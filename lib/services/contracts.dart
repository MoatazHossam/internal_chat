import '../models/authentication.dart'; import '../models/chat_message.dart';
sealed class RealtimeEvent { const RealtimeEvent(); }
class MessageReceived extends RealtimeEvent { const MessageReceived(this.message); final ChatMessage message; }
abstract interface class RealtimeService { Stream<RealtimeEvent> get events; Future<void> connect(); Future<void> disconnect(); }
abstract interface class TokenStorageService { Future<AuthTokens?> read(); Future<void> write(AuthTokens tokens); Future<void> clear(); }
abstract interface class LocalChatStorageService { Future<List<ChatMessage>> readMessages(String conversationId); Future<void> saveMessages(String conversationId, List<ChatMessage> messages); }
abstract interface class OutboxService { Future<void> enqueue(ChatMessage message); Future<List<ChatMessage>> pending(); Future<void> remove(String messageId); }
abstract interface class ConnectivityService { Stream<bool> get changes; Future<bool> get isOnline; }
