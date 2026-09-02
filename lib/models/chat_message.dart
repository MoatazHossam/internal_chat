enum MessageDeliveryStatus { pending, sent, delivered, read, failed }
class ChatMessage {
  const ChatMessage({required this.id, required this.conversationId, required this.senderId, required this.senderDisplayName, required this.body, required this.sentAt, this.status = MessageDeliveryStatus.sent});
  final String id;
  final String conversationId;
  final String senderId;
  final String senderDisplayName;
  final String body;
  final DateTime sentAt;
  final MessageDeliveryStatus status;
  ChatMessage copyWith({String? id, MessageDeliveryStatus? status}) => ChatMessage(id: id ?? this.id, conversationId: conversationId, senderId: senderId, senderDisplayName: senderDisplayName, body: body, sentAt: sentAt, status: status ?? this.status);
}
