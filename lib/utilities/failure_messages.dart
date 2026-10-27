import '../domain/chat_failure.dart';
import '../l10n/app_localizations.dart';
import '../models/chat_message.dart';

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
      LocalDataUnreadable() => l10n.errorLocalDataUnreadable,
      UnsupportedPlatform() => l10n.errorUnsupportedPlatform,
      Offline() => l10n.errorOffline,
      UserNotFound() => l10n.errorUserNotFound,
      InvalidRecoveryKey() => l10n.errorInvalidRecoveryKey,
      DeliveryUncertain() => l10n.errorDeliveryUncertain,
      NotAvailable() => l10n.errorNotAvailable,
      UnexpectedFailure() => l10n.errorUnexpected,
    };

/// Why a message from this device was not sent.
String sendFailureMessage(AppLocalizations l10n, SendFailureReason? reason) =>
    switch (reason) {
      SendFailureReason.notAllowed => l10n.sendFailedNotAllowed,
      SendFailureReason.tooLarge => l10n.sendFailedTooLarge,
      SendFailureReason.notEncrypted => l10n.sendFailedNotEncrypted,
      SendFailureReason.encryptionUnavailable =>
        l10n.sendFailedEncryptionUnavailable,
      SendFailureReason.rejected => l10n.sendFailedRejected,
      SendFailureReason.uncertain => l10n.sendFailedUncertain,
      SendFailureReason.notResendable => l10n.sendFailedNotResendable,
      SendFailureReason.server || null => l10n.sendFailedServer,
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
