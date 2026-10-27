import '../domain/ids.dart';

/// Matrix has read receipts ("read up to here") but no delivery receipts, so
/// there is deliberately no "delivered" state. A message is "sent" only once
/// the server returned its event ID.
enum MessageDeliveryStatus {
  /// Queued on this device and being sent, or about to be retried.
  pending,

  /// Queued on this device until the connection is back.
  waitingForNetwork,
  sent,
  read,

  /// Stopped; see [ChatMessage.failureReason]. The user can retry or delete.
  failed,
}

/// Why a message from this device stopped being sent.
enum SendFailureReason {
  /// Not (or no longer) a member, or not allowed to post.
  notAllowed,

  /// Above the server's size limit.
  tooLarge,

  /// The conversation is not end-to-end encrypted.
  notEncrypted,

  /// Encryption is not running on this device.
  encryptionUnavailable,

  /// The server rejected the message.
  rejected,

  /// The server kept failing.
  server,

  /// An earlier attempt may have arrived, and the server would no longer
  /// recognise a resend as the same message. Sending again may duplicate it.
  uncertain,

  /// Sent by an earlier version of the app; the attachment cannot be resent.
  notResendable,
}

enum MessageKind {
  text,
  image,
  file,
  voice,
  audio,

  /// Removed by its sender or a moderator (a redaction).
  deleted,

  /// Encrypted, but this device does not have the keys (yet).
  undecryptable,

  /// A message type this app does not render.
  unsupported,
}

class Reaction {
  const Reaction({
    required this.key,
    required this.count,
    required this.includesMe,
  });

  final String key;
  final int count;
  final bool includesMe;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderDisplayName,
    required this.body,
    required this.sentAt,
    this.kind = MessageKind.text,
    this.isOwn = false,
    this.status = MessageDeliveryStatus.sent,
    this.failureReason,
    this.localId,
    this.edited = false,
    this.forwarded = false,
    this.canEdit = false,
    this.canDelete = false,
    this.reactions = const [],
    this.replyToId,
    this.replyToSenderName,
    this.replyToBody,
    this.replyToKind,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentSizeBytes,
    this.attachmentDurationMs,
  });

  /// Server event ID, or the local ID while the message is still pending.
  final String id;
  final ConversationId conversationId;
  final UserId senderId;
  final String senderDisplayName;
  final String body;
  final DateTime sentAt;
  final MessageKind kind;
  final bool isOwn;
  final MessageDeliveryStatus status;

  /// Set when [status] is failed.
  final SendFailureReason? failureReason;

  /// Set for messages sent from this device.
  final LocalMessageId? localId;
  final bool edited;

  /// Marked as forwarded by the sending app. Says nothing reliable about
  /// where the message came from.
  final bool forwarded;
  final bool canEdit;
  final bool canDelete;
  final List<Reaction> reactions;

  final String? replyToId;
  final String? replyToSenderName;

  /// Null when the original message is not loaded on this device.
  final String? replyToBody;
  final MessageKind? replyToKind;

  final String? attachmentName;
  final String? attachmentMimeType;
  final int? attachmentSizeBytes;

  /// Only set for voice notes and audio.
  final int? attachmentDurationMs;

  MessageRef get ref => MessageRef(conversationId, id);

  bool get hasReply => replyToId != null;
  bool get hasAttachment => switch (kind) {
    MessageKind.image ||
    MessageKind.file ||
    MessageKind.voice ||
    MessageKind.audio => true,
    _ => false,
  };
  bool get isVoiceNote =>
      kind == MessageKind.voice || kind == MessageKind.audio;

  /// Not on the server yet (sending, or waiting for the connection).
  bool get isPending =>
      status == MessageDeliveryStatus.pending ||
      status == MessageDeliveryStatus.waitingForNetwork;
  bool get isFailed => status == MessageDeliveryStatus.failed;
  bool get isSent => !isPending && !isFailed;

  /// Sent messages with content this device can read.
  bool get canForward =>
      isSent &&
      switch (kind) {
        MessageKind.text ||
        MessageKind.image ||
        MessageKind.file ||
        MessageKind.voice ||
        MessageKind.audio => true,
        _ => false,
      };
}
