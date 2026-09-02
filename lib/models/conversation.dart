enum ConversationKind { group, direct }

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.kind,
    this.lastMessagePreview,
    this.lastMessageSenderName,
    this.lastActivityAt,
    this.unreadCount = 0,
    this.participantCount,
    this.isTyping = false,
    this.isOnline = false,
  });

  final String id;
  final String title;
  final ConversationKind kind;
  final String? lastMessagePreview;
  final String? lastMessageSenderName;
  final DateTime? lastActivityAt;
  final int unreadCount;
  final int? participantCount;
  final bool isTyping;
  final bool isOnline;

  Conversation copyWith({
    int? unreadCount,
    String? lastMessagePreview,
    String? lastMessageSenderName,
    DateTime? lastActivityAt,
    bool? isTyping,
    bool? isOnline,
  }) =>
      Conversation(
        id: id,
        title: title,
        kind: kind,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
        lastMessageSenderName:
            lastMessageSenderName ?? this.lastMessageSenderName,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        unreadCount: unreadCount ?? this.unreadCount,
        participantCount: participantCount,
        isTyping: isTyping ?? this.isTyping,
        isOnline: isOnline ?? this.isOnline,
      );
}
