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

---

## 2026-06-23 — DB-facing Riverpod providers are hand-written, not `@riverpod`

**Context:** B3 introduced providers returning drift's generated row classes — `StreamProvider<List<Category>>`, `StreamProvider<List<TransactionRow>>`. Annotating these with `@riverpod` for `riverpod_generator` fails the build with `InvalidTypeException: The type is invalid and cannot be converted to code`, even on a clean rebuild. `riverpod_generator` and `drift_dev` are separate `source_gen` builders; when riverpod_generator analyzes the provider, drift's generated part (where `Category`/`TransactionRow` are declared) is not yet resolvable, so the return type resolves to `InvalidType`. Providers returning hand-declared types (`AppDatabase`, `AppSettings`, `Dio`, `ApiClient`) are unaffected — `appDatabaseProvider` stays `@riverpod`.

**Decision:** Any provider whose type signature references a drift-generated class is **hand-written** as a plain top-level `StreamProvider`/`Provider`/`FutureProvider` (no `@riverpod`, no part file). Providers that only reference hand-declared types stay on `riverpod_generator`. Both styles coexist; `ref.watch` works across them. Naming matches the codegen convention (`activeCategoriesProvider`, `todayTransactionsProvider`, …) so call sites are identical.

**Why:** A handful of hand-written providers is far simpler than fighting cross-builder ordering with a custom `build.yaml`. This is the common, documented pattern in drift+riverpod projects. Generated providers are kept everywhere they work, preserving the locked-stack intent.

**Consequence for later milestones:** B4 (recurring/categories writes), B5 (summary aggregation over drift), B6 (export query), B8 (retention) will all touch drift row types — those providers must be hand-written too. Reserve `@riverpod` for non-drift providers.

**Alternatives considered:** Custom `build.yaml` to force builder ordering (fragile, poorly supported across versions); wrapper DTO classes mirroring each drift row so `@riverpod` sees hand-declared types (pure boilerplate, defeats drift's codegen); make `appDatabaseProvider` hand-written too (unnecessary — it returns `AppDatabase`, which resolves fine).

---

## 2026-06-23 — B4: outbox-op convention + temporary nav Drawer

**Context:** B4 added create/archive for categories and create/pause-resume for recurring rules. Each mutation must enqueue an outbox row (the forward sync contract), and the four primary screens needed an on-device entry point.

**Decision:**
- **Outbox op convention:** `OutboxOp.upsert` for create **and** update (including recurring pause/resume — a paused rule is an updated row, not a deleted one); `OutboxOp.delete` for archive (soft-delete). Every mutation bumps `updatedAt` to the mutation instant for later LWW; archive sets `deletedAt == updatedAt`. To support this, the B1 DAO methods `archiveCategory` (now also writes `updatedAt`) and `setActive` (now requires `updatedAt`) were tightened.
- **Writers mirror `TransactionWriter`:** `CategoryWriter` and `RecurringWriter` write the drift row + outbox entry in a single `db.transaction`. Hand-written providers (drift row types — see prior ADR).
- **Recurrence is store-only:** presets map to 5-field cron strings (`util/cron.dart`); `nextRunAt` is a best-effort display hint. Nothing executes rules in v1 — no milestone builds a recurrence scheduler, so stored rules never generate transactions yet.
- **Temporary nav Drawer** on the Today screen links History/Categories/Recurring/Settings. A proper bottom-nav/`StatefulShellRoute` is deferred until History (B5) completes the four primary sections, to avoid restructuring routing twice.

**Why:** `upsert`-for-update keeps the sync contract a simple last-writer-wins upsert; reserving `delete` strictly for soft-deletes maps cleanly to the server tombstone path. The Drawer unblocks B4's on-device "full CRUD flow" done-condition without committing to a navigation structure mid-stream.

**Alternatives considered:** `delete` op for pause (wrong — the rule still exists); a full bottom-nav shell now (premature — re-work once History lands); a real cron parser for `nextRunAt` (out of scope — no scheduler consumes it in v1).

---

## 2026-06-23 — B5 trimmed to local aggregation; online /summary deferred

**Context:** B5's History screen was specced to read from `/summary` online with a local-drift fallback. In offline-only mode (sync deferred, B7) the server holds no data until push exists, so the online path can return nothing useful and its network-fallback branch can't be exercised against real data. Same situation as the B2 trim.

**Decision:** Build History with **local drift aggregation only**:
- `rangeForPeriod(day|week|month)` → UTC ms windows (week starts Monday);
- `aggregateSpendByCategory` (pure) — **expense**-only totals per category, joined + sorted desc;
- `transactionsInRangeProvider` — `StreamProvider.family` keyed by a `(int,int)` range record (records give value-equality keys), reusing the existing `watchByOccurredRange` DAO query;
- `HistoryScreen` (period toggle + custom date-range picker, `fl_chart` bar chart, transaction list, empty state);
- `SpendBarChart` (`fl_chart`).

Deferred to B7: `SummaryResponse` model, `Endpoints.summary` + client call, and the online→local fallback. `freezed`/`json_serializable` still not added.

Two scoping notes:
- **History is expense-focused.** "Spend by category" aggregates expenses only; income/investment are excluded from the chart but still appear in the transaction list (signed `+`/`-`).
- **`fl_chart` Y values use `double`** (cents/100) — this is render-only pixel height, not money math; the no-`double`-for-amounts rule is about storage/transfer/compare and is unaffected.

**Why:** Smallest shippable unit, consistent with the offline-only direction and the B2 precedent — no dead network code, no test asserting an unbuilt server's behavior. Local aggregation is the real path users hit in v1.

**Routing:** All six primary routes now resolve to real screens; the `_Placeholder` widget was removed. The temporary Today `Drawer` remains the nav surface; a bottom-nav/`StatefulShellRoute` can now replace it as a focused follow-up (all four sections exist).

**Alternatives considered:** Build the online path now (dead code; fallback untestable without server data); aggregate all kinds into the chart (muddies "spend"); a family key class instead of a record (records already give value equality — simpler).

---

## 2026-06-23 — B6: CSV export design (pure builder + injected IO/share)

**Context:** B6 exports transactions to CSV and hands off via the OS share sheet. The CSV content must be unit-testable without `path_provider`/`share_plus` platform channels.

**Decision:**
- **Split pure generation from IO.** `ExportService.buildCsv({fromMs, toMs})` queries drift and returns a `String` (no file IO) — this is what the gate tests assert against. `exportToCsv({cacheDir, …})` writes the timestamped file. The service takes only the db.
- **Inject platform edges as providers:** `cacheDirProvider` (`FutureProvider<Directory>` over `getApplicationCacheDirectory`) and `fileSharerProvider` (`FileSharer` interface; `PlatformFileSharer` uses `SharePlus.instance.share(ShareParams(files:[XFile]))`). Tests override both with a temp dir + a recording fake — no platform channel.
- **CSV format:** fixed columns `date,amount,kind,category,note,source,recurring_rule_id`. `date` = **local** `YYYY-MM-DD` of `occurred_at`; `amount` = unsigned decimal string via `formatCents` (sign is implied by the separate `kind` column); RFC-4180 escaping (quote fields with `, " CR LF`, double embedded quotes). Rows oldest-first.
- **Category names resolved from ALL categories (incl. archived)** via new `CategoriesDao.allCategories()` — a transaction may reference a since-archived category. New `TransactionsDao.activeTransactions()` / `transactionsInRange()` Futures back the export (oldest-first).
- **Entry points:** History AppBar icon + a Settings row, both → `/export`.

**Why:** The pure-builder split makes every gate assertion (columns, amount formatting, soft-delete exclusion, category resolution, range filter, escaping) a fast string test. Injected IO/share keeps the screen testable.

**Test note:** the Export screen test wraps the tap in `tester.runAsync` — `File.writeAsString` is real filesystem IO that the fake test clock does not advance.

**Alternatives considered:** `ExportService` calling `path_provider`/`share_plus` directly (untestable without platform); a CSV package dependency (the format is trivial — a hand-rolled RFC-4180 escaper avoids a dep); UTC ISO timestamp for `date` (the column models a calendar day; local `YYYY-MM-DD` matches History and user expectation).

---

## 2026-07-13 — Default categories: flag-guarded idempotent seeding, not a migration

**Context:** First-run UX had zero categories, dead-ending the Add-transaction screen. A fixed starter set (income + expense) is needed, but devices already running the shipped v1 schema have an existing local DB — `onCreate` never fires for them, so seeding there is a no-op on upgrade.

**Decision:** `CategorySeeder.seedDefaults()` (`lib/db/seed_categories.dart`) runs on every app start via `seedDefaultCategoriesProvider`, guarded by a `sync_meta` key `default_categories_seeded`. On first run it inserts the 17 defaults (6 income, 11 expense) through the existing `CategoryWriter.add()` path — one drift row + one outbox row per category, same as any user-created category — skipping any name that already exists (case-insensitive, trimmed, checked against `CategoriesDao.allCategories()` including archived rows). The flag is set once all inserts complete; later runs short-circuit immediately.

**Why:** Routing through `CategoryWriter` keeps the outbox contract intact (every mutation enqueues a sync row) without a special-cased "seed op". A `sync_meta` flag is testable against an in-memory DB and runs identically whether the device is fresh or already has hand-made categories. Bumping `schemaVersion` for a data-only change would abuse `MigrationStrategy` for something that isn't a schema change, and running writer calls mid-migration (before the DB finishes opening) is fragile.

**Alternatives considered:** `onCreate`-only seeding (misses every device with an existing v1 DB — the primary case here); `MigrationStrategy.onUpgrade` bump to schemaVersion 2 with no schema change (wrong tool, and re-entrant DB access during migration is awkward); seed unconditionally on every launch with `INSERT OR IGNORE` (would fight the outbox contract — no clean way to conditionally-not-enqueue without the same existence check anyway).

---

## 2026-07-13 — Today window rolls over via a 1-minute local-day tick provider

**Context:** `todayTransactionsProvider` computed `todayUtcBounds()` once, at provider creation, and never recomputed it. If the app stayed open across local midnight, the window stayed pinned to the previous day — the provider itself is `keepAlive`-free but Riverpod only rebuilds a provider when one of its dependencies changes, and it had no dependency that changed at midnight.

**Decision:** Added `localDayTickProvider`, a `StreamProvider<DateTime>` that yields the current local calendar day (time truncated to midnight) immediately, then re-emits (only on change, via `.distinct()`) every minute via `Stream.periodic`. `todayTransactionsProvider` now watches it and recomputes `todayUtcBounds()` from the emitted day, so its underlying drift stream re-subscribes to a fresh window whenever the day advances.

**Why:** A 1-minute tick bounds the worst-case staleness to ≤1 minute after midnight without needing a `WidgetsBindingObserver` for app-resume — simpler to test (override the provider with a controllable stream) and sufficient given the local Today window is a glanceable figure, not a hard real-time requirement. A lifecycle-observer-driven immediate refresh on resume can be layered on later if 1 minute proves too coarse.

**Alternatives considered:** `WidgetsBindingObserver` firing on `AppLifecycleState.resumed` only (misses the case where the app is left open and foregrounded straight through midnight — the exact scenario reported); recomputing bounds inside the DAO query itself via SQL `date('now')` (moves day-boundary logic out of Dart, but still needs *something* to trigger a rebuild — doesn't solve the "provider never rebuilds" root cause); a full ticking `Timer` provider firing every second (unnecessary precision for a calendar-day boundary).

---

## 2026-07-13 — Home screen: Day/Week/Month summary replaces "net flow today"; split from History

**Context:** The user reported income dated the 1st of the month showing as 0 on the home screen — by design, "Today" only ever summed the current local day. Salary/interest/maturities land on arbitrary days, so a same-day-only view under-represents the user's actual financial position most days. The user asked for "a daily, weekly and monthly view so that user can track and check their spend at a glance."

**Decision:** `today_screen.dart`/`TodayScreen` is replaced by `home_screen.dart`/`HomeScreen`: a `SegmentedButton<HistoryPeriod>` (Day/Week/Month, reusing `HistoryPeriod`/`rangeForPeriod` from `providers/summary.dart`) drives Income/Expense/Net figures (via new `summarizeTransactions`/`PeriodSummary`) plus the existing quick-add category-chip grid, scoped to the selected period instead of always "today". Home and History intentionally share `rangeForPeriod` + `transactionsInRangeProvider`: **Home** = at-a-glance current-period totals (no chart, no custom range, no list); **History** = analysis (per-category bar chart, arbitrary custom date range, full transaction list, export entry). This is deliberate provider reuse, not screen duplication — the split is by *use case* (glance vs. analyze), not by data source. `HistoryScreen`'s private `_periodLabel` was hoisted to a shared `periodLabel` in `summary.dart` since both screens need it.

**Why:** Reusing `rangeForPeriod`/`transactionsInRangeProvider` avoids a second aggregation code path; `summarizeTransactions` mirrors the existing `netFlowCents` semantics (investment excluded from income/expense/net) so the two don't drift apart. Keeping History chart/list/export separate from Home avoids cluttering the at-a-glance screen while still giving power-user detail one tap away.

**Alternatives considered:** Keep "Today" and add a separate always-visible month total (two disjoint number displays — more UI for the same information, and doesn't give the user an at-a-glance week view they also asked for); merge Home and History into one screen (conflates the "glance" and "analyze" use cases and would force the chart/list to render on every app open); recompute a fresh aggregation pipeline for Home instead of reusing History's providers (duplicate logic with no behavioral upside).

---

## 2026-07-13 — Bottom navigation shell (StatefulShellRoute) replaces the temporary Drawer

**Context:** The B4/B5 ADRs both flagged the hamburger `Drawer` on the Today/Home screen as temporary, deferring a real navigation surface until History existed and the primary sections stabilized. All four sections have shipped since B5; this closes that deferral.

**Decision:** `router.dart` now roots a `StatefulShellRoute.indexedStack` with five branches — `/home`, `/history`, `/categories`, `/recurring`, `/settings` — rendered inside a new `AppShell` widget (`lib/widgets/app_shell.dart`) with a Material 3 `NavigationBar` (exactly the 5-destination max). `HomeScreen` drops its `_NavDrawer` and AppBar settings gear (Settings is now a tab). The "add"/"export" screens (`/add`, `/categories/add`, `/recurring/add`, `/export`) are declared as sibling root-level `GoRoute`s with `parentNavigatorKey` pointing at a dedicated root `GlobalKey<NavigatorState>`, so they push over the shell (covering the nav bar) instead of being nested inside a branch's own navigator.

**Side effect found and fixed:** `StatefulShellRoute.indexedStack` keeps every branch's widget tree mounted simultaneously (to preserve scroll position/state per tab) rather than tearing down inactive tabs. `HomeScreen`, `CategoriesScreen`, and `RecurringScreen` each had a `FloatingActionButton` using the implicit default hero tag; with all three mounted at once, any push/pop triggers "multiple heroes share the same tag" once more than one is live. Fixed by giving each FAB an explicit unique `heroTag` (`'home-fab'`, `'categories-fab'`, `'recurring-fab'`). This is a real bug independent of the test suite — it would have crashed navigation on-device the same way.

**Why:** `IndexedStack`-based branches are the standard go_router pattern for preserving per-tab state (matches Material's own bottom-nav guidance); a `StatefulNavigationShell` is simpler than hand-rolling a `Scaffold` + manual route-to-index mapping. Routing "add" screens through a `parentNavigatorKey` avoids duplicating them once per branch and matches how they behaved before (full-screen push, not part of any tab's back stack).

**Alternatives considered:** Rebuilding the shell/screens as a `PageView` or a manual `Scaffold` with `IndexedStack` wired to `GoRouterState` (more code for the same behavior go_router already provides); giving branches their own always-fresh screens (`StatefulShellRoute.indexedStack` is deliberately the "keep state" variant — no simpler non-preserving alternative exists in go_router without losing tab scroll/selection state); leaving FABs with implicit hero tags and disabling hero animations app-wide (loses a minor but free polish detail for an unrelated reason).

---

## 2026-07-13 — Category picker filtered by transaction kind

**Context:** The Add-transaction category dropdown listed every active category regardless of the selected Expense/Income/Investment kind — a user could pick "Salary" (an income category) while the segmented button was on Expense. With 17 seeded categories across all three kinds (M1), this made the picker noisy and error-prone; the user flagged it directly ("grocery will always be an expense, salary will always be income").

**Decision:** `AddTxnScreen` filters `activeCategoriesProvider`'s list to `c.kind == _kind` before building dropdown items. Changing the kind segmented button resets the category selection (the old pick may no longer be valid) and bumps the existing `_categoryFieldGeneration` key so the dropdown rebuilds cleanly. If a quick-add chip passes `initialCategoryId` for, say, an Income category, the kind segmented button now aligns itself to that category's own kind on first build (`_kindAlignedToInitialCategory`) instead of always defaulting to Expense. `CategoryForm.onSaved` now reports back `(id, kind)` instead of just `id`, so creating a new category via the inline sheet can align `_kind` to whatever kind was actually chosen in the sheet (avoiding a race against the categories stream re-emitting).

**Why:** Filtering at the picker is the smallest fix that directly prevents the bad state (a transaction with a kind-mismatched category) rather than just improving display; a category's kind is intrinsic to what it *means* (Salary is always income), so cross-kind selection was never a valid choice to begin with.

**Alternatives considered:** Keep the dropdown unfiltered but warn if kind/category mismatch on save (weaker — still allows entering the bad state, just nags after the fact); only filter visually (grey out non-matching items) while still allowing selection (unnecessary complexity — there's no legitimate reason to pick a mismatched category); infer `_kind` from category kind whenever the dropdown selection changes instead of filtering (inverts the more natural direction — kind is the primary axis the user picks first, category is scoped by it).

---

## 2026-07-13 — Categories screen grouped by kind

**Context:** With the picker now filtered per-kind (previous ADR), the Categories screen itself still listed all 17+ categories as one flat list with a small subtitle naming the kind — easy to miss, and not visually "segregated" the way the user asked for.

**Decision:** `CategoriesScreen` groups categories by `TransactionKind` into three sections (Income, Expense, Investment, in that fixed order) with a header per non-empty group; a kind with zero categories shows no header at all (no empty "Investment" section on a fresh install, since no defaults are seeded for that kind). The per-row `kindLabel` subtitle was removed since the section header now carries that information.

**Why:** Section headers make the kind grouping the primary visual structure instead of a secondary label, directly answering "grocery will always be an expense, salary will always be income" — the categories screen should look like three lists, not one.

**Alternatives considered:** Keep the flat list and just re-sort by kind (still reads as one list, no visual separation); use three separate tabs/screens for each kind (over-engineered for a list that's rarely more than a couple dozen rows); collapsible sections (adds interaction cost for no benefit — all three groups are small enough to always show expanded).

---

## 2026-07-13 — Home: month-only ledger, no Day/Week toggle

**Context:** The M4 Home redesign (Day/Week/Month toggle, default Day) still under-represented income/expenses dated earlier in the month by default — the user has to remember to switch to Month every time. The user explicitly asked for "all the transactions recorded by date since the start of month, [resetting] next month," i.e. a running ledger, not another aggregate-only toggle.

**Decision:** `HomeScreen` drops the `HistoryPeriod` toggle entirely and is now hard-coded to `rangeForPeriod(HistoryPeriod.month, day)` (still driven by `localDayTickProvider`, so it rolls over automatically at the month boundary — no separate reset logic needed). Below the Income/Expense/Net summary and quick-add chips, a chronological transaction list groups rows by local calendar date (newest date first, matching the existing newest-first DAO order), giving the "ledger since the start of the month" the user asked for. `HistoryScreen`'s own Day/Week/Month toggle + custom range + chart + export stays untouched — that's still the deliberate "analyze" surface (see the Home/History-split ADR above); Home is now unconditionally "this month, itemized."

**Why:** Removing the toggle removes the exact failure mode that caused the original bug report (defaulting to a narrower window that hides real transactions); a single month-scoped view matches how most people actually reason about a budget ("this month so far") without adding a control surface for something that should just always be true.

**Alternatives considered:** Keep the toggle but change the default to Month (still lets the Day view hide data if the user switches back, and the user asked for the daily view itself to behave this way, not just a different default); add a separate "This month" card alongside a still-present Day toggle (redundant UI for the same figures); infinite/paginated ledger across all history instead of scoping to the current month (users explicitly want the "resets each month" behavior, not an ever-growing list).

---

## 2026-07-13 — Transactions record clock time, not just a fixed noon

**Context:** `occurredAt` was always epoch ms with full precision in the schema (no migration needed), but the Add-transaction UI unconditionally pinned it to local noon on the chosen date, discarding any actual time-of-day. The user asked for transactions to record the time, not just the date.

**Decision:** Added `lib/util/datetime.dart` — pure, dependency-free helpers `occurredAtMs(DateTime date, {required int hour, required int minute})` and `formatTimeOfDay(int occurredAtMs)` (zero-padded local 24-hour `HH:mm`), unit-tested directly (no widget harness needed). `AddTxnScreen` gains a `TimeOfDay _time` (default `TimeOfDay.now()`) and a `showTimePicker` button next to the date button; `_occurredAtMs()` now combines the chosen date + time via `occurredAtMs()`. Both `HomeScreen`'s ledger rows and `HistoryScreen`'s transaction list subtitle now show `formatTimeOfDay(t.occurredAt)` alongside the date.

**Why:** The schema already supported this — it was a UI-layer gap, not a data model gap, so no migration was needed. Keeping the combining/formatting logic in a pure util (rather than inline in the widget) makes it unit-testable without driving Flutter's `TimePicker` dialog, which is fragile to widget-test (12/24-hour format and AM/PM toggle are locale-dependent) — consistent with this codebase's existing convention of never widget-testing `showDatePicker` either.

**Alternatives considered:** Widget-test the actual `TimePicker` dialog interaction (fragile, locale-dependent, and this codebase already accepts the same gap for `showDatePicker`); store `TimeOfDay` as a separate column (redundant — `occurredAt` already carries full date+time precision as epoch ms); leave CSV export's `date` column as-is without adding a time column (out of scope for this fix — the export decision already documents `date` as a calendar-day field, and the user didn't ask for the CSV format to change).

---

## 2026-07-13 — Edit transactions; make-recurring is a field on Add/Edit, not a separate flow

**Context:** There was no way to edit a saved transaction — any mistake required deleting and recreating it (and even deletion wasn't exposed in the UI). Separately, "make this transaction recurring" only existed as its own screen (Recurring tab → Add), duplicating the same amount/category/kind/note fields the user had just entered on Add-transaction, purely to also register a template.

**Decision:**
- `TransactionsDao.updateTransaction` / `RecurringDao.updateRule` — new partial-update DAO methods that intentionally leave `createdAt` (and, for rules, `active`) untouched, bumping only `updatedAt`, mirroring the existing `archiveCategory`/`setActive` convention rather than reusing `upsertTransaction`/`upsertRule` (which are full-row inserts and would silently reset `createdAt` on every edit).
- `TransactionWriter.update()` / `RecurringWriter.update()` — writer-layer counterparts, each writing the drift update + an outbox `upsert` in one transaction (edits are still upserts on the sync contract, per the B4 outbox-op ADR).
- `AddTxnScreen` now serves both create and edit: an optional `editTransactionId` constructor param triggers an async load (`transactionById` + `ruleById` if linked) that prefills every field, including a new "Make this recurring" `SwitchListTile` + the same `RecurrencePreset` picker used on the standalone Add-recurring screen (hoisted `presetLabel`/added `presetForCron` to `util/cron.dart` so both screens share it).
- Recurring-link semantics, matching the three decisions confirmed with the user: toggling recurring OFF only clears the transaction's `recurringRuleId` (the rule itself is never touched/deleted); toggling ON with no prior link always creates a **new** rule (no fuzzy matching against existing rules); toggling ON while already linked **updates the existing rule in place** (category/amount/kind/note/cron kept in sync with the transaction's current field values) rather than creating a duplicate.
- `TransactionWriter.add()` gained an optional `recurringRuleId` parameter so a brand-new transaction can be linked to a brand-new rule in the same save.

**Why:** Keeping edit semantics on the *transaction's own writer methods* (rather than routing edits through `add()`/`upsertRule` with a reused id) avoids accidentally resetting `createdAt`/`active`, which are meaningful for LWW sync ordering and pause state respectively. Surfacing "make recurring" as a field on Add/Edit (rather than requiring a trip to the Recurring tab) removes duplicate data entry for the common case of "this is rent, and it repeats" without removing the standalone Recurring tab, which still owns rule-only management (view all rules, pause/resume independent of any single transaction).

**Alternatives considered:** Reuse `add()`/`recurringWriterProvider.add()` with an explicit `id` via `insertOnConflictUpdate` for edits (simpler code, but overwrites `createdAt` on every edit — breaks LWW semantics); auto-delete/archive the linked rule when recurring is toggled off (destructive for a template the user might still want to keep active for other purposes — rejected per the confirmed unlink-only behavior); search for a matching existing rule before creating a new one when toggling recurring ON (adds matching/merge ambiguity the user explicitly didn't want — confirmed "always create new").

---

## 2026-07-14 — App icon via `flutter_launcher_icons`

**Context:** The user supplied a custom icon (gold/black wallet + ₹ badge, `spendarr icon.png`, 1024×1024) to replace Flutter's default launcher icon.

**Decision:** Copied the source image to `android/app/assets/icon.png` and added `flutter_launcher_icons: ^0.14.0` as a dev dependency with a minimal config (`image_path: "assets/icon.png"`, `android: true`, `ios: false` — matches the project's Android-only scope). Ran `dart run flutter_launcher_icons` to regenerate all five `mipmap-*/ic_launcher.png` densities (48–192px) from the source image. No adaptive-icon foreground/background split was configured — the supplied artwork already has its own background baked in, so the flat legacy icon is used as-is across API levels.

**Why:** `flutter_launcher_icons` is the standard tool for this (also used by the sibling `heerr` project — see its `pubspec.yaml`), regenerates every density correctly from one source image, and keeps the source `assets/icon.png` in the repo so the icon can be regenerated again if it changes.

**Alternatives considered:** Manually resizing and placing PNGs into each `mipmap-*` folder (heerr's own convention, but must be done by hand per density — more even to get wrong than delegating to the package); splitting into an adaptive icon (foreground+background) — skipped since the source art isn't a transparent foreground-only asset and the user didn't ask for a mask-safe adaptive icon.

---

## 2026-07-14 — Home screen redesign: black+gold, month ring, journal timeline (M1–M8)

**Context:** User supplied a mockup (`spendarr home.png`) for a full visual overhaul of Home: black+gold AMOLED theme, a hero circular budget-progress ring, a journal-style timeline with Day/Week/Month zoom, a month switcher, a facts-only insight card, and a FAB opening a kind-picker sheet. Landed as 8 sequential milestones (`PLAN.md`), each with its own commit and gate. This entry consolidates the decisions that don't already have their own dated ADR above.

**Decisions:**
- **Theme (`lib/theme.dart`)** — replaced `ColorScheme.fromSeed(0xFF7C4DFF)` (violet) with an explicit `ColorScheme.dark`: primary `kGold 0xFFD4AF37`, primary container `kGoldMuted 0xFF8A6A19`, surface `kSurfaceBlack 0xFF121212`, scaffold `kBackgroundBlack 0xFF000000`, plus `kIncomeGreen`/`kExpenseRed`/`kTextSecondary` semantic constants and component themes (NavigationBar, FAB, SegmentedButton, Card).
- **Display currency formatting (`lib/util/money.dart`)** — new `formatRupees(cents, {signed})` (Indian digit grouping, paise dropped when whole, true minus sign U+2212). `formatCents` deliberately untouched — it's the round-trip format for the Add/Edit amount `TextField` and the CSV export contract; the two must never merge.
- **Monthly budget & display name (`lib/providers/profile.dart`)** — stored as `sync_meta` key-value pairs (`display_name`, `monthly_budget_cents`), the same local-only mechanism already used for `default_categories_seeded`. Deliberately **not** synced (no outbox entry) — these are device-local preferences, not shared financial data. `flutter_secure_storage` was rejected (reserved for secrets per `android/CLAUDE.md`); a new `shared_preferences` dependency was rejected as duplicate capability.
- **Month ring semantics (`lib/providers/summary.dart` `ringProgress`, `lib/widgets/month_ring.dart`)** — ring = expense spend vs budget (not net flow), because the mockup's "left to spend" concept is inherently about controllable outflow. Current month with a budget set shows "₹X left to spend" (or "₹X over budget", ring clamped to 100%) plus a "Day N/M" footer; a **past** month shows "₹X spent" (no "left to spend" — that phrase presupposes days remaining, which a closed month doesn't have) with no Day/M footer; no budget set shows "₹X spent" + "Set a budget". Painted with a `CustomPainter`, not `fl_chart` — avoids fl_chart's implicit animation controllers, which fight the project's no-`pumpAndSettle` widget-test convention (animating `CircularProgressIndicator`s already require explicit `pump(Duration)` calls; a second animated widget would compound it).
- **Recurring summary chip = projected, not actual (`lib/widgets/summary_chips.dart`, `lib/util/cron.dart` `occurrencesInMonth`)** — v1 stores recurring rules but has no scheduler that executes them (`util/cron.dart` header comment, pre-existing), so `source == recurring` transactions never exist and an "actual spent" figure for the Recurring chip would always read ₹0. Instead it projects `Σ occurrencesInMonth(rule.cron, month) × rule.amount` over active (non-paused, non-deleted) rules for the displayed month.
- **Month-zoom timeline stays a date-grouped list, not a calendar grid (`lib/widgets/home_timeline.dart`)** — the mockup's calendar-grid concept needs a heat-map colour scale, day-cell tap targets, and empty-cell layout for a zoom level that (per the mockup's own emphasis) is the least-used of the three. The existing date-grouped ledger already has full tap-to-edit test coverage; reusing it for Month kept that coverage intact. Flagged as a documented follow-up in CONTEXT.md, not implemented.
- **Day/Week timeline zoom computed client-side from the already-loaded month list** — no additional DB queries per zoom change. Trade-off: a Week row overlapping the previous/next month only reflects the days that fall inside the currently-displayed month (documented limitation, `home_timeline.dart` doc comment).
- **Insight card is facts-only** — `lib/providers/insights.dart` `upcomingRenewal()` surfaces only a deterministic "soonest active rule firing within 7 days" fact (label from the rule's note, or its category name). No spend-pattern analysis, no "you spent X% more" style content — that's explicitly out of scope per `CLAUDE.md` §3 ("Do not implement or design spending-pattern flagging").
- **FAB → kind-picker bottom sheet, no Transfer** — `AddTxnScreen` gained an `initialKind` param (new `?kind=` query param on `/add`, parsed in `router.dart`), applied only when `initialCategoryId` is unset and not in edit mode (both of those already determine kind more specifically). "Transfer" was excluded — it isn't a `TransactionKind` in the data model and adding it was out of scope for this redesign.

**Why:** Each individual milestone's test/implementation pairing is in `CHANGELOG.md` (2026-07-14 entries, M1–M8); this ADR exists so the *reasoning* behind the cross-cutting choices (ring semantics, projection-vs-actual, list-vs-grid, sync boundary for local prefs) is discoverable in one place rather than re-derived from code.

**Alternatives considered:** Net-flow-based ring instead of expense-vs-budget (rejected — doesn't match "left to spend" framing, and income timing within a month is unpredictable, which would make the ring jump around non-intuitively); `fl_chart`'s `PieChart` for the ring (rejected — animation timer conflicts with test conventions, and its API fights round-stroke-cap + center-content composition); a calendar-grid Month view (deferred, not rejected outright — noted as a real v2 candidate once a heat-map design exists); storing the budget as a drift table row instead of `sync_meta` (rejected — one scalar value doesn't warrant a new table + DAO + migration).

---

## 2026-07-14 — Release-signing config + GitHub Actions APK publish workflow

**Context:** No mechanism existed to produce a distributable APK — only local debug sideloads via `flutter install`. The sibling `heerr` project already has a working tag-triggered release pipeline (`android-publish.yml`) that builds a signed APK and attaches it to a GitHub Release.

**Decision:** Mirrored heerr's pipeline as closely as spendarr's simpler needs allow: `.github/workflows/android-publish.yml` triggers on `v*` tag pushes, decodes a base64 keystore secret, writes `key.properties` from three password/alias secrets, and runs `flutter build apk --release` with the tag baked into `--build-name`. `android/app/android/app/build.gradle.kts` gained a real `release` signingConfig reading `key.properties`, falling back to the debug key when that file is absent (so a fresh clone with no keystore still compiles — same fallback heerr uses). No AAB build, no `dev_defaults`-style CI seeding step, and no R8/minify config were added — spendarr doesn't need a Play Console upload artifact yet, has no compile-time secrets to seed (backend URL/token are entered at runtime via Settings), and has no WorkManager-style reflection issue for R8 to strip.

The keystore itself was **not** generated by the agent — an auto-mode safety classifier correctly blocked both generating a signing password and echoing one into the transcript, since a leaked or lost signing key is either a security exposure or (if the password is genuinely lost) permanently blocks future updates to any real install. The user ran `keytool -genkey` themselves per the new `android/app/README.md` "Building a release APK" section and set the four GitHub secrets by hand. (One abandoned agent attempt did write a keystore file with an unrecoverable auto-generated password before its final step was blocked — caught and deleted before the user's own keytool run, documented here so the incident isn't silently lost.)

**Why:** Consistency with heerr's proven pattern lowers the maintenance cost of remembering two different release processes across the two apps in this repo. Debug-key fallback in Gradle (rather than failing the build when `key.properties` is missing) matches Flutter's own project-template behavior and heerr's precedent, keeping `flutter build apk --release` usable for local testing even before a keystore exists.

**Alternatives considered:** Building on every push to `main` instead of on tags (rejected — would spam GitHub Releases and doesn't map to a meaningful "shipped version" boundary); also producing a `.aab` for Play Console (deferred — no Play Store listing exists yet, matches the user's request scope of "generate the apk file"); having the agent generate the keystore end-to-end (rejected by the safety classifier, and correctly so — signing credentials must be generated and held by the human who owns the app's update chain, not materialized by an agent).

---

## 2026-07-14 — Metallic gradient palette + adaptive launcher icon

**Context:** After the M1–M8 Home redesign landed, side-by-side screenshot comparison against the mockup (`spendarr home.png`) showed the flat `0xFFD4AF37` gold reading as bright yellow, the ring/FAB/pill lacking the mockup's metallic depth, and the launcher icon rendering with a thick golden ring. The user supplied a detailed gradient spec ("premium warm metallic gold", 3–5 stop gradients on every gold element, champagne base).

**Decision:**
- Base gold moved to champagne `0xFFC89B3C`; every prominent gold element now uses a multi-stop gradient (`kPremiumGoldGradient` 5-stop for FAB/pill/amount text, 6-stop `kRingProgressColors` for the ring, `kGoldIconGradient` for icons via a shared `Gilded` ShaderMask widget). Flat `colorScheme.primary` remains for low-emphasis Material components (form buttons, switches) where a gradient isn't expressible without custom widgets.
- Ring gradient spans the **full circle** with the arc revealing the first `progress` portion — two rejected alternatives (gradient compressed into the arc span; highlight at the arc tip) both diverged visibly from the mockup, which is brightest at the top/start. Arc uses butt caps + hand-drawn endpoint circles because a round `StrokeCap` on a sweep-gradient samples wrapped angles outside the sweep, drawing a wrong-colour blob at the seam. Tip-cap colour is interpolated from the gradient at the current progress.
- Cards are `0xFF111111` with 1px `0xFF242424` borders; positives/negatives muted (`0xFF58C77A` / `0xFFD46A6A`); the narrower `kFabGradient`/`kActiveTabGradient` from the spec exist but the FAB and selected pill use the 5-stop premium gradient — the 2–3-stop versions render nearly flat at those sizes.
- Launcher icon converted to an **adaptive icon** (black background layer + foreground padded onto a 1908px black canvas for the ~66% safe zone), reversing the earlier no-adaptive-icon ADR: the Pixel launcher letterboxes legacy icons inside its circular mask and fills the ring with a colour sampled from the artwork — the source of the golden border. Verified after `pm clear` on the emulator launcher (its persisted icon cache kept showing the old ring through reinstalls).

**Why:** The mockup — not the hex values alone — is the acceptance bar; each change was screenshot-verified on the emulator against it. A shared `Gilded` widget keeps future gold elements consistent instead of scattering per-widget ShaderMasks.

**Alternatives considered:** Keeping flat fills with brighter hexes (rejected — reads as yellow paint, not metal); `fl_chart` for the gradient ring (rejected earlier, still holds); per-launcher icon tweaks instead of an adaptive icon (rejected — the ring is standard launcher behaviour for legacy icons, adaptive is the platform-correct fix).

---

## 2026-07-16 — Add/Edit Transaction screen redesign: card-based layout, sheet pickers over dropdown/segmented widgets

**Context:** The user supplied a mockup (`Add transaction.png`) for the Add/Edit-transaction screen matching the black+gold aesthetic already applied to Home. The screen was still stock Material 3 — outlined `TextField`s, a `SegmentedButton`, a `DropdownButtonFormField` for category, `OutlinedButton` date/time, a `SwitchListTile`, a plain `FilledButton` — none of which can express the mockup's bordered dark cards, gold-gradient pill selector, or gradient Save button without heavy theme overrides.

**Decision:**
- **Every field is now a bordered `_FieldCard`** (`kSurfaceBlack`, `kCardBorder`, 16px radius) under a caps `_SectionLabel`, matching the mockup's AMOUNT/CATEGORY/DATE & TIME/NOTE/MAKE THIS RECURRING sections. Amount stays an inline-editable `TextField` (not a tap-to-edit read-only display) — the pencil button only calls `FocusNode.requestFocus()`; this was an explicit user choice (AskUserQuestion) to minimize taps.
- **Category picker is a `showModalBottomSheet` listing kind-filtered categories, not a `DropdownButtonFormField`** — also an explicit user choice. This removes the `_categoryFieldGeneration` `ValueKey` hack that existed solely to force `DropdownButtonFormField` to rebuild after its "New category" sentinel was tapped; a freshly-built sheet has no equivalent stale-selection problem. The sheet's last row is always "＋ New category", which pops the sheet and calls the existing `_createCategory()` (unchanged — still opens `CategoryForm` in its own sheet and aligns `_kind` to whatever kind was saved).
- **New `KindPillSelector` widget** (`lib/widgets/kind_pill_selector.dart`) replaces `SegmentedButton<TransactionKind>` — generalizes `home_timeline.dart`'s `ZoomPillSelector` construction (single outer border, `AnimatedContainer` gradient fill on the selected segment) with per-segment icons and `Expanded` equal-width segments, since `SegmentedButton`'s Material styling can't produce the mockup's continuous gold-gradient pill with icon+label per segment.
- **Recurring toggle only shows its frequency card while on** — when off, the row shows a plain "Repeat this transaction automatically" placeholder next to the `Switch`; toggling on reveals the tappable frequency card (icon, preset label + subtitle, chevron) that opens its own preset-picker sheet. This avoids nesting a tappable region inside the row that also contains the `Switch` (gesture-conflict risk) by keeping them as Row siblings rather than one shared `InkWell`.
- **New 12-hour time/date display helpers** (`lib/util/datetime.dart`: `formatDayMonthYear`, `weekdayName`, `formatTime12h`) — additive, hand-rolled (no `intl` dep, consistent with the existing `monthLabel`). The existing 24-hour `formatTimeOfDay` (used by Home's ledger rows) is untouched; the mockup's 12-hour AM/PM format is specific to this screen.
- **Save button is a `FilledButton` (transparent background) wrapped in a `kPremiumGoldGradient` `Container`** — the same trick as `GoldFab`, chosen so the button stays a real `FilledButton` for existing `widgetWithText(FilledButton, ...)` test finders rather than a bespoke pressable. Label reads "Save Changes" in edit mode (was "Save" in both modes before) to match the mockup.
- All save/edit/delete/recurring-link business logic (`_save`, `_loadExisting`, `_confirmDelete`, kind-filtered category defaulting, the three confirmed recurring-link-sync rules from the earlier edit-transactions ADR) is **unchanged** — only `build()` and its private layout widgets were rewritten.

**Test-infra note:** the redesigned screen is taller than the old form (bordered cards + section labels add significant vertical space), pushing the Save button and recurring `Switch` past `ListView`'s sliver `cacheExtent` in the default ~600px test viewport — the same virtualization gotcha recorded in the M5 Home-redesign ADR. Every `add_txn_*_test.dart` file now sets a tall virtual window (`tester.view.physicalSize = Size(800, 2200)`) in its setup, mirroring the pattern already used by `home_screen_test.dart`/`add_txn_flow_test.dart`.

**Why:** The mockup is the acceptance bar (per the established pattern for every prior visual-polish round in this session); a card-based layout with sheet pickers is the only way to hit it without fighting Material's built-in dropdown/segmented-button chrome. Keeping the amount field inline-editable and the category picker a sheet were both explicit, asked-and-answered user decisions rather than agent defaults.

**Alternatives considered:** Tap-to-edit read-only amount display (rejected by the user — extra tap for the common case); full-screen category picker route (rejected by the user — heavier navigation for a short list, and the app has no other full-screen-picker precedent); reusing `SegmentedButton` with a custom `ButtonStyle` for the kind pill (rejected — `SegmentedButton` can't express one continuous gradient sliding behind the selected segment without per-segment border/divider artifacts, the same reason `ZoomPillSelector` was hand-rolled for Home); keeping the recurring frequency card always visible even when off (rejected — showing "Monthly / Every Month" while the toggle is off implies a schedule is active when it isn't).

---

## 2026-07-16 — Category icons re-themed as display-only emoji→icon mapping, not a data-model change

**Context:** Every mockup renders category glyphs as monochrome gold line-icons inside a dark circle bubble (coffee cup, briefcase, fuel pump, "N" for Netflix in `spendarr home.png`) — never native colourful emoji. The app stores and displays a free-text `emoji` string per category (`Categories.emoji`, non-nullable TEXT) and rendered it raw via `Text(category.emoji)` at ~10 call sites, reading as a jarring colourful sticker against the black+gold theme.

**Decision (both confirmed via AskUserQuestion):**
- **`emoji` stays exactly as-is** — the stored column, `CategoryForm`'s freeform-TextField + quick-emoji-grid picker, `CategoryWriter.add()`'s signature, and the outbox/sync JSON payload (`{'emoji': ...}`) are all untouched. This is a **display-only** re-theme: a new `categoryIconFor(String emoji) → IconData` lookup table (`lib/util/category_icon.dart`) maps the stored emoji to a themed Material icon at render time only.
- **Fallback is a generic icon (`Icons.label_outline`), not the raw emoji.** Any emoji outside the curated ~23-entry table — including a genuinely custom emoji a user types into the picker — renders the same neutral gold icon rather than falling back to the colourful character. This keeps every category row visually consistent (always a themed gold icon in a dark bubble) at the cost of losing the specific glyph for uncommon/custom emoji.
- **New shared `CategoryIconBubble` widget** (`lib/widgets/category_icon_bubble.dart`) is the single replacement for every prior `Text(emoji, fontSize: ...)` site — a dark `CircleAvatar` + the mapped icon gilded via the existing `Gilded` ShaderMask, matching the bubble style already established by `summary_chips.dart`'s Expenses/Investments/Recurring icons.

**Why:** Keeping `emoji` as the identity/sync field avoids a schema migration or backend-contract change for a purely cosmetic redesign — the backend (A1–A4) isn't built yet and offline-only v1 doesn't sync anything today, but the wire *shape* (`emoji` key in the outbox payload) shouldn't be redefined without a real reason to. A fixed lookup table with a neutral fallback is simpler and more predictable than trying to auto-generate or crowd-source an icon for arbitrary emoji, and avoids building a whole new icon-picker UI for what is, in v1, a purely visual polish pass.

**Alternatives considered:** Replacing emoji entirely with a curated icon-picker UI and a new `icon` column (rejected by the user — bigger change, needs a migration path for existing seeded/user categories, and changes what would be synced later for no functional gain in v1); keeping the raw emoji as the fallback for unmapped entries (rejected by the user — less visually consistent, and defeats the point of the re-theme for exactly the categories a user customized most); tinting/desaturating the emoji glyph itself via a `ColorFiltered` filter instead of a full icon swap (not pursued — colour emoji are bitmap glyphs where a shape-level gradient like `Gilded`'s `ShaderMask` wouldn't reliably preserve the mockup's clean line-icon look, and a lookup table gives exact control over which icon renders per category).

---

## 2026-07-16 — History restyle: generalize the pill selector rather than duplicate it

**Context:** History predates the black+gold redesign rounds already applied to Home and Add/Edit-transaction, and had no dedicated mockup of its own — the ask was to bring it in line with the design language already established elsewhere. History's `HistoryPeriod {day, week, month}` period toggle needed the same gold-gradient rounded-pill look as Home's `TimelineZoom {day, week, month}` zoom selector (`home_timeline.dart`'s `ZoomPillSelector`) — the two widgets would otherwise be near-identical copies differing only in their enum type.

**Decision:** Extracted a generic `PillSelector<T>` (`lib/widgets/pill_selector.dart`, `items`/`selected`/`labelFor`/`onChanged`) containing the actual pill-rendering logic. `ZoomPillSelector` becomes a thin same-named wrapper delegating to `PillSelector<TimelineZoom>`, preserving its public type (and therefore every existing `find.byType(ZoomPillSelector)` test) unchanged. History's period toggle uses `PillSelector<HistoryPeriod>` directly — no new `HistoryPillSelector` wrapper needed since History has no prior widget type for tests to depend on. Similarly, `add_txn_screen.dart`'s private `_SectionLabel`/`_FieldCard` (bordered-card + caps-header language) were promoted to public `SectionLabel`/`FieldCard` in `lib/widgets/field_card.dart` so History's bar-chart section could reuse the identical card styling instead of re-implementing it.

**Why:** The two pill selectors were already visually and structurally identical (same border/gradient/animation, differing only by enum type and label function) — generalizing avoids a second copy that would inevitably drift from the first over time, exactly the kind of duplication `kind_pill_selector.dart`'s own doc comment already flagged as a risk when it built a third bespoke pill for the kind selector. Keeping `ZoomPillSelector` as a wrapper (rather than replacing all its call sites with the generic type directly) was the lower-risk option — it avoids touching `home_timeline.dart`'s call site or `home_screen_test.dart`'s existing type-based finder for a change that isn't itself part of this task.

**Alternatives considered:** Building a second, History-specific pill selector copy (rejected — the exact duplication-drift risk this ADR exists to avoid); replacing `ZoomPillSelector`'s call sites with `PillSelector<TimelineZoom>` directly and deleting the wrapper (rejected — unnecessary churn to `home_timeline.dart` and `home_screen_test.dart` for a change outside this task's scope); leaving `SegmentedButton<HistoryPeriod>` in place and only re-theming its colours via `SegmentedButtonThemeData` (rejected — Material's `SegmentedButton` still can't express the mockup's single continuous gradient sliding behind the selected segment, the same limitation that motivated `ZoomPillSelector`/`KindPillSelector` in the first place).

---

## 2026-07-16 — Category form: replace the emoji picker with the same curated icon set, closing the display-mismatch gap

**Context:** The prior category-icon ADR deliberately kept `CategoryForm`'s emoji picker (freeform `TextField` + a 16-emoji `quickEmojis` grid) unchanged, mapping the stored emoji to a themed icon only at *display* time. In practice this meant a user could pick an emoji — including several of the form's own preset options — that had no entry in the curated ~23-emoji map, and would then see it silently replaced by the generic fallback icon (`Icons.label_outline`) everywhere else in the app. Reported directly by the user: "when i select something it automatically gets mapped to something else."

**Decision:** The picker itself now offers only `categoryIconChoices` — the curated map's own keys — rendered as the same `CategoryIconBubble` gold icons used throughout the app, not raw emoji characters. Tapping one is the entire selection mechanism; the freeform `TextField` is removed. Because every offered choice is guaranteed to have a real mapping, what the user taps is always exactly what displays elsewhere — the fallback path can now only be hit by data written before this fix (or, in principle, directly via the API once a backend exists), never through the in-app picker. The stored `emoji` string, `CategoryWriter`, and outbox payload are still untouched — this remains a display/input UI change only, not a schema change (confirmed with the user via AskUserQuestion, same constraint as the original re-theme).

**Why:** The alternative — reverting to showing the raw picked emoji everywhere — would have undone the entire black+gold re-theme for category glyphs to fix what was actually a narrower problem: the picker offering choices it couldn't faithfully render back. Constraining the picker to the same curated set closes that gap without sacrificing the visual consistency the re-theme was for.

**Alternatives considered:** Reverting category display to raw emoji everywhere (rejected by the user — throws away the mockup-matching re-theme for a narrower fix); expanding the curated map to cover arbitrary emoji instead of constraining the picker (not pursued — there's no bounded set of "arbitrary emoji," so this only shrinks the gap rather than closing it, and freeform emoji entry was the actual source of the mismatch); keeping freeform entry as an "advanced" option alongside the icon grid (rejected — reintroduces the exact same mismatch for anyone who uses it, for no clear benefit over just picking from the grid).

---

## 2026-07-16 — Settings: hide Profile/Server UI, keep the providers

**Context:** The user asked to keep only "Export CSV" visible on Settings and remove the Profile (display name/budget) and Server (backend URL/bearer token) sections "for now — we will add it back when they are functional." Server settings currently point at a backend that isn't part of this milestone's active work, and the Profile fields (display name, monthly budget) are of limited value without the sync loop that would make them meaningful across devices.

**Decision:** Removed the Profile/Server sections from `SettingsScreen`'s UI only. `profileProvider`, `settingsProvider`, `SettingsStore`, and their local-drift/secure-storage persistence are untouched in `lib/` — they're still exercised by their own provider-level unit tests and still consumed elsewhere in the app (Home's greeting reads `profileProvider`). `SettingsScreen` itself dropped from a `ConsumerStatefulWidget` (five controllers, prefill logic, save/test-connection handlers) to a stateless single-row screen, since none of that state is needed once only a static navigation row remains.

**Why:** The user's own framing ("we will add it back when they are functional") signals this is scoped as reversible UI hiding, not a decision to remove the feature — keeping the provider layer intact means restoring the UI later is a pure `SettingsScreen` edit, no data-layer archaeology needed.

**Alternatives considered:** Deleting `profileProvider`/`settingsProvider` and their tests entirely (rejected — the user explicitly said "for now," and Home's greeting already depends on `profileProvider`); hiding the sections behind a feature flag instead of removing the code paths (rejected — no feature-flag mechanism exists in this codebase, and a flag defaulting to "off" is equivalent complexity to just re-adding the UI when it's ready).

---

## 2026-07-16 — Home "Expense" stat means total outflow (expense + investment), not expense-only

**Context:** Home's month ring already computes `outflowCents = expenseCents + investmentCents` for its fill fraction and centre "left to spend" figure — investments have always counted as money leaving the pool of income for that purpose. The `_Stat` figure labelled "Expense" beside the ring, however, still showed `expenseCents` alone, so it disagreed with what the ring right next to it was visually measuring. The user flagged this directly: "the expenses on the right of the meter should be total expenses including investments."

**Decision:** `_Stat(label: 'Expense', ...)` now reads `outflowCents` (the same value already driving the ring), not `summary.expenseCents`. The `SummaryChips` "Expenses" chip below (documented as an actuals-only figure, separate from the "Investments" chip) is explicitly untouched — that chip's whole purpose is to show expense and investment as two distinct actuals side by side, which is the opposite intent from the ring's single combined-outflow figure.

**Why:** Two adjacent widgets (the ring and the "Expense" stat beside it) computing "how much went out" two different ways is confusing and was the literal bug reported. Making the stat match the ring's own math removes the discrepancy without touching the ring or the chips, which already had unambiguous, separately-documented semantics.

**Alternatives considered:** Changing the ring to expense-only instead (rejected — the ring's income-minus-outflow "left to spend" framing is the more load-bearing, already-tested semantic, and expense-only would make "left to spend" wrong whenever investments exist); adding a new fourth figure instead of changing "Expense" (rejected — not what was asked, and adds a stat the mockup never had).

---

## 2026-07-16 — Recurring screen: add a Delete action (soft-delete), not present before this redesign

**Context:** The supplied "Recurring expenses.png" mockup shows a kebab (⋮) menu next to each rule's pause/resume switch. Before this change, the app had no way to remove a recurring rule at all — `RecurringWriter` only exposed `add`/`update`/`setActive`; pausing was permanent-ish (a paused rule stays in the list forever). Implementing the mockup's kebab menu required deciding what it does.

**Decision:** The kebab menu offers a single "Delete" action, confirmed via a dialog (same shape as `AddTxnScreen`'s existing `_confirmDelete` for transactions), which soft-deletes the rule (`deletedAt` set, `activeRecurringProvider`'s stream — which already filters `deletedAt IS NULL` — stops showing it) and enqueues an `OutboxOp.delete` outbox entry. Transactions the rule already created are untouched — only the rule template itself stops firing/appearing. An "Edit" option was deliberately *not* added — there is no edit route for recurring rules yet (`AddRecurringScreen` has no `editRuleId`-style parameter, unlike `AddTxnScreen`), and building one is a separate, larger task outside "implement this screen from the reference image."

**Why:** The mockup includes the menu, so some destructive/management action was expected; soft-delete is the only such action the app already has an established pattern and DAO method for (`softDeleteRule` already existed on `RecurringDao`, just never wired to a writer). Reusing the confirm-dialog shape from `AddTxnScreen` keeps the interaction pattern consistent app-wide rather than inventing a new one.

**Alternatives considered:** Leaving the kebab menu out entirely and diverging from the mockup (rejected — the reference image was the explicit ask); making the kebab menu open the (nonexistent) edit screen instead of/in addition to delete (deferred — no edit flow exists for recurring rules, and building one is out of scope for a screen-visual-parity task); hard-deleting the row (rejected — violates the project-wide soft-delete-only rule for synced tables in `android/CLAUDE.md`).

---

## 2026-07-16 — Reset version-tag history: v0.1.0 is the actual first release

**Context:** Development so far had accumulated nine iteration tags (`v0.1.0`–`v0.1.8`), pushed to `origin` as each polish round landed, with no corresponding GitHub Releases (the `android-publish.yml` release workflow was never actually triggered with real signing secrets — the tags were pushed but no release artifacts exist). The user decided the app is ready for its first real tagged release and wants that release to be `v0.1.0`, not `v0.1.9`.

**Decision:** Deleted all nine existing tags, both locally (`git tag -d`) and on `origin` (`git push origin :refs/tags/<tag>` for each). Confirmed via `gh release list` that no GitHub Releases existed to clean up. Fixed the one stray doc reference to a future tag number (`README.md`'s "Releasing" example showed `git tag -a v0.2.0`, now `v0.1.0`) — `android/app/README.md`'s own example already said `v0.1.0`, `pubspec.yaml`'s `version:` was already `0.1.0+1`, and `android/docs/ROADMAP.md`'s B7 milestone already targets "Tagged `v0.1.0`" — none of those needed changing.

**Why:** The prior tags were development-iteration checkpoints, not releases (no GitHub Release/artifact was ever produced from them), so deleting them costs nothing and avoids a confusing `v0.1.0`-through-`v0.1.8`-then-back-to-`v0.1.0` history once the real first tag goes out. Confirmed with the user before deleting pushed tags, since removing pushed refs is a destructive, shared-state operation.

**Alternatives considered:** Keeping the old tags and starting the "real" release numbering at `v0.1.9`/`v0.2.0` instead (rejected by the user — they specifically want `v0.1.0` to be the first release, and the old tags carry no release artifacts worth preserving); leaving the old tags in place unlisted (rejected — the user explicitly asked for old tags/releases to be removed, not just superseded).

---

## 2026-07-16 — Defer fixing Android Auto Backup silently restoring app data after uninstall

**Context:** The user reported that uninstalling and reinstalling the app doesn't clear old data, and asked whether that's intentional. Investigation found it isn't the app retaining anything locally — uninstall does wipe internal storage as normal. `android/app/android/app/src/main/AndroidManifest.xml` sets no `android:allowBackup` attribute, which defaults to `true`, and `lib/db/database.dart:33` opens the drift DB via `driftDatabase(name: 'spendarr')` in the app's internal documents directory, a location Android's default Auto Backup (to the user's own Google account) includes. On reinstall, Android silently restores that backup, which is why the SQLite data reappears.

**Decision:** Not fixing this now. No manifest change (`android:allowBackup="false"` or a `dataExtractionRules`/backup-rules XML excluding the DB and secure-storage files) is being made yet.

**Why:** The user asked to record this as a decision rather than act on it — deferred, not rejected. Worth revisiting given the project's offline-only / no-data-leaves-the-device stance (`CLAUDE.md` §3 finance rules) and that this is financial data landing in the user's Google Drive backup without being surfaced anywhere in the app.

**Alternatives considered:** `android:allowBackup="false"` (simplest — disables Auto Backup entirely, including for anything else that might want it later, e.g. app preferences); a `dataExtractionRules`/`fullBackupContent` XML excluding just the drift DB and secure-storage files (more surgical, more setup). Neither implemented yet — parked for a future task.

---

## 2026-07-16 — Category icons: reverse the curated-icon-map decision, gild the user's own emoji instead

**Context:** Two prior ADRs (2026-07-16, "Category icons re-themed as display-only emoji→icon mapping" and its follow-up "Category form: replace the emoji picker with the same curated icon set") deliberately constrained category icon selection to a fixed ~23-entry emoji→`IconData` lookup table, so every category rendered a themed gold Material icon rather than a raw colourful emoji. The tradeoff, stated explicitly at the time, was that a user could no longer pick an arbitrary custom emoji — only the curated set. The user flagged this as unwanted: "we had decided that we would not do a mapping but change the emojis to the theme of the app so as to let user select any emoji." Checking the log, the actual prior decision was the opposite of that recollection — but the user now wants the "theme whatever's picked" behavior, so this is a fresh decision reversing the prior two, not a bug fix.

**Decision:** Deleted the curated `emoji → IconData` lookup entirely (`lib/util/category_icon.dart` and its test removed). `CategoryIconBubble` (`lib/widgets/category_icon_bubble.dart`) now renders the category's own emoji as `Text(emoji)` wrapped in the existing `Gilded` widget — `Gilded`'s `ShaderMask` with `BlendMode.srcIn` discards the emoji's native colour and repaints its alpha silhouette with the app's gold gradient, so any emoji (not just a curated set) still renders on-theme. `CategoryForm`'s icon picker (`lib/widgets/category_form.dart`) now offers a `TextField` that accepts any emoji typed via the system keyboard's emoji picker, alongside a small `_suggestedEmojis` grid of common shortcuts (tap-to-fill convenience only, not an enforced set). `recurring_screen.dart`'s rule-card icon box was updated the same way (gilded `Text(category.emoji)` instead of `Icon(categoryIconFor(...))`).

**Consequence:** The two prior ADRs' "known tradeoff" (custom emoji falls back to a generic icon) no longer applies — this entry supersedes them. Their reasoning for *why* a curated map was chosen originally (mockup shows clean monochrome line-icons; raw bitmap emoji glyphs risk looking like a "blobby" gold silhouette rather than a crisp line icon once gilded) still stands as a known visual-quality tradeoff of this new approach — accepted by the user as the cost of allowing arbitrary emoji.

**Why:** The user explicitly wants unrestricted emoji choice with on-theme rendering over a curated icon set, which this delivers without a schema/data change (the stored `emoji` column, `CategoryWriter`, and outbox payload are all untouched — still a display/input-only change, consistent with the constraint set in the prior ADRs).

**Alternatives considered:** Keeping the curated map as a fallback (gild via icon lookup when the emoji matches an entry, gild the raw emoji otherwise) — rejected as unnecessary complexity now that gilding raw emoji works uniformly for every case, curated or not; expanding the curated map to cover more emoji instead of removing it — rejected, still bounded and defeats "any emoji"; a third-party emoji-picker package for a nicer in-app picker UI — not pursued, the system keyboard's own emoji picker (available via any `TextField`) already covers this with zero new dependencies.

---

## 2026-07-17 — Stop gilding raw emoji: the "known visual-quality tradeoff" turned out unacceptable in practice

**Context:** The prior ADR accepted, as a known tradeoff, that gilding a raw emoji via `Gilded`'s `ShaderMask` (`BlendMode.srcIn`) might look "blobby" rather than a crisp line icon, since colour emoji are multi-colour bitmap glyphs and `srcIn` discards all colour information, keeping only the alpha silhouette. Once actually shipped and looked at, the user reported this directly: "you are just mapping the normal emojis to a solid gold icon" — i.e. the accepted tradeoff was worse in practice than anticipated, not a minor stylistic nit.

**Decision:** `CategoryIconBubble` and `recurring_screen.dart`'s rule-card icon box no longer wrap the emoji `Text` in `Gilded`. The dark circle/square bubble background stays on-theme; the emoji glyph itself now renders in its native colour, like any normal emoji. Confirmed with the user via `AskUserQuestion` between two options — native-colour emoji (chosen) vs. reverting to the earlier curated gold-icon map (not chosen, since the point of the prior change was letting users pick *any* emoji).

**Why:** A native-colour emoji is instantly recognisable (its whole point); a gilded solid-colour silhouette of the same emoji often isn't, especially for glyphs with a lot of internal detail (faces, multi-part icons). The theme's "everything gold" language is best applied to the *UI chrome* around user content (bubbles, borders, buttons, Material icons the app itself draws) — a user-picked emoji is closer to user *content*, which this reverts to treating as such.

**Alternatives considered:** Reverting to the curated `emoji → IconData` lookup (rejected — the whole point of the just-prior change was letting the user pick arbitrary emoji, and reverting would re-introduce that limitation); a partial/lighter tint (e.g. lower-opacity gold overlay instead of full `srcIn` replacement) — not pursued, adds complexity for a middle-ground result nobody asked for once "just show the real emoji" was on the table as the simpler, obviously-correct option.
