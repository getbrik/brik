# Rust

Brik detects a Rust project from `Cargo.toml`. The runner image ships
with `cargo`, `clippy`, `rustfmt`, `cargo-nextest`, and
`cargo-llvm-cov`. Supported runner image tags: `1`.

## Minimum brik.yml

```yaml
version: 1
project:
  name: my-crate
  stack: rust
```

With nothing else, Brik:

- runs `cargo build`;
- runs `cargo test` (the runner image has `cargo-nextest` available
  for the test reports flow);
- runs `clippy` for the lint sub-stage;
- runs `rustfmt` for formatting;
- emits an `lcov` coverage report (via `cargo-llvm-cov`) when
  `test.reports.enabled: true`.

## Typical brik.yml

```yaml
version: 1
project:
  name: my-crate
  stack: rust
build:
  command: cargo build --release --features prod
test:
  command: cargo nextest run --workspace
  coverage:
    threshold: 80
  reports:
    enabled: true
publish:
  cargo:
    registry: brik-cargo
    index: sparse+http://nexus:8081/repository/brik-cargo/
    token_var: CARGO_TOKEN
```

## Stack defaults

| Concern | Default |
|---------|---------|
| Build | `cargo build` |
| Test | `cargo test` |
| Lint | `clippy` |
| Format | `rustfmt` |
| Coverage format (`auto`) | `cobertura` |

## Gotchas

- **Single image tag.** Only `1` is published today; the runner tracks
  the latest stable Rust within that major version. Pin a specific
  toolchain in `rust-toolchain.toml` if reproducibility matters.
- **`cargo nextest` is not the default.** The default `test` runs
  `cargo test`. Use `test.command: cargo nextest run` explicitly when
  you want the parallel runner.
- **Private registries need a sparse index.** `publish.cargo.index`
  must be set to `sparse+<URL>` for any registry that is not
  `crates-io`; the named `registry` is just an alias used by `cargo
  publish`.
- **Workspace tests.** Running tests from a workspace root requires an
  explicit `--workspace` flag in `test.command`; defaults run only the
  current package.

## See also

- [`reference/build.md`](../reference/build.md)
- [`reference/test.md`](../reference/test.md)
- [`reference/quality.md`](../reference/quality.md)
- [`reference/publish.md`](../reference/publish.md)
