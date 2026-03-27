# Cherry-Pick Candidates

Ranked by ease of porting and impact. Updated 2026-03-26.

## Actionable Candidates

### 1. Option truthiness optimization bug — `e92879ea2`

- **Status**: triaged (confirmed present)
- **Upstream PR**: rescript-lang/rescript#7766
- **Impact**: HIGH — generates wrong code for `Some(0)`, `Some(false)`, `Some("")`
- **Difficulty**: EASY (1 line change)
- **File**: `jscomp/core/lam_pass_remove_alias.ml:87-89`
- **Bug**: `Normal_optional` evaluated as `Eval_true` in `id_is_for_sure_true_in_boolean`, but `Some(0)` unboxes to falsy JS value `0`
- **Fix**: Move `Normal_optional` from `Eval_true` to `Eval_unknown`

### 2. Ref assignment hoisted past conditional guard — `d47de1d1a`

- **Status**: triaged (confirmed present)
- **Impact**: HIGH — incorrect runtime behavior
- **Difficulty**: EASY (2 lines + signature widening)
- **File**: `jscomp/core/js_stmt_make.ml:352`
- **Bug**: When if/else branches have identical assignments, the assignment is hoisted above the conditional without checking if the assigned variable appears free in the guard
- **Fix**: Add `free_variables_of_expression` check to the `when` guard

### 3. Extra newline after `if` in JS output — `fa073e8ec`

- **Status**: triaged (confirmed present)
- **Upstream PR**: rescript-lang/rescript#7920
- **Impact**: LOW — cosmetic JS output issue
- **Difficulty**: EASY (1 line removal)
- **File**: `jscomp/core/js_dump.ml:1058`
- **Fix**: Remove `newline cxt;` call after if blocks with empty/trivial else

### 4. Emoji broken in polyvar/label codegen — `05c10e304`

- **Status**: planned
- **Upstream PR**: rescript-lang/rescript#7853
- **Impact**: MEDIUM — emoji/CJK identifiers produce invalid JS
- **Difficulty**: MEDIUM
- **File**: `jscomp/core/js_dump_string.ml:81-85`
- **Bug**: Bytes `\128`-`\255` are unconditionally hex-escaped, breaking multi-byte UTF-8
- **Plan**:
  1. Add `Utf8.classify` to `jscomp/melstd/`
  2. Rewrite escape loop: `for` -> `while` with manual index
  3. Handle UTF-8 sequences in `\128..\255` branch
  4. Add cram test with emoji polyvars

### 5. Allocating constants duplicated in field flattening — `74b4273b4`

- **Status**: discovered (needs verification)
- **Impact**: MEDIUM — potential memory/semantics issues
- **Difficulty**: MEDIUM
- **File**: `jscomp/core/lam_pass_remove_alias.ml:67`
- **Bug**: `Lam.const x` inlines any constant without checking allocation, duplicating `Const_block`/`Const_some`

### 6. Nested Some object loses parens in arrow returns — `87374f1a8`

- **Status**: discovered (confirmed present)
- **Upstream PR**: rescript-lang/rescript#7013
- **Impact**: MEDIUM — incorrect JS for `() => ({...})` patterns with nested Some
- **Difficulty**: MEDIUM
- **File**: `jscomp/core/js_dump.ml:197`
- **Bug**: `exp_need_paren` not recursive, doesn't handle `Optional_block(e, true)` in arrow context
- **Fix**: Make `exp_need_paren` recursive with `~arrow` parameter

## Not Applicable

| Commit | Reason |
|--------|--------|
| `0c49e7917` | Melange lacks `simplify_and_`/`simplify_or_` (untagged variant code) |
| `9263e4f8f` | Already fixed in melange `lam_compile.ml:540` |
| `880ca0c63` | Already fixed in melange `matching.ml:2791` |
| `11b2c2dda` | Already fixed in melange `js_exp_make.ml:1419` |

## Statistics

From the initial scan of 287 upstream commits (since 2024-06-01):
- **38** auto-classified as irrelevant (version bumps, CI, etc.)
- **~30** high-priority bug fixes identified
- **6** confirmed actionable after verification
- **4** found to be already fixed or not applicable
- **~210** candidates/needs_review awaiting triage
