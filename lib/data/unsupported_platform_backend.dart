import '../domain/chat_backend.dart';
import '../domain/chat_failure.dart';
import '../domain/device_trust_state.dart';
import '../domain/session_state.dart';

/// Web builds: the Matrix adapter needs FFI (vodozemac, SQLCipher), which the
/// browser does not have, and `flutter_vodozemac` has no WASM build yet.
/// Startup stops with a clear message instead of showing anything else.
ChatBackend createMatrixBackend(Uri homeserver) =>
    const UnsupportedPlatformBackend();

final class UnsupportedPlatformBackend implements ChatBackend {
  const UnsupportedPlatformBackend();

  static const _state = SessionState(SessionStatus.signedOut);

  @override
  Future<void> restore() async => throw const UnsupportedPlatform();

  @override
  SessionState get currentSessionState => _state;

  @override
  Stream<SessionState> get sessionState => Stream.value(_state);

  @override
  Stream<TrustState> get trustState => Stream.value(TrustState.unknown);

  @override
  Stream<VerificationRequest> get incomingVerifications => const Stream.empty();

  /// Every other operation fails the same way; none is reachable because the
  /// app never leaves the start screen on this platform.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw const UnsupportedPlatform();
}
