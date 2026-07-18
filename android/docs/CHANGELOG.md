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

---

## 2026-06-23 — B4: Categories + Recurring screens (local DB only)

- `android/app/lib/db/daos/categories_dao.dart` — `archiveCategory` now bumps `updatedAt` alongside `deletedAt`.
- `android/app/lib/db/daos/recurring_dao.dart` — `setActive` now requires `updatedAt`; added `activeRules()` (Future snapshot, for widget tests where a `watch().first` would hang under the fake clock).
- `android/app/lib/util/cron.dart` — `RecurrencePreset`, `cronForPreset` (daily `0 0 * * *` / weekly `0 0 * * 1` / monthly `0 0 1 * *` / custom), `isValidCron` (5-field check), `nextRunAtMs` (best-effort display hint).
- `android/app/lib/providers/categories.dart` — added `CategoryWriter` (`add`, `archive`) + `categoryWriterProvider`; drift row + outbox in one transaction. Outbox op: upsert for add, delete for archive.
- `android/app/lib/providers/recurring.dart` — `activeRecurringProvider`, `RecurringWriter` (`add`, `setActive`) + `recurringWriterProvider`. Pause/resume is an upsert.
- `android/app/lib/screens/categories_screen.dart` + `add_category_screen.dart` — list with archive action + kind label; add screen with quick-pick emoji row, name, kind.
- `android/app/lib/screens/recurring_screen.dart` + `add_recurring_screen.dart` — list joined with category (emoji/name), amount, next-run, pause/resume `Switch`; add screen with category dropdown, amount, kind, recurrence preset (+ custom cron field), note.
- `android/app/lib/screens/today_screen.dart` — added a temporary nav `Drawer` (History/Categories/Recurring/Settings) so sections are reachable on-device. Full bottom-nav deferred to B5.
- `android/app/lib/router.dart` — `/categories`, `/categories/add`, `/recurring`, `/recurring/add` now route to real screens.
- Tests: `test/util/cron_test.dart` (7), `test/providers/category_writer_test.dart` (2: add+outbox, archive+outbox-delete), `test/providers/recurring_writer_test.dart` (2: add, pause), `test/screens/categories_flow_test.dart` (1: add→list→archive), `test/screens/recurring_flow_test.dart` (1: add→list→pause). Updated B1 `dao_test` for the new `setActive` signature.
- Gates: `flutter analyze` clean; `flutter test` 43/43 green (run with `--timeout 90s` as a hang guard).

---

## 2026-06-23 — B5 (trimmed): History screen with local aggregation

Scope trimmed for offline-only (online `/summary` + fallback deferred to B7 — see DECISIONLOG).

- `android/app/pubspec.yaml` — added `fl_chart`.
- `android/app/lib/providers/summary.dart` — `HistoryPeriod` enum; `rangeForPeriod` (day/week[Mon-start]/month → UTC ms windows); `SpendByCategory` + `aggregateSpendByCategory` (expense-only, joined, sorted desc); `transactionsInRangeProvider` (`StreamProvider.family` keyed by `(int,int)` range record, reuses `watchByOccurredRange`).
- `android/app/lib/widgets/spend_bar_chart.dart` — `fl_chart` bar chart of spend per category (cents→double for pixel height only).
- `android/app/lib/screens/history_screen.dart` — period `SegmentedButton`, custom date-range picker, chart + categorised transaction list (signed amounts, colored by kind), empty state.
- `android/app/lib/router.dart` — `/history` → `HistoryScreen`; removed the now-unused `_Placeholder` widget (all primary routes are real screens) and the redundant material import.
- Tests: `test/providers/summary_test.dart` (7: range day/week/month, aggregation incl. exclusions/unknown/empty, and a seeded-drift day/week/month window check) + `test/screens/history_screen_test.dart` (2: empty state, chart+list render and re-render on period toggle).
- Gates: `flutter analyze` clean; `flutter test` 52/52 green (`--timeout 90s` hang guard).

---

## 2026-06-23 — B6: CSV export (ExportService + share sheet)

- `android/app/pubspec.yaml` — added `share_plus`, `path_provider`.
- `android/app/lib/db/daos/transactions_dao.dart` — `activeTransactions()` / `transactionsInRange()` Futures (oldest-first, for export).
- `android/app/lib/db/daos/categories_dao.dart` — `allCategories()` (incl. archived, for name resolution).
- `android/app/lib/services/export_service.dart` — `ExportService`: `buildCsv({fromMs,toMs})` (pure, fixed columns, local `YYYY-MM-DD` date, `formatCents` amounts, RFC-4180 escaping); `exportToCsv({cacheDir,…})` writes `spendarr_export_<ts>.csv`.
- `android/app/lib/providers/export.dart` — `exportServiceProvider`; `cacheDirProvider` (path_provider, overridable); `FileSharer` interface + `PlatformFileSharer` (share_plus `SharePlus.instance.share`) + `fileSharerProvider`; `exportRowCountProvider` (reactive count, family keyed by `(int?,int?)`).
- `android/app/lib/screens/export_screen.dart` — date-range picker (default all time), reactive row-count preview, Export CSV button (write + share), loading indicator.
- `android/app/lib/screens/history_screen.dart` + `settings_screen.dart` — export entry points (AppBar icon / Settings row) → `/export`.
- `android/app/lib/router.dart` — `/export` route.
- Tests: `test/services/export_service_test.dart` (8: header, all-rows/soft-delete-excluded, decimal amounts, category resolution incl. archived, local date, RFC-4180 escaping, ordering, range filter), `test/screens/export_screen_test.dart` (2: reactive count, export writes file + shares via fakes/temp dir + `runAsync`).
- Gates: `flutter analyze` clean; `flutter test` 62/62 green.

---

## 2026-07-13 — Seed default categories on first run

- `android/app/lib/db/seed_categories.dart` — `kDefaultCategories` (6 income: Salary/RD Maturity/FD Maturity/ESOPs/Mutual Funds/Interest; 11 expense: Food/Tea/Groceries/Rent/Household/Loan/Electronics/Learning/Beauty/Health/Social); `CategorySeeder.seedDefaults()` (flag-guarded via `sync_meta['default_categories_seeded']`, inserts missing defaults through `CategoryWriter.add()`, skips names that already exist case-insensitively); `categorySeederProvider`, `seedDefaultCategoriesProvider`.
- `android/app/lib/main.dart` — `SpendarrApp` → `ConsumerWidget`; watches `seedDefaultCategoriesProvider` fire-and-forget on startup.
- `android/app/test/db/seed_categories_test.dart` — 4 tests: fresh DB seeds all 17 + outbox rows + sets flag; second run is a no-op; pre-existing case-insensitive name match is not duplicated; timestamps are UTC epoch ms.
- `android/docs/DECISIONLOG.md` — ADR: flag-guarded idempotent seeding chosen over a schema migration.
- Gates: `flutter analyze` clean; `flutter test` 66/66 green.

---

## 2026-07-13 — Inline category creation from Add-transaction

- `android/app/lib/widgets/category_form.dart` — extracted `CategoryForm` (emoji field + quick-emoji row + name + kind `SegmentedButton` + Save) from `add_category_screen.dart`; takes `initialKind` and reports the new id via `onSaved`.
- `android/app/lib/screens/add_category_screen.dart` — shrunk to a `Scaffold` hosting `CategoryForm(onSaved: (_) => context.pop())`; behavior unchanged (`categories_flow_test.dart` passes without modification).
- `android/app/lib/screens/add_txn_screen.dart` — dropdown gains a "＋ New category" sentinel item that opens a `CategoryForm` in a modal bottom sheet (defaulting to the currently selected transaction kind), auto-selecting the new category on save; the dead-end "No categories yet" text is replaced with a "Create category" button that opens the same sheet. Added `_categoryFieldGeneration` + a `ValueKey` on the dropdown to force a clean rebuild after the sheet closes (`DropdownButtonFormField` otherwise keeps the sentinel visually selected).
- `android/app/test/screens/add_txn_inline_category_test.dart` — 2 widget tests: empty-categories flow (create → auto-select → save transaction; outbox has both `categories` and `transactions` rows) and existing-categories flow (dropdown "New category" item opens the sheet defaulting to the currently selected kind).
- Gates: `flutter analyze` clean; `flutter test` 68/68 green.

---

## 2026-07-13 — Fix: today's window no longer goes stale after midnight

- `android/app/lib/providers/transactions.dart` — added `localDayTickProvider` (`StreamProvider<DateTime>`, emits the current local day, then on-change every minute via `Stream.periodic` + `.distinct()`); `todayTransactionsProvider` now watches it and recomputes `todayUtcBounds()` per emission instead of once at provider creation.
- `android/app/test/providers/transactions_test.dart` — added a `localDayTickProvider rollover` group: overrides the tick with a controllable `StreamController`, seeds transactions on two different days, and asserts the window switches from day A to day B as the tick advances.
- `android/docs/DECISIONLOG.md` — ADR: 1-minute tick chosen over a lifecycle-observer-only refresh.
- Gates: `flutter analyze` clean; `flutter test` 69/69 green.

---

## 2026-07-13 — Home screen: Day/Week/Month summary (replaces "net flow today")

- `android/app/lib/providers/summary.dart` — added `periodLabel` (hoisted from History's private `_periodLabel`), `PeriodSummary` (`incomeCents`/`expenseCents`/`netCents`), and `summarizeTransactions` (income − expense, investment excluded — consistent with `netFlowCents`).
- `android/app/lib/screens/home_screen.dart` (new; replaces `today_screen.dart`) — `HomeScreen`: `SegmentedButton<HistoryPeriod>` (default Day) driving `rangeForPeriod` + `transactionsInRangeProvider`, watching `localDayTickProvider` so week/month windows also roll over; Net/Income/Expense figures via `summarizeTransactions`; quick-add category-chip grid scoped to the selected period (was always "today"). Drawer and FAB unchanged; AppBar title "Home".
- `android/app/lib/screens/history_screen.dart` — now imports `periodLabel` from `summary.dart` instead of a private copy.
- `android/app/lib/router.dart` — `/today` now builds `HomeScreen` (path renamed to `/home` in the next milestone, bottom-nav).
- `android/app/test/providers/summary_test.dart` — 2 new tests for `summarizeTransactions` (mixed kinds, empty list).
- `android/app/test/screens/home_screen_test.dart` (new) — 3 widget tests: Month view shows income dated the 1st while Day view doesn't (the reported bug, now fixed); chips reflect the categories used in the selected period; FAB still routes to `/add`.
- `android/app/test/screens/add_txn_flow_test.dart` — updated stale `'Net flow today'` label assertion for the new Home layout (Net/Income/Expense all read `0.00` initially — 3 matches, not 1).
- `android/docs/DECISIONLOG.md` — ADR: Home/History split rationale.
- Gates: `flutter analyze` clean; `flutter test` 74/74 green.

---

## 2026-07-13 — Bottom navigation shell replaces the temporary Drawer

- `android/app/lib/widgets/app_shell.dart` (new) — `AppShell`: `Scaffold` wrapping the `StatefulNavigationShell` with a Material 3 `NavigationBar` (Home/History/Categories/Recurring/Settings).
- `android/app/lib/router.dart` — restructured around `StatefulShellRoute.indexedStack` (5 branches, one screen each) inside `AppShell`; `/add`, `/categories/add`, `/recurring/add`, `/export` are now root-level `GoRoute`s with `parentNavigatorKey` so they push over the shell (covering the nav bar) instead of nesting in a branch navigator. `/home` is now the canonical path (was `/today`); `initialLocation` updated.
- `android/app/lib/screens/home_screen.dart` — removed `_NavDrawer` and the AppBar settings gear (Settings is a tab now).
- `android/app/lib/screens/home_screen.dart`, `categories_screen.dart`, `recurring_screen.dart` — gave each screen's `FloatingActionButton` an explicit unique `heroTag` (`home-fab`/`categories-fab`/`recurring-fab`). `StatefulShellRoute.indexedStack` keeps every branch mounted simultaneously, so the previous implicit (shared) hero tags collided the moment more than one branch was live — a real navigation-crashing bug the shell exposed, not a test-only artifact.
- `android/app/test/screens/app_shell_test.dart` (new) — 3 widget tests: all 5 destinations render and Home is initial; tapping a destination swaps the visible screen while the nav bar persists; the `/add` FAB push covers the nav bar (root-navigator push) and popping returns to the same tab with the shell intact.
- `android/docs/DECISIONLOG.md` — ADR: bottom-nav shell + the FAB hero-tag fix it surfaced.
- Gates: `flutter analyze` clean; `flutter test` 77/77 green.

---

## 2026-07-13 — Category picker filtered by transaction kind

- `android/app/lib/widgets/category_form.dart` — `CategoryForm.onSaved` signature changed from `ValueChanged<String>` to `void Function(String id, TransactionKind kind)`, reporting the kind that was actually persisted.
- `android/app/lib/screens/add_category_screen.dart` — updated call site for the new `onSaved` signature (kind ignored here).
- `android/app/lib/screens/add_txn_screen.dart` — category list filtered to `c.kind == _kind`; switching the kind segmented button resets category selection and forces a dropdown rebuild; a quick-add chip's `initialCategoryId` now aligns `_kind` to that category's own kind on first build instead of defaulting to Expense; the inline "New category" sheet aligns `_kind` to whatever kind was chosen when saved.
- `android/app/test/screens/add_txn_kind_filter_test.dart` (new) — 3 widget tests: dropdown shows only the selected kind's categories across all three kinds; zero categories for a kind shows "Create category" instead of an empty dropdown; a quick-add chip for an Income category pre-selects Income.
- `android/app/test/screens/add_txn_inline_category_test.dart` — seeded an Income category alongside the existing Expense one so the "switch to Income → New category" flow still has a non-empty (filtered) dropdown to interact with.
- `android/docs/DECISIONLOG.md` — ADR: filtering rationale.
- Gates: `flutter analyze` clean; `flutter test` 80/80 green.

---

## 2026-07-13 — Categories screen grouped by kind

- `android/app/lib/screens/categories_screen.dart` — categories grouped into Income/Expense/Investment sections (fixed order, header per non-empty group only); removed the now-redundant per-row `kindLabel` subtitle.
- `android/app/test/screens/categories_grouping_test.dart` (new) — 2 widget tests: headers render in Income→Expense→Investment order with each category under the right one; a kind with zero categories shows no header.
- `android/docs/DECISIONLOG.md` — ADR: grouping rationale.
- Gates: `flutter analyze` clean; `flutter test` 82/82 green.

---

## 2026-07-13 — Home: month-only ledger, no Day/Week toggle

- `android/app/lib/screens/home_screen.dart` — `HomeScreen` is now a `ConsumerWidget` (no more period state); always uses `rangeForPeriod(HistoryPeriod.month, day)` driven by `localDayTickProvider` (auto-resets on month rollover). Added a chronological, date-grouped transaction ledger below the summary/chips, newest date first (`_localDate` groups by local calendar day; `Map` insertion order preserves newest-first since `transactionsInRangeProvider` already returns newest-first).
- `android/app/test/screens/home_screen_test.dart` — rewritten for the month-only design: no toggle/`Day`/`Week` text present; income dated the 1st visible immediately without switching views; chips reflect every category used this month; a new test asserts date-grouped ledger rows in newest-first order; FAB test unchanged.
- `android/docs/DECISIONLOG.md` — ADR: month-only ledger rationale.
- Gates: `flutter analyze` clean; `flutter test` 83/83 green.

---

## 2026-07-13 — Record time-of-day on transactions

- `android/app/lib/util/datetime.dart` (new) — pure `occurredAtMs(date, {hour, minute})` and `formatTimeOfDay(occurredAtMs)` (zero-padded local `HH:mm`); no Flutter dependency, unit-testable directly.
- `android/app/lib/screens/add_txn_screen.dart` — added `TimeOfDay _time` (default `TimeOfDay.now()`) + a `showTimePicker` button next to the date button; `_occurredAtMs()` now combines date + time instead of pinning to noon.
- `android/app/lib/screens/home_screen.dart` — ledger rows show `formatTimeOfDay(t.occurredAt)` as a subtitle.
- `android/app/lib/screens/history_screen.dart` — transaction list subtitle now includes the time alongside the date.
- `android/app/test/util/datetime_test.dart` (new) — 4 unit tests: date+time combination, stray time-of-day on the date argument is ignored, `HH:mm` formatting incl. midnight/23:59.
- `android/app/test/screens/add_txn_flow_test.dart` — added a test asserting the time-picker button renders with today's current time.
- `android/app/test/screens/home_screen_test.dart`, `history_screen_test.dart` — added tests seeding transactions at specific times and asserting the formatted time renders in the ledger/list.
- `android/docs/DECISIONLOG.md` — ADR: UI-layer-only fix (schema already supported full-precision timestamps); native `TimePicker` interaction intentionally left untested, consistent with the existing `showDatePicker` convention.
- Gates: `flutter analyze` clean; `flutter test` 90/90 green.

---

## 2026-07-13 — Edit transactions; make-recurring as an Add/Edit field

- `android/app/lib/db/daos/transactions_dao.dart` — `updateTransaction()` (partial update: amount/kind/categoryId/occurredAt/note/recurringRuleId; leaves `createdAt` untouched, bumps `updatedAt`).
- `android/app/lib/db/daos/recurring_dao.dart` — `updateRule()` (partial update: categoryId/amount/kind/cron/note; leaves `createdAt`/`active` untouched, bumps `updatedAt`).
- `android/app/lib/providers/transactions.dart` — `TransactionWriter.add()` gained an optional `recurringRuleId` param; new `TransactionWriter.update()` writes the drift update + outbox upsert in one transaction.
- `android/app/lib/providers/recurring.dart` — new `RecurringWriter.update()`, same drift-update + outbox-upsert pattern.
- `android/app/lib/util/cron.dart` — added `presetLabel` (hoisted from `add_recurring_screen.dart`'s private copy) and `presetForCron` (reverse lookup: cron string → matching preset, or `custom`).
- `android/app/lib/screens/add_txn_screen.dart` — now serves both create and edit. New optional `editTransactionId` param triggers an async load (`transactionById` + linked `ruleById`) that prefills every field. New "Make this recurring" `SwitchListTile` + `RecurrencePreset` picker (shown when toggled on). Save logic: toggled off → `recurringRuleId: null` (unlinks only, rule untouched); toggled on with no prior link → creates a new rule; toggled on while already linked → updates that rule in place (kept in sync with the transaction's current fields) rather than creating a duplicate.
- `android/app/lib/screens/add_recurring_screen.dart` — uses the hoisted `presetLabel` instead of a private copy.
- `android/app/lib/screens/home_screen.dart`, `history_screen.dart` — ledger/list rows navigate to `/add?editTransactionId=<id>` on tap.
- `android/app/lib/router.dart` — `/add` route now also reads the `editTransactionId` query param.
- `android/app/test/db/dao_test.dart` — 3 new tests: `updateTransaction` field changes + createdAt preservation, note/recurringRuleId clearing, `updateRule` field changes + createdAt/active preservation.
- `android/app/test/providers/transactions_test.dart`, `recurring_writer_test.dart` — new tests for `add(recurringRuleId:)`, `TransactionWriter.update()`, `RecurringWriter.update()`.
- `android/app/test/screens/add_txn_edit_test.dart` (new) — 4 widget tests: edit prefills all fields and updates in place (createdAt preserved, single outbox row); make-recurring creates a linked rule on a new transaction; toggling recurring off on an edit unlinks without deleting the rule; toggling on while already linked keeps the same rule id and syncs its fields.
- `android/app/test/screens/home_screen_test.dart`, `history_screen_test.dart` — new tests: tapping a row opens it for editing.
- `android/docs/DECISIONLOG.md` — ADR covering the update-vs-upsert DAO distinction and the three confirmed recurring-link sync rules.
- Gates: `flutter analyze` clean; `flutter test` 103/103 green.

---

## 2026-07-14 — Custom app icon

- `android/app/assets/icon.png` (new) — user-supplied wallet/₹ icon (1024×1024), copied in as the `flutter_launcher_icons` source image.
- `android/app/pubspec.yaml` — added `flutter_launcher_icons: ^0.14.0` dev dependency + config (`image_path: "assets/icon.png"`, `android: true`, `ios: false`).
- `android/app/android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` — regenerated via `dart run flutter_launcher_icons` (48/72/96/144/192px respectively).
- `android/docs/DECISIONLOG.md` — ADR: tool choice + no adaptive-icon split.
- Gates: `flutter analyze` clean; `flutter test` 103/103 green; debug APK builds and installs with the new icon.

---

## 2026-07-14 — Rupee display formatter (Home redesign M1)

- `android/app/lib/util/money.dart` — new `formatRupees(int cents, {bool signed = false})`: Indian digit grouping (`₹1,23,456.78`), paise dropped when whole, true minus sign (U+2212) for negatives, optional `+` prefix for positives. `formatCents` untouched — it still round-trips with `parseAmountToCents` for the Add/Edit amount field and stays the CSV export format.
- `android/app/lib/screens/home_screen.dart`, `history_screen.dart`, `recurring_screen.dart` — display-only amounts switched to `formatRupees`; ledger/list rows now show a signed amount (income `+`, expense `−`, investment unsigned) instead of relying on colour alone.
- `android/app/test/util/money_test.dart` — new `formatRupees` unit tests (grouping, paise drop, sign handling).
- `android/app/test/screens/home_screen_test.dart`, `history_screen_test.dart`, `add_txn_flow_test.dart` — amount assertions updated to the new rupee format; the Add/Edit screen's amount `TextField` prefill assertions (`formatCents`, e.g. `'12.34'`) are unchanged.
- Gates: `flutter analyze` clean; `flutter test` 106/106 green.

---

## 2026-07-14 — Black and gold AMOLED theme (Home redesign M2)

- `android/app/lib/theme.dart` — replaced `ColorScheme.fromSeed(0xFF7C4DFF)` (violet) with an explicit dark `ColorScheme`: primary gold `kGold` (`0xFFD4AF37`), primary container `kGoldMuted` (`0xFF8A6A19`), surface `kSurfaceBlack` (`0xFF121212`), scaffold `kBackgroundBlack` (`0xFF000000`), error `kExpenseRed` (`0xFFE57373`); new semantic constants `kIncomeGreen`, `kTextSecondary`. Component themes added: `NavigationBarThemeData` (black bg, gold selected state), `FloatingActionButtonThemeData` (gold circle, black icon), `SegmentedButtonThemeData` (gold-muted selected segment), `CardThemeData` (20dp radius, surface colour).
- `android/app/lib/screens/home_screen.dart`, `history_screen.dart` — hardcoded `Colors.green` for income amounts replaced with `kIncomeGreen`.
- `android/app/test/util/theme_test.dart` (new) — asserts the palette, FAB theme, and NavigationBar theme.
- Gates: `flutter analyze` clean; `flutter test` 110/110 green.

---

## 2026-07-14 — Local profile settings: display name and monthly budget (Home redesign M3)

- `android/app/lib/providers/profile.dart` (new) — `Profile {displayName, monthlyBudgetCents}` + hand-written `ProfileNotifier extends AsyncNotifier<Profile>` (drift row types via `syncMetaDao` — DECISIONLOG 2026-06-23 rule). Backed by `sync_meta` keys `display_name`/`monthly_budget_cents` (local-only, no outbox — these never sync to the server). `save({displayName, monthlyBudgetCents})` is a partial update: a null argument leaves that field unchanged.
- `android/app/lib/screens/settings_screen.dart` — new "Profile" section above "Server": display name field (feeds the Home greeting, M4) and monthly budget field (feeds the Home month ring, M5), parsed via the existing `parseAmountToCents`; inline error on invalid input. Existing fields keyed (`settings_base_url`, `settings_token`) instead of relying on `TextField` index, since the new fields shift ordinal position.
- `android/app/test/providers/profile_test.dart` (new) — load-empty, save round-trips as int cents, partial-update semantics.
- `android/app/test/screens/settings_screen_test.dart` — new Profile-section tests; existing tests switched from `.at(0)/.at(1)` to key-based finders; `Test connection` taps now `ensureVisible` first (button moved below the fold once Profile fields were added).
- Gates: `flutter analyze` clean; `flutter test` 115/115 green.

---

## 2026-07-14 — Home greeting header with month switcher (Home redesign M4)

- `android/app/lib/providers/clock.dart` (new) — `nowProvider = Provider<DateTime Function()>` for injectable wall-clock time (the existing `localDayTickProvider` is day-granular only and can't drive an hour-of-day greeting).
- `android/app/lib/util/datetime.dart` — `greetingFor(DateTime)` (Morning 05:00 / Afternoon 12:00 / Evening 17:00 / Night 21:00) and `monthLabel(year, month)` ("July 2026").
- `android/app/lib/providers/summary.dart` — `homeMonthAnchorProvider` (`StateProvider<({int year, int month})?>`, null = follow current month) and `effectiveHomeMonthProvider` (anchor if set, else derived from `localDayTickProvider`). `StateProvider` now comes from `package:flutter_riverpod/legacy.dart` — Riverpod 3 moved it out of the main barrel.
- `android/app/lib/widgets/home_header.dart` (new) — `HomeHeader`: greeting (+ optional display name) and a month label with prev/next chevrons.
- `android/app/lib/screens/home_screen.dart` — AppBar replaced by `HomeHeader`; range now derived from `effectiveHomeMonthProvider` instead of the raw current-day tick; forward navigation capped at the current month.
- `android/app/test/util/datetime_test.dart`, `test/providers/summary_test.dart` — new unit tests for the greeting boundaries and the anchor/effective-month providers.
- `android/app/test/screens/home_screen_test.dart` — new tests: greeting with injected clock + profile name, greeting fallback, month-switcher previous chevron, forward chevron disabled at the current month.
- Gates: `flutter analyze` clean; `flutter test` 123/123 green.

---

## 2026-07-14 — Month ring hero with budget progress and summary chips (Home redesign M5)

- `android/app/lib/util/cron.dart` — `occurrencesInMonth(cron, year, month)`: fires-per-month count for the day-of-month-only/weekday-only cron shapes `cronForPreset` produces (daily/weekly/monthly); returns 0 for a genuine custom cron (both day-of-month and weekday set). `nextFireMs(cron, {from})` resolves through `presetForCron` → `nextRunAtMs`.
- `android/app/lib/providers/summary.dart` — `PeriodSummary` gained `investmentCents`; `ringProgress(spentCents, budgetCents)` (spend/budget clamped to `[0,1]`, 0 when unset).
- `android/app/lib/widgets/month_ring.dart` (new) — `MonthRing`: `CustomPainter`-based circular progress (gold arc, round caps, dark track) with center primary/secondary text + optional footer chip. Chosen over `fl_chart` to avoid implicit animation timers that fight the project's no-`pumpAndSettle` testing rule; painting itself is untested, the surrounding text/fields are.
- `android/app/lib/widgets/summary_chips.dart` (new) — `SummaryChips`: Expenses/Investments actuals for the displayed month + a **projected** Recurring total (`Σ occurrencesInMonth(rule.cron, ...) × rule.amount` over active rules) — v1 doesn't execute recurring rules yet, so a "spent so far" figure would always read ₹0.
- `android/app/lib/screens/home_screen.dart` — replaced the old Net text + quick-add category chips with the ring + Income/Expense stats + `SummaryChips`. Ring semantics: current month with a budget set → "₹X left to spend" (or "₹X over budget") + "Day N/M" footer; past month → "₹X spent"; no budget → "₹X spent" + "Set a budget" secondary (always shows "of ₹Y budget" when a budget exists).
- **Test-infra fix**: the taller ring/stats/chips layout pushed ledger rows past `ListView`'s sliver `cacheExtent` in the default 600px test viewport, so several ledger-row assertions silently found 0 widgets with no thrown exception. Fixed by setting a tall virtual test window (`tester.view.physicalSize = Size(800, 3000)`) in the Home/add-txn-flow test `_pump` helpers instead of scrolling per-test.
- `android/app/test/util/cron_test.dart`, `test/providers/summary_test.dart` — new unit tests for `occurrencesInMonth`, `nextFireMs`, `investmentCents`, `ringProgress`.
- `android/app/test/screens/home_screen_test.dart` — quick-add-chips test removed (chips are gone); new ring-state tests (budget set/over-budget/unset/past-month) and a summary-chips test. `add_txn_flow_test.dart`, `app_shell_test.dart` updated for new/duplicated chip and stat text.
- Gates: `flutter analyze` clean; `flutter test` 138/138 green.

---

## 2026-07-14 — Journal timeline with day/week/month zoom (Home redesign M6)

- `android/app/lib/widgets/home_timeline.dart` (new) — `HomeTimeline` + `TimelineZoom {day, week, month}` + `timelineZoomProvider`. Filters/aggregates client-side from the already-loaded month transaction list — no new DB queries. Month = the existing date-grouped ledger (unchanged visually). Day = today's transactions only, no date header. Week = one row per weekday of the current week (`ExpansionTile` + a gold `LinearProgressIndicator` bar proportional to that day's expense spend, relative to the week's max), tap expands to that day's transactions.
- **Known v1 limitation** (documented, not fixed here): Week zoom is computed from `monthTxns` only, so a week overlapping the previous/next month shows partial data for the days outside the currently displayed month. Acceptable trade-off to avoid an extra DB query per zoom.
- `android/app/lib/screens/home_screen.dart` — ledger rendering extracted into `HomeTimeline`; `allowZoom: isCurrentMonth` — Day/Week only apply to the current month (a past month always shows Month view, since "today" isn't well-defined then). Removed now-dead `_localDate`/`_signedRupees` helpers (moved into the widget).
- `android/app/test/screens/home_screen_test.dart` — replaced the "no Day/Week toggle" test (that behavior is now the opposite: Day/Week *are* offered) with "ring and income figures stay month-scoped regardless of timeline zoom" (preserves the original bug-fix guarantee: income on the 1st still counts in the Income stat even when viewing Day zoom, though it drops out of the Day ledger itself); added Day-zoom, Day-empty-state, Week-zoom, and past-month-hides-zoom-control tests.
- Gates: `flutter analyze` clean; `flutter test` 142/142 green.

---

## 2026-07-14 — Deterministic upcoming-renewal insight card (Home redesign M7)

- `android/app/lib/util/cron.dart` — (already added in M5) `nextFireMs`, reused here.
- `android/app/lib/providers/insights.dart` (new) — pure `upcomingRenewal(rules, categoriesById, now) → RenewalFact?`: soonest **active** rule (paused rules are excluded — `watchActiveRules()` only filters soft-deletes, not the pause flag) firing within 7 days; skips rules with an unparseable ("genuine custom") cron since `nextFireMs` returns null for those. Label = rule note if set, else the category name. `renewalPhrase(fireMs, now)` → "today"/"tomorrow"/"in N days". Deterministic facts only — no spending-pattern analysis (v2 fence, CLAUDE.md §3).
- `android/app/lib/widgets/insight_card.dart` (new) — `InsightCard`: gold renew icon + "{label} renews {phrase}".
- `android/app/lib/screens/home_screen.dart` — computes `renewalFact` from `activeRecurringProvider` + categories + the injected clock; shows the card below the timeline when non-null. Also de-duplicated the categories-by-id map (previously computed both outside and inside the `txnsAsync.when` builder).
- `android/app/test/providers/insights_test.dart` (new) — soonest-rule selection, paused-rule skip, custom-cron skip, 7-day-horizon boundary, note-vs-category-name label fallback, `renewalPhrase` boundaries.
- `android/app/test/screens/home_screen_test.dart` — card renders for an active daily rule firing tomorrow; absent with no rules.
- Gates: `flutter analyze` clean; `flutter test` 153/153 green.

---

## 2026-07-14 — Quick-add bottom sheet with kind pre-selection (Home redesign M8, final milestone)

- `android/app/lib/screens/add_txn_screen.dart` — new `initialKind` constructor param, applied in `initState()` only when `initialCategoryId` is unset (category alignment wins) and always overwritten by `_loadExisting()` in edit mode (the loaded transaction's kind wins).
- `android/app/lib/router.dart` — `/add` now also reads a `?kind=` query param (`_parseKind`, matched against `TransactionKind.values` by name) and passes it as `initialKind`.
- `android/app/lib/screens/home_screen.dart` — FAB now opens a gold-accented `showModalBottomSheet` listing Income/Expense/Investment (no Transfer — not a `TransactionKind`), each pushing `/add?kind=<name>`.
- `android/app/test/screens/home_screen_test.dart` — FAB-sheet test (exact three options, no Transfer; tapping Income lands on Add with Income pre-selected).
- `android/app/test/screens/add_txn_flow_test.dart` — new `/add?kind=income` router test; existing FAB-tap tests updated to select a kind from the sheet before reaching the Add screen.
- `android/app/test/screens/add_txn_inline_category_test.dart`, `add_txn_kind_filter_test.dart`, `app_shell_test.dart` — same FAB→sheet→kind bridging update; two tests that previously switched kind via the Add screen's own `SegmentedButton` after a default-Expense FAB tap now pick the kind directly from the sheet instead, since tapping `find.text('Income')` while the sheet is still open is ambiguous with Home's own "Income" stat label (added in M5) mounted underneath.
- `android/docs/CONTEXT.md` — Home/Settings screen descriptions rewritten for the full redesign (ring, chips, timeline, insight card, FAB sheet, Profile section); theme table entry updated; "Out of scope" gained Transfer and the calendar-grid Month view.
- `android/docs/DECISIONLOG.md` — consolidated ADR for the cross-cutting M1–M8 decisions (ring semantics, projected-vs-actual recurring chip, list-over-grid, local-only budget/name storage, no-Transfer FAB sheet).
- Gates: `flutter analyze` clean; `flutter test` 154/154 green.

---

## 2026-07-14 — Release-signing config + GitHub Actions APK publish workflow

- `.github/workflows/android-publish.yml` (new) — builds a signed release APK and attaches it to a GitHub Release on every `v*` tag push. Mirrors the sibling `heerr` project's `android-publish.yml`: Java 17 + Flutter 3.44.0, decodes `ANDROID_KEYSTORE_BASE64` into `android/keystore.jks`, writes `key.properties` from three more secrets (`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD`), then `flutter build apk --release` with the tag baked into `--build-name`/`--build-number`. No `dev_defaults`-style seeding step needed (unlike heerr) — spendarr's backend URL/token are entered at runtime via Settings, not compiled in.
- `android/app/android/app/build.gradle.kts` — added a real `release` signing config reading `key.properties` (gitignored), matching heerr's pattern: falls back to the debug key if `key.properties` is absent, so a fresh clone still compiles. No R8/minify changes (spendarr has no WorkManager reflection issue to work around).
- `android/app/android/key.properties.example` (new) — template for the local `key.properties`; the real file stays gitignored (already covered by `android/app/android/.gitignore`).
- `android/app/README.md` — new "Building a release APK" section: one-time `keytool` keystore generation, local release build/install, and the CI secrets table.
- **Deliberately not generated by the agent**: the actual keystore/passwords. Credential materialization (generating and handling a live signing secret) was blocked by the auto-mode safety classifier — correctly, since a mis-scoped/leaked keystore is unrecoverable for future updates. The user runs the `keytool` command themselves per the new README section and sets the four GitHub secrets by hand.
- Gates: `flutter analyze` clean; `flutter build apk --debug` succeeds with the new (unpopulated) signing config, confirming the Gradle file parses and falls back to the debug key correctly.

---

## 2026-07-14 — Warm-metallic-gold visual refinements (post-redesign polish round)

Iterative visual polish against the user's mockup (`spendarr home.png`) and their detailed "premium warm metallic gold" gradient spec, verified after every step by building on the `pixel7_api35` emulator with seeded test data and screenshot-diffing against the mockup.

- `android/app/lib/theme.dart` — palette reworked to the spec: base gold `kGold` now champagne `0xFFC89B3C` (was `0xFFD4AF37`, which read as flat yellow); `kGoldMuted 0xFF8A621E`; surface `kSurfaceBlack` now `0xFF111111` with new `kCardBorder 0xFF242424` (1px card borders); `kDivider 0xFF1D1D1D` (50% opacity divider theme); text `kTextSecondary 0xFFA0A0A0` + new `kTextMuted 0xFF666666`; positives/negatives now muted emerald `0xFF58C77A` / muted red `0xFFD46A6A`. New gradient constants: `kPrimaryGoldGradient` (4-stop), `kPremiumGoldGradient` (5-stop, `#FFF1B8→#8A621E`), `kFabGradient`, `kActiveTabGradient`, `kGoldIconGradient`, `kRingProgressColors/Stops` (6-stop), `kRingTrackGradient`, `kRingGlow`. Component themes: black AppBars (no M3 surface tint), `#111111` bottom sheets, bordered cards.
- `android/app/lib/widgets/gilded.dart` (new) — shared `Gilded` ShaderMask wrapper painting any icon/text with the metallic gradient; used app-wide so gold elements stay consistent.
- `android/app/lib/widgets/gold_fab.dart` (new) — `GoldFab`: 5-stop premium-gradient circular FAB with black drop shadow + subtle outer gold glow (ThemeData can't express gradients). Replaces the flat FABs on Home/Categories/Recurring.
- `android/app/lib/widgets/month_ring.dart` — ring rebuilt to the spec's three layers: dark-bronze gradient track (`#3A3124→#19140E`), 6-stop progress arc whose gradient spans the FULL circle with the arc revealing the first `progress` portion (an earlier attempt compressed all stops into the arc and went dark immediately; another placed the highlight at the tip — both visibly wrong against the mockup, which is brightest at the top/start), and a barely-there `#F2D27A` glow (10%, blur 18). Round caps are hand-drawn butt-cap + endpoint circles (a round `StrokeCap` on a sweep-gradient arc samples wrapped angles and rendered a wrong-colour blob at the seam); the tip cap colour is interpolated from the gradient at the current progress. API split into `amountText`/`descriptor`/`hint` — only the amount is bold, gold-gradient (`Gilded`-style ShaderMask), auto-shrunk via `FittedBox` so it can never overflow the ring; the mockup has no "of ₹X budget" line so it was removed.
- `android/app/lib/screens/home_screen.dart` — Income stat moved to the ring's left flank, Expense to its right (mockup layout); FAB-sheet kind icons gilded.
- `android/app/lib/widgets/home_timeline.dart` — Day/Week/Month selector rebuilt as `ZoomPillSelector` (single continuous outlined pill, 999px radius, premium-gradient selected segment, no per-segment borders/checkmark — Material's `SegmentedButton` can't render the mockup's shape); week bars now premium-gradient fills on a `kDivider` track.
- `android/app/lib/widgets/summary_chips.dart` — three separate chips merged into one bordered card with thin dividers and gilded icon-in-black-bubble per section (mockup layout).
- `android/app/lib/widgets/home_header.dart` — month label gilded. `lib/widgets/app_shell.dart` — selected nav icons gilded via `selectedIcon`. `lib/screens/categories_screen.dart` — kind group headers gilded. `lib/widgets/insight_card.dart` — bordered card + gilded icon.
- `android/app/test/util/theme_test.dart` — palette assertions updated to the new spec values + gradient-stop-count guards. `test/screens/home_screen_test.dart`, `add_txn_flow_test.dart` — assertions updated for the split ring text (`₹5,180` + `left to spend` as separate widgets) and the ring amount now duplicating the Expense figure when no budget is set.
- Gates: `flutter analyze` clean; `flutter test` 154/154 green; screenshot-verified on emulator against the mockup (ring top crop, FAB/pill crops).

---

## 2026-07-14 — Adaptive launcher icon (metallic wallet, pure-black background)

- `android/app/assets/icon.png` — replaced with the user's new metallic wallet artwork (1254×1254).
- `android/app/assets/icon_foreground.png` (new) — the same artwork padded onto a 1908×1908 black canvas so the adaptive-icon mask's ~66% safe zone doesn't clip the wallet.
- `android/app/pubspec.yaml` — `flutter_launcher_icons` config gained `adaptive_icon_background: "#000000"` + `adaptive_icon_foreground`, closing the earlier ADR's deliberate no-adaptive-icon gap: the Pixel launcher letterboxes legacy icons inside its circular mask and fills the leftover ring with a colour sampled from the artwork, which produced a thick golden border around the icon. With the adaptive split the icon renders as a full black circle with the gold wallet.
- Regenerated: `mipmap-*/ic_launcher.png` (legacy fallback, pre-Android-8), new `mipmap-anydpi-v26/ic_launcher.xml`, `drawable-*/ic_launcher_foreground.png`, `values/colors.xml`.
- Verified on the emulator app drawer after clearing the launcher's persisted icon cache (`pm clear` on the launcher — the stale cache initially kept showing the old ring even after reinstall).

---

## 2026-07-14 — Ring centre shows money left this month (income − expenses − investments)

- `android/app/lib/screens/home_screen.dart` — the ring's centre figure was `budget − expenses`; it now shows `income − expenses − investments` for the displayed month, matching the mockup's own numbers (₹6,000 income − ₹1,180 spent → "₹4,820 left to spend") and the intent "how much money is left per month". Descriptors: "left to spend" (current month), "left over" (past month), "overspent" (negative). The monthly-budget setting now only drives the ring's fill fraction (expenses/budget); the "Set a budget" hint still appears when unset.
- `android/app/test/screens/home_screen_test.dart` — ring tests rewritten around the new semantics (income+expense+investment seeds, past-month "left over", overspent case); collision counts adjusted where the ring amount no longer duplicates the Expense figure.
- Gates: `flutter analyze` clean; `flutter test` 154/154 green; emulator-verified (₹6,000 − ₹4,820 − ₹1,000 → "₹180 left to spend").

---

## 2026-07-15 — Ring fill = outflows ÷ income (budget no longer drives the meter)

- `android/app/lib/providers/summary.dart` — `ringProgress` re-defined: `(expenses + investments) ÷ income`, clamped `[0,1]`; with no income, any outflow → `1` (fully overspent), none → `0`. Previously `expenses ÷ budget`, which left the meter permanently empty unless a monthly budget was set in Settings — the user added salary/expenses/investments and saw an empty ring.
- `android/app/lib/screens/home_screen.dart` — fill now consistent with the centre figure (a full ring = everything earned this month is spent); the "Set a budget" hint removed. The Settings → Profile monthly-budget field remains but is dormant (no longer read by Home; kept for a future budget-alert feature rather than churning the Settings screen and profile tests).
- `android/app/test/providers/summary_test.dart`, `test/screens/home_screen_test.dart` — `ringProgress` units and ring widget tests rewritten for the income-based fill (0.97 for the 6,000/4,820/1,000 scenario; no-income overspend → full ring; empty month → empty ring, no hint).
- Gates: `flutter analyze` clean; `flutter test` 154/154 green; emulator-verified (~97% fill with the seeded scenario).

---

## 2026-07-15 — Timeline rows: time on the left, note as subtitle; category filter bar

- `android/app/lib/widgets/home_timeline.dart` — two remaining mockup gaps closed:
  - `_TxnRow` now renders the recorded time (`HH:mm`) on the far left of each row (inside the `ListTile` leading, before the emoji — keeps existing `widgetWithText(ListTile, ...)` test finders working), with the transaction's note as the subtitle (e.g. "Cafe Coffee Day") instead of the time.
  - New "All ▾" category filter (tune icon + `PopupMenuButton`) at the timeline's top right, backed by `timelineCategoryFilterProvider` (`StateProvider<String?>`, null = all). The menu lists categories actually used in the displayed month (plus a stale selection so it can always be cleared); the filter applies across all three zooms. Empty sentinel `''` maps to null since `PopupMenuItem` values can't be null.
- `android/app/test/screens/home_screen_test.dart` — new tests: filter narrows the ledger to one category and restores on "All"; time renders in the row's leading with the note as subtitle.
- Gates: `flutter analyze` clean; `flutter test` 156/156 green; emulator-verified against the mockup's timeline section.

---

## 2026-07-15 — Delete transactions; 20% larger row amounts

- `android/app/lib/db/daos/transactions_dao.dart` — `softDeleteTransaction` gained an optional `updatedAt` so deletions bump LWW ordering (same convention as `archiveCategory`); existing callers unaffected.
- `android/app/lib/providers/transactions.dart` — `TransactionWriter.delete(id)`: soft-delete + outbox `op=delete` entry (payload `{id, deleted_at, updated_at}`) in one DB transaction. No hard deletes (project rule).
- `android/app/lib/screens/add_txn_screen.dart` — edit mode gains a delete icon in the AppBar with a confirmation dialog ("A linked recurring rule (if any) is not deleted" — deleting a transaction never touches its rule, consistent with the unlink-only semantics from the edit/recurring ADR); pops back with a "Deleted" snackbar. Absent in create mode.
- `android/app/lib/widgets/home_timeline.dart`, `lib/screens/history_screen.dart` — row amount font 20% above the ListTile default (bodyMedium × 1.2), per user feedback that the amounts were too small.
- `android/app/test/providers/transactions_test.dart` — `delete()` unit test (soft-delete retained row, deletedAt=updatedAt, outbox delete entry, active-rows stream excludes it).
- `android/app/test/screens/add_txn_edit_test.dart` — delete flow widget tests (cancel is a no-op; confirm soft-deletes + pops; no delete icon in create mode).
- Gates: `flutter analyze` clean; `flutter test` 159/159 green; emulator-verified.

---

## 2026-07-16 — Row amount font matched to the note; investment amounts in gold

- `android/app/lib/widgets/home_timeline.dart`, `lib/screens/history_screen.dart` — reverted yesterday's 20%-larger amount font (per user feedback it should instead match the note/subtitle line, not be bigger than it) — amount `fontSize` is now `Theme.of(context).textTheme.bodyMedium?.fontSize`, same as the ListTile's default subtitle style.
- Investment-kind amounts now render in `kGold` (was unstyled/default white) in both the Home timeline and History list — consistent with the ring/FAB/pill metallic treatment elsewhere.
- `android/app/test/screens/home_screen_test.dart` — new test: investment amount colour is `kGold`, and its font size matches the note subtitle's resolved `bodyMedium` size.
- Gates: `flutter analyze` clean; `flutter test` 160/160 green; emulator-verified (Edit screen's Investment segment and amounts already used gold; ledger row visually confirmed via Food/Salary rows — the third seeded row was obscured by the FAB in this 3-row test scenario, a pre-existing layout quirk not touched here).

---

## 2026-07-16 — Custom 3D icons for the Expenses/Investments/Recurring summary strip

- `android/app/assets/icons/expenses.png`, `investment.png`, `recurring.png` (new) — user-supplied gold 3D-render icons (down arrow, up arrow, wallet-with-refresh), replacing the flat Material icons (`Icons.south`/`Icons.north`/`Icons.account_balance_wallet_outlined`) in the summary strip below the month ring.
- `android/app/pubspec.yaml` — registered `assets/icons/` under `flutter: assets:`.
- `android/app/lib/widgets/summary_chips.dart` — `_Item` now takes an `iconAsset` path instead of `IconData`; renders via `Image.asset` clipped to the existing circular black bubble (`ClipOval` + `CircleAvatar` background). Dropped the `Gilded` gradient-mask wrapper for these three icons since the artwork is already pre-rendered gold.
- No test previously asserted on the specific `IconData` values, so no test changes were needed.
- Gates: `flutter analyze` clean; `flutter test` 160/160 green; emulator-verified — all three icons render correctly in the summary strip.

---

## 2026-07-16 — Add/Edit Transaction screen redesign (mockup: `Add transaction.png`)

- `android/app/lib/util/datetime.dart` — new `formatDayMonthYear` (`"16 Jul 2026"`), `weekdayName` (`"Thursday"`), `formatTime12h` (`"10:47 AM"`); existing `formatTimeOfDay`/`occurredAtMs`/`greetingFor`/`monthLabel` untouched.
- `android/app/lib/widgets/kind_pill_selector.dart` (new) — `KindPillSelector`: full-width Expense/Income/Investment pill selector with per-segment icons and a gold-gradient selected segment, generalizing `home_timeline.dart`'s `ZoomPillSelector` construction. Replaces `SegmentedButton<TransactionKind>` on this screen.
- `android/app/lib/screens/add_txn_screen.dart` — full visual rebuild of `build()` to match the mockup: bordered `_FieldCard`s under caps `_SectionLabel`s for Amount (inline-editable, focus-pencil button), Kind (`KindPillSelector`), Category (tappable card → `showModalBottomSheet` of kind-filtered categories + "New category", replacing the `DropdownButtonFormField` and its `_categoryFieldGeneration` rebuild hack), Date & Time (two cards, 12-hour time + weekday), Note (120-char `TextField` with a visible counter), and Make This Recurring (Switch + a frequency card, shown only while toggled on, that opens its own preset-picker sheet). Save button is a `FilledButton` wrapped in the premium gold gradient (same technique as `GoldFab`), reading "Save Changes" in edit mode. AppBar centered, back/delete icons gilded. All save/edit/delete/recurring-link logic is unchanged — this is a `build()`-only rewrite.
- `android/app/test/screens/add_txn_edit_test.dart`, `add_txn_flow_test.dart`, `add_txn_inline_category_test.dart`, `add_txn_kind_filter_test.dart`, `home_screen_test.dart`, `history_screen_test.dart`, `app_shell_test.dart` — updated for the new UI: `'Edit transaction'`/`'Add transaction'` → `'Edit Transaction'`/`'Add Transaction'`; `SwitchListTile` finders → `find.byType(Switch)`; `SegmentedButton<TransactionKind>` finders → `find.byType(KindPillSelector)`; dropdown-menu taps → category-card-tap-then-sheet-row-tap; date/time prefill assertions updated to the new 12-hour/weekday format; edit-mode Save assertions changed to `'Save Changes'`. Added a tall test viewport (`Size(800, 2200)`) to every `add_txn_*_test.dart` file — the redesigned screen's extra card chrome pushes the Save button/Switch past the default test viewport's sliver cacheExtent (same gotcha as the M5 Home-redesign ADR).
- New tests: `test/widgets/kind_pill_selector_test.dart` (labels render, tap reports the tapped kind, selected label renders black); `add_txn_kind_filter_test.dart` gained a category-sheet kind-filtering test (only the current kind's categories listed; tapping one selects it and closes the sheet); `add_txn_edit_test.dart` gained a recurring-card-visibility test (frequency card only mounted while the toggle is on) and a note-field 120-character-limit test.
- `android/app/lib/screens/add_txn_screen.dart` AppBar's back button gained an explicit `tooltip: 'Back'` — required for `WidgetTester.pageBack()` (used by `app_shell_test.dart`) to find it, since a custom `IconButton` doesn't get Material's implicit back-button tooltip the way an auto-generated `BackButton` does.
- Gates: `flutter analyze` clean; `flutter test` 168/168 green (was 160; +8 new); emulator-verified — the Add screen (Investment kind, empty state) closely matches the mockup: amount card, gold pill selector, category/date/time/note cards, and the gradient Save button all render as designed.

---

## 2026-07-16 — Category icons: theme-matching gold bubbles replace colourful emoji

- `android/app/lib/util/category_icon.dart` (new) — `categoryIconFor(String emoji) → IconData`: a fixed lookup table covering the 17 seeded default-category emoji plus `CategoryForm`'s 16 quick-pick emoji (~23 distinct entries), e.g. `🍔→Icons.lunch_dining`, `💼→Icons.work_outline`, `🏠→Icons.home_outlined`. Anything outside the table (including a genuinely custom emoji a user types into `CategoryForm`) falls back to `kCategoryIconFallback` (`Icons.label_outline`) rather than rendering the raw emoji.
- `android/app/lib/widgets/category_icon_bubble.dart` (new) — `CategoryIconBubble(emoji, {size})`: a dark `CircleAvatar` containing the mapped icon gilded via the existing `Gilded` ShaderMask, matching the mockup's monochrome-gold-icon-in-a-dark-circle category glyph (coffee cup, briefcase, fuel pump, etc. in `spendarr home.png`).
- Every raw `Text(category.emoji)` display site now renders `CategoryIconBubble` instead: `categories_screen.dart`, `history_screen.dart`, `recurring_screen.dart`, `home_timeline.dart` (ledger rows + the category-filter popup menu), `category_chip.dart`, `spend_bar_chart.dart` (bar-chart axis labels), and the Add-transaction category picker sheet/selected-card in `add_txn_screen.dart` and `add_recurring_screen.dart`'s category dropdown. Row layouts that previously concatenated `'${emoji}  ${name}'` into one `Text` were split into `CategoryIconBubble` + a plain name `Text`, since a bubble can't be inlined into a string.
- **`emoji` remains the stored field, `CategoryForm`'s picker, and the sync/outbox payload — this is a display-only re-theme**, not a data-model or migration change (see DECISIONLOG). `CategoryWriter`, the `Categories` table, and the outbox JSON payload are untouched.
- `android/app/test/util/category_icon_test.dart`, `test/widgets/category_icon_bubble_test.dart` (new) — mapping spot-checks + fallback-icon coverage.
- Updated existing widget-test assertions across `add_txn_edit_test.dart`, `add_txn_inline_category_test.dart`, `add_txn_kind_filter_test.dart`, `home_screen_test.dart` that previously matched combined `'🍔  Food'`-style text — now assert the category **name** alone (scoped via `find.widgetWithText(ListTile/PopupMenuItem, name)` where the name alone would otherwise be ambiguous).
- Gates: `flutter analyze` clean; `flutter test` 173/173 green (was 168; +5 new); emulator-verified — Home ledger rows for Salary/Food/Rent/Mutual Funds render briefcase/burger/house/trending-up gold icons instead of the native colourful emoji, matching the mockup.

---

## 2026-07-16 — History screen: apply the established black+gold design system

- `android/app/lib/widgets/pill_selector.dart` (new) — generic `PillSelector<T>({items, selected, labelFor, onChanged})`: the gold-gradient rounded-pill toggle, extracted from `home_timeline.dart`'s `ZoomPillSelector` (which was hard-coded to `TimelineZoom`). `ZoomPillSelector` is now a thin same-named wrapper delegating to `PillSelector<TimelineZoom>`, so existing `find.byType(ZoomPillSelector)` callers/tests are unaffected.
- `android/app/lib/widgets/field_card.dart` (new) — public `SectionLabel` and `FieldCard`, promoted from `add_txn_screen.dart`'s private `_SectionLabel`/`_FieldCard` (caps section header + bordered dark card, used throughout Add/Edit-transaction). `add_txn_screen.dart` now imports and uses these instead of its own private copies — no behavior change there.
- `android/app/lib/screens/history_screen.dart` — restyled to reuse the above: `SegmentedButton<HistoryPeriod>` → `PillSelector<HistoryPeriod>`; AppBar's Export/Pick-range icons wrapped in `Gilded`; the custom-range label is now a small bordered chip (same visual language as `MonthRing`'s "Day N/M" footer) instead of plain `Text`; the spend-by-category bar chart is now wrapped in a `SectionLabel('SPEND BY CATEGORY')` + `FieldCard`; transaction row subtitles split the previously-joined `'date time · note'` string into two lines (`kTextSecondary`) instead of one, with the note only shown when present. `CategoryIconBubble` leading icons and the signed/coloured trailing amount (already applied in the category-icon change) are untouched.
- `android/app/test/screens/history_screen_test.dart` — added one assertion locking in `find.byType(PillSelector<HistoryPeriod>)`; no other existing assertions needed changes (the date+time subtitle text is preserved verbatim as its own `Text`, just restyled/regrouped).
- `android/docs/DECISIONLOG.md` — ADR recording the `PillSelector<T>` generalization and the design-reuse rationale.
- Gates: `flutter analyze` clean; `flutter test` 173/173 green (no net new tests — a restyle of already-tested behavior); Home ledger screenshot-verified (same `PillSelector`/`Gilded`/`CategoryIconBubble` components render correctly in this build); History itself verified via its existing widget-test coverage rather than a fresh screenshot — emulator nav-bar taps were unreliable this session (same flakiness noted in earlier CHANGELOG entries), so the automated suite was the primary signal.

---

## 2026-07-16 — Category form: pick from the same gold icon set instead of typing an emoji

- **Bug report**: after the category-icon re-theme, picking a category's emoji in `CategoryForm` no longer matched what displayed elsewhere — every emoji outside the ~23-entry curated map (including several of the form's own old `quickEmojis` presets, and any freeform-typed emoji) silently fell back to the generic `Icons.label_outline` icon everywhere else in the app, so users saw their pick "auto-mapped to something else."
- `android/app/lib/util/category_icon.dart` — added `categoryIconChoices`, the curated map's keys as a stable-ordered `List<String>` — the exact set of emoji with a real icon mapping.
- `android/app/lib/widgets/category_form.dart` — replaced the freeform emoji `TextField` + `quickEmojis` colourful-emoji grid with a tappable grid of `CategoryIconBubble`s (one per `categoryIconChoices` entry), gold-ring-highlighted when selected. The user now picks directly from the same gold icon set rendered everywhere else in the app — what's tapped is exactly what's stored and exactly what displays, with no possibility of an unmapped/fallback-icon surprise. `_emojiController` and the free-text entry path are removed entirely; the underlying `emoji` field, `CategoryWriter.add()` signature, and outbox payload are unchanged (still a display/input-only change, consistent with the earlier category-icon ADR).
- `android/app/test/screens/categories_flow_test.dart`, `add_txn_inline_category_test.dart` — updated the two tests that assumed a `TextField` index of 1 for the name field (index 0 was previously the emoji field); name is now `CategoryForm`'s only `TextField`.
- `android/app/test/widgets/category_form_test.dart` (new) — tapping a non-default icon and saving persists that exact emoji (`db.categoriesDao.categoryById(id).emoji == tappedEmoji`, no fallback substitution); every curated choice renders as its themed icon in the picker itself.
- Gates: `flutter analyze` clean; `flutter test` 175/175 green (was 173; +2 new).

---

## 2026-07-16 — Home polish: shrink-to-fit stat amounts, Expense stat includes investments, left-aligned day headers with a daily invested/spent summary, and Add-recurring re-themed

- **Bug reports**: (1) large Income/Expense figures beside the month ring wrapped to a second line instead of shrinking to fit; (2) the "Expense" figure only reflected `TransactionKind.expense` totals, undercounting real outflow once investments were factored in; (3) the ledger's date group header (`_MonthView`) rendered centered instead of left-aligned, inconsistent with the rest of the app's left-aligned text; (4) that header carried no per-day summary, so a day's earn/spend shape wasn't visible without opening every row; (5) `AddRecurringScreen` still used the pre-redesign stock `SegmentedButton`/`DropdownButtonFormField` look, unlike `AddTxnScreen`'s card-based gold theme.
- `android/app/lib/screens/home_screen.dart` — `_Stat`'s amount `Text` is now wrapped in a `FittedBox(fit: BoxFit.scaleDown)` with `maxLines: 1, softWrap: false`, so a wide amount shrinks instead of wrapping. The "Expense" stat now reads `outflowCents` (`expenseCents + investmentCents`, the same figure already driving the ring's fill fraction) instead of `expenseCents` alone; the "Expenses" chip in `SummaryChips` (a separate, documented expenses-only actual) is unchanged.
- `android/app/lib/widgets/home_timeline.dart` — `_MonthView`'s outer `Column` now sets `crossAxisAlignment: CrossAxisAlignment.start` (previously defaulted to `center`, which centered the date label). Extracted a new `_DayHeader` widget: the date label stays left-aligned on the left, with that day's `Invested ₹X` (gold) / `Spent ₹Y` (secondary) totals right-aligned via a `Spacer()` — computed from that date-group's own transactions, shown only when nonzero.
- `android/app/lib/screens/add_recurring_screen.dart` — full rewrite to match `AddTxnScreen`'s theme: `SegmentedButton<TransactionKind>` → `KindPillSelector`; `DropdownButtonFormField` category/repeat pickers → `FieldCard` rows opening bottom sheets (matching `AddTxnScreen`'s `_pickCategory`/`_pickRecurrencePreset` pattern); amount/note fields restyled as gilded `FieldCard`s; category list now filtered to the selected kind (the same invariant `AddTxnScreen` already enforces); Save button restyled as the gold-gradient pill button. Field semantics (amount is the first `TextField`, category defaulting, cron validation) are unchanged.
- `android/app/test/screens/recurring_flow_test.dart` — added the tall-viewport `tester.view.physicalSize` setup (established pattern) since the taller card layout pushed the Save button past the default test viewport's `ListView` cacheExtent.
- `android/app/test/screens/home_screen_test.dart` — updated the "summary chips" test's expectations for the Expense-stat total change (`₹300` now matches once, the Expenses chip only; `₹2,300` now matches twice, ring + Expense stat); added a new test asserting the date header's left alignment and its `Invested ₹2,000` / `Spent ₹300` day-summary text.
- Gates: `flutter analyze` clean; `flutter test` 176/176 green (was 175; +1 new). Blind-tap emulator verification skipped (established unreliable this session); relied on the updated/added widget tests as the correctness signal.

---

## 2026-07-16 — Recurring screen: full redesign from "Recurring expenses.png" reference

- `android/app/lib/screens/recurring_screen.dart` — full rewrite matching the supplied mockup: large bold "Recurring" title + a gilded filter icon (opens a bottom sheet to filter by kind — All/Expense/Income/Investment); a bordered "Total recurring" summary card (sum of active rules' amounts) with an "N active" count on the right; rules split into `ACTIVE (n)` / `INACTIVE (n)` sections (previously a single flat list with a generic "No recurring rules yet." message), each with its own themed empty state when zero. Each rule renders as a `FieldCard` row: category icon, name, amount, a gold-dot + frequency line (`Monthly`/`Weekly`/etc., via `presetForCron`/`presetLabel`), a vertical divider, "Next due on" + date (gold, `DD Mon YYYY` format matching the mockup), the existing pause/resume `Switch`, and a new kebab (⋮) menu with a "Delete" action (confirm dialog, soft-deletes the rule — past transactions it already created are untouched).
- `android/app/lib/providers/recurring.dart` — added `RecurringWriter.delete(id)`: soft-deletes via `recurringDao.softDeleteRule` + an `OutboxOp.delete` outbox entry, mirroring `TransactionWriter.delete`'s existing pattern. No delete action existed anywhere in the app before this (rules could only be paused, never removed).
- `android/app/test/screens/recurring_flow_test.dart` — updated the empty-state assertions for the new Active/Inactive sections; added a second test covering pause moving a rule from Active to Inactive and the new kebab-menu delete flow (confirms via dialog, then asserts the rule is gone from `activeRules()`).
- Gates: `flutter analyze` clean; `flutter test` 177/177 green (was 176; +1 new). Blind-tap emulator verification skipped (established unreliable this session); relied on the updated/added widget tests as the correctness signal.

---

## 2026-07-16 — Day-summary simplified to Income/Expense; Settings trimmed to Export CSV; CI now publishes an AAB too

- **Day-summary redo**: the just-added per-day header (`_DayHeader` in `home_timeline.dart`) no longer says "Invested"/"Spent" — it now shows only two figures, income (credit, green, `+₹X`) and expense (debit, red, `−₹Y`), where the expense figure folds in investments (money leaving the income pool either way — the goal is "money left", not a three-way category split). Confirmed this already rendered for every date group, not just the latest one (the earlier report of "only the latest day" was the same header code, verified correct once tested with two distinct date groups instead of one).
- `android/app/test/screens/home_screen_test.dart` — rewrote the day-header test with two separate date groups (multi-row sums that don't echo any single row's own amount, to prove it's a real per-day sum) and asserted both dates render their own summary. Updated three other pre-existing assertions (`add_txn_flow_test.dart`, and two spots in `home_screen_test.dart`) that now match the day-header text as well as the ledger row's own signed amount when both fall on the same single-transaction day (`findsNWidgets(2)` instead of `findsOneWidget`).
- `android/app/lib/screens/settings_screen.dart` — trimmed to a single themed "Export CSV" `FieldCard` row (`SectionLabel`/`FieldCard`/`Gilded`, same language as every other screen); Profile (display name/budget) and Server (backend URL/bearer token) sections are removed from the UI. The underlying `profileProvider`/`settingsProvider` and their local-drift/secure-storage persistence are untouched — they still have their own unit tests (`test/providers/profile_test.dart`, `test/providers/settings_test.dart`) and are still read elsewhere (e.g. Home's greeting) — this is a UI-visibility change only, not a removal of the feature.
- `android/app/test/screens/settings_screen_test.dart` — replaced the five old field/save/test-connection tests with one: Export CSV is the only visible option and navigates to `/export`.
- `.github/workflows/android-publish.yml` — added a `flutter build appbundle --release` step (same version/build-number baking and signing config as the existing APK build) and attaches the renamed `.aab` alongside the `.apk` to the GitHub Release. Needed because Play Store submissions require an AAB, not an APK.
- Gates: `flutter analyze` clean; `flutter test` 172/172 green (net -5 from the Settings test trim, +1 new Settings test, existing suite otherwise unaffected).

---

## 2026-07-16 — Day-summary header: match date font size, add a separator per day group

- `android/app/lib/widgets/home_timeline.dart` — `_DayHeader`'s income/expense summary text now uses `labelLarge` (same style as the date label) instead of the smaller `labelMedium`, since the smaller size read as an afterthought next to the date. `_MonthView` now renders a `kDivider`-coloured `Divider` before every date group (previously only one `Divider` at the very top of the whole month list), giving each day's block a clear visual break from the one before it.
- Gates: `flutter analyze` clean; `flutter test` 172/172 green (no test changes needed — purely a visual/style tweak, no new text or structural assertions to update).

---

## 2026-07-16 — Home: swipe the month ring left/right to browse months

- `android/app/lib/screens/home_screen.dart` — wrapped `MonthRing` in a `GestureDetector` (`onHorizontalDragEnd`, keyed off `details.primaryVelocity`) calling the same `goToMonth(±1)` the header's prev/next chevrons already use. Swipe right-to-left → next month (blocked past the current month, same as the disabled chevron); swipe left-to-right → previous month. The ring sits inside a vertically-scrolling `ListView`, so the horizontal gesture doesn't conflict with page scroll.
- `android/app/test/screens/home_screen_test.dart` — added a test flinging the `MonthRing` both directions, asserting it swaps between this-month/last-month transactions and that swiping "forward" past the current month is a no-op (mirrors the existing chevron test).
- Gates: `flutter analyze` clean; `flutter test` 173/173 green (+1 new).

---

## 2026-07-16 — Reset tag history ahead of the real v0.1.0 release

- Deleted the nine existing iteration tags (`v0.1.0`–`v0.1.8`) locally and on `origin`; confirmed via `gh release list` that no GitHub Releases existed for any of them (the publish workflow had never actually been run with real signing secrets, so nothing else needed cleanup).
- `README.md` — "Releasing" example changed from `git tag -a v0.2.0` to `git tag -a v0.1.0` to match. `android/app/README.md`'s own example, `pubspec.yaml`'s `version: 0.1.0+1`, and `android/docs/ROADMAP.md`'s B7 milestone target were already `v0.1.0` and needed no change.
- `android/docs/DECISIONLOG.md` — ADR recording the tag-history reset and why.
- No app code changed; docs/versioning only.

---

## 2026-07-16 — Home: FAB no longer covers the last ledger row

- `android/app/lib/screens/home_screen.dart` — the journal `ListView`'s bottom padding grew from `EdgeInsets.all(16)` to `EdgeInsets.fromLTRB(16, 16, 16, 96)`, so the last transaction row can scroll clear of the `GoldFab` instead of sitting underneath it when the user scrolls to the bottom of the month.
- Gates: `flutter analyze` clean; `flutter test` 173/173 green (no test changes — layout-only, no new/changed text or structure to assert on).

---

## 2026-07-16 — Play Store submission materials: store listing copy + privacy policy

- `android/app/store/release-notes.md` (new) — Play Console store-listing copy (short/full description, v0.1.0 "What's new" text) plus a submission checklist (data safety answers, content rating, privacy policy URL, package ID, screenshots still needed).
- `PRIVACY_POLICY.md` (new, repo root) — privacy policy for Play Console submission. States plainly what's stored (transactions/categories/recurring rules/prefs, local-only), that nothing leaves the device except a user-triggered CSV export, no third-party analytics/ads/trackers, and discloses Android's OS-level Auto Backup behavior (see the deferred-fix decision above) so the policy doesn't contradict what the app actually does on-device. No automatic retention sweep is claimed since B8 (`android/docs/ROADMAP.md`) is unbuilt — data persists until uninstall or manual deletion.
- No app code changed.

---

## 2026-07-16 — Category icons: any emoji is now allowed, gilded on-theme instead of mapped to a curated icon

- `lib/util/category_icon.dart` and `test/util/category_icon_test.dart` deleted — the curated ~23-entry `emoji → IconData` lookup is gone.
- `lib/widgets/category_icon_bubble.dart` — now renders `Text(emoji)` gilded via `Gilded`'s `ShaderMask` (`BlendMode.srcIn`) instead of `Icon(categoryIconFor(emoji))`, so any emoji renders gold-on-black on-theme, not just the curated set.
- `lib/widgets/category_form.dart` — icon picker replaced: a `TextField` accepts any emoji (system keyboard's emoji picker), plus a `_suggestedEmojis` grid of common shortcuts as tap-to-fill convenience only (not an enforced set).
- `lib/screens/recurring_screen.dart` — rule-card icon box updated the same way (gilded `Text(category.emoji)`).
- `test/widgets/category_icon_bubble_test.dart`, `test/widgets/category_form_test.dart` — rewritten for the new behavior; added a case proving an emoji outside the old curated set (and outside the new suggestions) is accepted and persisted exactly as typed.
- Fixed 3 unrelated pre-existing tests (`categories_flow_test.dart`, `add_txn_inline_category_test.dart` ×2) that hard-coded "Name is CategoryForm's only TextField" via `find.byType(TextField).first` — now `.at(1)`, since the new emoji `TextField` is field 0. Left unfixed, Name stayed empty, Save silently no-op'd, and the test hung until the 10-minute per-test timeout.
- Gates: `flutter analyze` clean; `flutter test` 170/170 green (net -3 vs. 173: -3 for the deleted `category_icon_test.dart`, ±0 for the rewritten widget tests, +1 new case for arbitrary-emoji entry).

---

## 2026-07-16 — Categories: edit support + Add/Edit screen re-themed to match Add-transaction

- `lib/db/daos/categories_dao.dart` — new `updateCategory()`, a partial update (name/emoji/kind + bumped `updatedAt`) that leaves `createdAt` untouched, mirroring `TransactionsDao.updateTransaction`.
- `lib/providers/categories.dart` — new `CategoryWriter.update()`: writes the drift update + an `OutboxOp.upsert` outbox entry in one transaction (an edit is still an upsert on the sync contract, per the existing outbox-op convention).
- `lib/widgets/category_form.dart` — full re-theme to match `AddTxnScreen`/`AddRecurringScreen`'s card-based black+gold language: `SectionLabel`/`FieldCard` wrap the icon and name fields, `SegmentedButton<TransactionKind>` replaced with `KindPillSelector`, plain `FilledButton` replaced with the gold-gradient Save button. New optional `editCategoryId` param: when set, async-loads the existing category (same `_existingLoaded` pattern as `AddTxnScreen`'s edit mode), prefills every field, and calls `CategoryWriter.update()` instead of `.add()` on save; the button reads "Update" instead of "Save" while editing.
- `lib/screens/add_category_screen.dart` — re-themed AppBar (gilded back arrow, matching every other Add/Edit screen); title switches to "Edit category" when `editCategoryId` is set; new `editCategoryId` param threaded through to `CategoryForm`.
- `lib/router.dart` — `/categories/add` now reads an `editCategoryId` query parameter, same pattern as `/add?editTransactionId=`.
- `lib/screens/categories_screen.dart` — each row is now tappable (→ `/categories/add?editCategoryId=<id>`), and the trailing archive icon is gilded for consistency with the rest of the app's icon language (was a plain unthemed `Icon`).
- Gates: `flutter analyze` clean; `flutter test` 174/174 green (+4 new: a DAO test for `updateCategory`, a `CategoryWriter.update` test, a `CategoryForm` edit-mode test, and a full tap-row-to-edit flow test). Also fixed a `SegmentedButton<TransactionKind>` finder in `add_txn_inline_category_test.dart` left over from the emoji-theming change, since `CategoryForm` no longer contains one.

---

## 2026-07-17 — Category emoji: stop gilding it into a solid gold blob

- `lib/widgets/category_icon_bubble.dart` — `CategoryIconBubble` no longer wraps the emoji in `Gilded`; the emoji now renders in its native colour. The dark circle background is unchanged.
- `lib/screens/recurring_screen.dart` — rule-card icon box updated the same way (plain `Text(category.emoji)`, no `Gilded`).
- `test/widgets/category_icon_bubble_test.dart` — updated to assert no `Gilded` wraps the emoji.
- Gates: `flutter analyze` clean; `flutter test` 174/174 green.

---

## 2026-07-17 — Recurring screen: summary splits by kind (Income/Investment/Expense) instead of one combined total

- `lib/screens/recurring_screen.dart` — `_SummaryCard` no longer shows a single "Total recurring" figure (which mixed money coming in with money going out into one number). It now shows three columns — Income (green), Investment (gold), Expense (red/error) — each summed from **all** active rules of that kind, independent of the screen's own kind filter (so filtering the list to one kind doesn't leave the other two summary columns at ₹0). New `_KindStat` widget for each column; the "N active" count in the header now counts all active rules, not just the filtered subset.
- `test/screens/recurring_flow_test.dart` — added a test seeding one active rule per kind and asserting each shows in its own summary column, and that no combined total (e.g. the sum of all three) appears anywhere.
- Gates: `flutter analyze` clean; `flutter test` 175/175 green (+1 new).

---

## 2026-07-17 — Category picker sheet: fixed non-scrollable list hiding "New category" behind long lists

- `lib/screens/add_txn_screen.dart` — `_pickCategory`'s bottom sheet used a fixed `Column`, which overflows and clips off-screen once the category list is longer than the sheet's available height — hiding both the tail of the list and the "＋ New category" row below it, so users with many categories couldn't scroll to pick one, or reach "New category" at all. Now `isScrollControlled: true` + a `ConstrainedBox` capping the sheet at 70% of screen height + a `ListView` (was `Column`), so a long list scrolls within the sheet instead of overflowing.
- `lib/screens/add_txn_screen.dart` — `_createCategory`'s sheet (the inline "New category" form) wrapped in `SafeArea` + `SingleChildScrollView`, since `CategoryForm`'s fields plus the keyboard (once a field is focused) could together exceed the sheet's height and push the Save button out of reach.
- `lib/screens/add_recurring_screen.dart` — same `Column` → `ListView` + `ConstrainedBox` fix applied to its own `_pickCategory` sheet (same bug, same cause).
- `test/screens/add_txn_kind_filter_test.dart` — added a regression test seeding 30 categories, confirming "＋ New category" isn't visible until the sheet is scrolled, and that scrolling and tapping it does reach the create-category form.
- Gates: `flutter analyze` clean; `flutter test` 176/176 green (+1 new).

## 2026-07-19 — Revert budget-based ring feature; Home ring layout: Income/Expense moved below the ring

- Reverted commits `2920cca` (budget-based month ring, budget setup/monthly re-prompt, recurring-chip income exclusion) and `58f5782` (its v0.1.3 release notes) via `git revert`, back to the v0.1.2 baseline — the budget feature is no longer in `main`. The `v0.1.3` tag/GitHub Release still points at the reverted commit and was intentionally left in place (user declined cleanup).
- `lib/screens/home_screen.dart` — Income/Expense stats no longer flank the month ring in narrow side columns (cramped, vertically centered against a 220px-tall ring with little room for wide amounts). The ring is now centered on its own row; Income/Expense sit in a separate full-width row directly below it, each getting the row's full width instead of a squeezed `Expanded` column.
- Gates: `flutter analyze` clean; `flutter test` 176/176 green (no test asserted on the flanking layout specifically, so no test changes were needed).

## 2026-07-19 — Home: colored Income/Expense text, then replaced with an Income/Expenses/Balance summary card

- `lib/screens/home_screen.dart` — the Income/Expense row below the ring (added earlier the same day) briefly got `kIncomeGreen`/`kExpenseRed` text colors, then was removed entirely per a follow-up request: the standalone row is gone, along with the now-unused `_Stat` widget and `recurringProjectedCents` computation.
- `lib/widgets/summary_chips.dart` — `SummaryChips` renamed from Expenses/Investments/Recurring to **Income/Expenses/Balance**, reusing the existing icon assets rather than sourcing new ones (`investment.png` → Income, `expenses.png` → Expenses unchanged, `recurring.png` → Balance). Balance = `PeriodSummary.netCents` (income − expenses, investments excluded, consistent with `netFlowCents`). Investment totals are no longer shown as a Home summary figure at all (still visible via History/Recurring elsewhere).
- Gates: `flutter analyze` clean; `flutter test` 176/176 green. Updated assertions across `home_screen_test.dart`, `add_txn_flow_test.dart`, and `app_shell_test.dart` for the new chip labels/values — several needed widening from `findsOneWidget` to `findsNWidgets(2/3)` since the Balance chip's income−expense figure frequently coincides with the ring amount or a ledger row's signed amount in these tests' seed data.

## 2026-07-19 — Categories screen: 3-column grid instead of one full-width row per category

- `lib/screens/categories_screen.dart` — each kind group's categories were a single-column `ListTile` list, wasting most of the row's width on a short name. Replaced with a `GridView.builder` (`SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3)`, `shrinkWrap: true` + `NeverScrollableScrollPhysics` inside the outer `ListView`, same as the pattern used elsewhere for sheet-embedded grids). New `_CategoryTile` widget: icon + name centered in a bordered card (tap → edit), with the archive action as a small `IconButton` overlaid in the top-right corner via `Stack`/`Positioned` (was the `ListTile`'s trailing icon).
- `test/screens/categories_grouping_test.dart` — the grid takes more vertical space per group than the old rows did, pushing the Investment group's header past the default 600px test viewport (only built lazily within the sliver's cache extent); added the same tall-virtual-window pattern already used in `home_screen_test.dart`.
- Gates: `flutter analyze` clean; `flutter test` 176/176 green (no new tests — same text/interaction assertions, no new behavior).
