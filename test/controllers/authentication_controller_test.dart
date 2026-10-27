import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/domain/chat_backend.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/session_state.dart';
import 'package:internal_chat/modules/authentication/authentication_controller.dart';

class FakeChatSession implements ChatSession {
  FakeChatSession({this.failure});

  final ChatFailure? failure;
  String? username;
  String? password;

  @override
  Stream<SessionState> get sessionState => const Stream.empty();

  @override
  SessionState get currentSessionState =>
      const SessionState(SessionStatus.signedOut);

  @override
  Future<void> restore() async {}

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    this.username = username;
    this.password = password;
    final failure = this.failure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> resetLocalData() async {}
}

void main() {
  test('signs in through the session contract', () async {
    final session = FakeChatSession();
    final controller = AuthenticationController(session);

    expect(await controller.signIn('moataz', 'correct horse battery'), isTrue);
    expect(session.username, 'moataz');
    expect(session.password, 'correct horse battery');
    expect(controller.failure.value, isNull);
    expect(controller.loading.value, isFalse);
  });

  test('reports the domain failure from the backend', () async {
    final controller = AuthenticationController(
      FakeChatSession(failure: const RateLimited(Duration(seconds: 30))),
    );

    expect(await controller.signIn('moataz', 'password'), isFalse);
    expect(controller.failure.value, isA<RateLimited>());
  });

  test('does not call the backend with empty credentials', () async {
    final session = FakeChatSession();
    final controller = AuthenticationController(session);

    expect(await controller.signIn('  ', ''), isFalse);
    expect(session.username, isNull);
    expect(controller.failure.value, isA<InvalidCredentials>());
  });
}
