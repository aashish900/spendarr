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
| Theme | Material 3, dark mode, black+gold AMOLED palette (`kGold 0xFFD4AF37`; replaced the original violet seed in the 2026-07 Home redesign) | Distinct from heerr's green; see DECISIONLOG |
| Connectivity | connectivity_plus | Deferred — was for sync triggers; added back with B7 |

## Local store: drift (SQLite)

Mirror of server schema — same UUID PKs (no ID remapping during sync). Every table carries `id`, `createdAt`, `updatedAt`, `deletedAt` (nullable).

Tables: `categories`, `transactions`, `recurringRules`, plus `outbox` and `syncMeta`.

`outbox(id, op ENUM(upsert|delete), table TEXT, payloadJson TEXT, queuedAt, attempts INT, lastError TEXT NULL)`

`syncMeta(key TEXT PK, value TEXT)` — stores `last_pull_at` and `pre_rotation_dismissed_at`.

## Screens

Navigation: a bottom `NavigationBar` (Home / History / Categories / Recurring / Settings), each backed by a go_router `StatefulShellRoute` branch. "Add transaction", "Add category", "Add recurring rule", and "Export" push over the nav bar on the root navigator rather than living inside a tab.

- **Home** — black+gold AMOLED design (2026-07 redesign; see DECISIONLOG). Header: greeting ("Good Morning" + optional display name, from `nowProvider`/`profileProvider`) and a month label with prev/next chevrons (`homeMonthAnchorProvider`/`effectiveHomeMonthProvider`; forward capped at the current month). A `MonthRing` shows spend vs the local `monthly_budget_cents` setting — current month: "₹X left to spend" (or "over budget") + "Day N/M"; past month: "₹X spent"; no budget set: "₹X spent" + "Set a budget". Below that, Income/Expense stats and a 3-chip strip (Expenses/Investments actuals for the month, Recurring **projected** total — v1 doesn't execute recurring rules, so a "spent" figure would always read ₹0). Then a `HomeTimeline` journal with Day/Week/Month zoom (Day/Week only for the current month — a past month always shows Month); Month is the original date-grouped chronological ledger (tap a row → edit). Below that, a facts-only `InsightCard` ("X renews tomorrow") when a recurring rule fires within 7 days — no spending-pattern analysis (out of scope, CLAUDE.md §3). FAB opens a bottom sheet (Income/Expense/Investment — no Transfer) that pre-selects the kind on Add.
- **Add/Edit transaction** — one screen for both (`/add`, optionally with `?editTransactionId=` to load and edit an existing row, or `?kind=` to pre-select a kind from the Home FAB sheet — ignored in edit mode or when `?categoryId=` is also set): amount, category (emoji picker filtered to the selected kind — e.g. Income only shows income categories; a "＋ New category" dropdown item, or a "Create category" button when none exist for that kind, opens an inline bottom-sheet form and auto-selects the result), date + time (both default to now; time is recorded, not pinned to noon), note, kind, and a "Make this recurring" toggle + recurrence preset (same picker as the standalone Add-recurring screen) that creates/updates/unlinks a linked `RecurringRule` — see DECISIONLOG for the sync-on-edit rules.
- **History** — toggle Day / Week / Month; bar chart + categorised list (tap a row → edit that transaction); date range picker. Local drift aggregation (expense spend by category). Online `/summary` path deferred with B7 (see DECISIONLOG 2026-06-23)
- **Categories** — grouped by kind (Income/Expense/Investment sections, header per non-empty group), add (emoji + name + kind), archive
- **Recurring** — list rules, add/edit (cron-ish picker), pause/resume
- **Export** — date-range picker, row count preview, "Export CSV" → OS share sheet. Columns: `date, amount, kind, category, note, source, recurring_rule_id`
- **Settings → Profile** — display name and monthly budget (both local-only, stored in `sync_meta`; feed Home's greeting and month ring — see DECISIONLOG)
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
- Transfer transaction kind (not in the data model — the Home FAB sheet offers Income/Expense/Investment only).
- Home Month-zoom calendar grid (a date-grouped list is used instead — see DECISIONLOG 2026-07-14).
