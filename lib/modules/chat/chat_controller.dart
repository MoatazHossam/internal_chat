import 'dart:async';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import '../../models/api_result.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/page_result.dart';
import '../../repositories/chat_repository.dart';

class ChatController extends GetxController {
  ChatController(this._repository);
  final ChatRepository _repository;
  final conversations = <Conversation>[].obs;
  final messages = <ChatMessage>[].obs;
  final loading = false.obs;
  final error = RxnString();
  StreamSubscription<ChatMessage>? _subscription;

  @override
  void onInit() {
    super.onInit();
    _subscription = _repository.incomingMessages.listen(
      (message) => messages.insert(0, message),
    );
    _repository.initialize();
  }

  Future<void> loadConversations() async {
    loading.value = true;
    final result = await _repository.conversations(const PageRequest());
    loading.value = false;
    switch (result) {
      case ApiSuccess(value: final page):
        conversations.assignAll(page.items);
      case ApiFailure(error: final apiError):
        error.value = apiError.message;
    }
  }

  Future<void> loadMessages(String id) async {
    final result = await _repository.messages(id, const PageRequest());
    if (result case ApiSuccess(value: final page)) {
      messages.assignAll(page.items.reversed);
    }
  }

  Future<void> send(String conversationId, String body) async {
    if (body.trim().isEmpty) return;
    final result = await _repository.sendMessage(
      conversationId: conversationId,
      body: body.trim(),
      clientId: const Uuid().v4(),
    );
    switch (result) {
      case ApiSuccess(value: final sent):
        messages.insert(0, sent);
      case ApiFailure(error: final apiError):
        error.value = apiError.message;
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    _repository.dispose();
    super.onClose();
  }
}
