# Python

Brik detects a Python project from `pyproject.toml`, `setup.py`, or
`requirements.txt`. The actual build tool is inferred from project
files in priority order: `uv.lock` -> `poetry.lock` (or `[tool.poetry]`)
-> `Pipfile` -> `pyproject.toml` -> `setup.py`. Supported runner image
tags: `3.13`, `3.14`.

## Minimum brik.yml

```yaml
version: 1
project:
  name: my-lib
  stack: python
```

With nothing else, Brik:

- picks the package manager (`uv`, `poetry`, `pipenv`, `pip`) from
  marker files;
- installs dependencies, then runs `python -m build` (or the tool's
  native build command);
- runs `python -m pytest`;
- runs `ruff` for lint and `ruff format` for formatting;
- emits a `cobertura` coverage report when `test.reports.enabled: true`.

## Typical brik.yml

```yaml
version: 1
project:
  name: my-lib
  stack: python
  stack_version: "3.13"
build:
  tool: uv
test:
  framework: pytest
  coverage:
    threshold: 90
  reports:
    enabled: true
quality:
  type_check:
    tool: mypy
publish:
  pypi:
    token_var: PYPI_API_TOKEN
```

## Stack defaults

| Concern | Default |
|---------|---------|
| Build | `uv build`, `poetry build`, `python -m build`, or `pip wheel` (per detector) |
| Test | `python -m pytest` |
| Lint | `ruff` |
| Format | `ruff format` |
| Coverage format (`auto`) | `cobertura` |

## Gotchas

- **`requirements.txt` alone is not enough to build.** Brik will detect
  the stack, but a `pyproject.toml`, `setup.py`, or `Pipfile` must
  also exist for the build to produce an artefact.
- **`uv.lock` wins over `poetry.lock`.** Both files in the same repo
  resolves to `uv` -- Brik does not warn. Remove the unused lock file
  to avoid confusion.
- **Type checking is opt-in.** `quality.type_check.tool: mypy` (or
  `pyright`) is required to run a type check; Brik never auto-detects
  this.
- **`stack_version`** must be a quoted string (`"3.13"`, not `3.13`,
  which the schema rejects as a non-string).

## See also

- [`reference/build.md`](../build.md)
- [`reference/test.md`](../test.md)
- [`reference/quality.md`](../quality.md)
- [`reference/publish.md`](../publish.md)
