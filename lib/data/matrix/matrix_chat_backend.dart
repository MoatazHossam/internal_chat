import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../domain/chat_backend.dart';
import '../../domain/chat_failure.dart';
import '../../domain/device_trust_state.dart';
import '../../domain/ids.dart';
import '../../domain/send_guard.dart';
import '../../domain/session_state.dart';
import '../../models/chat_message.dart';
import '../../models/conversation.dart';
import '../../models/user.dart' as domain;
import '../../utilities/streams.dart';
import 'matrix_errors.dart';
import 'matrix_mappers.dart';
import 'matrix_store.dart';
import 'matrix_verification.dart';

/// The only class in the app that uses the Matrix SDK. Everything it returns
/// or throws is a domain type, so this file plus `data/matrix/` is all that
/// changes if the SDK is replaced (for example by a matrix-rust-sdk bridge).
final class MatrixChatBackend implements ChatBackend {
  MatrixChatBackend({
    required Uri homeserver,
    this.clientName = 'internal_chat',
  }) : _homeserver = homeserver;

  final Uri _homeserver;
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
  final _autoRetried = <String>{};
  int? _maxUploadBytes;

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

  Future<void> _signOut() async {
    final client = _client;
    if (client != null) {
      // Detach first: the UI must not see "signed out" (and offer sign-in)
      // until the old client is closed and its store deleted.
      _client = null;
      _opening = null;
      await _detach();
      try {
        // Uploads keys to the backup, tells the server, and clears the local
        // store even when the server call fails.
        if (client.isLogged()) await client.logout();
      } catch (_) {
        // Already cleared locally; nothing else to undo.
      }
      try {
        await client.dispose();
      } catch (_) {
        // Closing is best effort; the client is discarded either way.
      }
      try {
        await deleteEncryptedMatrixStore(clientName);
      } catch (_) {
        // The store was cleared by logout(); removing the file is best effort.
      }
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
    var cancelled = false;

    void emit() {
      final current = timeline;
      if (current != null && !controller.isClosed) {
        controller.add(mapTimeline(current));
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
        } catch (error) {
          if (!controller.isClosed) controller.addError(toChatFailure(error));
        }
      },
      onCancel: () async {
        cancelled = true;
        await receipts?.cancel();
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

  @override
  Future<void> sendText(
    ConversationId id,
    String text, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  }) => _run(() async {
    final room = _room(id);
    _ensureCanSend(room);
    final inReplyTo = replyTo == null
        ? null
        : await _event(room, replyTo.messageId);
    // The transaction ID is the LocalMessageId, so every retry of this
    // message reuses it and the server deduplicates.
    await room.sendTextEvent(
      text,
      txid: localId.value,
      inReplyTo: inReplyTo,
      parseCommands: false,
      parseMarkdown: false,
    );
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
    final inReplyTo = replyTo == null
        ? null
        : await _event(room, replyTo.messageId);
    // The SDK encrypts the file (AES-256-CTR) before uploading it.
    await room.sendFileEvent(
      MatrixFile.fromMimeType(
        bytes: file.bytes,
        name: file.name,
        mimeType: file.mimeType,
      ),
      txid: localId.value,
      inReplyTo: inReplyTo,
    );
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
    final milliseconds = duration.inMilliseconds;
    await room.sendFileEvent(
      MatrixAudioFile(
        bytes: file.bytes,
        name: file.name,
        mimeType: file.mimeType ?? 'audio/mp4',
        duration: milliseconds,
      ),
      txid: localId.value,
      // MSC3245 voice-message markers, as Element sends them.
      extraContent: {
        'org.matrix.msc3245.voice': <String, Object?>{},
        'org.matrix.msc1767.audio': {'duration': milliseconds},
      },
    );
  });

  @override
  Future<void> retry(MessageRef ref) => _run(() async {
    final room = _room(ref.conversationId);
    _ensureCanSend(room);
    final event = await _event(room, ref.messageId);
    if (event == null || !event.status.isError) throw const NotAvailable();
    try {
      await event.sendAgain();
    } on FileNoLongerInCacheException {
      // Attachments are not kept on disk, so a failed upload cannot be
      // resent; the user has to pick the file again.
      throw const NotAvailable();
    }
  });

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

  @override
  Future<int?> maxUploadBytes() async {
    final cached = _maxUploadBytes;
    if (cached != null) return cached;
    try {
      final config = await _requireClient().getConfig();
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
    final database = await openEncryptedMatrixStore(clientName);
    final client = Client(
      clientName,
      database: database,
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
      // Keeps retrying a message while offline before marking it failed.
      sendTimelineEventTimeout: const Duration(minutes: 2),
      // Uploads of up to 25 MiB must not time out on slow networks.
      defaultNetworkRequestTimeout: const Duration(minutes: 5),
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
            if (wasOffline) _retryFailedSends(client);
          case SyncStatus.error:
            final exception = update.error?.exception;
            if (exception != null && toChatFailure(exception) is Offline) {
              _offline = true;
              _setSession(
                SessionState(SessionStatus.offline, user: _session.user),
              );
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
    unawaited(_loadOwnProfile(client));
    unawaited(_refreshTrustQuietly(client));
  }

  void _onSignedOut() {
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

  /// After reconnecting, sends failed messages in open conversations again.
  /// `sendAgain` reuses each message's transaction ID, so a message that did
  /// reach the server before the connection dropped is not duplicated.
  void _retryFailedSends(Client client) {
    for (final timeline in _timelines.values.toList()) {
      final room = timeline.room;
      if (!room.encrypted || !client.encryptionEnabled) continue;
      for (final event in timeline.events.toList()) {
        if (!event.status.isError || event.senderId != client.userID) {
          continue;
        }
        final key = event.transactionId ?? event.eventId;
        if (!_autoRetried.add(key)) continue;
        unawaited(event.sendAgain().then<void>((_) {}, onError: (Object _) {}));
      }
    }
  }

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
