# CLAUDE.md — android

Android-client Claude rules. The app is built with Flutter but deploys Android-only; the dir is named for the platform, not the framework. **Project-wide rules live in `/CLAUDE.md` at repo root** — read that first.

---

## Bootstrap (when working on the Android client)

In order:

1. `/CLAUDE.md` (project-wide rules)
2. `android/CLAUDE.md` (this file — Android client hard rules)
3. `android/docs/CONTEXT.md` (env, target device, architecture)
4. `android/docs/DECISIONLOG.md` (ADRs — newest at the bottom)
5. `android/docs/CHANGELOG.md` (per-task history)

For operational lookup: `android/README.md`.
For the build sequence: `android/docs/ROADMAP.md`.

---

## Architecture (do not re-litigate)

- **Offline-first.** SQLite (via `drift`) is the primary store. Every UI write goes to local DB first; network is optional.
- **Outbox pattern.** Every mutation appends a row to `outbox(id, op, table, payload_json, queued_at, attempts, last_error)`. The sync engine drains this on connectivity.
- **Server = source of truth on conflict.** LWW by `updated_at` (UTC). When the server row wins, overwrite local and drop the outbox entry.
- **Connectivity is Tailscale-only.** The backend URL is user-supplied in Settings. No public ingress.
- **Android-only.** iOS is out of scope. Don't suggest Cupertino widgets, iOS plugins, or Xcode/CocoaPods steps.
- **No direct CRUD to backend.** All server writes go through `/sync/push` (outbox flush). All server reads go through `/sync/pull`. Direct endpoint calls are never correct — the offline path must always be identical to the online path.

---

## Stack (locked v1)

| Concern | Choice |
|---|---|
| State management | Riverpod (`flutter_riverpod` + `riverpod_annotation` + `riverpod_generator`) |
| Local DB | drift (SQLite) — DAOs expose reactive streams |
| HTTP | dio with bearer interceptor + typed `ApiError` |
| JSON / models | freezed + json_serializable |
| Token storage | flutter_secure_storage (Android EncryptedSharedPreferences) — never `shared_preferences` for the bearer token |
| Navigation | go_router |
| Theme | Material 3, dark mode, new seed colour (to be picked at B1) |
| Connectivity detection | connectivity_plus |

---

## Local storage rules

- **Amounts as `int` cents or `Decimal`** — never `double`. Display layer converts to the user's currency format.
- **All timestamps UTC** — store and compare in UTC; convert to local time only at display.
- **Soft deletes** — `deleted_at` column; never hard-delete rows that participate in sync. Drift DAOs must filter `deleted_at IS NULL` in queries unless explicitly fetching tombstones.
- **Retention sweep** — keep last 6 months OR ≤100 MB, whichever hits first. Categories and `recurring_rules` are exempt from the sweep. Sweep runs after the user has seen at least one pre-rotation warning banner.
- **Pre-rotation warning** — `RetentionWatcher` checks on app foreground and after each sync. If any row has `occurred_at < now - 150 days` (within 30 days of the 180-day cutoff), set a persisted flag and show the banner on Today screen with a 7-day snooze.

---

## CSV export rules

- Export is initiated from the History screen or Settings.
- All amounts in the CSV are formatted as decimal strings (e.g. `"1234.56"`), never integers.
- Columns (fixed order): `date, amount, kind, category, note, source, recurring_rule_id`.
- Write to cache dir, open via OS share sheet — never write to shared external storage directly.

---

## Development workflow

- **TDD by default.** Widget tests for screens (`flutter_test` + `WidgetTester`). Unit tests for providers/services/DAOs. Write the failing test first, then the implementation.
  - **Scope:** screens, providers, API client, model serialization, sync engine, export service, retention watcher.
  - **Out of scope (v1):** golden tests, integration tests on a real device, performance benchmarks.
- **Green before, green after.** Run `flutter test` before starting a task and confirm it passes. Run it again before declaring done. Run `flutter analyze` at the same checkpoints.
- **`dart run build_runner build --delete-conflicting-outputs` clean** after every milestone touching `@freezed` / `@riverpod` / drift `@DriftDatabase` annotations.
- Commit per ROADMAP milestone with the Conventional Commits message prescribed by `docs/ROADMAP.md`.

---

## User background (mobile-side reminder)

The user has **zero Flutter / Dart / mobile-app experience** (DevOps + data engineer by day). When explaining:

- Name every file path in full.
- Show every command with its working directory.
- Don't assume familiarity with `pubspec.yaml`, `pub get`, hot-reload, `build_runner`, `flutter analyze`, or Android Studio.
- Backend / Docker / Python / SQL analogies are welcome.

The user *does* know REST APIs, JSON, async, containers, and SQL end-to-end. Don't re-explain those.

---

## Hard "don't"s

- Don't add any Sign-In-With-X flow. Auth is a single bearer token pasted in Settings, minted by the backend CLI.
- Don't propose iOS / Cupertino / Xcode steps.
- Don't store the bearer token in `shared_preferences` or a plain file — `flutter_secure_storage` only.
- Don't add a direct CRUD endpoint call that bypasses the outbox. The online and offline write paths must be identical.
- Don't hard-delete rows that are synced to the server — always use soft-delete (`deleted_at`).
- Don't use `double` for money amounts anywhere in the codebase.
