import '../domain/chat_failure.dart';
import '../l10n/app_localizations.dart';

/// The one place that turns a [ChatFailure] into user-facing text. Server
/// error text is never shown.
String failureMessage(AppLocalizations l10n, ChatFailure failure) =>
    switch (failure) {
      RateLimited(:final retryAfter?) when retryAfter.inSeconds > 0 =>
        l10n.errorRateLimitedSeconds(retryAfter.inSeconds),
      RateLimited() => l10n.errorRateLimited,
      NotAllowed() => l10n.errorNotAllowed,
      InvalidCredentials() => l10n.errorInvalidCredentials,
      SessionExpired() => l10n.errorSessionExpired,
      TooLarge(:final maxBytes?) => l10n.errorTooLargeWithLimit(
        formatBytes(maxBytes),
      ),
      TooLarge() => l10n.errorTooLarge,
      NotEncryptedRoom() => l10n.errorNotEncryptedRoom,
      EncryptionUnavailable() => l10n.errorEncryptionUnavailable,
      SecureStorageUnavailable() => l10n.errorSecureStorageUnavailable,
      UnsupportedPlatform() => l10n.errorUnsupportedPlatform,
      Offline() => l10n.errorOffline,
      UserNotFound() => l10n.errorUserNotFound,
      InvalidRecoveryKey() => l10n.errorInvalidRecoveryKey,
      NotAvailable() => l10n.errorNotAvailable,
      UnexpectedFailure() => l10n.errorUnexpected,
    };

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}
