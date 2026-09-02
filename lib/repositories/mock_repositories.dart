import 'dart:async';

import '../models/api_result.dart';
import '../models/authentication.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/file_models.dart';
import '../models/page_result.dart';
import '../models/user.dart';
import '../services/contracts.dart';
import '../services/mock_services.dart';
import 'authentication_repository.dart';
import 'chat_repository.dart';
import 'file_repository.dart';

// ---------------------------------------------------------------------------
// MockAuthenticationRepository
// ---------------------------------------------------------------------------

class MockAuthenticationRepository implements AuthenticationRepository {
  MockAuthenticationRepository(this._tokens);

  final TokenStorageService _tokens;
  User? _user;

  @override
  Future<ApiResult<AuthenticationOutcome>> signIn({
    required String identifier,
    required String password,
  }) async {
    if (identifier.trim().isEmpty || password.isEmpty) {
      return const ApiFailure(
        ApiError(ApiErrorKind.unknown, 'Enter your credentials'),
      );
    }

    _user = User(
      id: 'current-user',
      displayName: 'Team Member',
      email: 'member@example.invalid',
      isOnline: true,
    );

    final auth = Authenticated(
      _user!,
      const AuthTokens(accessToken: 'mock-session-token'),
    );

    await _tokens.write(auth.tokens);
    return ApiSuccess(auth);
  }

  @override
  Future<ApiResult<Authenticated>> verifyMfa({
    required String challengeId,
    required String code,
  }) async {
    if (code.trim().length != 6) {
      return const ApiFailure(
        ApiError(ApiErrorKind.unknown, 'Enter the 6-digit code'),
      );
    }

    if (code != '123456') {
      return const ApiFailure(
        ApiError(ApiErrorKind.unknown, 'Incorrect verification code'),
      );
    }

    _user = User(
      id: 'current-user',
      displayName: 'Team Member',
      email: 'member@example.invalid',
      isOnline: true,
    );

    final auth = Authenticated(
      _user!,
      const AuthTokens(accessToken: 'mock-mfa-session-token'),
    );

    await _tokens.write(auth.tokens);
    return ApiSuccess(auth);
  }

  @override
  Future<User?> currentUser() async => _user;

  @override
  Future<void> signOut() async {
    _user = null;
    await _tokens.clear();
  }
}

// ---------------------------------------------------------------------------
// MockChatRepository
// ---------------------------------------------------------------------------

class MockChatRepository implements ChatRepository {
  MockChatRepository({
    OutboxService? outbox,
    ConnectivityService? connectivity,
    RealtimeService? realtime,
  })  : _outbox = outbox ?? MemoryOutboxService(),
        _connectivity = connectivity ?? MockConnectivityService(),
        _realtime = realtime ?? MockRealtimeService();

  final OutboxService _outbox;
  final ConnectivityService _connectivity;
  final RealtimeService _realtime;

  StreamSubscription<RealtimeEvent>? _subscription;
  final _incoming = StreamController<ChatMessage>.broadcast();

  Timer? _typingTimer;

  @override
  Stream<ChatMessage> get incomingMessages => _incoming.stream;

  @override
  Future<void> initialize() async {
    _subscription ??= _realtime.events.listen((event) {
      if (event is MessageReceived) {
        _incoming.add(event.message);
      }
    });
    await _realtime.connect();
  }

  @override
  Future<void> dispose() async {
    _typingTimer?.cancel();
    await _subscription?.cancel();
    await _realtime.disconnect();
    await _incoming.close();
  }

  // -------------------------------------------------------------------------
  // Mock data
  // -------------------------------------------------------------------------

  final _now = DateTime(2026, 9, 2, 14, 30);

  late final _conversations = <Conversation>[
    Conversation(
      id: 'general',
      title: 'General',
      kind: ConversationKind.group,
      lastMessagePreview: 'The weekly sync is moved to Thursday',
      lastMessageSenderName: 'Alex Morgan',
      lastActivityAt: DateTime(2026, 9, 2, 14, 15),
      unreadCount: 3,
      participantCount: 12,
    ),
    Conversation(
      id: 'design',
      title: 'Product Design',
      kind: ConversationKind.group,
      lastMessagePreview: 'Updated mockups are in the shared drive',
      lastMessageSenderName: 'Layla Hassan',
      lastActivityAt: DateTime(2026, 9, 2, 11, 42),
      unreadCount: 0,
      participantCount: 5,
    ),
    Conversation(
      id: 'engineering',
      title: 'Engineering',
      kind: ConversationKind.group,
      lastMessagePreview: 'CI pipeline is green again',
      lastMessageSenderName: 'Omar Nasser',
      lastActivityAt: DateTime(2026, 9, 2, 9, 5),
      unreadCount: 1,
      participantCount: 8,
    ),
    Conversation(
      id: 'alex',
      title: 'Alex Morgan',
      kind: ConversationKind.direct,
      lastMessagePreview: 'See you at the stand-up!',
      lastActivityAt: DateTime(2026, 9, 1, 17, 30),
      unreadCount: 0,
      isOnline: true,
    ),
    Conversation(
      id: 'sarah',
      title: 'Sarah Chen',
      kind: ConversationKind.direct,
      lastMessagePreview: 'Can you review the PR when you have a moment?',
      lastActivityAt: DateTime(2026, 9, 1, 10, 20),
      unreadCount: 2,
      isOnline: false,
    ),
  ];

  late final _messages = <String, List<ChatMessage>>{
    'general': [
      ChatMessage(
        id: 'g1',
        conversationId: 'general',
        senderId: 'alex',
        senderDisplayName: 'Alex Morgan',
        body: 'Good morning everyone!',
        sentAt: DateTime(2026, 9, 2, 8, 0),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'g2',
        conversationId: 'general',
        senderId: 'layla',
        senderDisplayName: 'Layla Hassan',
        body: 'Morning! Ready for the sprint review?',
        sentAt: DateTime(2026, 9, 2, 8, 5),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'g3',
        conversationId: 'general',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'Almost ready. Just finishing up the last slide.',
        sentAt: DateTime(2026, 9, 2, 8, 10),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'g4',
        conversationId: 'general',
        senderId: 'omar',
        senderDisplayName: 'Omar Nasser',
        body: 'The staging environment is up and running.',
        sentAt: DateTime(2026, 9, 2, 9, 0),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'g5',
        conversationId: 'general',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'Great work! The demo went really smoothly.',
        sentAt: DateTime(2026, 9, 2, 10, 30),
        status: MessageDeliveryStatus.delivered,
      ),
      ChatMessage(
        id: 'g6',
        conversationId: 'general',
        senderId: 'alex',
        senderDisplayName: 'Alex Morgan',
        body: 'Agreed. Really solid progress this sprint.',
        sentAt: DateTime(2026, 9, 2, 10, 35),
        status: MessageDeliveryStatus.read,
        replyToId: 'g5',
        replyToSenderName: 'Team Member',
        replyToBody: 'Great work! The demo went really smoothly.',
      ),
      ChatMessage(
        id: 'g7',
        conversationId: 'general',
        senderId: 'alex',
        senderDisplayName: 'Alex Morgan',
        body: 'The weekly sync is moved to Thursday',
        sentAt: DateTime(2026, 9, 2, 14, 15),
        status: MessageDeliveryStatus.sent,
      ),
    ],
    'design': [
      ChatMessage(
        id: 'd1',
        conversationId: 'design',
        senderId: 'layla',
        senderDisplayName: 'Layla Hassan',
        body: 'Here are the updated screens for the chat module.',
        sentAt: DateTime(2026, 9, 1, 9, 0),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'd2',
        conversationId: 'design',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'These look great! Love the attachment preview design.',
        sentAt: DateTime(2026, 9, 1, 9, 15),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'd3',
        conversationId: 'design',
        senderId: 'layla',
        senderDisplayName: 'Layla Hassan',
        body: 'Thanks! I also updated the empty state illustrations.',
        sentAt: DateTime(2026, 9, 1, 9, 20),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'd4',
        conversationId: 'design',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'Can we discuss the RTL layouts in our next call?',
        sentAt: DateTime(2026, 9, 2, 11, 0),
        status: MessageDeliveryStatus.delivered,
      ),
      ChatMessage(
        id: 'd5',
        conversationId: 'design',
        senderId: 'layla',
        senderDisplayName: 'Layla Hassan',
        body: 'Updated mockups are in the shared drive',
        sentAt: DateTime(2026, 9, 2, 11, 42),
        status: MessageDeliveryStatus.read,
      ),
    ],
    'engineering': [
      ChatMessage(
        id: 'e1',
        conversationId: 'engineering',
        senderId: 'omar',
        senderDisplayName: 'Omar Nasser',
        body: 'Heads up: the CI pipeline was failing on the auth tests.',
        sentAt: DateTime(2026, 9, 2, 8, 30),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'e2',
        conversationId: 'engineering',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'On it. Looks like a dependency version conflict.',
        sentAt: DateTime(2026, 9, 2, 8, 45),
        status: MessageDeliveryStatus.read,
        replyToId: 'e1',
        replyToSenderName: 'Omar Nasser',
        replyToBody: 'Heads up: the CI pipeline was failing on the auth tests.',
      ),
      ChatMessage(
        id: 'e3',
        conversationId: 'engineering',
        senderId: 'omar',
        senderDisplayName: 'Omar Nasser',
        body: 'CI pipeline is green again',
        sentAt: DateTime(2026, 9, 2, 9, 5),
        status: MessageDeliveryStatus.sent,
      ),
    ],
    'alex': [
      ChatMessage(
        id: 'a1',
        conversationId: 'alex',
        senderId: 'alex',
        senderDisplayName: 'Alex Morgan',
        body: 'Hey! Did you get a chance to look at the onboarding doc?',
        sentAt: DateTime(2026, 9, 1, 16, 0),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'a2',
        conversationId: 'alex',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'Yes, looks good! I left some comments on section 3.',
        sentAt: DateTime(2026, 9, 1, 16, 20),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'a3',
        conversationId: 'alex',
        senderId: 'alex',
        senderDisplayName: 'Alex Morgan',
        body: 'Perfect, I will address them before the review.',
        sentAt: DateTime(2026, 9, 1, 16, 45),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 'a4',
        conversationId: 'alex',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'See you at the stand-up!',
        sentAt: DateTime(2026, 9, 1, 17, 30),
        status: MessageDeliveryStatus.read,
      ),
    ],
    'sarah': [
      ChatMessage(
        id: 's1',
        conversationId: 'sarah',
        senderId: 'sarah',
        senderDisplayName: 'Sarah Chen',
        body: 'Hi! I finished the token storage implementation.',
        sentAt: DateTime(2026, 9, 1, 9, 0),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 's2',
        conversationId: 'sarah',
        senderId: 'current-user',
        senderDisplayName: 'Team Member',
        body: 'Nice, I will take a look this afternoon.',
        sentAt: DateTime(2026, 9, 1, 9, 30),
        status: MessageDeliveryStatus.read,
      ),
      ChatMessage(
        id: 's3',
        conversationId: 'sarah',
        senderId: 'sarah',
        senderDisplayName: 'Sarah Chen',
        body: 'Can you review the PR when you have a moment?',
        sentAt: DateTime(2026, 9, 1, 10, 20),
        status: MessageDeliveryStatus.delivered,
      ),
    ],
  };

  // -------------------------------------------------------------------------
  // Repository methods
  // -------------------------------------------------------------------------

  @override
  Future<ApiResult<PageResult<Conversation>>> conversations(
    PageRequest request,
  ) async {
    return ApiSuccess(PageResult(items: List.unmodifiable(_conversations)));
  }

  @override
  Future<ApiResult<PageResult<ChatMessage>>> messages(
    String conversationId,
    PageRequest request,
  ) async {
    final list = _messages[conversationId] ?? [];
    return ApiSuccess(PageResult(items: List.unmodifiable(list)));
  }

  @override
  Future<ApiResult<ChatMessage>> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
    String? replyToId,
    String? replyToSenderName,
    String? replyToBody,
  }) async {
    final pending = ChatMessage(
      id: clientId,
      conversationId: conversationId,
      senderId: 'current-user',
      senderDisplayName: 'Team Member',
      body: body,
      sentAt: _now,
      status: MessageDeliveryStatus.pending,
      replyToId: replyToId,
      replyToSenderName: replyToSenderName,
      replyToBody: replyToBody,
    );

    final isOnline = await _connectivity.isOnline;
    if (!isOnline) {
      await _outbox.enqueue(pending);
      return ApiSuccess(pending);
    }

    final sent = ChatMessage(
      id: 'mock-$clientId',
      conversationId: conversationId,
      senderId: 'current-user',
      senderDisplayName: 'Team Member',
      body: body,
      sentAt: DateTime.now(),
      status: MessageDeliveryStatus.sent,
      replyToId: replyToId,
      replyToSenderName: replyToSenderName,
      replyToBody: replyToBody,
    );

    (_messages[conversationId] ??= []).add(sent);

    // Update conversation preview.
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      _conversations[idx] = _conversations[idx].copyWith(
        lastMessagePreview: body,
        lastMessageSenderName: 'You',
        lastActivityAt: sent.sentAt,
      );
    }

    // Simulate a reply after a short delay for demo purposes.
    _scheduleAutoReply(conversationId);

    return ApiSuccess(sent);
  }

  void _scheduleAutoReply(String conversationId) {
    _typingTimer?.cancel();

    const replies = <String, String>{
      'general': 'Thanks for the update!',
      'design': 'Will take a look shortly.',
      'engineering': 'Good to know, thanks.',
      'alex': 'Got it, talk soon!',
      'sarah': 'Sure, reviewing now.',
    };

    const senders = <String, String>{
      'general': 'Alex Morgan',
      'design': 'Layla Hassan',
      'engineering': 'Omar Nasser',
      'alex': 'Alex Morgan',
      'sarah': 'Sarah Chen',
    };

    final reply = replies[conversationId];
    final senderName = senders[conversationId];
    if (reply == null || senderName == null) return;

    // Emit typing event.
    final mock = _realtime is MockRealtimeService ? _realtime : null;
    if (mock == null) return;

    mock.emit(
      TypingEvent(
        conversationId: conversationId,
        userId: 'other-user',
        userName: senderName,
        isTyping: true,
      ),
    );

    _typingTimer = Timer(const Duration(seconds: 2), () {
      mock.emit(
        TypingEvent(
          conversationId: conversationId,
          userId: 'other-user',
          userName: senderName,
          isTyping: false,
        ),
      );

      final autoReply = ChatMessage(
        id: 'auto-reply-${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId,
        senderId: 'other-user',
        senderDisplayName: senderName,
        body: reply,
        sentAt: DateTime.now(),
        status: MessageDeliveryStatus.sent,
      );

      mock.emit(MessageReceived(autoReply));
    });
  }
}

// ---------------------------------------------------------------------------
// MockFileRepository
// ---------------------------------------------------------------------------

class MockFileRepository implements FileRepository {
  @override
  Future<ApiResult<UploadedFile>> upload(FileSelection file) async {
    return ApiSuccess(
      UploadedFile(
        id: 'mock-file-${file.name.hashCode.abs()}',
        name: file.name,
      ),
    );
  }
}
