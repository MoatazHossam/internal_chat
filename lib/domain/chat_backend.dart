import 'dart:typed_data';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import 'device_trust_state.dart';
import 'ids.dart';
import 'session_state.dart';

// Backend contracts. Pure Dart: no SDK types appear here, so the Matrix SDK
// can be replaced by changing only the adapter and the composition root.
//
// Every method reports errors by throwing a `ChatFailure` (chat_failure.dart).

abstract interface class ChatSession {
  /// Emits the current state on listen, then every change.
  Stream<SessionState> get sessionState;
  SessionState get currentSessionState;

  /// Opens the local store and restores a saved session, if any.
  Future<void> restore();

  /// Password sign-in. Accounts are provisioned by an administrator; there is
  /// no registration.
  Future<void> signIn({required String username, required String password});

  /// Signs out this device and deletes its local data.
  Future<void> signOut();
}

abstract interface class Conversations {
  /// Joined conversations and pending invites, invites first, then most
  /// recent activity first.
  Stream<List<Conversation>> watchAll();

  /// Reuses an existing encrypted direct conversation with [other], or
  /// creates a new encrypted one.
  Future<ConversationId> openDirect(UserId other);

  /// Creates an encrypted, invite-only group. [name] is visible to the
  /// server.
  Future<ConversationId> createGroup(String name, List<UserId> members);

  Future<void> acceptInvite(ConversationId id);

  /// Declines an invite or leaves a joined conversation.
  Future<void> leave(ConversationId id);

  Future<ConversationMembers> members(ConversationId id);
  Future<void> invite(ConversationId id, UserId user);
  Future<void> remove(ConversationId id, UserId user);
}

abstract interface class Messages {
  /// Newest message first. Includes local "sending"/"failed" echoes. Opening
  /// the stream loads the conversation; cancelling it releases it.
  Stream<List<ChatMessage>> watch(ConversationId id);

  /// Loads older history into the [watch] stream. Returns false when the
  /// start of the conversation is reached.
  Future<bool> loadOlder(ConversationId id);

  /// Display names of the other people typing in [id].
  Stream<List<String>> watchTyping(ConversationId id);

  Future<void> sendText(
    ConversationId id,
    String text, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  });

  Future<void> sendFile(
    ConversationId id,
    FileSource file, {
    required LocalMessageId localId,
    MessageRef? replyTo,
  });

  Future<void> sendVoiceNote(
    ConversationId id,
    FileSource file, {
    required Duration duration,
    required LocalMessageId localId,
  });

  /// Sends a failed message again with its original idempotency key.
  Future<void> retry(MessageRef ref);

  /// Adds [key] as a reaction, or removes it if the user already reacted
  /// with it.
  Future<void> toggleReaction(MessageRef ref, String key);
  Future<void> edit(MessageRef ref, String newText);

  /// Redacts a sent message, or discards one that was never sent. Redaction
  /// is not secure erasure: copies on other devices and in downloads remain.
  Future<void> delete(MessageRef ref);

  /// Marks everything up to and including [ref] as read.
  Future<void> markRead(MessageRef ref);
  Future<void> setTyping(ConversationId id, bool typing);

  /// Downloads and decrypts an attachment into memory.
  Future<Uint8List> downloadAttachment(
    MessageRef ref, {
    bool thumbnail = false,
  });

  /// The server's upload limit in bytes, or null when it does not say.
  Future<int?> maxUploadBytes();
}

abstract interface class DeviceTrust {
  /// Emits the current state on listen, then every change.
  Stream<TrustState> get trustState;

  /// Re-reads the state from the server.
  Future<TrustState> refreshTrust();

  /// Creates cross-signing keys, secret storage and the online key backup.
  /// The server re-checks the password before cross-signing keys are
  /// uploaded.
  Future<RecoveryKey> setUpRecovery({required String password});

  /// Connects this device to the account's crypto identity and restores
  /// earlier message keys from the online backup.
  Future<void> restoreWithRecoveryKey(RecoveryKey key);

  /// Asks the user's other signed-in devices to verify this one.
  Future<VerificationRequest> verifyWithOtherDevice();

  /// Verification requests started by other devices or users.
  Stream<VerificationRequest> get incomingVerifications;
}

/// One implementation of all four contracts (the Matrix adapter, or a test
/// fixture). The
/// composition root registers it under each interface; controllers depend
/// only on the interface they need.
abstract interface class ChatBackend
    implements ChatSession, Conversations, Messages, DeviceTrust {}

class FileSource {
  const FileSource({required this.name, required this.bytes, this.mimeType});

  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

enum MemberRole { admin, moderator, member }

class Member {
  const Member({
    required this.id,
    required this.displayName,
    required this.role,
    this.isInvited = false,
    this.canRemove = false,
  });

  final UserId id;
  final String displayName;
  final MemberRole role;
  final bool isInvited;

  /// Whether the signed-in user may remove this member.
  final bool canRemove;
}

class ConversationMembers {
  const ConversationMembers({required this.members, required this.canInvite});

  final List<Member> members;
  final bool canInvite;
}
