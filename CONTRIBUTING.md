# Contributing

Thanks for considering contributing to `ascctl`.

## Development

Requirements:

- Swift toolchain (see CI for the currently pinned version)

Common commands:

```bash
swift test
swift build -c release
swift run ascctl --help
```

## Project Goals

`ascctl` is agent-first and spec-driven:

- stdout is always exactly one JSON object (including `--help`)
- stderr is logs/progress only
- the primary workflow is `openapi ops list` -> `openapi op show` -> `openapi op run`

## Testing

- Tests must be offline (no live network calls).
- Prefer URLProtocol mocking for HTTP behavior.

## Pull Requests

- Keep changes scoped and easy to review.
- Update `README.md` for user-facing changes.

