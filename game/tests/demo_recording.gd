## Scripted gameplay demo for the owner's video (Godot Movie Maker). Drives the real UI code paths:
## title/world map -> prologue -> Tower 1 arrival -> stage intro -> capsule summons -> 3 rounds of
## battle (move, attack, skill; AI picks moves for both sides) -> victory + XP -> Evolution ->
## Fusion preview + confirm -> Tower 12 Sunforge Throne. Prints "MARK <seconds> <scene>" lines
## (video time) so narration can be aligned. Optional intro: game/scenes/intro/intro_sequence.tscn.
## Record: Godot.exe --path game --resolution 720x1280 --write-movie out.avi --fixed-fps 30 --script res://tests/demo_recording.gd
## Demo shortcut (disclosed): one capsule node is pre-activated for the player so the video can show a
## capsule-node summon on turn 1 (normally a monster must stand on the node first).
## Demo shortcut 2 (disclosed): from round 2, before one of our attacks the target rival's HP is
## lowered to 1 so the video is guaranteed to show a KO (the statue crumbling to rubble).
extends SceneTree

const GameState = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/ai.gd")
const Data = preload("res://scripts/data_loader.gd")
const Prog = preload("res://scripts/progression.gd")
const SAVE := "user://demo_save.json"
const INTRO := "res://scenes/intro/intro_sequence.tscn"

var main: Node
var frames := 0


func _initialize() -> void:
	process_frame.connect(func(): frames += 1)
	_run.call_deferred()


func mark(label: String) -> void:
	print("MARK %.2f %s" % [frames / 30.0, label])


func wait(sec: float) -> void:
	await create_timer(sec).timeout


## Waits while the 3D board's statue / transform animations play (max 8 s).
func anim_idle() -> void:
	var n := 0
	while main.board.has_method("anim_busy") and main.board.anim_busy() and n < 80:
		await wait(0.1)
		n += 1


func advance_dialogue(per_line: float, max_lines: int = 99) -> void:
	var n := 0
	while main.dialogue_box.visible and n < max_lines:
		await wait(per_line)
		main._on_dialogue_next()
		n += 1
	if main.dialogue_box.visible:
		await wait(0.6)
		main._on_dialogue_skip()


func _run() -> void:
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	if ResourceLoader.exists(INTRO):
		mark("intro")
		var intro: Node = load(INTRO).instantiate()
		root.add_child(intro)
		await wait(6.5)  # let the full ident and title build play, then tap through like a player
		while intro.step != "done":
			intro.skip()
			await wait(0.4)
		intro.queue_free()
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = SAVE
	root.add_child(main)
	await process_frame
	mark("title_prologue")
	await advance_dialogue(3.2, 3)
	mark("world_map")
	await wait(4.0)
	main._on_tower_pressed("01")
	mark("tower1_arrival")
	await advance_dialogue(3.2, 2)
	mark("tower1_stages")
	await wait(3.0)
	main.start_stage("T01-L01")  # skips the pre-match draft/placement (auto)
	mark("stage_intro")
	await advance_dialogue(3.5)
	var s: GameState = main.state
	# Demo shortcut: pre-activate the player's nearest capsule node (see header).
	var near_node := Vector2i(-1, -1)
	var best := 99
	for c in s.nodes:
		var d := GameState.manhattan(c, s.symbol_pos[0])
		if d < best:
			best = d
			near_node = c
	if near_node != Vector2i(-1, -1):
		s.nodes[near_node] = GameState.PLAYER
	main._refresh()
	mark("summon")
	var used_skill := false
	var summoned_node := false
	var did_ko := false
	while s.winner == GameState.NONE and s.round_num <= 4:
		if main.dialogue_box.visible:
			await advance_dialogue(3.0)
			main._continue()
			continue
		if main.ai_running or s.current == GameState.ENEMY:
			await wait(0.5)
			if not main.ai_running and s.current == GameState.ENEMY:
				main._continue()
			continue
		if s.is_sigil_turn():
			for i in 2:
				var opts: Array = s.legal_deploys(0)
				if opts.is_empty():
					break
				var pick: Dictionary = opts[0]
				if not summoned_node:
					for a in opts:
						if a.tile == near_node:
							pick = a
				var idx: int = main.progress.squad.find(pick.mon)
				main._on_team(idx)
				await wait(1.4)
				main._on_tile(pick.tile)
				if pick.tile == near_node:
					summoned_node = true
				await wait(0.3)
				await anim_idle()
				await wait(0.4)
			if s.is_sigil_turn() and s.current == GameState.PLAYER:  # a Crack already ended the Sigil's turn
				main._on_cmd("Wait")
			await wait(0.4)
			if s.round_num == 1:
				mark("battle")
			continue
		var u: GameState.Unit = s.actor_unit()
		main.mode = main.Mode.UNIT
		main._refresh("%s's turn: cyan = move, ember = attack" % u.name)
		await wait(1.3)
		var targets: Array = s.legal_skill_targets(u)
		if not used_skill and not targets.is_empty() and s.skill_def(u).type != "blink":
			main._on_cmd("Skill")
			await wait(1.2)
			main._on_tile(targets[0])
			used_skill = true
			await wait(0.3)
			await anim_idle()
			await wait(0.6)
			continue
		if not did_ko and s.round_num >= 2:
			var victim: GameState.Unit = null
			for e in s.units:
				if e.owner == GameState.ENEMY and s.can_attack(GameState.PLAYER, u.id, e.pos) == GameState.OK:
					victim = e
					break
			if victim != null:
				mark("ko")
				victim.hp = 1   # demo shortcut 2 (see header)
				s.force_hit = 1
				main.mode = main.Mode.UNIT
				main._on_tile(victim.pos)
				s.force_hit = -1
				did_ko = true
				await wait(0.3)
				await anim_idle()
				await wait(0.8)
				continue
		AI.take_activation(s, 0, "rush attacker")
		main._after_action("%s acts" % u.name)
		await wait(0.3)
		await anim_idle()
		await wait(0.5)
	# Victory (forced after 3 rounds to keep the video short).
	await anim_idle()
	mark("victory")
	if s.winner == GameState.NONE:
		s.symbol_hp[1] = 0
		s._set_winner(GameState.PLAYER, "symbol")
		main.ai_running = false
		main._after_action()
	await advance_dialogue(3.0)
	await wait(4.5)
	# Evolution.
	mark("evolution")
	var evo_uid: String = main.progress.squad[1]
	main.progress.get_inst(evo_uid).level = 16
	main.show_evolution()
	await wait(2.5)
	main._on_evolve(evo_uid)
	await wait(4.4)
	# Fusion.
	mark("fusion")
	var bench: Array = main.progress.roster.filter(func(i): return not main.progress.squad.has(i.uid))
	bench[0].level = 12
	bench[1].level = 11
	main.show_fusion()
	await wait(1.5)
	main._on_fusion_toggle(bench[0].uid)
	await wait(1.0)
	main._on_fusion_toggle(bench[1].uid)
	await wait(3.5)
	main._on_fusion_confirm()
	await wait(4.4)
	# Tower 12 preview.
	mark("tower12")
	main.progress.unlocked = Data.stage_count()
	main.show_stage_select()
	await wait(2.0)
	main._on_tower_pressed("12")
	await advance_dialogue(3.2, 1)
	await wait(2.5)
	main.start_stage("T12-L01")
	await advance_dialogue(3.0, 1)
	main._continue()
	await wait(4.0)
	mark("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
