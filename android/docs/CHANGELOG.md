# CHANGELOG.md — spendarr Android client

Append-only per-task change log. Format: `## YYYY-MM-DD — <one-line summary>` then bullets (files touched + what changed). Never edit or delete prior entries.

---

## 2026-06-22 — Initial documentation and skeleton

- `android/CLAUDE.md` — created Android-client Claude rules.
- `android/docs/CONTEXT.md` — created Android client project brief covering architecture, stack, screens, sync engine, retention, CSV export, error UX, and out-of-scope items.
- `android/docs/DECISIONLOG.md` — recorded five founding ADRs: stack, drift+outbox, connectivity-driven sync, retention with pre-rotation warning, CSV export, amounts as int cents.
- `android/docs/CHANGELOG.md` — this file.
- `android/docs/ROADMAP.md` — created Android implementation milestones B1–B8.

---

## 2026-06-23 — Defer sync engine; offline-only model for v1

- `android/docs/DECISIONLOG.md` — appended ADR: sync engine deferred; ships offline-only; outbox table retained in schema; B8 trigger changed to foreground-only; settings screen drops "Sync now".
- `android/docs/ROADMAP.md` — B7 marked `[DEFERRED]` with forward note; B8 sweep/watcher trigger updated to foreground-only; C1 smoke test stripped of sync steps.
- `android/docs/CONTEXT.md` — sync engine section replaced with deferred notice; settings screen description updated; `connectivity_plus` marked deferred.

---

## 2026-06-23 — B1: scaffold + drift schema + DAOs

- `android/app/` — `flutter create` Android-only scaffold (`--org com.aashish --project-name spendarr --empty`); app id `com.aashish.spendarr`. Flutter 3.44.0 / Dart 3.12.0.
- `android/app/pubspec.yaml` — added B1 deps: `flutter_riverpod`, `riverpod_annotation`, `drift`, `drift_flutter`, `go_router`, `uuid`; dev: `build_runner`, `drift_dev`, `riverpod_generator`. Versions pinned via `pubspec.lock`.
- `android/app/lib/db/tables.dart` — drift tables: `Categories`, `Transactions` (amount INTEGER cents), `RecurringRules`, `OutboxEntries` (SQL name `outbox`), `SyncMetaEntries` (SQL name `sync_meta`). Enums `TransactionKind`, `TransactionSource`, `OutboxOp` via `textEnum`. Synced tables carry `id` (UUID PK), `createdAt`/`updatedAt`/`deletedAt` (epoch ms). No FK constraints.
- `android/app/lib/db/database.dart` — `AppDatabase` (`@DriftDatabase`, schemaVersion 1) with injectable `QueryExecutor` for in-memory test DBs; on-device path via `drift_flutter`.
- `android/app/lib/db/daos/` — `CategoriesDao`, `TransactionsDao`, `RecurringDao`, `OutboxDao`, `SyncMetaDao`: reactive `watch*` streams (filter `deletedAt IS NULL`), upsert, soft-delete/archive, outbox enqueue/queue/remove, syncMeta put/getValue.
- `android/app/lib/theme.dart` — Material 3 dark theme, seed `0xFF7C4DFF` (deep violet, distinct from heerr green).
- `android/app/lib/router.dart` — go_router with 6 routes (`/today` initial, `/add`, `/history`, `/categories`, `/recurring`, `/settings`); placeholder screens.
- `android/app/lib/main.dart` — `ProviderScope` + `MaterialApp.router`.
- `android/app/test/db/dao_test.dart` — 9 DAO unit tests (B1 gate): insert→stream emits, soft-delete/archive sets `deletedAt` + filters, outbox FIFO enqueue/remove, syncMeta round-trip, recurring pause. All green.
- `android/app/lib/db/**/*.g.dart` — committed drift codegen output.
- Gates: `dart run build_runner build` clean; `flutter analyze` clean; `flutter test` 9/9 green.

---

## 2026-06-23 — B2 (trimmed): dio client + ApiError + Settings screen

Scope trimmed for offline-only (sync/summary/domain models deferred — see DECISIONLOG).

- `android/app/pubspec.yaml` — added `dio`, `flutter_secure_storage`; dev `http_mock_adapter`.
- `android/app/lib/api/api_error.dart` — typed `ApiError` + `ApiErrorKind` (unauthorized/forbidden/unprocessable/network/server/unknown); `ApiError.fromDio` maps status codes + extracts `detail` envelope. Hand-written (no JSON/freezed).
- `android/app/lib/api/endpoints.dart` — `Endpoints.health` = `/api/v1/health` (only live endpoint).
- `android/app/lib/api/client.dart` — `dioProvider` (base URL from settings + bearer interceptor, rebuilds on settings change); `ApiClient` interface + `DioApiClient.health()` (maps `DioException`→`ApiError` at call site); `apiClientProvider`.
- `android/app/lib/providers/settings.dart` — `AppSettings` value class; `SettingsStore` interface; `SecureSettingsStore` (flutter_secure_storage, keys `backend_base_url`/`bearer_token`); `settingsStoreProvider`; `Settings` AsyncNotifier with `save()`.
- `android/app/lib/screens/settings_screen.dart` — URL + token (obscured) fields, Save, Test connection (calls `/health`, success/failure snackbars); prefills from stored settings.
- `android/app/lib/router.dart` — `/settings` now routes to real `SettingsScreen`.
- `android/app/test/api/client_test.dart` — 7 tests: 200 happy + 401/403/422/500/418 + no-response network mapping.
- `android/app/test/providers/settings_test.dart` — 3 tests: load, unconfigured-empty, save-persists-and-refreshes (in-memory fake store).
- `android/app/test/screens/settings_screen_test.dart` — 4 widget tests: Save persists + snackbar, prefill, Test-connection success/failure snackbars (fake store + fake ApiClient).
- Gates: `build_runner` clean; `flutter analyze` clean; `flutter test` 23/23 green.

---

## 2026-06-23 — B3: Today + Add transaction screens (local DB only)

- `android/app/lib/db/database_provider.dart` — `appDatabaseProvider` (`@Riverpod(keepAlive: true)`); opens `AppDatabase`, closes on dispose; overridden in tests with `NativeDatabase.memory()`.
- `android/app/lib/db/daos/transactions_dao.dart` — added `watchByOccurredRange(fromMs, toMs)` (active rows in a UTC ms range, newest first).
- `android/app/lib/util/money.dart` — `parseAmountToCents` (rejects >2 decimals / negatives / junk) and `formatCents` (two-decimal string). No `double` anywhere.
- `android/app/lib/providers/categories.dart` — `activeCategoriesProvider` (hand-written `StreamProvider`).
- `android/app/lib/providers/transactions.dart` — `netFlowCents` (income−expense, investment excluded), `todayUtcBounds`, `todayTransactionsProvider`, `todayNetFlowProvider`, `transactionWriterProvider`. `TransactionWriter.add()` writes the drift row + outbox entry (op=upsert, table=transactions) in one `db.transaction`. Hand-written providers (drift row types — see DECISIONLOG).
- `android/app/lib/widgets/category_chip.dart` — emoji+name `ActionChip`.
- `android/app/lib/screens/today_screen.dart` — net flow (red when negative) from local stream; chip grid of categories used today (tap → quick-add `/add?categoryId=`); loading spinner; FAB → `/add`; Settings action.
- `android/app/lib/screens/add_txn_screen.dart` — amount, kind `SegmentedButton` (default expense), category dropdown (defaults to first / quick-add param), date picker (local noon, default today), note; Save writes via `TransactionWriter` then pops. Inline amount error; "pick a category" guard.
- `android/app/lib/router.dart` — `/today`→TodayScreen, `/add`→AddTxnScreen (reads `categoryId` query param).
- `android/app/test/util/money_test.dart` (3), `test/providers/transactions_test.dart` (3: bounds, atomic write, net-flow over insert/delete/investment), `test/screens/add_txn_flow_test.dart` (1: full Add→Today integration through the real router).
- Gates: `build_runner` clean; `flutter analyze` clean; `flutter test` 30/30 green.
- Note: widget tests of drift-backed screens use explicit `pump(Duration)` (never `pumpAndSettle` — the loading/saving `CircularProgressIndicator`s animate forever) and unmount + drain at the end to clear drift's stream-coalescing timers.
