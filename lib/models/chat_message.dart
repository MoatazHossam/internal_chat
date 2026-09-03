enum MessageDeliveryStatus { pending, sent, delivered, read, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderDisplayName,
    required this.body,
    required this.sentAt,
    this.status = MessageDeliveryStatus.sent,
    this.replyToId,
    this.replyToSenderName,
    this.replyToBody,
    this.attachmentName,
    this.attachmentMimeType,
    this.attachmentDurationMs,
    this.attachmentLocalPath,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderDisplayName;
  final String body;
  final DateTime sentAt;
  final MessageDeliveryStatus status;
  final String? replyToId;
  final String? replyToSenderName;
  final String? replyToBody;
  final String? attachmentName;
  final String? attachmentMimeType;

  /// Voice-note duration. Only set when [attachmentMimeType] is an audio type.
  final int? attachmentDurationMs;

  /// Local playback source for a mock-recorded voice note. This is a
  /// mock-only staging field until a real attachment download-URL contract
  /// exists; it must not be treated as a durable server reference.
  final String? attachmentLocalPath;

  bool get hasReply => replyToId != null;
  bool get hasAttachment => attachmentName != null;
  bool get isVoiceNote => attachmentMimeType?.startsWith('audio/') ?? false;

  ChatMessage copyWith({
    String? id,
    MessageDeliveryStatus? status,
    String? replyToId,
    String? replyToSenderName,
    String? replyToBody,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        conversationId: conversationId,
        senderId: senderId,
        senderDisplayName: senderDisplayName,
        body: body,
        sentAt: sentAt,
        status: status ?? this.status,
        replyToId: replyToId ?? this.replyToId,
        replyToSenderName: replyToSenderName ?? this.replyToSenderName,
        replyToBody: replyToBody ?? this.replyToBody,
        attachmentName: attachmentName,
        attachmentMimeType: attachmentMimeType,
        attachmentDurationMs: attachmentDurationMs,
        attachmentLocalPath: attachmentLocalPath,
      );
}
