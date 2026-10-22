import 'package:flutter/foundation.dart';

/// Build-time configuration from `--dart-define`. Values compiled into the app
/// are not secrets; never put credentials here.
class AppConfiguration {
  const AppConfiguration({required this.homeserver});

  final Uri homeserver;

  static AppConfiguration fromEnvironment() {
    const homeserverText = String.fromEnvironment(
      'MATRIX_HOMESERVER',
      defaultValue: 'https://secure-chat-poc.duckdns.org',
    );
    final homeserver = Uri.parse(homeserverText);
    _requireHttps(homeserver);
    return AppConfiguration(homeserver: homeserver);
  }

  /// Production builds must never talk to a homeserver over plain HTTP.
  static void _requireHttps(Uri uri) {
    final isLocal = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(isLocal && !kReleaseMode)) {
      throw StateError('MATRIX_HOMESERVER must use https.');
    }
  }
}
