class Channel {
  final String id;
  final String name;
  final String? description;
  final String type; // 'public' | 'private' | 'direct'
  final int memberCount;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  // For direct messages
  final String? dmParticipantName;
  final String? dmParticipantId;

  bool get isDirect => type == 'direct';

  const Channel({
    required this.id,
    required this.name,
    this.description,
    this.type = 'public',
    this.memberCount = 0,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.dmParticipantName,
    this.dmParticipantId,
  });

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        type: j['type'] as String? ?? 'public',
        memberCount: j['member_count'] as int? ?? 0,
        lastMessage: j['last_message'] as String?,
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.parse(j['last_message_at'] as String)
            : null,
        unreadCount: j['unread_count'] as int? ?? 0,
        dmParticipantName: j['dm_participant_name'] as String?,
        dmParticipantId: j['dm_participant_id'] as String?,
      );
}
