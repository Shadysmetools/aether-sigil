## Presentation timeline for the 3D board. The rules (GameState) change instantly; the board turns
## each change into a BEAT ({dur, cues: [[time, Callable], ...], end: Callable}) and plays beats one
## after another. `end` is the authoritative settle (statue pose, shown HP, KO'd actors freed), so a
## skipped or instant beat lands in exactly the state a fully played one does.
## instant = true (headless, tests): beats never wait — push() runs `end` at once, so animation can
## never block game logic. Time comes in through step(dt); the board scales dt (hold-to-2x, hit-stop,
## slow-mo) so nothing here touches Engine.time_scale.
extends RefCounted

## Tweens a property (float / Vector3 / Color) of one object through segments, driven by step(dt).
class Tracks:
	extends RefCounted
	var target: Object
	var _t: Dictionary = {}   ## prop -> {segs: [[dur, to, ease]], i, t, from}

	func _init(obj: Object) -> void:
		target = obj

	## Segments: [[duration, to_value], ...] or [[duration, to_value, "in"|"out"|"lin"|"io"], ...].
	func seq(prop: String, segs: Array) -> void:
		if segs.is_empty():
			return
		_t[prop] = {"segs": segs.duplicate(), "i": 0, "t": 0.0, "from": target.get(prop)}

	func to(prop: String, value: Variant, dur: float, ease := "io") -> void:
		seq(prop, [[dur, value, ease]])

	func has(prop: String) -> bool:
		return _t.has(prop)

	func busy() -> bool:
		return not _t.is_empty()

	static func _ease(f: float, kind: String) -> float:
		match kind:
			"lin": return f
			"in": return f * f
			"out": return 1.0 - (1.0 - f) * (1.0 - f)
			"back": return 1.0 + 2.70158 * pow(f - 1.0, 3.0) + 1.70158 * pow(f - 1.0, 2.0)
		return f * f * (3.0 - 2.0 * f)

	func step(dt: float) -> void:
		for prop in _t.keys():
			var tr: Dictionary = _t[prop]
			var left := dt
			while true:
				var seg: Array = tr.segs[tr.i]
				var dur: float = maxf(float(seg[0]), 0.0001)
				var need: float = dur - float(tr.t)
				var used := minf(left, need)
				tr.t = float(tr.t) + used
				left -= used
				var f := clampf(float(tr.t) / dur, 0.0, 1.0)
				target.set(prop, lerp(tr.from, seg[1], _ease(f, str(seg[2]) if seg.size() > 2 else "io")))
				if f < 1.0:
					break
				tr.from = seg[1]
				tr.i = int(tr.i) + 1
				tr.t = 0.0
				if int(tr.i) >= tr.segs.size():
					_t.erase(prop)
					break
				if left <= 0.0:
					break

	## Jumps every running track to its final value.
	func settle() -> void:
		for prop in _t.keys():
			var segs: Array = _t[prop].segs
			target.set(prop, segs[-1][1])
		_t.clear()

	func cancel(prop: String) -> void:
		_t.erase(prop)


var instant := false
var beats: Array = []
var current: Variant = null
var t := 0.0
var _cue := 0
var played := 0          ## beats finished (played, skipped or instant) — for tests


## Beat dictionary: {name, dur, cues: [[t, Callable]], end: Callable}. Cues are sorted here.
func push(beat: Dictionary) -> void:
	var cues: Array = beat.get("cues", [])
	cues.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	beat["cues"] = cues
	if instant:
		_end(beat)
		return
	beats.append(beat)


func busy() -> bool:
	return current != null or not beats.is_empty()


## Name of the beat playing now ("" when idle).
func now_playing() -> String:
	return str(current.get("name", "")) if current != null else ""


func step(dt: float) -> void:
	if current == null:
		if beats.is_empty():
			return
		current = beats.pop_front()
		t = 0.0
		_cue = 0
	t += dt
	var cues: Array = current.cues
	while _cue < cues.size() and float(cues[_cue][0]) <= t:
		var c: Callable = cues[_cue][1]
		_cue += 1
		if c.is_valid():
			c.call()
		if current == null:
			return
	if t >= float(current.get("dur", 0.0)):
		var b: Dictionary = current
		current = null
		_end(b)


## Finishes the playing beat now (its remaining cues are dropped, its `end` settles everything).
func skip() -> void:
	if current != null:
		var b: Dictionary = current
		current = null
		_end(b)


## Settles every queued beat at once (stage change, leaving the battle).
func flush() -> void:
	skip()
	while not beats.is_empty():
		_end(beats.pop_front())


func _end(b: Dictionary) -> void:
	played += 1
	var e: Variant = b.get("end")
	if e is Callable and (e as Callable).is_valid():
		(e as Callable).call()
