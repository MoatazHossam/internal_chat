# Matrix integration

How the Flutter app talks to the Matrix homeserver, what is implemented, and
what still has to be verified against the POC server. Server facts come from
the backend team's Flutter handover (2026-10-19) and its follow-up on
messaging (`flutter-followup-messaging.md`). This replaces the earlier
REST/SignalR integration requirements, which no longer apply.

## SDK and versions

| Package | Version | Licence | Notes |
|---|---|---|---|
| `matrix` (Famedly) | ^14.1.0 | AGPL-3.0 | Pure Dart. Uses classic `/v3/sync`. Authenticated media supported |
| `flutter_vodozemac` | ^0.8.1 | AGPL-3.0 | 0.9.0 needs `vodozemac` 0.9, which `matrix` 14.1.0 does not accept yet |
| `sqflite_common_ffi` | ^2.4.4 | BSD | Opens the local databases through `package:sqlite3` |
| `package:sqlite3` | 3.x | MIT; SQLCipher build is BSD-style | Built as SQLCipher via `hooks: user_defines: sqlite3: source: sqlcipher` |

Re-check versions before upgrading: the `matrix` and `flutter_vodozemac`
majors move together.

## Where the SDK is used

Only `lib/data/matrix/` imports the SDK:

| File | Responsibility |
|---|---|
| `matrix_chat_backend.dart` | Owns the `Client`; implements `ChatSession`, `Conversations`, `Messages`, `DeviceTrust` |
| `matrix_store.dart` | Opens the two SQLCipher databases (SDK store and outbox); key in Keychain/Keystore; fails closed and never deletes data on its own |
| `matrix_mappers.dart` | `Room` → `Conversation`, `Timeline`/`Event` → `ChatMessage`, outbox entries → `ChatMessage` |
| `matrix_errors.dart` | SDK and network exceptions → `ChatFailure` |
| `matrix_verification.dart` | `KeyVerification` → domain `VerificationRequest` (emoji/SAS) |
| `outbox/matrix_outbox_transport.dart` | Encrypts, uploads and sends outbox entries; classifies failures; searches history for delivered transaction IDs |

The rest of `outbox/` has no SDK imports and is tested on its own:

| File | Responsibility |
|---|---|
| `outbox/outbox_entry.dart` | One pending message, its state and the classes of send failures |
| `outbox/outbox_store.dart` | Durable storage of entries and attachment bytes (SQLite table `outbox`) |
| `outbox/outbox_worker.dart` | The app-wide sender: ordering, retries, backoff, token refresh, reconciliation |
| `outbox/forward_content.dart` | Builds the content of a forwarded copy |

`lib/data/backend_factory.dart` creates the adapter. Web builds never compile
it (conditional import), because it needs FFI; they get
`unsupported_platform_backend.dart`, which stops at the start screen.

## Feature mapping

| Feature | Implementation |
|---|---|
| Sign-in | **POC authentication:** `checkHomeserver` (well-known) + `login(m.login.password)`; refresh tokens requested. Production will use on-premises Active Directory with MFA; that integration is not designed yet |
| Direct chat | `startDirectChat` with `trusted_private_chat`, explicit `m.room.encryption`, `m.direct`; an unencrypted existing DM is not reused |
| Group | `createGroupChat` with `private_chat`, explicit `m.room.encryption`, `m.federate: false` |
| Invites | Shown first in the list; accept = `join`, decline = `leave` |
| Members | `requestParticipants`; invite = `invite`; remove = `kick` (when power levels allow) |
| Text | Outbox → `m.text`, plain body (no Markdown, no commands) |
| Image / file | Outbox → encrypted with AES-256-CTR (new key per file), uploaded, `file` object in the event; images get an encrypted thumbnail (`thumbnail_file`) |
| Voice note | Outbox → `m.audio` with `org.matrix.msc3245.voice` and `org.matrix.msc1767.audio` (duration) |
| Reply | `m.relates_to.m.in_reply_to`, without the deprecated quoted fallback text |
| Forward | Outbox → a new encrypted event per destination (see [Forwarding](#forwarding)) |
| Edit | `editEventId` (`m.replace`) through the SDK |
| Delete | `redactEvent`; a message not sent yet is removed from the outbox instead |
| Reactions | `sendReaction` (`m.annotation`); tapping again redacts it |
| Read receipts | `setReadMarker` (`m.fully_read`, `m.read`, `m.read.private`) for the newest message while the conversation is open and the app is in the foreground |
| Read ticks | A message is "read" when another member's receipt points at it or a later event. No delivery ticks |
| Typing | `setTyping` (throttled, 30 s timeout); others' typing from sync |
| History | `Timeline.requestHistory` when scrolling up |
| Media limit | `getConfig()` → `m.upload.size`, checked before reading the file (skipped when the server cannot be reached; the upload then fails with "too large" if it is) |
| Downloads | `downloadAndDecryptAttachment` (authenticated media), kept in memory |

Reactions, edits and redactions still use the SDK's own send queue; they are
not part of the outbox.

## Security rules (from the handover) and where they live

| Rule | Where |
|---|---|
| Explicit `m.room.encryption` on every new room | `openDirect`, `createGroup` |
| Refuse to send into unencrypted rooms; no plaintext fallback | `ensureEncryptedSend` (`domain/send_guard.dart`), called before every send, reaction and edit, and again by the outbox before each attempt. The outbox also refuses when encryption returns no ciphertext |
| Room names are server-visible | Group dialog tells users to keep names generic |
| Local store and keys encrypted at rest | `matrix_store.dart`: two SQLCipher databases (SDK store and outbox) with one random 256-bit key in Keychain (`first_unlock_this_device`) / Keystore. See [Local data: startup errors and reset](#local-data-startup-errors-and-reset) |
| Never log tokens, bodies or keys | SDK `logLevel: Level.error`; failures carry no server text; the outbox logs (debug builds only) a transaction-ID prefix and an error class, never content |

Additional choices:

* The SDK's media file cache is not used: it writes **decrypted** attachments
  to disk. Attachments waiting to be sent are kept in the encrypted outbox
  database instead, so they can be retried after a restart.
* Plaintext media that must exist as a file for a moment (a recording until
  its bytes are read; a decrypted voice note while the platform player plays
  it) lives in one temporary directory. It is deleted when the player
  closes, and the whole directory (plus the file picker's copies) is deleted
  at every app start and at sign-out, so files left by a killed app do not
  remain.
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
| Keychain/Keystore unreadable, or SQLCipher missing | `SecureStorageUnavailable` |
| Store files without their key, or a key that does not open them | `LocalDataUnreadable` |
| "Send again" on a message whose delivery is uncertain, without the user's confirmation | `DeliveryUncertain` |
| Anything else | `UnexpectedFailure` |

Inside the outbox, failures are kept as a `SendErrorClass` (network, server,
rate limited, token expired, session lost, not allowed, too large, not
encrypted, encryption unavailable, rejected, uncertain) and shown on failed
messages as a localized reason.

## Offline sending (outbox)

Implements section 1 of the backend's follow-up (F1–F7). The app does not use
the SDK's `Room.sendEvent` for messages: it retries internally, hides why a
request failed and gives up on an expired token without refreshing.

**Durable and encrypted.** Text, images, files, voice notes and forwards are
written to the outbox before the first attempt: a separate SQLCipher
database (`internal_chat_outbox.sqlite`) with the same key as the SDK store.
Entries include attachment bytes and, once uploaded, the event content with
the attachment's key. They survive restarts, belong to one account (entries
of another account are never loaded or sent) and are deleted with the rest of
the user's data at sign-out.

**One sender for the whole app.** `OutboxWorker` runs while the app runs and
sends for every conversation, open or not. Within a conversation, messages
go out in the order they were written; a message waiting to be retried holds
back the ones after it. Conversations do not hold each other back. It starts
on sign-in and app start, and runs again when a message is queued, when the
connection returns and on a timer. The timer is set only for the next
message that can actually go (the first waiting message of each conversation
not being sent right now), so it does not wake while a send is in progress.

**Same transaction ID on every retry.** The `LocalMessageId` created at the
tap is the Matrix transaction ID (`PUT /rooms/{roomId}/send/m.room.encrypted/{txnId}`).
Every retry from the same device reuses it, so within the server's window
(24 hours, per device and room) a repeat returns the same event.

**Retries by failure class.**

| Failure | What happens |
|---|---|
| No connection, timeout | Waits; retried with backoff (about 2 s doubling to 5 min, ±20 % jitter), and at once when sync reconnects. Shown as "waiting for network" |
| `5xx`, unexplained error | Retried with backoff; after 8 in a row the message stops as failed |
| `429` | Waits `retry_after_ms`, for every conversation (the limit is per user) |
| `401` `M_UNKNOWN_TOKEN` with `soft_logout` | Refreshes the token through the SDK's shared refresh (the same one the sync loop uses), then retries at once with the same transaction ID; a second expiry in a row backs off. Tokens about to expire are refreshed before each attempt |
| Session lost (refresh rejected, hard logout) | Kept; reconsidered after the next sign-in |
| `403`, too large, room not encrypted, encryption not running, other `4xx` | Stops as failed with a reason; the user can retry or delete |

Each request has its own time limit (60 s to encrypt, 60 s to send; uploads
60 s plus 1 s per 64 KiB). Uploads do not count as attempts: they cannot
create a message. An attempt is recorded **before** the request, so if the
app dies mid-request the message counts as possibly delivered.

**States the user sees.** Sending (clock), waiting for network (cloud), sent
(one tick, only once the server returned the event ID), read (two ticks),
failed (with the reason and *Retry*, *Send again* or *Delete*). Unsent
messages are shown from the outbox, at the end of the conversation. When
the send succeeds, the event is stored like the SDK does after its own sends
and the outbox entry is removed; sync later replaces it with the server's
copy under the same event ID, so it never appears twice.

**Delivered but the response was lost.** If sync shows an event with one of
this device's transaction IDs, the entry is completed without sending again.
Before resending an entry that was already attempted, the worker also looks
for that transaction ID among the stored events.

### Uncertain delivery

The server's deduplication lasts 24 hours and is scoped to the sending
device. Outside that, a resend would create a second message, so the worker
never resends blindly:

* **Attempted more than 23 hours ago (same device):** it pages back through
  the room's history (`/messages`, filtered to the user's own events) looking
  for `unsigned.transaction_id`, which the server shows only to the sending
  device. Found: completed. History before the first attempt (or the start
  of the room) searched without finding it: sent again. Paging continues
  past empty pages as long as the server returns a next-page token, as the
  Matrix spec requires; an empty page is not the end. If 20 pages are not
  enough, or the server stops moving on, the result is *uncertain*.
* **Queued on another device (after a new sign-in):** never attempted there:
  sent from this device. Attempted there: *uncertain*, because this device
  can neither reuse nor look up the other device's transaction IDs.
* **Uncertain** messages stop with the reason "It is not certain whether this
  message arrived". *Send again* asks for confirmation ("If it did, sending it
  again will show it twice") and then sends it as a new message with a new
  transaction ID. *Delete* removes the local copy only.

### What the outbox does not do

* **No background sending.** Nothing is sent while iOS or Android suspends
  the app; the queue continues when the app is opened again.
* Unsent messages do not appear in the conversation-list preview.
* Attachments that failed in a build before the outbox (SDK local echoes)
  cannot be resent; they show "This attachment can't be resent". Failed text
  from those builds moves into the outbox when retried.

## Forwarding

Implements section 2 of the follow-up. Long-press → *Forward* → choose one or
more conversations. Only sent, readable text, images, files, voice notes and
audio can be forwarded.

* Each destination gets a **new encrypted event** with its own
  `LocalMessageId` and transaction ID, through the outbox (so it is retried
  like any other message). The destination must be a joined, encrypted room.
* **Text:** the body only (with any old quoted reply fallback removed). No
  `m.relates_to`, edits or formatted body.
* **Media:** the original `file` object (`url`, `key`, `iv`, `hashes`) and
  `info` (MIME type, size, dimensions, duration, `thumbnail_file`) are
  reused, so nothing is uploaded again; the key travels inside the new
  Megolm-encrypted event. Voice notes keep `org.matrix.msc3245.voice` and
  `org.matrix.msc1767.audio`.
* A UI-only marker `im.internal_chat.forwarded: true` shows "Forwarded" on the
  copy. It proves nothing about where the message came from.
* Protected messages (section 3 of the follow-up) are not built; there is
  nothing protected to exclude yet.

## Local data: startup errors and reset

Opening the local databases fails closed and **never deletes data on its
own**:

| Situation | Start screen |
|---|---|
| Keychain/Keystore cannot be read (for example before the first unlock after a restart) | `SecureStorageUnavailable`: *Retry* only |
| SQLCipher is not linked | `SecureStorageUnavailable`: *Retry* only |
| Database files exist but their key is missing (for example files restored from a backup without this device's Keychain) | `LocalDataUnreadable`: *Retry* and *Reset local data* |
| The stored key does not open the databases (wrong key or damaged file) | `LocalDataUnreadable`: *Retry* and *Reset local data* |

In those cases no new key is created. Earlier builds deleted the database
automatically after an opening error; that is gone.

**Reset local data** is offered only for `LocalDataUnreadable`, only while
the store is closed, and only after the user confirms. It deletes both
databases, their key and temporary media, then returns to the sign-in
screen. Consequences, which the confirmation states:

* This device's copy of the chats, its encryption keys and **any messages
  not sent yet** are lost.
* The user signs in again, which creates a new device.
* Messages on the server stay. Earlier encrypted history comes back only
  with the recovery key or verification from another device.
* **The old device stays registered on the server**: the app no longer has
  its access token, so it cannot sign it out. Remove it from another session
  (for example Element's session list) or ask an administrator.

## Verification and recovery

* **Set up recovery** (account has no crypto identity): `initCryptoIdentity()`
  creates SSSS, cross-signing and the online key backup and returns the
  recovery key. Cross-signing upload may require user-interactive auth; the
  adapter answers the `m.login.password` stage once with the password the user
  just entered (never stored) and fails with `InvalidCredentials` if the
  server rejects it. This depends on POC password authentication and has to
  be revisited for Active Directory with MFA.
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

## Test status (2026-10-27)

### Automated tests: 92 passing

`flutter test` runs 92 tests, all passing; `flutter analyze` reports no
issues and `dart format` reports no changes. They run on the development
machine against fakes, in-memory SQLite and real SDK objects; **none of them
talks to the server or runs on a simulator or phone.**

| Area | Tests | What they cover |
|---|---|---|
| Outbox worker (`outbox_worker_test.dart`) | 25 | Against a fake transport and a fake server that deduplicates per device and transaction ID: retries with the same ID, lost responses without duplicates, offline then reconnect, token refresh then immediate retry, rate limit across conversations, ordering within a conversation, permanent failures, server-error cap, manual retry, lost session, restart (delivered or not), attachments kept across restart, new-device adoption and uncertainty, the 23-hour window (found / not found / cannot tell), discard while sending, account isolation, backoff, and that the worker stays idle while a send is in flight or later messages wait |
| History search (`history_search_test.dart`) | 5 | Empty intermediate pages, end of history, time cutoff, page budget, no progress |
| Outbox store, errors, forwarding | 2 + 4 + 4 | Round trip of every field and file bytes; error classification; forwarded content for text, media, voice and unsupported types |
| Local store (`matrix_store_test.dart`) | 2 | Files without their key are never replaced automatically |
| Mappers (`matrix_mappers_test.dart`) | 8 | Real SDK `Room`/`Event`/`Timeline` objects: receipts, edits, reactions, kinds, forwarded marker, outbox entries as pending / waiting / failed messages |
| Controllers | 11 + 3 + 2 | Chat (including forwarding to several conversations and "send again" only after confirmation), sign-in, startup errors and local-data reset |
| Other | 7 + 9 + 6 + 3 + 1 | Test fixture contract, Matrix error mapping, IDs, refuse-to-send guard, failure texts |

### On simulators

| Check | Result |
|---|---|
| Sign-in with `moataz` and `kamel`, first sync, existing DM listed, session kept across a reinstall | Passed on iOS simulators (2026-10-20), before the outbox |
| Installing the outbox build over an existing install keeps the session and history | Passed on two iOS simulators (2026-10-26) |
| iOS simulator debug build | Passed (2026-10-26) with the outbox, before the redesign and the review fixes; not rebuilt since |

### Not run yet (simulator or phone)

* Offline for more than five minutes, then reconnecting (token refresh on
  reconnect).
* Sending, then leaving the conversation before it goes out.
* Restarting the app with messages waiting.
* Attachment retries after a failed upload.
* Duplicate prevention against the real server when a response is lost, and
  the 23-hour reconciliation.
* Forwarding text, images, files and voice notes between real clients, and
  opening the copies in Flutter and Element.
* Recording a voice note (needs microphone permission).
* The start-screen errors and *Reset local data*.
* The redesigned interface on a device (it was checked only as rendered
  screenshots in a widget test).
* Any Android build or Android device with the outbox. **Nothing has been
  tested on a physical phone.**

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
| 6 | Airplane mode, queue, reconnect, no duplicates | Outbox implemented and unit-tested (see [Test status](#test-status-2026-10-27)); not yet run on a simulator or phone |
| 7 | iOS and Android builds including `flutter_vodozemac` on CI | iOS simulator build passes locally (last on 2026-10-26). An Android release APK (arm64) built before the outbox and started on an API 33 emulator; not rebuilt since. CI not set up yet |
| 8 | Licence decision recorded | Recorded as "accepted for POC, legal review pending" (README) |

## Known limitations

* **Sign-in is POC authentication** (Matrix password login). Production will
  use on-premises Active Directory with MFA; how it is connected to Matrix is
  not designed yet.
* Web is not supported until a vodozemac WASM pipeline exists.
* No push notifications (needs a push gateway; owner approval).
* No background sending: queued messages wait while the OS suspends the app.
* Soft logout without a refresh token clears the session; the user signs in
  again as a new device and restores history with the recovery key.
* Not yet verified: whether iOS plays Ogg/Opus voice messages, which Element
  on Android and web may send. Android's player supports them.
* In-conversation search covers loaded messages only (no server-side search
  for encrypted rooms).
* Device retention is not enforced; Settings says so.
* Protected (view-once / OTP) messages are not built (follow-up section 3).
