import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/models/api_result.dart';
import 'package:internal_chat/models/chat_message.dart';
import 'package:internal_chat/models/conversation.dart';
import 'package:internal_chat/models/page_result.dart';
import 'package:internal_chat/modules/chat/chat_controller.dart';
import 'package:internal_chat/repositories/chat_repository.dart';

class ContractChatRepository implements ChatRepository {
  bool listed = false;
  bool sent = false;

  @override
  Stream<ChatMessage> get incomingMessages => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<ApiResult<PageResult<Conversation>>> conversations(
    PageRequest request,
  ) async {
    listed = true;
    return const ApiSuccess(
      PageResult(
        items: [
          Conversation(
              id: 'c', title: 'Through contract', kind: ConversationKind.group),
        ],
      ),
    );
  }

  @override
  Future<ApiResult<PageResult<ChatMessage>>> messages(
    String conversationId,
    PageRequest request,
  ) async =>
      const ApiSuccess(PageResult(items: []));

  @override
  Future<ApiResult<ChatMessage>> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
    String? replyToId,
    String? replyToSenderName,
    String? replyToBody,
    String? attachmentName,
    String? attachmentMimeType,
    int? attachmentDurationMs,
    String? attachmentLocalPath,
  }) async {
    sent = true;
    return ApiSuccess(
      ChatMessage(
        id: 'server-id',
        conversationId: conversationId,
        senderId: 'current-user',
        senderDisplayName: 'You',
        body: body,
        sentAt: DateTime(2026),
        attachmentName: attachmentName,
        attachmentMimeType: attachmentMimeType,
        attachmentDurationMs: attachmentDurationMs,
        attachmentLocalPath: attachmentLocalPath,
      ),
    );
  }
}

void main() {
  test('chat controller lists and sends through repository interface',
      () async {
    final repository = ContractChatRepository();
    final controller = ChatController(repository);
    controller.onInit();

    await controller.loadConversations();

    expect(repository.listed, isTrue);
    expect(controller.conversations.single.title, 'Through contract');

    await controller.send('c', 'hello');
    expect(repository.sent, isTrue);
    expect(controller.messages.single.id, 'server-id');

    controller.onClose();
  });

  test('send delegates to repository contract', () async {
    final repository = ContractChatRepository();
    final controller = ChatController(repository);

    await controller.send('c', 'message');
    expect(repository.sent, isTrue);
  });

  test('message search finds matches and navigates between them', () {
    final repository = ContractChatRepository();
    final controller = ChatController(repository);

    controller.messages.addAll([
      ChatMessage(
        id: 'm3',
        conversationId: 'c',
        senderId: 'other',
        senderDisplayName: 'Other',
        body: 'third apple update',
        sentAt: DateTime(2026, 1, 3),
      ),
      ChatMessage(
        id: 'm2',
        conversationId: 'c',
        senderId: 'other',
        senderDisplayName: 'Other',
        body: 'unrelated message',
        sentAt: DateTime(2026, 1, 2),
      ),
      ChatMessage(
        id: 'm1',
        conversationId: 'c',
        senderId: 'other',
        senderDisplayName: 'Other',
        body: 'first apple mention',
        sentAt: DateTime(2026, 1, 1),
      ),
    ]);

    controller.updateMessageSearch('apple');

    expect(controller.messageSearchMatchIds, ['m3', 'm1']);
    expect(controller.currentMatchMessageId.value, 'm3');
    expect(controller.currentMatchPosition, 1);

    controller.goToOlderMatch();
    expect(controller.currentMatchMessageId.value, 'm1');
    expect(controller.currentMatchPosition, 2);

    // Already at the oldest match; stays put.
    controller.goToOlderMatch();
    expect(controller.currentMatchMessageId.value, 'm1');

    controller.goToNewerMatch();
    expect(controller.currentMatchMessageId.value, 'm3');

    controller.closeMessageSearch();
    expect(controller.messageSearchActive.value, isFalse);
    expect(controller.messageSearchMatchIds, isEmpty);
    expect(controller.currentMatchMessageId.value, isNull);
  });

  test('sendVoiceNote attaches audio metadata through the repository',
      () async {
    final repository = ContractChatRepository();
    final controller = ChatController(repository);

    await controller.sendVoiceNote(
      conversationId: 'c',
      localPath: '/tmp/voice.m4a',
      duration: const Duration(seconds: 4),
    );

    expect(repository.sent, isTrue);
    expect(controller.messages.single.isVoiceNote, isTrue);
  });
}
