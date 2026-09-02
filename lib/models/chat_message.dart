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

  bool get hasReply => replyToId != null;
  bool get hasAttachment => attachmentName != null;

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
      );
}
