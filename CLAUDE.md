# CLAUDE.md — spendarr (project-wide)

Project-wide rules for any Claude session in this repo. **App-specific rules and architecture facts live in each app's own `<app>/CLAUDE.md` / `<app>/docs/`** — this file is intentionally app-agnostic.

The repo currently contains two apps, both under the same convention:
- `backend/` — FastAPI service. Milestones A1–A4 not yet started.
- `android/` — Flutter Android client. Milestones B1–B8 not yet started.

---

## 1. Repo layout & docs convention

Every app under this repo follows the same structure:

```
<app>/
├── README.md            operational entry point — how to install / run / test
├── CLAUDE.md            (optional) app-specific Claude rules
└── docs/
    ├── CONTEXT.md       project brief — architecture, constraints, env
    ├── DECISIONLOG.md   ADR log (newest at bottom)
    ├── CHANGELOG.md     append-only per-task change log
    ├── DEBT.md          (optional) outstanding tech debt
    └── ROADMAP.md       milestone sequence
```

Files at repo root that aren't per-app:
- `CLAUDE.md` (this file)
- `README.md` (top-level project description — usually auto-created)
- `.env.example`, `docker-compose.snippet.yml`, `.gitignore` (deployment / repo metadata)

---

## 2. Session discipline (applies to every app)

### Session bootstrap

At the start of every session, before non-trivial answers or proposals, identify which app is in scope and read in order:

1. **`<app>/CLAUDE.md`** if it exists (app-specific rules)
2. `<app>/docs/CONTEXT.md`
3. `<app>/docs/DECISIONLOG.md`
4. `<app>/docs/CHANGELOG.md`

Consult `<app>/docs/ROADMAP.md` for build sequence, `<app>/docs/DEBT.md` (if present) for outstanding work, and `<app>/README.md` for operational lookup ("how do I run / call / test it").

If the question is purely project-wide (not bound to a single app), this file is sufficient.

Trivial one-liners (clarifications, definitions) may skip bootstrap. Only read source code when the docs are insufficient.

### Decisions vs changes

- A **decision** is *"we chose X over Y because Z"* → append to the relevant `DECISIONLOG.md`.
- A **change** is *"edited file F to do G"* → append to the relevant `CHANGELOG.md`.
- The same action can produce both entries.

### Entry format

- `DECISIONLOG.md`: `## YYYY-MM-DD — <title>` then **Context**, **Decision**, **Why**, **Alternatives considered**. Append newest at the bottom.
- `CHANGELOG.md`: `## YYYY-MM-DD — <one-line summary>` then bullets — files touched + what changed. Append-only; never edit or delete prior entries.
- Timestamps: use the date the harness injects into the system prompt. If unavailable, run `date` and cite it.

### Logging cadence

Flush entries **at the end of each task** (a user-approved unit of work), not end of session. If a task spans many edits, batch them into one CHANGELOG entry on completion.

### Staleness rule

Code is the source of truth. If `DECISIONLOG.md` or `CONTEXT.md` contradicts current code, the log is stale — update it in the same turn you discover the drift, and note the correction in `CHANGELOG.md`.

### CONTEXT.md vs DECISIONLOG.md

- Update **CONTEXT.md** when standing facts change (architecture, env, constraints).
- Append to **DECISIONLOG.md** when a *new* decision is made (even if it also updates CONTEXT.md).

---

## 3. Project-wide hard rules

These apply regardless of which app you're working on.

### Connectivity & infra

- **Connectivity is Tailscale only.** Never propose public exposure, reverse proxies, port-forwards to the open internet, or any path that bypasses the tailnet.
- **Reproducibility via compose.** All infra setup (DB init, file ownership, schema bootstrap) lives in `docker-compose.yml` / init containers. No manual host-side steps to bring up the stack.

### Secrets

- **Never hardcode or commit secrets** (API keys, DB credentials, OAuth secrets). Load from `.env` / env vars in the runtime container. Flag any diff that violates this.

### Finance-specific rules

- **No PII in logs.** Never log transaction notes, category names, or amounts at INFO level or above. Debug-level only, and only behind an explicit debug flag.
- **Amounts always `NUMERIC`, never float.** In Postgres: `NUMERIC(14,2)`. In Dart: `int` cents or a `Decimal` package — never `double`.
- **All timestamps UTC.** Store, transfer, and compare in UTC. Convert to local time only at the display layer.

### Scope discipline

- **Backend first, Android client second.** Don't propose `android/` work until the backend endpoint it depends on exists and is curl-testable. (The Android client is built with Flutter; the dir is named `android/` to reflect the deployment target — there is no iOS port.)
- **iOS is out of scope.** Don't suggest iOS-aware code, Cupertino widgets where Material works, or Xcode/CocoaPods steps.
- **v2 features are out of scope.** Do not implement or design spending-pattern flagging, multi-currency, investment portfolio valuation, SMS parsing, CSV import, or multi-user features. Flag and defer if the conversation drifts toward them.

### Source-citation discipline

- Cite docs / file paths / log lines for non-trivial claims. Use `file:line` for code references.
- Distinguish cited facts from inferences. Never present inferences as facts.
- State assumptions explicitly before acting on them.

---

## 4. User background (for tailoring explanations)

- DevOps + data-engineering background. Fluent on **backend / containers / Python / SQL / Docker / Linux / shell**.
- **Zero mobile-app experience.** On Flutter / Dart / Android tooling: explain step-by-step, name every file path, show full commands. On backend / Docker / Python: be terse.
- Blunt feedback preferred over diplomatic. Push back when reasoning seems unsound.
- Cite sources (log lines, file paths, doc URLs) to avoid hallucination; explicitly distinguish facts from inferences.
- Before modifying any shell config file (`.zshrc`, `.bashrc`, etc.), grep for existing entries — never add duplicates.

## Graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).


# Skills
- **ctx** (`~/.claude-personal/skills/ctx/SKILL.md`) - session bootstrap: reads CONTEXT.md, DECISIONLOG.md, ROADMAP.md, DEBT.md if present. Trigger: `/ctx`
When the user types `/ctx`, invoke the Skill tool with `skill: "ctx"` before doing anything else.
