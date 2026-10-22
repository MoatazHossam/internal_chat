import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/domain/chat_backend.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/ids.dart';
import 'package:internal_chat/models/chat_message.dart';
import 'package:internal_chat/modules/chat/chat_controller.dart';

import '../support/mock_chat_backend.dart';

const _general = ConversationId('!general:demo.invalid');
const _legacy = ConversationId('!legacy:demo.invalid');

/// Lets stream events and zero-length delays run.
Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late MockChatBackend backend;
  late ChatController controller;

  setUp(() async {
    backend = MockChatBackend(
      latency: Duration.zero,
      replyDelay: const Duration(hours: 1),
    );
    await backend.restore();
    await backend.signIn(username: 'member', password: 'password');
    controller = ChatController(
      backend,
      backend,
      backend,
      isAppInForeground: () => true,
    );
    controller.onInit();
    await settle();
  });

  tearDown(() => controller.onClose());

  test('lists conversations through the Conversations contract', () {
    expect(controller.loading.value, isFalse);
    expect(controller.conversations.map((c) => c.title), contains('General'));
    expect(
      controller.conversations.first.isInvite,
      isTrue,
      reason: 'invites are listed first',
    );
  });

  test('opening a conversation loads messages and clears unread', () async {
    expect(
      controller.conversations.firstWhere((c) => c.id == _general).unreadCount,
      greaterThan(0),
    );

    controller.openConversation(_general);
    await settle();

    expect(controller.messages, isNotEmpty);
    expect(
      controller.conversations.firstWhere((c) => c.id == _general).unreadCount,
      0,
    );
  });

  test('each send gets its own LocalMessageId', () async {
    controller.openConversation(_general);
    await settle();

    await controller.send(_general, 'one');
    await controller.send(_general, 'two');
    await settle();

    final sent = controller.messages.where((m) => m.isOwn && m.localId != null);
    expect(sent.map((m) => m.body), containsAll(['one', 'two']));
    expect(sent.map((m) => m.localId).toSet(), hasLength(2));
    expect(controller.messages.first.body, 'two');
  });

  test(
    'a send into an unencrypted conversation is refused and reported',
    () async {
      controller.openConversation(_legacy);
      await settle();
      final before = controller.messages.length;

      await controller.send(_legacy, 'secret');
      await settle();

      expect(controller.failure.value, isA<NotEncryptedRoom>());
      expect(controller.messages, hasLength(before));
    },
  );

  test('editing replaces the body and marks the message edited', () async {
    controller.openConversation(_general);
    await settle();
    await controller.send(_general, 'tpyo');
    await settle();

    controller.startEditing(controller.messages.first);
    await controller.send(_general, 'typo');
    await settle();

    expect(controller.editing.value, isNull);
    expect(controller.messages.first.body, 'typo');
    expect(controller.messages.first.edited, isTrue);
  });

  test('replies carry a reference to the original message', () async {
    controller.openConversation(_general);
    await settle();
    final original = controller.messages.firstWhere((m) => !m.isOwn);

    controller.setReplyTo(original);
    await controller.send(_general, 'answer');
    await settle();

    expect(controller.replyTo.value, isNull);
    expect(controller.messages.first.replyToId, original.id);
  });

  test('sendVoiceNote sends a voice message through the contract', () async {
    controller.openConversation(_general);
    await settle();

    await controller.sendVoiceNote(
      conversationId: _general,
      file: FileSource(
        name: 'voice-message.m4a',
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/mp4',
      ),
      duration: const Duration(seconds: 4),
    );
    await settle();

    final voice = controller.messages.first;
    expect(voice.isVoiceNote, isTrue);
    expect(voice.attachmentDurationMs, 4000);
    expect(await controller.attachmentBytes(voice), [1, 2, 3]);
  });

  test('message search finds matches and navigates between them', () {
    controller.messages.addAll([
      ChatMessage(
        id: 'm3',
        conversationId: _general,
        senderId: const UserId('@other:demo.invalid'),
        senderDisplayName: 'Other',
        body: 'third apple update',
        sentAt: DateTime(2026, 1, 3),
      ),
      ChatMessage(
        id: 'm2',
        conversationId: _general,
        senderId: const UserId('@other:demo.invalid'),
        senderDisplayName: 'Other',
        body: 'unrelated message',
        sentAt: DateTime(2026, 1, 2),
      ),
      ChatMessage(
        id: 'm1',
        conversationId: _general,
        senderId: const UserId('@other:demo.invalid'),
        senderDisplayName: 'Other',
        body: 'first apple mention',
        sentAt: DateTime(2026, 1, 1),
      ),
    ]);

    controller.updateMessageSearch('apple');

    expect(controller.messageSearchMatchIds, ['m3', 'm1']);
    expect(controller.currentMatchMessageId.value, 'm3');
    expect(controller.currentMatchPosition, 1);

    controller.goToOlderMatch();
    expect(controller.currentMatchMessageId.value, 'm1');
    expect(controller.currentMatchPosition, 2);

    // Already at the oldest match; stays put.
    controller.goToOlderMatch();
    expect(controller.currentMatchMessageId.value, 'm1');

    controller.goToNewerMatch();
    expect(controller.currentMatchMessageId.value, 'm3');

    controller.closeMessageSearch();
    expect(controller.messageSearchActive.value, isFalse);
    expect(controller.messageSearchMatchIds, isEmpty);
    expect(controller.currentMatchMessageId.value, isNull);
  });

  test('defaultServer comes from the signed-in user', () {
    expect(controller.defaultServer, 'demo.invalid');
  });
}
