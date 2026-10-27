import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'outbox_entry.dart';
import 'outbox_store.dart';

/// The server deduplicates a transaction ID for 24 hours, per device and
/// room. Before resending an attempt older than this, the worker first looks
/// for the delivered event.
const reconcileAfter = Duration(hours: 23);

/// Non-network failures in a row before an entry stops and asks the user.
const maxServerFailures = 8;

/// Capped exponential backoff with jitter: about 2 s, 4 s, 8 s ... 5 min.
Duration retryDelay(int failuresInARow, {Random? random}) {
  const baseMs = 2000;
  const capMs = 5 * 60 * 1000;
  final exponent = min(max(failuresInARow - 1, 0), 20);
  final delayMs = min(baseMs * pow(2, exponent).toInt(), capMs);
  final jitter = 0.8 + (random ?? Random()).nextDouble() * 0.4;
  return Duration(milliseconds: (delayMs * jitter).round());
}

enum OutboxDecision {
  /// Send with the entry's transaction ID.
  send,

  /// Never attempted by the device that queued it (for example before a
  /// re-login): safe to send from this device.
  adopt,

  /// The first attempt is older than the server's deduplication window:
  /// look for the delivered event first.
  reconcile,

  /// Attempted from another device, whose transaction IDs this device can
  /// neither reuse nor look up. Only the user can decide.
  uncertain,
}

OutboxDecision decide(
  OutboxEntry entry, {
  required String deviceId,
  required DateTime now,
}) {
  if (entry.deviceId != deviceId) {
    return entry.attempts == 0
        ? OutboxDecision.adopt
        : OutboxDecision.uncertain;
  }
  final first = entry.firstAttemptAt;
  if (entry.attempts > 0 &&
      first != null &&
      now.difference(first) > reconcileAfter) {
    return OutboxDecision.reconcile;
  }
  return OutboxDecision.send;
}

/// What the worker needs from the Matrix side. Every method reports
/// failures as [OutboxSendError].
abstract interface class OutboxTransport {
  /// The signed-in account, or null.
  ({String userId, String deviceId})? get account;

  /// False while the sync loop reports no connection.
  bool get online;

  /// Throws when the room can no longer receive messages from this device.
  void checkCanSend(String roomId);

  /// Refreshes the access token if it is about to expire, or always when
  /// [force] is set. Shares the refresh with the sync loop.
  Future<void> ensureFreshToken({bool force = false});

  /// Whether this device already delivered the entry's transaction ID: the
  /// server shows `unsigned.transaction_id` to the sending device. With
  /// [deep], also searches history back to the first attempt and returns
  /// null when that was not possible.
  Future<bool?> findDelivered(OutboxEntry entry, {bool deep = false});

  /// Removes a local echo the SDK may still hold for this transaction ID
  /// (left by an earlier version of the app). Queued entries themselves are
  /// shown from the outbox, not from the SDK store.
  Future<void> removeEcho(OutboxEntry entry);

  /// Uploads attachments (encrypted) and returns the event content.
  Future<Map<String, Object?>> prepare(OutboxEntry entry, Uint8List? file);

  /// Encrypts and sends the event with the entry's transaction ID; returns
  /// the server's event ID.
  Future<String> send(OutboxEntry entry, Map<String, Object?> content);
  Future<void> showSent(
    OutboxEntry entry,
    Map<String, Object?> content,
    String eventId,
  );
}

/// App-wide sender for pending messages. Runs while the app runs: on start,
/// on reconnect, after a token refresh, when a message is queued, and on a
/// backoff timer. Rooms are independent; within a room, messages go out in
/// the order they were written. It never gives up silently: an entry either
/// gets sent or ends up "failed" with a reason.
class OutboxWorker {
  OutboxWorker({
    required OutboxStore store,
    required OutboxTransport transport,
    DateTime Function()? clock,
    Random? random,
    void Function(String message)? log,
  }) : _store = store,
       _transport = transport,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random(),
       _log = log;

  final OutboxStore _store;
  final OutboxTransport _transport;
  final DateTime Function() _clock;
  final Random _random;
  final void Function(String message)? _log;

  final _changes = StreamController<void>.broadcast();
  List<OutboxEntry> _entries = [];
  String? _loadedFor;
  final _inFlight = <String>{};
  final _draining = <String>{};
  Timer? _timer;
  DateTime? _rateLimitedUntil;
  bool _running = false;
  bool _kickScheduled = false;

  /// Emits whenever an entry is added, changes state or is removed.
  Stream<void> get changes => _changes.stream;

  List<OutboxEntry> get entries => List.unmodifiable(_entries);

  List<OutboxEntry> entriesForRoom(String roomId) =>
      _entries.where((entry) => entry.roomId == roomId).toList();

  OutboxEntry? entry(String txnId) =>
      _entries.where((entry) => entry.txnId == txnId).firstOrNull;

  bool isInFlight(String txnId) => _inFlight.contains(txnId);

  /// Loads the signed-in account's entries and starts sending.
  Future<void> start() async {
    final account = _transport.account;
    if (account == null) return;
    if (_loadedFor != account.userId) {
      _entries = await _store.entriesFor(account.userId);
      _loadedFor = account.userId;
    }
    // Signed in again: what waited for a session can go now.
    final now = _clock();
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.state == OutboxState.queued &&
          entry.lastError == SendErrorClass.sessionLost) {
        _entries[i] = entry.copyWith(nextAttemptAt: now, failuresInARow: 0);
      }
    }
    _running = true;
    _notify();
    kick();
  }

  /// Stops sending (signed out or session lost). Entries stay stored.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Forgets the in-memory state after the store was deleted.
  void reset() {
    stop();
    _entries = [];
    _loadedFor = null;
    _rateLimitedUntil = null;
    _notify();
  }

  /// Persists [entry] before anything is sent, then sends it.
  Future<void> enqueue(OutboxEntry entry, {Uint8List? file}) async {
    await _store.add(entry, file: file);
    _entries.add(entry);
    _notify();
    kick();
  }

  /// Retries a failed entry. With [newTxnId] (for an uncertain entry the user
  /// chose to send again), it becomes a new message from this device.
  Future<void> retry(String txnId, {String? newTxnId}) async {
    final existing = entry(txnId);
    final account = _transport.account;
    if (existing == null || account == null || isInFlight(txnId)) return;
    var updated = existing.copyWith(
      state: OutboxState.queued,
      failuresInARow: 0,
      nextAttemptAt: _clock(),
      clearLastError: true,
    );
    if (newTxnId != null) {
      updated = updated.copyWith(
        txnId: newTxnId,
        deviceId: account.deviceId,
        attempts: 0,
        clearFirstAttempt: true,
      );
      await _quietly(() => _transport.removeEcho(existing));
      await _store.rename(txnId, updated);
    } else {
      await _store.update(updated);
    }
    _replace(txnId, updated);
    _notify();
    kick();
  }

  /// Deletes an entry that is not being sent right now.
  Future<bool> discard(String txnId) async {
    final existing = entry(txnId);
    if (existing == null || isInFlight(txnId)) return false;
    await _store.remove(txnId);
    _entries.removeWhere((entry) => entry.txnId == txnId);
    _notify();
    await _quietly(() => _transport.removeEcho(existing));
    return true;
  }

  Future<Uint8List?> file(String txnId) => _store.file(txnId);

  /// Sync showed an event with this transaction ID from this device: an
  /// earlier attempt was delivered even though its response was lost.
  Future<void> markDelivered(String txnId) async {
    final existing = entry(txnId);
    final account = _transport.account;
    if (existing == null ||
        account == null ||
        existing.deviceId != account.deviceId ||
        isInFlight(txnId)) {
      return;
    }
    _log?.call('outbox ${_short(txnId)}: delivered earlier');
    await _complete(existing);
  }

  /// The connection is back: retry entries that were waiting for it now.
  void networkRestored() {
    final now = _clock();
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      if (entry.state == OutboxState.queued &&
          (entry.lastError == SendErrorClass.network ||
              entry.lastError == SendErrorClass.server)) {
        _entries[i] = entry.copyWith(nextAttemptAt: now, failuresInARow: 0);
      }
    }
    _notify();
    kick();
  }

  /// The connection was lost: queued messages now show as waiting for it.
  void connectionLost() {
    _notify();
    _scheduleTimer();
  }

  void kick() {
    if (_kickScheduled || !_running) return;
    _kickScheduled = true;
    scheduleMicrotask(() {
      _kickScheduled = false;
      _run();
    });
  }

  void _run() {
    if (!_running) return;
    final account = _transport.account;
    if (account == null || account.userId != _loadedFor) return;
    if (_transport.online) {
      final rooms = {
        for (final entry in _entries)
          if (entry.state == OutboxState.queued) entry.roomId,
      };
      for (final room in rooms) {
        if (_draining.add(room)) unawaited(_drain(room));
      }
    }
    _scheduleTimer();
  }

  Future<void> _drain(String roomId) async {
    try {
      while (_running && _transport.online) {
        final next = _entries
            .where(
              (entry) =>
                  entry.roomId == roomId && entry.state == OutboxState.queued,
            )
            .firstOrNull;
        if (next == null) break;
        final now = _clock();
        final waitUntil = next.nextAttemptAt;
        final limitedUntil = _rateLimitedUntil;
        if ((waitUntil != null && waitUntil.isAfter(now)) ||
            (limitedUntil != null && limitedUntil.isAfter(now))) {
          break;
        }
        await _attempt(next);
        // A message still waiting to be retried holds back the ones after
        // it, so the room keeps its order.
        if (entry(next.txnId)?.state == OutboxState.queued) break;
      }
    } finally {
      _draining.remove(roomId);
      _scheduleTimer();
    }
  }

  Future<void> _attempt(OutboxEntry entry) async {
    final account = _transport.account;
    if (account == null) return;
    var current = entry;
    _inFlight.add(current.txnId);
    _notify();
    try {
      switch (decide(current, deviceId: account.deviceId, now: _clock())) {
        case OutboxDecision.uncertain:
          await _fail(current, SendErrorClass.uncertain);
          return;
        case OutboxDecision.adopt:
          current = current.copyWith(deviceId: account.deviceId);
          await _save(current);
        case OutboxDecision.reconcile:
          final delivered = await _transport.findDelivered(current, deep: true);
          if (delivered == true) {
            await _complete(current);
            return;
          }
          if (delivered == null) {
            await _fail(current, SendErrorClass.uncertain);
            return;
          }
          // Not delivered: the server keeps no record of the transaction
          // any more, so this is a first attempt again.
          current = current.copyWith(attempts: 0, clearFirstAttempt: true);
          await _save(current);
        case OutboxDecision.send:
          break;
      }

      _transport.checkCanSend(current.roomId);
      if (current.attempts > 0 &&
          await _transport.findDelivered(current) == true) {
        await _complete(current);
        return;
      }
      await _transport.ensureFreshToken();

      var content = current.preparedContent;
      if (content == null) {
        final file = current.hasFile ? await _store.file(current.txnId) : null;
        if (current.hasFile && file == null) {
          throw const OutboxSendError(SendErrorClass.rejected);
        }
        content = await _transport.prepare(current, file);
        current = current.copyWith(preparedContent: content);
        await _save(current);
      }

      // Recorded before the request: if the app dies mid-request, the
      // message counts as possibly delivered.
      final now = _clock();
      current = current.copyWith(
        attempts: current.attempts + 1,
        firstAttemptAt: current.firstAttemptAt ?? now,
        lastAttemptAt: now,
      );
      await _save(current);

      final eventId = await _transport.send(current, content);
      _log?.call('outbox ${_short(current.txnId)}: sent');
      await _quietly(() => _transport.showSent(current, content!, eventId));
      await _complete(current);
    } on OutboxSendError catch (error) {
      await _handleFailure(current, error);
    } catch (_) {
      await _handleFailure(
        current,
        const OutboxSendError(SendErrorClass.server),
      );
    } finally {
      _inFlight.remove(current.txnId);
      _notify();
    }
  }

  Future<void> _handleFailure(OutboxEntry entry, OutboxSendError error) async {
    final errorClass = error.errorClass;
    _log?.call(
      'outbox ${_short(entry.txnId)}: attempt ${entry.attempts} '
      'failed (${errorClass.name})',
    );
    if (isPermanent(errorClass)) {
      await _fail(entry, errorClass);
      return;
    }
    final now = _clock();
    final failures = entry.failuresInARow + 1;
    var next = now.add(retryDelay(failures, random: _random));
    switch (errorClass) {
      case SendErrorClass.tokenExpired:
        // Refresh through the shared path, then retry the same transaction
        // ID at once. A second expiry in a row backs off.
        await _quietly(() => _transport.ensureFreshToken(force: true));
        if (failures <= 1) next = now;
      case SendErrorClass.rateLimited:
        final wait = error.retryAfter ?? retryDelay(failures, random: _random);
        next = now.add(
          wait < const Duration(seconds: 1) ? const Duration(seconds: 1) : wait,
        );
        // The limit is per user, not per room.
        _rateLimitedUntil = next;
      case SendErrorClass.server when failures >= maxServerFailures:
        await _fail(entry, SendErrorClass.server);
        return;
      case SendErrorClass.sessionLost:
        // Kept for after the next sign-in (start() resumes it), which
        // decides how to resend it. Until then it waits like any failure.
        break;
      default:
        break;
    }
    await _save(
      entry.copyWith(
        failuresInARow: failures,
        lastError: errorClass,
        nextAttemptAt: next,
      ),
    );
  }

  Future<void> _fail(OutboxEntry entry, SendErrorClass errorClass) async {
    final failed = entry.copyWith(
      state: OutboxState.failed,
      lastError: errorClass,
    );
    await _save(failed);
    _log?.call('outbox ${_short(entry.txnId)}: stopped (${errorClass.name})');
  }

  Future<void> _complete(OutboxEntry entry) async {
    await _store.remove(entry.txnId);
    _entries.removeWhere((existing) => existing.txnId == entry.txnId);
    _notify();
  }

  Future<void> _save(OutboxEntry entry) async {
    await _store.update(entry);
    _replace(entry.txnId, entry);
    _notify();
  }

  void _replace(String txnId, OutboxEntry entry) {
    final index = _entries.indexWhere((existing) => existing.txnId == txnId);
    if (index >= 0) _entries[index] = entry;
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    final now = _clock();
    DateTime? earliest;
    for (final entry in _entries) {
      if (entry.state != OutboxState.queued) continue;
      final at = entry.nextAttemptAt ?? now;
      if (earliest == null || at.isBefore(earliest)) earliest = at;
    }
    if (earliest == null) return;
    final limitedUntil = _rateLimitedUntil;
    if (limitedUntil != null && limitedUntil.isAfter(earliest)) {
      earliest = limitedUntil;
    }
    var delay = earliest.difference(now);
    // While offline, the reconnect signal restarts sending; the timer is a
    // fallback in case that signal is missed.
    if (!_transport.online && delay < const Duration(seconds: 30)) {
      delay = const Duration(seconds: 30);
    }
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, kick);
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Echo updates are cosmetic; the stored entry is what counts.
    }
  }

  static String _short(String txnId) =>
      txnId.length <= 8 ? txnId : txnId.substring(0, 8);
}
