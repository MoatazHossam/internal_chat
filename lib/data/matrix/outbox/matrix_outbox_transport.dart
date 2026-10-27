import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'outbox_entry.dart';
import 'outbox_worker.dart';

const _voiceKeys = ['org.matrix.msc3245.voice', 'org.matrix.msc1767.audio'];

/// Sends outbox entries with the Matrix client.
///
/// It does not use `Room.sendEvent`: that retries internally, hides why a
/// request failed and gives up on an expired token without refreshing. Here
/// every request runs once, under a time limit, and failures are reported
/// by class so the worker can decide what to do.
final class MatrixOutboxTransport implements OutboxTransport {
  MatrixOutboxTransport(this._client, {required bool Function() isOnline})
    : _isOnline = isOnline;

  final Client _client;
  final bool Function() _isOnline;

  static const _sendTimeout = Duration(seconds: 60);

  /// Upload time limit: a fixed part plus 64 KiB/s for the file.
  static Duration _uploadTimeout(int bytes) =>
      Duration(seconds: 60 + bytes ~/ (64 * 1024));

  /// History pages to search when reconciling an old attempt.
  static const _maxHistoryPages = 20;

  @override
  ({String userId, String deviceId})? get account {
    final userId = _client.userID;
    final deviceId = _client.deviceID;
    if (!_client.isLogged() || userId == null || deviceId == null) return null;
    return (userId: userId, deviceId: deviceId);
  }

  @override
  bool get online => _isOnline();

  @override
  void checkCanSend(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null || room.membership != Membership.join) {
      throw const OutboxSendError(SendErrorClass.notAllowed);
    }
    if (!_client.encryptionEnabled) {
      throw const OutboxSendError(SendErrorClass.encryptionUnavailable);
    }
    if (!room.encrypted) {
      throw const OutboxSendError(SendErrorClass.notEncrypted);
    }
  }

  @override
  Future<void> ensureFreshToken({bool force = false}) async {
    try {
      // The SDK shares one refresh between the sync loop and this call. A
      // very long window forces it.
      await _client.ensureNotSoftLoggedOut(
        force ? const Duration(days: 3650) : const Duration(minutes: 1),
      );
    } on MatrixException {
      // The refresh token was rejected; the SDK has cleared the session.
      throw const OutboxSendError(SendErrorClass.sessionLost);
    } catch (error) {
      throw classifySendError(error);
    }
    if (!_client.isLogged()) {
      throw const OutboxSendError(SendErrorClass.sessionLost);
    }
  }

  @override
  Future<bool?> findDelivered(OutboxEntry entry, {bool deep = false}) async {
    final room = _client.getRoomById(entry.roomId);
    if (room != null) {
      final events = await _client.database.getEventList(room, limit: 300);
      if (events.any((event) => _isDelivered(event.toJson(), entry))) {
        return true;
      }
    }
    if (!deep) return false;

    final since = entry.firstAttemptAt;
    if (since == null) return false;
    // Allows for clock differences between this device and the server.
    final searchUntil = since.subtract(const Duration(minutes: 10));
    final filter = jsonEncode({
      'senders': [entry.userId],
    });
    String? from;
    try {
      for (var page = 0; page < _maxHistoryPages; page++) {
        final response = await _client
            .getRoomEvents(
              entry.roomId,
              Direction.b,
              from: from,
              limit: 100,
              filter: filter,
            )
            .timeout(_sendTimeout);
        for (final event in response.chunk) {
          if (_isDelivered(event.toJson(), entry)) return true;
        }
        final oldest = response.chunk.lastOrNull;
        if (oldest == null ||
            response.end == null ||
            oldest.originServerTs.isBefore(searchUntil)) {
          return false;
        }
        from = response.end;
      }
    } catch (error) {
      throw classifySendError(error);
    }
    // Searched as far as allowed without reaching the first attempt.
    return null;
  }

  bool _isDelivered(Map<String, Object?> event, OutboxEntry entry) {
    final unsigned = event['unsigned'];
    return event['sender'] == entry.userId &&
        // A local echo uses the transaction ID as its event ID.
        event['event_id'] != entry.txnId &&
        unsigned is Map &&
        unsigned['transaction_id'] == entry.txnId &&
        unsigned[messageSendingStatusKey] != EventStatus.error.intValue &&
        unsigned[messageSendingStatusKey] != EventStatus.sending.intValue;
  }

  @override
  Future<void> removeEcho(OutboxEntry entry) async {
    final room = _client.getRoomById(entry.roomId);
    if (room == null) return;
    final event = await _client.database.getEventById(entry.txnId, room);
    if (event == null || event.status.isSent) return;
    await _client.database.removeEvent(entry.txnId, room.id);
    _client.onCancelSendEvent.add(entry.txnId);
  }

  @override
  Future<Map<String, Object?>> prepare(
    OutboxEntry entry,
    Uint8List? file,
  ) async {
    try {
      final reply = entry.replyTo;
      final relation = reply == null
          ? const <String, Object?>{}
          : {
              'm.relates_to': {
                'm.in_reply_to': {'event_id': reply},
              },
            };
      switch (entry.kind) {
        case OutboxKind.text:
          return {
            'msgtype': MessageTypes.Text,
            'body': entry.text ?? '',
            ...relation,
          };
        case OutboxKind.forward:
          return entry.forwardContent ??
              (throw const OutboxSendError(SendErrorClass.rejected));
        case OutboxKind.file:
          return {
            ...await _uploadMedia(
              MatrixFile.fromMimeType(
                bytes: file!,
                name: entry.fileName ?? 'file',
                mimeType: entry.mimeType,
              ),
            ),
            ...relation,
          };
        case OutboxKind.voice:
          final duration = entry.durationMs;
          return {
            ...await _uploadMedia(
              MatrixAudioFile(
                bytes: file!,
                name: entry.fileName ?? 'voice-message.m4a',
                mimeType: entry.mimeType ?? 'audio/mp4',
                duration: duration,
              ),
            ),
            // MSC3245 voice-message markers, as Element sends them.
            _voiceKeys[0]: <String, Object?>{},
            _voiceKeys[1]: {'duration': ?duration},
          };
      }
    } catch (error) {
      throw classifySendError(error);
    }
  }

  /// Encrypts the file (AES-256-CTR, new key per file) and its thumbnail,
  /// uploads both and returns the event content.
  Future<Map<String, Object?>> _uploadMedia(MatrixFile file) async {
    MatrixImageFile? thumbnail;
    if (file is MatrixImageFile) {
      try {
        thumbnail = await file.generateThumbnail(
          nativeImplementations: _client.nativeImplementations,
        );
      } catch (_) {
        thumbnail = null;
      }
      if (thumbnail != null && file.size < thumbnail.size) thumbnail = null;
    }
    final encrypted = await file.encrypt();
    final url = await _upload(encrypted, file.name);
    EncryptedFile? encryptedThumbnail;
    Uri? thumbnailUrl;
    if (thumbnail != null) {
      encryptedThumbnail = await thumbnail.encrypt();
      thumbnailUrl = await _upload(encryptedThumbnail, thumbnail.name);
    }
    return {
      'msgtype': file.msgType,
      'body': file.name,
      'filename': file.name,
      'file': _fileJson(url, file.mimeType, encrypted),
      'info': {
        ...file.info,
        if (thumbnail != null) ...{
          'thumbnail_file': _fileJson(
            thumbnailUrl!,
            thumbnail.mimeType,
            encryptedThumbnail!,
          ),
          'thumbnail_info': thumbnail.info,
          if (file is MatrixImageFile &&
              file.blurhash == null &&
              thumbnail.blurhash != null)
            'xyz.amorgan.blurhash': thumbnail.blurhash,
        },
      },
    };
  }

  Future<Uri> _upload(EncryptedFile encrypted, String name) {
    final upload = encrypted.toMatrixFile();
    return _client
        .uploadContent(
          upload.bytes,
          filename: name,
          contentType: upload.mimeType,
        )
        .timeout(_uploadTimeout(upload.bytes.length));
  }

  static Map<String, Object?> _fileJson(
    Uri url,
    String mimeType,
    EncryptedFile encrypted,
  ) => {
    'url': url.toString(),
    'mimetype': mimeType,
    'v': 'v2',
    'key': {
      'alg': 'A256CTR',
      'ext': true,
      'k': encrypted.k,
      'key_ops': ['encrypt', 'decrypt'],
      'kty': 'oct',
    },
    'iv': encrypted.iv,
    'hashes': {'sha256': encrypted.sha256},
  };

  @override
  Future<String> send(OutboxEntry entry, Map<String, Object?> content) async {
    final encryption = _client.encryption;
    if (encryption == null || !_client.encryptionEnabled) {
      throw const OutboxSendError(SendErrorClass.encryptionUnavailable);
    }
    try {
      final payload = await encryption
          .encryptGroupMessagePayload(entry.roomId, content)
          .timeout(_sendTimeout);
      // Never fall back to plaintext.
      if (!payload.containsKey('ciphertext')) {
        throw const OutboxSendError(SendErrorClass.encryptionUnavailable);
      }
      return await _client
          .sendMessage(entry.roomId, EventTypes.Encrypted, entry.txnId, payload)
          .timeout(_sendTimeout);
    } catch (error) {
      throw classifySendError(error);
    }
  }

  /// Stores the sent message as the SDK does after its own sends, so it
  /// stays visible until sync brings the server's copy (same event ID).
  @override
  Future<void> showSent(
    OutboxEntry entry,
    Map<String, Object?> content,
    String eventId,
  ) async {
    final room = _client.getRoomById(entry.roomId);
    if (room == null) return;
    final update = SyncUpdate(
      nextBatch: '',
      rooms: RoomsUpdate(
        join: {
          room.id: JoinedRoomUpdate(
            timeline: TimelineUpdate(
              events: [
                MatrixEvent(
                  content: content,
                  type: EventTypes.Message,
                  eventId: eventId,
                  senderId: entry.userId,
                  originServerTs: DateTime.now(),
                  unsigned: {
                    messageSendingStatusKey: EventStatus.sent.intValue,
                    'transaction_id': entry.txnId,
                  },
                ),
              ],
            ),
          ),
        },
      ),
    );
    await _client.database.transaction(() => _client.handleSync(update));
  }
}

/// Sorts what the SDK or the network threw into a [SendErrorClass]. Only the
/// class is kept, never server text.
OutboxSendError classifySendError(Object error) {
  switch (error) {
    case OutboxSendError():
      return error;
    case FileTooBigMatrixException() || EventTooLarge():
      return const OutboxSendError(SendErrorClass.tooLarge);
    case MatrixException():
      // The raw code: the SDK maps codes it does not know to M_UNKNOWN.
      return switch (error.errcode) {
        'M_LIMIT_EXCEEDED' => OutboxSendError(
          SendErrorClass.rateLimited,
          retryAfter: error.retryAfterMs == null
              ? null
              : Duration(milliseconds: error.retryAfterMs!),
        ),
        'M_UNKNOWN_TOKEN' =>
          error.raw['soft_logout'] == true
              ? const OutboxSendError(SendErrorClass.tokenExpired)
              : const OutboxSendError(SendErrorClass.sessionLost),
        'M_MISSING_TOKEN' => const OutboxSendError(SendErrorClass.sessionLost),
        'M_FORBIDDEN' => const OutboxSendError(SendErrorClass.notAllowed),
        'M_TOO_LARGE' => const OutboxSendError(SendErrorClass.tooLarge),
        // Synapse reports internal errors as M_UNKNOWN.
        'M_UNKNOWN' => const OutboxSendError(SendErrorClass.server),
        _ => const OutboxSendError(SendErrorClass.rejected),
      };
    case SocketException() ||
        HttpException() ||
        HandshakeException() ||
        http.ClientException() ||
        TimeoutException() ||
        SyncConnectionException():
      return const OutboxSendError(SendErrorClass.network);
    default:
      // Includes the SDK's "http error response" for non-JSON 5xx answers,
      // for example from a proxy.
      return const OutboxSendError(SendErrorClass.server);
  }
}
