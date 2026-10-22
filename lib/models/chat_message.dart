import '../domain/ids.dart';

/// Matrix has read receipts ("read up to here") but no delivery receipts, so
/// there is deliberately no "delivered" state.
enum MessageDeliveryStatus { pending, sent, read, failed }

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
    this.localId,
    this.edited = false,
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

  /// Set for messages sent from this device.
  final LocalMessageId? localId;
  final bool edited;
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
  bool get isPending => status == MessageDeliveryStatus.pending;
  bool get isFailed => status == MessageDeliveryStatus.failed;
}
