import '../models/user.dart';

enum SessionStatus {
  /// Opening the local store and restoring a saved session.
  initializing,
  signedOut,

  /// Signed in; the first sync with the server has not finished yet.
  connecting,
  ready,

  /// Signed in, but the last sync failed (usually no network).
  offline,

  /// The server ended the access token and the adapter is refreshing it.
  refreshing,
}

enum SignOutReason {
  none,
  userRequested,

  /// The server invalidated the session (expired, revoked, or signed out
  /// from another device).
  sessionExpired,
}

class SessionState {
  const SessionState(
    this.status, {
    this.user,
    this.signOutReason = SignOutReason.none,
  });

  const SessionState.initializing() : this(SessionStatus.initializing);

  final SessionStatus status;
  final User? user;
  final SignOutReason signOutReason;

  bool get isSignedIn => switch (status) {
    SessionStatus.connecting ||
    SessionStatus.ready ||
    SessionStatus.offline ||
    SessionStatus.refreshing => true,
    SessionStatus.initializing || SessionStatus.signedOut => false,
  };
}
