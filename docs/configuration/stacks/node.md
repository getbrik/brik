# Node.js

Brik detects a Node project from `package.json` and runs the package
manager inferred from the lock file. Supported runner image tags:
`22`, `24`.

## Minimum brik.yml

```yaml
version: 1
project:
  name: my-app
  stack: node
```

With nothing else, Brik:

- selects the package manager from the lock file (`npm`, `yarn`, or
  `pnpm`); falls back to `npm install` when no lock file is present;
- runs `<pm> run build` if a `build` script exists;
- runs `npm test` if `scripts.test` is set, otherwise `npx jest`;
- runs `eslint` and `prettier` for the lint sub-stage;
- emits an `lcov` coverage report when `test.reports.enabled: true`.

## Typical brik.yml

```yaml
version: 1
project:
  name: my-app
  stack: node
  stack_version: "22"
build:
  tool: pnpm
test:
  framework: jest
  coverage:
    threshold: 85
  reports:
    enabled: true
quality:
  type_check:
    tool: tsc
package:
  docker:
    image: ghcr.io/org/my-app
publish:
  docker:
    registry: ghcr.io
    username_var: GHCR_USER
    password_var: GHCR_TOKEN
```

## Stack defaults

| Concern | Default |
|---------|---------|
| Build | `<pm> run build` (pm from lock file) |
| Test | `npm test` then `npx jest` fallback |
| Lint | `eslint` |
| Format | `prettier` |
| Coverage format (`auto`) | `cobertura` |

## Gotchas

- **Lock-file detection is strict.** A repo without `package-lock.json`,
  `yarn.lock`, or `pnpm-lock.yaml` falls back to `npm install` (not
  `npm ci`), which means non-reproducible installs. Commit a lock file
  to pin versions.
- **`npm test` vs `npx jest`.** When `scripts.test` is missing from
  `package.json`, Brik falls through to `npx jest` -- this fails
  silently if Jest is not installed.
- **Supported frameworks: `jest`, `vitest`, `npm`.** `vitest` emits
  `npx vitest run` (with `--reporter=junit` and Cobertura coverage when
  `test.reports.enabled: true`); `jest` emits `npx jest` with
  `jest-junit`; `npm` defers to the `scripts.test` entry in
  `package.json`. To use any other runner, declare a `scripts.test`
  entry and set `test.framework: npm`.
- **TypeScript type checking is opt-in.** Brik does not run `tsc`
  unless `quality.type_check.tool: tsc` is declared.
- **`stack_version`** must be a string (`"22"`, not `22`). The schema
  rejects numeric values.

## See also

- [`reference/build.md`](../reference/build.md)
- [`reference/test.md`](../reference/test.md)
- [`reference/quality.md`](../reference/quality.md)
- [`reference/publish.md`](../reference/publish.md)
