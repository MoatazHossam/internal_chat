# Backend integration requirements

No endpoint path, method, JSON field, or SignalR event name is assumed by the client. The following contracts must be approved before REST/SignalR adapters are implemented.

## Authentication and session
- Sign-in request/response, identity identifier rules, account states, throttling, and safe user-facing errors.
- Access-token format, JWT claims/audience/issuer, expiry and clock-skew rules.
- Refresh-token rotation, reuse detection, revocation, logout, concurrent-device policy, and the web refresh-session strategy (prefer an approved secure, HttpOnly cookie design).
- Central `401` behavior and distinction between expired, revoked, and insufficient-scope sessions.
- MFA challenge creation and expiry, supported factors, enrollment/recovery, verification request/response, resend and attempt limits.

## Conversations and messages
- Conversation list/detail schemas, membership/roles, direct-versus-group semantics, unread counts and ordering.
- History and message schemas, stable IDs, timestamps/time zones, content types, edits/deletes/replies and client idempotency keys.
- Cursor pagination direction, limits, cursor lifetime, empty/end-page semantics, and ordering guarantees.
- Send-message acknowledgement, retry/idempotency behavior, maximum sizes and moderation rules.
- Delivery and read-receipt states, participant scope, timestamps and privacy rules.

## Attachments
- Upload initialization, chunking or multipart rules, cancellation/resumption, checksums, encryption requirements and completion.
- Download/preview authorization, signed URL lifetime, metadata schema, MIME/size limits, malware scanning states and deletion.

## Realtime / SignalR
- Hub URL, negotiation/authentication and token renewal behavior; transport fallback and reconnect/backoff policy.
- Exact incoming/outgoing event names and typed payloads for messages, conversation changes, typing, presence, delivery/read receipts, deletion and retention changes.
- Subscription/group lifecycle, resume cursor or gap recovery, ordering, deduplication, acknowledgements and authorization failures.

## Retention and offline behavior
- Administrator retention-policy read/update endpoints, permission model, allowed limits (the client UI caps user selection at 365 days), effective dates and audit requirements.
- User device-retention preference endpoint (if synchronized), interaction with administrator maximums, legal holds, cache purge triggers and attachment retention.
- Offline outbox reconciliation, idempotency lifetime, conflict behavior and permanent-versus-retryable failure classification.

## Cross-cutting API conventions
- Environment-specific base URL delivery; API versioning and deprecation policy.
- Canonical error envelope, machine codes, field validation errors, correlation IDs and localization expectations.
- HTTP timeout/retry/rate-limit semantics, `Retry-After`, request limits and cancellation expectations.
- Date, identifier, enum, nullability and unknown-field compatibility conventions.
- CORS, CSP, TLS/certificate policy, logging/redaction and observability requirements.
