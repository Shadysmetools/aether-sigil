"""Aether Sigil placeholder-art generator (original work).

One primitive list per image -> emitted as SVG *and* rasterised with Pillow (4x supersample,
LANCZOS down), so SVG and PNG always match. No gradients/filters: flat cel-shaded facets,
glows are stacked low-alpha shapes. Every colour is a lerp of the 7 brand tokens.

Run:  python art/generated/tools/aether_art.py      (from the Emberwick folder, or anywhere)
"""
import json
import math
import random
import zlib
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
GEN = HERE.parent                      # art/generated
ROOT = GEN.parent.parent               # Emberwick
BIBLE = ROOT / "data" / "AETHER_SIGIL_MASTER_GAME_BIBLE.json"
SVG_DIR = GEN / "svg"
PNG_DIR = GEN / "png"
PREVIEW_DIR = GEN / "previews"
SS = 4  # supersample factor

# ----------------------------------------------------------------------------- colour
TOKENS = {
    "N": "#0B1220", "Cy": "#22D3EE", "G": "#2ECC71", "E": "#FF6B3D",
    "V": "#B15CFF", "Au": "#F6C445", "S": "#D6DEE9",
}


def _h2t(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Col(tuple):
    def lerp(self, other, t):
        o = other if isinstance(other, tuple) else K[other]
        return Col(tuple(round(a + (b - a) * t) for a, b in zip(self, o)))

    @property
    def hex(self):
        return "#%02X%02X%02X" % self[:3]


K = {k: Col(_h2t(v)) for k, v in TOKENS.items()}
N, Cy, G, E, V, Au, S = (K[k] for k in ("N", "Cy", "G", "E", "V", "Au", "S"))

FAMILY = {  # identical to game/scripts/theme_colors.gd family()
    "Water": Cy.lerp(V, 0.35), "Fire": E, "Wood": G, "Earth": Au.lerp(N, 0.35),
    "Thunder": Au, "Wind": Cy.lerp(S, 0.5), "Ice": S.lerp(Cy, 0.25),
    "Tech": S.lerp(N, 0.35), "Light": S, "Dark": V.lerp(N, 0.55), "Arcane": V,
    "Space": V.lerp(Cy, 0.35),
}
FAMILIES = ["Fire", "Water", "Wind", "Earth", "Wood", "Ice", "Thunder", "Light", "Dark",
            "Tech", "Space", "Arcane"]
TEAM = {"ally": Cy, "enemy": E}


# ----------------------------------------------------------------------------- geometry
def chaikin(pts, n=2, closed=True):
    for _ in range(n):
        out = []
        m = len(pts) if closed else len(pts) - 1
        for i in range(m):
            p, q = pts[i], pts[(i + 1) % len(pts)]
            out += [(p[0] * .75 + q[0] * .25, p[1] * .75 + q[1] * .25),
                    (p[0] * .25 + q[0] * .75, p[1] * .25 + q[1] * .75)]
        if not closed:
            out = [pts[0]] + out + [pts[-1]]
        pts = out
    return pts


def ellipse_pts(cx, cy, rx, ry, rot=0.0, n=48, a0=0.0, a1=360.0):
    r = math.radians(rot)
    pts = []
    for i in range(n + 1 if a1 - a0 < 360 else n):
        a = math.radians(a0 + (a1 - a0) * i / n)
        x, y = rx * math.cos(a), ry * math.sin(a)
        pts.append((cx + x * math.cos(r) - y * math.sin(r), cy + x * math.sin(r) + y * math.cos(r)))
    return pts


def star_pts(cx, cy, r_out, r_in, n=4, rot=-90.0, sy=1.0):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180.0 / n)
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a) * sy))
    return pts


def ring_pts(cx, cy, rx, ry, w, rot=0.0, n=56):
    """Thick ring as one polygon (outer CW then inner CCW, joined by a hairline seam)."""
    o = ellipse_pts(cx, cy, rx, ry, rot, n)
    i = ellipse_pts(cx, cy, rx - w, ry - w * ry / rx, rot, n)
    return o + [o[0]] + [i[0]] + i[::-1]


def crescent(c1, r1, c2, r2, n=40):
    # outer arc of circle1 outside circle2, inner arc of circle2 inside circle1
    d = math.dist(c1, c2)
    a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
    h = math.sqrt(max(r1 * r1 - a * a, 0))
    ex, ey = (c2[0] - c1[0]) / d, (c2[1] - c1[1]) / d
    px, py = c1[0] + a * ex, c1[1] + a * ey
    i1 = (px + h * ey, py - h * ex)
    i2 = (px - h * ey, py + h * ex)

    def ang(c, p):
        return math.atan2(p[1] - c[1], p[0] - c[0])

    pts = []
    s, e = ang(c1, i1), ang(c1, i2)
    while e > s:
        e -= 2 * math.pi
    for k in range(n + 1):  # long way round (away from c2)
        t = s + (e - s) * k / n
        pts.append((c1[0] + r1 * math.cos(t), c1[1] + r1 * math.sin(t)))
    s2, e2 = ang(c2, i2), ang(c2, i1)
    while e2 < s2:
        e2 += 2 * math.pi
    if e2 - s2 > math.pi:
        e2 -= 2 * math.pi
    for k in range(n + 1):
        t = s2 + (e2 - s2) * k / n
        pts.append((c2[0] + r2 * math.cos(t), c2[1] + r2 * math.sin(t)))
    return pts


# ----------------------------------------------------------------------------- canvas
class Canvas:
    """Items: ('poly', pts, fill, alpha, stroke, sw) | ('line', pts, stroke, sw, alpha, closed)
    | ('ell', cx, cy, rx, ry, fill, alpha, stroke, sw)."""

    def __init__(self, w, h):
        self.w, self.h, self.items = w, h, []

    def poly(self, pts, fill, alpha=1.0, stroke=None, sw=0.0):
        self.items.append(("poly", list(pts), fill, alpha, stroke, sw))

    def line(self, pts, stroke, sw=1.0, alpha=1.0, closed=False):
        self.items.append(("line", list(pts), stroke, sw, alpha, closed))

    def ell(self, cx, cy, rx, ry, fill, alpha=1.0, stroke=None, sw=0.0):
        self.items.append(("ell", cx, cy, rx, ry, fill, alpha, stroke, sw))

    def glow(self, cx, cy, rx, ry, col, steps=5, alpha=0.10):
        for i in range(steps):
            k = 1.0 - i / steps
            self.ell(cx, cy, rx * k, ry * k, col, alpha)

    def add(self, items, s=1.0, rot=0.0, dx=0.0, dy=0.0, recolor=None):
        r = math.radians(rot)
        cr, sr = math.cos(r), math.sin(r)

        def tf(p):
            x, y = p[0] * s, p[1] * s
            return (x * cr - y * sr + dx, x * sr + y * cr + dy)

        for it in items:
            if it[0] == "poly":
                _, pts, f, a, st, sw = it
                self.poly([tf(p) for p in pts], recolor or f, a, st, sw * s)
            elif it[0] == "line":
                _, pts, st, sw, a, cl = it
                self.line([tf(p) for p in pts], recolor or st, sw * s, a, cl)
            else:
                _, cx, cy, rx, ry, f, a, st, sw = it
                if rot:
                    self.poly([tf(p) for p in ellipse_pts(cx, cy, rx, ry)], recolor or f, a, st, sw * s)
                else:
                    c = tf((cx, cy))
                    self.ell(c[0], c[1], rx * s, ry * s, recolor or f, a, st, sw * s)

    # -------------------------------------------------- SVG
    def svg(self, title=""):
        f2 = lambda v: ("%.2f" % v).rstrip("0").rstrip(".")
        pts = lambda P: " ".join(f2(x) + "," + f2(y) for x, y in P)
        out = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
               % (self.w, self.h, self.w, self.h)]
        if title:
            out.append("<title>%s</title>" % title)
        for it in self.items:
            if it[0] == "poly":
                _, P, f, a, st, sw = it
                attrs = 'fill="%s"' % (f.hex if f else "none")
                if st and sw:
                    attrs += ' stroke="%s" stroke-width="%s" stroke-linejoin="round"' % (st.hex, f2(sw))
                if a < 1:
                    attrs += ' opacity="%s"' % f2(a)
                out.append('<polygon points="%s" %s/>' % (pts(P), attrs))
            elif it[0] == "line":
                _, P, st, sw, a, cl = it
                tag = "polygon" if cl else "polyline"
                attrs = 'fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round" stroke-linecap="round"' % (st.hex, f2(sw))
                if a < 1:
                    attrs += ' opacity="%s"' % f2(a)
                out.append('<%s points="%s" %s/>' % (tag, pts(P), attrs))
            else:
                _, cx, cy, rx, ry, f, a, st, sw = it
                attrs = 'fill="%s"' % (f.hex if f else "none")
                if st and sw:
                    attrs += ' stroke="%s" stroke-width="%s"' % (st.hex, f2(sw))
                if a < 1:
                    attrs += ' opacity="%s"' % f2(a)
                out.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" %s/>' % (f2(cx), f2(cy), f2(rx), f2(ry), attrs))
        out.append("</svg>")
        return "\n".join(out)

    # -------------------------------------------------- PNG
    def png(self, scale):
        k = scale * SS
        W, H = round(self.w * k), round(self.h * k)
        img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for it in self.items:
            alpha = it[3] if it[0] == "poly" else (it[4] if it[0] == "line" else it[6])
            if alpha >= 1:
                self._draw(ImageDraw.Draw(img), it, k)
            else:
                layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
                self._draw(ImageDraw.Draw(layer), it, k)
                bb = layer.getbbox()
                if not bb:
                    continue
                crop = layer.crop(bb)
                a = crop.getchannel("A").point(lambda v: round(v * alpha))
                crop.putalpha(a)
                img.alpha_composite(crop, dest=bb[:2])
        return img.resize((round(self.w * scale), round(self.h * scale)), Image.LANCZOS)

    @staticmethod
    def _stroke(d, P, col, w, closed):
        if closed:
            P = P + [P[0]]
        rgba = tuple(col) + (255,)
        d.line(P, fill=rgba, width=max(1, round(w)), joint="curve")
        r = w / 2.0
        if r >= 1:
            for x, y in P:
                d.ellipse((x - r, y - r, x + r, y + r), fill=rgba)

    def _draw(self, d, it, k):
        if it[0] == "poly":
            _, P, f, a, st, sw = it
            P = [(x * k, y * k) for x, y in P]
            if f:
                d.polygon(P, fill=tuple(f) + (255,))
            if st and sw:
                self._stroke(d, P, st, sw * k, True)
        elif it[0] == "line":
            _, P, st, sw, a, cl = it
            self._stroke(d, [(x * k, y * k) for x, y in P], st, sw * k, cl)
        else:
            _, cx, cy, rx, ry, f, a, st, sw = it
            bb = ((cx - rx) * k, (cy - ry) * k, (cx + rx) * k, (cy + ry) * k)
            if f:
                d.ellipse(bb, fill=tuple(f) + (255,))
            if st and sw:
                d.ellipse(bb, outline=tuple(st) + (255,), width=max(1, round(sw * k)))


WRITTEN = []  # (svg_path, png_path, purpose)


def save(cv, rel, scale, purpose, title=""):
    sp = SVG_DIR / (rel + ".svg")
    pp = PNG_DIR / (rel + ".png")
    sp.parent.mkdir(parents=True, exist_ok=True)
    pp.parent.mkdir(parents=True, exist_ok=True)
    sp.write_text(cv.svg(title or rel), encoding="utf-8")
    cv.png(scale).save(pp, optimize=True)
    WRITTEN.append((sp, pp, purpose))


def rng(*key):
    return random.Random(zlib.crc32("|".join(map(str, key)).encode()))


# ============================================================================= TILES
TW, TH = 128, 64           # diamond top face
CW, CH = 128, 160          # tile canvas
GX, GY = 64, 124           # ground-plane diamond centre (the Godot anchor)
MIN_LIFT = 6.0             # thin slab, matches board_art.gd max(raise, 4px @ 42)
RAISE = {"stone": 0.35, "elevation": 0.6, "obstacle": 0.8}   # game/data/game_rules.json

TOWERS = [
    # id, slug, name, cover(top), rock, accent, motif, obstacle builder
    ("T01", "verdant_spire", "Verdant Spire", G.lerp(N, 0.42).lerp(Au, 0.08), S.lerp(G, 0.25).lerp(N, 0.45), G, "moss", "boulder"),
    ("T02", "ember_bastion", "Ember Bastion", N.lerp(E, 0.16).lerp(S, 0.06), N.lerp(S, 0.16).lerp(E, 0.12), E, "embercrack", "basalt"),
    ("T03", "tideglass_citadel", "Tideglass Citadel", Cy.lerp(S, 0.45).lerp(N, 0.38), S.lerp(Cy, 0.3).lerp(N, 0.42), Cy, "glass", "seaglass"),
    ("T04", "frost_meridian", "Frost Meridian", S.lerp(Cy, 0.14).lerp(N, 0.06), S.lerp(N, 0.38).lerp(Cy, 0.1), Cy.lerp(S, 0.45), "frost", "icespike"),
    ("T05", "iron_labyrinth", "Iron Labyrinth", S.lerp(N, 0.58), S.lerp(N, 0.42), E.lerp(Au, 0.5), "plates", "pillar"),
    ("T06", "storm_crown", "Storm Crown", S.lerp(Cy, 0.3).lerp(N, 0.28), S.lerp(N, 0.32), Cy, "wind", "rod"),
    ("T07", "obsidian_eclipse", "Obsidian Eclipse", V.lerp(N, 0.8), N.lerp(V, 0.28), V, "veins", "obsidian"),
    ("T08", "sunken_archive", "Sunken Archive", Cy.lerp(G, 0.3).lerp(N, 0.62), S.lerp(Au, 0.25).lerp(N, 0.5), Cy, "runes", "column"),
    ("T09", "astral_observatory", "Astral Observatory", V.lerp(N, 0.66).lerp(Cy, 0.08), N.lerp(S, 0.3).lerp(V, 0.15), Au, "stars", "orrery"),
    ("T10", "crystal_sanctum", "Crystal Sanctum", V.lerp(S, 0.35).lerp(N, 0.35), V.lerp(N, 0.5), V.lerp(S, 0.4), "facets", "crystals"),
    ("T11", "rift_frontier", "Rift Frontier", V.lerp(N, 0.62).lerp(E, 0.08), N.lerp(V, 0.36), V.lerp(E, 0.35), "rift", "floatrock"),
    ("T12", "sunforge_throne", "Sunforge Throne", Au.lerp(S, 0.42).lerp(N, 0.3), S.lerp(Au, 0.3).lerp(N, 0.28), Au, "gilded", "goldcolumn"),
]
TILE_TYPES = ["ground", "stone", "obstacle", "bridge", "capsule_node", "player_symbol", "enemy_symbol",
              "player_spawn", "enemy_spawn", "relic", "warp_gate", "elevation", "hazard", "forest",
              "lava", "water", "ice", "metal", "shadow", "crystal", "mixed"]


class Face:
    """Top face of a tile lifted by `lift` px. uv in [0,1]^2: u runs top->right vertex
    (screen down-right, = the board's x axis), v runs top->left vertex."""

    def __init__(self, lift):
        self.lift = lift
        self.ty = GY - lift
        self.A = (GX, self.ty - TH / 2)

    def p(self, u, v):
        return (self.A[0] + u * TW / 2 - v * TW / 2, self.A[1] + u * TH / 2 + v * TH / 2)

    def map(self, uvs):
        return [self.p(u, v) for u, v in uvs]

    def diamond(self, inset=0.0, grow=0.0):
        a, b = inset - grow, 1 - inset + grow
        return self.map([(a, a), (b, a), (b, b), (a, b)])

    def circle(self, cu, cv, r, n=40, a0=0, a1=360):
        pts = []
        for i in range(n):
            t = math.radians(a0 + (a1 - a0) * i / n)
            pts.append(self.p(cu + r * math.cos(t), cv + r * math.sin(t)))
        return pts

    def star(self, cu, cv, ro, ri, n=4, rot=0):
        pts = []
        for i in range(n * 2):
            t = math.radians(rot + i * 180 / n)
            r = ro if i % 2 == 0 else ri
            pts.append(self.p(cu + r * math.cos(t), cv + r * math.sin(t)))
        return pts


def block(cv, lift, top, side_base, outline=True):
    f = Face(lift)
    L, B, R = (0, f.ty), (GX, f.ty + TH / 2), (CW, f.ty)
    gL, gB, gR = (0, GY), (GX, GY + TH / 2), (CW, GY)
    cv.poly([L, B, gB, gL], side_base.lerp(N, 0.30))
    cv.poly([B, R, gR, gB], side_base.lerp(N, 0.52))
    if lift > 14:  # stone courses on tall sides
        for k in range(1, int(lift // 14) + 1):
            y = k * 14
            cv.line([(L[0], L[1] + y), (B[0], B[1] + y)], N, 0.8, 0.35)
            cv.line([(B[0], B[1] + y), (R[0], R[1] + y)], N, 0.8, 0.35)
    cv.poly(f.diamond(grow=0.006), top)
    # lit rim on the two front edges (cel highlight) + dark outline
    cv.line([f.p(0, 1), f.p(1, 1), f.p(1, 0)], S, 1.0, 0.28)
    if outline:
        cv.line([L, B, R], N, 1.0, 0.55)
        cv.line([B, gB], N, 0.8, 0.45)
    return f


def motif(cv, f, tw, key, density=1.0):
    tid, slug, name, cover, rock, acc, mot, _ = tw
    r = rng(tid, key, "motif")
    light, dark = cover.lerp(S, 0.22), cover.lerp(N, 0.35)
    n = max(1, int(7 * density))
    if mot == "moss":
        for _ in range(n + 3):
            u, v = r.uniform(.15, .85), r.uniform(.15, .85)
            cv.poly(f.circle(u, v, r.uniform(.05, .09), 12), G.lerp(N, r.choice([.2, .55])), 0.75)
        for _ in range(3):
            q = f.p(r.uniform(.2, .8), r.uniform(.2, .8))
            cv.ell(q[0], q[1], 1.3, 1.0, S.lerp(Au, .3))
    elif mot == "embercrack":
        for _ in range(2):
            u, v = r.uniform(.2, .5), r.uniform(.2, .5)
            pts = [(u, v)]
            for _ in range(3):
                u, v = u + r.uniform(.05, .18), v + r.uniform(-.1, .18)
                pts.append((min(u, .9), min(max(v, .1), .9)))
            P = f.map(pts)
            cv.line(P, E, 2.6, 0.25)
            cv.line(P, E.lerp(Au, .4), 1.0, 0.9)
    elif mot == "glass":
        for _ in range(n):
            u, v, s = r.uniform(.15, .8), r.uniform(.15, .8), r.uniform(.06, .12)
            cv.poly(f.map([(u, v), (u + s, v + s * .3), (u + s * .7, v + s), (u - s * .2, v + s * .6)]), Cy.lerp(S, .5), 0.35)
        cv.line(f.circle(.5, .5, .28, 24, 200, 320), S, 0.8, 0.4)
    elif mot == "frost":
        for _ in range(n):
            q = f.p(r.uniform(.15, .85), r.uniform(.15, .85))
            cv.poly(star_pts(q[0], q[1], 3.2, .8, 4, -90, .6), S, 0.85)
        cv.line(f.map([(.3, .2), (.42, .38), (.38, .55), (.55, .7)]), N.lerp(Cy, .4), 0.8, 0.45)
    elif mot == "plates":
        cv.line([f.p(.5, .04), f.p(.5, .96)], N, 1.0, 0.5)
        cv.line([f.p(.04, .5), f.p(.96, .5)], N, 1.0, 0.5)
        for u in (.12, .38, .62, .88):
            for v in (.12, .38, .62, .88):
                if r.random() < .5:
                    q = f.p(u, v)
                    cv.ell(q[0], q[1], 1.3, .8, S.lerp(N, .2))
        cv.line([f.p(.1, .5 + .04), f.p(.9, .5 + .04)], acc, 0.9, 0.5)
    elif mot == "wind":
        for i in range(3):
            v = .25 + i * .22 + r.uniform(-.04, .04)
            pts = [(.1 + .05 * i, v), (.45, v - .04), (.75, v + .02), (.85, v - .06)]
            cv.line(f.map(chaikin(pts, 2, False)), S, 1.0, 0.5)
    elif mot == "veins":
        for _ in range(2):
            u, v = r.uniform(.15, .4), r.uniform(.2, .7)
            pts = [(u, v)]
            for _ in range(4):
                u, v = u + r.uniform(.08, .16), v + r.uniform(-.12, .12)
                pts.append((min(u, .9), min(max(v, .1), .9)))
            cv.line(f.map(pts), V, 2.4, 0.22)
            cv.line(f.map(pts), V.lerp(S, .3), 0.8, 0.8)
    elif mot == "runes":
        for a in (.33, .66):
            cv.line([f.p(a, .03), f.p(a, .97)], N, 0.8, 0.45)
            cv.line([f.p(.03, a), f.p(.97, a)], N, 0.8, 0.45)
        q = .5
        cv.line(f.map([(q - .08, q - .08), (q + .08, q - .08), (q, q + .1), (q - .08, q - .08)]), Cy.lerp(S, .3), 1.0, 0.55)
    elif mot == "stars":
        for _ in range(n + 4):
            q = f.p(r.uniform(.1, .9), r.uniform(.1, .9))
            rr = r.uniform(.5, 1.2)
            cv.ell(q[0], q[1], rr, rr, r.choice([Au, S, S]), 0.9)
        cv.line(f.circle(.5, .5, .33, 40), Au, 0.7, 0.35, )
    elif mot == "facets":
        c = f.p(.5, .5)
        for (u, v) in [(0, 0), (1, 0), (1, 1), (0, 1)]:
            cv.line([c, f.p(u * .9 + .05, v * .9 + .05)], S, 0.8, 0.3)
        cv.poly(f.map([(.5, .5), (.95, .05), (.95, .5)]), S, 0.08)
        cv.poly(f.map([(.5, .5), (.05, .95), (.5, .95)]), N, 0.12)
    elif mot == "rift":
        for _ in range(n):
            q = f.p(r.uniform(.15, .85), r.uniform(.15, .85))
            cv.poly(star_pts(q[0], q[1], 2.2, .9, 4, -90, .6), V.lerp(S, .4), 0.7)
        P = f.map([(.25, .55), (.4, .48), (.52, .6), (.7, .5)])
        cv.line(P, E.lerp(V, .4), 2.2, 0.35)
        cv.line(P, S, 0.6, 0.6)
    elif mot == "gilded":
        cv.line(f.diamond(inset=.1), Au, 1.0, 0.75, closed=True)
        cv.poly(f.map([(.5, .38), (.62, .5), (.5, .62), (.38, .5)]), Au, 0.6)
    del light, dark


def tile_obstacle_topper(cv, f, tw):
    tid, slug, name, cover, rock, acc, mot, kind = tw
    c = f.p(.5, .5)
    x, y = c
    hi, lo = rock.lerp(S, .25), rock.lerp(N, .35)
    if kind in ("boulder", "orrery", "floatrock"):
        base = rock if kind != "floatrock" else rock.lerp(V, .15)
        dy = -6 if kind == "floatrock" else 0
        if kind == "floatrock":
            cv.ell(x, y + 4, 22, 8, N, 0.35)
        body = chaikin([(x - 26, y + 4 + dy), (x - 20, y - 14 + dy), (x - 4, y - 24 + dy), (x + 14, y - 20 + dy),
                        (x + 26, y - 4 + dy), (x + 16, y + 10 + dy), (x - 8, y + 12 + dy)], 2)
        cv.poly(body, base, 1, N, 1.4)
        cv.poly(chaikin([(x - 20, y - 12 + dy), (x - 4, y - 22 + dy), (x + 12, y - 18 + dy), (x + 2, y - 8 + dy), (x - 14, y - 4 + dy)], 2), hi)
        if kind == "boulder":   # moss cap
            cv.poly(chaikin([(x - 18, y - 13), (x - 4, y - 23), (x + 13, y - 19), (x + 6, y - 14), (x - 10, y - 8)], 2), G.lerp(N, .25))
            for i in range(4):
                cv.line([(x - 12 + i * 7, y - 10), (x - 13 + i * 7, y - 3)], G.lerp(N, .35), 1.4)
        elif kind == "orrery":
            cv.line(ellipse_pts(x, y - 30, 16, 5, -15), Au, 1.4)
            cv.poly(star_pts(x, y - 30, 7, 2, 4), Au, 1, N, 0.8)
        else:
            cv.line([(x - 10, y - 4 + dy), (x + 2, y - 12 + dy), (x + 12, y - 2 + dy)], V.lerp(E, .35), 1.6, 0.9)
    elif kind in ("basalt", "seaglass", "icespike", "obsidian", "crystals"):
        col = {"basalt": N.lerp(S, .2), "seaglass": Cy.lerp(S, .35), "icespike": S.lerp(Cy, .3),
               "obsidian": N.lerp(V, .35), "crystals": V.lerp(S, .25)}[kind]
        spikes = [(-14, 30, 9), (2, 44, 10), (16, 26, 8), (-4, 22, 7)]
        for dx, h, w in spikes:
            bx, by = x + dx, y + 4 - abs(dx) * .15
            L, R, T = (bx - w, by), (bx + w, by), (bx + dx * .1, by - h)
            M = (bx + w * .15, by + 3)
            cv.poly([L, T, M], col, 1, N, 1.2)
            cv.poly([M, T, R], col.lerp(N, .35), 1, N, 1.2)
            cv.line([T, (bx - w * .35, by - h * .3)], S, 0.8, .6)
        if kind == "basalt":
            cv.line([(x - 4, y - 2), (x + 2, y - 18), (x + 1, y - 30)], E.lerp(Au, .3), 1.3, .9)
            cv.glow(x, y - 8, 10, 10, E, 3, .08)
    elif kind in ("pillar",):
        w, h = 18, 34
        L, Bm, R = (x - w, y), (x, y + w / 2), (x + w, y)
        T = (x, y - w / 2)
        cv.poly([L, Bm, (Bm[0], Bm[1] - h), (L[0], L[1] - h)], rock.lerp(N, .2), 1, N, 1)
        cv.poly([Bm, R, (R[0], R[1] - h), (Bm[0], Bm[1] - h)], rock.lerp(N, .45), 1, N, 1)
        cv.poly([(L[0], L[1] - h), (T[0], T[1] - h), (R[0], R[1] - h), (Bm[0], Bm[1] - h)], rock.lerp(S, .2), 1, N, 1)
        cv.line([(x - w + 3, y - 12), (x, y + w / 2 - 12)], acc, 1.6, .9)
        cv.line([(x + 3, y + w / 2 - 22), (x + w - 2, y - 20)], acc, 1.6, .7)
    else:  # column / rod / goldcolumn
        colr = {"column": S.lerp(Au, .25).lerp(N, .3), "rod": S.lerp(N, .35), "goldcolumn": S.lerp(Au, .35)}[kind]
        w, h = 11, 36 if kind != "column" else 26
        cv.ell(x, y, w + 5, (w + 5) / 2, colr.lerp(N, .3), 1, N, 1)
        cv.poly([(x - w, y - 2), (x + w, y - 2), (x + w, y - h), (x - w, y - h)], colr, 1, N, 1)
        cv.poly([(x + 2, y - 2), (x + w, y - 2), (x + w, y - h), (x + 2, y - h)], colr.lerp(N, .3))
        for k in (-6, 0):
            cv.line([(x + k, y - 3), (x + k, y - h + 2)], N, 0.7, .4)
        if kind == "column":  # broken top
            cv.poly([(x - w, y - h), (x - 4, y - h - 6), (x + 3, y - h - 2), (x + w, y - h - 7), (x + w, y - h)], colr.lerp(S, .2), 1, N, 1)
        else:
            cv.ell(x, y - h, w, w / 2, colr.lerp(S, .25), 1, N, 1)
        if kind == "rod":
            cv.line([(x, y - h), (x, y - h - 18)], S, 2.2)
            cv.poly(star_pts(x, y - h - 20, 6, 1.6, 4), Cy, 1, N, .6)
            cv.glow(x, y - h - 20, 10, 10, Cy, 3, .1)
        if kind == "goldcolumn":
            cv.poly([(x - 6, y - h - 2), (x, y - h - 14), (x + 6, y - h - 2)], Au, 1, N, 1)


def tri(cx, cy, r, rot=-90):
    return [(cx + r * math.cos(math.radians(rot + i * 120)), cy + r * math.sin(math.radians(rot + i * 120))) for i in range(3)]


def make_tile(tw, ttype, alt=False, variant=0):
    tid, slug, name, cover, rock, acc, mot, _ = tw
    cv = Canvas(CW, CH)
    lift = MIN_LIFT
    top, side = cover, rock
    if ttype in RAISE:
        lift = RAISE[ttype] * TH
    if ttype == "stone":
        top = rock.lerp(S, .12)
    if ttype == "obstacle":
        top = rock
    if ttype == "elevation":
        top = cover.lerp(S, .14)
    terr = {"forest": G.lerp(N, .38), "lava": N.lerp(E, .18), "water": cover, "ice": Cy.lerp(S, .62),
            "metal": S.lerp(Cy, .2).lerp(N, .48), "shadow": V.lerp(N, .76), "crystal": V.lerp(S, .38).lerp(N, .1)}
    if ttype in terr:
        top = terr[ttype]
    if ttype == "bridge":
        # chasm: the slab is a hollow — draw dark void with far-side cliff hint
        f = Face(MIN_LIFT)
        cv.poly(f.diamond(grow=.006), N.lerp(V, .12), 0.85)
        cv.poly(f.map([(0, 0), (1, 0), (1, .12), (0, .12)]) if not alt else f.map([(0, 0), (.12, 0), (.12, 1), (0, 1)]), rock.lerp(N, .5), .7)
        wood = Au.lerp(N, .5).lerp(rock, .3)
        if not alt:   # deck along u (board x axis): planks are short bars across v
            v0, v1 = .3, .7
            for i in range(9):
                u0 = .02 + i * .108
                cv.poly(f.map([(u0, v0), (u0 + .085, v0), (u0 + .085, v1), (u0, v1)]), wood.lerp(S, .08 * (i % 2)), 1, N, .8)
            for vv in (v0 - .02, v1 + .02):
                cv.line([f.p(0, vv), f.p(1, vv)], Au.lerp(N, .2), 1.6)
                for u in (.06, .5, .94):
                    q = f.p(u, vv)
                    cv.line([q, (q[0], q[1] - 7)], Au.lerp(N, .3), 1.6)
                cv.line([(f.p(.06, vv)[0], f.p(.06, vv)[1] - 6), (f.p(.94, vv)[0], f.p(.94, vv)[1] - 6)], Au, 1.0, .9)
        else:
            u0_, u1_ = .3, .7
            for i in range(9):
                v0 = .02 + i * .108
                cv.poly(f.map([(u0_, v0), (u1_, v0), (u1_, v0 + .085), (u0_, v0 + .085)]), wood.lerp(S, .08 * (i % 2)), 1, N, .8)
            for uu in (u0_ - .02, u1_ + .02):
                cv.line([f.p(uu, 0), f.p(uu, 1)], Au.lerp(N, .2), 1.6)
                for v in (.06, .5, .94):
                    q = f.p(uu, v)
                    cv.line([q, (q[0], q[1] - 7)], Au.lerp(N, .3), 1.6)
                cv.line([(f.p(uu, .06)[0], f.p(uu, .06)[1] - 6), (f.p(uu, .94)[0], f.p(uu, .94)[1] - 6)], Au, 1.0, .9)
        return cv

    f = block(cv, lift, top, side)

    if ttype in ("ground", "stone", "elevation", "obstacle") or ttype in (
            "capsule_node", "player_symbol", "enemy_symbol", "player_spawn", "enemy_spawn", "relic", "warp_gate", "hazard"):
        motif(cv, f, tw, ttype + ("" if not variant else str(variant)), 0.6 if ttype != "ground" else 1.0)
    if ttype == "stone":
        for (a, b) in [(0, 0), (.5, 0), (.5, .5), (0, .5)]:
            cv.line(f.map([(a + .04, b + .04), (a + .46, b + .04), (a + .46, b + .46), (a + .04, b + .46)]), N, 0.9, .4, True)
    elif ttype == "obstacle":
        tile_obstacle_topper(cv, f, tw)
    elif ttype == "elevation":
        cv.line([f.p(0, 1), f.p(1, 1), f.p(1, 0)], Au, 1.4, .6)
        x, y = f.p(.5, .5)
        for k, a in ((0, .8), (7, .5)):
            cv.line([(x - 11, y + 4 - k), (x, y - 2 - k), (x + 11, y + 4 - k)], Au, 2.0, a)
    elif ttype == "capsule_node":
        cv.poly(f.circle(.5, .5, .36, 40), N, .35)
        cv.line(f.circle(.5, .5, .36, 40), Cy, 1.4, .85, True)
        hexa = [f.p(.5 + .2 * math.cos(math.radians(30 + 60 * i)), .5 + .2 * math.sin(math.radians(30 + 60 * i))) for i in range(6)]
        cv.poly(hexa, Cy.lerp(N, .45), 1, Cy, 1.2)
        for i in range(0, 6, 2):
            cv.line([f.p(.5, .5), hexa[i]], Cy.lerp(S, .4), .8, .7)
        for t in (45, 135, 225, 315):
            q = f.p(.5 + .43 * math.cos(math.radians(t)), .5 + .43 * math.sin(math.radians(t)))
            cv.ell(q[0], q[1], 1.6, 1.0, Au)
    elif ttype in ("player_symbol", "enemy_symbol"):
        tc = Cy if ttype == "player_symbol" else E
        cv.poly(f.circle(.5, .5, .42, 48), tc.lerp(N, .6), .55)
        cv.line(f.circle(.5, .5, .42, 48), Au, 1.4, .9, True)
        cv.line(f.circle(.5, .5, .34, 48), tc, 1.0, .9, True)
        cv.poly(f.star(.5, .5, .32, .07, 4, 45), tc, 1, N, .8)
        cv.poly(f.star(.5, .5, .2, .05, 4, 0), Au, 1, N, .6)
    elif ttype in ("player_spawn", "enemy_spawn"):
        tc = Cy if ttype == "player_spawn" else E
        cv.poly(f.diamond(inset=.08), tc, .22)
        cv.line(f.diamond(inset=.08), tc, 1.6, .9, closed=True)
        for (u, v) in [(.08, .08), (.92, .08), (.92, .92), (.08, .92)]:
            q = f.p(u, v)
            cv.ell(q[0], q[1], 2.0, 1.3, Au)
        tri_uv = [(.5, .36), (.62, .56), (.38, .56)] if ttype == "player_spawn" else [(.5, .64), (.62, .44), (.38, .44)]
        cv.poly(f.map(tri_uv), tc, .75)
    elif ttype == "relic":
        cv.poly(f.circle(.5, .5, .36, 40), Au.lerp(N, .55), .5)
        cv.line(f.circle(.5, .5, .36, 40), Au, 1.2, .85, True)
        t = [f.p(.5 + .24 * math.cos(math.radians(a)), .5 + .24 * math.sin(math.radians(a))) for a in (-135, -15, 105)]
        cv.poly(t, Au, 1, N, 1)
        cv.poly(f.star(.5, .5, .1, .03, 4, 45), S, 1, N, .6)
    elif ttype == "warp_gate":
        cv.poly(f.circle(.5, .5, .4, 48), V.lerp(N, .55), .65)
        cv.line(f.circle(.5, .5, .4, 48), V, 2.4, .95, True)
        cv.line(f.circle(.5, .5, .4, 48), V.lerp(S, .5), .8, .9, True)
        for k, r_ in enumerate((.3, .2, .1)):
            cv.line(f.circle(.5, .5, r_, 30, k * 60, k * 60 + 250), V.lerp(S, .3 + .2 * k), 1.2, .8)
    elif ttype == "hazard":
        hz = E.lerp(Au, .45)
        cv.poly(f.diamond(inset=.06), E, .14)
        r = rng(tid, "hazard")
        for _ in range(3):
            u, v = r.uniform(.2, .45), r.uniform(.2, .45)
            P = f.map([(u, v), (u + .15, v + r.uniform(0, .2)), (u + .3, v + .1), (u + .45, v + r.uniform(.15, .35))])
            cv.line(P, E, 3.0, .3)
            cv.line(P, hz, 1.2, .95)
        c = f.p(.5, .5)
        cv.glow(c[0], c[1], 22, 11, E, 4, .07)
        for (u, v) in [(.3, .7), (.7, .3), (.5, .5)]:
            q = f.p(u, v)
            cv.poly([(q[0] - 3, q[1]), (q[0], q[1] - 8), (q[0] + 3, q[1])], hz, 1, N, .7)
    elif ttype == "forest":
        r = rng(tid, "forest")
        cv.poly(f.diamond(inset=.05), G.lerp(N, .5), .5)
        spots = [(.3, .3), (.68, .32), (.32, .7), (.7, .7), (.5, .5)]
        spots.sort(key=lambda uv: uv[0] + uv[1])
        for (u, v) in spots:
            q = f.p(u + r.uniform(-.04, .04), v + r.uniform(-.04, .04))
            h = r.uniform(18, 26)
            cv.ell(q[0], q[1], 6, 3, N, .35)
            cv.poly([(q[0] - 1.6, q[1]), (q[0] + 1.6, q[1]), (q[0] + 1.6, q[1] - 5), (q[0] - 1.6, q[1] - 5)], Au.lerp(N, .6))
            cv.poly([(q[0] - 8, q[1] - 4), (q[0], q[1] - h), (q[0] + 1, q[1] - 2)], G.lerp(N, .15), 1, N, 1)
            cv.poly([(q[0] + 1, q[1] - 2), (q[0], q[1] - h), (q[0] + 8, q[1] - 4)], G.lerp(N, .45), 1, N, 1)
            cv.line([(q[0] - 2, q[1] - h * .6), (q[0], q[1] - h + 2)], G.lerp(S, .4), .9, .7)
    elif ttype == "lava":
        P = f.map(chaikin([(.0, .45), (.3, .35), (.55, .55), (.75, .45), (1, .6), (1, .8), (.7, .66), (.5, .78), (.25, .58), (0, .66)], 2))
        cv.poly(P, E)
        cv.poly(f.map(chaikin([(.1, .5), (.3, .42), (.5, .6), (.3, .52)], 1)), Au, .9)
        cv.poly(f.map([(.55, .1), (.75, .2), (.65, .3)]), E, .8)
        c = f.p(.5, .6)
        cv.glow(c[0], c[1], 30, 14, E, 4, .07)
        for (u, v) in [(.6, .55), (.85, .7)]:
            q = f.p(u, v)
            cv.ell(q[0], q[1], 1.8, 1.2, Au)
    elif ttype == "water":
        wcol = Cy.lerp(V, .35).lerp(N, .35)
        cv.poly(f.diamond(inset=.1), wcol)
        cv.poly(f.map([(.1, .1), (.9, .1), (.82, .18), (.18, .18)]), N, .35)  # inner shadow far edge
        cv.poly(f.map([(.1, .1), (.18, .18), (.18, .82), (.1, .9)]), N, .25)
        r = rng(tid, "water")
        for _ in range(4):
            u, v = r.uniform(.25, .65), r.uniform(.25, .75)
            cv.line(f.map([(u, v), (u + .08, v - .03), (u + .16, v)]), S, 1.0, .6)
        q = f.p(.65, .7)
        cv.ell(q[0], q[1], 3, 1.2, S, .7)
    elif ttype == "ice":
        cv.poly(f.map([(.15, .05), (.35, .05), (.05, .55), (.05, .3)]), S, .55)
        cv.poly(f.map([(.45, .05), (.55, .05), (.05, .75), (.05, .65)]), S, .45)
        P = f.map([(.55, .3), (.62, .5), (.8, .58), (.7, .78)])
        cv.line(P, N.lerp(Cy, .5), 1.0, .65)
        cv.line([f.p(.62, .5), f.p(.45, .62)], N.lerp(Cy, .5), .9, .6)
        q = f.p(.3, .7)
        cv.poly(star_pts(q[0], q[1], 4, 1, 4, -90, .7), S)
    elif ttype == "metal":
        cv.poly(f.diamond(inset=.08), S.lerp(N, .35))
        cv.line(f.diamond(inset=.08), N, 1.0, .6, closed=True)
        for (u, v) in [(.15, .15), (.85, .15), (.85, .85), (.15, .85)]:
            q = f.p(u, v)
            cv.ell(q[0], q[1], 1.6, 1.0, S.lerp(Cy, .2))
        cv.line([f.p(.2, .5), f.p(.8, .5)], Cy, 2.6, .25)
        cv.line([f.p(.2, .5), f.p(.8, .5)], Cy, 1.0, .95)
        for v in (.3, .7):
            cv.line([f.p(.25, v), f.p(.75, v)], N, .8, .45)
    elif ttype == "shadow":
        c = f.p(.5, .5)
        for k, (r_, a) in enumerate(((.42, .45), (.3, .6), (.18, .8))):
            cv.poly(f.circle(.5, .5, r_, 36), N, a)
        for k in range(3):
            cv.line(f.circle(.5, .5, .2 + k * .09, 24, k * 90, k * 90 + 200), V, 1.2, .7)
        cv.ell(c[0], c[1], 2.4, 1.4, V.lerp(S, .5))
    elif ttype == "crystal":
        cv.poly(f.circle(.5, .5, .38, 36), V.lerp(N, .3), .4)
        for (u, v, h, w) in [(.32, .4, 20, 5), (.58, .36, 14, 4), (.55, .62, 26, 6), (.36, .66, 12, 4)]:
            q = f.p(u, v)
            L, R, T, M = (q[0] - w, q[1]), (q[0] + w, q[1]), (q[0], q[1] - h), (q[0] + 1, q[1] + 2)
            cv.poly([L, T, M], V.lerp(S, .55), 1, N, .9)
            cv.poly([M, T, R], V.lerp(N, .1), 1, N, .9)
        c = f.p(.5, .5)
        cv.glow(c[0], c[1] - 8, 18, 12, V, 3, .08)
    elif ttype == "mixed":
        quads = [((0, 0), (.5, .5)), ((.5, 0), (1, .5)), ((.5, .5), (1, 1)), ((0, .5), (.5, 1))]
        cols = [c_.lerp(cover, .5).lerp(N, .25) for c_ in (G, E, Cy, V)]
        for ((u0, v0), (u1, v1)), c_ in zip(quads, cols):
            cv.poly(f.map([(u0, v0), (u1, v0), (u1, v1), (u0, v1)]), c_, .6)
        cv.line([f.p(.5, 0), f.p(.5, 1)], Au, 1.0, .6)
        cv.line([f.p(0, .5), f.p(1, .5)], Au, 1.0, .6)
        cv.poly(f.map([(.5, .4), (.6, .5), (.5, .6), (.4, .5)]), Au, 1, N, .8)
        cv.line([f.p(0, 1), f.p(1, 1), f.p(1, 0)], S, 1.0, .28)
    return cv


# ============================================================================= PROPS
PW, PH = 128, 192
PX, PY = 64, 176     # foot point = tile top-face centre


def pedestal(cv, x, y, col, rx=26, h=14):
    ry = rx / 2
    cv.ell(x, y, rx + 6, ry + 3, N, .35)
    cv.poly([(x - rx, y - h), (x + rx, y - h), (x + rx, y), (x - rx, y)], col.lerp(N, .25))
    cv.ell(x, y, rx, ry, col.lerp(N, .45), 1, N, 1)
    cv.poly([(x - rx, y - h), (x + rx, y - h), (x + rx, y), (x - rx, y)], col.lerp(N, .3))
    cv.poly([(x + 4, y - h), (x + rx, y - h), (x + rx, y), (x + 4, y + ry * .98)], col.lerp(N, .5))
    cv.line([(x - rx, y - h), (x - rx, y)], N, 1, .8)
    cv.line([(x + rx, y - h), (x + rx, y)], N, 1, .8)
    cv.line(ellipse_pts(x, y, rx, ry, 0, 40, 0, 180), N, 1, .8)
    cv.ell(x, y - h, rx, ry, col.lerp(S, .1), 1, N, 1)
    cv.line(ellipse_pts(x, y - h, rx - 4, ry - 2), Au, 1.2, .9, True)


def faceted_crystal(cv, x, y, w, h, col, tip=0.28):
    """Elongated octahedron, 4 visible facets. y = bottom tip."""
    top, bot = (x, y - h), (x, y)
    mid = y - h * (1 - tip) * .55 - h * tip * .0
    my = y - h * 0.38
    L, R, C = (x - w, my), (x + w, my), (x + w * .15, my + 3)
    cv.poly([top, L, C], col.lerp(S, .45), 1, N, 1.2)
    cv.poly([top, C, R], col, 1, N, 1.2)
    cv.poly([L, bot, C], col.lerp(N, .25), 1, N, 1.2)
    cv.poly([C, bot, R], col.lerp(N, .5), 1, N, 1.2)
    cv.line([(x - w * .55, my - h * .2), (x - w * .15, y - h * .82)], S, 1.2, .8)
    del mid


def prop_sigil(team):
    tc = Cy if team == "player" else E
    cv = Canvas(PW, PH)
    x, y = PX, PY
    cv.glow(x, y - 70, 50, 60, tc, 6, .06)
    base = S.lerp(N, .55) if team == "player" else N.lerp(E, .15).lerp(S, .15)
    pedestal(cv, x, y, base)
    # compass-star engraving + rings behind the crystal
    cv.line(ellipse_pts(x, y - 68, 34, 10, -12), Au, 1.6, .9)
    faceted_crystal(cv, x, y - 26, 17, 92, tc)
    cv.line(ellipse_pts(x, y - 68, 34, 10, -12, 40, 0, 180), Au, 2.0, 1)
    cv.poly(star_pts(x, y - 136, 9, 2, 4), Au, 1, N, .8)
    if team == "enemy":
        for dx in (-22, 22):
            cv.poly([(x + dx - 4, y - 16), (x + dx + dx * .25, y - 44), (x + dx + 4, y - 16)], E.lerp(N, .3), 1, N, 1)
    return cv


def prop_capsule_node():
    """Faceted hexagonal crystal vessel inside a gold gyroscope cage (two TILTED rings only)."""
    cv = Canvas(PW, PH)
    x, y = PX, PY
    cv.glow(x, y - 62, 40, 46, Cy, 5, .06)
    pedestal(cv, x, y, S.lerp(N, .5), 22, 10)
    cy_ = y - 62
    # back halves of rings
    for rot in (55, -55):
        cv.line(ellipse_pts(x, cy_, 34, 13, rot, 40, 180, 360), Au.lerp(N, .35), 2.6)
    # hex crystal vessel (vertical hexagonal prism with pointed ends)
    w, h = 13, 30
    top, bot = (x, cy_ - h - 12), (x, cy_ + h + 6)
    l1, l2 = (x - w, cy_ - h), (x - w, cy_ + h - 6)
    c1, c2 = (x + 2, cy_ - h + 4), (x + 2, cy_ + h - 2)
    r1, r2 = (x + w, cy_ - h), (x + w, cy_ + h - 6)
    cv.poly([l1, c1, c2, l2], Cy.lerp(S, .4), 1, N, 1.2)
    cv.poly([c1, r1, r2, c2], Cy.lerp(N, .2), 1, N, 1.2)
    cv.poly([top, c1, l1], Cy.lerp(S, .65), 1, N, 1.2)
    cv.poly([top, r1, c1], Cy.lerp(S, .2), 1, N, 1.2)
    cv.poly([l2, c2, bot], Cy.lerp(N, .35), 1, N, 1.2)
    cv.poly([c2, r2, bot], Cy.lerp(N, .55), 1, N, 1.2)
    cv.line([(x - w + 4, cy_ - h + 6), (x - w + 4, cy_ + h - 14)], S, 1.4, .8)
    cv.poly(star_pts(x + 2, cy_, 6, 1.6, 4), S, .9)
    # front halves of tilted rings + pivot studs
    for rot in (55, -55):
        P = ellipse_pts(x, cy_, 34, 13, rot, 40, 0, 180)
        cv.line(P, N, 4.2, .8)
        cv.line(P, Au, 2.6)
        cv.line(P[4:14], Au.lerp(S, .5), 1.0, .9)
    for ang in (55, 235, -55, 125):
        a = math.radians(ang)
        q = (x + 34 * math.cos(a), cy_ + 34 * math.sin(a))
    cv.poly(star_pts(x, cy_ - h - 16, 4, 1, 4), Au, 1, N, .6)
    # cage stem to pedestal
    cv.line([(x, bot[1]), (x, y - 10)], Au.lerp(N, .2), 3)
    return cv


def prop_relic():
    cv = Canvas(PW, PH)
    x, y = PX, PY
    cv.glow(x, y - 54, 36, 40, Au, 5, .07)
    pedestal(cv, x, y, S.lerp(Au, .25).lerp(N, .45), 18, 18)
    cy_ = y - 60
    T = tri(x, cy_, 26)
    cv.poly([T[0], T[1], (x, cy_)], Au.lerp(S, .3), 1, N, 1.2)
    cv.poly([T[1], T[2], (x, cy_)], Au.lerp(N, .3), 1, N, 1.2)
    cv.poly([T[2], T[0], (x, cy_)], Au, 1, N, 1.2)
    cv.poly(star_pts(x, cy_ + 1, 7, 1.8, 4), S, 1, N, .8)
    cv.ell(x, y - 20, 10, 3, Au, .25)
    for (dx, dy, s) in [(-24, -84, 5), (22, -40, 4), (18, -92, 3)]:
        cv.poly(star_pts(x + dx, y + dy, s, s * .25, 4), S, .9)
    return cv


def prop_portal():
    cv = Canvas(PW, PH)
    x, y = PX, PY
    cy_ = y - 64
    cv.glow(x, cy_, 46, 60, V, 6, .07)
    cv.ell(x, y, 40, 16, N, .4)
    # stone base arc
    for dx in (-30, 30):
        cv.poly([(x + dx - 9, y), (x + dx - 6, y - 26), (x + dx + 6, y - 26), (x + dx + 9, y)], S.lerp(N, .5), 1, N, 1.2)
    # swirl interior
    for k, (rx, ry, a) in enumerate(((30, 50, .55), (24, 40, .5), (16, 28, .55), (8, 15, .7))):
        cv.ell(x, cy_, rx, ry, V.lerp(N, .5 - k * .12) if k < 3 else V.lerp(S, .5), a)
    for k in range(3):
        cv.line(ellipse_pts(x, cy_, 12 + k * 7, 20 + k * 11, 0, 30, k * 120, k * 120 + 210), V.lerp(S, .55), 1.4, .85)
    # the ring (thick, two-tone cel)
    cv.poly(ring_pts(x, cy_, 38, 58, 8), V, 1, N, 1.2)
    cv.line(ellipse_pts(x, cy_, 35, 55, 0, 40, 200, 320), V.lerp(S, .55), 1.6, .9)
    for ang in (-90, 30, 150):
        a = math.radians(ang)
        q = (x + 34 * math.cos(a), cy_ + 54 * math.sin(a))
        cv.poly([(q[0], q[1] - 6), (q[0] + 4, q[1]), (q[0], q[1] + 6), (q[0] - 4, q[1])], Au, 1, N, .8)
    return cv


# ============================================================================= ELEMENT GLYPHS (64 box)
def glyph(fam):
    """Returns list of items for the element glyph in a 64x64 box, coloured with the family colour."""
    c = FAMILY[fam]
    hi = c.lerp(S, .5)
    I = []
    P = lambda pts, col=c, a=1.0, st=N, sw=1.5: I.append(("poly", pts, col, a, st, sw))
    L = lambda pts, col=c, sw=4.0, a=1.0, cl=False: I.append(("line", pts, col, sw, a, cl))
    if fam == "Fire":
        P(chaikin([(32, 9), (39, 19), (45, 27), (47, 37), (44, 47), (37, 53), (32, 54), (26, 53), (19, 47), (17, 37), (21, 27), (26, 33), (28, 23)], 2))
        P(chaikin([(32, 29), (37, 38), (37, 46), (32, 50), (27, 46), (28, 39)], 2), Au.lerp(S, .2), 1, None, 0)
    elif fam == "Water":
        P(chaikin([(32, 8), (40, 22), (47, 33), (47, 42), (42, 51), (32, 55), (22, 51), (17, 42), (17, 33), (24, 22)], 2))
        P(chaikin([(24, 36), (26, 44), (31, 49), (26, 48), (22, 42)], 1), hi, 1, None, 0)
    elif fam == "Wind":
        L(chaikin([(10, 24), (30, 24), (40, 24), (47, 20), (47, 13), (40, 11), (36, 16)], 2, False), N, 7)
        L(chaikin([(8, 34), (44, 34), (54, 38), (54, 45), (47, 47), (43, 42)], 2, False), N, 7)
        L([(14, 44), (32, 44)], N, 7)
        L(chaikin([(10, 24), (30, 24), (40, 24), (47, 20), (47, 13), (40, 11), (36, 16)], 2, False))
        L(chaikin([(8, 34), (44, 34), (54, 38), (54, 45), (47, 47), (43, 42)], 2, False))
        L([(14, 44), (32, 44)])
    elif fam == "Earth":
        P([(9, 50), (22, 26), (29, 31), (38, 14), (55, 50)])
        P([(38, 14), (55, 50), (38, 50), (34, 30)], c.lerp(N, .35), 1, None, 0)
        P([(22, 26), (29, 31), (24, 50), (9, 50)], hi, .7, None, 0)
        L([(9, 50), (55, 50)], N, 1.5)
    elif fam == "Wood":
        L([(32, 56), (32, 38)], N, 5)
        L([(32, 56), (32, 38)], c.lerp(N, .2), 3)
        P(chaikin([(31, 46), (20, 40), (13, 26), (25, 27), (31, 37)], 2))
        P(chaikin([(33, 44), (37, 30), (50, 16), (53, 31), (43, 42)], 2), c.lerp(S, .25))
        L([(31, 44), (20, 32)], N, 1.2, .5)
    elif fam == "Ice":
        for a in (0, 60, 120):
            r = math.radians(a)
            dx, dy = 22 * math.cos(r), 22 * math.sin(r)
            L([(32 - dx, 32 - dy), (32 + dx, 32 + dy)], N, 6)
        for a in (0, 60, 120, 180, 240, 300):
            r = math.radians(a)
            bx, by = 32 + 13 * math.cos(r), 32 + 13 * math.sin(r)
            for s in (-1, 1):
                r2 = r + s * math.radians(45)
                L([(bx, by), (bx + 7 * math.cos(r2), by + 7 * math.sin(r2))], N, 5)
        for a in (0, 60, 120):
            r = math.radians(a)
            dx, dy = 22 * math.cos(r), 22 * math.sin(r)
            L([(32 - dx, 32 - dy), (32 + dx, 32 + dy)], c, 3.2)
        for a in (0, 60, 120, 180, 240, 300):
            r = math.radians(a)
            bx, by = 32 + 13 * math.cos(r), 32 + 13 * math.sin(r)
            for s in (-1, 1):
                r2 = r + s * math.radians(45)
                L([(bx, by), (bx + 7 * math.cos(r2), by + 7 * math.sin(r2))], c, 2.4)
        I.append(("ell", 32, 32, 3.5, 3.5, S, 1, N, 1))
    elif fam == "Thunder":
        P([(37, 7), (17, 35), (29, 35), (23, 57), (47, 26), (34, 26), (42, 7)])
        P([(37, 7), (42, 7), (34, 26), (29, 26)], hi, .8, None, 0)
    elif fam == "Light":
        for i in range(8):
            a = math.radians(i * 45 - 90)
            ln = 22 if i % 2 == 0 else 17
            pa = (32 + 12 * math.cos(a - .28), 32 + 12 * math.sin(a - .28))
            pb = (32 + 12 * math.cos(a + .28), 32 + 12 * math.sin(a + .28))
            P([pa, (32 + ln * math.cos(a), 32 + ln * math.sin(a)), pb], Au.lerp(S, .3))
        I.append(("ell", 32, 32, 10, 10, c, 1, N, 1.5))
        I.append(("ell", 29, 29, 4, 4, S.lerp(Au, .2), 1, None, 0))
    elif fam == "Dark":
        P(crescent((30, 33), 19, (40, 25), 16), c.lerp(S, .25))
        P(star_pts(45, 40, 5, 1.3, 4), V.lerp(S, .5), 1, None, 0)
    elif fam == "Tech":
        pts = []
        for i in range(16):
            a0 = math.radians(i * 22.5)
            r = 21 if i % 2 == 0 else 15
            pts += [(32 + r * math.cos(a0 - .17), 32 + r * math.sin(a0 - .17)), (32 + r * math.cos(a0 + .17), 32 + r * math.sin(a0 + .17))]
        P(pts)
        I.append(("ell", 32, 32, 7, 7, N, 1, None, 0))
        P([(32, 27), (36, 32), (32, 37), (28, 32)], Cy, 1, None, 0)
    elif fam == "Space":
        L(ellipse_pts(32, 32, 26, 9, -25), N, 4.5)
        L(ellipse_pts(32, 32, 26, 9, -25), Cy.lerp(S, .3), 2)
        P(star_pts(32, 32, 20, 4.5, 4))
        I.append(("ell", 53, 22, 3, 3, Au, 1, N, 1))
    elif fam == "Arcane":
        L([(32, 9), (54, 32), (32, 55), (10, 32)], N, 6, 1, True)
        L([(32, 9), (54, 32), (32, 55), (10, 32)], c, 3.4, 1, True)
        P(chaikin([(18, 32), (32, 22), (46, 32), (32, 42)], 2), c.lerp(S, .3))
        I.append(("ell", 32, 32, 4.5, 4.5, N, 1, None, 0))
        I.append(("ell", 33, 31, 1.4, 1.4, S, 1, None, 0))
    return I


def element_icon(fam):
    cv = Canvas(64, 64)
    c = FAMILY[fam]
    cv.ell(32, 32, 31, 31, N, 1, c, 2.5)
    cv.ell(32, 32, 26.5, 26.5, None, 1, Au, .9)
    cv.ell(32, 32, 26, 26, c, .1)
    cv.add(glyph(fam), s=.72, dx=32 - 32 * .72, dy=32 - 32 * .72)
    for a in (-90, 0, 90, 180):
        r = math.radians(a)
        q = (32 + 29.5 * math.cos(r), 32 + 29.5 * math.sin(r))
        cv.poly([(q[0], q[1] - 2.2), (q[0] + 2.2, q[1]), (q[0], q[1] + 2.2), (q[0] - 2.2, q[1])], Au)
    return cv


# ============================================================================= SILHOUETTES (100 box)
def sil(name):
    I = []
    P = lambda pts: I.append(("poly", pts, S, 1, N, 2.0))
    L = lambda pts, w=3.5: I.append(("line", pts, S, w, 1, False))
    H = lambda pts: I.append(("poly", pts, N, 1, None, 0))      # navy cut-out detail
    if name == "stag":
        for pts in ([(78, 24), (74, 14), (70, 6)], [(74, 14), (81, 8)], [(72, 10), (65, 9)],
                    [(83, 24), (86, 13), (92, 6)], [(85, 15), (93, 15)]):
            I.append(("line", pts, N, 6.5, 1, False))
        for pts in ([(78, 24), (74, 14), (70, 6)], [(74, 14), (81, 8)], [(72, 10), (65, 9)],
                    [(83, 24), (86, 13), (92, 6)], [(85, 15), (93, 15)]):
            L(pts)
        P(chaikin([(22, 52), (36, 46), (55, 46), (66, 43), (72, 35), (77, 27), (82, 23), (89, 26), (93, 31), (89, 34), (82, 34),
                   (78, 42), (76, 52), (72, 58), (72, 74), (74, 88), (68, 88), (65, 74), (62, 62), (50, 63), (39, 62), (37, 74),
                   (35, 88), (29, 88), (29, 72), (25, 62), (19, 58), (16, 50)], 1))
        P([(77, 28), (69, 22), (75, 31)])
        H([(85, 28), (87, 27), (87, 29)])
    elif name == "hopper":
        P([(66, 30), (62, 4), (71, 6), (74, 28)])
        P([(73, 30), (80, 7), (88, 11), (80, 32)])
        P(chaikin([(30, 88), (22, 80), (23, 64), (32, 52), (46, 46), (57, 44), (61, 36), (68, 29), (76, 28), (84, 33), (86, 41),
                   (80, 47), (71, 49), (67, 59), (70, 78), (77, 88), (61, 88), (59, 76), (54, 80), (57, 88)], 1))
        I.append(("ell", 20, 66, 6, 6, S, 1, N, 2))
        H([(76, 35), (79, 34), (79, 38), (76, 38)])
        H([(42, 62), (52, 56), (54, 66), (46, 72)])
    elif name == "phoenix":
        wing = [(46, 44), (36, 40), (24, 30), (14, 16), (8, 6), (16, 22), (5, 20), (14, 33), (4, 37), (18, 46), (10, 54), (28, 54), (42, 57)]
        P(wing)
        P([(100 - x, y) for x, y in wing])
        P([(46, 70), (36, 92), (45, 85), (50, 98), (55, 85), (64, 92), (54, 70)])
        P(chaikin([(50, 28), (55, 33), (57, 44), (58, 60), (54, 72), (50, 76), (46, 72), (42, 60), (43, 44), (45, 33)], 2))
        P([(47, 31), (43, 16), (49, 24), (51, 11), (53, 24), (59, 17), (54, 32)])
        H([(48, 36), (50, 34), (52, 36), (50, 38)])
    elif name == "colossus":
        P([(30, 96), (30, 72), (45, 72), (45, 96)])
        P([(55, 96), (55, 72), (70, 72), (70, 96)])
        P([(8, 52), (3, 78), (10, 84), (21, 81), (23, 56)])
        P([(92, 52), (97, 78), (90, 84), (79, 81), (77, 56)])
        P([(26, 78), (21, 48), (30, 35), (70, 35), (79, 48), (74, 78)])
        P([(31, 36), (12, 33), (5, 46), (14, 57), (25, 52)])
        P([(69, 36), (88, 33), (95, 46), (86, 57), (75, 52)])
        P([(41, 36), (41, 23), (46, 17), (54, 17), (59, 23), (59, 36)])
        P([(50, 3), (56, 12), (50, 19), (44, 12)])
        H([(44, 25), (56, 25), (55, 29), (45, 29)])
        H([(50, 45), (56, 54), (50, 63), (44, 54)])
    elif name == "beetle":
        for side in (1, -1):
            for pts in ([(26, 50), (11, 44), (6, 35)], [(23, 62), (8, 64), (4, 73)], [(27, 74), (15, 83), (13, 93)]):
                I.append(("line", [(50 + side * (x - 50), y) for x, y in pts], N, 6.5, 1, False))
                L([(50 + side * (x - 50), y) for x, y in pts])
        P([(44, 30), (46, 10), (51, 3), (55, 9), (56, 30)])
        P([(36, 38), (41, 25), (59, 25), (64, 38)])
        I.append(("ell", 50, 60, 29, 27, S, 1, N, 2))
        I.append(("line", [(50, 35), (50, 86)], N, 2, 1, False))
        H(chaikin([(30, 52), (36, 42), (42, 40), (36, 52)], 1))
    elif name == "drake":
        P([(50, 52), (40, 36), (30, 14), (40, 20), (46, 9), (54, 22), (62, 7), (66, 24), (77, 15), (71, 36), (64, 50)])
        P(chaikin([(22, 66), (34, 56), (52, 52), (64, 50), (70, 42), (72, 34), (76, 28), (88, 28), (95, 33), (89, 37), (80, 38),
                   (78, 46), (76, 56), (72, 64), (74, 78), (80, 88), (68, 88), (64, 72), (52, 72), (46, 80), (48, 88), (38, 88),
                   (36, 74), (28, 74), (16, 78), (8, 74), (4, 64), (10, 70), (18, 68)], 1))
        P([(77, 29), (72, 17), (81, 28)])
        P([(82, 28), (82, 18), (86, 28)])
        H([(85, 31), (88, 30), (87, 33)])
    return I


SILHOUETTES = ["stag", "hopper", "phoenix", "colossus", "beetle", "drake"]


def silhouette(name):
    cv = Canvas(100, 100)
    cv.add(sil(name))
    return cv


# ============================================================================= TOKENS (128 box)
def token(fam, team, creature=None):
    cv = Canvas(128, 128)
    tc, fc = TEAM[team], FAMILY[fam]
    cx, cy = 64, 60
    cv.ell(cx, cy + 4, 56, 56, N, .35)                       # drop shadow
    cv.ell(cx, cy, 56, 56, tc, 1, N, 2)                       # team ring
    cv.ell(cx, cy, 56, 56, None, 1, tc.lerp(S, .5), 1)
    cv.poly(ellipse_pts(cx, cy, 56, 56, 0, 40, 200, 340) + ellipse_pts(cx, cy, 50, 50, 0, 40, 340, 200)[::-1][::-1],
            tc.lerp(S, .35), .45)                             # cel light on ring
    cv.ell(cx, cy, 49, 49, N, 1, Au, 1.6)                      # gold bezel
    cv.ell(cx, cy, 45, 45, fc.lerp(N, .55), 1, fc, 2.4)        # element ring + slot
    cv.ell(cx, cy, 41, 41, N.lerp(fc, .12))                    # creature slot (r=41)
    for a in (-45, 45, 135, 225):
        r = math.radians(a)
        q = (cx + 52.5 * math.cos(r), cy + 52.5 * math.sin(r))
        cv.poly([(q[0], q[1] - 3), (q[0] + 3, q[1]), (q[0], q[1] + 3), (q[0] - 3, q[1])], Au, 1, N, .8)
    # team notch at top
    cv.poly([(cx, cy - 62), (cx + 7, cy - 54), (cx, cy - 47), (cx - 7, cy - 54)], tc, 1, N, 1.4)
    cv.poly(star_pts(cx, cy - 54, 4.5, 1.2, 4), Au)
    if creature:
        cv.add(sil(creature), s=.72, dx=cx - 36, dy=cy - 38)
    # element badge
    bx, by, br = cx, cy + 50, 13
    cv.ell(bx, by, br + 2, br + 2, N)
    cv.ell(bx, by, br, br, N, 1, fc, 2)
    cv.add(glyph(fam), s=br * 1.5 / 64 * 1.05, dx=bx - 32 * br * 1.5 / 64 * 1.05, dy=by - 32 * br * 1.5 / 64 * 1.05)
    return cv


# ============================================================================= UI
def cut_rect(x0, y0, x1, y1, c):
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


def cmd_icon(name):
    I = []
    P = lambda pts, col=S, a=1.0, st=N, sw=2.0: I.append(("poly", pts, col, a, st, sw))
    L = lambda pts, col=S, sw=4.0, a=1.0: I.append(("line", pts, col, sw, a, False))
    if name == "move":
        for i, x in enumerate((12, 22)):
            P([(x, 28), (x + 5, 32), (x, 36), (x - 5, 32)], Cy, .5 + .25 * i)
        P([(30, 26), (44, 26), (44, 16), (58, 32), (44, 48), (44, 38), (30, 38)])
        P([(44, 16), (58, 32), (44, 32)], Cy.lerp(S, .3), 1, None, 0)
    elif name == "attack":
        blade = [(30, 6), (34, 6), (35, 40), (32, 46), (29, 40)]
        guard = [(20, 40), (44, 40), (44, 45), (20, 45)]
        grip = [(29.5, 45), (34.5, 45), (34.5, 56), (29.5, 56)]
        for pts, col in ((blade, S), (guard, Au), (grip, N.lerp(S, .3))):
            I.append(("poly", pts, col, 1, N, 2))
        I.append(("poly", [(32, 6), (34, 6), (35, 40), (32, 46)], S.lerp(N, .25), 1, None, 0))
        I.append(("ell", 32, 58, 3.5, 3.5, E, 1, N, 1.5))
        I[:] = [("poly", [_rot(p, 45) for p in it[1]]) + it[2:] if it[0] == "poly" else ("ell",) + _rot((it[1], it[2]), 45) + it[3:] for it in I]
    elif name == "skill":
        P(star_pts(30, 34, 22, 5, 4), Cy.lerp(S, .3))
        P(star_pts(48, 14, 9, 2.4, 4), Au)
        I.append(("ell", 14, 52, 3, 3, S, 1, N, 1.5))
    elif name == "defend":
        sh = chaikin([(32, 6), (52, 12), (51, 34), (32, 58), (13, 34), (12, 12)], 1)
        P(sh, S.lerp(N, .15))
        P([(32, 6), (52, 12), (51, 34), (32, 58)], S.lerp(N, .4), 1, None, 0)
        P([(32, 18), (42, 22), (41, 33), (32, 46), (23, 33), (22, 22)], Cy, 1, N, 1.5)
        L([(32, 6), (52, 12), (51, 34), (32, 58), (13, 34), (12, 12), (32, 6)], N, 2.0)
    elif name == "wait":
        P([(16, 8), (48, 8), (48, 13), (16, 13)], Au)
        P([(16, 51), (48, 51), (48, 56), (16, 56)], Au)
        P([(20, 13), (44, 13), (34, 32), (44, 51), (20, 51), (30, 32)], S.lerp(N, .1))
        P([(26, 47), (38, 47), (32, 38)], Cy, 1, None, 0)
        P([(25, 17), (39, 17), (32, 26)], Cy, .6, None, 0)
    return I


def _rot(p, deg, c=(32, 32)):
    r = math.radians(deg)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(r) - y * math.sin(r), c[1] + x * math.sin(r) + y * math.cos(r))


def ui_button(name, state):
    cv = Canvas(96, 96)
    edge = {"normal": Au, "pressed": Cy, "disabled": S.lerp(N, .5)}[state]
    fill = {"normal": N.lerp(S, .06), "pressed": N.lerp(Cy, .18), "disabled": N.lerp(S, .03)}[state]
    if state == "pressed":
        cv.poly(cut_rect(1, 1, 95, 95, 18), Cy, .25)
    cv.poly(cut_rect(4, 4, 92, 92, 16), fill, 1, N, 2)
    cv.line(cut_rect(4, 4, 92, 92, 16), edge, 2.4, 1, True)
    cv.line(cut_rect(9, 9, 87, 87, 13), edge, 1.0, .6, True)
    cv.poly(cut_rect(9, 9, 87, 50, 13)[:4] + [(87, 30), (9, 30)], S, .05)
    for (x, y) in ((48, 4), (48, 92)):
        cv.poly([(x, y - 4), (x + 4, y), (x, y + 4), (x - 4, y)], edge, 1, N, 1)
    cv.add(cmd_icon(name), s=.85, dx=48 - 32 * .85, dy=48 - 32 * .85)
    if state == "disabled":
        cv.poly(cut_rect(4, 4, 92, 92, 16), N, .55)
    return cv


def ui_turn_slot(team, active):
    cv = Canvas(72, 72)
    tc = TEAM[team]
    if active:
        cv.poly(cut_rect(0, 0, 72, 72, 12), tc, .3)
    cv.poly(cut_rect(4, 4, 68, 68, 10), N.lerp(tc, .08), 1, N, 2)
    cv.line(cut_rect(4, 4, 68, 68, 10), tc, 3.0 if active else 2.0, 1, True)
    cv.line(cut_rect(8, 8, 64, 64, 8), Au, 1.0, .7, True)
    cv.poly([(4, 4), (22, 4), (4, 22)], tc, 1, N, 1)          # index badge corner (label in Godot)
    for q in ((68, 36), (4, 36)):
        cv.poly([(q[0], q[1] - 4), (q[0] + 3, q[1]), (q[0], q[1] + 4), (q[0] - 3, q[1])], Au, 1, N, .8)
    return cv


def ui_checkbox(state):
    cv = Canvas(32, 32)
    cv.poly(cut_rect(3, 3, 29, 29, 6), N.lerp(S, .05), 1, N, 1.5)
    cv.line(cut_rect(3, 3, 29, 29, 6), Au, 1.8, 1, True)
    if state == "checked":
        cv.line([(9, 16), (14, 22), (24, 9)], N, 5.5)
        cv.line([(9, 16), (14, 22), (24, 9)], Au, 3.2)
    elif state == "failed":
        cv.line([(10, 10), (22, 22)], E, 3.2)
        cv.line([(22, 10), (10, 22)], E, 3.2)
    return cv


def ui_panel():
    cv = Canvas(192, 192)
    cv.poly(cut_rect(4, 4, 188, 188, 14), N, .94)
    cv.line(cut_rect(4, 4, 188, 188, 14), Au, 2.2, 1, True)
    cv.line(cut_rect(10, 10, 182, 182, 10), Cy, .9, .55, True)
    for (x, y, sx, sy) in ((4, 4, 1, 1), (188, 4, -1, 1), (188, 188, -1, -1), (4, 188, 1, -1)):
        cv.poly([(x + sx * 2, y + sy * 18), (x + sx * 18, y + sy * 2), (x + sx * 22, y + sy * 6), (x + sx * 6, y + sy * 22)], Au, 1, N, 1)
        q = (x + sx * 12, y + sy * 12)
        cv.poly(star_pts(q[0], q[1], 5, 1.2, 4), S)
    # top gem (sits in the stretchable middle; it's fine to remove by using it as header only)
    return cv


def ui_header():
    cv = Canvas(192, 32)
    cv.poly([(0, 16), (14, 4), (178, 4), (192, 16), (178, 28), (14, 28)], N.lerp(S, .06), 1, N, 1.5)
    cv.line([(0, 16), (14, 4), (178, 4), (192, 16), (178, 28), (14, 28), (0, 16)], Au, 1.6)
    cv.poly([(96, 2), (103, 9), (96, 16), (89, 9)], Cy, 1, N, 1)
    return cv


# ============================================================================= PREVIEWS
def compose_stage(tower_idx, level_idx, bible, out_name):
    tw = TOWERS[tower_idx]
    lvl = bible["towers"][tower_idx]["levels"][level_idx]
    grid = [list(r) for r in lvl["map_grid"]]
    for o in lvl.get("objectives", []):
        x, y = o["tile"]
        grid[y][x] = o["type"]
    n = len(grid)
    sc = 0.5  # tile PNG (256 wide) -> 128 px wide in preview, i.e. 1 SVG unit = 1 px
    W, H = n * TW + 64, n * TH + 260
    img = Image.new("RGBA", (W, H), tuple(N) + (255,))
    half = (n - 1) / 2

    def center(cx, cy):  # mirrors board_view.gd tile_center()
        x, y = half - cx, half - cy
        return (W / 2 + (x - y) * TW / 2, 200 + n * TH / 2 + (x + y) * TH / 2)

    cache = {}

    def load(rel):
        if rel not in cache:
            im = Image.open(PNG_DIR / rel)
            cache[rel] = im.resize((round(im.width * sc), round(im.height * sc)), Image.LANCZOS)
        return cache[rel]

    props = {"player_symbol": "props/player_sigil.png", "enemy_symbol": "props/enemy_sigil.png",
             "capsule_node": "props/capsule_node.png", "relic": "props/relic.png", "warp_gate": "props/portal.png"}
    cells = sorted(((cx, cy) for cy in range(n) for cx in range(n)), key=lambda c: center(*c)[1])
    for cx, cy in cells:
        t = grid[cy][cx]
        name = t
        if t == "bridge":
            horiz = (cx > 0 and grid[cy][cx - 1] in ("bridge",)) or (cx < n - 1 and grid[cy][cx + 1] == "bridge")
            name = "bridge" if horiz else "bridge_y"
        if t not in TILE_TYPES:
            name = "ground"
        if name == "ground":
            name = ["ground", "ground_v2", "ground_v3"][(cx * 7 + cy * 13) % 3]
        tile = load("tiles/%s_%s/%s.png" % (tw[0], tw[1], name))
        gx, gy = center(cx, cy)
        img.alpha_composite(tile, (round(gx - GX), round(gy - GY)))
        if t in props:
            lift = RAISE.get(t, 0) * TH or MIN_LIFT
            p = load(props[t])
            ps = .55
            p2 = p.resize((round(p.width * ps), round(p.height * ps)), Image.LANCZOS)
            img.alpha_composite(p2, (round(gx - PX * ps), round(gy - lift - PY * ps)))
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(PREVIEW_DIR / out_name, optimize=True)


def contact_sheet(rels, cols, cell, out_name, bg=N):
    rows = math.ceil(len(rels) / cols)
    img = Image.new("RGBA", (cols * cell[0], rows * cell[1]), tuple(bg) + (255,))
    for i, rel in enumerate(rels):
        im = Image.open(PNG_DIR / rel)
        im.thumbnail(cell, Image.LANCZOS)
        x = (i % cols) * cell[0] + (cell[0] - im.width) // 2
        y = (i // cols) * cell[1] + (cell[1] - im.height) // 2
        img.alpha_composite(im, (x, y))
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(PREVIEW_DIR / out_name, optimize=True)


# ============================================================================= MAIN
def main(only_first_tower=False):
    bible = json.loads(BIBLE.read_text(encoding="utf-8"))
    found = set()
    for t in bible["towers"]:
        for l in t["levels"]:
            for row in l["map_grid"]:
                found.update(row)
    missing = found - set(TILE_TYPES)
    assert not missing, missing
    WRITTEN.clear()
    towers = TOWERS[:1] if only_first_tower else TOWERS
    for tw in towers:
        folder = "tiles/%s_%s" % (tw[0], tw[1])
        for tt in TILE_TYPES:
            save(make_tile(tw, tt), "%s/%s" % (folder, tt), 2, "tile:%s:%s" % (tw[0], tt))
        save(make_tile(tw, "bridge", alt=True), "%s/bridge_y" % folder, 2, "tile:%s:bridge_y" % tw[0])
        for k in (2, 3):
            save(make_tile(tw, "ground", variant=k), "%s/ground_v%d" % (folder, k), 2, "tile:%s:ground_v%d" % (tw[0], k))
    save(prop_sigil("player"), "props/player_sigil", 2, "prop:player_sigil")
    save(prop_sigil("enemy"), "props/enemy_sigil", 2, "prop:enemy_sigil")
    save(prop_capsule_node(), "props/capsule_node", 2, "prop:capsule_node")
    save(prop_relic(), "props/relic", 2, "prop:relic")
    save(prop_portal(), "props/portal", 2, "prop:portal")
    for fam in FAMILIES:
        save(element_icon(fam), "icons/elements/%s" % fam.lower(), 4, "icon:%s" % fam)
    for s_ in SILHOUETTES:
        save(silhouette(s_), "tokens/silhouettes/%s" % s_, 2.56, "silhouette:%s" % s_)
    for fam in FAMILIES:
        for team in ("ally", "enemy"):
            save(token(fam, team), "tokens/frames/%s_%s" % (team, fam.lower()), 2, "token:%s:%s" % (team, fam))
    samples = [("Wood", "ally", "stag"), ("Tech", "ally", "hopper"), ("Light", "ally", "phoenix"),
               ("Ice", "enemy", "colossus"), ("Dark", "enemy", "beetle"), ("Fire", "enemy", "drake")]
    for fam, team, cr in samples:
        save(token(fam, team, cr), "tokens/samples/%s_%s_%s" % (team, fam.lower(), cr), 2, "token-sample")
    for b in ("move", "attack", "skill", "defend", "wait"):
        for st in ("normal", "pressed", "disabled"):
            save(ui_button(b, st), "ui/buttons/btn_%s_%s" % (b, st), 2, "ui:button")
    for team in ("ally", "enemy"):
        save(ui_turn_slot(team, False), "ui/turn_order/slot_%s" % team, 2, "ui:slot")
        save(ui_turn_slot(team, True), "ui/turn_order/slot_%s_active" % team, 2, "ui:slot")
    for st in ("unchecked", "checked", "failed"):
        save(ui_checkbox(st), "ui/objective/checkbox_%s" % st, 4, "ui:checkbox")
    save(ui_panel(), "ui/panel/panel_border", 2, "ui:panel")
    save(ui_header(), "ui/panel/panel_header", 2, "ui:header")

    # previews
    for tw in towers:
        rels = ["tiles/%s_%s/%s.png" % (tw[0], tw[1], t) for t in TILE_TYPES + ["bridge_y", "ground_v2", "ground_v3"]]
        contact_sheet(rels, 11, (128, 160), "sheet_tiles_%s_%s.png" % (tw[0], tw[1]))
    compose_stage(0, 0, bible, "stage_T01-L01.png")
    if not only_first_tower:
        compose_stage(1, 0, bible, "stage_T02-L01.png")
        compose_stage(3, 0, bible, "stage_T04-L01.png")
        contact_sheet(["tiles/%s_%s/ground.png" % (t[0], t[1]) for t in TOWERS] +
                      ["tiles/%s_%s/obstacle.png" % (t[0], t[1]) for t in TOWERS], 12, (128, 160), "sheet_towers_ground_obstacle.png")
    contact_sheet(["props/%s.png" % p for p in ("player_sigil", "enemy_sigil", "capsule_node", "relic", "portal")], 5, (256, 384), "sheet_props.png")
    contact_sheet(["icons/elements/%s.png" % f.lower() for f in FAMILIES], 6, (160, 160), "sheet_element_icons.png")
    contact_sheet(["tokens/frames/%s_%s.png" % (tm, f.lower()) for tm in ("ally", "enemy") for f in FAMILIES], 12, (128, 128), "sheet_token_frames.png")
    contact_sheet(["tokens/samples/%s_%s_%s.png" % (tm, f.lower(), c) for f, tm, c in samples] +
                  ["tokens/silhouettes/%s.png" % s_ for s_ in SILHOUETTES], 6, (200, 200), "sheet_tokens_silhouettes.png")
    contact_sheet(["ui/buttons/btn_%s_%s.png" % (b, s_) for s_ in ("normal", "pressed", "disabled") for b in ("move", "attack", "skill", "defend", "wait")]
                  + ["ui/turn_order/slot_%s.png" % s_ for s_ in ("ally", "ally_active", "enemy", "enemy_active")]
                  + ["ui/objective/checkbox_%s.png" % s_ for s_ in ("unchecked", "checked", "failed")], 5, (200, 200), "sheet_ui.png")
    print("files:", len(WRITTEN) * 2, "tile types found:", sorted(found))
    return found


if __name__ == "__main__":
    import sys
    main(only_first_tower="--first" in sys.argv)
