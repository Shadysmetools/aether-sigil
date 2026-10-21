# CCGS local patches (Aether Sigil)

Claude Code Game Studios v1.2.0 (commit 05ad7c8, MIT, see `LICENSE-CCGS.txt`)
was installed by copying, not merging: this repo shares no history with the
template. These files differ from upstream. **Re-apply them after any upgrade**:
UPGRADING.md Strategy A2 (`git checkout template/main -- .claude`) overwrites them.

## Why: the code root

Stock CCGS hard-codes the Godot code root to `src/` and assumes `project.godot`
at the repo root. Aether Sigil's Godot project is `game/` (`game/project.godot`,
code in `game/scripts/`, tests in `game/tests/`). Without a patch every CCGS code
scan targets a missing `src/` and reports a false "clean".

The patch adds one key, `engine.code_root` in `project.yaml`, honoured only when
that directory exists (otherwise the stock rules apply).

| File | Change |
|---|---|
| `.claude/hooks/yaml-helper.sh` | `resolve_code_root()` returns `engine.code_root` (source `engine.code_root`) |
| `.claude/scripts/project-state.sh` | same override for the `code_root` / `source_files` rows |
| `.claude/scripts/write-guard.sh` | same override for its code-root list |
| `.claude/rules/{ai-code,gameplay-code,ui-code,test-standards,data-files}.md` | `paths:` globs also match `game/scripts/**`, `game/scenes/**`, `game/tests/**`, `data/**/*.json`, `game/data/**/*.json` |
| `.claude/docs/technical-preferences.md`, `CLAUDE.md`, `docs/engine-reference/godot/VERSION.md` | filled in as `/setup-engine` would |
| `game/CLAUDE.md` | CCGS's `src/CLAUDE.md`, moved to the real code root |

## Known gaps (not patched)

These still assume `src/` or a root `project.godot`. Treat their output for code
as **NOT ASSESSED**, not as a pass:

- `.claude/scripts/content-count.sh`: Godot roots are `assets src`.
- `.claude/scripts/asset-scan.sh`: orphan/missing checks need `src/`.
- `.claude/scripts/project-coherence.sh`: looks for `./project.godot` and 2D nodes under `src/`.
- `.claude/scripts/godot-parse-check.gd`: invoked as `res://.claude/scripts/...`; `.claude/` is not under `res://` (= `game/`). Copy it or pass an absolute path.
- `/setup-engine` §7.5 offers to create a root `project.godot`. **Decline it.**
- Skills that say `tests/unit/...`: the test root here is `game/tests/`, run by `bash game/run_tests.sh` (no gdUnit4).
- `project-state.sh` reports `origin_url absent` inside a git worktree (it reads `.git/config`; a worktree's `.git` is a file).
