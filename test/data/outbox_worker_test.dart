import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_entry.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_store.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_worker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _me = '@me:example.org';
const _roomA = '!a:example.org';
const _roomB = '!b:example.org';

/// The homeserver's side: one event per (device, transaction ID), as
/// Synapse deduplicates within 24 hours.
class _FakeServer {
  final events = <String, String>{};

  String receive(String deviceId, String txnId) =>
      events.putIfAbsent('$deviceId|$txnId', () => '\$event${events.length}');

  int get created => events.length;
}

/// What one `send` call does.
sealed class _Step {
  const _Step();
}

class _Ok extends _Step {
  const _Ok();
}

/// The server stores the event but the response never arrives.
class _LostResponse extends _Step {
  const _LostResponse();
}

/// The server stores the event and the request never finishes (the app is
/// killed while waiting).
class _Hang extends _Step {
  const _Hang();
}

class _Fail extends _Step {
  const _Fail(this.error);

  final OutboxSendError error;
}

class _FakeTransport implements OutboxTransport {
  _FakeTransport(this.server, {String deviceId = 'DEVICE'})
    : account = (userId: _me, deviceId: deviceId);

  final _FakeServer server;

  @override
  ({String userId, String deviceId})? account;

  @override
  bool online = true;

  final plan = <_Step>[];
  final sent = <String>[];
  final shownSent = <String>[];
  final removedEchoes = <String>[];

  /// Transaction IDs whose events reached this device through sync.
  final syncedLocally = <String>{};

  /// Result of a deep search (history back to the first attempt).
  bool? deepResult = false;
  SendErrorClass? cannotSend;
  int refreshes = 0;
  int forcedRefreshes = 0;

  @override
  void checkCanSend(String roomId) {
    final reason = cannotSend;
    if (reason != null) throw OutboxSendError(reason);
  }

  @override
  Future<void> ensureFreshToken({bool force = false}) async {
    refreshes++;
    if (force) forcedRefreshes++;
  }

  @override
  Future<bool?> findDelivered(OutboxEntry entry, {bool deep = false}) async {
    if (syncedLocally.contains(entry.txnId)) return true;
    return deep ? deepResult : false;
  }

  @override
  Future<void> removeEcho(OutboxEntry entry) async =>
      removedEchoes.add(entry.txnId);

  @override
  Future<Map<String, Object?>> prepare(
    OutboxEntry entry,
    Uint8List? file,
  ) async => {
    'msgtype': 'm.text',
    'body': entry.text ?? '',
    if (file != null) 'size': file.length,
  };

  @override
  Future<String> send(OutboxEntry entry, Map<String, Object?> content) async {
    sent.add(entry.txnId);
    final step = plan.isEmpty ? const _Ok() : plan.removeAt(0);
    switch (step) {
      case _Fail(:final error):
        throw error;
      case _LostResponse():
        server.receive(account!.deviceId, entry.txnId);
        throw const OutboxSendError(SendErrorClass.network);
      case _Hang():
        server.receive(account!.deviceId, entry.txnId);
        return Completer<String>().future;
      case _Ok():
        return server.receive(account!.deviceId, entry.txnId);
    }
  }

  @override
  Future<void> showSent(
    OutboxEntry entry,
    Map<String, Object?> content,
    String eventId,
  ) async => shownSent.add(entry.txnId);
}

/// Lets queued microtasks and awaited futures run.
Future<void> _settle() async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Database database;
  late SqliteOutboxStore store;
  late _FakeServer server;
  late _FakeTransport transport;
  late DateTime now;
  final workers = <OutboxWorker>[];

  OutboxWorker newWorker(_FakeTransport transport) {
    final worker = OutboxWorker(
      store: store,
      transport: transport,
      clock: () => now,
      random: Random(1),
    );
    workers.add(worker);
    return worker;
  }

  OutboxEntry entry(
    String txnId, {
    String room = _roomA,
    String deviceId = 'DEVICE',
    int attempts = 0,
    DateTime? firstAttemptAt,
  }) => OutboxEntry(
    txnId: txnId,
    userId: _me,
    deviceId: deviceId,
    roomId: room,
    kind: OutboxKind.text,
    payload: {'body': 'message $txnId'},
    createdAt: now,
    attempts: attempts,
    firstAttemptAt: firstAttemptAt,
    lastAttemptAt: firstAttemptAt,
  );

  /// Moves past every scheduled retry and runs the worker again.
  Future<void> later(
    OutboxWorker worker, [
    Duration by = const Duration(minutes: 6),
  ]) async {
    now = now.add(by);
    worker.kick();
    await _settle();
  }

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    store = await SqliteOutboxStore.open(database);
    server = _FakeServer();
    transport = _FakeTransport(server);
    now = DateTime(2026, 10, 26, 12);
  });

  tearDown(() async {
    for (final worker in workers) {
      worker.stop();
    }
    workers.clear();
    await database.close();
  });

  test('sends a queued message once and removes it', () async {
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();

    expect(transport.sent, ['t1']);
    expect(transport.shownSent, ['t1']);
    expect(server.created, 1);
    expect(worker.entries, isEmpty);
    expect(await store.entriesFor(_me), isEmpty);
  });

  test('retries network failures with the same transaction ID', () async {
    transport.plan.addAll(const [
      _Fail(OutboxSendError(SendErrorClass.network)),
      _Fail(OutboxSendError(SendErrorClass.network)),
    ]);
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();

    final waiting = worker.entry('t1')!;
    expect(waiting.state, OutboxState.queued);
    expect(waiting.lastError, SendErrorClass.network);
    expect(waiting.nextAttemptAt!.isAfter(now), isTrue);

    await later(worker);
    await later(worker);

    expect(transport.sent, ['t1', 't1', 't1']);
    expect(server.created, 1);
    expect(worker.entries, isEmpty);
  });

  test('a lost response does not create a duplicate', () async {
    transport.plan.add(const _LostResponse());
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();
    expect(worker.entry('t1')?.attempts, 1);

    await later(worker);

    expect(transport.sent, ['t1', 't1']);
    expect(server.created, 1);
    expect(worker.entries, isEmpty);
  });

  test(
    'a delivery seen in sync completes the message without resending',
    () async {
      transport.plan.add(const _LostResponse());
      final worker = newWorker(transport);
      await worker.start();
      await worker.enqueue(entry('t1'));
      await _settle();

      await worker.markDelivered('t1');
      await later(worker);

      expect(transport.sent, ['t1']);
      expect(worker.entries, isEmpty);
    },
  );

  test('waits while offline and sends when the connection is back', () async {
    transport.online = false;
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();
    expect(transport.sent, isEmpty);

    transport.online = true;
    worker.networkRestored();
    await _settle();

    expect(transport.sent, ['t1']);
    expect(worker.entries, isEmpty);
  });

  test(
    'refreshes an expired token, then retries at once with the same ID',
    () async {
      transport.plan.add(
        const _Fail(OutboxSendError(SendErrorClass.tokenExpired)),
      );
      final worker = newWorker(transport);
      await worker.start();
      await worker.enqueue(entry('t1'));
      await _settle();

      // No clock change: the retry follows the refresh immediately.
      worker.kick();
      await _settle();

      expect(transport.forcedRefreshes, 1);
      expect(transport.sent, ['t1', 't1']);
      expect(server.created, 1);
      expect(worker.entries, isEmpty);
    },
  );

  test(
    'a rate limit holds back every conversation until retry_after',
    () async {
      transport.plan.add(
        const _Fail(
          OutboxSendError(
            SendErrorClass.rateLimited,
            retryAfter: Duration(seconds: 30),
          ),
        ),
      );
      final worker = newWorker(transport);
      await worker.start();
      await worker.enqueue(entry('a1'));
      await _settle();
      await worker.enqueue(entry('b1', room: _roomB));
      await _settle();
      expect(transport.sent, ['a1']);

      await later(worker, const Duration(seconds: 10));
      expect(transport.sent, ['a1']);

      await later(worker, const Duration(seconds: 25));
      expect(transport.sent, unorderedEquals(['a1', 'a1', 'b1']));
      expect(worker.entries, isEmpty);
    },
  );

  test('keeps order within a conversation; others are not held back', () async {
    transport.plan.add(const _Fail(OutboxSendError(SendErrorClass.network)));
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('a1'));
    await worker.enqueue(entry('a2'));
    await worker.enqueue(entry('b1', room: _roomB));
    await _settle();

    expect(transport.sent, containsAll(['a1', 'b1']));
    expect(transport.sent, isNot(contains('a2')));

    await later(worker);
    expect(transport.sent.where((t) => t != 'b1'), ['a1', 'a1', 'a2']);
    expect(worker.entries, isEmpty);
  });

  test('stops on a permanent failure and keeps the message', () async {
    transport.cannotSend = SendErrorClass.notAllowed;
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();
    await later(worker);

    final failed = worker.entry('t1')!;
    expect(failed.state, OutboxState.failed);
    expect(failed.lastError, SendErrorClass.notAllowed);
    expect(transport.sent, isEmpty);
  });

  test('gives up after repeated server errors', () async {
    for (var i = 0; i < maxServerFailures; i++) {
      transport.plan.add(const _Fail(OutboxSendError(SendErrorClass.server)));
    }
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();
    for (var i = 0; i < maxServerFailures; i++) {
      await later(worker);
    }

    expect(transport.sent, hasLength(maxServerFailures));
    expect(worker.entry('t1')?.state, OutboxState.failed);
    expect(worker.entry('t1')?.lastError, SendErrorClass.server);
  });

  test('a manual retry resets the failure and sends again', () async {
    transport.cannotSend = SendErrorClass.encryptionUnavailable;
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();
    expect(worker.entry('t1')?.state, OutboxState.failed);

    transport.cannotSend = null;
    await worker.retry('t1');
    await _settle();

    expect(transport.sent, ['t1']);
    expect(worker.entries, isEmpty);
  });

  test('a lost session keeps the message for the next sign-in', () async {
    transport.plan.add(
      const _Fail(OutboxSendError(SendErrorClass.sessionLost)),
    );
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();

    final kept = worker.entry('t1')!;
    expect(kept.state, OutboxState.queued);
    expect(kept.lastError, SendErrorClass.sessionLost);
    expect(transport.sent, ['t1']);

    // Signing in again resumes it without waiting for the backoff.
    worker.stop();
    await worker.start();
    await _settle();
    expect(transport.sent, ['t1', 't1']);
    expect(worker.entries, isEmpty);
  });

  group('after a restart', () {
    test('an attempt that came back through sync is not resent', () async {
      transport.plan.add(const _Hang());
      final first = newWorker(transport);
      await first.start();
      await first.enqueue(entry('t1'));
      await _settle();
      // The app is killed while the request is open.
      first.stop();
      expect((await store.entriesFor(_me)).single.attempts, 1);

      final restarted = _FakeTransport(server)..syncedLocally.add('t1');
      final second = newWorker(restarted);
      await second.start();
      await _settle();

      expect(restarted.sent, isEmpty);
      expect(second.entries, isEmpty);
    });

    test('an unconfirmed attempt is resent with the same ID', () async {
      transport.plan.add(const _Hang());
      final first = newWorker(transport);
      await first.start();
      await first.enqueue(entry('t1'));
      await _settle();
      first.stop();

      final restarted = _FakeTransport(server);
      final second = newWorker(restarted);
      await second.start();
      await _settle();

      expect(restarted.sent, ['t1']);
      expect(server.created, 1);
      expect(second.entries, isEmpty);
    });

    test('attachments survive in the store', () async {
      transport.online = false;
      final first = newWorker(transport);
      await first.start();
      await first.enqueue(
        OutboxEntry(
          txnId: 'f1',
          userId: _me,
          deviceId: 'DEVICE',
          roomId: _roomA,
          kind: OutboxKind.file,
          payload: const {'name': 'a.bin'},
          createdAt: now,
          hasFile: true,
        ),
        file: Uint8List.fromList([1, 2, 3]),
      );
      first.stop();

      final second = newWorker(_FakeTransport(server));
      await second.start();
      await _settle();

      expect(server.created, 1);
      expect(await store.file('f1'), isNull);
    });
  });

  group('after signing in as a new device', () {
    test('never-attempted messages are adopted and sent', () async {
      await store.add(entry('t1', deviceId: 'OLD'));
      final worker = newWorker(transport);
      await worker.start();
      await _settle();

      expect(transport.sent, ['t1']);
      expect(worker.entries, isEmpty);
    });

    test(
      'attempted messages become uncertain until the user decides',
      () async {
        await store.add(
          entry('t1', deviceId: 'OLD', attempts: 1, firstAttemptAt: now),
        );
        final worker = newWorker(transport);
        await worker.start();
        await _settle();

        expect(transport.sent, isEmpty);
        expect(worker.entry('t1')?.state, OutboxState.failed);
        expect(worker.entry('t1')?.lastError, SendErrorClass.uncertain);

        await worker.retry('t1', newTxnId: 't1-again');
        await _settle();

        expect(transport.sent, ['t1-again']);
        expect(transport.removedEchoes, ['t1']);
        expect(worker.entries, isEmpty);
      },
    );
  });

  group('older than the deduplication window', () {
    OutboxEntry old() => entry(
      't1',
      attempts: 1,
      firstAttemptAt: now.subtract(const Duration(hours: 25)),
    );

    test('a delivered message is found, not resent', () async {
      await store.add(old());
      transport.deepResult = true;
      final worker = newWorker(transport);
      await worker.start();
      await _settle();

      expect(transport.sent, isEmpty);
      expect(worker.entries, isEmpty);
    });

    test('a message that never arrived is sent', () async {
      await store.add(old());
      transport.deepResult = false;
      final worker = newWorker(transport);
      await worker.start();
      await _settle();

      expect(transport.sent, ['t1']);
      expect(worker.entries, isEmpty);
    });

    test('when history cannot tell, the user decides', () async {
      await store.add(old());
      transport.deepResult = null;
      final worker = newWorker(transport);
      await worker.start();
      await _settle();

      expect(transport.sent, isEmpty);
      expect(worker.entry('t1')?.lastError, SendErrorClass.uncertain);
    });
  });

  test('discard is refused while the message is being sent', () async {
    transport.plan.add(const _Hang());
    final worker = newWorker(transport);
    await worker.start();
    await worker.enqueue(entry('t1'));
    await _settle();

    expect(worker.isInFlight('t1'), isTrue);
    expect(await worker.discard('t1'), isFalse);
  });

  test('entries of another account are not loaded', () async {
    await store.add(
      OutboxEntry(
        txnId: 'other',
        userId: '@someone:example.org',
        deviceId: 'DEVICE',
        roomId: _roomA,
        kind: OutboxKind.text,
        payload: const {'body': 'x'},
        createdAt: now,
      ),
    );
    final worker = newWorker(transport);
    await worker.start();
    await _settle();

    expect(worker.entries, isEmpty);
    expect(transport.sent, isEmpty);
  });

  test('retry delay grows from about 2 seconds to at most 5 minutes', () {
    final random = Random(1);
    final first = retryDelay(1, random: random);
    expect(first.inMilliseconds, inInclusiveRange(1600, 2400));
    final capped = retryDelay(30, random: random);
    expect(capped.inSeconds, inInclusiveRange(240, 360));
  });
}
