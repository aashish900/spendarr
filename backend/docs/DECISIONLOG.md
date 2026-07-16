# DECISIONLOG.md — spendarr backend

ADR log. Append newest at the bottom. Format: `## YYYY-MM-DD — <title>` then **Context**, **Decision**, **Why**, **Alternatives considered**.

---

## 2026-06-22 — Stack: FastAPI + Postgres 17 + Alembic + bearer tokens

**Context:** Choosing the backend stack for a single-user personal finance tracker that syncs to an Android app over Tailscale.

**Decision:** Mirror the `heerr` stack exactly — FastAPI, Postgres 17, Alembic migrations, opaque bearer tokens (sha256-hashed, scopes `read`/`write`/`admin`), minted via a Typer CLI.

**Why:** The user already operates `heerr` on the same arr-stack. Reusing the same toolchain means no new operational surface, known deployment patterns (compose snippet, fixed IP), and copy-able code for auth, Alembic config, and CLI.

**Alternatives considered:** Django REST Framework (heavier, unnecessary for a single-service API); Postgres + PostgREST (no custom business logic possible — recurring runner and LWW conflict resolution need server-side code); SQLite as the server DB (removes the sync source-of-truth guarantee).

---

## 2026-06-22 — Sync model: outbox queue + LWW conflict resolution

**Context:** The app must work fully offline; writes on the device must survive network partitions and replay correctly when connectivity resumes.

**Decision:** Local SQLite as primary store. Every UI mutation appends to an `outbox` table. The sync engine drains the outbox via `POST /sync/push` (outbox batch → per-row ack). Server applies last-write-wins by `updated_at` (UTC). Delta pull via `POST /sync/pull?since=<last_pull_at>`. Server is the source of truth on conflict — device overwrites local row and drops the outbox entry when `conflict: true`.

**Why:** Outbox pattern gives a durable, replayable mutation log without needing a real queue (no Redis/Celery). LWW by `updated_at` is simple to implement, auditable in the DB, and sufficient for a single-user app where concurrent edits from two devices are uncommon.

**Alternatives considered:** CRDT-based merge (correct but complex, library support in Dart is thin); server-wins always (loses offline edits entirely); client-wins always (corrupts server state if the device clock is wrong).

---

## 2026-06-22 — No direct CRUD endpoints

**Context:** Deciding whether to expose `POST /transactions`, `POST /categories`, etc. alongside the sync endpoints.

**Decision:** No direct CRUD endpoints. All client mutations go through `/sync/push`. Server mutations (recurring runner) are applied server-side and become visible to the client via `/sync/pull`.

**Why:** A direct CRUD path would mean the app has two write paths — one online (direct endpoint) and one offline (outbox). Any bug in one path wouldn't be caught by the other. The outbox approach forces the online and offline paths to be identical.

**Alternatives considered:** Direct CRUD for online-only mutations (rejected — splits write path and undermines offline correctness).

---

## 2026-06-22 — Recurring runner: BackgroundTasks, not Celery

**Context:** Recurring transactions (salary, rent, subscriptions) must auto-post on schedule without user action.

**Decision:** FastAPI `BackgroundTasks` worker that wakes every 5 minutes. Finds `recurring_rules` with `next_run_at <= now AND active`, inserts `transactions`, advances `next_run_at`. Idempotent via unique index on `(recurring_rule_id, occurred_at)`.

**Why:** No additional infrastructure (Redis, Celery, worker process). The same pattern was proven sufficient in `heerr`. A 5-minute resolution is fine for recurring transactions (salary posts daily/monthly — sub-minute precision is not required).

**Alternatives considered:** Celery + Redis (operational overhead not justified for one periodic task); APScheduler (external library, state management more complex than a simple Postgres-backed loop); cron on the host (breaks the "reproducibility via compose" rule — no host-side manual steps).

---

## 2026-06-22 — Amounts: NUMERIC(14,2), never float

**Context:** Choosing the Postgres column type and SQLAlchemy mapping for monetary amounts.

**Decision:** `NUMERIC(14, 2)` in Postgres; `Numeric(14, 2)` in SQLAlchemy; `Decimal` in Python. Never `float`, `real`, or `double precision`.

**Why:** Floating-point arithmetic on money produces rounding errors (e.g. `0.1 + 0.2 != 0.3` in IEEE 754). `NUMERIC` is exact. 14 digits before the decimal covers amounts up to 999,999,999,999.99, which is sufficient for personal finance in any currency.

**Alternatives considered:** `INTEGER` cents (avoids floats but requires all display logic to divide by 100; error-prone at the boundary). `FLOAT8` (fast but inexact — ruled out categorically).

---

## 2026-06-22 — Soft deletes via deleted_at

**Context:** Deciding how to handle deletion of categories, transactions, and recurring rules that are synced to the device.

**Decision:** All synced tables carry a `deleted_at TIMESTAMPTZ NULL` column. Deletions set `deleted_at = now()` and update `updated_at`. Hard deletes are never performed on these tables. `/sync/pull` returns tombstones (rows where `deleted_at IS NOT NULL`) so the client can apply the deletion locally.

**Why:** Hard deletes would break delta sync — a client that hasn't synced since before the deletion would never learn the row is gone. Tombstones make the deletion visible to all clients.

**Alternatives considered:** Separate `tombstones` table (normalised but requires joins on every sync pull; more schema complexity); hard delete + event log (more infrastructure).
