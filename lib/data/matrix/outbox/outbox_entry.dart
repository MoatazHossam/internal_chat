import 'dart:convert';

enum OutboxKind { text, file, voice, forward }

/// Sent entries are deleted, so only these two states are stored.
enum OutboxState {
  /// Waiting for its next attempt (or being attempted).
  queued,

  /// Stopped; needs a decision from the user (retry, send again or delete).
  failed,
}

/// Why the last attempt did not deliver the message. Only classes and codes
/// are kept: never content or server text.
enum SendErrorClass {
  /// No connection, DNS failure, timeout. Retried with backoff.
  network,

  /// `5xx` or an unexplained failure. Retried with backoff, then stopped.
  server,

  /// `429 M_LIMIT_EXCEEDED`. Retried after `retry_after_ms`.
  rateLimited,

  /// `401 M_UNKNOWN_TOKEN` with `soft_logout`. Refresh, then retry.
  tokenExpired,

  /// The session is gone (refresh failed or hard logout). Kept for later.
  sessionLost,

  /// `403`: not (or no longer) a member, or not allowed to post.
  notAllowed,

  /// `413` / `M_TOO_LARGE` / above the server's upload limit.
  tooLarge,

  /// The room is not end-to-end encrypted.
  notEncrypted,

  /// Encryption is not running on this device.
  encryptionUnavailable,

  /// The server rejected the request for another reason (`4xx`).
  rejected,

  /// It cannot be ruled out that an earlier attempt was delivered, and the
  /// server would no longer deduplicate a resend.
  uncertain,
}

bool isPermanent(SendErrorClass errorClass) => switch (errorClass) {
  SendErrorClass.notAllowed ||
  SendErrorClass.tooLarge ||
  SendErrorClass.notEncrypted ||
  SendErrorClass.encryptionUnavailable ||
  SendErrorClass.rejected ||
  SendErrorClass.uncertain => true,
  SendErrorClass.network ||
  SendErrorClass.server ||
  SendErrorClass.rateLimited ||
  SendErrorClass.tokenExpired ||
  SendErrorClass.sessionLost => false,
};

/// Thrown by an [OutboxTransport] with the class of a failed step.
class OutboxSendError implements Exception {
  const OutboxSendError(this.errorClass, {this.retryAfter});

  final SendErrorClass errorClass;
  final Duration? retryAfter;

  @override
  String toString() => 'OutboxSendError($errorClass)';
}

/// One message waiting to be sent. Its transaction ID is derived from the
/// LocalMessageId created when the user tapped send, and is reused on every
/// retry from the same device so the server deduplicates.
class OutboxEntry {
  const OutboxEntry({
    required this.txnId,
    required this.userId,
    required this.deviceId,
    required this.roomId,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.hasFile = false,
    this.state = OutboxState.queued,
    this.attempts = 0,
    this.failuresInARow = 0,
    this.firstAttemptAt,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastError,
    this.preparedContent,
  });

  final String txnId;
  final String userId;

  /// The device whose transaction-ID scope [txnId] belongs to.
  final String deviceId;
  final String roomId;
  final OutboxKind kind;

  /// What to send: text and reply target, file metadata, or the content to
  /// forward. Never logged.
  final Map<String, Object?> payload;
  final DateTime createdAt;

  /// Whether the original file bytes are stored with this entry.
  final bool hasFile;
  final OutboxState state;

  /// Number of times the event itself was sent to the server. Uploads do not
  /// count: they cannot create a message.
  final int attempts;

  /// Consecutive failed tries of any kind, for backoff.
  final int failuresInARow;
  final DateTime? firstAttemptAt;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;
  final SendErrorClass? lastError;

  /// The event content once attachments are uploaded, so a retry of the
  /// event does not upload again. Contains the attachment's key; it lives
  /// only in the encrypted store.
  final Map<String, Object?>? preparedContent;

  String? get text => payload['body'] as String?;
  String? get replyTo => payload['replyTo'] as String?;
  String? get fileName => payload['name'] as String?;
  String? get mimeType => payload['mimeType'] as String?;
  int? get durationMs => payload['durationMs'] as int?;
  Map<String, Object?>? get forwardContent =>
      (payload['content'] as Map?)?.cast<String, Object?>();

  OutboxEntry copyWith({
    String? txnId,
    String? deviceId,
    OutboxState? state,
    int? attempts,
    int? failuresInARow,
    DateTime? firstAttemptAt,
    DateTime? lastAttemptAt,
    DateTime? nextAttemptAt,
    SendErrorClass? lastError,
    Map<String, Object?>? preparedContent,
    bool clearLastError = false,
    bool clearFirstAttempt = false,
    bool clearPreparedContent = false,
  }) => OutboxEntry(
    txnId: txnId ?? this.txnId,
    userId: userId,
    deviceId: deviceId ?? this.deviceId,
    roomId: roomId,
    kind: kind,
    payload: payload,
    createdAt: createdAt,
    hasFile: hasFile,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    failuresInARow: failuresInARow ?? this.failuresInARow,
    firstAttemptAt: clearFirstAttempt
        ? null
        : firstAttemptAt ?? this.firstAttemptAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastError: clearLastError ? null : lastError ?? this.lastError,
    preparedContent: clearPreparedContent
        ? null
        : preparedContent ?? this.preparedContent,
  );

  Map<String, Object?> toRow() => {
    'txn_id': txnId,
    'user_id': userId,
    'device_id': deviceId,
    'room_id': roomId,
    'kind': kind.name,
    'payload': jsonEncode(payload),
    'created_at': createdAt.millisecondsSinceEpoch,
    'has_file': hasFile ? 1 : 0,
    'state': state.name,
    'attempts': attempts,
    'failures_in_a_row': failuresInARow,
    'first_attempt_at': firstAttemptAt?.millisecondsSinceEpoch,
    'last_attempt_at': lastAttemptAt?.millisecondsSinceEpoch,
    'next_attempt_at': nextAttemptAt?.millisecondsSinceEpoch,
    'last_error': lastError?.name,
    'prepared_content': preparedContent == null
        ? null
        : jsonEncode(preparedContent),
  };

  static OutboxEntry fromRow(Map<String, Object?> row) {
    DateTime? time(String column) {
      final value = row[column] as int?;
      return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
    }

    final prepared = row['prepared_content'] as String?;
    final error = row['last_error'] as String?;
    return OutboxEntry(
      txnId: row['txn_id']! as String,
      userId: row['user_id']! as String,
      deviceId: row['device_id']! as String,
      roomId: row['room_id']! as String,
      kind: OutboxKind.values.byName(row['kind']! as String),
      payload: (jsonDecode(row['payload']! as String) as Map)
          .cast<String, Object?>(),
      createdAt: time('created_at')!,
      hasFile: row['has_file'] == 1,
      state: OutboxState.values.byName(row['state']! as String),
      attempts: row['attempts']! as int,
      failuresInARow: row['failures_in_a_row']! as int,
      firstAttemptAt: time('first_attempt_at'),
      lastAttemptAt: time('last_attempt_at'),
      nextAttemptAt: time('next_attempt_at'),
      lastError: error == null ? null : SendErrorClass.values.byName(error),
      preparedContent: prepared == null
          ? null
          : (jsonDecode(prepared) as Map).cast<String, Object?>(),
    );
  }
}
