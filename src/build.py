# Builds ../tokyo_wgsl.luau: lays out the crossing (seeded, so it is the same
# every time) as WGSL constant tables, and assembles the shader sources beside
# this file (common.wgsl into ground.wgsl and live.wgsl, then show.wgsl) into
# one Luau module.
#
#   python3 src/build.py
import math, os, random, sys

os.chdir(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else "../tokyo_wgsl.luau"
rnd = random.Random(7)

FLOOR = -0.75
CYCLE = 44.0


def fl(x):
    s = ("%.4f" % x).rstrip("0")
    return s + "0" if s.endswith(".") else s


def vec(a):
    return "vec%d<f32>(%s)" % (len(a), ", ".join(fl(x) for x in a))


def table(name, rows):
    ty = "vec%d<f32>" % len(rows[0])
    return "const %s: array<%s, %d> = array<%s, %d>(\n\t%s\n);\n" % (
        name, ty, len(rows), ty, len(rows), ",\n\t".join(vec(r) for r in rows))


def hx(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]


# The palette: a ramp per family of things, darkest first. The sky's ramp
# comes first: it is also what far things fade into.
SUNRISE = ['#4f78b0', '#6690c2', '#83a8d2', '#a3bfdf', '#c3d3e6', '#e0dbe2', '#f5ddd3', '#fbe3c0', '#fdf0cf', '#fffbea']
SUNSET = ['#3b4f8a', '#52579a', '#7361a4', '#9a6fa8', '#c47fa0', '#e39590', '#f4ad7c', '#f9c877', '#fde08e', '#fff3c4']
NIGHT = ['#0b0d1f', '#141733', '#1f2350', '#30306e', '#4b3f86', '#75529a', '#a86aa3', '#d98aa6', '#f2b3a7', '#fbdcc0']
SKY = SUNSET
GREY = ['#14151f', '#262836', '#3e4152', '#636779', '#9a9eac', '#d8dbe0']
PINK = ['#3a1c33', '#6b2f52', '#a84f78', '#de86a3', '#f7b8c9', '#fde6ea']
GREEN = ['#0f2219', '#1c3d2a', '#2f6340', '#5a9457', '#9cc77c']
WOOD = ['#1f1410', '#3b261b', '#62402a', '#936a43', '#c9a273']
WARM = ['#5a3413', '#a8611c', '#e89a2c', '#fbd35f', '#fff6c4']
RED = ['#3d0d12', '#8a1a1e', '#d8342a', '#ff8a5c']
BLUE = ['#10233f', '#1d4273', '#3a74b0', '#7fb4dc']
PAL = SKY + GREY + PINK + GREEN + WOOD + WARM + RED + BLUE

# The crossing's four posts: x, z, and which way each faces (+1 the viewer).
xing = [(-1.25, 0.85, 1, 0), (1.25, 0.85, 1, 0), (-1.25, -1.85, -1, 0), (1.25, -1.85, -1, 0)]

# Utility poles (x, z, height, half an arm), and the wires strung between
# them and on out of the picture, sagging.
poles = [(-2.3, -1.62, 2.35, 0.2), (2.75, -1.62, 2.35, 0.2)]
wire_a, wire_b = [], []


def wire(a, b, sag, parts):
    pts = []
    for k in range(parts + 1):
        t = k / parts
        pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - sag * 4 * t * (1 - t), a[2] + (b[2] - a[2]) * t))
    for k in range(parts):
        wire_a.append(pts[k])
        wire_b.append(pts[k + 1])


top = FLOOR + 2.35 - 0.08
for dz, drop, sag in ((-0.18, 0.0, 0.14), (0.18, 0.0, 0.2), (0.0, 0.3, 0.26)):
    wire((-9.0, top - drop, -1.62 + dz), (-2.3, top - drop, -1.62 + dz), sag + 0.06, 3)
    wire((-2.3, top - drop, -1.62 + dz), (2.75, top - drop, -1.62 + dz), sag, 6)
    wire((2.75, top - drop, -1.62 + dz), (9.0, top - drop, -1.62 + dz), sag + 0.06, 3)

# Street lamps: x, z, height, and how far the arm reaches (along x).
lamps = [(-1.3, 1.62, 1.5, 0.3), (1.32, -2.3, 1.5, -0.3), (-1.32, -5.2, 1.5, 0.3), (1.32, -8.0, 1.5, -0.3),
         (-1.32, -11.0, 1.5, 0.3), (1.32, -14.0, 1.5, -0.3)]
vend = (1.76, 1.42)
lights = [(l[0] + l[3], FLOOR + l[2] - 0.05, l[1], 1.0) for l in lamps] + [(vend[0], FLOOR + 0.42, vend[1] + 0.3, 0.45)]


# Trees: where the trunk stands, how tall it is, sakura (0) or green (1), and
# how wide the canopy spreads.
def tree(x, z, h, kind, spread, lean):
    crown = (x + lean, FLOOR + h, z)
    centre = (x + lean * 1.6, FLOOR + h + spread * 0.55, z)
    blobs = []
    for k in range(6):
        a = k * 6.283 / 6 + rnd.uniform(-0.3, 0.3)
        r = spread * rnd.uniform(0.42, 0.6)
        reach = spread * rnd.uniform(0.35, 0.6)
        blobs.append((centre[0] + math.cos(a) * reach, centre[1] + rnd.uniform(-0.22, 0.28) * spread, centre[2] + math.sin(a) * reach * 0.8, r))
    boughs = [(blobs[k][0], blobs[k][1] - 0.1, blobs[k][2], 0) for k in (0, 2, 4)]
    return (x, z, h, kind), (*crown, 0), boughs, blobs, (*centre, spread * 1.3 + 0.2)


trees = [
    tree(-1.98, 1.05, 0.95, 0, 0.95, -0.08),
    tree(2.08, 0.75, 1.0, 0, 0.9, 0.1),
    tree(-4.3, -3.4, 1.1, 0, 1.05, 0.05),
    tree(-1.45, -3.7, 0.85, 1, 0.7, 0.0),
    tree(1.5, -3.6, 0.9, 1, 0.75, 0.04),
    tree(3.95, -3.5, 1.1, 0, 1.0, -0.06),
    tree(-3.1, -5.6, 1.0, 0, 0.9, 0.0),
    tree(5.6, -5.2, 1.1, 1, 0.95, 0.0),
]

bushes = [(x, FLOOR + r * 0.45, z, r) for x, z, r in [
    (-2.4, 0.52, 0.27), (-1.82, 0.5, 0.2), (1.8, 0.5, 0.22), (2.55, 0.47, 0.28),
    (-1.9, -1.78, 0.24), (-2.65, -1.82, 0.3), (1.9, -1.8, 0.26), (2.9, -1.78, 0.3),
    (-3.5, -1.9, 0.3), (3.6, -1.9, 0.26), (-3.3, 0.6, 0.3), (3.3, 0.55, 0.3),
]]

# Houses: centre x, centre z, half width, half depth; then wall height, roof
# height (0 for a flat roof) and the wall's material.
# (The street runs on between two rows of them, to the horizon.)
house_c = [(-2.75, -4.3, 0.95, 0.6), (2.7, -4.4, 0.85, 0.6), (-6.0, -7.2, 1.4, 0.7), (4.9, -7.6, 1.5, 0.7),
           (-2.7, -7.3, 0.95, 0.9), (2.75, -7.9, 0.95, 1.0), (-2.9, -10.8, 1.05, 1.2), (2.95, -11.4, 1.05, 1.2),
           (-3.1, -15.0, 1.15, 1.6), (3.1, -15.6, 1.15, 1.6)]
house_h = [(0.95, 0.42, 8, 0), (1.35, 0.4, 8, 0), (2.5, 0.0, 20, 0), (3.0, 0.0, 20, 0),
           (1.9, 0.0, 20, 0), (2.5, 0.0, 8, 0), (3.2, 0.0, 20, 0), (2.4, 0.0, 20, 0),
           (3.9, 0.0, 20, 0), (3.3, 0.0, 8, 0)]

# Who walks here: kind (0 a long coat, 1 a student, 2 a child, 3 an office
# worker, 4 a dog), size and coat. Each has its path through the round, as
# keys of (time, x, z, heading while standing): standing between two keys at
# one place, walking between two apart, and off stage across a gap shorter
# than a fifth of a second.
AWAY, HERE = -math.pi / 2, math.pi / 2
N_KEY = 9


def keys(rows):
    rows = list(rows)
    while len(rows) < N_KEY:
        rows.insert(-1, rows[-2])
    assert len(rows) == N_KEY and rows[0][0] == 0 and rows[-1][0] == CYCLE
    return rows


def beside(rows, dx, dz, late):
    return [(t if t in (0, CYCLE) else t + late, x + dx, z + dz, h) for t, x, z, h in rows]


parent = [(0, -0.5, 1.55, AWAY), (15.4, -0.5, 1.55, AWAY), (23.4, -0.5, -2.7, AWAY), (32.6, -5.2, -2.7, AWAY),
          (32.7, -3.3, 2.1, AWAY), (37.3, -0.5, 2.1, AWAY), (38.3, -0.5, 1.55, AWAY), (CYCLE, -0.5, 1.55, AWAY)]
walker = [(0, 0.45, 1.72, AWAY), (15.7, 0.45, 1.72, AWAY), (23.9, 0.5, -2.72, AWAY), (33.0, 5.3, -2.72, AWAY),
          (33.1, 3.4, 2.25, AWAY), (38.3, 0.45, 2.25, AWAY), (39.1, 0.45, 1.72, AWAY), (CYCLE, 0.45, 1.72, AWAY)]
worker = [(0, 0.35, -2.35, HERE), (15.5, 0.35, -2.35, HERE), (23.5, 0.35, 2.2, HERE), (28.8, 3.5, 2.25, HERE),
          (28.9, -5.3, -2.72, HERE), (33.0, -5.3, -2.72, HERE), (42.5, 0.35, -2.72, HERE), (43.2, 0.35, -2.35, HERE),
          (CYCLE, 0.35, -2.35, HERE)]
student = [(0, -0.35, -2.5, HERE), (15.9, -0.35, -2.5, HERE), (24.0, -0.35, 2.15, HERE), (29.4, -3.5, 2.2, HERE),
           (29.5, 5.3, -2.78, HERE), (32.0, 5.3, -2.78, HERE), (41.6, -0.35, -2.78, HERE), (42.2, -0.35, -2.5, HERE),
           (CYCLE, -0.35, -2.5, HERE)]
who = [(0, 1.0, 38, 0), (2, 0.62, 38, 0), (0, 0.95, 40, 0), (4, 1.0, 43, 0), (3, 1.02, 41, 0), (1, 0.9, 38, 0)]
paths = [keys(parent), keys(beside(parent, 0.27, 0.1, 0.25)), keys(walker), keys(beside(walker, 0.3, -0.12, 0.1)),
         keys(worker), keys(student)]

T = []
T.append("const N_PAL: i32 = %d;\n" % len(PAL) + table("K_PAL", [hx(c) for c in PAL]))
T.append(table("K_SKY", [hx(c) for c in SUNRISE + SUNSET + NIGHT]))
T.append("const N_XING: i32 = %d;\n" % len(xing) + table("K_XING", xing))
T.append("const N_POLE: i32 = %d;\n" % len(poles) + table("K_POLE", poles))
T.append("const N_WIRE: i32 = %d;\n" % len(wire_a) + table("K_WIRE_A", wire_a) + table("K_WIRE_B", wire_b))
T.append("const N_LAMP: i32 = %d;\n" % len(lamps) + table("K_LAMP", lamps))
T.append("const K_VEND: vec2<f32> = %s;\n" % vec(vend))
T.append("const N_LIGHT: i32 = %d;\n" % len(lights) + table("K_LIGHT", lights))
T.append("const N_TREE: i32 = %d;\n" % len(trees) + table("K_TREE_T", [t[0] for t in trees]) + table("K_TREE_L", [t[1] for t in trees])
         + table("K_TREE_BR", sum([t[2] for t in trees], [])) + table("K_BLOB", sum([t[3] for t in trees], [])) + table("K_TREE_B", [t[4] for t in trees]))
T.append("const N_BUSH: i32 = %d;\n" % len(bushes) + table("K_BUSH", bushes))
T.append("const N_HOUSE: i32 = %d;\n" % len(house_c) + table("K_HOUSE_C", house_c) + table("K_HOUSE_H", house_h))
T.append("const N_WHO: i32 = %d;\nconst N_KEY: i32 = %d;\n" % (len(who), N_KEY) + table("K_WHO", who) + table("K_PATH", sum(paths, [])))

common = open("common.wgsl").read().replace("/*TABLES*/", "\n".join(T))
ground = common + "\n" + open("ground.wgsl").read()
live = common + "\n" + open("live.wgsl").read()
show = open("show.wgsl").read()
head = open("head.txt").read()
open(OUT, "w").write(head + "local M = {}\n\nM.GROUND = [==[\n" + ground + "]==]\n\nM.LIVE = [==[\n" + live + "]==]\n\nM.SHOW = [==[\n" + show + "]==]\n\nreturn M\n")
if len(sys.argv) > 2:
    open(os.path.join(sys.argv[2], "ground.wgsl"), "w").write(ground)
    open(os.path.join(sys.argv[2], "live.wgsl"), "w").write(live)
print("ground", len(ground), "live", len(live))
