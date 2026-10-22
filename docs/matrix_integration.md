# Matrix integration

How the Flutter app talks to the Matrix homeserver, what is implemented, and
what still has to be verified against the POC server. Server facts come from
the backend team's Flutter handover (2026-10-19). This replaces the earlier
REST/SignalR integration requirements, which no longer apply.

## SDK and versions

| Package | Version | Licence | Notes |
|---|---|---|---|
| `matrix` (Famedly) | ^14.1.0 | AGPL-3.0 | Pure Dart. Uses classic `/v3/sync`. Authenticated media supported |
| `flutter_vodozemac` | ^0.8.1 | AGPL-3.0 | 0.9.0 needs `vodozemac` 0.9, which `matrix` 14.1.0 does not accept yet |
| `sqflite_common_ffi` | ^2.4.4 | BSD | Opens the SDK store through `package:sqlite3` |
| `package:sqlite3` | 3.x | MIT; SQLCipher build is BSD-style | Built as SQLCipher via `hooks: user_defines: sqlite3: source: sqlcipher` |

Re-check versions before upgrading: the `matrix` and `flutter_vodozemac`
majors move together.

## Where the SDK is used

Only `lib/data/matrix/` imports the SDK:

| File | Responsibility |
|---|---|
| `matrix_chat_backend.dart` | Owns the `Client`; implements `ChatSession`, `Conversations`, `Messages`, `DeviceTrust` |
| `matrix_store.dart` | Opens the SQLCipher store; key in Keychain/Keystore; fails closed |
| `matrix_mappers.dart` | `Room` → `Conversation`, `Timeline`/`Event` → `ChatMessage` |
| `matrix_errors.dart` | SDK and network exceptions → `ChatFailure` |
| `matrix_verification.dart` | `KeyVerification` → domain `VerificationRequest` (emoji/SAS) |

`lib/data/backend_factory.dart` creates the adapter. Web builds never compile
it (conditional import), because it needs FFI; they get
`unsupported_platform_backend.dart`, which stops at the start screen.

## Feature mapping

| Feature | Implementation |
|---|---|
| Sign-in | `checkHomeserver` (well-known) + `login(m.login.password)`; refresh tokens requested |
| Direct chat | `startDirectChat` with `trusted_private_chat`, explicit `m.room.encryption`, `m.direct`; an unencrypted existing DM is not reused |
| Group | `createGroupChat` with `private_chat`, explicit `m.room.encryption`, `m.federate: false` |
| Invites | Shown first in the list; accept = `join`, decline = `leave` |
| Members | `requestParticipants`; invite = `invite`; remove = `kick` (when power levels allow) |
| Text | `sendTextEvent` with `parseCommands: false`, `parseMarkdown: false` |
| Image / file | `sendFileEvent` (SDK encrypts, AES-256-CTR; thumbnails for images) |
| Voice note | `m.audio` with `org.matrix.msc3245.voice` and `org.matrix.msc1767.audio` |
| Reply | `inReplyTo` |
| Edit | `editEventId` (`m.replace`) |
| Delete | `redactEvent`; unsent local echoes are discarded instead |
| Reactions | `sendReaction` (`m.annotation`); tapping again redacts it |
| Read receipts | `setReadMarker` (`m.fully_read`, `m.read`, `m.read.private`) for the newest message while the conversation is open and the app is in the foreground |
| Read ticks | A message is "read" when another member's receipt points at it or a later event. No delivery ticks |
| Typing | `setTyping` (throttled, 30 s timeout); others' typing from sync |
| History | `Timeline.requestHistory` when scrolling up |
| Media limit | `getConfig()` → `m.upload.size`, checked before reading the file |
| Downloads | `downloadAndDecryptAttachment` (authenticated media), kept in memory |

## Security rules (from the handover) and where they live

| Rule | Where |
|---|---|
| Explicit `m.room.encryption` on every new room | `openDirect`, `createGroup` |
| Refuse to send into unencrypted rooms; no plaintext fallback | `ensureEncryptedSend` (`domain/send_guard.dart`), called before every send, reaction and edit. Also refuses when encryption is not running, because the SDK would otherwise send plaintext into an encrypted room |
| Room names are server-visible | Group dialog tells users to keep names generic |
| Local store and keys encrypted at rest | `matrix_store.dart`: SQLCipher, random 256-bit key in Keychain (`first_unlock_this_device`) / Keystore. Startup stops with an error if either is unavailable |
| Never log tokens, bodies or keys | SDK `logLevel: Level.error`; failures carry no server text |

Additional choices:

* The SDK's media file cache is not used: it writes **decrypted** attachments
  to disk. As a result, failed attachment uploads cannot be retried.
* Voice-note playback writes the decrypted audio to a temporary file (the
  platform players need one) and deletes it when the player closes.
* Recordings and picker copies are deleted as soon as their bytes are read.
* Android backups and device transfer are disabled.

## Errors across the boundary

| SDK / transport | Domain |
|---|---|
| `M_LIMIT_EXCEEDED` | `RateLimited(retryAfter)` |
| `M_FORBIDDEN`, `M_USER_DEACTIVATED` | `NotAllowed` (`InvalidCredentials` at sign-in) |
| `M_UNKNOWN_TOKEN` | `SessionExpired(softLogout)` |
| `M_TOO_LARGE`, HTTP 413, file over the media limit | `TooLarge(maxBytes)` |
| `M_NOT_FOUND` on invite/create | `UserNotFound` |
| Socket, HTTP client, timeout, sync connection errors | `Offline` |
| Wrong recovery key | `InvalidRecoveryKey` |
| Unencrypted room / encryption not running | `NotEncryptedRoom` / `EncryptionUnavailable` |
| Store or key unavailable | `SecureStorageUnavailable` |
| Anything else | `UnexpectedFailure` |

## Idempotent sending

* The controller creates one `LocalMessageId` per tap.
* The adapter passes it as the Matrix transaction ID. The SDK stores the local
  echo (event ID = transaction ID) in the encrypted store, so it survives a
  restart.
* `Event.sendAgain()` reuses the transaction ID; retries cannot duplicate.
* Offline: the SDK retries for `sendTimelineEventTimeout` (2 minutes), then
  marks the message failed. After reconnecting, the adapter retries failed
  messages in open conversations once per app run. Users can retry any failed
  message by tapping it.

## Verification and recovery

* **Set up recovery** (account has no crypto identity): `initCryptoIdentity()`
  creates SSSS, cross-signing and the online key backup and returns the
  recovery key. Cross-signing upload may require user-interactive auth; the
  adapter answers the `m.login.password` stage once with the password the user
  just entered (never stored) and fails with `InvalidCredentials` if the
  server rejects it.
* An identity "exists" if the account has a **published master key**, even
  without a recovery key: Element X bootstraps cross-signing at sign-in without
  secret storage. The app never runs setup over an existing identity, because
  that would replace it and untrust the user's Element devices. Healing a
  partial identity (or adding a recovery key to an Element-created one) is not
  implemented.
* "Verified" means this device is signed by the account's self-signing key.
  That is what other clients check: with the SDK default
  `ShareKeysWith.crossVerifiedIfEnabled` (and Element's equivalent), room keys
  are **not shared with devices their owner has not cross-signed**. An
  unverified Flutter device therefore cannot read new messages from users who
  have cross-signing. This is intended; verification is required.
* **Restore** (identity exists, this device not connected):
  `restoreCryptoIdentity(recoveryKey)`, then `keyManager.loadAllKeys()` to
  import earlier room keys from the backup.
* **Emoji verification:** incoming requests from `onKeyVerificationRequest`
  open a dialog; "Verify with another device" starts a self-verification with
  `userDeviceKeys[me].startVerification()`. Only SAS (emoji/numbers) is
  offered; QR is not.

## SDK spike checklist (handover section 7)

Run against the POC with a dedicated account
(`sudo ./scripts/provision-users.sh flutter-dev1`) and synthetic content only.

| # | Check | Status |
|---|---|---|
| 1 | Sign in; read `/versions`; sync survives restarts | **Passed on iOS simulators (2026-10-20)** with `moataz` and `kamel`: sign-in, first sync, existing DM listed, session kept across a reinstall |
| 2 | Encrypted DM with an Element X user, both directions | Partly verified: sending works and read receipts arrive. The other side's new, unverified Flutter device does not receive the room key (by design, see "Verification and recovery"). Needs emoji verification of each Flutter device from the user's Element device first |
| 3 | Refuse to send in an unencrypted room | Implemented and unit-tested (guard + test fixture); to verify against a real unencrypted room |
| 4 | Verify from Element (emoji); set up recovery; restore on a second device | Implemented; to verify on device |
| 5 | 25 MiB upload accepted, 25 MiB + 1 byte rejected cleanly; authenticated download | Implemented (limit read from the server); to verify on device |
| 6 | Airplane mode, queue, reconnect, no duplicates | Implemented; to verify on device |
| 7 | iOS and Android builds including `flutter_vodozemac` on CI | Passes locally: iOS simulator (SPM prebuilt) and Android release APK for arm64 (Rust via `rustup`; ~5 min first build). The APK starts on an API 33 emulator. CI not set up yet |
| 8 | Licence decision recorded | Recorded as "accepted for POC, legal review pending" (README) |

## Known limitations

* Web is not supported until a vodozemac WASM pipeline exists.
* No push notifications (needs a push gateway; owner approval).
* Soft logout without a refresh token clears the session; the user signs in
  again as a new device and restores history with the recovery key.
* Failed messages in conversations that are not open are not retried
  automatically; failed attachments cannot be retried.
* Not yet verified: whether iOS plays Ogg/Opus voice messages, which Element
  on Android and web may send. Android's player supports them.
* In-conversation search covers loaded messages only (no server-side search
  for encrypted rooms).
* Device retention is not enforced.
