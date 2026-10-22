import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import '../../domain/chat_failure.dart';

/// Translates anything the SDK or the network throws into a [ChatFailure].
///
/// [notFound] lets callers say what `M_NOT_FOUND` means for their request
/// (for example an unknown user when inviting).
ChatFailure toChatFailure(Object error, {ChatFailure? notFound}) {
  return switch (error) {
    ChatFailure() => error,
    FileTooBigMatrixException() => TooLarge(maxBytes: error.maxFileSize),
    EventTooLarge() => TooLarge(maxBytes: error.maxSize),
    MatrixException() => _fromMatrixException(error, notFound: notFound),
    InvalidPassphraseException() => const InvalidRecoveryKey(),
    SyncConnectionException() ||
    SocketException() ||
    http.ClientException() ||
    TimeoutException() ||
    HandshakeException() => const Offline(),
    _ => const UnexpectedFailure(),
  };
}

ChatFailure _fromMatrixException(
  MatrixException error, {
  ChatFailure? notFound,
}) {
  switch (error.error) {
    case MatrixError.M_LIMIT_EXCEEDED:
      final ms = error.retryAfterMs;
      return RateLimited(ms == null ? null : Duration(milliseconds: ms));
    case MatrixError.M_FORBIDDEN:
    case MatrixError.M_USER_DEACTIVATED:
      return const NotAllowed();
    case MatrixError.M_UNKNOWN_TOKEN:
      return SessionExpired(softLogout: error.raw['soft_logout'] == true);
    case MatrixError.M_TOO_LARGE:
      return const TooLarge();
    case MatrixError.M_NOT_FOUND:
      return notFound ?? const UnexpectedFailure();
    default:
      if (error.response?.statusCode == 413) return const TooLarge();
      return const UnexpectedFailure();
  }
}
