## One character standing in a scene (visual-novel style). A small state machine
## (ABSENT -> ENTERING -> PRESENT -> EXITING -> ABSENT) plus the idle/talk animation clocks.
## advance(dt) is the whole simulation, so tests drive it directly; _process only forwards time.
## Reduced motion (`instant`) skips slides and wobble: state changes complete immediately.
extends Control

const UIArt = preload("res://scripts/ui_art.gd")
const Palette = preload("res://scripts/theme_colors.gd")

enum State { ABSENT, ENTERING, PRESENT, EXITING }

const ENTER_TIME := 0.38
const EXIT_TIME := 0.28

signal exited(actor)

var who := ""
var state: State = State.ABSENT
var side := 1                 ## -1 enters from the left edge, +1 from the right, 0 fades in (the floating Narrator)
var home_x := 0.5             ## resting centre x as a fraction of the stage width
var home_scale := 1.0         ## slot scale (inner slots are a bit smaller)
var floating := false         ## the Narrator hovers above the floor
var expression := "neutral"
var active := false           ## the speaker: steps forward and brightens
var talking := false          ## typewriter / voice is running
var talk_level := 0.0         ## 0..1 mouth/bob drive (voice amplitude when a voice plays, else the typewriter)
var instant := false          ## reduced motion
var progress := 0.0           ## 0..1 through ENTERING (towards 1) or EXITING (towards 0)
var focus := 0.0              ## 0 = background actor, 1 = the speaker (eased)
var clock := 0.0
var blink_left := 0.0
var blinking := false
var _next_blink := 2.5
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7
	visible = false


## Walks in from the edge (or fades in) to its slot.
func enter(p_who: String, p_side: int, p_home_x: float, p_scale: float, p_floating: bool = false) -> void:
	who = p_who
	side = p_side
	home_x = p_home_x
	home_scale = p_scale
	floating = p_floating
	visible = true
	if instant:
		state = State.PRESENT
		progress = 1.0
	else:
		state = State.ENTERING
		progress = 0.0
	focus = 0.0
	_apply_modulate()
	queue_redraw()


## Slides back out. exited(actor) fires when it is gone.
func exit() -> void:
	if state == State.ABSENT or state == State.EXITING:
		return
	active = false
	talking = false
	if instant:
		_finish_exit()
	else:
		state = State.EXITING


func set_active(on: bool) -> void:
	active = on
	if instant:
		focus = 1.0 if on else 0.0
		_apply_modulate()


func set_expression(e: String) -> void:
	expression = e
	queue_redraw()


func is_on_stage() -> bool:
	return state == State.ENTERING or state == State.PRESENT


## Time step of the whole actor. Returns true while something is still animating.
func advance(dt: float) -> bool:
	clock += dt
	match state:
		State.ENTERING:
			progress = minf(1.0, progress + dt / ENTER_TIME)
			if progress >= 1.0:
				state = State.PRESENT
		State.EXITING:
			progress = maxf(0.0, progress - dt / EXIT_TIME)
			if progress <= 0.0:
				_finish_exit()
		State.ABSENT:
			return false
	if not instant:
		focus = move_toward(focus, 1.0 if active else 0.0, dt * 5.0)
		# blinking: a short close every few seconds
		if blinking:
			blink_left -= dt
			if blink_left <= 0.0:
				blinking = false
		else:
			_next_blink -= dt
			if _next_blink <= 0.0:
				blinking = true
				blink_left = 0.12
				_next_blink = _rng.randf_range(2.2, 4.8)
	else:
		blinking = false
	_apply_modulate()
	queue_redraw()
	return state == State.ENTERING or state == State.EXITING or active


func _finish_exit() -> void:
	state = State.ABSENT
	progress = 0.0
	visible = false
	active = false
	exited.emit(self)


func _process(dt: float) -> void:
	if state != State.ABSENT:
		advance(dt)


func _apply_modulate() -> void:
	var p := pose()
	var dim: float = p.dim
	self_modulate = Color(dim, dim, minf(1.0, dim * 1.04), p.alpha)


func _ease(k: float) -> float:
	return 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)


## Where the figure is drawn: {rect, alpha, scale_x, scale_y, dim} for the current state. Pure geometry.
func pose() -> Dictionary:
	var e := _ease(progress)
	var sx := 1.0
	var sy := 1.0
	var bob := 0.0
	if not instant:
		var breathe := sin(clock * 2.1) * 0.006
		sy += breathe
		sx -= breathe * 0.5
		if talking or talk_level > 0.05:
			var k := maxf(talk_level, 0.25 if talking else 0.0)
			sy += sin(clock * 15.0) * 0.012 * k
			sx -= sin(clock * 15.0) * 0.008 * k
			bob = -absf(sin(clock * 7.5)) * 3.0 * k
		if floating:
			bob += sin(clock * 1.7) * 9.0
	var f := focus
	var sc := home_scale * lerpf(0.9, 1.0, f)
	var slide := (1.0 - e) * size.x * 0.9 * float(side)
	return {"scale": sc, "slide": slide, "alpha": e, "dim": lerpf(0.5, 1.0, f), "sx": sx, "sy": sy, "bob": bob - 12.0 * f, "lift": 0.0}


func _draw() -> void:
	if state == State.ABSENT or who == "":
		return
	var p := pose()
	var w := size.x
	var h := size.y
	var sc: float = p.scale * (1.0 if not floating else 0.9)
	var fw := w * sc
	var fh := h * sc
	var cx: float = w * 0.5 + float(p.slide)
	var base_y := h + float(p.bob) - (h * 0.3 if floating else 0.0)
	var a: float = p.alpha
	# soft floor shadow
	if not floating:
		draw_set_transform(Vector2(cx, h - 6.0), 0.0, Vector2(1.0, 0.18))
		draw_circle(Vector2.ZERO, fw * 0.36, Color(0, 0, 0, 0.35 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# squash and stretch about the feet
	draw_set_transform(Vector2(cx, base_y), 0.0, Vector2(p.sx, p.sy))
	var level := talk_level if talk_level > 0.05 else (0.6 * (0.5 + 0.5 * sin(clock * 16.0)) if talking else 0.0)
	UIArt.draw_actor_figure(self, Rect2(Vector2(-fw * 0.5, -fh), Vector2(fw, fh)), who, expression, level, blinking, clock)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
