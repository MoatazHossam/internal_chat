import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/ids.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';

class ChatController extends GetxController {
  ChatController(
    this._conversations,
    this._messages,
    this._session, {
    bool Function()? isAppInForeground,
  }) : _isAppInForeground = isAppInForeground ?? _defaultIsAppInForeground;

  final Conversations _conversations;
  final Messages _messages;
  final ChatSession _session;
  final bool Function() _isAppInForeground;

  final conversations = <Conversation>[].obs;
  final loading = true.obs;

  /// The latest failure to show. Refreshed on every report, so the same
  /// failure twice is shown twice.
  final failure = Rxn<ChatFailure>();

  /// Messages of the open conversation, newest first.
  final messages = <ChatMessage>[].obs;
  final currentConversationId = Rxn<ConversationId>();

  /// Names of the other people typing in the open conversation.
  final typingLabel = RxnString();
  final replyTo = Rxn<ChatMessage>();
  final editing = Rxn<ChatMessage>();
  final loadingOlder = false.obs;
  final hasOlder = true.obs;

  /// In-conversation message search state.
  final messageSearchActive = false.obs;
  final messageSearchQuery = ''.obs;

  /// IDs of messages matching [messageSearchQuery], in the same
  /// newest-first order as [messages].
  final messageSearchMatchIds = <String>[].obs;
  final currentMatchMessageId = RxnString();

  StreamSubscription<List<Conversation>>? _conversationSubscription;
  StreamSubscription<List<ChatMessage>>? _messageSubscription;
  StreamSubscription<List<String>>? _typingSubscription;
  DateTime? _typingSentAt;
  Timer? _typingStopTimer;
  final _attachmentCache = <String, Future<Uint8List>>{};

  @override
  void onInit() {
    super.onInit();
    _conversationSubscription = _conversations.watchAll().listen(
      (items) {
        conversations.assignAll(items);
        loading.value = false;
      },
      onError: (Object error) {
        loading.value = false;
        _report(error);
      },
    );
  }

  Conversation? get currentConversation {
    final id = currentConversationId.value;
    return conversations.where((c) => c.id == id).firstOrNull;
  }

  /// Server of the signed-in user, used to complete bare user names.
  String get defaultServer =>
      _session.currentSessionState.user?.id.server ?? '';

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  Future<ConversationId?> startDirectChat(UserId other) =>
      _guard(() => _conversations.openDirect(other));

  Future<ConversationId?> createGroup(String name, List<UserId> members) =>
      _guard(() => _conversations.createGroup(name, members));

  Future<void> acceptInvite(ConversationId id) =>
      _guard(() => _conversations.acceptInvite(id));

  /// Declines an invite or leaves a joined conversation.
  Future<void> leave(ConversationId id) =>
      _guard(() => _conversations.leave(id));

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  void openConversation(ConversationId id) {
    if (currentConversationId.value == id && _messageSubscription != null) {
      return;
    }
    _closeConversationStreams();
    currentConversationId.value = id;
    messages.clear();
    replyTo.value = null;
    editing.value = null;
    typingLabel.value = null;
    hasOlder.value = true;
    closeMessageSearch();

    _messageSubscription = _messages.watch(id).listen((items) {
      messages.assignAll(items);
      if (messageSearchActive.value) {
        updateMessageSearch(messageSearchQuery.value);
      }
      _markLatestRead(id, items);
    }, onError: _report);
    _typingSubscription = _messages
        .watchTyping(id)
        .listen(
          (names) =>
              typingLabel.value = names.isEmpty ? null : names.join(', '),
          onError: (Object _) {},
        );
  }

  void closeConversation() {
    final id = currentConversationId.value;
    if (id != null) _stopTyping(id);
    _closeConversationStreams();
    currentConversationId.value = null;
    replyTo.value = null;
    editing.value = null;
    typingLabel.value = null;
    messages.clear();
    _attachmentCache.clear();
    closeMessageSearch();
  }

  Future<void> loadOlder() async {
    final id = currentConversationId.value;
    if (id == null || loadingOlder.value || !hasOlder.value) return;
    loadingOlder.value = true;
    try {
      hasOlder.value = await _messages.loadOlder(id);
    } on ChatFailure catch (error) {
      _report(error);
    } finally {
      loadingOlder.value = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Sends [body], or saves it as an edit when a message is being edited.
  ///
  /// A new [LocalMessageId] is created once per call (one per tap). The
  /// message appears as "sending" at once; the backend keeps retrying while
  /// offline with the same ID, so it cannot arrive twice.
  Future<void> send(ConversationId conversationId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    _stopTyping(conversationId);

    final edited = editing.value;
    if (edited != null) {
      editing.value = null;
      await _guard(() => _messages.edit(edited.ref, text));
      return;
    }

    final reply = replyTo.value;
    replyTo.value = null;
    await _guard(
      () => _messages.sendText(
        conversationId,
        text,
        localId: LocalMessageId.generate(),
        replyTo: reply?.ref,
      ),
    );
  }

  Future<void> sendFile(ConversationId conversationId, FileSource file) async {
    final reply = replyTo.value;
    replyTo.value = null;
    await _guard(
      () => _messages.sendFile(
        conversationId,
        file,
        localId: LocalMessageId.generate(),
        replyTo: reply?.ref,
      ),
    );
  }

  Future<void> sendVoiceNote({
    required ConversationId conversationId,
    required FileSource file,
    required Duration duration,
  }) => _guard(
    () => _messages.sendVoiceNote(
      conversationId,
      file,
      duration: duration,
      localId: LocalMessageId.generate(),
    ),
  );

  Future<int?> maxUploadBytes() => _messages.maxUploadBytes();

  /// Sends typing notifications at most every few seconds while the user
  /// types, and stops them shortly after the user pauses.
  void onComposerChanged(ConversationId conversationId, String text) {
    if (text.trim().isEmpty) {
      _stopTyping(conversationId);
      return;
    }
    final now = DateTime.now();
    final sentAt = _typingSentAt;
    if (sentAt == null || now.difference(sentAt) > const Duration(seconds: 4)) {
      _typingSentAt = now;
      unawaited(_messages.setTyping(conversationId, true));
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(
      const Duration(seconds: 5),
      () => _stopTyping(conversationId),
    );
  }

  // ---------------------------------------------------------------------------
  // Message actions
  // ---------------------------------------------------------------------------

  void setReplyTo(ChatMessage? message) {
    editing.value = null;
    replyTo.value = message;
  }

  void startEditing(ChatMessage message) {
    if (!message.canEdit) return;
    replyTo.value = null;
    editing.value = message;
  }

  void cancelEditing() => editing.value = null;

  Future<void> retry(ChatMessage message) =>
      _guard(() => _messages.retry(message.ref));

  Future<void> delete(ChatMessage message) =>
      _guard(() => _messages.delete(message.ref));

  Future<void> toggleReaction(ChatMessage message, String key) =>
      _guard(() => _messages.toggleReaction(message.ref, key));

  /// Decrypted attachment bytes, kept in memory only while the conversation
  /// is open.
  Future<Uint8List> attachmentBytes(
    ChatMessage message, {
    bool thumbnail = false,
  }) {
    final key = '${message.id}|$thumbnail';
    final cached = _attachmentCache[key];
    if (cached != null) return cached;
    if (_attachmentCache.length >= 40) {
      _attachmentCache.remove(_attachmentCache.keys.first);
    }
    final future = _messages.downloadAttachment(
      message.ref,
      thumbnail: thumbnail,
    );
    _attachmentCache[key] = future;
    future.then<void>(
      (_) {},
      onError: (Object _) => _attachmentCache.remove(key),
    );
    return future;
  }

  // ---------------------------------------------------------------------------
  // In-conversation message search
  // ---------------------------------------------------------------------------

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
    final current = currentMatchMessageId.value;
    currentMatchMessageId.value = ids.contains(current)
        ? current
        : ids.firstOrNull;
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

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _markLatestRead(ConversationId id, List<ChatMessage> items) {
    if (currentConversationId.value != id || !_isAppInForeground()) return;
    final latest = items.where((m) => !m.isPending && !m.isFailed).firstOrNull;
    if (latest == null) return;

    final index = conversations.indexWhere((c) => c.id == id);
    if (index >= 0 && conversations[index].unreadCount > 0) {
      conversations[index] = conversations[index].copyWith(unreadCount: 0);
    }
    unawaited(_messages.markRead(latest.ref).catchError((Object _) {}));
  }

  void _stopTyping(ConversationId conversationId) {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_typingSentAt == null) return;
    _typingSentAt = null;
    unawaited(_messages.setTyping(conversationId, false));
  }

  void _closeConversationStreams() {
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _typingSubscription?.cancel();
    _typingSubscription = null;
  }

  Future<T?> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ChatFailure catch (error) {
      _report(error);
      return null;
    }
  }

  void _report(Object error) {
    failure.value = error is ChatFailure ? error : const UnexpectedFailure();
    failure.refresh();
  }

  static bool _defaultIsAppInForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void onClose() {
    closeConversation();
    _conversationSubscription?.cancel();
    super.onClose();
  }
}
