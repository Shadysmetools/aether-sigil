## Boot intro: SMETOOLS studio ident -> Aether Sigil title. Emits `finished` when the player
## taps through the title (or everything is skipped).
##
## Input: one tap / click / key skips the current step (studio ident -> title build -> title).
## Touch arrives as emulated mouse (project has pointing/emulate_mouse_from_touch=true), so only
## mouse-button and key presses are handled, with a short debounce so one tap = one skip.
##
## Full vs short: `play_full_intro` is true on the first launch of the calendar day, otherwise the
## studio ident is the ~1 s short version. The date lives in its own file, `user://intro_prefs.cfg`
## (never the main save). Override from the command line with `-- --intro-full` / `--intro-short`.
extends CanvasLayer

## Emitted once, after the title has been tapped through.
signal finished

const STUDIO_SCENE := preload("res://scenes/intro/studio_intro.tscn")
const TITLE_SCENE := preload("res://scenes/intro/title_intro.tscn")
const PREFS_PATH := "user://intro_prefs.cfg"
const SKIP_DEBOUNCE := 0.2  # s
const MAX_FULL_SECONDS := 5.0  # hard ceiling for the studio ident

## Where to go when this scene is the running main scene and the player taps through.
## Ignored when the sequence is instanced inside another scene (then just listen to `finished`).
@export_file("*.tscn") var next_scene := ""
## Injected by tests; empty = real values.
@export var prefs_path := PREFS_PATH
@export var today_override := ""
## "", "full" or "short". Empty = decide from prefs / command line.
@export var force_mode := ""

## Resolved on _ready: true = full ~3 s ident, false = ~1 s short ident.
var play_full_intro := true
## "studio", "title" or "done".
var step := ""
var studio: Node
var title: Node
var _since_skip := 999.0


func _ready() -> void:
	play_full_intro = _resolve_full()
	_start_studio()


func _process(delta: float) -> void:
	_since_skip += delta


func _input(event: InputEvent) -> void:
	if step != "done" and is_skip_event(event):
		get_viewport().set_input_as_handled()
		skip()


## true for a fresh press of a mouse button (incl. emulated touch) or a key; never releases/echo.
static func is_skip_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventKey:
		return event.pressed and not event.echo
	return false


## Skips the current step (debounced).
func skip() -> void:
	if _since_skip < SKIP_DEBOUNCE or step == "done":
		return
	_since_skip = 0.0
	if step == "studio" and studio:
		studio.skip()
	elif step == "title" and title:
		title.skip()


## Whether today's launch should get the full intro, reading/writing the prefs file.
static func should_play_full(path: String, today: String) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return true
	return str(cfg.get_value("intro", "last_full_date", "")) != today


## Records that the full intro played `today`.
static func mark_full_played(path: String, today: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep any other keys
	cfg.set_value("intro", "last_full_date", today)
	cfg.save(path)


func _resolve_full() -> bool:
	var args := OS.get_cmdline_user_args()
	var mode := force_mode
	if mode == "":
		if "--intro-full" in args:
			mode = "full"
		elif "--intro-short" in args:
			mode = "short"
	if mode != "":
		return mode == "full"  # forced: leave the prefs file alone
	var today := today_override if today_override != "" else Time.get_date_string_from_system()
	var full := should_play_full(prefs_path, today)
	if full:
		mark_full_played(prefs_path, today)
	return full


func _start_studio() -> void:
	step = "studio"
	studio = STUDIO_SCENE.instantiate()
	studio.short_mode = not play_full_intro
	studio.finished.connect(_on_studio_finished, CONNECT_ONE_SHOT)
	add_child(studio)


func _on_studio_finished() -> void:
	studio.queue_free()
	studio = null
	step = "title"
	title = TITLE_SCENE.instantiate()
	title.finished.connect(_on_title_finished, CONNECT_ONE_SHOT)
	add_child(title)


func _on_title_finished() -> void:
	step = "done"
	finished.emit()
	if next_scene != "" and get_tree().current_scene == self and ResourceLoader.exists(next_scene):
		get_tree().change_scene_to_file.call_deferred(next_scene)
