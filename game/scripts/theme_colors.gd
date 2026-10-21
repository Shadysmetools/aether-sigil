## Brand colour tokens (owner's brand sheet, 2026-10-20). The ONE colour file: UI, board
## tiles, tokens and icons all read from here. Every derived colour is a blend of the 7 tokens.
extends RefCounted

const MIDNIGHT_NAVY := Color("#0B1220")   ## background
const AETHER_CYAN := Color("#22D3EE")     ## energy, tech, summoning; PLAYER highlight
const VERDANT_GREEN := Color("#2ECC71")   ## nature
const EMBER := Color("#FF6B3D")           ## passion, rivalry; ENEMY highlight
const CRYSTAL_VIOLET := Color("#B15CFF")  ## arcana, realms; portals
const SIGIL_GOLD := Color("#F6C445")      ## legend, evolution; Symbols, relics, rare UI
const SOFT_SILVER := Color("#D6DEE9")     ## text, neutral tiles

const BG := MIDNIGHT_NAVY
const TEXT := SOFT_SILVER
const PLAYER := AETHER_CYAN
const ENEMY := EMBER
const NEUTRAL := SOFT_SILVER

static var _tiles: Dictionary = {}
static var _families: Dictionary = {}


static func side(p: int) -> Color:
	match p:
		0: return PLAYER
		1: return ENEMY
	return NEUTRAL


static func panel() -> Color:
	return MIDNIGHT_NAVY.lerp(SOFT_SILVER, 0.08)


static func panel_edge() -> Color:
	return MIDNIGHT_NAVY.lerp(AETHER_CYAN, 0.35)


## Top-face colour of each tile type. Distinct per type, all derived from the brand tokens.
static func tile(type: String) -> Color:
	if _tiles.is_empty():
		var N := MIDNIGHT_NAVY
		var S := SOFT_SILVER
		_tiles = {
			"ground": S.lerp(N, 0.62),
			"stone": S.lerp(N, 0.40),
			"obstacle": N.lerp(S, 0.20),
			"bridge": SIGIL_GOLD.lerp(N, 0.50),
			"capsule_node": AETHER_CYAN.lerp(N, 0.62),
			"player_symbol": AETHER_CYAN.lerp(N, 0.45),
			"enemy_symbol": EMBER.lerp(N, 0.45),
			"player_spawn": AETHER_CYAN.lerp(S, 0.25).lerp(N, 0.68),
			"enemy_spawn": EMBER.lerp(S, 0.25).lerp(N, 0.68),
			"relic": SIGIL_GOLD.lerp(N, 0.66),
			"warp_gate": CRYSTAL_VIOLET.lerp(N, 0.62),
			"elevation": S.lerp(N, 0.22),
			"hazard": EMBER.lerp(SIGIL_GOLD, 0.45).lerp(N, 0.35),
			"forest": VERDANT_GREEN.lerp(N, 0.45),
			"lava": EMBER.lerp(N, 0.15),
			"water": AETHER_CYAN.lerp(CRYSTAL_VIOLET, 0.40).lerp(N, 0.35),
			"ice": AETHER_CYAN.lerp(S, 0.65),
			"metal": S.lerp(AETHER_CYAN, 0.20).lerp(N, 0.45),
			"sky": AETHER_CYAN.lerp(S, 0.35).lerp(N, 0.15),
			"shadow": CRYSTAL_VIOLET.lerp(N, 0.75),
			"ruins": SIGIL_GOLD.lerp(S, 0.45).lerp(N, 0.48),
			"space": CRYSTAL_VIOLET.lerp(N, 0.50),
			"crystal": CRYSTAL_VIOLET.lerp(S, 0.40),
			"rift": CRYSTAL_VIOLET.lerp(EMBER, 0.40).lerp(N, 0.25),
			"mixed": VERDANT_GREEN.lerp(SIGIL_GOLD, 0.50).lerp(N, 0.50),
		}
	return _tiles.get(type, Color.MAGENTA)  # magenta = a tile type with no colour (test catches it)


static func has_tile(type: String) -> bool:
	tile("ground")
	return _tiles.has(type)


## Token fill per element_family.
static func family(f: String) -> Color:
	if _families.is_empty():
		_families = {
			"Water": AETHER_CYAN.lerp(CRYSTAL_VIOLET, 0.35),
			"Fire": EMBER,
			"Wood": VERDANT_GREEN,
			"Earth": SIGIL_GOLD.lerp(MIDNIGHT_NAVY, 0.35),
			"Thunder": SIGIL_GOLD,
			"Wind": AETHER_CYAN.lerp(SOFT_SILVER, 0.5),
			"Ice": SOFT_SILVER.lerp(AETHER_CYAN, 0.25),
			"Tech": SOFT_SILVER.lerp(MIDNIGHT_NAVY, 0.35),
			"Light": SOFT_SILVER,
			"Dark": CRYSTAL_VIOLET.lerp(MIDNIGHT_NAVY, 0.55),
			"Arcane": CRYSTAL_VIOLET,
			"Space": CRYSTAL_VIOLET.lerp(AETHER_CYAN, 0.35),
		}
	return _families.get(f, SOFT_SILVER)


static var _themes: Dictionary = {}

## 3D board look per tower theme (bible tower `theme`): stone tints, foliage, glow accent and decor
## flavour. Every colour is a blend of the 7 tokens. Unknown themes get the Nature look.
##   stone = flagstone tops, cliff = block sides / island rock, moss = foliage + moss patches,
##   accent = emissive trim (hazard cracks, runes), water = channel colour, flora = scatter kind,
##   moss_amt 0..1, trees = small trees on the rim, snow = frosted tops.
static func tower_theme(theme: String) -> Dictionary:
	if _themes.is_empty():
		var N := MIDNIGHT_NAVY
		var S := SOFT_SILVER
		var G := SIGIL_GOLD
		var V := VERDANT_GREEN
		var C := AETHER_CYAN
		var E := EMBER
		var P := CRYSTAL_VIOLET
		var warm := S.lerp(G, 0.26).lerp(N, 0.42)   # sun-warmed ruin stone
		var water := C.lerp(P, 0.18).lerp(N, 0.28)
		var t := func(stone: Color, cliff: Color, moss: Color, accent: Color, wat: Color, flora: String, moss_amt: float, trees: bool, snow: bool) -> Dictionary:
			return {"stone": stone, "cliff": cliff, "moss": moss, "accent": accent, "water": wat, "flora": flora,
				"moss_amt": moss_amt, "trees": trees, "snow": snow}
		_themes = {
			"Nature": t.call(warm, warm.lerp(G, 0.10).lerp(N, 0.35), V.lerp(G, 0.4).lerp(N, 0.52), V.lerp(G, 0.3), water, "grass", 0.75, true, false),
			"Fire": t.call(S.lerp(E, 0.18).lerp(N, 0.48), E.lerp(N, 0.72), E.lerp(G, 0.4).lerp(N, 0.55), E.lerp(G, 0.25), E.lerp(G, 0.35), "ember", 0.25, false, false),
			"Water": t.call(S.lerp(C, 0.18).lerp(N, 0.32), C.lerp(N, 0.62).lerp(S, 0.12), V.lerp(C, 0.45).lerp(N, 0.55), C, water.lerp(C, 0.25), "coral", 0.55, false, false),
			"Ice": t.call(S.lerp(C, 0.15).lerp(N, 0.12), C.lerp(S, 0.4).lerp(N, 0.45), S.lerp(C, 0.3), C.lerp(S, 0.4), C.lerp(S, 0.35).lerp(N, 0.2), "frost", 0.35, false, true),
			"Metal": t.call(S.lerp(N, 0.45), S.lerp(N, 0.62), V.lerp(N, 0.55), C, water, "cog", 0.2, false, false),
			"Wind": t.call(S.lerp(G, 0.10).lerp(N, 0.22), S.lerp(C, 0.15).lerp(N, 0.42), V.lerp(G, 0.3).lerp(S, 0.2).lerp(N, 0.45), C.lerp(S, 0.3), water, "grass", 0.6, true, false),
			"Dark": t.call(P.lerp(N, 0.72).lerp(S, 0.12), P.lerp(N, 0.82), P.lerp(V, 0.3).lerp(N, 0.55), P, P.lerp(N, 0.4), "shadow", 0.35, false, false),
			"Ancient": t.call(warm.lerp(G, 0.15), warm.lerp(N, 0.38), V.lerp(G, 0.5).lerp(N, 0.55), G, water.lerp(V, 0.15), "grass", 0.75, true, false),
			"Space": t.call(P.lerp(S, 0.35).lerp(N, 0.55), P.lerp(N, 0.78), P.lerp(C, 0.5).lerp(N, 0.4), C.lerp(P, 0.5), P.lerp(C, 0.4).lerp(N, 0.3), "crystal", 0.2, false, false),
			"Crystal": t.call(S.lerp(P, 0.18).lerp(N, 0.22), P.lerp(S, 0.2).lerp(N, 0.55), P.lerp(C, 0.3).lerp(S, 0.2), P.lerp(S, 0.2), C.lerp(P, 0.4).lerp(N, 0.2), "crystal", 0.3, false, false),
			"Aether": t.call(S.lerp(P, 0.25).lerp(N, 0.40), P.lerp(E, 0.2).lerp(N, 0.65), P.lerp(V, 0.4).lerp(N, 0.4), P.lerp(E, 0.35), P.lerp(C, 0.3).lerp(N, 0.25), "crystal", 0.35, false, false),
			"Mixed": t.call(S.lerp(G, 0.32).lerp(N, 0.24), G.lerp(N, 0.58), V.lerp(G, 0.55).lerp(N, 0.5), G, water.lerp(G, 0.15), "grass", 0.45, true, false),
		}
	return _themes.get(theme, _themes["Nature"])


## All theme keys tower_theme knows (tests).
static func tower_themes() -> Array:
	tower_theme("Nature")
	return _themes.keys()
