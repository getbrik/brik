# Development

Working on Brik itself: prerequisites, the Makefile, running tests, and the test
strategy.

## Prerequisites

```bash
brew install bash yq jq shellspec shellcheck kcov
```

`jv` (the JSON Schema validator) is not in Homebrew core. Install the static
binary from the [upstream releases](https://github.com/santhosh-tekuri/jsonschema/releases):
pick the `darwin-arm64` or `darwin-amd64` archive, extract, and place `jv` on
your `PATH` (for example `~/.local/bin/jv`).

## Makefile targets

| Target | What it does |
|--------|--------------|
| `make help` | Show available targets |
| `make test` | Run all ShellSpec tests (parallel) |
| `make test-quick` | Run tests, stop on first failure |
| `make lint` | Run ShellCheck on all production scripts |
| `make coverage` | Run tests with a kcov coverage report (`coverage/index.html`) |
| `make validate` | Validate every example `brik.yml` |
| `make validate-docs` | Validate every fenced `yaml` block under `docs/configuration/` |
| `make regen-docs` | Regenerate the auto-managed Quick reference tables from the schema |
| `make check-docs-drift` | Verify the auto-managed tables match the schema (CI gate) |
| `make check` | Full pre-commit gate: `lint + coverage + validate + validate-docs + check-docs-drift` |
| `make metrics` | Run shellmetrics on production scripts |
| `make install` / `make uninstall` | Symlink `bin/brik` into `/usr/local/bin` (dev mode) |
| `make clean` | Remove the generated `coverage/` directory |

## Running tests

```bash
# All tests (parallel)
make test

# Or directly with ShellSpec
shellspec

# A specific spec file
shellspec spec/cli/validate_spec.sh

# With documentation-format output
shellspec --format documentation

# With coverage
make coverage   # report in coverage/index.html
```

Tests live in `spec/` and `shared-libs/*/spec/`, using
[ShellSpec](https://shellspec.info). The `.shellspec` config at the repo root
sets the shell, the spec path (`--default-path "**/spec"`), and the helper.

> On macOS, `ulimit -n 1024` is required when running kcov directly. The
> Makefile's `coverage` target handles this automatically. See
> [kcov#293](https://github.com/SimonKagstrom/kcov/issues/293).

## Test strategy

Brik tests at three levels:

- **Unit tests (ShellSpec).** Every source file in `lib/` has a corresponding
  `_spec.sh` in `spec/`, covering runtime modules, library functions, and stage
  entry points in isolation.
- **Shared library tests (ShellSpec).** Tests under `shared-libs/*/spec/` verify
  that the platform templates and wrappers read configuration correctly and
  invoke `stage.run`.
- **End-to-end tests (briklab).** Full pipeline validation on a real GitLab CE
  instance with a runner and a container registry. See [briklab.md](briklab.md).

Coverage is measured by kcov and must stay at or above 80%. Every source file
passes ShellCheck.

## Continuous integration

GitHub Actions runs three jobs on every push and pull request:

- **lint** -- ShellCheck on all Bash source files.
- **test** -- the full ShellSpec suite plus kcov coverage uploaded to Codecov.
- **metrics** -- shellmetrics badge generation (push to `main` only).

A separate **Docs drift** workflow runs `make validate-docs` and
`make check-docs-drift` when `docs/configuration/`, the schema, or the doc
scripts change.

## See also

- [Layout](layout.md) -- the domain notions and the `lib/` tree (ten domain directories)
- [Extending a stack](extending-stack.md) -- add a language ecosystem
- [Extending a stage](extending-stage.md) -- add to the fixed flow
- [Briklab](briklab.md) -- the end-to-end test infrastructure
