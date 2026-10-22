import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/matrix_errors.dart';
import 'package:internal_chat/domain/chat_failure.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

MatrixException _matrix(String code, [Map<String, Object?> extra = const {}]) =>
    MatrixException.fromJson({
      'errcode': code,
      'error': 'server text',
      ...extra,
    });

void main() {
  test('rate limits carry retry_after_ms', () {
    final failure = toChatFailure(
      _matrix('M_LIMIT_EXCEEDED', {'retry_after_ms': 5500}),
    );
    expect(failure, isA<RateLimited>());
    expect(
      (failure as RateLimited).retryAfter,
      const Duration(milliseconds: 5500),
    );
  });

  test('maps the Matrix error codes from the handover', () {
    expect(toChatFailure(_matrix('M_FORBIDDEN')), isA<NotAllowed>());
    expect(toChatFailure(_matrix('M_TOO_LARGE')), isA<TooLarge>());
    expect(toChatFailure(_matrix('M_UNKNOWN_TOKEN')), isA<SessionExpired>());
  });

  test('honours soft_logout on M_UNKNOWN_TOKEN', () {
    final soft =
        toChatFailure(_matrix('M_UNKNOWN_TOKEN', {'soft_logout': true}))
            as SessionExpired;
    final hard = toChatFailure(_matrix('M_UNKNOWN_TOKEN')) as SessionExpired;
    expect(soft.softLogout, isTrue);
    expect(hard.softLogout, isFalse);
  });

  test('M_NOT_FOUND means what the caller says', () {
    expect(toChatFailure(_matrix('M_NOT_FOUND')), isA<UnexpectedFailure>());
    expect(
      toChatFailure(_matrix('M_NOT_FOUND'), notFound: const UserNotFound()),
      isA<UserNotFound>(),
    );
  });

  test('network problems become Offline', () {
    expect(toChatFailure(const SocketException('down')), isA<Offline>());
    expect(toChatFailure(TimeoutException('slow')), isA<Offline>());
  });

  test('a wrong recovery key is reported as such', () {
    expect(
      toChatFailure(InvalidPassphraseException('Incorrect parity')),
      isA<InvalidRecoveryKey>(),
    );
  });

  test('upload size errors keep the limit', () {
    final failure = toChatFailure(EventTooLarge(26214400, 26214401));
    expect((failure as TooLarge).maxBytes, 26214400);
  });

  test('anything else becomes a detail-free UnexpectedFailure', () {
    expect(toChatFailure(StateError('internal')), isA<UnexpectedFailure>());
    expect(toChatFailure(_matrix('M_UNKNOWN')), isA<UnexpectedFailure>());
  });

  test('domain failures pass through unchanged', () {
    const failure = NotEncryptedRoom();
    expect(toChatFailure(failure), same(failure));
  });
}
