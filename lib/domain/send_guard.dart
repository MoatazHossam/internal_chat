import 'chat_failure.dart';

/// The server encrypts new rooms by default but does not enforce it: a client
/// can still send plaintext into any room. The app therefore checks before
/// every message, reaction and edit, and refuses instead of falling back to
/// plaintext.
///
/// Both conditions matter. The Matrix SDK only encrypts when the room is
/// encrypted *and* its own encryption is running, so a room that is marked
/// encrypted would still receive plaintext if encryption failed to start.
void ensureEncryptedSend({
  required bool encryptionRunning,
  required bool roomEncrypted,
}) {
  if (!encryptionRunning) throw const EncryptionUnavailable();
  if (!roomEncrypted) throw const NotEncryptedRoom();
}
