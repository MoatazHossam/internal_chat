/// Errors that cross the backend boundary.
///
/// Adapters translate every SDK or transport exception into one of these, so
/// controllers and pages never see SDK types. None of them carries server
/// text: the UI chooses a localized message from the type alone, which keeps
/// infrastructure details out of the interface and out of logs.
sealed class ChatFailure implements Exception {
  const ChatFailure();
}

/// The server asked us to slow down (`429 M_LIMIT_EXCEEDED`).
final class RateLimited extends ChatFailure {
  const RateLimited([this.retryAfter]);

  final Duration? retryAfter;
}

/// The server refused the action (`M_FORBIDDEN`).
final class NotAllowed extends ChatFailure {
  const NotAllowed();
}

/// Username or password was rejected at sign-in.
final class InvalidCredentials extends ChatFailure {
  const InvalidCredentials();
}

/// The access token is no longer valid (`M_UNKNOWN_TOKEN`).
final class SessionExpired extends ChatFailure {
  const SessionExpired({this.softLogout = false});

  /// True when the server kept the device (`soft_logout`), so signing in
  /// again keeps this device's keys.
  final bool softLogout;
}

/// The file is above the server's upload limit (HTTP 413 / `M_TOO_LARGE`).
final class TooLarge extends ChatFailure {
  const TooLarge({this.maxBytes});

  final int? maxBytes;
}

/// The conversation is not end-to-end encrypted, so the app refuses to send.
final class NotEncryptedRoom extends ChatFailure {
  const NotEncryptedRoom();
}

/// End-to-end encryption could not be started on this device.
final class EncryptionUnavailable extends ChatFailure {
  const EncryptionUnavailable();
}

/// The local encrypted store could not be opened. The app must not continue
/// with an unencrypted fallback.
final class SecureStorageUnavailable extends ChatFailure {
  const SecureStorageUnavailable();
}

/// The local encrypted store exists but cannot be opened: its key is gone
/// (for example files restored without the device's Keychain) or does not
/// open it. Nothing is deleted automatically; the user may reset local data.
final class LocalDataUnreadable extends ChatFailure {
  const LocalDataUnreadable();
}

/// This platform cannot run the encrypted backend yet (web).
final class UnsupportedPlatform extends ChatFailure {
  const UnsupportedPlatform();
}

/// No network connection to the server.
final class Offline extends ChatFailure {
  const Offline();
}

/// The user ID does not exist on the server.
final class UserNotFound extends ChatFailure {
  const UserNotFound();
}

/// The recovery key did not unlock the secret storage.
final class InvalidRecoveryKey extends ChatFailure {
  const InvalidRecoveryKey();
}

/// An earlier attempt to send the message may have arrived, and the server
/// would no longer recognise a resend as the same message. Only the user can
/// accept the risk of a duplicate.
final class DeliveryUncertain extends ChatFailure {
  const DeliveryUncertain();
}

/// The operation is not available in the current state (for example a
/// verification that was already cancelled).
final class NotAvailable extends ChatFailure {
  const NotAvailable();
}

/// Anything else. Deliberately carries no detail.
final class UnexpectedFailure extends ChatFailure {
  const UnexpectedFailure();
}
