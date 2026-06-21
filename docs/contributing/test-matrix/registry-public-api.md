# Public API surface: `registry`

> Source: `lib/registry/**/*.sh`.

## Public functions

Format: `<notion>.<submodule>.<verb>` (convention layout.md).

<!-- BEGIN AUTO-GENERATED: public-api -->
| Function| Source file |
|---|---|
| `_registry._cache_path` | `registry/_loader.sh:75` |
| `_registry._reset` | `registry/_loader.sh:83` |
| `_registry._reload` | `registry/_loader.sh:119` |
| `_registry._load` | `registry/_loader.sh:124` |
| `_registry._load_stacks` | `registry/_loader.sh:168` |
| `_registry._load_providers` | `registry/_loader.sh:219` |
| `_registry._load_contracts` | `registry/_loader.sh:248` |
| `_registry._load_stages` | `registry/_loader.sh:267` |
| `_validator._fail` | `registry/_validator.sh:24` |
| `_validator._kind` | `registry/_validator.sh:29` |
| `_validator._schema` | `registry/_validator.sh:42` |
| `registry.validate_manifest` | `registry/_validator.sh:56` |
| `registry.validate_all_manifests` | `registry/_validator.sh:97` |
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
| `registry.stack.detect_from_framework` | `registry/registry.sh:172` |
| `registry.stage.list` | `registry/registry.sh:186` |
| `registry.stage.exists` | `registry/registry.sh:192` |
| `registry.stage.resolve_alias` | `registry/registry.sh:207` |
| `_registry._resolve_stage_id_or_die` | `registry/registry.sh:228` |
| `registry.stage.display_name` | `registry/registry.sh:245` |
| `registry.stage.function` | `registry/registry.sh:251` |
| `registry.stage.module` | `registry/registry.sh:257` |
| `registry.stage.placement_slot` | `registry/registry.sh:263` |
| `registry.stage.placement_group` | `registry/registry.sh:269` |
| `registry.stage.after` | `registry/registry.sh:275` |
| `registry.stage.before` | `registry/registry.sh:281` |
| `registry.stage.runner_class` | `registry/registry.sh:287` |
| `registry.stage.needs_docker` | `registry/registry.sh:296` |
| `registry.stage.gate_mode` | `registry/registry.sh:302` |
| `registry.stage.gate_opt_in_flag` | `registry/registry.sh:308` |
| `registry.stage.gate_contexts` | `registry/registry.sh:314` |
| `registry.stage.is_destructive` | `registry/registry.sh:320` |
| `registry.stage.aliases` | `registry/registry.sh:326` |
| `registry.stage.api_required` | `registry/registry.sh:332` |
| `registry.stage.impact_changes` | `registry/registry.sh:342` |
| `registry.stage.impact_use_stack_impact` | `registry/registry.sh:351` |
| `registry.provider.list` | `registry/registry.sh:364` |
| `registry.provider.exists` | `registry/registry.sh:370` |
| `registry.provider.display_name` | `registry/registry.sh:377` |
| `registry.provider.capability` | `registry/registry.sh:383` |
| `registry.provider.binding` | `registry/registry.sh:389` |
| `registry.provider.module` | `registry/registry.sh:398` |
| `registry.provider.endpoint_kind` | `registry/registry.sh:407` |
| `registry.provider.contract` | `registry/registry.sh:413` |
| `registry.provider.tools` | `registry/registry.sh:421` |
| `registry.provider.for_capability` | `registry/registry.sh:428` |
| `registry.contract.list` | `registry/registry.sh:445` |
| `registry.contract.exists` | `registry/registry.sh:451` |
| `registry.contract.capability` | `registry/registry.sh:459` |
| `registry.contract.operations` | `registry/registry.sh:466` |
| `registry.runner_class.image` | `registry/registry.sh:507` |
| `registry.explain` | `registry/registry.sh:553` |

## Total

**72 unique public functions** in notion `registry`.
<!-- END AUTO-GENERATED -->
