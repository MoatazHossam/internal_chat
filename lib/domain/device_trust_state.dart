enum TrustState {
  /// Still loading the account's cross-signing and backup state.
  unknown,

  /// End-to-end encryption is not running on this device.
  encryptionUnavailable,

  /// The account has no cross-signing identity at all. Set one up once.
  needsRecoverySetup,

  /// The account has a cross-signing identity and a recovery key, but this
  /// device is not verified. Verify with another device or enter the recovery
  /// key. Until then other users' devices do not share room keys with it.
  unverified,

  /// The account has a cross-signing identity (for example created by
  /// Element) but no recovery key. Only verification from one of the user's
  /// other devices can verify this one.
  unverifiedNoRecoveryKey,

  /// This device is cross-signed by the account's identity.
  verified,
}

/// A recovery key, shown to the user once. It unlocks secret storage and the
/// online key backup. It is never logged or stored by the app.
extension type const RecoveryKey(String value) {}

class SasEmoji {
  const SasEmoji(this.emoji, this.name);

  final String emoji;

  /// English name from the Matrix spec emoji table.
  final String name;
}

sealed class VerificationStep {
  const VerificationStep();
}

/// Another device or user asks to verify; accept or decline.
final class VerificationIncoming extends VerificationStep {
  const VerificationIncoming();
}

final class VerificationWaiting extends VerificationStep {
  const VerificationWaiting();
}

/// Compare these emojis with the other device.
final class VerificationCompareEmojis extends VerificationStep {
  const VerificationCompareEmojis(this.emojis);

  final List<SasEmoji> emojis;
}

final class VerificationDone extends VerificationStep {
  const VerificationDone();
}

final class VerificationCancelled extends VerificationStep {
  const VerificationCancelled({this.byOtherSide = false});

  final bool byOtherSide;
}

/// One emoji (SAS) verification, incoming or outgoing.
abstract interface class VerificationRequest {
  /// True when verifying one of this account's own devices.
  bool get isSelfVerification;
  String get otherUserId;
  String? get otherDeviceId;

  VerificationStep get step;
  Stream<VerificationStep> get steps;

  Future<void> accept();
  Future<void> confirmEmojisMatch();
  Future<void> rejectEmojis();
  Future<void> cancel();
}
