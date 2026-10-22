import '../domain/ids.dart';
import 'chat_message.dart';

enum ConversationKind { group, direct }

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.kind,
    required this.isEncrypted,
    this.lastMessagePreview,
    this.lastMessageKind,
    this.lastMessageSenderName,
    this.lastMessageIsOwn = false,
    this.lastActivityAt,
    this.unreadCount = 0,
    this.participantCount,
    this.isTyping = false,
    this.isInvite = false,
    this.invitedBy,
  });

  final ConversationId id;

  /// Room names are server-visible state, not encrypted content.
  final String title;
  final ConversationKind kind;

  /// Whether messages in this conversation are end-to-end encrypted. The app
  /// refuses to send into conversations where this is false.
  final bool isEncrypted;

  final String? lastMessagePreview;
  final MessageKind? lastMessageKind;
  final String? lastMessageSenderName;
  final bool lastMessageIsOwn;
  final DateTime? lastActivityAt;
  final int unreadCount;
  final int? participantCount;
  final bool isTyping;

  /// The user was invited and has not joined yet.
  final bool isInvite;
  final String? invitedBy;

  Conversation copyWith({int? unreadCount}) => Conversation(
    id: id,
    title: title,
    kind: kind,
    isEncrypted: isEncrypted,
    lastMessagePreview: lastMessagePreview,
    lastMessageKind: lastMessageKind,
    lastMessageSenderName: lastMessageSenderName,
    lastMessageIsOwn: lastMessageIsOwn,
    lastActivityAt: lastActivityAt,
    unreadCount: unreadCount ?? this.unreadCount,
    participantCount: participantCount,
    isTyping: isTyping,
    isInvite: isInvite,
    invitedBy: invitedBy,
  );
}
