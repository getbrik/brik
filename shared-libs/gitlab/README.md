# Brik GitLab Shared Library

GitLab CI templates that implement the Brik **fixed flow** pipeline.

## Quick Start

Add this to your `.gitlab-ci.yml`:

```yaml
include:
  - project: 'brik/gitlab-templates'
    ref: v0.1.0
    file: '/templates/pipeline.yml'
```

And create a `brik.yml` in your project root:

```yaml
version: 1

project:
  name: my-app
  stack: node
```

That's it. Your project now has a full CI/CD pipeline.

## Fixed Flow

The pipeline implements this stage sequence:

```
Init -> Release -> Build -> Quality || Security -> Test -> Package -> Deploy -> Notify
```

- **Init**: Detects stack, validates `brik.yml`, sets up environment
- **Release**: Computes semantic version (conditional, on tags)
- **Build**: Compiles/builds via `brik-lib` (`build.run`)
- **Quality**: Lint + format checks (runs in parallel with Security)
- **Security**: Dependency + secret scanning (runs in parallel with Quality)
- **Test**: Runs tests via `brik-lib` (`test.run`)
- **Package**: Container build (conditional, on tags)
- **Deploy**: Deploy to target environment (conditional)
- **Notify**: Pipeline summary (always runs)

Quality and Security run in **parallel** (same GitLab stage with separate `needs`).

## Setup on Your GitLab Instance

### 1. Push the Brik runtime

Create a `brik/brik` project on your GitLab instance and push the Brik source:

```bash
git clone https://github.com/getbrik/brik.git
cd brik
git remote add gitlab http://your-gitlab.com/brik/brik.git
git push gitlab main --tags
```

### 2. Push the GitLab templates

Create a `brik/gitlab-templates` project and push this directory:

```bash
cd shared-libs/gitlab
git init -b main
git add -A
git commit -m "Initial commit"
git remote add origin http://your-gitlab.com/brik/gitlab-templates.git
git push -u origin main
git tag v0.1.0
git push origin v0.1.0
```

### 3. Add the bootstrap file to your project

Create `.gitlab-ci.yml` in your project root (see Quick Start above).

## How It Works

Each GitLab CI job:

1. Installs `yq` and `jq` (if not present in the runner image)
2. Clones the `brik/brik` repo to `/opt/brik`
3. Sources the stage wrapper script
4. Calls `brik.gitlab.run_stage <stage_name>`
5. The stage wrapper invokes `stage.run` from the Brik runtime

The runtime handles logging, context, hooks, error handling, and summary generation.

## Configuration

See the [brik.yml specification](../../docs/specs/01-brik-yml.md) for all configuration options.

### Stack Defaults

When `project.stack` is set, default tools are applied:

| Stack | Build | Test | Lint | Format |
|-------|-------|------|------|--------|
| node | `npm run build` | `jest` | `eslint` | `prettier` |
| java | `mvn package` | `junit` | `checkstyle` | `google-java-format` |
| python | `pip install .` | `pytest` | `ruff` | `ruff format` |

## Requirements

- GitLab CI Runner with Docker executor
- Runner image with `bash`, `git`, `wget` (for yq download)
- `brik/brik` and `brik/gitlab-templates` repos on the same GitLab instance

## Troubleshooting

**yq not found**: The `before_script` downloads yq automatically. If it fails, ensure the runner has internet access or pre-install yq in your runner image.

**Runtime not cloned**: Check that `brik/brik` exists on your GitLab instance and has the correct tag. Verify the runner can access the repo URL.

**Runner not registered**: Ensure the GitLab Runner is registered and has the Docker executor configured.

## Directory Structure

```
shared-libs/gitlab/
  scripts/
    config-reader.sh    -- Reads brik.yml via yq
    condition-eval.sh   -- Evaluates deploy conditions
    stage-wrapper.sh    -- Bridges GitLab CI to stage.run
  templates/
    pipeline.yml        -- Main entry point (stages, defaults, includes)
    jobs/
      init.yml          -- Init stage job
      release.yml       -- Release stage job (conditional)
      build.yml         -- Build stage job
      quality.yml       -- Quality stage job (parallel with security)
      security.yml      -- Security stage job (parallel with quality)
      test.yml          -- Test stage job
      package.yml       -- Package stage job (conditional)
      deploy.yml        -- Deploy stage job (conditional)
      notify.yml        -- Notify stage job (always)
  spec/                 -- ShellSpec tests
```
