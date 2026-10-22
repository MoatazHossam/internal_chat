# Internal Chat

A security-first internal messaging application for organizational use, built with Flutter for iOS, Android, and Web.

The application provides a familiar WhatsApp-style experience on top of an end-to-end encrypted [Matrix](https://spec.matrix.org/latest/client-server-api/) homeserver operated by the organization.

> This project is currently a prototype and must not be treated as production-ready.

## Project Status

Current development state:

* `main`: Existing working prototype and UI baseline.
* `contract-first`: Rejected experimental refactor. Do not merge or use as a development base.
* `foundation/contract-first-v2`: Corrective incremental architecture branch based on `main`.

The backend is now a Matrix homeserver (Synapse). The earlier custom REST/SignalR API is **not** the contract: the app speaks the standard Matrix Client-Server API through an SDK, behind replaceable domain interfaces. The source for the server facts below is the Flutter handover from the backend team (2026-10-19); see also [`docs/matrix_integration.md`](docs/matrix_integration.md).

## Core Principles

1. Security is the highest priority.
2. Existing working functionality must be preserved.
3. Mock and real integrations must use identical contracts.
4. Connecting real APIs must not require rewriting pages or controllers.
5. Backend contracts must never be guessed.
6. Refactoring must be incremental and reviewable.
7. The repository must remain private.
8. No production credentials or internal data may be committed.

## Platforms

The application targets:

* iOS: Matrix backend.
* Android: Matrix backend.
* Web: **not supported yet.** `flutter_vodozemac` has no web build, so end-to-end encryption on the web needs a separate vodozemac WASM pipeline. Until that exists, web builds stop at the start screen with an explanation. The app shows no demo or sample data on any platform.

Desktop Flutter platforms are not currently part of the approved production scope.

## Licence (decision pending)

The Matrix SDK (`matrix`) and its encryption bindings (`flutter_vodozemac`) are **AGPL-3.0**. Linking them generally means the app must be distributed under AGPL-compatible terms, with source offered to the people who receive it.

* Status: **accepted for the POC only (2026-10-20); legal review still required** before distributing builds beyond the POC.
* If AGPL is not acceptable, the options are a commercial licence from Famedly (not verified) or a Dart bridge to `matrix-rust-sdk` (Apache-2.0). Only `lib/data/matrix/` would change.

This conflicts with the "Proprietary" statement in the [License](#license) section until legal decides.

## Technology Direction

### Mobile and Web

* Flutter and Dart
* GetX for state management, dependency injection, and routing
* Famedly `matrix` SDK (14.x, pure Dart) for the Matrix Client-Server API
* `flutter_vodozemac` (0.8.x) for Olm/Megolm end-to-end encryption. Keep 0.8.x until `matrix` depends on `vodozemac` 0.9.
* SQLCipher (through `package:sqlite3` build hooks and `sqflite_common_ffi`) for the encrypted local store
* `flutter_secure_storage` for the database key (Keychain on iOS, Keystore on Android)

### Backend

| Topic | Value |
|---|---|
| Homeserver | `https://secure-chat-poc.duckdns.org`, discovered through `/.well-known/matrix/client` |
| Software | Synapse 1.163; Matrix spec v1.1–v1.15 |
| Sign-in | `m.login.password` only. No SSO, OIDC, MFA, or registration; an administrator creates accounts |
| Sync | Classic `/v3/sync` long-polling |
| Rooms | Encrypted by default (Megolm), invite-only, no public directory |
| Federation | Disabled |
| User search | Only users who already share a room; a first chat needs the full Matrix ID |
| Presence | Disabled |
| URL previews | Disabled |
| Media | Authenticated media only (`/_matrix/client/v1/media`). Upload limit read at runtime from `/v1/media/config` (25 MiB on the POC) |
| Rate limits | `429 M_LIMIT_EXCEEDED` with `retry_after_ms` |
| Push | Requires a push gateway the organization controls; not deployed yet |

## Functional Scope

Implemented on the Matrix backend:

* Direct conversations (encrypted, reusing an existing encrypted DM)
* Group conversations (encrypted, invite-only), add and remove members, leave
* Accepting and declining invitations
* Text messages, replies, edits, deletions (redactions), reactions
* Images and documents (encrypted client-side before upload)
* Voice notes (MSC3245 voice markers, as Element sends them)
* Read receipts and unread counts
* Typing indicators
* In-conversation message search (loaded messages)
* Offline sending with idempotent retry
* Device verification (emoji/SAS), recovery key, and online key backup

Not available or not applicable:

* **Delivery receipts:** Matrix has none; the app shows read receipts only.
* **Presence/online status:** disabled on the server; the app shows none.
* **Push notifications:** need a push gateway (see below).
* **Full plaintext server history:** see [Server History](#server-history).

## Explicitly Excluded

The following are not currently included:

* Voice calls
* Video calls
* Public social channels
* External-user messaging
* Matrix federation
* VIP-specific security behaviour in Phase 1

Features must not be added merely because they exist in WhatsApp. Organizational and security requirements take precedence.

## UX Direction

The UX should remain close to WhatsApp because users already understand its interaction patterns.

This includes:

* Familiar conversation-list layout
* Familiar message bubbles
* Clear sending, sent, read, and failed states (Matrix has no delivery receipts, so there is no "delivered" tick)
* Familiar attachment actions
* Predictable navigation
* Responsive layouts for mobile and Web
* Arabic and English support
* Correct RTL and LTR behaviour
* Light and dark themes

The application must not copy WhatsApp branding, copyrighted assets, or trademarks.

## Flutter Structure

```text
lib/
├── domain/                 # Backend contracts. Pure Dart, no SDK imports.
│   ├── chat_backend.dart   # ChatSession, Conversations, Messages, DeviceTrust
│   ├── chat_failure.dart   # Errors that cross the boundary
│   ├── ids.dart            # ConversationId, UserId, LocalMessageId, MessageRef
│   ├── send_guard.dart     # Refuse to send without encryption
│   ├── session_state.dart
│   └── device_trust_state.dart
├── models/                 # Domain models: Conversation, ChatMessage, User
├── data/
│   ├── backend_factory.dart        # Composition root for the backend
│   ├── matrix/                     # The ONLY code that imports the Matrix SDK
│   │   ├── matrix_chat_backend.dart
│   │   ├── matrix_mappers.dart     # SDK events/rooms -> domain models
│   │   ├── matrix_errors.dart      # SDK/network errors -> ChatFailure
│   │   ├── matrix_store.dart       # SQLCipher store, key in secure storage
│   │   └── matrix_verification.dart
│   └── unsupported_platform_backend.dart  # Web: explains it is not supported
├── modules/
│   ├── app_binding.dart    # Registers the backend under each contract
│   ├── session/            # Startup, routing on session changes
│   ├── authentication/
│   ├── chat/
│   ├── security/           # Recovery key, verification
│   └── settings/
├── services/
├── styles/
├── utilities/
├── widgets/
├── app_pages.dart
├── app_routes.dart
├── constants.dart          # Build-time configuration
└── main.dart
```

## Module Convention

Each UI module should normally contain:

* Binding
* Controller
* Page
* Module-specific widgets when necessary

Large reusable widgets belong in `widgets/`.

Controllers must not:

* Import the Matrix SDK or any other transport
* Parse JSON
* Access secure storage directly
* Contain mock data
* Know which backend implementation is behind the contracts

## Application Data Flow

```text
Page or Widget
    → Controller
        → Domain contract (ChatSession / Conversations / Messages / DeviceTrust)
            → MatrixChatBackend (data/matrix, Matrix SDK)
            → or a test fixture (test/support) in unit tests
```

* **Pages and widgets** render state, collect input, and navigate.
* **Controllers** hold screen state, call domain contracts, and expose `ChatFailure`s for the UI to localize.
* **The Matrix adapter** owns the SDK client, maps SDK events to domain models, enforces the security rules below, and translates every SDK or network error into a `ChatFailure`.
* **The SDK's persistent store** owns the sync cursor (`next_batch`), device keys, room keys, and the access token. The app does not duplicate them.

## Contracts and Test Fixtures

The Matrix adapter implements the `ChatBackend` contracts. Tests use an in-memory fixture (`test/support/mock_chat_backend.dart`) that implements the same contracts, so controller tests run through the real interfaces. The app itself contains no mock backend or sample conversations.

Pages, widgets, controller method signatures, navigation, and UI state models must not depend on which implementation is behind the contracts. Replacing the SDK (for example with a `matrix-rust-sdk` bridge) must only touch `lib/data/matrix/` and `lib/data/backend_factory.dart`.

## Domain Models

Domain models (`Conversation`, `ChatMessage`, `User`, `Member`) do not depend on SDK types. SDK events are mapped in `data/matrix/matrix_mappers.dart`:

* Message kinds: text, image, file, voice, audio.
* Redacted messages become "deleted" items.
* Events this device cannot decrypt become "waiting for keys" items. The SDK's decryption error text is never shown.
* Unknown event types become "unsupported message" items rather than crashing.
* State events, reactions, edits, and verification events are folded into other items or hidden.

## Security Rules the App Enforces

The server encrypts new rooms by default but **does not enforce encryption**. The app therefore:

1. Creates every room with an explicit `m.room.encryption` (`m.megolm.v1.aes-sha2`) in `initial_state`, and never reuses an old unencrypted DM.
2. **Refuses to send** (messages, files, voice notes, reactions, edits) into any room that is not encrypted, or when encryption is not running on the device. The composer is replaced by an explanation; there is no plaintext fallback.
3. Treats room names and topics as server-visible and tells users to keep group names generic.
4. Stores the local database encrypted with SQLCipher. The key lives in Keychain/Keystore. If either is unavailable, the app stops at the start screen instead of falling back to plaintext.
5. Never logs access tokens, message bodies, or keys (SDK log level is `error`).

## Sign-in and Sessions

* Password sign-in only (`m.login.password`). The app offers no sign-up.
* Each sign-in creates a new device with its own encryption keys.
* The app requests refresh tokens; the SDK renews access tokens automatically.
* If the server ends the session (`M_UNKNOWN_TOKEN`), the user returns to the login screen with an explanation.
* Sign-out tells the server, deletes the local store and its key, and returns to the login screen.

## Devices, Verification, and Recovery

* **Recovery key:** set up once per account from *Settings → Security & verification*. It creates cross-signing keys, secret storage (SSSS), and the online key backup. The server re-checks the password first. The key is shown once.
* **New devices** become trusted by entering the recovery key, or by emoji (SAS) verification with another signed-in device (including Element). Incoming verification requests open a dialog anywhere in the app.
* **Restoring history:** after the recovery key is accepted (or verification completes), the app loads earlier room keys from the online backup.
* An existing identity (for example one created from Element) is never wiped by the app.
* **Losing every device and the recovery key means losing encrypted history.** Server backups and password resets cannot recover it. The app says this on the security page.

## Server History

The previous plan required the server to provide complete plaintext history to authenticated Web users. With end-to-end encryption the server cannot do that: it stores ciphertext only. A device reads earlier messages only through the recovery key / key backup or verification with another device.

This changes the original requirement and needs an organizational decision (see [Open Decisions](#open-decisions)).

## Offline Messaging and Deduplication

* Every send creates one `LocalMessageId` per user action. The adapter uses it as the Matrix transaction ID (`PUT /rooms/{roomId}/send/{type}/{txnId}`), so every retry reuses it and the server returns the same event instead of a duplicate.
* Pending messages are kept as local echoes in the SDK's encrypted store and shown as "sending" until the server accepts them.
* While offline the SDK keeps retrying for two minutes; after that the message is marked failed. When the connection returns, failed messages in open conversations are retried automatically (once per app run); any failed message can be retried by tapping it.
* A queued message is never shown as accepted by the server.
* Failed **attachments** cannot be retried, because decrypted files are not kept on disk; the user picks the file again.

## Push Notifications (needs new infrastructure)

Not implemented. The stock Element apps use Element's own push gateway and credentials, which another app cannot use. `internal_chat` needs:

1. Its own Firebase project (FCM) and APNs key.
2. A push gateway the organization controls, for example Sygnal (Apache-2.0). This expands the server stack and **needs owner approval**.
3. Pusher registration with `format: event_id_only`, then fetching and decrypting the event on the device.

Lock-screen text must stay generic (for example "New message"): no content or sender.

## Device Retention

Device retention is out of scope of the Matrix handover. The retention picker in Settings is still a UI-only preference and is **not enforced** yet.

Earlier requirements still apply for the eventual design:

* Session only / no persistent local history, 1, 7, 30, 90, 180, or 365 days.
* The administrator can reduce the maximum; the user cannot exceed it.
* Policy validation must work in release builds and must not rely on Dart `assert`.
* Expired messages and attachments must be removed from the local store.

## VIP and Sensitive Data

VIP-specific functionality is deferred to Phase 2.

Possible Phase 2 capabilities include:

* Forced session-only local history
* More restrictive MDM policies
* Remote local-data purge
* Additional authentication checks
* Restricted export, sharing, screenshot, or clipboard behaviour
* Stronger attachment restrictions
* Special key-management policies

These capabilities must not be partially implemented in Phase 1 without an approved security design.

## Managed Devices and MDM

The organization is expected to use AirWatch/Workspace ONE or another approved MDM platform.

Mobile access is intended for managed endpoints.

The final compliance policy should define:

* Device enrollment
* OS-version minimum
* Encryption status
* Screen-lock requirements
* Root/jailbreak detection
* Application version
* Remote wipe
* Screenshot and screen-recording policy
* Clipboard and data-sharing restrictions
* Certificate distribution
* Application configuration
* Behaviour when a device becomes non-compliant

MDM improves device control but does not replace application security.

## Network Security

* HTTPS only. `MATRIX_HOMESERVER` must use `https`; plain HTTP is allowed only for `localhost` in debug builds.
* Valid trusted certificates; no certificate bypass.
* Certificate pinning or an enterprise-CA policy is still to be decided with security.
* Rate limits are respected (`retry_after_ms` is surfaced to the user).

## Local Data Security

* The SDK store (messages, room keys, device keys, sync cursor, access token) is an SQLCipher database. Its 256-bit key is generated on the device and stored with `flutter_secure_storage` (Keychain `first_unlock_this_device`; Android Keystore).
* Decrypted attachments are held in memory only. The SDK's file cache is disabled because it writes decrypted files to disk.
* Voice notes are written to a temporary file for playback and deleted when the player closes. Recordings and files chosen with the picker are deleted after they are read.
* Android backups and device-to-device transfer are disabled for app data.
* Sign-out deletes the database files and the key.

## Attachment Security

* Files are encrypted client-side (AES-256-CTR) before upload; thumbnails are separate encrypted uploads.
* The upload limit comes from the server (`/v1/media/config`) and is checked before the file is read into memory.
* Downloads use the authenticated `/_matrix/client/v1/media/download` endpoints.
* **There is no server-side malware scanning.** The app does not claim otherwise.
* Saving a file to the device creates a copy outside the app's control.

## Logging and Telemetry

Never log:

* Access tokens
* Refresh tokens
* Passwords
* MFA codes
* Message content
* Attachment content
* Encryption keys
* Sensitive personal data
* Full API request or response bodies

Production telemetry should use:

* Safe error codes
* Correlation IDs
* Redacted metadata
* Performance timings
* Connection-state transitions
* Retry counts

Crash reports must be reviewed for possible sensitive-data exposure.

## Configuration

Build-time values from `--dart-define`:

| Name | Default | Purpose |
|---|---|---|
| `MATRIX_HOMESERVER` | `https://secure-chat-poc.duckdns.org` | Homeserver base URL; must be `https` |

Values supplied through `dart-define` are compiled into the application and must not be treated as secrets.

## Security-Team Decisions Required

The security team must approve:

* AGPL licence for the Matrix SDK (see [Licence](#licence-decision-pending))
* Threat model
* Push gateway deployment and notification content
* Loss of server-side plaintext history under end-to-end encryption
* Recovery-key handling guidance for users
* TLS and certificate policy
* MDM compliance rules
* Root/jailbreak response
* Screenshot and clipboard policy
* Message and attachment classification
* Malware-scanning integration (none on the server today)
* Logging and SIEM integration
* Penetration-testing scope
* Incident-response behaviour
* Remote-wipe behaviour

## Development Workflow

### Branches

Use short-lived branches such as:

```text
foundation/contract-first-v2
feature/conversation-list
feature/message-outbox
fix/message-deduplication
security/token-storage
docs/backend-requirements
```

Rules:

* Do not push feature work directly to `main`.
* Do not merge without review.
* Keep commits focused.
* Avoid destructive history rewriting.
* Do not commit `.DS_Store`, `.env`, tokens, certificates, signing keys, or generated build output.
* Commit `pubspec.lock` because this repository is an application.
* Protect `main` and require pull-request review and CI before merging.

## Verification Requirements

Before a pull request is considered ready:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
flutter build ios --simulator --debug
git diff --check
git status --short
```

Platform notes:

* **iOS:** `flutter_vodozemac` ships a prebuilt xcframework through Swift Package Manager (the default on current Flutter). With CocoaPods it is compiled from Rust instead.
* **Android:** `flutter_vodozemac` is compiled from Rust during the build, so the machine and CI need a Rust toolchain (`rustup`).
* **SQLCipher:** `package:sqlite3` downloads its prebuilt SQLCipher libraries during the build (see `hooks:` in `pubspec.yaml`).

If a tool is unavailable, report that clearly. Never claim a check passed when it was not executed.

## Testing Strategy

The project includes:

* Domain tests (user-ID parsing, the refuse-to-send guard)
* Error-mapping tests (Matrix error codes → `ChatFailure`)
* Mapper tests against real SDK `Room`/`Event`/`Timeline` objects (read receipts, edits, reactions, undecryptable events, local echoes)
* Contract tests on the in-memory test fixture (idempotent send, unencrypted rooms, upload limit, invites)
* Controller tests through the domain contracts

Still needed against the POC server (the SDK spike in `docs/matrix_integration.md`): sign-in, DM with Element, verification and recovery across devices, media limits, offline send, and CI builds.

## Definition of Done

A feature is complete only when:

* Functional requirements are satisfied.
* Existing behaviour is preserved unless a change was approved.
* UI does not depend on infrastructure implementations.
* Mock and real paths share contracts.
* Security requirements are addressed.
* Errors and offline states are handled.
* Tests are added and pass.
* Dart formatting and analysis pass.
* Supported platform builds pass.
* Documentation is updated.
* No credentials or sensitive data are introduced.
* A reviewed pull request exists.

## Codex and Claude Collaboration

Codex is the primary implementation agent.

Claude may be used for:

* Independent architecture review
* Pull-request review
* Security-design criticism
* Test-gap identification
* Documentation review
* A separate, clearly bounded implementation task

Do not allow Codex and Claude to edit the same branch simultaneously.

Recommended workflow:

1. Codex implements one bounded task on its own branch.
2. Codex runs tests and opens a pull request.
3. Claude reviews the diff without changing it.
4. Review findings return to Codex.
5. Codex applies corrections on the same implementation branch.
6. The user reviews the final diff.
7. Merge only after approval.

If Claude must implement changes, it should use a separate branch and must not overwrite Codex work.

## Instructions for AI Coding Agents

Before changing code:

1. Read this README completely.
2. Read relevant documents under `docs/`.
3. Inspect the active branch and `git status`.
4. Inspect existing code before proposing replacements.
5. Identify existing behaviour that must be preserved.
6. Present a short plan.
7. Ask one concise question if a material decision is unclear.

While changing code:

* Work incrementally.
* Preserve useful UI.
* Keep controllers independent of infrastructure.
* Do not invent backend contracts.
* Do not introduce empty production implementations merely to satisfy structure.
* Do not compress source code into single lines.
* Do not perform broad rewrites without approval.
* Do not disable TLS validation.
* Do not weaken security for debugging convenience.
* Do not expose secrets in logs or commits.
* Do not modify unrelated files.
* Add tests with each behaviour change.

Before finishing:

1. Format the code.
2. Run analysis.
3. Run tests.
4. Build supported targets where possible.
5. Review the complete diff.
6. Confirm no sensitive files were added.
7. Report unexecuted checks honestly.
8. Provide the commit and pull-request links.

## AI Handover Format

Every implementation handover should include:

```text
Objective:
Branch:
Commit:
Pull request:

Implemented:
- ...

Preserved behaviour:
- ...

Contracts introduced or changed:
- ...

Files changed:
- ...

Tests executed:
- ...

Tests not executed:
- ...

Security considerations:
- ...

Backend contracts still required:
- ...

Known limitations:
- ...

Recommended next step:
- ...
```

## Delivery Phases

### Phase 1 — Core Secure Messaging

* Contract-first Flutter foundation
* Matrix SDK adapter behind domain contracts
* Direct and group messaging with end-to-end encryption
* Device verification, recovery key, and key backup
* Offline sending with idempotent retry
* Encrypted local storage
* Attachments
* Push notifications (needs a push gateway)
* Device-retention settings
* Web support with end-to-end encryption (needs vodozemac WASM)
* MDM integration
* Security testing

### Phase 2 — VIP and Sensitive Data

* VIP-specific local-retention enforcement
* Forced session-only modes
* Enhanced MDM restrictions
* Remote local-data purge
* Additional content controls
* Stronger authorization and key-management policies
* Other approved sensitive-data features

## Open Decisions

The following remain unresolved:

* AGPL licence of the Matrix SDK, or a switch to a `matrix-rust-sdk` bridge
* Push gateway (Sygnal or similar), FCM/APNs credentials, or UnifiedPush on Android
* Full server history versus end-to-end encryption
* Web end-to-end encryption (vodozemac WASM build)
* Certificate pinning or enterprise-CA strategy
* Final MDM compliance policy
* Device retention and VIP deletion
* AD/MFA or SSO in front of Matrix
* Production server naming
* Expected user, conversation, message, and attachment scale

These decisions must be documented before related production implementations are finalized.

## Repository Security

This repository is proprietary and intended for authorized project members only.

It must remain private.

Do not commit:

* Production data
* Real employee identities
* Internal server URLs unless approved
* Tokens
* Passwords
* Certificates
* Signing keys
* Provisioning profiles
* Database credentials
* AD configuration secrets
* Push-notification credentials

If a secret is committed, removing the file is insufficient. The secret must be revoked and the Git history must be reviewed.

## License

Proprietary and confidential.

Unauthorized copying, distribution, or use is prohibited.

> **Note:** the POC links AGPL-3.0 libraries (`matrix`, `flutter_vodozemac`). Until legal decides, treat builds as internal POC builds only. See [Licence](#licence-decision-pending).
