import 'package:flutter/foundation.dart';

/// Build-time configuration from `--dart-define`. Values compiled into the app
/// are not secrets; never put credentials here.
class AppConfiguration {
  const AppConfiguration({required this.homeserver, this.push});

  final Uri homeserver;

  /// Null when this build has no push gateway configured: the app then runs
  /// without push notifications.
  final PushConfiguration? push;

  static AppConfiguration fromEnvironment() {
    const homeserverText = String.fromEnvironment(
      'MATRIX_HOMESERVER',
      defaultValue: 'https://secure-chat-poc.duckdns.org',
    );
    final homeserver = Uri.parse(homeserverText);
    _requireHttps(homeserver);
    return AppConfiguration(
      homeserver: homeserver,
      push: PushConfiguration.parse(
        gateway: const String.fromEnvironment('PUSH_GATEWAY_URL'),
        iosAppId: const String.fromEnvironment(
          'PUSH_APP_ID_IOS',
          defaultValue: 'com.example.internalChat.ios',
        ),
        androidAppId: const String.fromEnvironment(
          'PUSH_APP_ID_ANDROID',
          defaultValue: 'com.example.internal_chat.android',
        ),
      ),
    );
  }

  /// Production builds must never talk to a homeserver over plain HTTP.
  static void _requireHttps(Uri uri) {
    final isLocal = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(isLocal && !kReleaseMode)) {
      throw StateError('MATRIX_HOMESERVER must use https.');
    }
  }
}

/// Push notifications through the organization's push gateway (Sygnal),
/// which forwards to Apple (APNs) and Google (FCM). See
/// `docs/push_notifications.md`.
class PushConfiguration {
  const PushConfiguration({
    required this.gateway,
    required this.iosAppId,
    required this.androidAppId,
  });

  /// The gateway's notify endpoint. Synapse accepts only URLs ending in
  /// `/_matrix/push/v1/notify`.
  final Uri gateway;

  /// Sygnal app ID for iOS release builds (production APNs). Debug and
  /// profile builds use the APNs sandbox, so they register as
  /// `<iosAppId>.dev`, which the gateway must also know.
  final String iosAppId;

  /// Sygnal app ID for Android (FCM).
  final String androidAppId;

  static const notifyPath = '/_matrix/push/v1/notify';

  /// Null when [gateway] is empty (push not configured). Throws when it is
  /// set but invalid, so a misconfigured build fails at once.
  static PushConfiguration? parse({
    required String gateway,
    required String iosAppId,
    required String androidAppId,
    bool releaseMode = kReleaseMode,
  }) {
    if (gateway.trim().isEmpty) return null;
    final uri = Uri.parse(gateway.trim());
    final isLocal = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(isLocal && !releaseMode)) {
      throw StateError('PUSH_GATEWAY_URL must use https.');
    }
    if (!uri.path.endsWith(notifyPath)) {
      throw StateError('PUSH_GATEWAY_URL must end with $notifyPath.');
    }
    // Matrix limits app IDs to 64 characters; ".dev" is added in debug.
    for (final id in [iosAppId, androidAppId]) {
      if (id.isEmpty || id.length > 60) {
        throw StateError('Push app IDs must have 1 to 60 characters.');
      }
    }
    return PushConfiguration(
      gateway: uri,
      iosAppId: iosAppId,
      androidAppId: androidAppId,
    );
  }
}
