# python-pytest

`python 3.13` · **CI** · starter

> [!NOTE]
> A Python / pytest project using Ruff for both linting and formatting.

## When to use this
A Python project that runs pytest and enforces Ruff lint + format, leaving the
rest to stack defaults.

## What it configures
- **test** `framework: pytest`.
- **quality** `lint.tool: ruff` (with a config file) and
  `format.tool: "ruff format"` in check mode.
- **security** a dependency-scan severity floor and secret scanning with
  defaults.

## Try it
```bash
brik validate --config examples/python-pytest/brik.yml
```

## Reference
- [`quality`](../../docs/reference/configuration/quality.md) - lint and format
- [`security`](../../docs/reference/configuration/security.md) - dependency and secret scans
