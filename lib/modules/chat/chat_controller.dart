import 'dart:async';

import 'package:get/get.dart';
import 'package:uuid/uuid.dart';

import '../../models/api_result.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/page_result.dart';
import '../../repositories/chat_repository.dart';
import '../../services/contracts.dart';

class ChatController extends GetxController {
  ChatController(this._repository);

  final ChatRepository _repository;

  final conversations = <Conversation>[].obs;
  final messages = <ChatMessage>[].obs;
  final loading = false.obs;
  final error = RxnString();

  /// The message currently being replied to, if any.
  final replyTo = Rxn<ChatMessage>();

  /// The ID of the conversation currently open in the chat page.
  final currentConversationId = RxnString();

  /// Per-conversation typing state: conversationId → typer display name.
  final typingLabel = RxnString();

  /// In-conversation message search state.
  final messageSearchActive = false.obs;
  final messageSearchQuery = ''.obs;

  /// IDs of messages matching [messageSearchQuery], in the same
  /// newest-first order as [messages].
  final messageSearchMatchIds = <String>[].obs;
  final currentMatchMessageId = RxnString();

  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<RealtimeEvent>? _realtimeSubscription;

  @override
  void onInit() {
    super.onInit();

    _messageSubscription = _repository.incomingMessages.listen((message) {
      // Only show in current conversation's message list.
      if (message.conversationId == currentConversationId.value) {
        messages.insert(0, message);
      }
      _updateConversationPreview(message);
    });

    // Listen to realtime events directly for typing indicators.
    // The realtime service is accessed through the repository via
    // incomingMessages; typing is a separate concern handled here.
    _repository.initialize();
  }

  void listenToRealtime(Stream<RealtimeEvent> events) {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = events.listen((event) {
      if (event is TypingEvent) {
        if (event.conversationId == currentConversationId.value) {
          typingLabel.value = event.isTyping ? event.userName : null;
        }
      }
    });
  }

  // -------------------------------------------------------------------------
  // Conversations
  // -------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Messages
  // -------------------------------------------------------------------------

  Future<void> openConversation(String conversationId) async {
    currentConversationId.value = conversationId;
    replyTo.value = null;
    typingLabel.value = null;
    closeMessageSearch();

    final result = await _repository.messages(
      conversationId,
      const PageRequest(),
    );

    if (result case ApiSuccess(value: final page)) {
      messages.assignAll(page.items.reversed.toList());
      _markConversationRead(conversationId);
    }
  }

  void closeConversation() {
    currentConversationId.value = null;
    replyTo.value = null;
    typingLabel.value = null;
    messages.clear();
    closeMessageSearch();
  }

  // -------------------------------------------------------------------------
  // Sending
  // -------------------------------------------------------------------------

  Future<void> send(String conversationId, String body) async {
    if (body.trim().isEmpty) return;

    final reply = replyTo.value;
    replyTo.value = null;

    final result = await _repository.sendMessage(
      conversationId: conversationId,
      body: body.trim(),
      clientId: const Uuid().v4(),
      replyToId: reply?.id,
      replyToSenderName: reply?.senderDisplayName,
      replyToBody:
          reply != null && reply.isVoiceNote ? '🎤 Voice message' : reply?.body,
    );

    switch (result) {
      case ApiSuccess(value: final sent):
        messages.insert(0, sent);
        _updateConversationPreview(sent);
      case ApiFailure(error: final apiError):
        error.value = apiError.message;
    }
  }

  Future<void> sendVoiceNote({
    required String conversationId,
    required String localPath,
    required Duration duration,
  }) async {
    final result = await _repository.sendMessage(
      conversationId: conversationId,
      body: '',
      clientId: const Uuid().v4(),
      attachmentName: 'Voice message',
      attachmentMimeType: 'audio/m4a',
      attachmentDurationMs: duration.inMilliseconds,
      attachmentLocalPath: localPath,
    );

    switch (result) {
      case ApiSuccess(value: final sent):
        messages.insert(0, sent);
        _updateConversationPreview(sent);
      case ApiFailure(error: final apiError):
        error.value = apiError.message;
    }
  }

  void setReplyTo(ChatMessage? message) {
    replyTo.value = message;
  }

  // -------------------------------------------------------------------------
  // In-conversation message search
  // -------------------------------------------------------------------------

  void openMessageSearch() {
    messageSearchActive.value = true;
  }

  void closeMessageSearch() {
    messageSearchActive.value = false;
    messageSearchQuery.value = '';
    messageSearchMatchIds.clear();
    currentMatchMessageId.value = null;
  }

  void updateMessageSearch(String query) {
    messageSearchQuery.value = query;

    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      messageSearchMatchIds.clear();
      currentMatchMessageId.value = null;
      return;
    }

    final ids = messages
        .where((m) => m.body.toLowerCase().contains(normalized))
        .map((m) => m.id)
        .toList();
    messageSearchMatchIds.assignAll(ids);
    currentMatchMessageId.value = ids.isEmpty ? null : ids.first;
  }

  /// 1-based position of the current match among [messageSearchMatchIds],
  /// or 0 when there is no current match.
  int get currentMatchPosition {
    final id = currentMatchMessageId.value;
    if (id == null) return 0;
    return messageSearchMatchIds.indexOf(id) + 1;
  }

  /// Moves to the next older match (further up the conversation).
  void goToOlderMatch() {
    final ids = messageSearchMatchIds;
    if (ids.isEmpty) return;
    final idx = ids.indexOf(currentMatchMessageId.value);
    if (idx >= 0 && idx < ids.length - 1) {
      currentMatchMessageId.value = ids[idx + 1];
    }
  }

  /// Moves to the next newer match (further down the conversation).
  void goToNewerMatch() {
    final ids = messageSearchMatchIds;
    if (ids.isEmpty) return;
    final idx = ids.indexOf(currentMatchMessageId.value);
    if (idx > 0) {
      currentMatchMessageId.value = ids[idx - 1];
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _markConversationRead(String conversationId) {
    final idx = conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0 && conversations[idx].unreadCount > 0) {
      conversations[idx] = conversations[idx].copyWith(unreadCount: 0);
    }
  }

  void _updateConversationPreview(ChatMessage message) {
    final idx = conversations.indexWhere(
      (c) => c.id == message.conversationId,
    );
    if (idx >= 0) {
      conversations[idx] = conversations[idx].copyWith(
        lastMessagePreview: message.body,
        lastMessageSenderName: message.senderId == 'current-user'
            ? 'You'
            : message.senderDisplayName,
        lastActivityAt: message.sentAt,
      );
      // Bubble unread if not in the current conversation.
      if (message.conversationId != currentConversationId.value &&
          message.senderId != 'current-user') {
        conversations[idx] = conversations[idx].copyWith(
          unreadCount: conversations[idx].unreadCount + 1,
        );
      }
    }
  }

  @override
  void onClose() {
    _messageSubscription?.cancel();
    _realtimeSubscription?.cancel();
    _repository.dispose();
    super.onClose();
  }
}
