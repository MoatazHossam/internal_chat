import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/domain/chat_backend.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/ids.dart';
import 'package:internal_chat/domain/session_state.dart';
import 'package:internal_chat/models/chat_message.dart';

import '../support/mock_chat_backend.dart';

const _general = ConversationId('!general:demo.invalid');
const _legacy = ConversationId('!legacy:demo.invalid');

void main() {
  late MockChatBackend backend;

  setUp(() async {
    backend = MockChatBackend(
      latency: Duration.zero,
      replyDelay: Duration.zero,
    );
    await backend.restore();
    await backend.signIn(username: 'member', password: 'password');
  });

  test('signs in and out', () async {
    expect(backend.currentSessionState.status, SessionStatus.ready);
    await backend.signOut();
    expect(backend.currentSessionState.status, SessionStatus.signedOut);
    expect(
      backend.currentSessionState.signOutReason,
      SignOutReason.userRequested,
    );
  });

  test('rejects empty credentials', () async {
    await expectLater(
      backend.signIn(username: '', password: ''),
      throwsA(isA<InvalidCredentials>()),
    );
  });

  test('the same LocalMessageId is never sent twice', () async {
    final localId = LocalMessageId.generate();
    await backend.sendText(_general, 'once', localId: localId);
    await backend.sendText(_general, 'once', localId: localId);

    final messages = await backend.watch(_general).first;
    expect(messages.where((m) => m.localId == localId), hasLength(1));
  });

  test('refuses to send into an unencrypted conversation', () async {
    await expectLater(
      backend.sendText(
        _legacy,
        'plaintext?',
        localId: LocalMessageId.generate(),
      ),
      throwsA(isA<NotEncryptedRoom>()),
    );
    final messages = await backend.watch(_legacy).first;
    expect(messages.any((m) => m.body == 'plaintext?'), isFalse);
  });

  test('enforces the upload limit', () async {
    final max = (await backend.maxUploadBytes())!;
    final file = FileSource(name: 'big.bin', bytes: Uint8List(max + 1));
    await expectLater(
      backend.sendFile(_general, file, localId: LocalMessageId.generate()),
      throwsA(isA<TooLarge>().having((f) => f.maxBytes, 'maxBytes', max)),
    );
  });

  test('accepts an invite', () async {
    final before = await backend.watchAll().first;
    final invite = before.firstWhere((c) => c.isInvite);
    await backend.acceptInvite(invite.id);
    final after = await backend.watchAll().first;
    expect(after.firstWhere((c) => c.id == invite.id).isInvite, isFalse);
  });

  test('deleting a sent message leaves a deleted placeholder', () async {
    final messages = await backend.watch(_general).first;
    final own = messages.firstWhere((m) => m.isOwn);
    await backend.delete(own.ref);
    final after = await backend.watch(_general).first;
    expect(after.firstWhere((m) => m.id == own.id).kind, MessageKind.deleted);
  });
}
