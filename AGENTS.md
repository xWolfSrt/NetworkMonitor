# NetworkMonitor local maintenance

Read this file, `docs/agent-context/README.md`, then the task-specific upstream docs.

## Source priority
1. Current user instructions and preservation requirements.
2. This local context baseline and verified source/runtime evidence.
3. `CLAUDE.md` and existing `docs/` for upstream contribution and release procedures.

## Rules
- Preserve user settings, history, credentials and unrelated work.
- Use `develop`, tracking `origin/develop`, for ongoing fork development (user decision, 2026-10-27). When isolation is needed, start a `codex/` branch from `develop`. Do not push directly to `main`.
- Local development builds are allowed for an authorized local maintenance task.
- Explicitly authorised fork pushes and integration on `develop` follow the user's scope. Upstream contributions and formal releases still use issue → PR → release. Issues remain disabled on this fork; do not enable repository features or publish releases as a side effect of development.
- Run `make test` and `make app`; use the existing SwiftPM wrapper and signing behavior.
- Never run a real speed test as part of verification.
- Never enable Hotspot mode or install the privileged helper during ordinary development.
- Back up the installed app and local data before replacing an installation. Stop the running copy before backing up its SQLite files.
- Update context when a verified implementation decision changes.

## Routing
- Current state: `docs/agent-context/current-project-state.md`.
- Implementation and validation: `docs/agent-context/work-rules.md`, `docs/development.md`.
- Measurement: `docs/architecture.md`, `docs/decisions.md`, `docs/accuracy-and-battery.md`.
- Privileged behavior: `docs/hotspot-mode.md`, `Scripts/helper-setup.sh`.
- Pending decisions: `docs/agent-context/open-questions.md`.
