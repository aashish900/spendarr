# CONTEXT.md — spendarr backend

Project brief for resuming the backend build in Claude Code. Read this after `/CLAUDE.md` and `backend/CLAUDE.md`.

## Name

**spendarr** — personal money tracker, arr-stack sibling of `heerr`. Tracks earnings, investments (as cashflow), and day-to-day spending. Single-user, single-currency, offline-first on the device with server-side sync.

## Goal

A FastAPI service that acts as the sync server and recurring-transaction engine for the spendarr Android app. The app writes to local SQLite first; when online it pushes mutations to this service and pulls any server-side changes (including auto-posted recurring transactions). The server is the source of truth on conflict.

## Architecture

- **FastAPI** service, Docker container, merges into the user's arr-stack via `docker-compose.snippet.yml`.
- **Postgres 17** — server-side store. Tables: `categories`, `transactions`, `recurring_rules`, `tokens`.
- **Alembic** migrations — one initial migration (`0001`) creates the full schema.
- **Sync model** — client sends outbox batches via `POST /sync/push`; server returns per-row ack with LWW result. Client pulls delta via `POST /sync/pull?since=<ISO>`.
- **Recurring runner** — `BackgroundTasks` worker wakes every 5 min; inserts `transactions` rows for due rules; idempotent on `(rule_id, occurred_at)`.
- **Summary endpoint** — `GET /summary` aggregates spend by category for a requested period; used by the app when online as a faster alternative to local aggregation.
- **Auth** — opaque bearer tokens, sha256-hashed in DB, scopes `read` / `write` / `admin`. Minted via `python -m app.cli create-token`.
- **Connectivity** — Tailscale-only. No public exposure.

## Data model (Postgres)

All tables carry: `id UUID PK`, `created_at TIMESTAMPTZ`, `updated_at TIMESTAMPTZ`, `deleted_at TIMESTAMPTZ NULL` (soft delete, LWW applies).

- `categories` — `name TEXT`, `emoji TEXT`, `kind ENUM(income|expense|investment)`, `archived BOOL`
- `transactions` — `category_id UUID FK`, `amount NUMERIC(14,2)`, `kind ENUM(income|expense|investment)`, `occurred_at TIMESTAMPTZ`, `note TEXT`, `source ENUM(manual|recurring)`, `recurring_rule_id UUID FK NULL`
- `recurring_rules` — `category_id UUID FK`, `amount NUMERIC(14,2)`, `kind`, `note TEXT`, `cron TEXT`, `next_run_at TIMESTAMPTZ`, `last_run_at TIMESTAMPTZ NULL`, `active BOOL`
- `tokens` — sha256-hashed bearer, scopes, `owner TEXT`, `revoked_at TIMESTAMPTZ NULL`

## API contract (`/api/v1`)

| Method | Path | Scope | Purpose |
|---|---|---|---|
| GET | `/health` | none | liveness |
| POST | `/sync/pull` | read | body: `{since: ISO-8601}` → delta rows for all tables (incl. tombstones) |
| POST | `/sync/push` | write | outbox batch → per-row ack `{id, server_updated_at, conflict}` |
| GET | `/summary` | read | `?period=day\|week\|month&from=&to=` → spend aggregated by category |
| POST | `/admin/tokens` | admin | mint token |

Direct CRUD endpoints are intentionally absent — all mutations flow through the sync endpoints.

## Conflict policy

Last-write-wins by `updated_at` (UTC). Incoming `updated_at` must be strictly greater than the server row's `updated_at` to overwrite. Server returns `conflict: true` when the server row wins; client overwrites local and drops the outbox entry.

Soft-deletes (`deleted_at`) follow the same LWW rule.

## Server environment

- Same arr-stack as `heerr`: Ubuntu 26.04, user `aashish`, LAN IP `192.168.1.43`, Tailscale `100.106.120.121`.
- arr-stack at `~/docker/arr-stack/docker-compose.yml`, Docker subnet `172.39.0.0/24` with fixed IPs.

## Dev environment

- Python 3.13, Poetry, FastAPI, SQLAlchemy async, Alembic.
- Tests: pytest + testcontainers-postgres (real Postgres in CI, no SQLite mocks).
- Mac (Apple Silicon), Docker Desktop.

## Build order

Backend milestones A1–A4, then Android B1–B8. See `docs/ROADMAP.md`.

## Out of scope for v1

- Spending-pattern flagging / insights.
- Multi-currency.
- Investment portfolio valuation.
- SMS parsing, CSV import.
- Multi-user.
