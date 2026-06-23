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
