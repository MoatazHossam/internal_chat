# Push notifications

How Internal Chat gets notifications onto locked phones, what has to be
replaced with the organization's real accounts, and what is still untested.

## How it works

```text
Synapse ──(IDs and counts only)──▶ Sygnal (push gateway, run by the organization)
                                     ├──▶ APNs (Apple) ──▶ iPhone
                                     └──▶ FCM (Google) ──▶ Android phone
```

1. After sign-in the app asks for permission to show notifications, gets a
   push token from the phone and registers a **pusher** with Synapse
   (`POST /_matrix/client/v3/pushers/set`).
2. When a message arrives that the user's push rules notify about, Synapse
   posts to the gateway. The pusher uses the format **`event_id_only`**:
   Synapse sends only the room ID, the event ID and unread counts. No
   sender, room name or content (the content is end-to-end encrypted
   anyway).
3. The gateway forwards to Apple or Google, which deliver it to the phone.
4. The phone shows **"New message"** (in the app's language). The lock
   screen never shows the sender or the text, as the README requires.
5. Tapping the notification opens the conversation.

| | iOS | Android |
|---|---|---|
| Delivery | APNs directly, **no Google SDK** | FCM (Firebase Messaging SDK only; no analytics) |
| Token | APNs device token, base64 (what Sygnal expects) | FCM registration token |
| Visible text | Inside the push: the app puts "New message" in its language into the pusher (`default_payload.aps.alert.body`) | Built on the phone by `PushMessagingService` from a data message; the text is stored when the app registers |
| Code | `ios/Runner/AppDelegate.swift` (`PushNotificationsPlugin`), `ios/Runner/Runner.entitlements` | `MainActivity.kt`, `PushMessagingService.kt`, `PushNotifications.kt`, `AndroidManifest.xml`, `build.gradle.kts` |
| Updates without a message (unread count after reading elsewhere) | Sygnal sends them as a badge update without the alert (to verify, see below) | Ignored (no `event_id`) |

Dart side: `lib/services/push_platform.dart` (platform channel
`internal_chat/push`), `lib/modules/push/push_controller.dart` (when to
register), `lib/data/matrix/matrix_push.dart` (the pusher) and
`registerPush` in `matrix_chat_backend.dart`.

### When the app registers

* After every sign-in and at every app start while signed in (so a pusher
  lost on the server comes back).
* When APNs or FCM issues a new token.
* When the user changes the app language (the text is in the pusher).
* With `append: false`: if another account was registered with the same
  phone, its pusher is replaced, so a shared phone never shows another
  user's notifications.

Synapse deletes the pusher when the device signs out.

### On the phone

* **App in the foreground:** no banner; the conversation list updates live.
* **Notifications are cleared** when the app comes to the front. On iOS the
  badge is reset too.
* **Android:** one notification per conversation (a newer message replaces
  it), channel "Messages", importance high, visible on the lock screen
  (the text is generic).
* **Settings → Notifications** shows the state: on; not set up in this
  build; off (with a link to the system settings); or unavailable (tap to
  retry).

### Privacy

Apple or Google, and the gateway, see: that a message arrived, when, the
room ID, the event ID, the unread count and the push token. On iOS they also
see the fixed text "New message". They never see the sender, the room name
or the content.

## What to replace with the real accounts

| # | What | Where | Now |
|---|---|---|---|
| 1 | iOS bundle ID and signing team | Xcode → Runner target → *Signing & Capabilities* | `com.example.internalChat`, no team |
| 2 | Push capability on the App ID | Apple Developer → Identifiers. With automatic signing Xcode adds it, because the app has `aps-environment` in `Runner.entitlements` | — |
| 3 | APNs authentication key (`.p8`), its Key ID and the Team ID | Apple Developer → Keys → *Apple Push Notifications service*. Goes **to the gateway**, never into the app | — |
| 4 | Android application ID | `applicationId` in `android/app/build.gradle.kts` | `com.example.internal_chat` |
| 5 | Firebase project with an Android app for that ID; download `google-services.json` | Save as `android/app/google-services.json`. Without it the app builds and runs, but without push on Android | missing |
| 6 | Firebase service-account key (role: *Firebase Cloud Messaging API*) | **To the gateway** | — |
| 7 | Push gateway | Deploy Sygnal with [`push/sygnal.yaml`](push/sygnal.yaml) behind TLS (owner approval needed: it adds a server) | not deployed |
| 8 | Build flags | `--dart-define=PUSH_GATEWAY_URL=https://<gateway>/_matrix/push/v1/notify`; if you change the app IDs in Sygnal, also `--dart-define=PUSH_APP_ID_IOS=…` and `--dart-define=PUSH_APP_ID_ANDROID=…` | not set: push off |
| 9 | Synapse | Must reach the gateway. If the gateway has a private IP address, add it to `ip_range_whitelist` | — |

App IDs (defaults; they must match the keys under `apps:` in Sygnal):

| Build | App ID | APNs |
|---|---|---|
| iOS release (TestFlight, App Store, enterprise) | `com.example.internalChat.ios` (`PUSH_APP_ID_IOS`) | production |
| iOS debug / profile (from Xcode) | `com.example.internalChat.ios.dev` | sandbox |
| Android | `com.example.internal_chat.android` (`PUSH_APP_ID_ANDROID`) | — |

The app checks the flags at start: the gateway URL must use `https` (plain
`http` only for `localhost` in debug builds) and end with
`/_matrix/push/v1/notify`, which Synapse requires.

Example build:

```bash
flutter build ipa --dart-define=PUSH_GATEWAY_URL=https://push.example.org/_matrix/push/v1/notify
```

## Test status

**Automated (host only):** 15 tests, in the 107 that pass:

* `push_controller_test.dart` (8): registers after sign-in with the generic
  text in the app's language; registers again for a new token or language
  and not otherwise; nothing when push is not configured or before sign-in;
  reports a refused permission, a missing token and server errors; taps
  (including a tap that started the app) become open requests; registers
  again after signing out and in.
* `matrix_push_test.dart` (7): the pusher for iOS (production and sandbox
  app IDs, generic alert, `event_id_only`) and Android (data only); the
  gateway URL rules.

**Builds (2026-10-27):** the iOS simulator build compiles the Swift code and
contains the `aps-environment` entitlement; the Android release build
compiles the Kotlin code and its manifest has the notification permission
and the FCM service. The Android build ran **without** `google-services.json`;
a build with Firebase applied has not been tried. See the
[Matrix integration test status](matrix_integration.md#test-status-2026-10-27).

**Not tested at all yet**, because there is no gateway or accounts: real
delivery on any device, simulator or phone. Once the accounts exist, check:

* [ ] iPhone, app closed and locked: "New message" appears (English and
      Arabic), no sender or text; tap opens the conversation.
* [ ] iPhone: reading the message on another device updates the badge
      **without** a second banner (Sygnal sends badge-only updates without
      the default alert; confirm with your Sygnal version).
* [ ] Android, app killed: notification appears; tap opens the conversation.
* [ ] Android: devices with aggressive battery savers (some vendors) still
      receive high-priority FCM messages.
* [ ] App in the foreground: no banner; opening the app clears notifications.
* [ ] Signing out stops notifications (Synapse removed the pusher); signing
      in as another user on the same phone shows only that user's.
* [ ] Notifications keep arriving after the access token was refreshed
      several times (the POC server rotates it every 5 minutes; check that
      Synapse keeps the pusher).
* [ ] Settings → Notifications shows "Off" after permission is refused and
      the link opens the system settings.

## Limitations

* The text is always "New message": no sender, preview, mentions or
  per-conversation settings. This is the documented requirement, not a gap.
* No notification sound or channel settings beyond the platform defaults.
* iOS badges come only from the gateway's unread-count updates and are
  cleared when the app opens; they are not kept exactly in sync.
* Notifications also follow the user's Matrix push rules (for example
  invitations notify as "New message").
* The pusher includes the device display name ("Internal Chat (iOS)") and
  the app's language, which the homeserver and the gateway can see.
