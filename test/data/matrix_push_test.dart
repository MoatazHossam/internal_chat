import 'package:flutter_test/flutter_test.dart';
import 'package:internal_chat/constants.dart';
import 'package:internal_chat/data/matrix/matrix_push.dart';
import 'package:internal_chat/domain/push.dart';

final _config = PushConfiguration(
  gateway: Uri.parse('https://push.example.org/_matrix/push/v1/notify'),
  iosAppId: 'org.example.chat.ios',
  androidAppId: 'org.example.chat.android',
);

Map<String, Object?> _pusher(PushToken token, {bool production = true}) =>
    pusherJson(
      token,
      _config,
      alertText: 'New message',
      languageCode: 'en',
      deviceDisplayName: 'Internal Chat (iOS)',
      production: production,
    );

void main() {
  group('pusher', () {
    test('iOS: generic alert text, IDs only, production APNs', () {
      final pusher = _pusher(const PushToken(PushService.apns, 'dG9rZW4='));

      expect(pusher['app_id'], 'org.example.chat.ios');
      expect(pusher['pushkey'], 'dG9rZW4=');
      expect(pusher['kind'], 'http');
      expect(pusher['lang'], 'en');
      expect(pusher['data'], {
        'url': 'https://push.example.org/_matrix/push/v1/notify',
        'format': 'event_id_only',
        'default_payload': {
          'aps': {
            'alert': {'body': 'New message'},
            'sound': 'default',
          },
        },
      });
    });

    test('iOS debug builds use the APNs sandbox app ID', () {
      final pusher = _pusher(
        const PushToken(PushService.apns, 'dG9rZW4='),
        production: false,
      );
      expect(pusher['app_id'], 'org.example.chat.ios.dev');
    });

    test('Android: data only, the device shows the text', () {
      final pusher = _pusher(const PushToken(PushService.fcm, 'fcm-token'));

      expect(pusher['app_id'], 'org.example.chat.android');
      expect(pusher['data'], {
        'url': 'https://push.example.org/_matrix/push/v1/notify',
        'format': 'event_id_only',
      });
    });
  });

  group('push configuration', () {
    PushConfiguration? parse(String gateway, {bool release = true}) =>
        PushConfiguration.parse(
          gateway: gateway,
          iosAppId: 'org.example.chat.ios',
          androidAppId: 'org.example.chat.android',
          releaseMode: release,
        );

    test('no gateway: push is off', () {
      expect(parse(''), isNull);
    });

    test('accepts the notify endpoint over https', () {
      expect(
        parse('https://push.example.org/_matrix/push/v1/notify')?.gateway.host,
        'push.example.org',
      );
    });

    test('rejects plain http, except localhost in debug builds', () {
      expect(
        () => parse('http://push.example.org/_matrix/push/v1/notify'),
        throwsStateError,
      );
      expect(
        parse('http://localhost:5000/_matrix/push/v1/notify', release: false),
        isNotNull,
      );
    });

    test('rejects a URL Synapse would refuse', () {
      expect(() => parse('https://push.example.org/notify'), throwsStateError);
    });
  });
}
