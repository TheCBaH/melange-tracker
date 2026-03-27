# Fork Divergence Analysis

## Fork Point

- **Commit**: `6f3256af585f31ea751c51d25f9980b9f8033d2a`
- **Date**: 2021-02-20
- **ReScript PR**: #4963 (`wip_lstring_switch`)
- **Method**: `git merge-base main upstream/master`

## Scale of Divergence

Since the fork, both projects have had 5+ years of independent development:

- **Melange**: ~1700+ commits on top of the fork point
- **ReScript upstream**: ~4000+ commits on top of the fork point

## Areas of Code Overlap

### High overlap (cherry-picks most viable)
- `jscomp/core/js_dump.ml` — JS code printer
- `jscomp/core/js_dump_string.ml` — String escaping for JS output
- `jscomp/core/js_exp_make.ml` — JS expression construction
- `jscomp/core/js_stmt_make.ml` — JS statement construction
- `jscomp/core/lam_compile.ml` — Lambda-to-JS compilation
- `jscomp/core/lam_pass_remove_alias.ml` — Optimization pass

### Medium overlap (need careful adaptation)
- `jscomp/runtime/` — Runtime primitives (melange has additional modules)
- `jscomp/core/lam_convert.ml` — Lambda conversion (PPX interaction differs)

### Low overlap (usually not worth porting)
- `jscomp/ext/` vs `jscomp/melstd/` — Heavily refactored in melange
- PPX code — Different attribute namespaces (`@mel.*` vs `@bs.*`)
- Build system — Completely different (dune vs bsb/ninja)

## Key Differences

| Aspect | Melange | ReScript |
|--------|---------|----------|
| Build system | Dune | bsb/ninja (removed in v13) |
| OCaml version | 5.4 | 4.14 (vendored) |
| Attribute prefix | `@mel.*` | `@bs.*` / `@res.*` |
| Extension lib | `melstd` (in `jscomp/melstd/`) | `ext` (in `compiler/ext/`) |
| Compiler libs | Submodule (`vendor/melange-compiler-libs/`) | Vendored inline |
| Distribution | OPAM | NPM |
| Syntax | OCaml + Reason | ReScript syntax |
| PP module | `Js_pp` | `Ext_pp` |
| Buffer ops | `Buffer.add_string` | `Ext_buffer.add_string` |
| Import style | `open Import` module | Direct `open Ext_*` |

## Commits Already Fixed in Melange

Some upstream fixes have already been independently addressed in melange:

| Upstream commit | Description | Melange status |
|-----------------|-------------|----------------|
| `9263e4f8f` | Redundant switch branches | Fixed at `lam_compile.ml:540` |
| `880ca0c63` | Nondeterminism in pattern matching | Fixed at `matching.ml:2791` |
| `11b2c2dda` | Assert false in neq_null_undefined | Fixed at `js_exp_make.ml:1419` |
| `0c49e7917` | Exponential blowup in simplify_and_ | N/A — melange lacks the affected code |
