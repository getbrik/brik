<p align="center">
  <b><font size="6">Brik</font></b>
  <!-- TODO: Replace with logo when available -->
  <!-- <img src="assets/brik.svg" alt="Brik"> -->
</p>

<p align="center">
  <b>Portable CI/CD pipelines - configure what, not how. One brik.yml, any platform.</b>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-blue?style=for-the-badge&labelColor=2b2d42&color=4a90d9" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/getbrik/brik/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/getbrik/brik/ci.yml?label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/getbrik/brik"><img src="https://img.shields.io/codecov/c/github/getbrik/brik" alt="Coverage"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-blue" alt="License"></a>
</p>

<p align="center">
  <a href="https://github.com/getbrik/brik/issues">Issues</a> ·
  <a href="https://github.com/getbrik/briklab">Briklab</a>
</p>

## How it works

1. **Configure** your project in `brik.yml` - stack, tools, thresholds, deploy targets
2. **Add** a bootstrap file (1-12 lines) for your CI platform
3. **Push** - the shared library reads your config and runs the fixed pipeline

```
Init -> Release -> Build -> Quality | Security -> Test -> Package -> Deploy -> Notify
```

## Architecture

```
brik.yml           project configuration (stack, tools, thresholds)
Shared Library     per platform (GitLab, Jenkins, GitHub Actions, Azure DevOps)
brik-lib           reusable CI/CD functions (Bash)
Bash Runtime       stage lifecycle, logging, hooks, error handling
```

## Development

### Prerequisites

```bash
brew install bash yq jq check-jsonschema shellspec shellcheck kcov
```

### Run tests

```bash
# All tests
shellspec

# A specific spec file
shellspec runtime/bash/spec/cli/validate_spec.sh

# With verbose output
shellspec --format documentation

# With coverage (requires kcov)
ulimit -n 1024 && shellspec --kcov
# Report in coverage/index.html
```

Tests are in `runtime/bash/spec/` using [ShellSpec](https://shellspec.info). The `.shellspec` config at the project root sets the shell, spec path, and helper.

> **Note:** `ulimit -n 1024` is required on macOS where the default file descriptor limit is too high for kcov's `dup2()` call. See [kcov#293](https://github.com/SimonKagstrom/kcov/issues/293).

### Validate examples

```bash
# Single file
bin/brik validate --config examples/minimal-node/brik.yml

# All examples
for f in examples/*/brik.yml; do bin/brik validate --config "$f"; done
```

### Lint

```bash
shellcheck bin/brik
```

## Status

Early development - Milestone 0 (foundation + schema).

## Related

- [briklab](https://github.com/getbrik/briklab) - local Docker infrastructure for testing Brik pipelines

## License

[MPL-2.0](LICENSE)
