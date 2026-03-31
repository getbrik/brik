# Brik

Portable CI/CD pipelines - configure what, not how. One `brik.yml`, any platform.

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
brew install bash yq jq check-jsonschema shellspec shellcheck
```

### Run tests

```bash
# All tests
shellspec

# A specific spec file
shellspec runtime/bash/spec/cli/validate_spec.sh

# With verbose output
shellspec --format documentation
```

Tests are in `runtime/bash/spec/` using [ShellSpec](https://shellspec.info). The `.shellspec` config at the project root sets the shell, spec path, and helper.

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
