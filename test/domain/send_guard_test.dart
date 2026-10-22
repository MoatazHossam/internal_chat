import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:internal_chat/domain/send_guard.dart';

void main() {
  test(
    'allows sending only when encryption runs and the room is encrypted',
    () {
      expect(
        () => ensureEncryptedSend(encryptionRunning: true, roomEncrypted: true),
        returnsNormally,
      );
    },
  );

  test('refuses an unencrypted room', () {
    expect(
      () => ensureEncryptedSend(encryptionRunning: true, roomEncrypted: false),
      throwsA(isA<NotEncryptedRoom>()),
    );
  });

  test('refuses when encryption is not running, even in an encrypted room', () {
    // The SDK would send plaintext in this case; the guard must stop it.
    expect(
      () => ensureEncryptedSend(encryptionRunning: false, roomEncrypted: true),
      throwsA(isA<EncryptionUnavailable>()),
    );
  });
}
