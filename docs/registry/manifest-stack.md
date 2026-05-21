# Stack manifest reference

Field-by-field reference for `lib/registry/manifests/stacks/<id>.yml`.

The authoritative contract is
[`schemas/registry/v1/stack.schema.json`](../../schemas/registry/v1/stack.schema.json).
This page is the human-readable companion: what each field does, why
it is there, what consumers look at it.

## Skeleton

```yaml
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: my-stack             # kebab-case, unique
  displayName: My Stack
  owner: my-org            # optional
spec:
  detect:
    markers:
      any: [my-project.toml]
  runner:
    image: ghcr.io/my-org/brik-runner-my-stack
    defaultVersion: "1"
  api:
    required:
      - stacks.<id>.build
      - stacks.<id>.test
```

The three top-level required keys are `apiVersion`, `kind`, `metadata`
plus a `spec` block. Every other section under `spec` is optional but
most stacks declare at least `detect`, `runner`, `api`, and `cache`.

## metadata

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | kebab-case (`^[a-z][a-z0-9-]*$`). Used as namespace key (`registry.stack.<id>`) and as the value of `project.stack` in `brik.yml`. |
| `displayName` | string | yes | Human-readable. Surfaced in CLI output, HTML report. |
| `owner` | string | no | Free-form. Helps consumers route bugs to the right team. |
| `minBrikVersion` | semver | no | Refuse to load if brik runtime is older. Format `<MAJOR>.<MINOR>.<PATCH>`. |
| `maxBrikVersion` | semver | no | Refuse to load if newer. Use sparingly; prefer letting the registry break with a clear error than silently locking out future runtimes. |

## spec.detect

How `stacks.detect <workspace>` finds your stack.

```yaml
detect:
  markers:
    any:
      - package.json     # ANY of these makes the stack match
      - .nvmrc
    all:                  # rarely needed
      - .nvmrc
      - .node-version
```

| Field | Semantics |
|---|---|
| `markers.any` | OR -- the stack matches if at least one file exists in the workspace root. |
| `markers.all` | AND -- the stack matches only if all listed files exist. Combined with `markers.any` via AND across the two. |

Detection is single-pass and rooted at the workspace top: `stacks.detect`
never recurses. If your stack only marks a subdirectory, document the
limitation in your manifest's `displayName` and educate users to set
`project.root` explicitly in `brik.yml`.

## spec.runner

Which container image runs this stack and what versions it ships.

```yaml
runner:
  image: ghcr.io/getbrik/brik-runner-node
  defaultVersion: "22"
  versions: ["22", "24"]
```

| Field | Semantics |
|---|---|
| `image` | Fully-qualified image without tag. The runner image build pipeline pushes one image per `versions[]` value, tagged with that version. |
| `defaultVersion` | The version selected when `brik.yml` omits `project.stackVersion`. |
| `versions` | Allowed values for `project.stackVersion`. Validated at config load time. |

Consumers: `lib/pipeline/runner-images.sh` resolves the image to pull
via `registry.stack.runner_image <id> [--version <v>]`. The Jenkins
wrapper, the GitLab template, and the local wrapper all go through the
same resolver -- the manifest is the only place that knows the image.

## spec.cache

Which paths inside the workspace are package-manager caches that the
runtime should preserve across builds.

```yaml
cache:
  paths:
    - .npm
    - .cache/pip
```

`lib/stacks/_deps.sh::stacks.cache_paths <id>` reads this list.
GitLab's `cache:` block, Jenkins's `brikRunStage`, and the local
wrapper all keep these paths between runs while wiping the rest of the
workspace.

Keep this list narrow. Anything you add increases the persistent
storage footprint of every CI runner.

## spec.frameworks

Maps user-declared framework hints (in `brik.yml` `test.framework`,
`build.tool`, etc.) to the stack that handles them.

```yaml
frameworks:
  test:
    jest:  {stack: node}
    npm:   {stack: node}
  build:
    npm:   {stack: node}
```

The `{stack: node}` form makes it explicit that this framework is
handled by *this* stack. The reverse-lookup
`stacks.detect_from_framework <name>` walks every manifest's
`frameworks` map.

## spec.impact

Glob lists feeding the planner's impact filter. Used by
`brik plan` to decide whether a commit
touches code that this stack cares about.

```yaml
impact:
  source: ["**/*.js", "**/*.ts", "package.json"]
  test:   ["**/*.test.js", "**/*.spec.ts"]
  build:  ["package.json", "tsconfig.json"]
```

| Field | Used by |
|---|---|
| `source` | Generic build/lint/scan impact. |
| `test` | Test stage only (skipping tests when no test file changed). |
| `build` | Build stage; manifest/config files that force a rebuild. |

Globs are matched against the workspace-relative change set produced
by `lib/transverse/changes.sh`.

## spec.api

The Bash module surface the stack exposes. Used by the registry
loader to refuse a stack whose implementation module is missing
exports.

```yaml
api:
  required:
    - stacks.<id>.build
    - stacks.<id>.test
    - stacks.<id>.install_deps
  optional:
    - stacks.<id>.package
```

`registry.stack.api_required <id>` returns the list. The runtime then
checks `declare -f stacks.<id>.build` for each required function and
fails the build with a precise error if any is missing.

## spec.doctor

Tools that `brik doctor` should verify are installed for this stack to
work outside a brik-runner image.

```yaml
doctor:
  tools:
    - npm
    - node
```

`brik doctor` reads `registry.stack.doctor_tools <id>` and shells out
to `command -v <tool>` for each.

## spec.artifacts

Output directories and file patterns the stack produces. Used by the
package stage to know what to archive.

```yaml
artifacts:
  outputDirs: [dist, build]
  patterns:
    - "dist/**/*"
    - "*.tgz"
```

`registry.stack.artifact_output_dirs <id>` / `artifact_patterns <id>`
serve these to consumers.

## spec.system

Host-level requirements the stack depends on (rare; used for stacks
that need a system service like Docker).

```yaml
system:
  requires:
    - docker
```

## Worked example: the node manifest

```yaml
apiVersion: brik.dev/v1
kind: Stack
metadata:
  id: node
  displayName: Node.js
  owner: getbrik
spec:
  detect:
    markers:
      any: [package.json]
  runner:
    image: ghcr.io/getbrik/brik-runner-node
    defaultVersion: "22"
    versions: ["22", "24"]
  cache:
    paths: [.npm]
  frameworks:
    test:
      jest:   {stack: node}
      vitest: {stack: node}
      npm:    {stack: node}
  impact:
    source: ["**/*.js", "**/*.ts", "**/*.tsx", "**/*.jsx", "package.json"]
    test:   ["**/*.test.js", "**/*.test.ts", "**/*.spec.js", "**/*.spec.ts"]
    build:  [package.json, tsconfig.json, .nvmrc]
  api:
    required:
      - stacks.node.build
      - stacks.node.test
      - stacks.node.install_deps
```

The full set of builtin manifests lives in
`lib/registry/manifests/stacks/*.yml`. They are the canonical examples
to copy when authoring a new one.
