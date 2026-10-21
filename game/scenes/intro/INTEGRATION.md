# Boot intro: integration

These are new files only. Nothing existing was edited. The owner of `project.godot`, `main.tscn` and `run_tests.sh` applies the steps below.

## 1. Godot boot splash (`project.godot`, `[application]` section)

Godot 4.7 replaced `boot_splash/fullsize` with `boot_splash/stretch_mode`. The enum is Disabled, Keep, Keep Width, Keep Height, Cover, Ignore, so `0` (Disabled) is the old `fullsize=false`.

```ini
boot_splash/bg_color=Color(0, 0, 0, 1)
boot_splash/show_image=true
boot_splash/image="res://art/intro/boot_splash.png"
boot_splash/stretch_mode=0
boot_splash/use_filter=true
```

`boot_splash.png` is a 64 px black square. The engine splash is plain black, so it flows straight into the studio ident, which also opens on black. Without an image, Godot would show its own logo.

## 2. Route boot through the intro

Choose one of the two options.

**A. Recommended: instance it from `main.tscn`'s root script, at the top of `_ready` (3 lines)**

```gdscript
if DisplayServer.get_name() != "headless" and not "--no-intro" in OS.get_cmdline_user_args():
	var intro := preload("res://scenes/intro/intro_sequence.tscn").instantiate(); intro.next_scene = ""
	add_child(intro); await intro.finished; intro.queue_free()   # CanvasLayer 100 covers the UI
```

The guard matters. The title waits for a tap, and `tests/test_ui_smoke.gd`, `tests/screenshot.gd` and the gate's `run main --quit-after 120` all instantiate `main.tscn`.
- Without the guard, main's `_ready` would stall at the `await`, and those runs would never build the game UI.
- The headless check covers the test suites.
- The windowed `screenshot.gd` needs `-- --no-intro`, or its own skip.
- `test_intro.gd` exercises the intro directly, so the guard costs no coverage.

**B. Alternative: make the intro the main scene (1 line)**

```ini
run/main_scene="res://scenes/intro/intro_sequence.tscn"
```

`intro_sequence.tscn` already has `next_scene = "res://scenes/main.tscn"`. When the player taps through the title, it calls `change_scene_to_file` to load it.

Caveat: the gate's `run main --quit-after 120` would then run the intro instead of `main.tscn`, so it would no longer smoke-test the game. Prefer A.

## 3. Add the test to the strict gate (`run_tests.sh`)

```bash
run intro  yes --script res://tests/test_intro.gd
```

## Behaviour notes

- **Skipping:** one tap, click or key press skips one step: studio ident → title build → title (emits `finished`).
  - Only mouse-button and key **presses** count. Releases and echoes are ignored.
  - Touch is ignored because it arrives as emulated mouse (`emulate_mouse_from_touch=true`).
  - A 0.2 s debounce means one tap equals one skip.
- **Full or short ident:**
  - The first launch of the calendar day plays the full ident (3.0 s). Later launches that day play the short ident (1.0 s).
  - The date is stored in `user://intro_prefs.cfg` under `[intro] last_full_date`, never in the main save.
  - Command-line override: `-- --intro-full` or `-- --intro-short`. A forced mode does not write the prefs file.
- **Reduced motion:** Godot 4.7 has no built-in setting.
  - The intro checks `accessibility/general/reduced_motion` and `aether_sigil/accessibility/reduced_motion`, both off by default.
  - When either is set, the studio ident is a plain reveal of the logo PNG, and the title is a single 0.8 s cross-fade with no spin and no particles.
  - Nothing ever flashes: the "Tap to begin" pulse runs at 0.56 Hz.
- **Swapping the logo:** `studio_intro.tscn` → `logo_texture`.
  - The vector rebuild is measured from the current SMETOOLS PNG.
  - For a logo with different geometry, set `vector_build = false`. The ident then only reveals the texture.

## Re-rendering the preview

```bash
cd game
../engine/Godot_v4.7.2-stable_win64_console.exe --path . --write-movie /tmp/intro.avi --fixed-fps 30 \
  --quit-after 270 res://scenes/intro/intro_sequence.tscn -- --intro-full
ffmpeg -i /tmp/intro.avi -c:v libx264 -pix_fmt yuv420p -crf 18 -c:a aac -b:a 160k ../docs/media/smetools-intro.mp4
```

Movie Maker records at the window size, which is 540×960 because of `window_width_override`.

Regenerate the audio with `python game/audio/intro/tools/make_intro_audio.py`. It is deterministic.
