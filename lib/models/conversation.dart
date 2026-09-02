enum ConversationKind { group, direct }
class Conversation {
  const Conversation({required this.id, required this.title, required this.kind, this.lastMessagePreview, this.lastActivityAt, this.unreadCount = 0});
  final String id;
  final String title;
  final ConversationKind kind;
  final String? lastMessagePreview;
  final DateTime? lastActivityAt;
  final int unreadCount;
}
