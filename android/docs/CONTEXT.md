# CONTEXT.md — spendarr Android client

Project brief for resuming the Android client build in Claude Code. Read this after `/CLAUDE.md` and `android/CLAUDE.md`.

## Name

**spendarr** (same as the repo / backend). Android app id will be `com.aashish.spendarr`.

## Goal

A native Android app where the user records income, expenses, and investments; reviews spending by day/week/month; manages recurring transactions; and defines their own categories with emoji icons. Works fully offline — SQLite is the primary store. Syncs to the Postgres backend over Tailscale when reachable.

## What the app does NOT do

- **No direct CRUD to backend.** All mutations go through the local DB + outbox → `/sync/push`. Direct endpoint calls are never correct.
- **No real-time push.** No WebSocket / FCM. Sync is triggered by connectivity events, foreground transitions, pull-to-refresh, and a 15-min foreground timer.
- **No iOS.** Out of scope (no Xcode / Apple Developer account). Don't propose iOS-aware code.
- **No multi-user.** Single user, single currency.
- **No v2 features.** Spending-pattern flagging, multi-currency, investment portfolio valuation, SMS parsing, CSV import — all deferred.

## Backend dependency

REST endpoints under `/api/v1`:

| Method | Path | Scope | Use |
|---|---|---|---|
| GET | `/health` | none | Settings "Test connection" button |
| POST | `/sync/push` | write | flush outbox — mutations batch |
| POST | `/sync/pull` | read | delta pull since last sync |
| GET | `/summary` | read | aggregated spend by category (online path for History screen) |

Auth: `Authorization: Bearer <raw-token>`. Minted via `python -m app.cli create-token`; user pastes into Settings once.

## Stack (locked v1)

| Concern | Choice | Rationale |
|---|---|---|
| State management | Riverpod (`flutter_riverpod` + `riverpod_annotation` + `riverpod_generator`) | Type-safe, reactive, testable — same as heerr |
| Local DB | drift (SQLite) | Reactive streams, type-safe DAOs, code-gen schema — best fit for offline-first |
| HTTP | dio + bearer interceptor + typed `ApiError` | Same pattern as heerr |
| JSON / models | freezed + json_serializable | Immutable models, codegen `fromJson`/`toJson`/`copyWith` |
| Token storage | flutter_secure_storage | Android EncryptedSharedPreferences — never plaintext prefs for the bearer token |
| Navigation | go_router | Declarative, Flutter-team-supported |
| Theme | Material 3, dark mode, new seed colour (picked at B1) | Consistent with heerr aesthetic |
| Connectivity | connectivity_plus | Deferred — was for sync triggers; added back with B7 |

## Local store: drift (SQLite)

Mirror of server schema — same UUID PKs (no ID remapping during sync). Every table carries `id`, `createdAt`, `updatedAt`, `deletedAt` (nullable).

Tables: `categories`, `transactions`, `recurringRules`, plus `outbox` and `syncMeta`.

`outbox(id, op ENUM(upsert|delete), table TEXT, payloadJson TEXT, queuedAt, attempts INT, lastError TEXT NULL)`

`syncMeta(key TEXT PK, value TEXT)` — stores `last_pull_at` and `pre_rotation_dismissed_at`.

## Screens

- **Today** — net flow + emoji-chip category grid; tap chip → quick-add transaction
- **Add transaction** — amount, category (emoji picker), date (default today), note, kind
- **History** — toggle Day / Week / Month; bar chart + categorised list; date range picker. Local drift aggregation (expense spend by category). Online `/summary` path deferred with B7 (see DECISIONLOG 2026-06-23)
- **Categories** — list, add (emoji + name + kind), archive
- **Recurring** — list rules, add/edit (cron-ish picker), pause/resume
- **Export** — date-range picker, row count preview, "Export CSV" → OS share sheet. Columns: `date, amount, kind, category, note, source, recurring_rule_id`
- **Settings → Server** — backend URL + bearer token + "Test connection" (last-sync indicator and "Sync now" deferred with B7)

## Pre-rotation warning

`RetentionWatcher` checks on foreground and after each sync. If any row has `occurred_at < now - 150 days`, shows a persistent banner on Today screen:
- "Your oldest data will be removed in ~30 days. Export it now."
- "Export now" CTA → navigates to Export screen.
- "Dismiss" → snooze 7 days (stored in `syncMeta`); re-surfaces after 7 days.
- Banner dismissed only after export or manual dismiss (not automatically).

## Sync engine sequence

> **Deferred — see DECISIONLOG 2026-06-23.** The app ships offline-only first. The outbox table is retained in the drift schema to make the future migration trivial. The sync engine (push + pull + conflict resolution + connectivity triggers) is milestone B7 and is not built in v1.

Retention sweep runs on app foreground (not post-sync) once the pre-rotation banner has been shown at least once.

## Retention sweep ordering

The sweep runs only after the user has seen at least one pre-rotation warning banner. This ensures the user always has the opportunity to export before data disappears. The `syncMeta` table tracks whether the banner has been shown.

## CSV export

`ExportService` queries drift for all (or date-range-filtered) non-deleted transactions joined with category names. Writes CSV bytes to the app cache dir. Opens the OS share sheet. Export is available from the History screen and Settings.

Columns (fixed order): `date, amount, kind, category, note, source, recurring_rule_id`.
Amounts as decimal strings (e.g. `"1234.56"`).

## Error UX

| Status | UX |
|---|---|
| 401 | Snackbar "auth failed" — check bearer token in Settings |
| 403 | Snackbar "insufficient scope" |
| 422 | Inline form error if user-entered; snackbar otherwise |
| network failure | "can't reach backend — check Tailscale" snackbar; mutations queue silently |
| other 4xx/5xx | Snackbar with `detail` field from error envelope |

## Dev environment

- Flutter 3.44.0 stable, at `~/develop/flutter`, macOS Apple Silicon.
- Dart 3.12.0 (bundled).
- Android SDK 36.1.0 via Android Studio; cmdline-tools installed; licenses accepted.
- `adb` on PATH (`~/Library/Android/sdk/platform-tools`).
- Test device: Pixel 7, Android 16 (API 36), connected over wireless adb.
- iOS path intentionally skipped.

## Out of scope for v1

- Push notifications / FCM.
- Biometric token unlock.
- Light theme.
- Internationalisation.
- Tablet layouts.
- Spending-pattern flagging / insights engine (v2).
- Multi-currency.
- Investment portfolio valuation.
- SMS parsing, CSV import, iOS port, multi-user.
