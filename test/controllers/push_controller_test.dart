import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:internal_chat/domain/chat_backend.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/ids.dart';
import 'package:internal_chat/domain/push.dart';
import 'package:internal_chat/domain/session_state.dart';
import 'package:internal_chat/models/user.dart';
import 'package:internal_chat/modules/push/push_controller.dart';
import 'package:internal_chat/services/push_platform.dart';

class _Platform implements PushPlatform {
  bool permission = true;
  PushToken? currentToken = const PushToken(PushService.fcm, 'token-1');
  String? coldStartRoom;
  final alertTexts = <String>[];
  int cleared = 0;
  final tokens = StreamController<PushToken>.broadcast();
  final opened = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<PushToken?> token() async => currentToken;

  @override
  Stream<PushToken> get tokenChanges => tokens.stream;

  @override
  Stream<String> get openedConversations => opened.stream;

  @override
  Future<String?> takeOpenedConversation() async {
    final room = coldStartRoom;
    coldStartRoom = null;
    return room;
  }

  @override
  Future<void> clearDelivered() async => cleared++;

  @override
  Future<void> setAlertText(String text) async => alertTexts.add(text);
}

class _Registration implements PushRegistration {
  final calls = <(PushToken, String, String)>[];
  ChatFailure? failure;

  @override
  Future<void> registerPush(
    PushToken token, {
    required String alertText,
    required String languageCode,
  }) async {
    final error = failure;
    if (error != null) throw error;
    calls.add((token, alertText, languageCode));
  }
}

class _Session implements ChatSession {
  final _states = StreamController<SessionState>.broadcast();
  SessionState _state = const SessionState(SessionStatus.signedOut);

  void emit(SessionState state) {
    _state = state;
    _states.add(state);
  }

  @override
  Stream<SessionState> get sessionState => _states.stream;

  @override
  SessionState get currentSessionState => _state;

  @override
  Future<void> restore() async {}

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> resetLocalData() async {}
}

const _signedIn = SessionState(
  SessionStatus.ready,
  user: User(
    id: UserId('@me:example.org'),
    displayName: 'Me',
    deviceId: 'DEVICE',
  ),
);

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Platform platform;
  late _Registration registration;
  late _Session session;
  var locale = const Locale('en');

  TestWidgetsFlutterBinding.ensureInitialized();

  PushController create({bool enabled = true}) {
    final controller = PushController(
      platform,
      registration,
      session,
      enabled: enabled,
      locale: () => locale,
    );
    controller.onInit();
    return controller;
  }

  setUp(() {
    Get.testMode = true;
    platform = _Platform();
    registration = _Registration();
    session = _Session();
    locale = const Locale('en');
  });

  test('registers after sign-in with the generic text', () async {
    final controller = create();
    session.emit(_signedIn);
    await _settle();

    expect(controller.status.value, PushStatus.on);
    expect(registration.calls, [
      (const PushToken(PushService.fcm, 'token-1'), 'New message', 'en'),
    ]);
    expect(platform.alertTexts, ['New message']);
  });

  test('uses the app language for the text', () async {
    locale = const Locale('ar');
    create();
    session.emit(_signedIn);
    await _settle();

    expect(registration.calls.single.$2, 'رسالة جديدة');
    expect(registration.calls.single.$3, 'ar');
  });

  test('registers again for a new token or language, not otherwise', () async {
    final controller = create();
    session.emit(_signedIn);
    await _settle();

    await controller.updateRegistration();
    expect(registration.calls, hasLength(1));

    platform.currentToken = const PushToken(PushService.fcm, 'token-2');
    platform.tokens.add(platform.currentToken!);
    await _settle();
    expect(registration.calls.last.$1.value, 'token-2');

    locale = const Locale('ar');
    await controller.updateRegistration();
    expect(registration.calls, hasLength(3));
    expect(registration.calls.last.$3, 'ar');
  });

  test('does nothing when push is not configured', () async {
    final controller = create(enabled: false);
    session.emit(_signedIn);
    await _settle();

    expect(controller.status.value, PushStatus.notConfigured);
    expect(registration.calls, isEmpty);
  });

  test('does nothing before sign-in', () async {
    final controller = create();
    await controller.updateRegistration();

    expect(controller.status.value, PushStatus.pending);
    expect(registration.calls, isEmpty);
  });

  test(
    'reports a refused permission, a missing token and server errors',
    () async {
      final controller = create();
      platform.permission = false;
      session.emit(_signedIn);
      await _settle();
      expect(controller.status.value, PushStatus.denied);

      platform
        ..permission = true
        ..currentToken = null;
      await controller.updateRegistration();
      expect(controller.status.value, PushStatus.unavailable);

      platform.currentToken = const PushToken(PushService.fcm, 'token-1');
      registration.failure = const NotAvailable();
      await controller.updateRegistration();
      expect(controller.status.value, PushStatus.unavailable);
      expect(registration.calls, isEmpty);
    },
  );

  test('turns notification taps into open requests', () async {
    platform.coldStartRoom = '!cold:example.org';
    final controller = create();
    await _settle();
    expect(controller.openRequest.value, '!cold:example.org');

    controller.openRequest.value = null;
    platform.opened.add('!warm:example.org');
    await _settle();
    expect(controller.openRequest.value, '!warm:example.org');
  });

  test('registers again after signing out and in', () async {
    create();
    session.emit(_signedIn);
    await _settle();
    session.emit(const SessionState(SessionStatus.signedOut));
    await _settle();
    session.emit(_signedIn);
    await _settle();

    expect(registration.calls, hasLength(2));
  });
}
