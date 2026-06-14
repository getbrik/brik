# minimal-node

`node` · **CI** · starter

> [!NOTE]
> The smallest valid brik.yml -- everything by auto-detection.

## When to use this
Your first brik.yml. Start here, then copy blocks from the richer examples as
you need them.

## What it configures
- **project** name and `stack: node` (Brik also infers the stack from a
  `package.json`).
- **test** `framework: npm`.

Build tool, lint, and packaging all come from the Node stack defaults at
runtime.

## Try it
```bash
brik validate --config examples/minimal-node/brik.yml
```

## Reference
- [`project`](../../docs/reference/configuration/project.md) - identity and stack
- [`test`](../../docs/reference/configuration/test.md) - framework selection
