# Play Store listing — spendarr

Copy-paste source for the Play Console store listing. Keep this file updated
alongside each tagged release; append new "What's new" entries at the bottom
under [Release notes by version](#release-notes-by-version) rather than
overwriting the previous one.

---

## Short description (max 80 characters)

```
Offline expense tracker. Your money, your device, no accounts, no ads.
```

## Full description (max 4000 characters)

```
spendarr is a personal, offline-first expense tracker built for one thing: knowing exactly how much money you have left this month, at a glance.

WHY SPENDARR

Most expense trackers get in their own way — they need a network connection to work, they monetise your spending data through ads or "free" bank-linking, or they bury the one number you actually care about under budgets, goals, and gamification you never asked for.

spendarr does the opposite:

• Works completely offline. Every transaction is saved to your device first. Airplane mode, no signal, doesn't matter — the app never depends on a connection.
• No accounts, no sign-up, no analytics, no ads. Nothing about your spending leaves your phone unless you choose to export it yourself.
• One number, front and centre: income minus everything that went out equals what's left to spend.

WHAT YOU CAN DO

Track — Log income, expenses, and investments in seconds, each with a category, amount, date, time, and an optional note. Set up recurring entries (rent, subscriptions, SIPs) once and they show up automatically on their due dates.

Review — The home screen shows a month-progress ring with "₹X left to spend," income/expense totals, and a running day-by-day ledger you can zoom to Day, Week, or Month view. Every day's entries are summarised in green (money in) and red (money out) so you can scan a whole month in seconds.

Analyse — The History tab breaks down spending by category with a bar chart, and lets you pull up any custom date range.

Own your data — Export everything to CSV whenever you want, straight through Android's share sheet — email it, save it to Drive, open it in a spreadsheet, whatever you like. There's no lock-in.

DESIGN

A dark, AMOLED-black theme with metallic gold accents throughout, built to be easy on the eyes and easy on the battery on OLED screens.

PRIVACY

spendarr doesn't collect, transmit, or sell any of your data. There are no third-party analytics or ad SDKs in the app. Your transactions live in a local database on your device; the only way data leaves the app is a CSV export that you explicitly trigger and share yourself.

WHAT'S NOT HERE (YET)

This is a focused v1. It deliberately doesn't do multi-currency, bank/SMS auto-import, multi-user accounts, or spending-pattern nudges — the goal is a fast, honest, single-purpose tracker, not a finance suite. A self-hosted sync option (over your own private network) is planned for a future release but is not required to use the app.

spendarr is built for people who want to actually know where their money went last month — not fight software to find out.
```

---

## Release notes by version

### v0.1.0 (max 500 characters)

```
First release of spendarr 🎉

• Track income, expenses, and investments offline
• Home screen shows money left to spend this month at a glance, with a day-by-day ledger
• Recurring transactions (rent, subscriptions, SIPs)
• Category management with custom icons
• Spend-by-category breakdown and custom date-range history
• CSV export via the standard share sheet
• Dark, AMOLED black + gold theme

No accounts, no ads, no data collection. Your data stays on your device.
```

### v0.1.1 (max 500 characters)

```
Polish update:

• Fixed the + button covering the last transaction when scrolled to the bottom
• Category icons now support any emoji, not just a preset list
• Categories can now be edited, not just created and archived
• Add/Edit Category screen redesigned to match the rest of the app

No accounts, no ads, no data collection. Your data stays on your device.
```

### v0.1.2 (max 500 characters)

```
Polish update:

• Category icons now show your emoji in its real colour instead of solid gold
• Recurring screen now breaks totals down by Income, Investment, and Expense
• Fixed the category picker not scrolling with a long list, blocking "New category"

No accounts, no ads, no data collection. Your data stays on your device.
```

### v0.1.3 (max 500 character)

```
Budget update:

• Set a monthly budget — the home ring now tracks it, not your income
• Overspend and the ring fills red so you can see it at a glance
• Choose a budget that stays the same each month, or set a new one every month
• Edit your budget any time from Settings
• Recurring total on Home no longer counts income rules like salary

No accounts, no ads, no data collection. Your data stays on your device.
```

### v0.1.4 (max 500 characters)

```
Polish update:

• Home summary now shows Income, Expenses, and Balance instead of Expenses/Investments/Recurring
• Categories screen now shows a 3-column grid instead of one row per category
• Cleaner month-ring layout: income and expense figures moved below the ring

No accounts, no ads, no data collection. Your data stays on your device.
```

---

## Submission checklist (things this file doesn't cover)

- **Data safety section** — answer "No data collected" across the board; matches the app's actual behavior (see [`PRIVACY_POLICY.md`](../../../PRIVACY_POLICY.md)).
- **Content rating questionnaire** — "Everyone," no user-generated content shared with others.
- **Privacy policy URL** — Play Console requires one even for a no-collection app. Use the GitHub blob URL for `PRIVACY_POLICY.md`, e.g. `https://github.com/aashish900/spendarr/blob/main/PRIVACY_POLICY.md`, or enable GitHub Pages for a rendered version.
- **Package ID** — `com.aashish.spendarr` (`android/app/android/app/build.gradle.kts`) — confirm this matches what's registered in Play Console.
- **Screenshots** — Play Console requires at least 2 phone screenshots; none are checked into the repo yet.
