# Internal Chat

A security-first internal messaging application for organizational use, built with Flutter for iOS, Android, and Web.

The application provides a familiar WhatsApp-style experience while enforcing organizational authentication, device-management, retention, auditing, and data-protection requirements.

> This project is currently a prototype and must not be treated as production-ready.

## Project Status

Current development state:

* `main`: Existing working prototype and UI baseline.
* `contract-first`: Rejected experimental refactor. Do not merge or use as a development base.
* `foundation/contract-first-v2`: Corrective incremental architecture branch based on `main`.

The active objective is to introduce contract-first architecture without replacing or degrading the existing UI.

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

* iOS
* Android
* Web

Desktop Flutter platforms are not currently part of the approved production scope.

## Technology Direction

### Mobile and Web

* Flutter
* Dart
* GetX for state management, dependency injection, and routing
* `http` package for REST communication
* SignalR for realtime messaging
* `flutter_secure_storage` for mobile secrets
* Encrypted local storage technology to be finalized with the security team
* APNS and FCM for generic push notifications

### Backend

The backend will be discussed and implemented separately.

Current backend direction:

* ASP.NET/.NET
* Windows Servers
* SignalR
* Active Directory authentication
* Mandatory MFA
* JWT access tokens
* Oracle Database for all server-side persistent data
* Fully on-premises deployment
* Public-internet access through approved security infrastructure

Matrix is not part of the current architecture.

## Functional Scope

The target application supports WhatsApp-like internal messaging without voice or video calls.

Expected capabilities include:

* Direct conversations
* Group conversations
* Text messages
* Images
* Documents and file attachments
* Voice notes
* Message replies
* Delivery status
* Read receipts
* Unread-message counts
* Typing indicators
* Presence information where permitted
* Conversation and message search
* Offline message queue
* Reconnection and missed-message recovery
* Generic push notifications
* Device-history retention settings
* Full authorized history through Web

Final approval of individual features remains subject to business and security review.

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
* Clear sent, delivered, read, pending, and failed states
* Familiar attachment actions
* Predictable navigation
* Responsive layouts for mobile and Web
* Arabic and English support
* Correct RTL and LTR behaviour
* Light and dark themes

The application must not copy WhatsApp branding, copyrighted assets, or trademarks.

## Target Flutter Structure

```text
lib/
├── models/
├── modules/
│   ├── authentication/
│   │   ├── authentication_binding.dart
│   │   ├── authentication_controller.dart
│   │   └── authentication_page.dart
│   ├── conversations/
│   ├── chat/
│   ├── files/
│   └── settings/
├── repositories/
├── services/
├── styles/
├── utilities/
├── web_services/
│   ├── dtos/
│   └── mappers/
├── widgets/
├── app_pages.dart
├── app_routes.dart
├── constants.dart
└── main.dart
```

This is a target structure. Existing code must be migrated incrementally rather than replaced through a large rewrite.

## Module Convention

Each UI module should normally contain:

* Binding
* Controller
* Page
* Module-specific widgets when necessary

Large reusable widgets belong in `widgets/`.

Controllers must not:

* Call HTTP directly
* Parse JSON
* Access secure storage directly
* Contain mock data
* Connect directly to SignalR
* Execute local-database queries
* Know whether the application is using mock or real services

## Application Data Flow

```text
Page or Widget
    → Controller
        → Repository Interface
            → Remote Web Service
            → Realtime Service
            → Local Storage Service
            → Offline Outbox
```

Responsibilities must remain separated.

### Pages and Widgets

Responsible for:

* Rendering state
* Collecting user input
* Triggering controller actions
* Navigation and presentation

### Controllers

Responsible for:

* Screen state
* User actions
* Calling repository contracts
* Presenting domain results to the UI

### Repositories

Responsible for:

* Coordinating remote and local sources
* Realtime reconciliation
* Offline behaviour
* Deduplication
* Mapping infrastructure results to domain models

### Web Services

Responsible only for transport concerns:

* HTTP method and URL
* Headers
* Request encoding
* Response decoding
* Timeouts
* Network cancellation
* Status codes
* Safe error translation

### Services

Responsible for infrastructure capabilities such as:

* Token storage
* Local encrypted history
* Offline outbox
* Connectivity
* SignalR
* Device-retention cleanup
* Session handling

## Required Repository Contracts

The application should define stable interfaces for:

* `AuthenticationRepository`
* `ChatRepository`
* `FileRepository`

Controllers depend on these interfaces, never directly on mock or REST implementations.

## Required Service Contracts

The application should define stable interfaces for:

* `RealtimeService`
* `TokenStorageService`
* `LocalChatStorageService`
* `OutboxService`
* `ConnectivityService`
* `RetentionService`
* `SessionService`

These interfaces must be designed so implementations can be replaced without changing controllers.

## Mock-to-Real Integration Rule

Mock and real implementations must implement identical interfaces.

For example:

```text
ChatController
    → ChatRepository
        → MockChatRepository
```

Later:

```text
ChatController
    → ChatRepository
        → RestChatRepository
            → ChatWebService
            → SignalRService
            → LocalChatStorageService
```

Changing from mock to real mode should happen only in GetX dependency bindings or application composition.

It must not require changes to:

* Pages
* Widgets
* Controller method signatures
* Navigation
* UI state models

## Domain Models and DTOs

Domain models represent application concepts and must not depend directly on backend JSON.

Examples:

* User
* Authentication session
* Conversation
* Participant
* Chat message
* Attachment
* Delivery receipt
* Read receipt
* Retention policy
* Outbox item

Backend DTOs belong under `web_services/dtos/`.

DTO-to-domain mapping belongs under `web_services/mappers/` or inside the real repository implementation.

Backend field names must not leak into UI code.

No DTO should be finalized until the backend team provides an approved API contract.

## REST, SignalR, and Push Responsibilities

### REST APIs

REST APIs are used for:

* Authentication
* MFA
* Session refresh
* Conversation lists
* Message history
* Sending messages
* Uploading and downloading attachments
* Search
* Read and delivery acknowledgements
* Retention preferences
* Recovery after disconnection
* Missed-event reconciliation

### SignalR

SignalR is used for:

* Incoming messages
* Conversation updates
* Delivery receipts
* Read receipts
* Typing indicators
* Presence updates
* Message edits or deletions
* Realtime policy changes where required

SignalR is not the source of truth. Oracle-backed backend services remain authoritative.

### Push Notifications

APNS and FCM are used when the application is suspended or terminated.

Push content must be generic. It must not contain:

* Message content
* Attachment names
* Sensitive sender details
* Authentication tokens
* Internal identifiers that are unnecessary for routing

A notification may tell the application that new activity exists. After authentication, the application retrieves the real data from the backend.

## Reconnection and Recovery

When the app is reopened or SignalR reconnects:

1. Validate or restore the authenticated session.
2. Reconnect SignalR.
3. Request missed messages or events using a cursor or sequence value.
4. Reconcile the local outbox.
5. Deduplicate messages using server and client message identifiers.
6. Refresh delivery and read states.
7. Update the conversation list.

The application must never assume SignalR delivered every event.

## Offline Messaging

Every outgoing message must have a unique client-generated idempotency identifier.

Offline states include:

* Pending
* Sending
* Sent
* Delivered
* Read
* Retryable failure
* Permanent failure

The outbox contract must support:

* Enqueue
* Update
* Retry
* Remove
* Retry count
* Creation time
* Last-attempt time
* Idempotency/client message ID
* Permanent-versus-retryable failure classification

A queued local message must not be shown as successfully accepted by the server.

## Message Deduplication

Messages can arrive through:

* REST send acknowledgement
* SignalR
* History synchronization
* Offline recovery

The repository must merge these using:

1. Server message ID
2. Client message ID
3. Conversation ID

Controllers must not implement deduplication independently.

Incoming messages must always be filtered by conversation ID before appearing in an open conversation.

## Authentication

Authentication requirements:

* Active Directory is the identity source.
* MFA is mandatory.
* The backend issues JWT access tokens.
* Token refresh and revocation behaviour must be formally defined.
* Authentication errors must not expose sensitive infrastructure information.
* Concurrent unauthorized responses must trigger only one logout flow.
* Logout must clear tokens, sensitive cache, realtime connections, and protected local data as required.

### Mobile Token Storage

On iOS and Android:

* Store tokens using `flutter_secure_storage`.
* Use Keychain/Keystore-backed protection.
* Never use `GetStorage`, SharedPreferences, or plain files for tokens.
* Replacing a token set must delete obsolete refresh tokens.

### Web Session Storage

For Web:

* Access tokens should remain memory-only.
* Do not store tokens in local storage, session storage, IndexedDB, or `GetStorage`.
* The preferred refresh-session approach is an approved `HttpOnly`, `Secure`, and appropriate `SameSite` cookie managed by the backend.
* The final Web session strategy requires backend and security approval.

## Server History

The server must retain complete authorized chat history in Oracle.

Users must be able to view their complete server history through the Web application after successful AD and MFA authentication.

The system must enforce:

* Conversation membership authorization
* User-level history access
* Pagination
* Audit logging
* Rate limits
* Session validation
* Protection against identifier enumeration

Normal database access should not expose plaintext messages unnecessarily. Encryption, key-management, HSM/KMS usage, and privileged administrator access require security-team approval.

This is not traditional device-only end-to-end encryption because the server must provide full history to authenticated users.

## Device Retention

Server retention and device retention are separate.

### Server

* Keeps complete authorized history.
* Oracle remains the authoritative source.
* Server retention changes require organizational approval.

### Device

Users may select a local-history period, limited by administrator policy.

Initial options:

* Session only / no persistent local history
* 1 day
* 7 days
* 30 days
* 90 days
* 180 days
* 365 days

Rules:

* The administrator can reduce the maximum.
* The user cannot exceed the administrator maximum.
* Policy validation must work in release builds and must not rely only on Dart `assert`.
* Expired messages and attachments must be securely removed from the local application database and cache.
* Web history remains available from the server after authentication.
* Retention-policy changes must trigger local cleanup.
* Logout, revocation, remote wipe, or device non-compliance may trigger additional cleanup.

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

The application is reachable through the public internet while backend infrastructure remains on-premises.

Required controls include:

* HTTPS only outside explicit local development
* Approved TLS versions and cipher suites
* Valid trusted certificates
* No production certificate bypass
* Reverse proxy, gateway, or WAF as approved
* Authentication rate limiting
* Request-size limits
* Safe timeout and retry policies
* Correlation identifiers without sensitive content
* Certificate pinning or enterprise-CA policy to be decided with security
* Optional mTLS to be evaluated

Production builds must reject insecure HTTP API URLs.

## Local Data Security

Local chat history must use encrypted storage.

The final local-database technology must support:

* Encryption at rest
* Key storage outside the database
* Per-user data separation
* Retention deletion
* Attachment-cache deletion
* Schema migration
* Transaction safety
* Offline outbox persistence
* Corruption recovery
* Logout cleanup

The database encryption key must be protected through Keychain or Keystore-backed mechanisms.

## Attachment Security

Attachments must be treated as untrusted content.

Required backend and client controls include:

* File-size limits
* Approved MIME types
* File-signature validation
* Malware scanning
* Upload cancellation and resumption
* Checksums
* Authorization before download
* Short-lived download authorization
* Secure temporary storage
* Local-retention cleanup
* Safe preview behaviour
* Filename sanitization

The organization will provide or approve the malware-scanning capability.

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

Environment configuration may contain:

* Application environment
* API base URL
* SignalR hub URL
* Feature flags
* Mock-versus-real implementation selection

Configuration must not contain:

* Passwords
* Client secrets
* Private keys
* Production tokens
* Encryption keys

Example development command:

```bash
flutter run \
  --dart-define=APP_ENV=mock \
  --dart-define=API_BASE_URL=https://example.invalid
```

Values supplied through `dart-define` are compiled into the application and must not be treated as secrets.

## Backend Contracts Required

Before implementing real integrations, the backend team must provide:

### Authentication

* Login method and endpoint
* AD integration behaviour
* MFA challenge and verification
* Access-token response
* Token-refresh response
* Expiry and clock-skew rules
* Revocation and logout
* Account-locking and throttling
* Error envelope

### Conversations

* Conversation-list response
* Conversation membership
* Direct and group conversation rules
* Pagination
* Unread counts
* Roles and permissions

### Messages

* Message schema
* Supported content types
* Client message ID
* Server message ID
* Timestamps
* Reply/edit/delete behaviour
* Delivery and read receipts
* Pagination and sequence rules
* Idempotency behaviour

### Attachments

* Upload initialization
* Multipart or chunking rules
* Resume and cancellation
* Maximum sizes and MIME types
* Malware-scan states
* Download authorization
* Metadata schema

### SignalR

* Hub URL
* Authentication method
* Event names
* Payload schemas
* Group/subscription lifecycle
* Reconnection rules
* Token renewal
* Missed-event recovery
* Ordering guarantees
* Deduplication identifiers

### Retention

* Administrator-policy endpoint
* User-preference endpoint
* Effective dates
* Audit requirements
* Remote purge events

An OpenAPI document and a written SignalR event contract are preferred.

## Oracle Requirements

All persistent server-side application data must be stored in Oracle.

The Oracle and backend teams must define:

* Schema ownership
* Conversation and participant tables
* Message and attachment metadata
* Message ordering
* Idempotency constraints
* Pagination indexes
* Encryption at rest
* Key-management integration
* Audit tables
* Backup and recovery
* Archiving
* High availability
* Data-retention controls
* Privileged-access controls
* Search strategy
* Performance and expected scale

Flutter must not connect directly to Oracle.

## Security-Team Decisions Required

The security team must approve:

* Threat model
* Authentication and MFA flow
* Token lifetimes
* Web refresh-session strategy
* TLS and certificate policy
* MDM compliance rules
* Root/jailbreak response
* Local database encryption
* Screenshot and clipboard policy
* Message and attachment classification
* HSM/KMS strategy
* Database administrator access
* Malware-scanning integration
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
git diff --check
git status --short
```

Also verify relevant iOS and Android builds in approved development environments.

If a tool is unavailable, report that clearly. Never claim a check passed when it was not executed.

## Testing Strategy

The project should include:

* Domain-model tests
* Repository contract tests
* Controller tests using fake repositories
* Web-service mapping tests
* Token-storage tests
* Outbox and retry tests
* Message-deduplication tests
* Retention-policy tests
* Widget tests
* Navigation tests
* Integration tests for real backend environments
* Web compilation checks

Important behaviours to test include:

* Repository implementation replacement without controller changes
* Expired and revoked sessions
* Concurrent `401` responses
* MFA-required authentication
* Offline sending
* Retry and idempotency
* Realtime/REST duplicate messages
* Missed-message recovery
* Messages arriving for another conversation
* Retention cleanup
* Logout cleanup
* Attachment upload failure
* Arabic RTL layouts
* Web token behaviour

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
* Authentication and MFA integration
* Direct and group messaging
* REST and SignalR integration
* Offline outbox
* Encrypted local storage
* Attachments and malware-scan workflow
* Push notifications
* Device-retention settings
* Full authenticated Web history
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

* Final REST API specification
* SignalR hub and event contract
* Web refresh-session design
* Local encrypted-database technology
* Certificate pinning or enterprise-CA strategy
* HSM/KMS design
* Oracle encryption and privileged-access design
* Final MDM compliance policy
* Attachment limits
* Presence and typing privacy rules
* Final retention option list
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
