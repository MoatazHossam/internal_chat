import 'dart:async';
import 'dart:typed_data';

import 'package:internal_chat/domain/chat_backend.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/device_trust_state.dart';
import 'package:internal_chat/domain/ids.dart';
import 'package:internal_chat/domain/send_guard.dart';
import 'package:internal_chat/domain/session_state.dart';
import 'package:internal_chat/models/chat_message.dart';
import 'package:internal_chat/models/conversation.dart';
import 'package:internal_chat/models/user.dart';
import 'package:internal_chat/utilities/streams.dart';

const _server = 'demo.invalid';

/// Test fixture: an in-memory backend with sample conversations. Implements
/// the same contracts as the Matrix adapter, so controller tests run through
/// the real interfaces. Not part of the app.
final class MockChatBackend implements ChatBackend {
  MockChatBackend({
    this.latency = const Duration(milliseconds: 300),
    this.replyDelay = const Duration(seconds: 2),
  });

  /// Simulated server round trip for sign-in and sending.
  final Duration latency;

  /// How long the simulated other person "types" before replying.
  final Duration replyDelay;

  static const demoUserId = UserId('@team.member:$_server');

  SessionState _session = const SessionState.initializing();
  final _sessionChanges = StreamController<SessionState>.broadcast();
  TrustState _trust = TrustState.unknown;
  final _trustChanges = StreamController<TrustState>.broadcast();
  final _incoming = StreamController<VerificationRequest>.broadcast();
  final _changes = StreamController<void>.broadcast();
  final _typing = <ConversationId, List<String>>{};
  final _attachments = <String, Uint8List>{};
  Timer? _replyTimer;
  var _sequence = 0;

  User? get _me => _session.user;

  // ---------------------------------------------------------------------------
  // ChatSession
  // ---------------------------------------------------------------------------

  @override
  Stream<SessionState> get sessionState =>
      startWith(() => _session, _sessionChanges.stream);

  @override
  SessionState get currentSessionState => _session;

  @override
  Future<void> restore() async {
    if (_session.status == SessionStatus.initializing) {
      _setSession(const SessionState(SessionStatus.signedOut));
    }
  }

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    if (username.trim().isEmpty || password.isEmpty) {
      throw const InvalidCredentials();
    }
    _setSession(
      const SessionState(
        SessionStatus.ready,
        user: User(
          id: demoUserId,
          displayName: 'Team Member',
          deviceId: 'DEMODEVICE',
        ),
      ),
    );
    _setTrust(TrustState.needsRecoverySetup);
  }

  @override
  Future<void> resetLocalData() async {}

  @override
  Future<void> signOut() async {
    _replyTimer?.cancel();
    _setTrust(TrustState.unknown);
    _setSession(
      const SessionState(
        SessionStatus.signedOut,
        signOutReason: SignOutReason.userRequested,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  @override
  Stream<List<Conversation>> watchAll() =>
      startWith(_conversationList, _changes.stream);

  @override
  Future<ConversationId> openDirect(UserId other) async {
    final existing = _rooms.values
        .where(
          (room) =>
              room.kind == ConversationKind.direct &&
              room.encrypted &&
              room.members.contains(other),
        )
        .firstOrNull;
    if (existing != null) return existing.id;
    final room = _MockRoom(
      id: ConversationId('!dm-${++_sequence}:$_server'),
      title: _nameFor(other),
      kind: ConversationKind.direct,
      members: [other],
    );
    _rooms[room.id] = room;
    _notify();
    return room.id;
  }

  @override
  Future<ConversationId> createGroup(String name, List<UserId> members) async {
    final room = _MockRoom(
      id: ConversationId('!group-${++_sequence}:$_server'),
      title: name.trim(),
      kind: ConversationKind.group,
      members: members,
    );
    _rooms[room.id] = room;
    _notify();
    return room.id;
  }

  @override
  Future<void> acceptInvite(ConversationId id) async {
    _roomOrThrow(id).isInvite = false;
    _notify();
  }

  @override
  Future<void> leave(ConversationId id) async {
    _rooms.remove(id);
    _notify();
  }

  @override
  Future<ConversationMembers> members(ConversationId id) async {
    final room = _roomOrThrow(id);
    return ConversationMembers(
      canInvite: room.kind == ConversationKind.group,
      members: [
        Member(
          id: demoUserId,
          displayName: _me?.displayName ?? 'Team Member',
          role: MemberRole.admin,
        ),
        for (final member in room.members)
          Member(
            id: member,
            displayName: _nameFor(member),
            role: MemberRole.member,
            canRemove: room.kind == ConversationKind.group,
          ),
      ],
    );
  }

  @override
  Future<void> invite(ConversationId id, UserId user) async {
    final room = _roomOrThrow(id);
    if (!room.members.contains(user)) room.members.add(user);
    _notify();
  }

  @override
  Future<void> remove(ConversationId id, UserId user) async {
    _roomOrThrow(id).members.remove(user);
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  @override
  Stream<List<ChatMessage>> watch(ConversationId id) => startWith(
    () => List.unmodifiable(_rooms[id]?.messages.reversed ?? const []),
    _changes.stream,
  );

  @override
  Future<bool> loadOlder(ConversationId id) async => false;

  @override
  Stream<List<String>> watchTyping(ConversationId id) =>
      startWith(() => _typing[id] ?? const <String>[], _changes.stream);

  @override
  Future<void> sendText(
    ConversationId id,
    String text, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  }) => _send(id, localId: localId, body: text, replyTo: replyTo);

  @override
  Future<void> sendFile(
    ConversationId id,
    FileSource file, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  }) async {
    await _checkSize(file.bytes.length);
    final isImage = file.mimeType?.startsWith('image/') ?? false;
    await _send(
      id,
      localId: localId,
      kind: isImage ? MessageKind.image : MessageKind.file,
      replyTo: replyTo,
      file: file,
    );
  }

  @override
  Future<void> sendVoiceNote(
    ConversationId id,
    FileSource file, {
    required Duration duration,
    required LocalMessageId localId,
  }) async {
    await _checkSize(file.bytes.length);
    await _send(
      id,
      localId: localId,
      kind: MessageKind.voice,
      file: file,
      durationMs: duration.inMilliseconds,
    );
  }

  @override
  Future<void> retry(MessageRef ref, {bool acceptDuplicateRisk = false}) async {
    final room = _roomOrThrow(ref.conversationId);
    final index = room.indexOf(ref.messageId);
    if (index < 0 || !room.messages[index].isFailed) {
      throw const NotAvailable();
    }
    if (room.messages[index].failureReason == SendFailureReason.uncertain &&
        !acceptDuplicateRisk) {
      throw const DeliveryUncertain();
    }
    room.messages[index] = _copy(
      room.messages[index],
      status: MessageDeliveryStatus.sent,
    );
    _notify();
  }

  @override
  Future<void> forward(
    MessageRef source,
    ConversationId destination, {
    required LocalMessageId localId,
  }) async {
    final room = _roomOrThrow(source.conversationId);
    final index = room.indexOf(source.messageId);
    if (index < 0 || !room.messages[index].canForward) {
      throw const NotAvailable();
    }
    final message = room.messages[index];
    final bytes = _attachments[message.id];
    await _send(
      destination,
      localId: localId,
      body: message.body,
      kind: message.kind,
      forwarded: true,
      file: bytes == null
          ? null
          : FileSource(
              name: message.attachmentName ?? 'file',
              bytes: bytes,
              mimeType: message.attachmentMimeType,
            ),
      durationMs: message.attachmentDurationMs,
    );
  }

  @override
  Future<void> toggleReaction(MessageRef ref, String key) async {
    final room = _roomOrThrow(ref.conversationId);
    ensureEncryptedSend(encryptionRunning: true, roomEncrypted: room.encrypted);
    final index = room.indexOf(ref.messageId);
    if (index < 0) throw const NotAvailable();
    final message = room.messages[index];
    final reactions = [...message.reactions];
    final existing = reactions.indexWhere((r) => r.key == key);
    if (existing >= 0 && reactions[existing].includesMe) {
      final count = reactions[existing].count - 1;
      if (count == 0) {
        reactions.removeAt(existing);
      } else {
        reactions[existing] = Reaction(
          key: key,
          count: count,
          includesMe: false,
        );
      }
    } else if (existing >= 0) {
      reactions[existing] = Reaction(
        key: key,
        count: reactions[existing].count + 1,
        includesMe: true,
      );
    } else {
      reactions.add(Reaction(key: key, count: 1, includesMe: true));
    }
    room.messages[index] = _copy(message, reactions: reactions);
    _notify();
  }

  @override
  Future<void> edit(MessageRef ref, String newText) async {
    final room = _roomOrThrow(ref.conversationId);
    ensureEncryptedSend(encryptionRunning: true, roomEncrypted: room.encrypted);
    final index = room.indexOf(ref.messageId);
    if (index < 0 || !room.messages[index].isOwn) throw const NotAllowed();
    room.messages[index] = _copy(
      room.messages[index],
      body: newText,
      edited: true,
    );
    _notify();
  }

  @override
  Future<void> delete(MessageRef ref) async {
    final room = _roomOrThrow(ref.conversationId);
    final index = room.indexOf(ref.messageId);
    if (index < 0) throw const NotAvailable();
    final message = room.messages[index];
    if (message.isFailed || message.isPending) {
      room.messages.removeAt(index);
    } else {
      room.messages[index] = _copy(
        message,
        kind: MessageKind.deleted,
        body: '',
        reactions: const [],
      );
    }
    _notify();
  }

  @override
  Future<void> markRead(MessageRef ref) async {
    final room = _rooms[ref.conversationId];
    if (room == null || room.unread == 0) return;
    room.unread = 0;
    _notify();
  }

  @override
  Future<void> setTyping(ConversationId id, bool typing) async {}

  @override
  Future<Uint8List> downloadAttachment(
    MessageRef ref, {
    bool thumbnail = false,
  }) async {
    final bytes = _attachments[ref.messageId];
    if (bytes == null) throw const NotAvailable();
    return bytes;
  }

  @override
  Future<int?> maxUploadBytes() async => 25 * 1024 * 1024;

  // ---------------------------------------------------------------------------
  // DeviceTrust
  // ---------------------------------------------------------------------------

  @override
  Stream<TrustState> get trustState =>
      startWith(() => _trust, _trustChanges.stream);

  @override
  Stream<VerificationRequest> get incomingVerifications => _incoming.stream;

  @override
  Future<TrustState> refreshTrust() async => _trust;

  @override
  Future<RecoveryKey> setUpRecovery({required String password}) async {
    if (password.isEmpty) throw const InvalidCredentials();
    await Future<void>.delayed(latency);
    _setTrust(TrustState.verified);
    return const RecoveryKey(
      'EsTD emo1 Demo Reco very Keyx 1234 5678 abcd efgh ijkl mnop qrst uvwx',
    );
  }

  @override
  Future<void> restoreWithRecoveryKey(RecoveryKey key) async {
    if (key.value.trim().length < 12) throw const InvalidRecoveryKey();
    _setTrust(TrustState.verified);
  }

  @override
  Future<VerificationRequest> verifyWithOtherDevice() async =>
      _MockVerification(onDone: () => _setTrust(TrustState.verified));

  /// Simulates another device asking to verify this one.
  /// Marks one of the user's messages as failed with [reason].
  void failMessage(MessageRef ref, SendFailureReason reason) {
    final room = _roomOrThrow(ref.conversationId);
    final index = room.indexOf(ref.messageId);
    final m = room.messages[index];
    room.messages[index] = ChatMessage(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      senderDisplayName: m.senderDisplayName,
      body: m.body,
      sentAt: m.sentAt,
      kind: m.kind,
      isOwn: m.isOwn,
      status: MessageDeliveryStatus.failed,
      failureReason: reason,
      localId: m.localId,
      canDelete: true,
    );
    _notify();
  }

  void simulateIncomingVerification() {
    _incoming.add(
      _MockVerification(
        incoming: true,
        onDone: () => _setTrust(TrustState.verified),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<void> _send(
    ConversationId id, {
    required LocalMessageId localId,
    String body = '',
    MessageKind kind = MessageKind.text,
    MessageRef? replyTo,
    FileSource? file,
    int? durationMs,
    bool forwarded = false,
  }) async {
    final room = _roomOrThrow(id);
    ensureEncryptedSend(encryptionRunning: true, roomEncrypted: room.encrypted);
    final me = _me;
    if (me == null) throw const SessionExpired();

    // The same LocalMessageId is never added twice, like the server's
    // transaction-ID deduplication.
    if (room.indexOf(localId.value) >= 0) return;

    final reply = replyTo == null ? -1 : room.indexOf(replyTo.messageId);
    final replied = reply < 0 ? null : room.messages[reply];
    if (file != null) _attachments[localId.value] = file.bytes;

    room.messages.add(
      ChatMessage(
        id: localId.value,
        conversationId: id,
        senderId: me.id,
        senderDisplayName: me.displayName,
        body: body,
        sentAt: DateTime.now(),
        kind: kind,
        isOwn: true,
        status: MessageDeliveryStatus.pending,
        localId: localId,
        forwarded: forwarded,
        canEdit: kind == MessageKind.text,
        canDelete: true,
        replyToId: replied?.id,
        replyToSenderName: replied?.senderDisplayName,
        replyToBody: replied?.body,
        replyToKind: replied?.kind,
        attachmentName: file?.name,
        attachmentMimeType: file?.mimeType,
        attachmentSizeBytes: file?.bytes.length,
        attachmentDurationMs: durationMs,
      ),
    );
    _notify();

    await Future<void>.delayed(latency);
    final index = room.indexOf(localId.value);
    if (index >= 0) {
      room.messages[index] = _copy(
        room.messages[index],
        status: MessageDeliveryStatus.sent,
      );
      _notify();
    }
    _scheduleReply(room);
  }

  void _scheduleReply(_MockRoom room) {
    final sender = room.members.firstOrNull;
    if (sender == null) return;
    final name = _nameFor(sender);
    _replyTimer?.cancel();
    _typing[room.id] = [name];
    _notify();
    _replyTimer = Timer(replyDelay, () {
      _typing.remove(room.id);
      // The other person has now read everything.
      for (var i = 0; i < room.messages.length; i++) {
        if (room.messages[i].isOwn &&
            room.messages[i].status == MessageDeliveryStatus.sent) {
          room.messages[i] = _copy(
            room.messages[i],
            status: MessageDeliveryStatus.read,
          );
        }
      }
      room.messages.add(
        ChatMessage(
          id: '\$reply-${++_sequence}',
          conversationId: room.id,
          senderId: sender,
          senderDisplayName: name,
          body: 'Thanks, got it.',
          sentAt: DateTime.now(),
        ),
      );
      _notify();
    });
  }

  Future<void> _checkSize(int bytes) async {
    final max = await maxUploadBytes();
    if (max != null && bytes > max) throw TooLarge(maxBytes: max);
  }

  List<Conversation> _conversationList() {
    final rooms = _rooms.values.toList()
      ..sort((a, b) {
        if (a.isInvite != b.isInvite) return a.isInvite ? -1 : 1;
        return b.lastActivity.compareTo(a.lastActivity);
      });
    return [for (final room in rooms) room.toConversation(_typing[room.id])];
  }

  _MockRoom _roomOrThrow(ConversationId id) =>
      _rooms[id] ?? (throw const NotAvailable());

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _setSession(SessionState state) {
    _session = state;
    _sessionChanges.add(state);
  }

  void _setTrust(TrustState state) {
    if (_trust == state) return;
    _trust = state;
    _trustChanges.add(state);
  }

  static String _nameFor(UserId id) => _people[id] ?? id.value;

  static ChatMessage _copy(
    ChatMessage m, {
    MessageDeliveryStatus? status,
    String? body,
    bool? edited,
    MessageKind? kind,
    List<Reaction>? reactions,
  }) => ChatMessage(
    id: m.id,
    conversationId: m.conversationId,
    senderId: m.senderId,
    senderDisplayName: m.senderDisplayName,
    body: body ?? m.body,
    sentAt: m.sentAt,
    kind: kind ?? m.kind,
    isOwn: m.isOwn,
    status: status ?? m.status,
    failureReason: status == null || status == MessageDeliveryStatus.failed
        ? m.failureReason
        : null,
    localId: m.localId,
    edited: edited ?? m.edited,
    forwarded: m.forwarded,
    canEdit: (kind ?? m.kind) == MessageKind.text && m.canEdit,
    canDelete: (kind ?? m.kind) != MessageKind.deleted && m.canDelete,
    reactions: reactions ?? m.reactions,
    replyToId: m.replyToId,
    replyToSenderName: m.replyToSenderName,
    replyToBody: m.replyToBody,
    replyToKind: m.replyToKind,
    attachmentName: m.attachmentName,
    attachmentMimeType: m.attachmentMimeType,
    attachmentSizeBytes: m.attachmentSizeBytes,
    attachmentDurationMs: m.attachmentDurationMs,
  );

  // ---------------------------------------------------------------------------
  // Demo data
  // ---------------------------------------------------------------------------

  static const _alex = UserId('@alex:$_server');
  static const _layla = UserId('@layla:$_server');
  static const _omar = UserId('@omar:$_server');
  static const _sarah = UserId('@sarah:$_server');

  static const _people = {
    _alex: 'Alex Morgan',
    _layla: 'Layla Hassan',
    _omar: 'Omar Nasser',
    _sarah: 'Sarah Chen',
  };

  late final Map<ConversationId, _MockRoom> _rooms = {
    for (final room in _seedRooms()) room.id: room,
  };

  List<_MockRoom> _seedRooms() {
    ChatMessage msg(
      String id,
      String room,
      UserId sender,
      String body,
      DateTime at, {
      MessageDeliveryStatus status = MessageDeliveryStatus.read,
    }) {
      final own = sender == demoUserId;
      return ChatMessage(
        id: '\$$id',
        conversationId: ConversationId(room),
        senderId: sender,
        senderDisplayName: own ? 'Team Member' : _nameFor(sender),
        body: body,
        sentAt: at,
        isOwn: own,
        status: own ? status : MessageDeliveryStatus.sent,
        canEdit: own,
        canDelete: own,
      );
    }

    final today = DateTime.now();
    DateTime at(int daysAgo, int hour, int minute) =>
        DateTime(today.year, today.month, today.day - daysAgo, hour, minute);

    const general = '!general:$_server';
    const design = '!design:$_server';
    const alex = '!alex:$_server';
    const sarah = '!sarah:$_server';
    const legacy = '!legacy:$_server';

    return [
      _MockRoom(
        id: const ConversationId(general),
        title: 'General',
        kind: ConversationKind.group,
        members: [_alex, _layla, _omar],
        unread: 2,
        messages: [
          msg('g1', general, _alex, 'Good morning everyone!', at(0, 8, 0)),
          msg(
            'g2',
            general,
            _layla,
            'Morning! Ready for the sprint review?',
            at(0, 8, 5),
          ),
          msg(
            'g3',
            general,
            demoUserId,
            'Almost ready. Just finishing up the last slide.',
            at(0, 8, 10),
          ),
          msg(
            'g4',
            general,
            _omar,
            'The staging environment is up and running.',
            at(0, 9, 0),
          ),
          msg(
            'g5',
            general,
            _alex,
            'The weekly sync is moved to Thursday',
            at(0, 9, 15),
          ),
        ],
      ),
      _MockRoom(
        id: const ConversationId(design),
        title: 'Product Design',
        kind: ConversationKind.group,
        members: [_layla],
        messages: [
          msg(
            'd1',
            design,
            _layla,
            'Here are the updated screens for the chat module.',
            at(1, 9, 0),
          ),
          msg(
            'd2',
            design,
            demoUserId,
            'Can we discuss the RTL layouts in our next call?',
            at(0, 11, 0),
            status: MessageDeliveryStatus.sent,
          ),
        ],
      ),
      _MockRoom(
        id: const ConversationId(alex),
        title: 'Alex Morgan',
        kind: ConversationKind.direct,
        members: [_alex],
        messages: [
          msg(
            'a1',
            alex,
            _alex,
            'Did you get a chance to look at the onboarding doc?',
            at(1, 16, 0),
          ),
          msg(
            'a2',
            alex,
            demoUserId,
            'Yes, I left some comments on section 3.',
            at(1, 16, 20),
          ),
        ],
      ),
      _MockRoom(
        id: const ConversationId(sarah),
        title: 'Sarah Chen',
        kind: ConversationKind.direct,
        members: [_sarah],
        isInvite: true,
        invitedBy: 'Sarah Chen',
      ),
      // Demonstrates the rule that the app refuses to send into a room that
      // is not end-to-end encrypted.
      _MockRoom(
        id: const ConversationId(legacy),
        title: 'Legacy room',
        kind: ConversationKind.group,
        members: [_omar],
        encrypted: false,
        messages: [
          msg(
            'l1',
            legacy,
            _omar,
            'This room was created without encryption.',
            at(3, 10, 0),
          ),
        ],
      ),
    ];
  }
}

class _MockRoom {
  _MockRoom({
    required this.id,
    required this.title,
    required this.kind,
    required this.members,
    List<ChatMessage>? messages,
    this.encrypted = true,
    this.unread = 0,
    this.isInvite = false,
    this.invitedBy,
  }) : messages = messages ?? [];

  final ConversationId id;
  final String title;
  final ConversationKind kind;
  final List<UserId> members;

  /// Oldest first.
  final List<ChatMessage> messages;
  final bool encrypted;
  int unread;
  bool isInvite;
  final String? invitedBy;

  DateTime get lastActivity =>
      messages.isEmpty ? DateTime(2000) : messages.last.sentAt;

  int indexOf(String messageId) => messages.indexWhere(
    (m) => m.id == messageId || m.localId?.value == messageId,
  );

  Conversation toConversation(List<String>? typing) {
    final last = messages.lastOrNull;
    return Conversation(
      id: id,
      title: title,
      kind: kind,
      isEncrypted: encrypted,
      lastMessagePreview: last?.body,
      lastMessageKind: last?.kind,
      lastMessageSenderName: last?.senderDisplayName,
      lastMessageIsOwn: last?.isOwn ?? false,
      lastActivityAt: last?.sentAt,
      unreadCount: unread,
      participantCount: members.length + 1,
      isTyping: typing?.isNotEmpty ?? false,
      isInvite: isInvite,
      invitedBy: invitedBy,
    );
  }
}

class _MockVerification implements VerificationRequest {
  _MockVerification({this.incoming = false, this.onDone}) {
    _step = incoming
        ? const VerificationIncoming()
        : const VerificationWaiting();
    if (!incoming) _advanceToEmojis();
  }

  final bool incoming;
  final void Function()? onDone;
  final _steps = StreamController<VerificationStep>.broadcast();
  late VerificationStep _step;

  @override
  bool get isSelfVerification => true;

  @override
  String get otherUserId => MockChatBackend.demoUserId.value;

  @override
  String? get otherDeviceId => 'OTHERDEVICE';

  @override
  VerificationStep get step => _step;

  @override
  Stream<VerificationStep> get steps => _steps.stream;

  @override
  Future<void> accept() async {
    _emit(const VerificationWaiting());
    _advanceToEmojis();
  }

  @override
  Future<void> confirmEmojisMatch() async {
    _emit(const VerificationDone());
    onDone?.call();
  }

  @override
  Future<void> rejectEmojis() async => _emit(const VerificationCancelled());

  @override
  Future<void> cancel() async => _emit(const VerificationCancelled());

  void _advanceToEmojis() {
    Timer(const Duration(milliseconds: 800), () {
      if (_step is! VerificationWaiting) return;
      _emit(
        const VerificationCompareEmojis([
          SasEmoji('🐶', 'Dog'),
          SasEmoji('🔑', 'Key'),
          SasEmoji('🎸', 'Guitar'),
          SasEmoji('🌍', 'Globe'),
          SasEmoji('🚀', 'Rocket'),
          SasEmoji('🍎', 'Apple'),
          SasEmoji('📕', 'Book'),
        ]),
      );
    });
  }

  void _emit(VerificationStep step) {
    _step = step;
    if (!_steps.isClosed) _steps.add(step);
  }
}
