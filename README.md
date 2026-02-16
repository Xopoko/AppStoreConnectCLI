# App Store Connect CLI (`ascctl`)

Agent-first, spec-driven CLI for the App Store Connect API.

Disclaimer: This project is not affiliated with Apple. Apple, App Store, and App Store Connect are trademarks of Apple Inc.

The CLI surface is intentionally small:

- `ascctl config` (init/show)
- `ascctl auth` (validate)
- `ascctl openapi` (the product: ops list/show/run/template + pinned spec)
- `ascctl ids` (minimal ID-oriented sugar)

## Agent Contract v1 (Default, Global)

- **stdout**: always exactly **one JSON object** (success, error, and `--help` too)
- **stderr**: logs/progress only (`--verbose`, warnings)
- JSON is compact + deterministic (`sortedKeys`). Use `--pretty` to pretty-print (still JSON).

Envelope:

```json
{"ok":true,"command":"openapi.op.run","data":{...},"meta":{...}}
{"ok":false,"command":"openapi.op.run","error":{"code":"...","message":"...","status":422,"details":{...}},"meta":{...}}
```

Exit codes:

- `0` success
- `2` usage / validation / confirm required / spec missing / select pointer not found / non-JSON requires `--out`
- `3` auth/config/credentials/signing
- `4` network/transport
- `5` API non-2xx (HTTP)
- `6` internal/unexpected

## Installation

### Homebrew (macOS + Linux)

```bash
brew tap Xopoko/tap
brew install ascctl
```

### Script (macOS + Linux)

Install the latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/Xopoko/AppStoreConnectCLI/main/install.sh | bash
```

Install a specific version:

```bash
curl -fsSL https://raw.githubusercontent.com/Xopoko/AppStoreConnectCLI/main/install.sh | bash -s -- --version v0.1.1
```

If your chosen `--bin-dir` isn't on PATH, re-run with `--update-path` (adds it to `~/.zshrc` or `~/.bashrc`).

Quick check:

```bash
ascctl --help | python3 -c 'import sys,json; print(json.load(sys.stdin)["ok"])'
```

## Agent Skill (Recommended)

This repo includes an agent skill at `skills/ascctl` that acts as a compact playbook for operating `ascctl` safely and efficiently:

- stable JSON I/O contract (parse stdout only)
- universal OpenAPI workflow (`ops list` → `op show` → `op template` → `op run`)
- token-efficient patterns (`ids`, `--select`, `--paginate --limit`, `--record/--replay`)

Install the skill into your local skills directory:

```bash
SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
```

Option A (copy):

```bash
SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
mkdir -p "$SKILLS_DIR"
rm -rf "$SKILLS_DIR/ascctl"
cp -R skills/ascctl "$SKILLS_DIR/ascctl"
```

Option B (symlink, best for updating from git):

```bash
SKILLS_DIR="${CODEX_HOME:-$HOME/.codex}/skills"
mkdir -p "$SKILLS_DIR"
rm -rf "$SKILLS_DIR/ascctl"
ln -s "$(pwd)/skills/ascctl" "$SKILLS_DIR/ascctl"
```

Option C (no clone, install via raw files):

```bash
SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/ascctl"
mkdir -p "$SKILL_DIR/agents"
curl -fsSL https://raw.githubusercontent.com/Xopoko/AppStoreConnectCLI/main/skills/ascctl/SKILL.md -o "$SKILL_DIR/SKILL.md"
curl -fsSL https://raw.githubusercontent.com/Xopoko/AppStoreConnectCLI/main/skills/ascctl/agents/openai.yaml -o "$SKILL_DIR/agents/openai.yaml"
```

Verify:

```bash
command -v ascctl
ascctl --help | python3 -c 'import sys,json; print(json.load(sys.stdin)["ok"])'
mkdir -p ~/.cache/ascctl
ascctl openapi spec update --out ~/.cache/ascctl/openapi.oas.json --force
```

## Quick Start

1. Create config (optional, env vars also work):

```bash
ascctl config init
```

2. Provide credentials (any of the following):

- Env vars:
  - `ASC_ISSUER_ID`, `ASC_KEY_ID`
  - `ASC_PRIVATE_KEY_PATH` (path to `.p8`) or `ASC_PRIVATE_KEY_PEM` (raw PEM content)
  - `ASC_PROFILE` (profile name in config)
- CLI flags override everything:
  - `--issuer-id`, `--key-id`, `--private-key-path`

3. Validate:

```bash
ascctl auth validate
```

## OpenAPI Spec (Downloaded)

`ascctl` uses Apple’s App Store Connect OpenAPI spec stored locally as `./openapi.oas.json` (not committed).

Update it (by default downloads Apple’s ZIP and extracts `openapi.oas.json`). You can also pass `--url` pointing to either the ZIP or a raw OpenAPI JSON file (including `file://...`):

```bash
ascctl openapi spec update
ascctl openapi spec update --url file:///path/to/openapi.json --out openapi.oas.json --force
```

## OpenAPI Workflow (Universal Hammer)

1. List operations:

```bash
ascctl openapi ops list --all
ascctl openapi ops list --tag Apps --method GET --text builds --details
```

2. Inspect an operation:

```bash
ascctl openapi op show --id <operationId>
ascctl openapi op show --method GET --path /v1/apps/{id}
```

3. Generate a ready-to-run template:

```bash
ascctl openapi op template --id <operationId>
```

Returns `data.argv` (as a string array) + a minimal `data.body` skeleton (when applicable).

4. Run an operation:

```bash
ascctl openapi op run --method GET --path /v1/apps --query limit=1
```

Notes:

- Mutating methods (`POST`, `PUT`, `PATCH`, `DELETE`) require `--confirm` (unless `--dry-run` or `--replay`).
- Non-JSON responses are **never** printed to stdout; use `--out <file>`.

Common flags:

- `--body-json`, `--body-file`
- `--paginate` (GET-only) + `--limit` (default `200`, `0` = unlimited)
- `--select /json/pointer` (returns only `data.result`)
- `--record <dir>` / `--replay <dir>`

## `ascctl ids` (Minimal Sugar)

Fast ID resolvers for “fetch an id and continue”:

```bash
ascctl ids app --bundle-id com.example.app
ascctl ids bundle-id --identifier com.example.app
ascctl ids version --app-id <appId> --platform IOS --version 1.2.3
ascctl ids build --app-id <appId> --latest
ascctl ids beta-group --app-id <appId> --name "Internal"
ascctl ids tester --email a@b.com
```

## Build/Test

```bash
swift test
swift run ascctl --help
```
