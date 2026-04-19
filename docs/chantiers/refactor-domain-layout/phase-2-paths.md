# Phase 2 - Inventory of hardcoded path references

**Date:** 2026-04-19
**Baseline commit:** f31b486 (end of Phase 1)

## Totals

192 hits across 96 files (much larger than the ~38 initial estimate; most hits
are self-references inside `runtime/bash/spec/` Include directives and path
constructions).

| Category | Files | Hits |
|----------|-------|------|
| spec (Include + path literals in tests) | 78 | 133 |
| shared-libs (common, gitlab, jenkins, local) | 8 | 22 |
| root (bin/brik, Makefile, .shellspec, README, codecov) | 5 | 18 |
| docs | 3 | 13 |
| CI (.github/workflows/ci.yml) | 1 | 3 |
| prod (runtime/bash/lib/core/_loader.sh, deploy/profile.sh) | 2 | 3 |
| scripts | 1 | 1 |

## Strategy

After `git mv runtime/bash/{lib,spec} {lib,spec}`, run a single global sed
replacing the string `runtime/bash/lib` -> `lib` and `runtime/bash/spec` -> `spec`
across all tracked files, then verify zero residual hits.
