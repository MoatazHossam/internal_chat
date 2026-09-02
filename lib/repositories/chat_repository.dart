import '../models/api_result.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/page_result.dart';

abstract interface class ChatRepository {
  Stream<ChatMessage> get incomingMessages;
  Future<void> initialize();
  Future<void> dispose();

  Future<ApiResult<PageResult<Conversation>>> conversations(
    PageRequest request,
  );

  Future<ApiResult<PageResult<ChatMessage>>> messages(
    String conversationId,
    PageRequest request,
  );

  Future<ApiResult<ChatMessage>> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
    String? replyToId,
    String? replyToSenderName,
    String? replyToBody,
  });
}
