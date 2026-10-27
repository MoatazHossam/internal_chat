import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:internal_chat/domain/chat_backend.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/session_state.dart';
import 'package:internal_chat/modules/session/session_controller.dart';

class _Session implements ChatSession {
  /// What each `restore()` call throws, in order; then it succeeds.
  final restoreFailures = <ChatFailure>[];
  int resets = 0;

  @override
  Future<void> restore() async {
    if (restoreFailures.isNotEmpty) throw restoreFailures.removeAt(0);
  }

  @override
  Future<void> resetLocalData() async => resets++;

  @override
  Stream<SessionState> get sessionState => const Stream.empty();

  @override
  SessionState get currentSessionState =>
      const SessionState(SessionStatus.signedOut);

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  setUp(() => Get.testMode = true);

  test('unreadable local data is reported, not deleted', () async {
    final session = _Session()
      ..restoreFailures.add(const LocalDataUnreadable());
    final controller = SessionController(session);

    await controller.restore();

    expect(controller.startupFailure.value, isA<LocalDataUnreadable>());
    expect(session.resets, 0);
  });

  test('resetting on request deletes local data and starts again', () async {
    final session = _Session()
      ..restoreFailures.add(const LocalDataUnreadable());
    final controller = SessionController(session);
    await controller.restore();

    await controller.resetLocalData();

    expect(session.resets, 1);
    expect(controller.startupFailure.value, isNull);
    expect(controller.resetting.value, isFalse);
  });
}
