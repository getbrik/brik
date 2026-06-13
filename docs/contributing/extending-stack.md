# Extending a Stack

A *stack* is a language ecosystem (`node`, `java`, `python`, `rust`, `dotnet`,
`docker`). Adding one is the most common extension. The build and test stages
dispatch dynamically (`brik.use "stacks.${stack}"`) so no manual wiring is
needed once the files exist.

## Recipe: add a `go` stack

1. **JSON Schema**: add `go` to the `stack` enum in
   `schemas/config/v1/brik.schema.json` and define any stack-specific
   properties.

2. **Stack module**: create `lib/stacks/go.sh` implementing `stacks.go.build`,
   `stacks.go.test_cmd` (returns the test command), and `stacks.go.test`
   (executes it). Build and test live in the same file, one file per stack.

3. **Config module**: create `lib/transverse/config/go.sh` implementing
   `config.go.default` (sensible defaults), `config.go.export_build_vars`
   (export stack-specific build variables), and `config.go.validate_coherence`
   (cross-field validation).

4. **Dynamic dispatch**: nothing to wire. `lib/stages/build.sh` and
   `lib/stages/test.sh` call `brik.use "stacks.${stack}"`, so the new module is
   picked up at runtime.

5. **Doctor**: add Go prerequisite checks to `lib/cli/doctor.sh`.

6. **Example**: create `examples/minimal-go/brik.yml` with a minimal config.

7. **Tests**: add ShellSpec tests under `spec/stacks/go_spec.sh` and
   `spec/transverse/config/go_spec.sh`.

8. **Validate on briklab**: push a Go test project to the
   [briklab](briklab.md) GitLab instance and confirm the full pipeline runs.

## Module loading

When a stage calls `brik.use "stacks.go"`, the loader resolves the `.sh` file
through three levels, first match wins:

1. **Project extensions**: `${BRIK_PROJECT_DIR}/.brik/lib/`
2. **`BRIK_LIB`**: an optional legacy override, skipped when unset
3. **`BRIK_LIB_EXTENSIONS`**: the colon-separated notion paths (`pipeline`,
   `transverse`, `stacks`, `rollout`, `deployments`, `package-managers`, `cli`)

This is module-file resolution, distinct from the three-tier resolution of
*configuration values* (command, tool, stack default) described in the
[configuration overview](../reference/configuration/overview.md#three-tier-resolution).

## See also

- [Layout](layout.md): where `lib/stacks/` and `lib/transverse/config/` sit
- [Extending a stage](extending-stage.md): the rarer case of adding to the fixed flow
- [Architecture](../concepts/architecture.md): the layer model these modules live in
- [Development](development.md): running the tests you add
