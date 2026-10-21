"""Generates docs/BALANCE-REPORT.md, docs/ABILITIES.md and docs/data/*.csv.
Run from the repo root:  python -X utf8 docs/tools/aether_report.py
Read-only on data/. Every number in the docs is interpolated from aether_core computations."""
import sys, os, csv, itertools
sys.path.insert(0, os.path.dirname(__file__))
from aether_core import *
from aether_design import *

DOCS = os.path.join(ROOT, 'docs'); OUTD = os.path.join(DOCS, 'data')
os.makedirs(OUTD, exist_ok=True)
f1 = lambda x: f"{x:.1f}"; f2 = lambda x: f"{x:.2f}"; pct = lambda x: f"{100*x:.1f}%"
def table(head, rows):
    o = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    o += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(o)
def wcsv(name, head, rows):
    with open(os.path.join(OUTD, name), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f); w.writerow(head); w.writerows(rows)
LOG = []
def say(*a):
    s = " ".join(str(x) for x in a); LOG.append(s); print(s)

# ================================================================== 1. monsters
fields = ['hp', 'attack', 'defense', 'move', 'range', 'level_cap', '_power']
def grp_rows(key, order=None):
    keys = order or sorted({m[key] for m in MON})
    rows = []
    for k in keys:
        g = [m for m in MON if m[key] == k]
        row = [k, len(g)]
        for f in fields:
            v = [m[f] for m in g]
            row.append(f"{S.mean(v):.1f} ({min(v):.0f}-{max(v):.0f})" if f != '_power' else f"{S.mean(v):.2f} ({min(v):.2f}-{max(v):.2f})")
        rows.append(row)
    return rows
HEADG = ['group', 'n', 'hp', 'attack', 'defense', 'move', 'range', 'level_cap', 'power']
ETA = {k: {f: eta2(k, f) for f in fields} for k in ['rarity', 'role', 'element_family', 'element']}
say('eta2', {k: {f: round(v, 4) for f, v in d.items()} for k, d in ETA.items()})

zp, mup, sdp = zs([m['_power'] for m in MON])
for m, z in zip(MON, zp): m['_z'] = z
stat_z = {}
for f in STATS:
    zz, mu, sd = zs([m[f] for m in MON]); stat_z[f] = (max(abs(x) for x in zz), sum(1 for x in zz if abs(x) >= 2.5), mu, sd)
P_OUT = sorted([m for m in MON if abs(m['_z']) >= 2.5], key=lambda m: -m['_z'])
P_LOW = sorted(MON, key=lambda m: m['_power'])[:10]
say('power outliers |z|>=2.5:', len(P_OUT), 'mean', round(mup, 3), 'sd', round(sdp, 3))
# within-rarity outliers on power
for m in MON:
    g = [x['_power'] for x in MON if x['rarity'] == m['rarity']]
    m['_zr'] = (m['_power'] - S.mean(g)) / S.pstdev(g)
role_elem = Counter((m['element'], m['role']) for m in MON)
fam_role = defaultdict(set)
for m in MON: fam_role[m['element_family']].add(m['role'])
cycles = dict(rarity=[m['rarity'] for m in MON[:10]], role=[m['role'] for m in MON[:8]])
SLOT = {f: [len({str(l[f]) for l in STAGES if l['stage_id'].endswith('L%02d' % s)}) for s in range(1, 11)] for f in ['opponent_style', 'special_rule', 'win_condition']}
wcsv('monster_power.csv', ['id', 'name', 'element', 'element_family', 'role', 'rarity', 'hp', 'attack', 'defense', 'move', 'range', 'level_cap', 'ability', 'avg_dmg_dealt', 'avg_dmg_taken', 'power', 'power_z', 'power_z_within_rarity'],
     [[m['id'], m['name'], m['element'], m['element_family'], m['role'], m['rarity'], m['hp'], m['attack'], m['defense'], m['move'], m['range'], m['level_cap'], m['ability'], round(m['_out'], 2), round(m['_inc'], 2), round(m['_power'], 3), round(m['_z'], 2), round(m['_zr'], 2)] for m in MON])

# ================================================================== 2. damage floor + alternatives
def formula_stats(fn):
    dm = fn(A[:, None], D[None, :]); dm = np.maximum(1.0, np.round(dm))
    htk = np.ceil(H[None, :] / dm)
    return float(np.median(htk)), float((htk > 20).mean()), float((dm <= 1).mean()), float(np.percentile(htk, 90))
ALT = {
    "current: max(1, atk-def)": lambda a, d: np.maximum(1, a - d),
    "floor: max(0.25*atk, atk-def)": lambda a, d: np.maximum(0.25 * a, a - d),
    "ratio: atk*atk/(atk+def)": lambda a, d: a * a / (a + d),
    "ratio x0.6: 0.6*atk*atk/(atk+def)": lambda a, d: 0.6 * a * a / (a + d),
    "ratio x1.5: 1.5*atk*atk/(atk+def)": lambda a, d: 1.5 * a * a / (a + d),
}
ALT_S = {k: formula_stats(fn) for k, fn in ALT.items()}
REC = min((k for k in ALT_S if k.startswith('ratio')), key=lambda k: abs(ALT_S[k][0] - 6))  # target ~6 hits-to-KO
REC_F = REC.split(': ', 1)[1]
say('floor pairs', FLOOR_PAIRS, 'alt', ALT_S)

# ================================================================== 3. stage power curve
SP = []
for l in STAGES:
    p = [BYID[x]['_power'] for x in l['enemy_roster']]
    SP.append(dict(stage_id=l['stage_id'], tower=int(l['stage_id'][1:3]), level=int(l['stage_id'][-2:]), n=len(p),
                   sum=sum(p), mean=S.mean(p), boss=l['boss'], style=l['opponent_style'], rule=l['special_rule'],
                   win=l['win_condition'], opponent=l['opponent'], first=l['enemy_roster'][0], last=l['enemy_roster'][-1],
                   rar=Counter(BYID[x]['rarity'] for x in l['enemy_roster'])))
TOW = [(t, S.mean(s['sum'] for s in SP if s['tower'] == t), S.mean(s['mean'] for s in SP if s['tower'] == t)) for t in range(1, 13)]
tower_inv = [(TOW[i][0], TOW[i + 1][0], TOW[i][1], TOW[i + 1][1]) for i in range(11) if TOW[i + 1][1] < TOW[i][1]]
stage_inv = [(SP[i]['stage_id'], SP[i + 1]['stage_id'], SP[i]['sum'], SP[i + 1]['sum']) for i in range(119) if SP[i + 1]['sum'] < SP[i]['sum']]
within_inv = [x for x in stage_inv if x[0][:3] == x[1][:3]]
tower_inv_m = [(TOW[i][0], TOW[i + 1][0], TOW[i][2], TOW[i + 1][2]) for i in range(11) if TOW[i + 1][2] < TOW[i][2]]
stage_inv_m = [(SP[i]['stage_id'], SP[i + 1]['stage_id'], SP[i]['mean'], SP[i + 1]['mean']) for i in range(119) if SP[i + 1]['mean'] < SP[i]['mean']]
within_inv_m = [x for x in stage_inv_m if x[0][:3] == x[1][:3]]
def spearman(x, y):
    rx = np.argsort(np.argsort(x)); ry = np.argsort(np.argsort(y))
    return float(np.corrcoef(rx, ry)[0, 1])
RHO_SUM = spearman(list(range(120)), [s['sum'] for s in SP]); RHO_MEAN = spearman(list(range(120)), [s['mean'] for s in SP])
boss_sum = [s['sum'] for s in SP if s['boss']]; non_sum = [s['sum'] for s in SP if not s['boss']]
boss_mean = [s['mean'] for s in SP if s['boss']]; non_mean = [s['mean'] for s in SP if not s['boss']]
boss_rank = []
for t in range(1, 13):
    tw = sorted([s for s in SP if s['tower'] == t], key=lambda s: -s['sum'])
    boss_rank.append((t, [s['stage_id'] for s in tw].index(f"T{t:02d}-L10") + 1, next(s for s in tw if s['boss'])))
bosses_weaker_than_tower_avg = [b for b in boss_rank if b[2]['sum'] < TOW[b[0] - 1][1]]
used = Counter(x for l in STAGES for x in l['enemy_roster'])
overlaps = []
for a, b in itertools.combinations(STAGES, 2):
    k = len(set(a['enemy_roster']) & set(b['enemy_roster']))
    if k >= 3: overlaps.append((a['stage_id'], b['stage_id'], k))
say('tower sums', [(t, round(s, 2)) for t, s, _ in TOW], 'rho', RHO_SUM, RHO_MEAN, 'boss', S.mean(boss_sum), S.mean(non_sum))

# ================================================================== 4. maps
MA = {l['stage_id']: analyse_map(l) for l in STAGES}
MB = {l['stage_id']: analyse_map(l, True) for l in STAGES}
INTEG = {l['stage_id']: integrity(l) for l in STAGES}
FLAGS = defaultdict(list)
for l in STAGES:
    sid = l['stage_id']; a, b = MA[sid], MB[sid]
    if a['n_psym'] != 1: FLAGS[sid].append("BROKEN: no player_symbol tile on grid")
    if a['n_esym'] != 1: FLAGS[sid].append("BROKEN: enemy_symbol count != 1")
    if a['path_p2esym'] is None or b['path_p2esym'] is None: FLAGS[sid].append("BROKEN: enemy Symbol unreachable")
    if not a['spawns_connected'] or not b['spawns_connected']: FLAGS[sid].append("BROKEN: spawns disconnected")
    if 'relic' in l['win_condition'] and a['n_relic'] < 3: FLAGS[sid].append(f"BROKEN: relic win needs 3 relic nodes, grid has {a['n_relic']}")
    if 'portal' in l['special_rule'] and a['n_warp'] < 2: FLAGS[sid].append(f"BROKEN: portal rule with {a['n_warp']} warp_gate (needs >=2)")
    if a['n_player_spawn'] < 3 or a['n_enemy_spawn'] < 3: FLAGS[sid].append(f"UNFAIR: spawn tiles player {a['n_player_spawn']} vs enemy {a['n_enemy_spawn']}")
    if a['n_caps'] < 2: FLAGS[sid].append(f"UNFAIR: only {a['n_caps']} capsule node")
    # map-specific fairness is judged on the template-corrected (mirrored-spawn) numbers, symmetric thresholds
    cm = a['cap_diff_sum_mirror']
    if cm is not None and abs(cm) >= 2: FLAGS[sid].append(f"UNFAIR: capsule nodes favour {'PLAYER' if cm < 0 else 'ENEMY'} by {abs(cm)} tiles (mirrored spawns; raw sum {a['cap_diff_sum']:+d})")
    if a['path_p2esym'] is not None and a['path_e2psym_mirror'] is not None and abs(a['path_p2esym'] - a['path_e2psym_mirror']) >= 2:
        FLAGS[sid].append(f"UNFAIR: Symbol path asymmetry {a['path_p2esym']} vs {a['path_e2psym_mirror']} (mirrored spawns)")
    if INTEG[sid][0]: FLAGS[sid].append("DATA: objective list disagrees with grid: " + "; ".join(INTEG[sid][0]))
SYM_N = sum(1 for s in MA if MA[s]['spawns_point_symmetric'])
tmpl = Counter((tuple(grid_find(l['map_grid'], 'player_spawn')), tuple(grid_find(l['map_grid'], 'enemy_spawn'))) for l in STAGES).most_common(1)[0]
CAP_RAW = Counter(MA[s]['cap_diff_sum'] for s in MA); CAP_MIR = Counter(MA[s]['cap_diff_sum_mirror'] for s in MA)
PATH_RAW = Counter((MA[s]['path_p2esym'], MA[s]['path_e2psym']) for s in MA)
PATH_MIR = Counter((MA[s]['path_p2esym'], MA[s]['path_e2psym_mirror']) for s in MA)
CK_A = [MA[s]['chokepoints'] for s in MA]; CK_B = [MB[s]['chokepoints'] for s in MA]
BR_A = sum(MA[s]['bridge_chokepoints'] for s in MA); BR_B = sum(MB[s]['bridge_chokepoints'] for s in MA); BR_T = sum(MA[s]['n_bridge'] for s in MA)
stone_changes = sorted(s for s in MA if (MA[s]['path_p2esym'], MA[s]['spawns_connected'], MA[s]['path_e2psym']) != (MB[s]['path_p2esym'], MB[s]['spawns_connected'], MB[s]['path_e2psym']))
STONE_DESC = (str(len(stone_changes)) + ' (' + ', '.join(f"{x}: player->enemy Symbol {MA[x]['path_p2esym']}->{MB[x]['path_p2esym']}, enemy->player Symbol {MA[x]['path_e2psym']}->{MB[x]['path_e2psym']}, spawns connected {MA[x]['spawns_connected']}->{MB[x]['spawns_connected']}" for x in stone_changes) + ')') if stone_changes else 'none'
broken = sorted(s for s, f in FLAGS.items() if any(x.startswith('BROKEN') for x in f))
unfair = sorted(s for s, f in FLAGS.items() if any(x.startswith('UNFAIR') for x in f) and s not in broken)
data_only = sorted(s for s, f in FLAGS.items() if all(x.startswith('DATA') for x in f))
missing_psym = sorted(s for s in MA if MA[s]['n_psym'] != 1)
relic_stages = [l['stage_id'] for l in STAGES if 'relic' in l['win_condition']]
portal_stages = [l['stage_id'] for l in STAGES if 'portal' in l['special_rule']]
relic_plus_caps = Counter(MA[s]['n_relic'] + MA[s]['n_caps'] for s in relic_stages)
spawn_mismatch_tiles = sum(v[1] for v in INTEG.values()); obj_bad_stages = sum(1 for v in INTEG.values() if v[0])
obj_bad_total = sum(len(v[0]) for v in INTEG.values()); obj_total = sum(len(l['objectives']) for l in STAGES)
grid0 = STAGES[0]['map_grid']
similar = [sum(l['map_grid'][r][c] == grid0[r][c] for r in range(12) for c in range(12)) / 144 for l in STAGES]
esym_pos = Counter(tuple(grid_find(l['map_grid'], 'enemy_symbol')[0]) for l in STAGES)
psym_pos = Counter(tuple(grid_find(l['map_grid'], 'player_symbol')[0]) for l in STAGES if grid_find(l['map_grid'], 'player_symbol'))
FAM_TILE = {'forest': 'Nature', 'lava': 'Fire', 'water': 'Water', 'ice': 'Ice', 'metal': 'Tech', 'sky': 'Wind', 'shadow': 'Dark', 'stone': 'Earth', 'ruins': 'Earth', 'crystal': 'Earth', 'space': 'Space', 'rift': 'Arcane'}
THEME_FAM = {'Nature': 'Nature', 'Fire': 'Fire', 'Water': 'Water', 'Ice': 'Ice', 'Metal': 'Tech', 'Wind': 'Wind', 'Dark': 'Dark', 'Ancient': 'Earth', 'Space': 'Space', 'Crystal': 'Earth', 'Aether': 'Arcane', 'Mixed': None}
theme_match = []
for t in BIBLE['towers']:
    tiles = Counter(c for l in t['levels'] for row in l['map_grid'] for c in row if c in FAM_TILE)
    fam = THEME_FAM[t['theme']]
    match = sum(v for k, v in tiles.items() if FAM_TILE[k] == fam)
    theme_match.append((t['tower_id'], t['theme'], fam, sum(tiles.values()), match, tiles.most_common(1)[0][0] if tiles else '-'))
grid_counts = Counter(c for l in STAGES for row in l['map_grid'] for c in row)
legend_keys = set(STAGES[0]['map_legend'])
not_in_legend = sorted(k for k in grid_counts if k not in legend_keys)
legend_unused = sorted(k for k in legend_keys if k not in grid_counts)
say('maps broken', len(broken), 'unfair', len(unfair), 'missing psym', missing_psym)

wcsv('map_analysis.csv', ['stage_id', 'walkable_pct', 'walkable_pct_stone_blocks', 'path_spawn_to_enemy_symbol', 'path_enemy_spawn_to_player_symbol', 'path_with_warps', 'chokepoints_articulation', 'chokepoints_stone_blocks', 'bridge_tiles', 'elevation_tiles', 'water_tiles', 'hazard_tiles', 'stone_tiles', 'capsule_nodes', 'capsule_dist_diffs_player_minus_enemy', 'capsule_diff_sum', 'relic_tiles', 'warp_gates', 'player_spawn_tiles', 'enemy_spawn_tiles', 'player_symbol_tiles', 'flags', 'capsule_diff_sum_mirrored_spawns', 'path_enemy_to_player_symbol_mirrored', 'bridge_tiles_that_are_chokepoints', 'bridge_chokepoints_stone_blocks'],
     [[s, f1(MA[s]['walkable_pct']), f1(MB[s]['walkable_pct']), MA[s]['path_p2esym'], MA[s]['path_e2psym'], MA[s]['path_p2esym_warp'], MA[s]['chokepoints'], MB[s]['chokepoints'], MA[s]['n_bridge'], MA[s]['n_elev'], MA[s]['n_water'], MA[s]['n_hazard'], MA[s]['n_stone'], MA[s]['n_caps'], ' '.join(str(x) for x in MA[s]['cap_diffs']), MA[s]['cap_diff_sum'], MA[s]['n_relic'], MA[s]['n_warp'], MA[s]['n_player_spawn'], MA[s]['n_enemy_spawn'], MA[s]['n_psym'], ' || '.join(FLAGS.get(s, [])), MA[s]['cap_diff_sum_mirror'], MA[s]['path_e2psym_mirror'], MA[s]['bridge_chokepoints'], MB[s]['bridge_chokepoints']] for s in MA])
wcsv('stage_difficulty.csv', ['stage_id', 'tower', 'level', 'boss', 'opponent', 'opponent_style', 'special_rule', 'win_condition', 'roster_size', 'roster_first', 'roster_last', 'roster_power_sum', 'roster_power_mean', 'rank_in_tower_by_sum', 'rarity_mix'],
     [[s['stage_id'], s['tower'], s['level'], s['boss'], s['opponent'], s['style'], s['rule'], s['win'], s['n'], s['first'], s['last'], round(s['sum'], 3), round(s['mean'], 3),
       sorted([x for x in SP if x['tower'] == s['tower']], key=lambda x: -x['sum']).index(s) + 1, ' '.join(f"{k}:{v}" for k, v in sorted(s['rar'].items()))] for s in SP])

# ================================================================== 5. cross-source drift
PDF = pdf_stages(pdf_text())
pdf_opp_diff = sum(1 for l in STAGES if PDF.get(l['stage_id'], {}).get('opponent') != l['opponent'])
pdf_rule_diff = sum(1 for l in STAGES if PDF.get(l['stage_id'], {}).get('rule') != l['special_rule'])
pdf_win_diff = sum(1 for l in STAGES if PDF.get(l['stage_id'], {}).get('win') != l['win_condition'])
CS = {r['stage_id']: r for r in read_csv('120_STAGES_AND_OPPONENTS.csv')}
csv_stage_diff = sum(1 for l in STAGES for f in ['opponent', 'opponent_style', 'win_condition', 'special_rule'] if CS[l['stage_id']][f] != l[f]) + \
    sum(1 for l in STAGES if CS[l['stage_id']]['enemy_roster'].split('|') != l['enemy_roster'])
MC = read_csv('1000_MONSTERS.csv')
csv_mon_diff = sum(1 for r in MC for k, v in r.items() if str(BYID[r['id']].get(k)) != v)
boss_name_mismatch = [(t['tower_id'], t['tower_boss'], t['levels'][9]['opponent']) for t in BIBLE['towers'] if t['tower_boss'] != t['levels'][9]['opponent']]
pdf_has_chart = any(w in pdf_text().lower() for w in ['weak to', 'beats', 'strong against', 'super effective'])
say('drift pdf', pdf_opp_diff, pdf_rule_diff, pdf_win_diff, 'csv', csv_stage_diff, csv_mon_diff, 'boss mismatch', len(boss_name_mismatch), 'pdf chart', pdf_has_chart)

# ================================================================== 6. element chart
FAM_RING = {}
for ring, fams, _ in RINGS:
    for i, f in enumerate(fams): FAM_RING[f] = (ring, fams[(i + 1) % 4], fams[(i - 1) % 4])
fam_counts = Counter(m['element_family'] for m in MON)
ring_counts = {ring: sum(fam_counts[f] for f in fams) for ring, fams, _ in RINGS}
assert set(FAM_RING) == set(fam_counts), "chart must cover every family"
fams_sorted = [f for _, fams, _ in RINGS for f in fams]
def mult(att, dfn):
    if FAM_RING[att][1] == dfn: return ELEM_ADV
    if FAM_RING[att][2] == dfn: return ELEM_DIS
    return 1.0
wcsv('element_chart.csv', ['attacker\\defender'] + fams_sorted, [[a] + [mult(a, d) for d in fams_sorted] for a in fams_sorted])
tower_fam = [THEME_FAM[t['theme']] for t in BIBLE['towers']]
fam_no_tower = sorted(set(fam_counts) - set(f for f in tower_fam if f))

# ================================================================== 7. starter squad
pool = [m for m in MON if m['rarity'] in ('Common', 'Uncommon')]
active = {k for k, v in ABIL.items() if v[1] == 'active'}
by_role = defaultdict(list)
for m in pool: by_role[m['role']].append(m)
SQUAD_TARGET = S.mean(s['sum'] for s in SP if s['tower'] == 1)   # squad of 4 ~ the average T01 roster threat
for r in by_role:
    # no power outliers, and no ability that is near-dead on these maps (Rift Bite / Verdant Renewal / Soul Lantern)
    by_role[r] = [m for m in by_role[r] if abs(m['_z']) < 1.0 and m['ability'] not in ('Rift Bite', 'Verdant Renewal', 'Soul Lantern')]
    by_role[r].sort(key=lambda m: abs(m['_power'] - SQUAD_TARGET / 4)); by_role[r] = by_role[r][:15]
best = None
others = [r for r in by_role if r not in ('Guardian', 'Support')]
for r3, r4 in itertools.combinations(others, 2):
    for sq in itertools.product(by_role['Guardian'], by_role['Support'], by_role[r3], by_role[r4]):
        fams = [m['element_family'] for m in sq]
        if len(set(fams)) < 4: continue
        if sum(m['ability'] in active for m in sq) < 2: continue
        if max(m['range'] for m in sq) < 3: continue
        rings = {FAM_RING[f][0] for f in fams}
        # closest to the T01 target; then more element rings, more actives
        score = (abs(sum(m['_power'] for m in sq) - SQUAD_TARGET), -len(rings), -sum(m['ability'] in active for m in sq))
        if best is None or score < best[0]: best = (score, sq)
SQUAD = best[1]
pool_mean = S.mean(m['_power'] for m in pool)
say('squad', [(m['id'], m['name'], m['role'], m['element_family'], round(m['_power'], 2)) for m in SQUAD])

# ================================================================== 8. abilities
AB = defaultdict(list)
for m in MON: AB[m['ability']].append(m)
desc = {a: g[0]['ability_description'] for a, g in AB.items()}
desc_variants = {a: len({m['ability_description'] for m in g}) for a, g in AB.items()}
assert set(AB) == set(ABIL), set(AB) ^ set(ABIL)
forest_stages = sum(1 for s in MA if MA[s]['n_forest'] > 0)
nature_tiles_total = sum(MA[s]['n_forest'] for s in MA)
warp_stages = sum(1 for s in MA if MA[s]['n_warp'] > 0)
trap_stages = sum(1 for l in STAGES if 'hidden trap' in l['hazards'])
special_nodes = S.mean(MA[s]['n_caps'] + MA[s]['n_relic'] + MA[s]['n_warp'] + MA[s]['n_elev'] for s in MA)
water_stages = sum(1 for s in MA if MA[s]['n_water'] > 0)
elev_stages = sum(1 for s in MA if MA[s]['n_elev'] > 0)
passive_like = [a for a, v in ABIL.items() if v[1] != 'active']
dead_skill = sum(len(AB[a]) for a in passive_like)
roster_abil = Counter(BYID[x]['ability'] for l in STAGES for x in l['enemy_roster'])
prims = Counter(p for v in ABIL.values() for p in v[3])
COND = {
    "Rift Bite": f"needs a unit on a warp tile: {warp_stages}/120 maps have any warp_gate, and every one of them has exactly {max(MA[s]['n_warp'] for s in MA)} (out of 144 tiles)",
    "Verdant Renewal": f"needs Nature terrain: {forest_stages}/120 maps have any `forest` tile ({nature_tiles_total} forest tiles in total). The rule falls back to Nature-theme stages (10)",
    "Soul Lantern": f"needs hidden traps: {trap_stages}/120 stages list 'hidden trap'; no stage has concealed capsules",
    "Astral Shift": f"needs special nodes: {special_nodes:.1f} per map on average (capsule+relic+warp+elevation)",
    "Iron Root": "its knockback clause only matters against Tidal Pull, the only displacement effect in the data",
    "Tidal Pull": f"water exists on only {water_stages}/120 maps, so pulling into water rarely applies",
    "Phase Step": "needs an obstacle/terrain change. That is common: every map has obstacles",
}
ARCH_ORDER = ['damage', 'heal', 'buff', 'debuff', 'movement', 'summon', 'utility']
wcsv('ability_index.csv', ['ability', 'archetype', 'trigger', 'monsters', 'in_enemy_rosters', 'description', 'spec', 'primitives', 'roles', 'elements'],
     [[a, ABIL[a][0], ABIL[a][1], len(AB[a]), roster_abil[a], desc[a], ABIL[a][2], '+'.join(ABIL[a][3]),
       ' '.join(f"{k}:{v}" for k, v in sorted(Counter(m['role'] for m in AB[a]).items())),
       ' '.join(f"{k}:{v}" for k, v in sorted(Counter(m['element'] for m in AB[a]).items()))] for a in sorted(AB, key=lambda a: (ARCH_ORDER.index(ABIL[a][0]), a))])

# ================================================================== write BALANCE-REPORT.md
R = []
w = R.append
w("# Aether Sigil: Balance Report\n")
w("Generated by `docs/tools/aether_report.py` (core: `aether_core.py`, design constants: `aether_design.py`). Re-run with `python -X utf8 docs/tools/aether_report.py`. Every number below is computed by the script; the prose proposals are the analyst's.\n")
w("Sources: `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json` (primary), `data/1000_MONSTERS.csv`, `data/120_STAGES_AND_OPPONENTS.csv`, and `data/AETHER_SIGIL_GAME_BIBLE.pdf` (parsed with PyMuPDF). Helper tables are in `docs/data/`.\n")
w("## 0. TL;DR\n")
w(f"- **Rarity does nothing.** Rarity explains {pct(ETA['rarity']['hp'])} of HP variance, {pct(ETA['rarity']['attack'])} of attack, {pct(ETA['rarity']['defense'])} of defense and {pct(ETA['rarity']['_power'])} of power. A Legendary averages {S.mean(m['_power'] for m in MON if m['rarity']=='Legendary'):.2f} power vs a Common's {S.mean(m['_power'] for m in MON if m['rarity']=='Common'):.2f}.")
w(f"- **The damage floor dominates combat.** In {pct(FLOOR_PAIRS)} of all attacker/defender pairs, atk <= def, so the hit deals exactly 1. The median hits-to-KO is {HTK_MED:.0f}, and {pct(HTK_GT20)} of pairs need more than 20 hits.")
w(f"- **Difficulty is flat and non-monotonic.** Spearman rho between stage order and mean roster power is {RHO_MEAN:+.2f} ({RHO_SUM:+.2f} on the sum). On the mean there are {len(tower_inv_m)} tower-to-tower inversions, and {len(within_inv_m)} of 108 within-tower steps go down. Boss stages average {S.mean(boss_sum):.1f} roster power vs {S.mean(non_sum):.1f} for normal stages.")
w(f"- **Two map rules can't work as written.** All {len(relic_stages)} 'secure 3 relic nodes' stages have exactly {max(MA[s]['n_relic'] for s in relic_stages)} relic tile. All {len(portal_stages)} 'random portal' stages have exactly {max(MA[s]['n_warp'] for s in portal_stages)} warp gate. {len(missing_psym)} of 12 boss stages have no player Symbol tile.")
w(f"- **Identity is locked by ID arithmetic.** Each element has exactly one role ({len(role_elem)} element/role combos out of 16x8=128 possible). Range is a pure function of role (eta^2 = {ETA['role']['range']:.2f}). Only {len(active)} of 20 abilities are activatable, so {dead_skill} monsters have nothing to do with the Skill command.")
w("")

w("## 1. Definitions and assumptions\n")
w(f"**Power score.** `{POWER_FORMULA}`. It equals expected damage dealt per hit times hits survived, with a +/-5% nudge per point of move/range. It uses the owner's damage formula against the whole population, so the 1-damage floor is priced in. Population: mean {mup:.3f}, sd {sdp:.3f}, min {min(POWER):.3f}, max {max(POWER):.3f}. The distribution is heavy-tailed because `max(1, ...)` makes low-attack monsters nearly harmless.\n")
w("**Stage difficulty** = the MEAN roster power (average power of the stage's enemy roster, as the brief defines it). The SUM ('threat') is reported next to it, because a squad of 4 must beat every enemy and roster size cycles 5/6/7. Inversions are listed for both.\n")
w("**Coordinates.** `map_grid[row][col]`. Objective `tile` values are [row, col]. The JSON `player_spawns`/`enemy_spawns` fields disagree with the grid (see section 2), so **the grid is the source of truth** for every map metric.\n")
w(f"**Walkability.** `obstacle` is blocked. Everything else is walkable: water/hazard/lava cost or hurt but do not block. `stone` is not in `map_legend`. It is treated as walkable-but-blocks-LOS (ruins/columns) in the main run, and every map metric was re-run with stone BLOCKED. Stages whose reachability or Symbol path changes between the two treatments: {STONE_DESC}. Columns `walkable_pct_stone_blocks` and `chokepoints_stone_blocks` in `docs/data/map_analysis.csv`. Warp gates do NOT add BFS edges in the main numbers; `path_with_warps` adds them.\n")
w("**Path length** = BFS steps (4-neighbour) from the nearest `player_spawn` tile to the `enemy_symbol` tile. **Chokepoints** = articulation vertices of the walkable 4-neighbour graph (tiles whose removal disconnects the board), counted in the spawn component. Bridge tiles are counted separately. **Capsule fairness** = for each `capsule_node`, BFS distance from the nearest player spawn minus the nearest enemy spawn, summed over the map's nodes. Negative means the player is closer. The grid's spawn template is itself asymmetric (section 9), so map-specific fairness is judged with the enemy spawns replaced by the point-mirror `(11-r, 11-c)` of the player spawns. A map is flagged UNFAIR when that corrected sum is beyond +/-2 either way, or when the Symbol-to-Symbol path lengths differ by 2 or more.\n")
w("\n**Rules the data does not cover** (these definitions are reused in every spec below):\n")
w(table(['Topic', 'Definition'], GAPS))
w("")

w("## 2. Data integrity (fix these first; they change balance)\n")
w(table(['Check', 'Result'], [
    ['Objective tiles that disagree with the grid', f"{obj_bad_total} of {obj_total} objectives, on {obj_bad_stages}/120 stages"],
    ['JSON spawn tiles that are not spawn tiles on the grid', f"{spawn_mismatch_tiles} of {sum(len(l['player_spawns'])+len(l['enemy_spawns']) for l in STAGES)}. The JSON lists [1,1]/[10,10], which are the Symbol tiles. The grid puts spawns at offset +1"],
    ['Stages with no `player_symbol` tile on the grid', f"{len(missing_psym)}: {', '.join(missing_psym)} (all boss stages)"],
    ['Stages with < 3 player / enemy spawn tiles', f"{sum(1 for s in MA if MA[s]['n_player_spawn']<3)} / {sum(1 for s in MA if MA[s]['n_enemy_spawn']<3)}"],
    ['Stages with only 1 capsule node', f"{sum(1 for s in MA if MA[s]['n_caps']<2)}"],
    ['Grid tile types missing from `map_legend`', ', '.join(not_in_legend) or 'none'],
    ['Legend entries never used on any grid', ', '.join(legend_unused) or 'none'],
    ['Enemy Symbol position', ', '.join(f"{k} x{v}" for k, v in esym_pos.items())],
    ['Player Symbol position', ', '.join(f"{k} x{v}" for k, v in psym_pos.items())],
    ['Map similarity to T01-L01 (share of identical tiles)', f"min {min(similar):.2f}, mean {S.mean(similar):.2f}. All maps are one template plus noise"],
    ['PDF vs JSON: opponent / rule / win condition', f"{pdf_opp_diff} / {pdf_rule_diff} / {pdf_win_diff} of 120 stages differ"],
    ['Tower boss name vs the L10 opponent (JSON)', f"{len(boss_name_mismatch)}/12 differ (e.g. T{boss_name_mismatch[0][0]}: tower_boss {boss_name_mismatch[0][1]}, L10 opponent {boss_name_mismatch[0][2]}). The PDF uses tower_boss as the L10 opponent" if boss_name_mismatch else 'none'],
    ['Stage CSV vs JSON (opponent/style/rule/win/roster)', f"{csv_stage_diff} differences"],
    ['Monster CSV vs JSON (all fields)', f"{csv_mon_diff} differences"],
    ['Element chart stated in the PDF?', 'no' if not pdf_has_chart else 'yes'],
]))
w("\n**Generator fingerprints** (attributes are assigned by ID modulo cycles, not designed):\n")
w(f"- Rarity repeats every 10 IDs: {' > '.join(cycles['rarity'])} (so Legendary = {sum(1 for m in MON if m['rarity']=='Legendary')}, the others 181-182).")
w(f"- Role repeats every 8 IDs and element every 16, so each element has exactly one role: {', '.join(sorted(f'{e}={r}' for (e, r) in role_elem))}.")
w(f"- Range by role: {', '.join(f'{r}={sorted({m['range'] for m in MON if m['role']==r})[0]}' for r in sorted({m['role'] for m in MON}))}. Artillery has range 2, shorter than Assassins and Controllers.")
w(f"- Abilities repeat every 20 IDs. Each element therefore only ever carries {len({m['ability'] for m in MON if m['element']=='Mist'})} of the 20 abilities.")
w(f"- Enemy rosters are sliding ID windows ({len(used)} unique monsters fill {sum(used.values())} roster slots). {len(overlaps)} stage pairs share 3+ monsters, e.g. " + ", ".join(f"{a}/{b} ({k})" for a, b, k in overlaps[:6]) + ".")
w(f"- Level-slot locking (distinct values per L-slot across the 12 towers): special_rule {SLOT['special_rule']}, win_condition {SLOT['win_condition']}, opponent_style {SLOT['opponent_style']}. Rule and win condition are identical in every tower: rules cycle with period 4 ({' / '.join(l['special_rule'] for l in STAGES[:4])}) and the relic win sits on {', '.join(sorted({l['stage_id'][-3:] for l in STAGES if 'relic' in l['win_condition']}))}. Style is not slot-locked: each style appears once per tower (section 6).")
w("")

w("## 3. Stat distributions\n")
w("Cells are `mean (min-max)`. Power is defined in section 1.\n")
w("### By rarity\n"); w(table(HEADG, grp_rows('rarity', RARITIES)))
w("\n### By role\n"); w(table(HEADG, grp_rows('role')))
w("\n### By element family\n"); w(table(HEADG, grp_rows('element_family')))
w("\n### Variance explained (eta^2, one-way ANOVA): how much of each stat the grouping accounts for\n")
w(table(['grouping'] + fields, [[k] + [f"{v:.3f}" for v in d.values()] for k, d in ETA.items()]))
w(f"\nReading it: 1.000 means the grouping fully determines the stat (range by role; also by family, because both elements of each 2-element family land on roles with equal range). Values near 0 mean the grouping is cosmetic, as with rarity for every stat.\n")
w("### Outliers (z-score)\n")
w(table(['stat', 'mean', 'sd', 'max abs z', 'monsters with abs z >= 2.5'], [[f, f1(v[2]), f1(v[3]), f2(v[0]), v[1]] for f, v in stat_z.items()]))
w(f"\nRaw stats are uniform-ish with no single-stat outliers. The outliers are in **power**, where attack and defense combine through the floor. {len(P_OUT)} monsters have power z >= 2.5 (all on the high side; the lowest z is {min(zp):+.2f}). The top 15:\n")
w(table(['id', 'name', 'rarity', 'role', 'family', 'hp', 'atk', 'def', 'power', 'z'], [[m['id'], m['name'], m['rarity'], m['role'], m['element_family'], m['hp'], m['attack'], m['defense'], f2(m['_power']), f"{m['_z']:+.2f}"] for m in P_OUT[:15]]))
w(f"\nThe remaining {len(P_OUT) - 15}: " + ", ".join(f"{m['name']} ({m['id']}, {m['_z']:+.1f})" for m in P_OUT[15:]) + ".")
w(f"\nRarity mix of those {len(P_OUT)}: {dict(Counter(m['rarity'] for m in P_OUT))}. The weakest 10 (they deal about 1 damage per hit to most of the population):\n")
w(table(['id', 'name', 'rarity', 'role', 'atk', 'def', 'hp', 'power'], [[m['id'], m['name'], m['rarity'], m['role'], m['attack'], m['defense'], m['hp'], f"{m['_power']:.3f}"] for m in P_LOW]))
w("\nThe full list with z and within-rarity z is in `docs/data/monster_power.csv`.\n")

w("## 4. The damage floor\n")
w(f"With `damage = max(1, atk - def)`, atk in [{int(A.min())},{int(A.max())}] and def in [{int(D.min())},{int(D.max())}]:\n")
w(f"- {pct(FLOOR_PAIRS)} of all 1,000,000 attacker/defender pairs deal exactly 1 damage.")
w(f"- Hits-to-KO: median {HTK_MED:.0f}. {pct(HTK_LE5)} of pairs KO in 5 or fewer hits, {pct(HTK_GT20)} need more than 20, and {pct(HTK_GT50)} need more than 50.")
w("- Terrain and element multipliers barely matter against the floor: x1.30 of 1 is still 1.\n")
w("Alternative formulas on the same population (round, min 1):\n")
w(table(['formula', 'median hits-to-KO', 'pairs > 20 hits', 'pairs dealing 1 dmg', 'p90 hits-to-KO'], [[k, f"{v[0]:.0f}", pct(v[1]), pct(v[2]), f"{v[3]:.0f}"] for k, v in ALT_S.items()]))
w(f"\nRecommendation: `dmg = max(1, round({REC_F}))`. It is the ratio variant whose median hits-to-KO is closest to a 6-hit tactics target. Defense still matters but never trivialises a hit: median hits-to-KO {ALT_S[REC][0]:.0f}, p90 {ALT_S[REC][3]:.0f}, 1-damage pairs {pct(ALT_S[REC][2])}. If the owner wants to keep the subtraction, use the `max(0.25*atk, atk-def)` floor instead (median {ALT_S['floor: max(0.25*atk, atk-def)'][0]:.0f}).\n")

w("## 5. Power curve\n")
w("### Per tower (T01 -> T12)\n")
w(table(['tower', 'theme', 'mean stage threat (sum)', 'mean roster power (mean)', 'boss (L10) threat', 'boss rank in tower (1 = hardest)'],
        [[f"T{t:02d}", BIBLE['towers'][t-1]['theme'], f1(s), f2(mn), f1(next(x['sum'] for x in SP if x['tower']==t and x['boss'])), boss_rank[t-1][1]] for t, s, mn in TOW]))
w(f"\n**Monotonic?** No.\n")
w(f"- Tower-to-tower inversions on MEAN roster power ({len(tower_inv_m)}): " + (", ".join(f"T{a:02d}->T{b:02d} ({x:.2f}->{y:.2f})" for a, b, x, y in tower_inv_m) or "none") + ".")
w(f"- Tower-to-tower inversions on SUM threat ({len(tower_inv)}): " + (", ".join(f"T{a:02d}->T{b:02d} ({x:.1f}->{y:.1f})" for a, b, x, y in tower_inv) or "none") + ".")
w(f"- Stage order vs difficulty: Spearman rho = {RHO_MEAN:+.3f} (mean) and {RHO_SUM:+.3f} (sum). There is no trend: T12 is about as hard as T01.")
w(f"- Of the 119 consecutive stage pairs, {len(stage_inv_m)} go DOWN on the mean ({len(within_inv_m)} of 108 within a tower) and {len(stage_inv)} on the sum ({len(within_inv)} within a tower).\n")
w("### Per stage (threat = roster power sum; mean in brackets)\n")
rows = []
for t in range(1, 13):
    rows.append([f"T{t:02d}"] + [f"{s['sum']:.1f} ({s['mean']:.2f})" for s in SP if s['tower'] == t])
w(table(['tower'] + [f"L{i:02d}" for i in range(1, 11)], rows))
w("\n**Within-tower inversions on MEAN roster power** (L(n+1) easier than L(n)):\n")
w(", ".join(f"{a}->{b[-3:]} ({x:.2f}->{y:.2f})" for a, b, x, y in within_inv_m))
w("\n**Within-tower inversions on SUM threat:**\n")
w(", ".join(f"{a}->{b[-3:]} ({x:.1f}->{y:.1f})" for a, b, x, y in within_inv))
w(f"\nThe full table with rarity mix and in-tower rank is in `docs/data/stage_difficulty.csv`.\n")
w("### Boss stages\n")
w(f"Boss stages are exactly the 12 L10 stages. Mean threat: boss {S.mean(boss_sum):.2f} vs non-boss {S.mean(non_sum):.2f}. Mean roster power: boss {S.mean(boss_mean):.2f} vs {S.mean(non_mean):.2f}. A boss is the hardest stage of its tower in {sum(1 for b in boss_rank if b[1]==1)}/12 towers and is below its tower's average in {len(bosses_weaker_than_tower_avg)}/12 ({', '.join(f'T{b[0]:02d}' for b in bosses_weaker_than_tower_avg)}). **Bosses are not stronger.** `boss: true` changes nothing in the data except the flag, and {len(missing_psym)} boss maps are also missing the player Symbol.\n")

w("## 6. Opponent styles -> AI behaviour\n")
sc = Counter(l['opponent_style'] for l in STAGES)
w(f"{len(sc)} distinct styles, each used {sorted(set(sc.values()))[0]} times (once per tower). Boss (L10) styles: {dict(Counter(l['opponent_style'] for l in STAGES if l['boss']))}.\n")
for st, n in sorted(sc.items(), key=lambda x: [l['opponent_style'] for l in STAGES[:10]].index(x[0])):
    a = AI[st]; slot = sorted({l['stage_id'][-3:] for l in STAGES if l['opponent_style'] == st})
    w(f"### {st} (x{n})\n")
    w(f"Stages: {', '.join(l['stage_id'] for l in STAGES if l['opponent_style'] == st)}\n")
    w(f"- **Target priority:** {a['target']}\n- **Positioning:** {a['position']}\n- **Defend:** {a['defend']}\n- **Skill:** {a['skill']}\n- **Tuning knob:** `{a['knob']}`\n")
w("Shared AI scoring for every style: `score(action) = w_dmg*expected_damage + w_ko*P(KO) + w_obj*objective_value - w_risk*incoming_threat_next_round`. Each style above only reweights these terms. Bosses should add one boss-only behaviour on top of their style: at <= 50% HP, switch to the 'rush attacker' targeting for one round (boss_phase dialogue fires).\n")

w("## 7. Special rules\n")
rc = Counter(l['special_rule'] for l in STAGES)
w(f"{len(rc)} distinct special rules:\n")
w(table(['rule', 'stages', 'level slots', 'implementable definition'], [[r, n, ' '.join(sorted({l['stage_id'][-3:] for l in STAGES if l['special_rule'] == r})), RULES[r]] for r, n in rc.most_common()]))
w(f"\nData support: the portal rule appears on {len(portal_stages)} stages, which have {Counter(MA[s]['n_warp'] for s in portal_stages)} warp gates (count: stages). With one gate it can't pair, hence the mirrored-tile fallback above. Better: add a second gate. 'Terrain bonuses are doubled' runs on maps where {sum(1 for s in MA if MA[s]['n_elev']<=1)}/120 have at most 1 elevation tile, so it is mostly a no-op until terrain is added (see section 9).\n")
w("## 8. Win conditions\n")
wc = Counter(l['win_condition'] for l in STAGES)
w(table(['win condition', 'stages', 'implementable definition'], [[k, v, WINS[k]] for k, v in wc.most_common()]))
w(f"\nRelic stages have relic + capsule node counts of {dict(relic_plus_caps)}. Counting capsule nodes as relic nodes makes '3 nodes' reachable on {sum(v for k, v in relic_plus_caps.items() if k >= 3)}/{len(relic_stages)} relic stages, but with zero slack on those with exactly 3 ({relic_plus_caps.get(3, 0)}): the player must hold every node at once. Adding a 4th node gives the condition some play.\n")
w("Owner's multi-objectives, mapped onto the same machinery:\n")
w(table(['objective', 'definition'], list(OWNER_OBJECTIVES.items())))
w("")

w("## 9. Map analysis\n")
wp = [MA[s]['walkable_pct'] for s in MA]; pl = [MA[s]['path_p2esym'] for s in MA if MA[s]['path_p2esym'] is not None]
ck = [MA[s]['chokepoints'] for s in MA]
w(table(['metric', 'min', 'mean', 'max'], [
    ['walkable %', f1(min(wp)), f1(S.mean(wp)), f1(max(wp))],
    ['path player spawn -> enemy Symbol', min(pl), f1(S.mean(pl)), max(pl)],
    ['path with warp edges', min(MA[s]['path_p2esym_warp'] for s in MA), f1(S.mean(MA[s]['path_p2esym_warp'] for s in MA)), max(MA[s]['path_p2esym_warp'] for s in MA)],
    ['chokepoints (articulation tiles)', min(ck), f1(S.mean(ck)), max(ck)],
    ['bridge tiles', min(MA[s]['n_bridge'] for s in MA), f1(S.mean(MA[s]['n_bridge'] for s in MA)), max(MA[s]['n_bridge'] for s in MA)],
    ['elevation tiles', min(MA[s]['n_elev'] for s in MA), f1(S.mean(MA[s]['n_elev'] for s in MA)), max(MA[s]['n_elev'] for s in MA)],
    ['water tiles', min(MA[s]['n_water'] for s in MA), f1(S.mean(MA[s]['n_water'] for s in MA)), max(MA[s]['n_water'] for s in MA)],
    ['chokepoints, stone blocking', min(CK_B), f1(S.mean(CK_B)), max(CK_B)],
    ['capsule-node distance sum (player - enemy)', min(MA[s]['cap_diff_sum'] for s in MA), f1(S.mean(MA[s]['cap_diff_sum'] for s in MA)), max(MA[s]['cap_diff_sum'] for s in MA)],
    ['same, mirrored enemy spawns', min(MA[s]['cap_diff_sum_mirror'] for s in MA), f1(S.mean(MA[s]['cap_diff_sum_mirror'] for s in MA)), max(MA[s]['cap_diff_sum_mirror'] for s in MA)],
]))
w(f"\nDistributions: path length {dict(Counter(pl))}. Capsule sum {dict(Counter(MA[s]['cap_diff_sum'] for s in MA))}. Chokepoints {dict(sorted(Counter(ck).items()))}. Water appears on only {water_stages}/120 maps and elevation on {elev_stages}/120, never more than {max(MA[s]['n_elev'] for s in MA)} tile per map. The owner's water and high-ground rules therefore rarely fire. Walkable area is {f1(min(wp))}-{f1(max(wp))}%.\n")
w(f"**Chokepoints depend on how `stone` is treated.** With stone walkable, the articulation-tile distribution is {dict(sorted(Counter(CK_A).items()))} ({sum(1 for c in CK_A if c == 0)} maps have none). With stone blocking, it is {dict(sorted(Counter(CK_B).items()))} ({sum(1 for c in CK_B if c == 0)} maps have none, mean {S.mean(CK_B):.1f}). Of the {BR_T} bridge tiles, {BR_A} are true chokepoints (articulation vertices) with stone walkable and {BR_B} with stone blocking. The owner's 'bridges are 1-wide chokepoints' rule mostly does not hold on these grids: almost no bridge tile is an articulation vertex, so units can walk around bridges. Flank bridges with obstacle/water tiles if they are meant to be chokepoints. Decide whether `stone` blocks movement before the map pass; it is the single biggest lever on board openness.\n")
w(f"**Spawn template bias (systemic, all maps).** {tmpl[1]}/120 maps use player spawns {list(tmpl[0][0])} and enemy spawns {list(tmpl[0][1])}. The player's spawns step toward the centre, the enemy's toward its corner, and {SYM_N}/120 maps are point-symmetric. Result: raw capsule sums {dict(CAP_RAW)} and Symbol paths (player->enemy, enemy->player) {dict(PATH_RAW)}, so the player is about 1 tile closer to everything. With mirrored enemy spawns the capsule sums become {dict(CAP_MIR)} and the paths {dict(PATH_MIR)}. Fix: move the enemy spawns to the mirror of the player's, `(9,9), (9,8), (8,9)`. The per-map UNFAIR flags below use the corrected numbers.\n")
w("**Themed terrain vs tower theme** (terrain tiles whose family matches the tower):\n")
w(table(['tower', 'theme', 'family', 'terrain tiles (10 maps)', 'matching', 'most common terrain tile'], theme_match))
w(f"\nFamilies with no tower: {', '.join(fam_no_tower)}. Earth gets two (Ancient and Crystal).\n")
w(f"### Flagged maps\n")
w(f"- **BROKEN ({len(broken)}):** {', '.join(broken)}")
w(f"  - by cause: " + "; ".join(f"{k} = {v}" for k, v in Counter(f.split(',')[0].split(' (')[0] if 'relic' not in f and 'portal' not in f else f.split(', grid')[0].split(' with')[0] for s in broken for f in FLAGS[s] if f.startswith('BROKEN')).most_common()) + f". Without the relic/portal rule issues, the only broken maps are the {len(missing_psym)} boss maps with no player Symbol.")
w(f"- **UNFAIR only ({len(unfair)}):** {', '.join(unfair) or 'none'}")
w(f"- Data-only mismatches (objective list vs grid, otherwise playable): {len(data_only)} stages.\n")
w(table(['stage', 'walk%', 'path', 'chokes', 'bridges', 'caps diff', 'flags'],
        [[s, f1(MA[s]['walkable_pct']), MA[s]['path_p2esym'], MA[s]['chokepoints'], MA[s]['n_bridge'], MA[s]['cap_diff_sum'], '<br>'.join(f for f in FLAGS[s] if not f.startswith('DATA'))] for s in sorted(set(broken) | set(unfair))]))
w("\n### All 120 maps\n")
w("`walk%` = walkable share; `path` = BFS player spawn -> enemy Symbol; `chokes` = articulation tiles (stone walkable / stone blocking); `caps` = capsule distance sum raw / mirrored (negative = player closer).\n")
w(table(['stage', 'walk%', 'path', 'chokes', 'bridges', 'elev', 'water', 'caps', 'relic', 'warp', 'status'],
        [[s, f1(MA[s]['walkable_pct']), MA[s]['path_p2esym'], f"{MA[s]['chokepoints']}/{MB[s]['chokepoints']}", MA[s]['n_bridge'], MA[s]['n_elev'], MA[s]['n_water'],
          f"{MA[s]['cap_diff_sum']}/{MA[s]['cap_diff_sum_mirror']}", MA[s]['n_relic'], MA[s]['n_warp'],
          'BROKEN' if s in broken else 'UNFAIR' if s in unfair else 'data' if s in data_only else 'ok'] for s in MA]))
w("\nThe per-stage numbers for all 120 maps, with flag text, are in `docs/data/map_analysis.csv`.\n")

w("## 10. Element chart (proposed)\n")
w(f"The bible and PDF state no matchups (keyword search for 'weak to', 'beats', 'strong against' and 'super effective' finds nothing). The concept sheet only gives flavour words (Nature/Life, Fire/War, ...). The data has 16 elements in 12 families: 4 families hold 2 elements each ({', '.join(f'{f}={fam_counts[f]}' for f in ['Fire','Water','Earth','Wind'])} monsters), and 8 hold 1. The proposal is **three rings of four**. In each ring a family beats the next one and loses to the previous one. Cross-ring matchups and opposite-in-ring matchups are neutral. Advantage is x{ELEM_ADV}, disadvantage x{ELEM_DIS}.\n")
for ring, fams, why in RINGS:
    w(f"- **{ring} ring** ({ring_counts[ring]} monsters): {' > '.join(fams + [fams[0]])}. *{why}.*")
w(f"\nWhy it works: every family has exactly ONE strength and ONE weakness, so the whole chart is 12 arrows a player can memorise as three loops. The 4 big families form the core ring, the one players meet first. Sub-elements inherit their family (Mist and Tide are both Water). Element multipliers apply after the damage floor fix (section 4). On the current formula they are invisible on {pct(FLOOR_PAIRS)} of pairs. Full matrix: `docs/data/element_chart.csv`.\n")
w(table(['attacker \\ defender'] + fams_sorted, [[a] + [('**1.25**' if mult(a, d) > 1 else '0.8' if mult(a, d) < 1 else '.') for d in fams_sorted] for a in fams_sorted]))
w("")

w("## 11. Recommended starter squad\n")
w(f"Picked by the script from Common/Uncommon only ({len(pool)} monsters). Constraints: one Guardian, one Support and two other distinct roles; 4 distinct element families; at least 2 activatable abilities; at least one unit with range >= 3; no member with |power z| >= 1; no map-dependent ability that rarely fires (Rift Bite, Verdant Renewal, Soul Lantern; see ABILITIES.md). Among valid squads it picks the one whose total power is closest to the average T01 stage threat ({SQUAD_TARGET:.1f}), then the one covering the most element rings, then the one with the most actives. A starter should be fair, not the strongest: the strongest monster in the game, {max(MON, key=lambda m: m['_power'])['name']} ({max(MON, key=lambda m: m['_power'])['id']}, power z {max(zp):+.1f}), is a {max(MON, key=lambda m: m['_power'])['rarity']}, and the four strongest Common/Uncommon monsters total {sum(sorted((m['_power'] for m in pool), reverse=True)[:4]):.1f} power, against a T01 average threat of {SQUAD_TARGET:.1f}.\n")
w(table(['id', 'name', 'rarity', 'role', 'element / family', 'hp', 'atk', 'def', 'move', 'range', 'ability', 'power'],
        [[m['id'], m['name'], m['rarity'], m['role'], f"{m['element']} / {m['element_family']}", m['hp'], m['attack'], m['defense'], m['move'], m['range'], f"{m['ability']} ({ABIL[m['ability']][1]})", f2(m['_power'])] for m in SQUAD]))
w(f"\nSquad power {sum(m['_power'] for m in SQUAD):.2f} (Common/Uncommon pool mean x4 = {4*pool_mean:.2f}). Element rings covered: {', '.join(sorted({FAM_RING[m['element_family']][0] for m in SQUAD}))}. Because rarity doesn't scale stats (section 3), a Common/Uncommon squad is not handicapped by rarity. Once tuning change #1 lands, re-run this pick.\n")

w("## 12. Top 10 tuning changes\n")
tun = [
    f"**Rarity multipliers** on hp/attack/defense: Common 1.00, Uncommon 1.06, Rare 1.12, Epic 1.20, Mythic 1.28, Legendary 1.36. Rarity currently explains {pct(ETA['rarity']['_power'])} of power.",
    f"**Replace the damage formula** with `max(1, round({REC_F}))`. This takes the 1-damage pairs from {pct(FLOOR_PAIRS)} to {pct(ALT_S[REC][2])} and the median hits-to-KO from {HTK_MED:.0f} to {ALT_S[REC][0]:.0f}.",
    f"**Budget rosters by tower.** Target stage threat = T01 mean ({TOW[0][1]:.1f}) x 1.12^(tower-1) x (1 + 0.03*(level-1)), with the boss at x1.3. Fill rosters by greedy pick from the monster pool, not ID windows (currently rho = {RHO_SUM:+.2f}).",
    f"**Make bosses bosses**: give the L10 opponent a unique boss monster (Legendary, 2x HP, 2 abilities) and restore the player Symbol on {', '.join(missing_psym)}.",
    f"**Relic win condition**: either place 3 relic tiles per relic stage (currently {max(MA[s]['n_relic'] for s in relic_stages)}) or formally count capsule nodes as relic nodes (section 8).",
    f"**Portal rule**: place 2 warp gates on each of the {len(portal_stages)} portal stages (currently 1 each), or use the mirrored-tile fallback.",
    f"**Decouple identity from ID**: reshuffle element/role/ability so each element spans 3+ roles (currently 1) and ability doesn't follow ID mod 20. Give Artillery range 4 and Supports range 3.",
    f"**Give every monster a Skill**: {dead_skill} monsters have only passive/triggered abilities. Add one shared active `Signature Strike` (x1.3 damage of own element, cooldown 2) for them. That is 1 extra script, not {len(passive_like)}.",
    f"**Terrain that matters**: at least 3 elevation tiles and a themed terrain patch (>= 8 tiles of the tower's family) per map, and water on Water-tower maps. Today {water_stages}/120 maps have water and {sum(1 for s in MA if MA[s]['n_elev']<=1)}/120 have <= 1 elevation tile. Narrow the open boards: {sum(1 for c in CK_A if c == 0)} maps have no chokepoint with stone walkable ({sum(1 for c in CK_B if c == 0)} with stone blocking), and only {BR_A}/{BR_T} bridge tiles are real chokepoints.",
    f"**Squad vs spawn count**: squad is 4, but maps give 3 spawn tiles and rosters are 5-7. Add a 4th player spawn, cap rosters at 4 on-field + capsules, fix the {spawn_mismatch_tiles} JSON spawn coordinates so they match the grid, and mirror the enemy spawn template so the player stops starting 1 tile closer to every objective.",
]
for i, t in enumerate(tun, 1): w(f"{i}. {t}")
w("")
open(os.path.join(DOCS, 'BALANCE-REPORT.md'), 'w', encoding='utf-8').write("\n".join(R))

# ================================================================== write ABILITIES.md
B = []; w = B.append
w("# Aether Sigil: Abilities\n")
w("Generated by `docs/tools/aether_report.py`. Counts come from `data/AETHER_SIGIL_MASTER_GAME_BIBLE.json`. Specs use the shared rule definitions in `BALANCE-REPORT.md` section 1 (accuracy 90%, crit 10% x1.5, round half up, min 1).\n")
w(f"**{len(AB)} distinct abilities** across {len(MON)} monsters. Every ability has exactly {'/'.join(str(x) for x in sorted(set(len(g) for g in AB.values())))} holders and {'/'.join(str(x) for x in sorted(set(desc_variants.values())))} description text, so there are no near-duplicate NAMES to merge. Because of the ID-modulo generator, each ability sits on exactly {'/'.join(str(x) for x in sorted(set(len({m['role'] for m in g}) for g in AB.values())))} roles and {'/'.join(str(x) for x in sorted(set(len({m['element'] for m in g}) for g in AB.values())))} elements. Trigger split: " + ", ".join(f"{k} {v}" for k, v in Counter(v[1] for v in ABIL.values()).most_common()) + ".\n")
w(f"**Scripts needed:** {len(AB)} ability scripts. They are built on **{len(prims)} shared primitives** ({', '.join(f'`{p}` x{n}' for p, n in prims.most_common())}). Near-duplicate behaviours collapse into {len(NEAR_DUP)} shared hooks (below), so the real engineering load is about {len(prims)} primitives plus {len(AB)} thin configs. Recommended addition: 1 shared `Signature Strike` active for the {dead_skill} monsters ({pct(dead_skill/len(MON))}) whose ability is not activatable, otherwise their Skill command is empty.\n")
w("## Summary by archetype\n")
w(table(['archetype', 'abilities', 'monsters'], [[a, ', '.join(sorted(k for k in ABIL if ABIL[k][0] == a)), sum(len(AB[k]) for k in ABIL if ABIL[k][0] == a)] for a in ARCH_ORDER]))
w("\n## Near-duplicate groups (share one hook)\n")
w(table(['group', 'abilities', 'shared implementation'], [[g, ', '.join(a), s] for g, a, s in NEAR_DUP]))
for arch in ARCH_ORDER:
    w(f"\n## {arch.title()}\n")
    for a in sorted(k for k in ABIL if ABIL[k][0] == arch):
        g = AB[a]
        w(f"### {a}\n")
        w(f"- **Data text:** {desc[a]}")
        w(f"- **Holders:** {len(g)} monsters ({roster_abil[a]} enemy-roster slots). Roles: {', '.join(f'{k} {v}' for k, v in sorted(Counter(m['role'] for m in g).items()))}. Elements: {', '.join(f'{k} {v}' for k, v in sorted(Counter(m['element'] for m in g).items()))}.")
        w(f"- **Trigger:** {ABIL[a][1]}" + (" (usable via the Skill command)" if ABIL[a][1] == 'active' else " (no Skill-command use)"))
        w(f"- **Spec:** {ABIL[a][2]}")
        w(f"- **Primitives:** {', '.join('`'+p+'`' for p in ABIL[a][3])}")
        if a in COND: w(f"- **Map dependency:** {COND[a]}.")
        w("")
w("## Index\n")
w("The machine-readable index is `docs/data/ability_index.csv` (archetype, trigger, counts, spec, primitives, role/element spread).")
open(os.path.join(DOCS, 'ABILITIES.md'), 'w', encoding='utf-8').write("\n".join(B))
say('wrote', os.path.join(DOCS, 'BALANCE-REPORT.md'), os.path.join(DOCS, 'ABILITIES.md'))
say('counts abilities', len(AB), 'styles', len(sc), 'rules', len(rc), 'wins', len(wc), 'dead_skill', dead_skill, 'prims', len(prims))
say('broken', broken); say('unfair', unfair)
