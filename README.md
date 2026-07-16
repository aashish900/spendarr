# spendarr

[![Publish Android APK + AAB](https://github.com/aashish900/spendarr/actions/workflows/android-publish.yml/badge.svg)](https://github.com/aashish900/spendarr/actions/workflows/android-publish.yml)
[![Latest release](https://img.shields.io/github/v/release/aashish900/spendarr?label=version)](https://github.com/aashish900/spendarr/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**spendarr** is a personal, offline-first expense tracker for Android. You record income, expenses, and investments; it tells you — at a glance, on one screen — how much money you have left this month and where the rest went.

<br>

## Why it exists

Most expense trackers fail in one of three ways:

1. **They need the network.** Your data lives on someone else's server, entry fails without connectivity, and the app dies when the company does.
2. **They monetise your data.** Bank-account linking, SMS scraping, and ad-driven "free" models mean your complete financial history is the product.
3. **They overcomplicate the core question.** Budget envelopes, goals, gamification — when all you actually want to know is *"how much is left, and what did I spend it on?"*

spendarr is the opposite of all three:

- **Offline-first, local-only storage.** Every transaction is written to an on-device SQLite database first. The app is fully functional with airplane mode on, forever. A self-hosted sync backend (FastAPI + Postgres, reachable only over a private [Tailscale](https://tailscale.com/) network — never the public internet) is planned, but the app never depends on it.
- **Single user, no accounts, no telemetry.** There is no sign-up, no analytics SDK, and no third-party service in the data path. Your data leaves the device only when *you* export it.
- **One question, answered instantly.** The home screen is built around a single figure: *income − outflows = left to spend*, with a month-progress ring and a chronological ledger under it.

<br>

## What it does

### Track
- **Three kinds of transactions** — income, expense, investment — each with an amount, category, date & time, and optional note. Amounts are stored as integer paise (never floating point), timestamps in UTC.
- **Custom categories** with a curated set of gold-themed icons, grouped by kind (income / expense / investment).
- **Recurring transactions** — daily / weekly / monthly / custom cron rules with pause, resume, and delete. Any transaction can be flagged recurring at entry time; the Recurring tab shows active and inactive rules, the projected monthly total, and each rule's next due date.

### Review
- **Home** — a month ring showing *"₹X left to spend"* (income minus all outflows, investments included), income/expense stats, an Expenses / Investments / Recurring summary strip, and a date-grouped journal with Day / Week / Month zoom. Every day header carries its own credit/debit summary (money in, green; money out, red). Month switcher to browse history.
- **History** — spend-by-category bar chart plus the full transaction list for a day, week, month, or any custom date range.
- **Insights, minimal by design** — a facts-only card ("Rent renews tomorrow") when a recurring rule fires within the next 7 days. No spending-pattern judgment, no nudges.

### Own your data
- **CSV export** — pick a date range, get a CSV (`date, amount, kind, category, note, source, recurring_rule_id`) through the standard Android share sheet. Available from History and Settings.
- **Soft deletes and a sync-ready schema** — nothing is hard-deleted; every mutation also queues an outbox entry, so the future backend sync (last-write-wins over Tailscale) plugs in without a data migration.

### Look
- A dark **AMOLED black + metallic gold** theme throughout — gradient gold accents, dark bordered cards, and a consistent design language on every screen. Built for OLED screens and for glancing at in the dark.

<br>

## Screens

| Tab | Purpose |
|---|---|
| **Home** | Month ring ("left to spend"), income/expense stats, summary strip, Day/Week/Month journal, upcoming-renewal insight |
| **History** | Bar chart + transaction list per day/week/month/custom range; CSV export shortcut |
| **Categories** | Manage categories per kind; add with a themed icon picker; archive |
| **Recurring** | Total recurring summary, active/inactive rules, pause/resume/delete, next due dates |
| **Settings** | CSV export (server & profile settings return when sync ships) |

<br>

## Architecture (short version)

```
┌───────────────────────────── Android app (Flutter) ─────────────────────────────┐
│                                                                                 │
│  UI (Material 3, black+gold)  ──  Riverpod providers  ──  drift (SQLite)        │
│                                                              │                  │
│                                        every write ──────────┤                  │
│                                                              ▼                  │
│                                                        outbox table             │
│                                                     (queued mutations)          │
└──────────────────────────────────────────────────────────────│──────────────────┘
                                                               ▼  (planned, B7)
                                     /sync/push · /sync/pull over Tailscale only
                                            FastAPI + Postgres backend
```

- **Flutter + Riverpod + drift + go_router.** Reactive DAO streams drive the UI; every screen updates live as the database changes.
- **Outbox pattern.** Each mutation writes the drift row *and* an outbox entry in one transaction. Online and offline write paths are identical — sync is a drain of the outbox, not a separate code path.
- **Money is integer cents.** Integer arithmetic end-to-end; `double` is banned from the codebase for amounts.
- **The repo also contains `backend/`** — the FastAPI sync service. It has not been started yet; the app currently ships offline-only.

Deeper docs live with each app: [`android/docs/CONTEXT.md`](android/docs/CONTEXT.md) (architecture & constraints), [`android/docs/DECISIONLOG.md`](android/docs/DECISIONLOG.md) (every ADR), [`android/docs/ROADMAP.md`](android/docs/ROADMAP.md) (milestones), [`android/docs/CHANGELOG.md`](android/docs/CHANGELOG.md) (per-task history).

<br>

## Repo layout

```
spendarr/
├── android/            Flutter Android client
│   ├── app/            the Flutter project (lib/, test/, android/)
│   └── docs/           CONTEXT / DECISIONLOG / CHANGELOG / ROADMAP
├── backend/            FastAPI + Postgres sync service (not started)
└── .github/workflows/  tag-triggered APK + AAB release pipeline
```

<br>

## Install

Grab the APK from the [latest release](https://github.com/aashish900/spendarr/releases/latest) and sideload it (`adb install spendarr-vX.Y.Z.apk`, or open it on the phone). Each release also carries the `.aab` used for Play Store submission.

### Build from source

```bash
cd android/app
flutter pub get
flutter analyze          # should report no issues
flutter test             # full widget + unit suite
flutter run -d <device>  # debug build on a connected device/emulator
```

Release builds are signed; see [`android/app/README.md`](android/app/README.md) for one-time keystore setup and the full release procedure.

### Releasing

Push a `v*` tag. The [`android-publish`](.github/workflows/android-publish.yml) workflow builds the signed APK and AAB (version name baked from the tag) and attaches both to a GitHub Release:

```bash
git tag -a v0.1.0 -m "..."
git push origin v0.1.0
```

<br>

## Out of scope (v1)

Deliberately not built, to keep the core sharp: multi-user, multi-currency, bank/SMS integration, CSV *import*, investment portfolio valuation, spending-pattern analysis, and iOS.

<br>

## License

[MIT](LICENSE) © 2026 Aashish Agarwal
