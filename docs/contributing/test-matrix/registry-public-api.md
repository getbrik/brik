# Public API surface: `registry`

> Source: `lib/registry/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

| Function| Source file |
|---|---|
| `_registry._cache_path` | `registry/_loader.sh:60` |
| `_registry._reset` | `registry/_loader.sh:68` |
| `_registry._reload` | `registry/_loader.sh:95` |
| `_registry._load` | `registry/_loader.sh:100` |
| `_registry._load_stacks` | `registry/_loader.sh:142` |
| `_registry._load_stages` | `registry/_loader.sh:191` |
| `_validator._fail` | `registry/_validator.sh:23` |
| `_validator._kind` | `registry/_validator.sh:28` |
| `_validator._schema` | `registry/_validator.sh:41` |
| `registry.validate_manifest` | `registry/_validator.sh:53` |
| `registry.validate_all_manifests` | `registry/_validator.sh:88` |
| `_registry._explode` | `registry/registry.sh:14` |
| `registry.use` | `registry/registry.sh:20` |
| `registry.stack.list` | `registry/registry.sh:24` |
| `registry.stack.exists` | `registry/registry.sh:30` |
| `registry.stack.display_name` | `registry/registry.sh:37` |
| `registry.stack.markers` | `registry/registry.sh:43` |
| `registry.stack.markers_glob` | `registry/registry.sh:49` |
| `registry.stack.cache_paths` | `registry/registry.sh:55` |
| `registry.stack.runner_image` | `registry/registry.sh:61` |
| `registry.stack.runner_default_version` | `registry/registry.sh:67` |
| `registry.stack.runner_versions` | `registry/registry.sh:73` |
| `registry.stack.module` | `registry/registry.sh:79` |
| `registry.stack.api_required` | `registry/registry.sh:85` |
| `registry.stack.api_optional` | `registry/registry.sh:91` |
| `registry.stack.doctor_tools` | `registry/registry.sh:99` |
| `registry.stack.artifact_output_dirs` | `registry/registry.sh:107` |
| `registry.stack.artifact_patterns` | `registry/registry.sh:115` |
| `registry.stack.impact_source` | `registry/registry.sh:124` |
| `registry.stack.impact_test` | `registry/registry.sh:132` |
| `registry.stack.impact_build` | `registry/registry.sh:141` |
| `registry.stack.detect` | `registry/registry.sh:147` |
| `registry.stack.detect_from_framework` | `registry/registry.sh:168` |
| `registry.stage.list` | `registry/registry.sh:182` |
| `registry.stage.exists` | `registry/registry.sh:188` |
| `registry.stage.resolve_alias` | `registry/registry.sh:203` |
| `_registry._resolve_stage_id_or_die` | `registry/registry.sh:224` |
| `registry.stage.display_name` | `registry/registry.sh:241` |
| `registry.stage.function` | `registry/registry.sh:247` |
| `registry.stage.module` | `registry/registry.sh:253` |
| `registry.stage.placement_slot` | `registry/registry.sh:259` |
| `registry.stage.placement_group` | `registry/registry.sh:265` |
| `registry.stage.after` | `registry/registry.sh:271` |
| `registry.stage.before` | `registry/registry.sh:277` |
| `registry.stage.runner_class` | `registry/registry.sh:283` |
| `registry.stage.gate_mode` | `registry/registry.sh:289` |
| `registry.stage.gate_opt_in_flag` | `registry/registry.sh:295` |
| `registry.stage.gate_contexts` | `registry/registry.sh:301` |
| `registry.stage.is_destructive` | `registry/registry.sh:307` |
| `registry.stage.aliases` | `registry/registry.sh:313` |
| `registry.stage.api_required` | `registry/registry.sh:319` |
| `registry.stage.impact_changes` | `registry/registry.sh:329` |
| `registry.stage.impact_use_stack_impact` | `registry/registry.sh:338` |
| `registry.runner_class.image` | `registry/registry.sh:375` |
| `registry.explain` | `registry/registry.sh:428` |

## Total

**55 unique public functions** in notion `registry`.
