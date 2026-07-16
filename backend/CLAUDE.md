# CLAUDE.md — backend

Backend-specific Claude rules. **Project-wide rules live in `/CLAUDE.md` at repo root** — read that first.

---

## Bootstrap (when working on the backend)

In order:

1. `/CLAUDE.md` (project-wide rules)
2. `backend/CLAUDE.md` (this file — backend hard rules)
3. `backend/docs/CONTEXT.md` (server env, architecture, constraints)
4. `backend/docs/DECISIONLOG.md` (ADRs — newest at the bottom)
5. `backend/docs/CHANGELOG.md` (per-task history)

For operational lookup: `backend/README.md`.
For the build sequence: `backend/docs/ROADMAP.md`.

---

## Architecture (do not re-litigate)

- FastAPI service in Docker, merges into the user's arr-stack via `docker-compose.snippet.yml`.
- Postgres 17 as the server-side source of truth; SQLite lives on the device only.
- Sync is the only write path from the app — no direct CRUD endpoints. All mutations flow through `/sync/push` (outbox batches) and `/sync/pull` (delta pull by `updated_at`).
- Recurring rules are evaluated server-side by a `BackgroundTasks` worker (`recurring_runner.py`), not on the device. The device only reads the resulting `transactions` rows via `/sync/pull`.
- Connectivity is Tailscale-only. No public ingress.

---

## Data integrity rules

- **Amounts are always `NUMERIC(14,2)`** in Postgres — never `float`, never `real`. SQLAlchemy column type must be `Numeric(14, 2)`.
- **All timestamps UTC** — `TIMESTAMPTZ` in Postgres; Python always uses `datetime.now(UTC)` or `datetime.utcnow()`. Never naive datetimes in the DB layer.
- **Soft deletes via `deleted_at`** — never hard-delete `transactions`, `categories`, or `recurring_rules`. Tombstones must be returned by `/sync/pull` so the client can apply the deletion locally.
- **LWW conflict policy** — `/sync/push` compares incoming `updated_at` with the server row's `updated_at`; only overwrite if incoming is newer. Return `conflict: true` when the server row wins.
- **Idempotent recurring runner** — unique index on `(recurring_rule_id, occurred_at)` in `transactions`. Catch `IntegrityError` on insert; silently skip; do not double-post.
- **No PII in logs** — never log transaction `note`, category names, or amounts at INFO level or above.

---

## API contract (do not add direct CRUD endpoints)

Direct CRUD endpoints (`POST /transactions`, `POST /categories`, etc.) are intentionally absent. Adding them would split the write path and break offline consistency. All mutations from the client must go through `/sync/push`. If a new endpoint is proposed, verify it fits the sync model first.

---

## Job processing

- **No Redis / Celery.** Use FastAPI `BackgroundTasks` for the recurring runner. Suggest a real queue only with evidence the current setup is outgrown.
- Recurring runner wakes every 5 min, finds `recurring_rules` with `next_run_at <= now AND active`, inserts a `transactions` row, advances `next_run_at`. Idempotent on `(rule_id, occurred_at)`.

---

## Development workflow

- **TDD by default.** Write the failing test, then the implementation. No production logic merges without a test that exercises it first.
  - **Scope:** FastAPI app code — endpoints, services, models, CLI.
  - **Out of scope:** `docker-compose.yml`, `Dockerfile`, Alembic migrations, smoke tests. These have their own verification gates.
- **Green before, green after.** Run `poetry run pytest` before starting a task and confirm it's passing. Run it again before declaring done. If tests were red before you started, fix them first.
- Real Postgres in tests via `testcontainers-postgres` — no SQLite mocks.
- Commit per ROADMAP milestone with the Conventional Commits message prescribed by `docs/ROADMAP.md`.
