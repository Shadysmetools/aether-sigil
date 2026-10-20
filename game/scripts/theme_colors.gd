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
			"Nature": VERDANT_GREEN,
			"Earth": SIGIL_GOLD.lerp(MIDNIGHT_NAVY, 0.35),
			"Lightning": SIGIL_GOLD,
			"Wind": AETHER_CYAN.lerp(SOFT_SILVER, 0.5),
			"Ice": SOFT_SILVER.lerp(AETHER_CYAN, 0.25),
			"Tech": SOFT_SILVER.lerp(MIDNIGHT_NAVY, 0.35),
			"Light": SOFT_SILVER,
			"Dark": CRYSTAL_VIOLET.lerp(MIDNIGHT_NAVY, 0.55),
			"Arcane": CRYSTAL_VIOLET,
			"Space": CRYSTAL_VIOLET.lerp(AETHER_CYAN, 0.35),
		}
	return _families.get(f, SOFT_SILVER)
