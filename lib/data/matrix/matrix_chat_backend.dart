import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../../constants.dart';
import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/device_trust_state.dart';
import '../../domain/ids.dart';
import '../../domain/push.dart';
import '../../domain/send_guard.dart';
import '../../domain/session_state.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/user.dart' as domain;
import '../../utilities/streams.dart';
import '../../utilities/temporary_media.dart';
import 'matrix_errors.dart';
import 'matrix_mappers.dart';
import 'matrix_push.dart';
import 'matrix_store.dart';
import 'matrix_verification.dart';
import 'outbox/forward_content.dart';
import 'outbox/matrix_outbox_transport.dart';
import 'outbox/outbox_entry.dart';
import 'outbox/outbox_store.dart';
import 'outbox/outbox_worker.dart';

/// The only class in the app that uses the Matrix SDK. Everything it returns
/// or throws is a domain type, so this file plus `data/matrix/` is all that
/// changes if the SDK is replaced (for example by a matrix-rust-sdk bridge).
final class MatrixChatBackend implements ChatBackend {
  MatrixChatBackend({
    required Uri homeserver,
    PushConfiguration? push,
    this.clientName = 'internal_chat',
  }) : _homeserver = homeserver,
       _push = push;

  final Uri _homeserver;
  final PushConfiguration? _push;
  final String clientName;

  Client? _client;
  Future<Client>? _opening;
  Future<void>? _signingOut;
  final _clientSubscriptions = <StreamSubscription<Object?>>[];

  SessionState _session = const SessionState.initializing();
  final _sessionChanges = StreamController<SessionState>.broadcast();
  SignOutReason _nextSignOutReason = SignOutReason.none;
  bool _offline = false;

  TrustState _trust = TrustState.unknown;
  final _trustChanges = StreamController<TrustState>.broadcast();
  final _incomingVerifications =
      StreamController<VerificationRequest>.broadcast();
  String? _uiaPassword;
  bool _uiaPasswordRejected = false;
  final _answeredUia = Expando<bool>();

  final _timelines = <String, Timeline>{};
  int? _maxUploadBytes;

  /// Messages not sent yet, for every conversation. Created with the client.
  OutboxWorker? _outbox;
  Database? _outboxDatabase;

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
    try {
      final client = await _openClient();
      if (!client.isLogged()) {
        await client.init(waitForFirstSync: false);
      }
      if (client.isLogged()) {
        _onSignedIn(client);
      } else {
        _setSession(const SessionState(SessionStatus.signedOut));
      }
    } catch (error) {
      _setSession(const SessionState(SessionStatus.signedOut));
      throw toChatFailure(error);
    }
  }

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final client = await _openClient();
    if (client.isLogged()) return;
    try {
      await client.checkHomeserver(_homeserver);
      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: _deviceDisplayName,
      );
    } on MatrixException catch (error) {
      if (error.error == MatrixError.M_FORBIDDEN) {
        throw const InvalidCredentials();
      }
      throw toChatFailure(error);
    } catch (error) {
      throw toChatFailure(error);
    }
  }

  @override
  Future<void> signOut() =>
      _signingOut ??= _signOut().whenComplete(() => _signingOut = null);

  @override
  Future<void> resetLocalData() async {
    // Only for a store that could not be opened: an open client means the
    // data is readable, and signing out is the way to remove it.
    if (_client != null || _opening != null) throw const NotAvailable();
    try {
      await deleteEncryptedStores(clientName);
    } catch (_) {
      throw const SecureStorageUnavailable();
    }
    await deleteTemporaryMedia();
  }

  Future<void> _signOut() async {
    final client = _client;
    if (client != null) {
      // Detach first: the UI must not see "signed out" (and offer sign-in)
      // until the old client is closed and its store deleted.
      _client = null;
      _opening = null;
      await _detach();
      final outbox = _outbox;
      _outbox = null;
      outbox?.reset();
      try {
        // Uploads keys to the backup, tells the server, and clears the local
        // store even when the server call fails.
        if (client.isLogged()) await client.logout();
      } catch (_) {
        // Already cleared locally; nothing else to undo.
      }
      try {
        await client.dispose();
        await _outboxDatabase?.close();
      } catch (_) {
        // Closing is best effort; the client is discarded either way.
      }
      _outboxDatabase = null;
      try {
        // Unsent messages are deleted with the rest of this user's data.
        await deleteEncryptedStores(clientName);
      } catch (_) {
        // The store was cleared by logout(); removing the file is best effort.
      }
      await deleteTemporaryMedia();
    }
    _offline = false;
    _maxUploadBytes = null;
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
  Stream<List<Conversation>> watchAll() {
    final client = _client;
    if (client == null) return Stream.error(const NotAvailable());
    return startWith(() => _conversations(client), client.onSync.stream);
  }

  @override
  Future<ConversationId> openDirect(UserId other) => _run(() async {
    final client = _requireClient();
    if (other.value == client.userID) throw const NotAllowed();
    final existingId = client.getDirectChatFromUserId(other.value);
    final existing = existingId == null ? null : client.getRoomById(existingId);
    final roomId = await client.startDirectChat(
      other.value,
      enableEncryption: true,
      initialState: [_encryptionState],
      preset: CreateRoomPreset.trustedPrivateChat,
      // An old unencrypted DM is never reused; a new encrypted one is
      // created instead.
      skipExistingChat: existing != null && !existing.encrypted,
    );
    return ConversationId(roomId);
  }, notFound: const UserNotFound());

  @override
  Future<ConversationId> createGroup(String name, List<UserId> members) =>
      _run(() async {
        final client = _requireClient();
        final roomId = await client.createGroupChat(
          groupName: name.trim(),
          enableEncryption: true,
          initialState: [_encryptionState],
          invite: [for (final member in members) member.value],
          preset: CreateRoomPreset.privateChat,
          federated: false,
        );
        return ConversationId(roomId);
      }, notFound: const UserNotFound());

  @override
  Future<void> acceptInvite(ConversationId id) => _run(() => _room(id).join());

  @override
  Future<void> leave(ConversationId id) => _run(() => _room(id).leave());

  @override
  Future<ConversationMembers> members(ConversationId id) => _run(() async {
    final room = _room(id);
    final users = await room.requestParticipants(const [
      Membership.join,
      Membership.invite,
    ]);
    final me = room.client.userID;
    return ConversationMembers(
      canInvite: room.canInvite,
      members: [
        for (final user in users)
          Member(
            id: UserId(user.id),
            displayName: user.calcDisplayname(),
            role: switch (user.powerLevel.role) {
              PowerLevelRole.owner || PowerLevelRole.admin => MemberRole.admin,
              PowerLevelRole.moderator => MemberRole.moderator,
              PowerLevelRole.user => MemberRole.member,
            },
            isInvited: user.membership == Membership.invite,
            canRemove: user.id != me && user.canKick,
          ),
      ],
    );
  });

  @override
  Future<void> invite(ConversationId id, UserId user) =>
      _run(() => _room(id).invite(user.value), notFound: const UserNotFound());

  @override
  Future<void> remove(ConversationId id, UserId user) =>
      _run(() => _room(id).kick(user.value));

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  @override
  Stream<List<ChatMessage>> watch(ConversationId id) {
    late final StreamController<List<ChatMessage>> controller;
    Timeline? timeline;
    StreamSubscription<SyncUpdate>? receipts;
    StreamSubscription<void>? outboxChanges;
    var cancelled = false;

    void emit() {
      final current = timeline;
      if (current != null && !controller.isClosed) {
        controller.add(_messagesOf(current));
      }
    }

    controller = StreamController<List<ChatMessage>>(
      onListen: () async {
        try {
          final room = _room(id);
          final opened = await room.getTimeline(onUpdate: emit);
          if (cancelled) {
            opened.cancelSubscriptions();
            return;
          }
          timeline = _timelines[id.value] = opened;
          emit();
          // Asks the online key backup, and the user's own verified devices,
          // for keys of messages this device cannot decrypt yet. Other
          // devices only answer once this device is verified.
          opened.requestKeys(onlineKeyBackupOnly: false);
          // Receipts and typing arrive as ephemeral sync data, which does not
          // always trigger a timeline update.
          receipts = room.client.onSync.stream
              .where((sync) => _touchesRoom(sync, id.value))
              .listen((_) => emit());
          outboxChanges = _outbox?.changes.listen((_) => emit());
        } catch (error) {
          if (!controller.isClosed) controller.addError(toChatFailure(error));
        }
      },
      onCancel: () async {
        cancelled = true;
        await receipts?.cancel();
        await outboxChanges?.cancel();
        final current = timeline;
        if (current != null) {
          current.cancelSubscriptions();
          if (identical(_timelines[id.value], current)) {
            _timelines.remove(id.value);
          }
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<bool> loadOlder(ConversationId id) => _run(() async {
    final timeline = _timelines[id.value];
    if (timeline == null || !timeline.canRequestHistory) return false;
    await timeline.requestHistory();
    return timeline.canRequestHistory;
  });

  @override
  Stream<List<String>> watchTyping(ConversationId id) {
    final client = _client;
    if (client == null) return Stream.error(const NotAvailable());
    return startWith(
      () => _typingNames(client, id),
      client.onSync.stream.where((sync) => _touchesRoom(sync, id.value)),
    ).distinct(listEquals);
  }

  // Text, files, voice notes and forwards go through the outbox: stored
  // encrypted before the first attempt, sent in order per conversation, and
  // retried across restarts with the same transaction ID (the
  // LocalMessageId), so the server can drop repeats.

  @override
  Future<void> sendText(
    ConversationId id,
    String text, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  }) => _run(() async {
    final room = _room(id);
    _ensureCanSend(room);
    await _enqueue(room, OutboxKind.text, localId, {
      'body': text,
      'replyTo': ?replyTo?.messageId,
    });
  });

  @override
  Future<void> sendFile(
    ConversationId id,
    FileSource file, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  }) => _run(() async {
    final room = _room(id);
    _ensureCanSend(room);
    await _ensureWithinUploadLimit(file.bytes.length);
    await _enqueue(room, OutboxKind.file, localId, {
      'name': file.name,
      'mimeType': ?file.mimeType,
      'size': file.bytes.length,
      'replyTo': ?replyTo?.messageId,
    }, file: file.bytes);
  });

  @override
  Future<void> sendVoiceNote(
    ConversationId id,
    FileSource file, {
    required Duration duration,
    required LocalMessageId localId,
  }) => _run(() async {
    final room = _room(id);
    _ensureCanSend(room);
    await _ensureWithinUploadLimit(file.bytes.length);
    await _enqueue(room, OutboxKind.voice, localId, {
      'name': file.name,
      'mimeType': file.mimeType ?? 'audio/mp4',
      'size': file.bytes.length,
      'durationMs': duration.inMilliseconds,
    }, file: file.bytes);
  });

  @override
  Future<void> forward(
    MessageRef source,
    ConversationId destination, {
    required LocalMessageId localId,
  }) => _run(() async {
    final target = _room(destination);
    _ensureCanSend(target);
    final room = _room(source.conversationId);
    final event = await _requireEvent(room, source.messageId);
    if (!event.status.isSent || event.redacted) throw const NotAvailable();
    final timeline = _timelines[room.id];
    final display = timeline == null ? event : event.getDisplayEvent(timeline);
    // Undecryptable events are still of type m.room.encrypted.
    if (display.type != EventTypes.Message) throw const NotAvailable();
    final content = forwardContent(display.content);
    if (content == null) throw const NotAvailable();
    await _enqueue(target, OutboxKind.forward, localId, {'content': content});
  });

  @override
  Future<void> retry(MessageRef ref, {bool acceptDuplicateRisk = false}) =>
      _run(() async {
        final outbox = _requireOutbox();
        final entry = outbox.entry(ref.messageId);
        if (entry != null) {
          if (entry.state != OutboxState.failed) return;
          if (entry.lastError == SendErrorClass.uncertain) {
            if (!acceptDuplicateRisk) throw const DeliveryUncertain();
            // A new message from this device: the old transaction ID may
            // belong to another device or be past the server's 24 hours.
            await outbox.retry(
              entry.txnId,
              newTxnId: LocalMessageId.generate().value,
            );
          } else {
            await outbox.retry(entry.txnId);
          }
          return;
        }
        await _retryLegacyEcho(ref);
      });

  /// A failed local echo stored by the SDK (sent by an earlier version of
  /// the app). Text moves into the outbox with its transaction ID; attachment
  /// bytes were never kept, so those cannot be resent.
  Future<void> _retryLegacyEcho(MessageRef ref) async {
    final room = _room(ref.conversationId);
    final event = await _event(room, ref.messageId);
    if (event == null || !event.status.isError) throw const NotAvailable();
    if (kindOf(event) != MessageKind.text) throw const NotAvailable();
    _ensureCanSend(room);
    final client = room.client;
    final txnId = event.transactionId ?? event.eventId;
    final entry = OutboxEntry(
      txnId: txnId,
      userId: client.userID!,
      deviceId: client.deviceID!,
      roomId: room.id,
      kind: OutboxKind.text,
      payload: {
        'body': stripReplyFallback(event.body),
        'replyTo': ?event.inReplyToEventId(),
      },
      createdAt: event.originServerTs,
      // It may have reached the server: reconcile like any other attempt.
      attempts: 1,
      firstAttemptAt: event.originServerTs,
      lastAttemptAt: event.originServerTs,
    );
    await _requireOutbox().enqueue(entry);
    await client.database.removeEvent(event.eventId, room.id);
    client.onCancelSendEvent.add(event.eventId);
  }

  @override
  Future<void> toggleReaction(MessageRef ref, String key) => _run(() async {
    final room = _room(ref.conversationId);
    _ensureCanSend(room);
    final event = await _requireEvent(room, ref.messageId);
    final timeline = _timelines[room.id];
    final mine = timeline == null
        ? null
        : event
              .aggregatedEvents(timeline, RelationshipTypes.reaction)
              .where(
                (reaction) =>
                    !reaction.redacted &&
                    reaction.senderId == room.client.userID &&
                    reaction.content
                            .tryGetMap<String, Object?>('m.relates_to')
                            ?.tryGet<String>('key') ==
                        key,
              )
              .firstOrNull;
    if (mine != null) {
      await room.redactEvent(mine.eventId);
    } else {
      await room.sendReaction(event.eventId, key);
    }
  });

  @override
  Future<void> edit(MessageRef ref, String newText) => _run(() async {
    final room = _room(ref.conversationId);
    _ensureCanSend(room);
    final event = await _requireEvent(room, ref.messageId);
    if (event.senderId != room.client.userID) throw const NotAllowed();
    await room.sendTextEvent(
      newText,
      editEventId: event.eventId,
      parseCommands: false,
      parseMarkdown: false,
    );
  });

  @override
  Future<void> delete(MessageRef ref) => _run(() async {
    final outbox = _outbox;
    if (outbox?.entry(ref.messageId) != null) {
      // Not sent: removes it from the outbox. Refused while it is being
      // sent, because that attempt may still arrive.
      if (!await outbox!.discard(ref.messageId)) throw const NotAvailable();
      return;
    }
    final room = _room(ref.conversationId);
    final event = await _requireEvent(room, ref.messageId);
    if (!event.status.isSent) {
      // Never reached the server: just discard the local copy.
      await event.cancelSend();
      return;
    }
    await room.redactEvent(event.eventId);
  });

  @override
  Future<void> markRead(MessageRef ref) => _run(() async {
    final room = _room(ref.conversationId);
    final event = await _event(room, ref.messageId);
    if (event == null || !event.status.isSynced) return;
    if (room.fullyRead == event.eventId && room.notificationCount == 0) {
      return;
    }
    await room.setReadMarker(event.eventId, mRead: event.eventId);
  });

  @override
  Future<void> setTyping(ConversationId id, bool typing) async {
    try {
      await _room(id).setTyping(typing, timeout: 30000);
    } catch (_) {
      // Typing notifications are best effort.
    }
  }

  @override
  Future<Uint8List> downloadAttachment(
    MessageRef ref, {
    bool thumbnail = false,
  }) => _run(() async {
    final room = _room(ref.conversationId);
    final pending = _outbox?.entry(ref.messageId);
    if (pending != null) return _pendingAttachment(room, pending, thumbnail);
    final event = await _requireEvent(room, ref.messageId);
    final timeline = _timelines[room.id];
    final display = timeline == null ? event : event.getDisplayEvent(timeline);
    // Uses the authenticated /_matrix/client/v1/media endpoints and
    // decrypts in memory.
    final file = await display.downloadAndDecryptAttachment(
      getThumbnail: thumbnail && display.hasThumbnail,
    );
    return file.bytes;
  });

  /// The attachment of a message that is not sent yet: the stored file, or
  /// for a forward the original encrypted media.
  Future<Uint8List> _pendingAttachment(
    Room room,
    OutboxEntry entry,
    bool thumbnail,
  ) async {
    if (entry.hasFile) {
      return await _requireOutbox().file(entry.txnId) ??
          (throw const NotAvailable());
    }
    final content = entry.forwardContent;
    if (content == null) throw const NotAvailable();
    final event = Event(
      content: content,
      type: EventTypes.Message,
      eventId: entry.txnId,
      senderId: entry.userId,
      originServerTs: entry.createdAt,
      room: room,
      status: EventStatus.sent,
    );
    final file = await event.downloadAndDecryptAttachment(
      getThumbnail: thumbnail && event.hasThumbnail,
    );
    return file.bytes;
  }

  @override
  Future<int?> maxUploadBytes() async {
    final cached = _maxUploadBytes;
    if (cached != null) return cached;
    try {
      // Short limit: a file is queued without the check while offline, and
      // a later upload above the limit fails with a clear reason.
      final config = await _requireClient().getConfig().timeout(
        const Duration(seconds: 5),
      );
      return _maxUploadBytes = config.mUploadSize;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // DeviceTrust
  // ---------------------------------------------------------------------------

  @override
  Stream<TrustState> get trustState =>
      startWith(() => _trust, _trustChanges.stream);

  @override
  Stream<VerificationRequest> get incomingVerifications =>
      _incomingVerifications.stream;

  @override
  Future<TrustState> refreshTrust() async {
    final client = _client;
    if (client == null || !client.isLogged()) {
      return _setTrust(TrustState.unknown);
    }
    if (!client.encryptionEnabled) {
      return _setTrust(TrustState.encryptionUnavailable);
    }
    try {
      final identity = await _identity(client);
      if (!identity.exists) return _setTrust(TrustState.needsRecoverySetup);
      // What other devices check before sharing room keys with this one.
      if (!client.isUnknownSession) return _setTrust(TrustState.verified);
      return _setTrust(
        identity.hasRecoveryKey
            ? TrustState.unverified
            : TrustState.unverifiedNoRecoveryKey,
      );
    } catch (error) {
      throw toChatFailure(error);
    }
  }

  /// Whether the account already has a cross-signing identity. A published
  /// master key counts even without a recovery key: Element X creates one at
  /// sign-in without setting up secret storage.
  Future<({bool exists, bool hasRecoveryKey})> _identity(Client client) async {
    final state = await client.getCryptoIdentityState();
    final me = client.userID!;
    await client.updateUserDeviceKeys(additionalUsers: {me});
    final hasMasterKey = client.userDeviceKeys[me]?.masterKey != null;
    return (
      exists:
          hasMasterKey || state.crossSigningEnabled || state.keyBackupEnabled,
      hasRecoveryKey: state.initialized,
    );
  }

  @override
  Future<RecoveryKey> setUpRecovery({required String password}) =>
      _run(() async {
        final client = _requireEncryptedClient();
        // Never replace an identity that already exists (for example one
        // created by Element): the user's other devices would lose their
        // verification and other users would stop trusting them.
        if ((await _identity(client)).exists) throw const NotAvailable();
        _uiaPassword = password;
        _uiaPasswordRejected = false;
        try {
          final key = await client.initCryptoIdentity();
          await refreshTrust();
          return RecoveryKey(key);
        } catch (error) {
          if (_uiaPasswordRejected) throw const InvalidCredentials();
          rethrow;
        } finally {
          _uiaPassword = null;
        }
      });

  @override
  Future<void> restoreWithRecoveryKey(RecoveryKey key) => _run(() async {
    final client = _requireEncryptedClient();
    final state = await client.getCryptoIdentityState();
    if (!state.initialized) throw const NotAvailable();
    final secret = key.value.trim();
    if (!state.connected) {
      await client.restoreCryptoIdentity(secret);
    } else if (client.isUnknownSession) {
      await client.encryption!.crossSigning.selfSign(keyOrPassphrase: secret);
    }
    await refreshTrust();
    unawaited(_loadKeyBackup(client));
  });

  @override
  Future<VerificationRequest> verifyWithOtherDevice() => _run(() async {
    final client = _requireEncryptedClient();
    final ownKeys = client.userDeviceKeys[client.userID];
    if (ownKeys == null) throw const NotAvailable();
    final verification = await ownKeys.startVerification();
    return MatrixVerificationRequest(
      verification,
      onDone: () => _afterVerification(client),
    );
  });

  // ---------------------------------------------------------------------------
  // PushRegistration
  // ---------------------------------------------------------------------------

  @override
  Future<void> registerPush(
    PushToken token, {
    required String alertText,
    required String languageCode,
  }) => _run(() async {
    final push = _push;
    if (push == null) throw const NotAvailable();
    // Replaces this pushkey's pusher for any other account on the gateway
    // (append: false), so one device never gets another user's pushes.
    // Synapse removes the pusher when this device signs out.
    await _requireClient().postPusher(
      Pusher.fromJson(
        pusherJson(
          token,
          push,
          alertText: alertText,
          languageCode: languageCode,
          deviceDisplayName: _deviceDisplayName,
          production: kReleaseMode,
        ),
      ),
      append: false,
    );
  });

  // ---------------------------------------------------------------------------
  // Client lifecycle
  // ---------------------------------------------------------------------------

  Future<Client> _openClient() async {
    final signingOut = _signingOut;
    if (signingOut != null) await signingOut;
    final existing = _client;
    if (existing != null) return existing;
    return _opening ??= _createClient().then(
      (client) => _client = client,
      onError: (Object error) {
        _opening = null;
        throw toChatFailure(error);
      },
    );
  }

  Future<Client> _createClient() async {
    try {
      await vod.init();
    } catch (_) {
      throw const EncryptionUnavailable();
    }
    final stores = await openEncryptedStores(clientName);
    final client = Client(
      clientName,
      database: stores.sdk,
      supportedLoginTypes: {AuthenticationTypes.password},
      verificationMethods: {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
      },
      nativeImplementations: NativeImplementationsIsolate(
        compute,
        vodozemacInit: () => vod.init(),
      ),
      // The SDK's lower log levels can include event content. Message
      // bodies, tokens and keys must never reach logs.
      logLevel: Level.error,
      // Requests refresh tokens at sign-in and renews the access token when
      // the server reports it expired.
      onSoftLogout: (client) => client.refreshAccessToken(),
      // Only reactions, edits and redactions still use the SDK's own send
      // queue; messages go through the outbox.
      sendTimelineEventTimeout: const Duration(minutes: 2),
      // Uploads of up to 25 MiB must not time out on slow networks.
      defaultNetworkRequestTimeout: const Duration(minutes: 5),
    );
    _outboxDatabase = stores.outbox;
    _outbox = OutboxWorker(
      store: await SqliteOutboxStore.open(stores.outbox),
      transport: MatrixOutboxTransport(client, isOnline: () => !_offline),
      // Transaction-ID prefix and error class only, never content.
      log: kDebugMode ? debugPrint : null,
    );
    _attach(client);
    return client;
  }

  void _attach(Client client) {
    _clientSubscriptions.addAll([
      client.onSessionCleared.stream.listen((reason) {
        if (_nextSignOutReason == SignOutReason.none) {
          _nextSignOutReason = reason == SessionClearReason.logout
              ? SignOutReason.userRequested
              : SignOutReason.sessionExpired;
        }
      }),
      client.onLoginStateChanged.stream.listen((state) {
        switch (state) {
          case LoginState.loggedIn:
            _onSignedIn(client);
          case LoginState.softLoggedOut:
            _setSession(
              SessionState(SessionStatus.refreshing, user: _session.user),
            );
          case LoginState.loggedOut:
            _onSignedOut();
        }
      }),
      client.onSyncStatus.stream.listen((update) {
        if (!client.isLogged()) return;
        switch (update.status) {
          case SyncStatus.finished:
            final wasOffline = _offline;
            _offline = false;
            _setSession(SessionState(SessionStatus.ready, user: _session.user));
            if (wasOffline) _outbox?.networkRestored();
          case SyncStatus.error:
            final exception = update.error?.exception;
            if (exception != null && toChatFailure(exception) is Offline) {
              final wasOffline = _offline;
              _offline = true;
              _setSession(
                SessionState(SessionStatus.offline, user: _session.user),
              );
              if (!wasOffline) _outbox?.connectionLost();
            }
          default:
            break;
        }
      }),
      client.onSync.stream.listen((sync) {
        final me = client.userID;
        final accountDataChanged = sync.accountData?.isNotEmpty ?? false;
        final ownDevicesChanged =
            sync.deviceLists?.changed?.contains(me) ?? false;
        if (accountDataChanged || ownDevicesChanged) {
          unawaited(_refreshTrustQuietly(client));
        }
      }),
      // An event with one of our transaction IDs came back through sync: an
      // attempt whose response was lost did arrive.
      client.onTimelineEvent.stream.listen((event) {
        final txnId = event.transactionId;
        if (txnId != null &&
            event.status.isSynced &&
            event.senderId == client.userID) {
          unawaited(_outbox?.markDelivered(txnId));
        }
      }),
      client.onKeyVerificationRequest.stream.listen((verification) {
        _incomingVerifications.add(
          MatrixVerificationRequest(
            verification,
            onDone: () => _afterVerification(client),
          ),
        );
      }),
      client.onUiaRequest.stream.listen(_answerUia),
    ]);
  }

  void _onSignedIn(Client client) {
    final userId = client.userID;
    if (userId == null) return;
    final user = domain.User(
      id: UserId(userId),
      displayName: _session.user?.displayName ?? userId.localpart ?? userId,
      deviceId: client.deviceID,
    );
    _nextSignOutReason = SignOutReason.none;
    final status = _offline
        ? SessionStatus.offline
        : client.prevBatch == null
        ? SessionStatus.connecting
        : SessionStatus.ready;
    _setSession(SessionState(status, user: user));
    unawaited(_outbox?.start());
    unawaited(_loadOwnProfile(client));
    unawaited(_refreshTrustQuietly(client));
  }

  void _onSignedOut() {
    // Session lost (not a user sign-out): unsent messages stay stored and
    // are reconsidered after the next sign-in.
    _outbox?.stop();
    for (final timeline in _timelines.values) {
      timeline.cancelSubscriptions();
    }
    _timelines.clear();
    _maxUploadBytes = null;
    _setTrust(TrustState.unknown);
    _setSession(
      SessionState(SessionStatus.signedOut, signOutReason: _nextSignOutReason),
    );
    _nextSignOutReason = SignOutReason.none;
  }

  Future<void> _detach() async {
    for (final subscription in _clientSubscriptions) {
      await subscription.cancel();
    }
    _clientSubscriptions.clear();
    for (final timeline in _timelines.values) {
      timeline.cancelSubscriptions();
    }
    _timelines.clear();
  }

  Future<void> _loadOwnProfile(Client client) async {
    try {
      final profile = await client.fetchOwnProfile();
      final user = _session.user;
      final name = profile.displayName;
      if (user == null || name == null || name.isEmpty) return;
      _setSession(
        SessionState(
          _session.status,
          user: domain.User(
            id: user.id,
            displayName: name,
            deviceId: user.deviceId,
          ),
        ),
      );
    } catch (_) {
      // Keep the Matrix ID as the display name.
    }
  }

  // ---------------------------------------------------------------------------
  // Trust helpers
  // ---------------------------------------------------------------------------

  Future<void> _refreshTrustQuietly(Client client) async {
    final before = _trust;
    try {
      final after = await refreshTrust();
      if (before != TrustState.verified && after == TrustState.verified) {
        unawaited(_loadKeyBackup(client));
      }
    } catch (_) {
      // Shown as "unknown" until the next attempt.
    }
  }

  void _afterVerification(Client client) {
    // Secrets arrive from the other device shortly after verification; the
    // sync listener refreshes again when they land.
    unawaited(_refreshTrustQuietly(client));
  }

  /// Pulls earlier room keys from the online backup so history decrypts.
  Future<void> _loadKeyBackup(Client client) async {
    try {
      await client.encryption?.keyManager.loadAllKeys();
    } catch (_) {
      // Undecryptable messages stay marked as such.
    }
  }

  /// Answers the server's password re-check during cross-signing setup.
  /// Each request is answered at most once, so a wrong password fails
  /// instead of looping.
  void _answerUia(UiaRequest request) {
    if (request.state != UiaRequestState.waitForUser) return;
    final client = _client;
    final password = _uiaPassword;
    final userId = client?.userID;
    if (password == null ||
        userId == null ||
        !request.nextStages.contains(AuthenticationTypes.password)) {
      request.cancel();
      return;
    }
    if (_answeredUia[request] == true) {
      _uiaPasswordRejected = true;
      request.cancel();
      return;
    }
    _answeredUia[request] = true;
    unawaited(
      request.completeStage(
        AuthenticationPassword(
          session: request.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: userId),
        ),
      ),
    );
  }

  TrustState _setTrust(TrustState state) {
    if (_trust != state) {
      _trust = state;
      _trustChanges.add(state);
    }
    return state;
  }

  // ---------------------------------------------------------------------------
  // Message helpers
  // ---------------------------------------------------------------------------

  void _ensureCanSend(Room room) {
    ensureEncryptedSend(
      encryptionRunning: room.client.encryptionEnabled,
      roomEncrypted: room.encrypted,
    );
    if (room.membership != Membership.join) throw const NotAllowed();
  }

  Future<void> _ensureWithinUploadLimit(int bytes) async {
    final max = await maxUploadBytes();
    if (max != null && bytes > max) throw TooLarge(maxBytes: max);
  }

  Future<void> _enqueue(
    Room room,
    OutboxKind kind,
    LocalMessageId localId,
    Map<String, Object?> payload, {
    Uint8List? file,
  }) {
    final client = room.client;
    return _requireOutbox().enqueue(
      OutboxEntry(
        txnId: localId.value,
        userId: client.userID!,
        deviceId: client.deviceID!,
        roomId: room.id,
        kind: kind,
        payload: payload,
        createdAt: DateTime.now(),
        hasFile: file != null,
      ),
      file: file,
    );
  }

  /// The timeline plus this room's unsent messages, newest first.
  List<ChatMessage> _messagesOf(Timeline timeline) {
    final messages = mapTimeline(timeline);
    final outbox = _outbox;
    final entries = outbox?.entriesForRoom(timeline.room.id) ?? const [];
    if (outbox == null || entries.isEmpty) return messages;
    // Already in the timeline under the server's event ID.
    final delivered = {
      for (final event in timeline.events)
        if (event.status.isSent) ?event.transactionId,
    };
    final pending = entries.where((e) => !delivered.contains(e.txnId));
    final pendingIds = {for (final entry in entries) entry.txnId};
    return [
      ...mapOutbox(
        pending,
        timeline,
        online: !_offline,
        isInFlight: outbox.isInFlight,
      ),
      // Drops an SDK echo of a message that moved into the outbox.
      ...messages.where((message) => !pendingIds.contains(message.id)),
    ];
  }

  OutboxWorker _requireOutbox() => _outbox ?? (throw const NotAvailable());

  List<Conversation> _conversations(Client client) => [
    for (final room in client.rooms)
      if (room.membership == Membership.join ||
          room.membership == Membership.invite)
        mapRoom(room),
  ];

  List<String> _typingNames(Client client, ConversationId id) {
    final room = client.getRoomById(id.value);
    if (room == null) return const [];
    return [
      for (final user in room.typingUsers)
        if (user.id != client.userID) user.calcDisplayname(),
    ];
  }

  Client _requireClient() {
    final client = _client;
    if (client == null || !client.isLogged()) throw const NotAvailable();
    return client;
  }

  Client _requireEncryptedClient() {
    final client = _requireClient();
    if (!client.encryptionEnabled) throw const EncryptionUnavailable();
    return client;
  }

  Room _room(ConversationId id) =>
      _requireClient().getRoomById(id.value) ?? (throw const NotAvailable());

  Future<Event?> _event(Room room, String eventId) async {
    final loaded = _timelines[room.id]?.events
        .where((event) => event.eventId == eventId)
        .firstOrNull;
    return loaded ?? await room.getEventById(eventId);
  }

  Future<Event> _requireEvent(Room room, String eventId) async =>
      await _event(room, eventId) ?? (throw const NotAvailable());

  Future<T> _run<T>(
    Future<T> Function() action, {
    ChatFailure? notFound,
  }) async {
    try {
      return await action();
    } catch (error) {
      throw toChatFailure(error, notFound: notFound);
    }
  }

  void _setSession(SessionState state) {
    final previous = _session;
    if (previous.status == state.status &&
        previous.user?.id == state.user?.id &&
        previous.user?.displayName == state.user?.displayName &&
        previous.signOutReason == state.signOutReason) {
      return;
    }
    _session = state;
    _sessionChanges.add(state);
  }

  static bool _touchesRoom(SyncUpdate sync, String roomId) =>
      (sync.rooms?.join?.containsKey(roomId) ?? false) ||
      (sync.rooms?.invite?.containsKey(roomId) ?? false);

  static final _encryptionState = StateEvent(
    type: EventTypes.Encryption,
    content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
  );

  static String get _deviceDisplayName => Platform.isIOS
      ? 'Internal Chat (iOS)'
      : Platform.isAndroid
      ? 'Internal Chat (Android)'
      : 'Internal Chat';
}
