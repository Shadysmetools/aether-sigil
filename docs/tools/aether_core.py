"""Aether Sigil balance analysis - computation core (READ-ONLY on data/).
Every number in docs/BALANCE-REPORT.md and docs/ABILITIES.md is computed here.
Run:  python -X utf8 docs/tools/aether_report.py   (writes docs/*.md and docs/data/*.csv)
"""
import json, csv, re, os, statistics as S
from collections import Counter, defaultdict, deque
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DATA = os.path.join(ROOT, 'data')
BIBLE = json.load(open(os.path.join(DATA, 'AETHER_SIGIL_MASTER_GAME_BIBLE.json'), encoding='utf-8'))
MON = BIBLE['monsters']
BYID = {m['id']: m for m in MON}
STAGES = [l for t in BIBLE['towers'] for l in t['levels']]
TOWER_OF = {l['stage_id']: t for t in BIBLE['towers'] for l in t['levels']}
RARITIES = ['Common', 'Uncommon', 'Rare', 'Epic', 'Mythic', 'Legendary']
STATS = ['hp', 'attack', 'defense', 'move', 'range', 'level_cap']

# ------------------------------------------------------------------ power score
A = np.array([m['attack'] for m in MON], float)
D = np.array([m['defense'] for m in MON], float)
H = np.array([m['hp'] for m in MON], float)
MV = np.array([m['move'] for m in MON], float)
RG = np.array([m['range'] for m in MON], float)
DMG = np.maximum(1.0, A[:, None] - D[None, :])      # DMG[i,j] = base damage when i hits j
OUT = DMG.mean(axis=1)                               # avg damage i deals per hit vs the whole population
INC = DMG.mean(axis=0)                               # avg damage i takes per hit from the whole population
MOB = 1 + 0.05 * (MV - MV.mean()) + 0.05 * (RG - RG.mean())
POWER = OUT * (H / INC) * MOB / 100.0
for i, m in enumerate(MON):
    m['_power'] = float(POWER[i]); m['_out'] = float(OUT[i]); m['_inc'] = float(INC[i])
POWER_FORMULA = ("power = mean_j[max(1, atk - def_j)] x hp / mean_j[max(1, atk_j - def)] "
                 "x (1 + 0.05*(move - mean_move) + 0.05*(range - mean_range)) / 100, "
                 "with j over all 1000 monsters")

def zs(vals):
    mu, sd = S.mean(vals), S.pstdev(vals)
    return [(v - mu) / sd if sd else 0.0 for v in vals], mu, sd

def eta2(key, f):
    """share of variance of stat f explained by grouping `key` (one-way ANOVA eta^2)"""
    v = [m[f] for m in MON]; mu = S.mean(v)
    sst = sum((x - mu) ** 2 for x in v)
    groups = defaultdict(list)
    for m in MON: groups[m[key]].append(m[f])
    ssb = sum(len(g) * (S.mean(g) - mu) ** 2 for g in groups.values())
    return ssb / sst if sst else 0.0

# ------------------------------------------------------------------ damage floor
FLOOR_PAIRS = float((A[:, None] <= D[None, :]).mean())          # attacker atk <= defender def -> 1 dmg
HTK = np.ceil(H[None, :] / DMG)                                 # hits for i to KO j
HTK_MED = float(np.median(HTK))
HTK_GT20 = float((HTK > 20).mean()); HTK_GT50 = float((HTK > 50).mean()); HTK_LE5 = float((HTK <= 5).mean())

# ------------------------------------------------------------------ maps
def grid_find(g, name): return [(r, c) for r in range(12) for c in range(12) if g[r][c] == name]
def nbrs(r, c):
    for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        rr, cc = r + dr, c + dc
        if 0 <= rr < 12 and 0 <= cc < 12: yield rr, cc
def walkable(g, stone_blocks):
    blk = {'obstacle'} | ({'stone'} if stone_blocks else set())
    return {(r, c) for r in range(12) for c in range(12) if g[r][c] not in blk}
def bfs(W, sources, warps=None):
    dist = {s: 0 for s in sources if s in W}; q = deque(dist)
    while q:
        u = q.popleft(); nx = list(nbrs(*u))
        if warps and u in warps: nx += [w for w in warps if w != u]
        for v in nx:
            if v in W and v not in dist:
                dist[v] = dist[u] + 1; q.append(v)
    return dist
def articulation(W, root):
    """articulation vertices of the 4-neighbour graph on W, in root's component (iterative Tarjan)"""
    disc, low, par, child, ap, t = {root: 0}, {root: 0}, {root: None}, Counter(), set(), 0
    stack = [(root, iter(list(nbrs(*root))))]
    while stack:
        u, it = stack[-1]; pushed = False
        for v in it:
            if v not in W: continue
            if v not in disc:
                t += 1; disc[v] = low[v] = t; par[v] = u; child[u] += 1
                stack.append((v, iter(list(nbrs(*v))))); pushed = True; break
            elif v != par[u]:
                low[u] = min(low[u], disc[v])
        if not pushed:
            stack.pop(); p = par[u]
            if p is not None:
                low[p] = min(low[p], low[u])
                if par[p] is not None and low[u] >= disc[p]: ap.add(p)
    if child[root] > 1: ap.add(root)
    return ap

def analyse_map(l, stone_blocks=False):
    g = l['map_grid']; W = walkable(g, stone_blocks)
    ps, es = grid_find(g, 'player_spawn'), grid_find(g, 'enemy_spawn')
    psym, esym = grid_find(g, 'player_symbol'), grid_find(g, 'enemy_symbol')
    caps, rel, warps = grid_find(g, 'capsule_node'), grid_find(g, 'relic'), grid_find(g, 'warp_gate')
    dp, de, dpw = bfs(W, ps), bfs(W, es), bfs(W, ps, set(warps))
    r = dict(stage_id=l['stage_id'], walkable_pct=100 * len(W) / 144,
             n_player_spawn=len(ps), n_enemy_spawn=len(es), n_psym=len(psym), n_esym=len(esym),
             n_caps=len(caps), n_relic=len(rel), n_warp=len(warps), n_bridge=len(grid_find(g, 'bridge')),
             n_elev=len(grid_find(g, 'elevation')), n_water=len(grid_find(g, 'water')),
             n_hazard=len(grid_find(g, 'hazard')), n_stone=len(grid_find(g, 'stone')),
             n_forest=len(grid_find(g, 'forest')), n_obstacle=len(grid_find(g, 'obstacle')))
    r['path_p2esym'] = min((dp[x] for x in esym if x in dp), default=None)
    r['path_e2psym'] = min((de[x] for x in psym if x in de), default=None)
    r['path_p2esym_warp'] = min((dpw[x] for x in esym if x in dpw), default=None)
    r['reach_pct'] = 100 * len(dp) / len(W) if W else 0
    r['spawns_connected'] = bool(es) and all(e in dp for e in es)
    r['chokepoints'] = len(articulation(W, ps[0])) if ps and ps[0] in W else None
    diffs = [None if dp.get(c) is None or de.get(c) is None else dp[c] - de[c] for c in caps]
    valid = [x for x in diffs if x is not None]
    r['cap_diffs'] = diffs
    r['cap_diff_sum'] = sum(valid) if valid else None
    r['cap_unreachable'] = sum(1 for x in diffs if x is None)
    rd = [dp[x] - de[x] for x in rel if x in dp and x in de]
    r['relic_diff_sum'] = sum(rd) if rd else None
    # template-corrected fairness: enemy spawns replaced by the point-mirror (11-r, 11-c) of the player spawns,
    # isolating map-specific bias from the shared (asymmetric) spawn template
    r['spawns_point_symmetric'] = set(es) == {(11 - a, 11 - b) for a, b in ps}
    dm = bfs(W, [(11 - a, 11 - b) for a, b in ps])
    vm = [dp[c] - dm[c] for c in caps if c in dp and c in dm]
    r['cap_diff_sum_mirror'] = sum(vm) if vm else None
    r['path_e2psym_mirror'] = min((dm[x] for x in psym if x in dm), default=None)
    # bridges that are real chokepoints (articulation vertices)
    art = articulation(W, ps[0]) if ps and ps[0] in W else set()
    r['bridge_chokepoints'] = sum(1 for x in grid_find(g, 'bridge') if x in art)
    return r

def integrity(l):
    """objective tiles that disagree with the grid; JSON spawn tiles that are not spawn tiles on the grid"""
    g = l['map_grid']; bad = []
    for o in l['objectives']:
        rr, cc = o['tile']
        if g[rr][cc] != o['type']: bad.append(f"{o['type']}@{tuple(o['tile'])} is '{g[rr][cc]}'")
    sp_bad = sum(1 for t in l['player_spawns'] if g[t[0]][t[1]] != 'player_spawn') + \
             sum(1 for t in l['enemy_spawns'] if g[t[0]][t[1]] != 'enemy_spawn')
    return bad, sp_bad

# ------------------------------------------------------------------ PDF / CSV drift
def pdf_text():
    import fitz
    return ''.join(p.get_text() for p in fitz.open(os.path.join(DATA, 'AETHER_SIGIL_GAME_BIBLE.pdf')))
def pdf_stages(txt):
    lines = [x.strip() for x in txt.splitlines()]
    out = {}
    for i, x in enumerate(lines):
        if re.fullmatch(r'T\d\d-L\d\d', x) and i + 3 < len(lines):
            out[x] = dict(opponent=lines[i + 1], rule=lines[i + 2], win=lines[i + 3])
    return out
def read_csv(name):
    return list(csv.DictReader(open(os.path.join(DATA, name), encoding='utf-8-sig')))
