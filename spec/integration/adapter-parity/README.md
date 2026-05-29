# Adapter parity (cross-cutting)

These integration specs are NOT a single dependency-graph edge. They assert
that the execution environments (GitLab, Jenkins, local adapters) stay in sync
with the single source of truth they must mirror:

- `adapter_coverage_spec.sh` -- every registry manifest stage is reachable
  from both adapters.
- `plan_adapter_parity_spec.sh` -- the plan.json is identical across adapters.
- `gitlab_needs_parity_spec.sh` -- GitLab `needs[]` match the manifest
  dependency declarations.
- `gitlab_dotenv_parity_spec.sh` -- GitLab `reports.dotenv` is declared on
  every job template.
- `cache_paths_parity_spec.sh` -- stack cache paths are consistent across the
  consumers that reference them.
- `install_spec.sh` -- the install shim integration.

They live here (not under `spec/unit/`) because they are end-to-end across
adapters and the registry, not pure single-notion logic. They have no
`fixture.yml` because they assert parity against the real built-in manifests
and templates rather than a synthesized fixture.
