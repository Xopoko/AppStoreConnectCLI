# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0

Initial public release.

- Agent Contract v1: stdout is always a single JSON object; stderr is logs only; stable exit codes.
- Spec-driven workflow: `openapi ops list` -> `openapi op show` -> `openapi op run`.
- `openapi op run`: preflight validation, `--confirm` for mutating methods, `--paginate` + `--limit`, `--select`, `--record`/`--replay`.
- `openapi op template`: generates minimal `body` skeleton + runnable `argv`.
- `openapi spec update`: supports Apple ZIP, raw OpenAPI JSON, and `file://...` sources.
- `ids` helpers for fast ID lookups.

