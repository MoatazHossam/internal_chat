import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/data/matrix/outbox/matrix_outbox_transport.dart';
import 'package:internal_chat/data/matrix/outbox/outbox_entry.dart';
import 'package:matrix/matrix.dart';

SendErrorClass _classOf(Object error) => classifySendError(error).errorClass;

MatrixException _matrix(String code, [Map<String, Object?> extra = const {}]) =>
    MatrixException.fromJson({'errcode': code, 'error': 'x', ...extra});

void main() {
  test('rate limits keep retry_after_ms', () {
    final error = classifySendError(
      _matrix('M_LIMIT_EXCEEDED', {'retry_after_ms': 1500}),
    );
    expect(error.errorClass, SendErrorClass.rateLimited);
    expect(error.retryAfter, const Duration(milliseconds: 1500));
  });

  test('an expired token is refreshable only with soft_logout', () {
    expect(
      _classOf(_matrix('M_UNKNOWN_TOKEN', {'soft_logout': true})),
      SendErrorClass.tokenExpired,
    );
    expect(_classOf(_matrix('M_UNKNOWN_TOKEN')), SendErrorClass.sessionLost);
    expect(_classOf(_matrix('M_MISSING_TOKEN')), SendErrorClass.sessionLost);
  });

  test('permanent server answers', () {
    expect(_classOf(_matrix('M_FORBIDDEN')), SendErrorClass.notAllowed);
    expect(_classOf(_matrix('M_TOO_LARGE')), SendErrorClass.tooLarge);
    expect(_classOf(_matrix('M_BAD_JSON')), SendErrorClass.rejected);
    expect(_classOf(EventTooLarge(60000, 70000)), SendErrorClass.tooLarge);
  });

  test('server and connection failures are retried', () {
    expect(_classOf(_matrix('M_UNKNOWN')), SendErrorClass.server);
    expect(_classOf(Exception('http error response')), SendErrorClass.server);
    expect(_classOf(const SocketException('no route')), SendErrorClass.network);
    expect(_classOf(TimeoutException('slow')), SendErrorClass.network);
  });
}
