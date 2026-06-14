# rust-cargo

`rust 1.83` · **CI** · starter

> [!NOTE]
> A minimal Rust / Cargo project -- the Rust counterpart of minimal-node.

## When to use this
Your first Rust brik.yml. Cargo build, Clippy lint, and rustfmt all come from
the Rust stack defaults.

## What it configures
- **project** name, `stack: rust`, and `stack_version: "1.83"`.
- **test** `framework: cargo`.

## Try it
```bash
brik validate --config examples/rust-cargo/brik.yml
```

## Reference
- [`project`](../../docs/reference/configuration/project.md) - identity and stack
- [`test`](../../docs/reference/configuration/test.md) - framework selection
