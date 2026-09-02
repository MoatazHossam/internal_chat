import '../models/authentication.dart';
import '../models/chat_message.dart';

// ---------------------------------------------------------------------------
// Realtime events
// ---------------------------------------------------------------------------

sealed class RealtimeEvent {
  const RealtimeEvent();
}

class MessageReceived extends RealtimeEvent {
  const MessageReceived(this.message);
  final ChatMessage message;
}

class TypingEvent extends RealtimeEvent {
  const TypingEvent({
    required this.conversationId,
    required this.userId,
    required this.userName,
    required this.isTyping,
  });

  final String conversationId;
  final String userId;
  final String userName;
  final bool isTyping;
}

class PresenceEvent extends RealtimeEvent {
  const PresenceEvent({required this.userId, required this.isOnline});
  final String userId;
  final bool isOnline;
}

// ---------------------------------------------------------------------------
// Service interfaces
// ---------------------------------------------------------------------------

abstract interface class RealtimeService {
  Stream<RealtimeEvent> get events;
  Future<void> connect();
  Future<void> disconnect();
}

abstract interface class TokenStorageService {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

abstract interface class LocalChatStorageService {
  Future<List<ChatMessage>> readMessages(String conversationId);
  Future<void> saveMessages(String conversationId, List<ChatMessage> messages);
}

abstract interface class OutboxService {
  Future<void> enqueue(ChatMessage message);
  Future<List<ChatMessage>> pending();
  Future<void> remove(String messageId);
}

abstract interface class ConnectivityService {
  Stream<bool> get changes;
  Future<bool> get isOnline;
}
