---
name: ascctl
description: "Use when operating Apple App Store Connect via the installed `ascctl` CLI: OpenAPI ops list/show/run/template, spec update, ids lookups, pagination, JSON-pointer selection, and record/replay. Trigger on App Store Connect / ASC / operationId / OpenAPI endpoint execution requests."
---

# ascctl (Agent Playbook)

## Agent Contract v1 (Read This First)

- Parse **stdout only**: it is always exactly one JSON object (success, error, and `--help`).
- Treat **stderr** as logs/progress (`--verbose`, warnings).
- JSON is compact + deterministic (`sortedKeys`). `--pretty` is still JSON.

Exit codes:

- `0` success
- `2` usage / validation / confirm required / spec missing / select not found / non-JSON requires `--out`
- `3` auth/config/credentials/signing
- `4` network/transport
- `5` API non-2xx (HTTP)
- `6` internal/unexpected

## Preflight (Before Any API Call)

1. Ensure the CLI exists:

```bash
command -v ascctl
```

2. Credentials precedence: CLI flags > env vars > config file.

Env vars:

- `ASC_ISSUER_ID`, `ASC_KEY_ID`
- `ASC_PRIVATE_KEY_PATH` (path to `.p8`) or `ASC_PRIVATE_KEY_PEM` (raw PEM)
- `ASC_PROFILE` (profile name in config)

3. Keep a stable local spec path (recommended):

```bash
mkdir -p ~/.cache/ascctl
ascctl openapi spec update --out ~/.cache/ascctl/openapi.oas.json --force
```

In all OpenAPI commands below, prefer:

```bash
--spec ~/.cache/ascctl/openapi.oas.json
```

## Universal Hammer Workflow (OpenAPI-First)

1. Discover operations:

```bash
ascctl openapi ops list --spec ~/.cache/ascctl/openapi.oas.json --details --text builds --method GET
```

2. Inspect one operation:

```bash
ascctl openapi op show --spec ~/.cache/ascctl/openapi.oas.json --id <operationId>
```

3. Generate a ready-to-run template (preferred for agents):

```bash
ascctl openapi op template --spec ~/.cache/ascctl/openapi.oas.json --id <operationId>
```

Use:

- `data.argv` as the canonical invocation (string array, no quoting pitfalls)
- `data.body` as the minimal body skeleton (fill placeholders like `"VALUE"`)
- `data.hints` to learn required params/headers/content-types without reading docs

4. Execute:

```bash
ascctl openapi op run --spec ~/.cache/ascctl/openapi.oas.json --id <operationId> \
  --path-param id=... \
  --query limit=1 \
  --header If-Match=... \
  --select /data/0/id
```

Inputs:

- Path params: `--path-param key=value` (repeatable)
- Query params: `--query key=value` (repeatable)
- Headers: `--header key=value` (repeatable)
- Body: `--body-json '{...}'` or `--body-file /path/to/body.json`

## Guardrails (Do Not Skip)

- Mutating methods (`POST`, `PUT`, `PATCH`, `DELETE`) require `--confirm`.
- Prefer `--dry-run` first to validate request resolution without network.
- If the response is not JSON: you must use `--out <file>` (stdout must stay JSON).
- Debug/offline:
  - `--record <dir>` saves resolved request (no secrets) + response meta + raw bytes
  - `--replay <dir>` replays the same envelope without network

## Token Economy (Default Behaviors)

- Prefer `ascctl ids ...` when you only need an ID and want to continue quickly.
- Prefer `--select /json/pointer` to return only the needed fragment.
- For GET list endpoints: `--paginate` (GET-only) + `--limit N` (default 200). Use `--limit 0` for unlimited.

## Help Is JSON

`ascctl ... --help` returns JSON with the help string inside `data.help`. Never assume raw help text is printed to stdout.

