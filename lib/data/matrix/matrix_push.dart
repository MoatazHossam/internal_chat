import '../../constants.dart';
import '../../domain/push.dart';

const _appDisplayName = 'Internal Chat';

/// The Matrix pusher (`POST /_matrix/client/v3/pushers/set`) for [token].
///
/// `event_id_only`: the homeserver sends the gateway only the room ID, the
/// event ID and unread counts, never the sender, room name or content. On
/// iOS the visible text is fixed here as [alertText] (a generic "New
/// message"); Android builds the same text on the device.
///
/// [production] selects the production APNs app ID (release builds); other
/// iOS builds use the sandbox (`<iosAppId>.dev`).
Map<String, Object?> pusherJson(
  PushToken token,
  PushConfiguration config, {
  required String alertText,
  required String languageCode,
  required String deviceDisplayName,
  required bool production,
}) => {
  'app_id': switch (token.service) {
    PushService.apns => production ? config.iosAppId : '${config.iosAppId}.dev',
    PushService.fcm => config.androidAppId,
  },
  'pushkey': token.value,
  'kind': 'http',
  'app_display_name': _appDisplayName,
  'device_display_name': deviceDisplayName,
  'lang': languageCode,
  'data': {
    'url': config.gateway.toString(),
    'format': 'event_id_only',
    if (token.service == PushService.apns)
      'default_payload': {
        'aps': {
          'alert': {'body': alertText},
          'sound': 'default',
        },
      },
  },
};
