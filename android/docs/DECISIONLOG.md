# DECISIONLOG.md — spendarr Android client

ADR log. Append newest at the bottom. Format: `## YYYY-MM-DD — <title>` then **Context**, **Decision**, **Why**, **Alternatives considered**.

---

## 2026-06-22 — Stack: Flutter + Riverpod + drift + dio + freezed + go_router

**Context:** Choosing the Flutter stack for an offline-first single-user money tracker.

**Decision:** Mirror the `heerr` Android stack exactly — Riverpod for state, drift for local SQLite, dio + bearer interceptor for HTTP, freezed + json_serializable for models, flutter_secure_storage for the bearer token, go_router for navigation. Material 3 dark theme with a new seed colour (picked at B1 to differentiate visually from heerr).

**Why:** The user already has operational experience with this stack from heerr. Reusing it means zero ramp-up on tooling decisions, copy-able patterns for the API client and settings flow, and a known CI/APK signing workflow.

**Alternatives considered:** Bloc (more boilerplate than Riverpod); Isar/ObjectBox instead of drift (drift's generated DAOs + reactive streams are a better fit for the outbox-sync model; drift also has first-class migration support).

---

## 2026-06-22 — Local store: drift (SQLite) with outbox pattern

**Context:** The app must work fully offline. Mutations made while offline must replay to the server when connectivity resumes without data loss.

**Decision:** drift as the local SQLite library. Schema mirrors server tables (same UUID PKs — no ID remapping). Every UI mutation writes to local DB and appends a row to the `outbox` table. The sync engine drains the outbox via `/sync/push`.

**Why:** drift generates type-safe DAOs, provides reactive streams (UI rebuilds on local writes without polling), and handles migrations cleanly. The outbox pattern makes the online/offline write paths identical — the app always writes locally first, and the sync engine handles propagation.

**Alternatives considered:** sqflite (lower-level, no code-gen DAOs, no reactive streams); Isar (faster but no SQL, and the relational structure of the finance schema is a better fit for drift); in-memory state + sync on foreground (loses mutations on crash).

---

## 2026-06-22 — Connectivity-driven sync with 15-min fallback timer

**Context:** Deciding when to trigger the sync engine.

**Decision:** Sync triggers: (1) app foreground, (2) `connectivity_plus` network-available event, (3) manual pull-to-refresh, (4) 15-min periodic timer while app is foregrounded.

**Why:** Event-driven sync (foreground + connectivity) gives low latency without polling. The 15-min fallback catches drift if events are missed (e.g. connectivity_plus misfires). No background sync in v1 — the WorkManager pattern from heerr Phase Q is out of scope.

**Alternatives considered:** Polling every 60s (wastes battery and network when nothing has changed); WebSocket/SSE push from server (adds backend infrastructure; overkill for a single-user app); background sync via WorkManager (deferred to v2).

---

## 2026-06-22 — Retention: 6-month local cap with pre-rotation warning

**Context:** Deciding how much data to retain locally and how to prevent silent data loss.

**Decision:** Keep last 6 months (180 days) OR ≤100 MB, whichever hits first. Older rows truncated locally (retained on server). Categories and `recurringRules` are exempt from the sweep. The sweep runs only after the pre-rotation warning banner has been shown at least once.

Pre-rotation warning: `RetentionWatcher` checks on foreground and after each sync. If any row has `occurred_at < now - 150 days` (within 30 days of cutoff), shows a persistent banner with "Export now" CTA and 7-day snooze.

**Why:** A 6-month local window keeps the on-device DB small while retaining enough history for the most common use (current and last month's spend). The 30-day advance warning ensures the user can export before data disappears. The sweep-after-warning-only rule prevents silent first-run data loss for users who have older server data.

**Alternatives considered:** No local cap (DB grows unbounded, eventually slow); hard-enforce cap with no warning (silent data loss — unacceptable for financial data); warn on every app open until dismissed (annoying after the first few times — 7-day snooze is the balance).

---

## 2026-06-22 — CSV export via OS share sheet

**Context:** Users need a way to preserve local data before the retention sweep removes it, and a general-purpose export for use in spreadsheets.

**Decision:** `ExportService` queries drift, formats as CSV (columns: `date, amount, kind, category, note, source, recurring_rule_id`), writes to the app cache dir, and opens the OS share sheet. Available from the History screen and Settings. Date-range filter is optional (defaults to all local data).

**Why:** The share sheet is the standard Android pattern for file hand-off — it works with email, Drive, Files, and any other installed handler without requiring specific storage permissions. Writing to the cache dir avoids the `WRITE_EXTERNAL_STORAGE` permission dance. The cache is cleared when the user clears app data, which is acceptable because the export is complete at that point.

**Alternatives considered:** Save directly to Downloads folder (`MediaStore` API — requires Android 9+ handling, more complex permission flow); export to cloud storage directly (requires provider-specific auth — out of scope); email directly from the app (requires email provider auth — out of scope).

---

## 2026-06-22 — Amounts: int cents in drift, Decimal in Dart models, NEVER double

**Context:** Choosing how to store and pass monetary amounts in the Flutter/Dart layer.

**Decision:** drift schema uses `INTEGER` (cents, e.g. 1234 = $12.34). Dart freezed models expose a `Decimal` (from the `decimal` package) or a helper that converts from/to cents. The sync payload serialises as a string (e.g. `"12.34"`). Display layer formats for the user's locale. `double` is never used for amounts anywhere in the codebase.

**Why:** SQLite has no `DECIMAL` type — storing as `INTEGER` cents avoids floating-point storage. Dart `double` has the same IEEE 754 rounding issues as any other language. `Decimal` from the `decimal` package provides exact arithmetic in Dart.

**Alternatives considered:** Store as TEXT in SQLite (correct but slower to sort/aggregate); store as REAL (floating-point, inexact — ruled out categorically); keep as `double` in Dart and round on display (error-prone, easy to accumulate rounding drift).

---

## 2026-06-23 — Defer sync engine to a later phase; ship offline-only first

**Context:** The outbox pattern, push/pull sync engine, conflict resolution, and connectivity triggers (B7) add significant complexity and backend coupling. The backend `/sync/push` and `/sync/pull` endpoints exist on paper but have not been implemented or tested. Shipping the Android client with sync wired up before those endpoints are stable risks building against a moving contract.

**Decision:** Ship the Android client as an offline-only app in v1. The local DB (drift), all screens, CSV export, and retention watcher/sweep are implemented as planned. The sync engine (milestone B7) is deferred to a future milestone. The outbox table is kept in the drift schema so no migration is required when sync is added later, but the `SyncEngine`, `OutboxPusher`, `PullHandler`, and `syncProvider` are not built.

Consequences:
- Milestone B7 is deferred entirely. Removed from the active roadmap.
- Milestone B8 (retention watcher + sweep) is kept but the sweep trigger changes: `RetentionSweep.run()` is called on app foreground (not at the end of `SyncEngine.run()`). `RetentionWatcher.check()` is called on foreground only (no post-sync call).
- Settings screen drops "Sync now" and last-sync indicator. "Test connection" is retained so the user can validate the bearer token before sync is wired up.
- `connectivity_plus` dependency is deferred (was only needed for sync triggers).
- `syncMeta` table is retained for `last_pull_at` and `pre_rotation_dismissed_at` — still needed by retention watcher.
- CONTEXT.md "Sync engine sequence" section updated to reflect deferred status.

**Why:** Reduce scope to the smallest shippable unit. Offline-only is useful on its own (local expense tracking + CSV export). Sync can be layered on once backend endpoints are stable and testable.

**Alternatives considered:** Ship sync as planned (increases risk of building against an unstable backend contract); stub sync with no-ops (adds dead code with no value); remove the outbox table entirely (would require a schema migration when sync is added — rejected to keep the future migration simple).

---

## 2026-06-23 — B1: theme seed colour, no local FK constraints, commit generated code

**Context:** B1 scaffold decisions that need a record.

**Decision:**
- **Seed colour `0xFF7C4DFF` (deep violet).** Material 3 dark scheme via `ColorScheme.fromSeed(seedColor: 0xFF7C4DFF, brightness: dark)`. Defined as `kSeedColor` in `lib/theme.dart`.
- **No foreign-key constraints in the drift schema.** `transactions.categoryId` and `recurringRules.categoryId` reference categories by UUID but are not enforced FKs.
- **Generated `*.g.dart` files are committed** to the repo (drift + riverpod output), rather than gitignored and regenerated.
- **`build_runner` invocation:** the installed build_runner ignores `--delete-conflicting-outputs` (now default). Command is still documented with the flag for compatibility; it is a harmless no-op warning.

**Why:**
- Violet is unmistakably distinct from heerr's green at a glance — the two apps are visually separable on-device. ROADMAP B1 required documenting the choice.
- Server is source of truth on sync (B7, deferred). Sync pulls may arrive out of order (a transaction before its category); enforcing FKs locally would reject valid out-of-order upserts. Soft-delete + LWW semantics make local referential enforcement the wrong layer.
- Committing generated code lets a fresh clone run `flutter test` without first running `build_runner`, and removes a CI ordering dependency. Trade-off: larger diffs on schema changes — acceptable for a solo project.

**Alternatives considered:** Teal seed (too close to green — rejected); enforce FKs with `PRAGMA foreign_keys` (breaks out-of-order sync upserts); gitignore `*.g.dart` and regenerate in CI (fragile fresh-clone test runs).

---

## 2026-06-23 — B2 trimmed to the live network surface; ApiError mapped at the client layer

**Context:** B2 as originally specced assumed sync existed — it called for the full freezed model set (`SyncPushItem`/`SyncPushAck`/`SyncPullResponse`, `SummaryResponse`, and `CategoryModel`/`TransactionModel`/`RecurringRuleModel`). With sync deferred (B7), the only live network call is `/health` for the Settings "Test connection" button. The offline UI reads drift row classes directly, so none of those models have a consumer yet.

**Decision:** Build only the live surface in B2:
- `dio` client (base URL from `settingsProvider` + bearer interceptor),
- typed `ApiError` (`unauthorized | forbidden | unprocessable | network | server | unknown`),
- `Endpoints.health` (`/api/v1/health`),
- `settingsProvider` (Riverpod `AsyncNotifier`) backed by a `SettingsStore` interface; `SecureSettingsStore` uses `flutter_secure_storage`,
- Settings screen (URL + token + Save + Test connection).

Deferred to the milestone that consumes them: `SummaryResponse` → B5; sync envelopes + domain models → B7. `freezed`/`json_serializable` are **not** added until then (`ApiError` and `AppSettings` are hand-written plain classes — they carry no JSON).

`ApiError` mapping lives at the **client method layer** (`DioApiClient.health` catches `DioException` → throws `ApiError`), not in a dio error interceptor. The `ApiClient` is an interface so widget tests inject a fake.

Two assumptions, stated for review:
1. `/health` is under `/api/v1` (`/api/v1/health`), per CONTEXT.md's "endpoints under /api/v1" grouping. The backend (A1–A4) is unbuilt, so this is the contract we're asserting — adjust if the backend lands it at root `/health`.
2. The bearer token is sent on `/health` too (interceptor is unconditional); the endpoint is expected to ignore it.

**Why:** Smallest shippable unit, consistent with the sync deferral — no dead model code or untested contracts. Mapping errors at the client layer (vs. an interceptor that must `reject` a wrapped exception) is simpler to test with one endpoint; revisit interceptor-based mapping at B7 when several endpoints exist.

**Alternatives considered:** Build all models now for a "ready" contract (dead code + tests asserting an unbuilt backend's shape); dio error interceptor mapping (awkward `handler.reject` unwrapping, deferred); store settings via `FlutterSecureStorage` directly in the provider (untestable without platform channels — the `SettingsStore` interface fixes that).
