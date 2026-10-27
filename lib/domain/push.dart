/// Which service delivers pushes to this device.
enum PushService {
  /// Apple Push Notification service, used directly on iOS.
  apns,

  /// Firebase Cloud Messaging, on Android.
  fcm,
}

/// This device's push address at [PushService]. Changes from time to time;
/// the app registers the new one with the homeserver.
class PushToken {
  const PushToken(this.service, this.value);

  final PushService service;

  /// APNs: the device token, base64-encoded (what the gateway expects).
  /// FCM: the registration token.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is PushToken && other.service == service && other.value == value;

  @override
  int get hashCode => Object.hash(service, value);
}

/// Registers this device for push notifications with the homeserver.
abstract interface class PushRegistration {
  /// Creates or replaces this device's pusher. Pushes carry only IDs and
  /// counts; the lock screen shows [alertText] (a generic "New message" in
  /// the user's language), never the sender or the content.
  ///
  /// Throws `NotAvailable` when this build has no push gateway configured.
  Future<void> registerPush(
    PushToken token, {
    required String alertText,
    required String languageCode,
  });
}
