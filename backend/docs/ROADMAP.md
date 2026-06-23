# ROADMAP.md — spendarr backend implementation milestones

Track progress through the backend build. Each milestone = one git commit with a green test gate where applicable. Tick the box when committed.

See `CONTEXT.md` for the architecture; `DECISIONLOG.md` for the why behind decisions; this file is the how/when.

**Conventions:**
- TDD per `CLAUDE.md` — tests written first, land in the same commit as production code.
- Out of TDD scope: scaffold, Dockerfile, compose snippet, Alembic migrations, smoke steps. These have other verification gates noted per milestone.
- Commit messages: Conventional Commits (`feat(scope): …`, `chore: …`, `infra: …`).
- One milestone = one commit. Follow-up cleanup = separate commit under the same milestone label.
- **Halt and confirm at each milestone boundary.**

---

## Phase A — Foundation

### [ ] A1. Scaffold: Poetry + Alembic skeleton

**Files:** `backend/pyproject.toml`, `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/script.py.mako`, `backend/alembic/versions/`, `backend/app/__init__.py`

**Deliverable:** `cd backend && poetry install` succeeds; `poetry run alembic current` exits 0.

**Dependencies:** `fastapi`, `uvicorn[standard]`, `sqlalchemy[asyncio]`, `asyncpg`, `alembic`, `pydantic-settings`, `typer`, `python-jose`, `pytest`, `pytest-asyncio`, `testcontainers[postgres]`, `httpx`

**Test gate:** none (out of TDD scope).

**Done when:** `poetry install` + `alembic current` both exit 0.

**Commit:** `chore(backend): scaffold poetry + alembic skeleton`

---

### [ ] A2. Migration 0001 — base schema

**Files:** `backend/alembic/versions/0001_init.py`, `backend/tests/__init__.py`, `backend/tests/conftest.py`, `backend/tests/test_migration_0001.py`

**Deliverable:** Full schema in one migration — `categories`, `transactions`, `recurring_rules`, `tokens`. All tables carry `id UUID PK default gen_random_uuid()`, `created_at TIMESTAMPTZ default now()`, `updated_at TIMESTAMPTZ default now()`, `deleted_at TIMESTAMPTZ NULL`. Enum types: `txn_kind (income, expense, investment)`, `txn_source (manual, recurring)`. Unique index on `(recurring_rule_id, occurred_at)` in `transactions` (idempotent recurring runner). `updated_at` auto-set via a Postgres trigger or explicit `onupdate` — document the choice in DECISIONLOG.

**Test gate:** migration round-trip (`alembic upgrade head` + `alembic downgrade base`) against `testcontainers-postgres`; assert unique constraint on `(recurring_rule_id, occurred_at)` prevents duplicate recurring posts; assert FK violations caught.

**Done when:** round-trip clean; unique index invariant proven by a test that catches the constraint violation.

**Commit:** `feat(db): migration 0001 — base schema`

---

### [ ] A3. SQLAlchemy ORM models + config + DB session

**Files:** `backend/app/models/{__init__,base,category,transaction,recurring_rule,token}.py`, `backend/app/config.py`, `backend/app/db.py`, `backend/tests/test_models_match_schema.py`, `backend/tests/test_config.py`, `backend/tests/test_db_session.py`

**Deliverable:**
- ORM models mirror the 0001 schema exactly. `compare_metadata` drift check returns no differences.
- `pydantic-settings`-based `Settings` with `DATABASE_URL` (required), `TOKEN_HASH_ALGO` (default `sha256`). Fails fast with a named error if `DATABASE_URL` is unset.
- Async SQLAlchemy engine + `get_session` dependency.

**Test gate:** `compare_metadata` clean against the migrated testcontainer; config missing-field error test; session yields/commits/closes against the testcontainer.

**Done when:** `compare_metadata` returns no differences; session round-trips `SELECT 1`.

**Commit:** `feat(backend): ORM models + config + async db session`

---

### [ ] A4. Auth dependency + token CLI + `/health`

**Files:** `backend/app/api/__init__.py`, `backend/app/api/deps.py`, `backend/app/api/v1/__init__.py`, `backend/app/api/v1/router.py`, `backend/app/api/v1/health.py`, `backend/app/main.py`, `backend/app/cli.py`, `backend/tests/test_auth.py`, `backend/tests/test_cli.py`, `backend/tests/test_health.py`

**Deliverable:**
- `bearer_token()` FastAPI dependency — extracts `Authorization: Bearer <token>`, hashes it, looks up in `tokens` table, checks `revoked_at`. `require_scope(scope)` and `require_admin()` guards.
- CLI: `python -m app.cli create-token --owner=<label> --scopes=read,write` (raw token printed once; hash stored). `list-tokens`, `revoke-token`.
- `GET /api/v1/health` returns `{"status": "ok"}` with no auth.
- FastAPI app: `app = FastAPI(lifespan=...)`, `/api/v1` mounted, CORS locked to no public origins.

**Test gate (auth):** table-driven coverage of missing/invalid/revoked/wrong-scope/admin-required branches.
**Test gate (CLI):** Typer `CliRunner` against testcontainer — create token prints raw token; hash in DB; `list-tokens` shows it; `revoke-token` sets `revoked_at`; revoked token → 401.
**Test gate (health):** ASGI transport → 200; no auth required.

**Done when:** all auth state-machine branches green; CLI round-trip green; `curl localhost:8000/api/v1/health` returns 200.

**Commit:** `feat(backend): auth dependency + token CLI + GET /health`

---

## Phase B — Sync endpoints

### [ ] B1. `/sync/push` — outbox batch ingest with LWW

**Files:** `backend/app/schemas/sync.py`, `backend/app/services/sync.py`, `backend/app/api/v1/sync.py` (push handler), `backend/tests/test_sync_push.py`

**Deliverable:** `POST /sync/push` (scope: `write`). Body: list of mutation items — each has `table`, `op (upsert|delete)`, `payload` (full row dict), `client_updated_at`. Server applies LWW per row:
- **Upsert:** if no server row exists, insert. If server row exists and `client_updated_at > server.updated_at`, overwrite. Otherwise, return `conflict: true` and current `server_updated_at`.
- **Delete (soft):** set `deleted_at = client_updated_at` if `client_updated_at > server.deleted_at` (or `server.deleted_at IS NULL`). LWW applies here too.

Response: list of `{id, server_updated_at, conflict: bool}`, one per input item. Unknown `table` values → 422.

**Test gate:** new row upsert; existing row — client newer wins; existing row — server newer → `conflict: true`; soft delete; soft delete conflict (server deleted more recently); unknown table → 422; scope=read → 403.

**Done when:** all LWW branches exercised in tests.

**Commit:** `feat(backend): POST /sync/push with LWW conflict resolution`

---

### [ ] B2. `/sync/pull` — delta pull with tombstones

**Files:** `backend/app/api/v1/sync.py` (pull handler added), `backend/tests/test_sync_pull.py`

**Deliverable:** `POST /sync/pull` (scope: `read`). Body: `{since: ISO-8601 | null}`. Returns rows from `categories`, `transactions`, `recurring_rules` where `updated_at > since` OR `deleted_at > since` (i.e. all changes including tombstones). If `since` is null, returns all non-deleted rows (full bootstrap). Response: `{categories: [...], transactions: [...], recurring_rules: [...], server_time: ISO-8601}`.

**Test gate:** full bootstrap (null since); delta with changes; tombstone in delta; `since` in the future → empty delta; scope=admin-only token with `read` → works; scope missing → 403.

**Done when:** tombstone test passes (deleted row appears in delta); full bootstrap round-trip verified.

**Commit:** `feat(backend): POST /sync/pull with tombstone support`

---

### [ ] B3. `/summary` — period aggregation

**Files:** `backend/app/schemas/summary.py`, `backend/app/services/summary.py`, `backend/app/api/v1/summary.py`, `backend/tests/test_summary.py`

**Deliverable:** `GET /summary?period=day|week|month&from=YYYY-MM-DD&to=YYYY-MM-DD` (scope: `read`). Aggregates non-deleted `transactions` grouped by `category_id + kind`, filtered to `occurred_at` in `[from, to]`. Returns `{period, from, to, totals: [{category_id, category_name, emoji, kind, total: NUMERIC}]}`.

If `period` is provided without `from`/`to`, default `to = today` and `from` = `today - 1 day|week|month`. If `from`/`to` provided, `period` is informational only.

**Test gate:** day/week/month aggregation with seeded rows; excludes soft-deleted transactions; respects `from`/`to` bounds; empty result for out-of-range dates; missing required params → 422.

**Done when:** all aggregation cases covered.

**Commit:** `feat(backend): GET /summary with period aggregation`

---

## Phase C — Recurring runner + CI

### [ ] C1. Recurring transaction runner

**Files:** `backend/app/services/recurring_runner.py`, `backend/app/main.py` (wire `BackgroundTasks` lifespan loop), `backend/tests/test_recurring_runner.py`

**Deliverable:** `recurring_runner.run_once(session)` — finds `recurring_rules` with `next_run_at <= now() AND active = true AND deleted_at IS NULL`; for each rule, inserts a `transactions` row with `source=recurring`, `occurred_at = rule.next_run_at`; advances `next_run_at` per the rule's `cron` string (use `croniter`); updates `rule.last_run_at`. Idempotent: catches `UniqueViolationError` on `(recurring_rule_id, occurred_at)` → skip without error.

Wired into the FastAPI lifespan as a `BackgroundTasks`-driven loop that calls `run_once` every 5 minutes.

**Test gate:** due rule → transaction inserted + `next_run_at` advanced; rule in future → skipped; inactive rule → skipped; duplicate run for same `occurred_at` → idempotent (no error, no double row); cron advancement correct for monthly/weekly/daily rules.

**Done when:** idempotency test passes; cron advancement verified for at least monthly and weekly rules.

**Commit:** `feat(backend): recurring transaction runner`

---

### [ ] C2. pytest suite + CI

**Files:** `backend/.github/workflows/backend-ci.yml` (copy from heerr, adapt), `backend/Dockerfile` (multi-stage, non-root, uvicorn CMD), `backend/.dockerignore`, `backend/tests/` (confirm all existing tests pass in CI environment)

**Deliverable:**
- CI workflow runs `poetry install`, `poetry run pytest --tb=short` on push/PR to `main`. Uses `testcontainers-postgres` (Docker-in-Docker or service container — pick the pattern from heerr).
- Dockerfile: `python:3.13-slim` base, Poetry deps installed, app copied, runs as non-root UID. `CMD` is `uvicorn app.main:app --host 0.0.0.0 --port 8000`.
- `docker build` succeeds; `docker run --rm spendarr-backend python -m app.cli --help` prints help.

**Test gate:** `poetry run pytest` green locally; CI workflow green on a push.

**Done when:** all A1–C1 tests green in CI; Docker build succeeds.

**Commit:** `infra(backend): Dockerfile + CI workflow`

---

## Cross-cutting reminders

- **`.env` never committed.** Only `.env.example`.
- **Amounts always `NUMERIC(14,2)`** — any ORM field or schema field for money must use `Decimal`, not `float`.
- **All timestamps UTC** — `datetime.now(timezone.utc)` in Python; `TIMESTAMPTZ` in Postgres. Never naive datetimes.
- **No PII in logs** — never log `note`, `amount`, or `category.name` at INFO level or above.
- **DECISIONLOG drift** — any contract/schema change → append ADR and update `CONTEXT.md` in the same commit.
- **Green-before, green-after** — run `poetry run pytest` before starting each milestone and before declaring done.

---

## Roadmap complete when

1. All milestone boxes checked (A1–A4, B1–B3, C1–C2).
2. Every test gate green at its milestone.
3. Docker build succeeds; `docker run` boots and responds to `/health`.
4. CI workflow green on `main`.
5. CHANGELOG entries exist for each milestone.
6. `git log --oneline backend/` reads as a clean A→B→C progression.
