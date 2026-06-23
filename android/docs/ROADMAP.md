# ROADMAP.md — spendarr Android client implementation milestones

Track progress through the Android client build. Each milestone = one git commit with the test gate green where applicable. Tick the box when committed.

See `CONTEXT.md` for the what; `DECISIONLOG.md` for the why; this file is the how/when.

**Conventions:**
- TDD by default — widget tests for screens, unit tests for providers/services/DAOs. Write the failing test first.
- Out of TDD scope: `flutter create` scaffold, `pubspec.yaml`, `android/` manifest config, manual smoke. These have other verification gates noted per milestone.
- `dart run build_runner build --delete-conflicting-outputs` must be clean after every milestone touching `@freezed` / `@riverpod` / drift `@DriftDatabase` annotations.
- Commit messages: Conventional Commits with `flutter` scope (`feat(flutter): …`, `chore(flutter): …`).
- One milestone = one commit. Follow-up cleanup = separate commit under the same milestone label.
- **Halt and confirm at each milestone boundary.**

---

## Phase B — Foundation & local-only core

### [x] B1. Scaffold: flutter create + pinned deps + drift schema + DAOs

**Files:** `android/app/pubspec.yaml`, `android/app/analysis_options.yaml`, `android/app/lib/main.dart`, `android/app/lib/theme.dart`, `android/app/lib/router.dart`, `android/app/lib/db/database.dart`, `android/app/lib/db/daos/`, `android/app/test/db/dao_test.dart`

**Deliverable:**
- `flutter pub get && flutter analyze` exit 0. Default counter app replaced with bare `MaterialApp` + `ProviderScope`.
- Theme: Material 3, dark mode, `ColorScheme.fromSeed(<seed>, Brightness.dark)` — pick a seed colour distinct from heerr green. Document the choice in DECISIONLOG.
- go_router with five empty screens: `/today`, `/add`, `/history`, `/categories`, `/recurring`, `/settings`.
- drift schema mirroring server tables (`categories`, `transactions`, `recurringRules`, `outbox`, `syncMeta`). All tables carry `id TEXT PK` (UUID string), `createdAt INTEGER` (epoch ms), `updatedAt INTEGER`, `deletedAt INTEGER NULL`. `transactions.amount` stored as `INTEGER` (cents). DAOs for each table with reactive streams and basic CRUD.

**Test gate:** drift DAO unit tests — insert → stream emits; soft-delete → row has `deletedAt` set; `deletedAt IS NULL` filter works; outbox append → row visible; `syncMeta` get/set round-trip.

**Done when:** `flutter run -d <pixel>` shows the skeleton app; all DAO tests green.

**Commit:** `chore(flutter): scaffold + drift schema + DAOs`

---

### [x] B2. Freezed models + API client + settings screen

> **Trimmed for offline-only — see DECISIONLOG 2026-06-23.** Built: dio client + bearer interceptor + typed `ApiError` + `/health` + `settingsProvider` (secure storage) + Settings screen. Deferred to their consuming milestones: `SummaryResponse` (B5); sync envelopes + `CategoryModel`/`TransactionModel`/`RecurringRuleModel` (B7). `freezed`/`json_serializable` not yet added.

**Files:** `android/app/lib/models/*.dart`, `android/app/lib/api/client.dart`, `android/app/lib/api/api_error.dart`, `android/app/lib/api/endpoints.dart`, `android/app/lib/providers/settings.dart`, `android/app/lib/screens/settings_screen.dart`, `android/app/test/models/`, `android/app/test/api/client_test.dart`, `android/app/test/screens/settings_screen_test.dart`

**Deliverable:**
- Freezed + json_serializable models for every sync payload shape: `SyncPushItem`, `SyncPushAck`, `SyncPullResponse`, `SummaryResponse`, `CategoryModel`, `TransactionModel`, `RecurringRuleModel`.
- `dioClientProvider` with base URL from `settingsProvider` + bearer interceptor + response/error interceptor mapping to typed `ApiError` (401/403/422/5xx/network).
- `settingsProvider` reads/writes `backend_base_url` and `bearer_token` from `flutter_secure_storage`.
- Settings screen: URL + token fields, Save button, "Test connection" (hits `/health`).

**Test gate:** model round-trip serialization for all types; `DioAdapter` covers happy + every `ApiError` branch; widget test: Save → `settingsProvider` updated; "Test connection" success/failure snackbars.

**Done when:** `build_runner` + `analyze` + `flutter test` all green.

**Commit:** `feat(flutter): models + dio client + settings screen`

---

### [x] B3. Add transaction + Today screens (local DB only, no sync)

**Files:** `android/app/lib/screens/today_screen.dart`, `android/app/lib/screens/add_txn_screen.dart`, `android/app/lib/providers/transactions.dart`, `android/app/lib/providers/categories.dart`, `android/app/lib/widgets/category_chip.dart`, `android/app/test/screens/`, `android/app/test/providers/`

**Deliverable:**
- **Today screen** — net flow for today (income − expense) from local drift stream; emoji-chip grid of categories filtered to today's transactions; tap chip → quick-add. Shows a loading skeleton while drift emits.
- **Add transaction screen** — amount field, category picker (emoji + name list), date picker (default today), note field, kind selector (income/expense/investment), Save button. Save writes to local drift `transactions` + appends to `outbox` (op=upsert, table=transactions). No sync yet.
- Riverpod providers wrap drift reactive streams; UI rebuilds on local writes.

**Test gate:** `todayNetFlowProvider` emits correct sum after inserts/deletes; `addTransactionProvider` writes to drift + outbox in one operation (both rows present after save); widget test: fill form → tap Save → Today screen net flow updates reactively.

**Done when:** add a transaction on the device → Today screen net flow updates immediately; outbox row visible in a debug query.

**Commit:** `feat(flutter): Today screen + Add transaction (local only)`

---

### [x] B4. Categories + Recurring screens (local DB only)

**Files:** `android/app/lib/screens/categories_screen.dart`, `android/app/lib/screens/recurring_screen.dart`, `android/app/lib/screens/add_category_screen.dart`, `android/app/lib/screens/add_recurring_screen.dart`, `android/app/lib/providers/recurring.dart`, `android/app/test/screens/`, `android/app/test/providers/`

**Deliverable:**
- **Categories screen** — list of non-archived categories (emoji + name + kind chip). "Add" FAB → Add category screen (emoji picker, name, kind). Archive action (soft-delete sets `deletedAt`). All writes go to drift + outbox.
- **Recurring screen** — list of active recurring rules (emoji, name, amount, next run date). "Add" FAB → Add recurring screen (category picker, amount, kind, note, cron picker with presets: daily/weekly/monthly/custom). Pause/resume toggle. All writes to drift + outbox.

**Test gate:** add category → stream emits; archive → `deletedAt` set + outbox row; add recurring rule → visible in list; pause rule → `active = false` + outbox row; cron picker produces valid cron strings for daily/weekly/monthly presets.

**Done when:** full CRUD flow for both screens against local drift.

**Commit:** `feat(flutter): Categories + Recurring screens (local only)`

---

### [x] B5. History screen with local aggregation

> **Trimmed for offline-only — see DECISIONLOG 2026-06-23.** Built: local drift aggregation (day/week/month + custom range), `fl_chart` bar chart, transaction list, empty state. Deferred to B7: `SummaryResponse`, `/summary` call, online→local fallback.

**Files:** `android/app/lib/screens/history_screen.dart`, `android/app/lib/providers/summary.dart`, `android/app/lib/widgets/spend_bar_chart.dart`, `android/app/test/screens/history_screen_test.dart`, `android/app/test/providers/summary_test.dart`

**Deliverable:**
- **History screen** — day/week/month toggle; date range picker; bar chart (`fl_chart`) showing spend by category; categorised transaction list below. While offline or before first sync: uses local drift aggregation. When online: calls `/summary` and uses backend response (lower latency for large datasets).
- `summaryProvider(period, from, to)` — when settings has a valid URL + token: calls `/summary`; on network error: falls back to local drift aggregation. When no settings: local only.

**Test gate:** local aggregation correct for day/week/month with seeded drift rows; `summaryProvider` falls back to local when dio throws a network error; widget test: toggle switches period, chart re-renders; empty state renders when no transactions in range.

**Done when:** History screen shows correct data from local drift; fallback path tested.

**Commit:** `feat(flutter): History screen with local aggregation + online /summary fallback`

---

## Phase C — Export & retention

### [ ] B6. CSV export (ExportService + share sheet)

**Files:** `android/app/lib/services/export_service.dart`, `android/app/lib/screens/export_screen.dart`, `android/app/lib/providers/export.dart`, `android/app/test/services/export_service_test.dart`, `android/app/test/screens/export_screen_test.dart`

**Dependencies to add:** `share_plus`, `path_provider`

**Deliverable:**
- `ExportService.exportToCsv({DateTimeRange? range})` — queries drift for all non-deleted transactions (optionally filtered by `occurred_at` in `range`), joined with category names. Formats CSV with header row. Writes to `getApplicationCacheDirectory()/spendarr_export_<timestamp>.csv`. Returns the file path.
- **Export screen** — date-range picker (default: all time); row count preview (reactive from drift, updates as range changes); "Export CSV" button triggers `ExportService` then opens the OS share sheet via `share_plus`. Loading indicator while writing.
- Export accessible from History screen (AppBar icon) and Settings (export row).

**Test gate:** export with no filter → CSV has all non-deleted rows with correct columns and header; export with date range → only matching rows; amounts formatted as `"1234.56"` (decimal string, not cents integer); soft-deleted rows excluded; category name resolved correctly.

**Done when:** export produces a valid CSV; share sheet opens on device.

**Commit:** `feat(flutter): CSV export via share sheet`

---

### [DEFERRED] B7. Sync engine: push + pull + conflict handling + connectivity trigger

> **Deferred — see DECISIONLOG 2026-06-23.** The app ships offline-only first. The outbox table exists in the drift schema so no migration is needed when this is picked up. This milestone is not in the active build sequence.

---

### [ ] B8. RetentionWatcher + pre-rotation banner + retention sweep

**Files:** `android/app/lib/sync/retention_watcher.dart`, `android/app/lib/sync/retention_sweep.dart`, `android/app/lib/widgets/rotation_warning_banner.dart`, `android/app/lib/providers/retention.dart`, `android/app/test/sync/retention_test.dart`, `android/app/test/widgets/rotation_warning_banner_test.dart`

**Deliverable:**
- **`RetentionWatcher.check()`** — called on app foreground only (sync trigger deferred with B7). Queries drift for the earliest `occurred_at` among non-deleted `transactions`. If `earliest < now - 150 days`, sets `syncMeta['pre_rotation_shown'] = 'true'` and exposes a `retentionWarningProvider` that emits `true`. If `syncMeta['pre_rotation_dismissed_until']` is set and `< now`, re-surface the banner.
- **`RotationWarningBanner`** widget — shown at the top of the Today screen when `retentionWarningProvider` is `true`. Shows "Your oldest data will be removed in ~X days. Export it now." with:
  - "Export now" button → navigates to Export screen.
  - "Dismiss" button → sets `syncMeta['pre_rotation_dismissed_until'] = now + 7 days`; hides banner.
- **`RetentionSweep.run()`** — called on app foreground (after `RetentionWatcher.check()`), but only if `syncMeta['pre_rotation_shown'] == 'true'`. Deletes local `transactions` where `occurred_at < now - 180 days`. Then checks drift DB file size via `path_provider` + `dart:io`; if > 100 MB, deletes oldest rows (by `occurred_at`) in batches of 100 until under the cap. Categories and `recurringRules` rows are never swept.

**Test gate (watcher):** row at 151 days old → `retentionWarningProvider` emits true; row at 149 days → emits false; dismissed-until in future → emits false; dismissed-until in past → re-surfaces.
**Test gate (banner):** banner visible when provider is true; "Export now" taps route to `/export`; "Dismiss" sets dismissed-until 7 days out + banner disappears; banner absent when provider is false.
**Test gate (sweep):** sweep runs only after `pre_rotation_shown = true`; sweep deletes rows < 180 days; categories not deleted; `recurringRules` not deleted; 100 MB cap logic deletes oldest first.

**Done when:** seed a row at 151 days old → banner appears on Today screen → dismiss → re-appears after 7 days (mocked clock); seed rows > 180 days → after sync + sweep → local rows gone; `psql` confirms server still has them.

**Commit:** `feat(flutter): retention watcher + pre-rotation banner + sweep`

---

## Phase D — Ship

### [ ] C1. Release build + CI + end-to-end smoke

**Files:** `android/app/android/app/build.gradle` (signingConfig), `android/app/android/key.properties` (gitignored), `.github/workflows/android-ci.yml` (copy from heerr, adapt), `android/README.md`

**Deliverable:**
- Keystore generated; `key.properties` configured locally. `flutter build apk --release` produces a signed APK.
- CI workflow: `flutter pub get`, `dart run build_runner build`, `flutter analyze`, `flutter test` on push/PR to `main`.
- Manual end-to-end smoke: add transaction → visible on Today screen immediately; add 5 transactions → all visible in History; banner appears at 151 days (mocked clock) → export → CSV contains expected rows → dismiss → re-appears after 7 days; seed rows > 180 days → sweep removes them on foreground. (Sync smoke deferred to B7.)

**Test gate:** `flutter analyze` clean; `flutter test` green; signed APK installs via `adb install`.

**Done when:** all smoke steps pass; CI green on `main`. Tagged `v0.1.0`.

**Commit:** `infra(flutter): release build + CI + v0.1.0 smoke`

---

## Cross-cutting reminders

- **`flutter analyze` green before declaring any milestone done.**
- **`flutter test` green before AND after each milestone.**
- **`dart run build_runner build --delete-conflicting-outputs` clean after every milestone touching `@freezed` / `@riverpod` / drift annotations.**
- **No `double` for amounts anywhere.** Use `int` cents in drift, `Decimal` in models, decimal string in sync payload.
- **No `print` in production code** — `debugPrint` only.
- **No `.env` files** — all credentials in `flutter_secure_storage`.
- **No direct endpoint calls bypassing the outbox** — the online and offline write paths must be identical.
- **DECISIONLOG drift** — any contract/stack change → update `DECISIONLOG.md` + `CONTEXT.md` in the same commit.

---

## Roadmap complete when

1. All milestone boxes checked (B1–B8, C1).
2. Every test gate green at its milestone.
3. Signed APK installs and smoke passes end-to-end.
4. CI workflow green on `main`.
5. CHANGELOG entries exist for each milestone.
6. `git log --oneline android/` reads as a clean B→C progression under `feat(flutter):` / `chore(flutter):` cadence.
