#!/usr/bin/env python3
"""
Generate DandersFrames frame-border edge textures as WoW SetBackdrop edgeFiles.

Output: 32-bit uncompressed TGA, written into ../Media/ next to this script.

These are designed for SQUARE / rectangular frames (no corner mask), so every
border has square corners.

WoW edgeFile format (verified empirically against an existing border texture):
  * The image is 8 equal SQUARE cells laid out in one horizontal row, so for a
    cell size N the image is (8*N) x N pixels.
  * 32-bit BGRA, uncompressed (TGA image type 2), bottom-left origin (descriptor
    byte 0x08), so pixel rows are written bottom-to-top.
  * Cell order, left -> right:
        0 Left edge   1 Right edge   2 Top edge   3 Bottom edge
        4 Top-Left    5 Top-Right    6 Bottom-Left   7 Bottom-Right
  * The Top and Bottom edge cells are stored as VERTICAL strips (drawn like the
    Left/Right edges); the engine rotates them into place at render time.

Each generator returns (shade, alpha) per point. SetBackdropBorderColor multiplies
the chosen colour onto the texture, so a greyscale shade < 1 bakes in 3D shading
(bevel/inset) that survives tinting; plain borders just use shade = 1 (white).
"""

import math
import os
import struct

N = 32                     # cell size in pixels -> 256x32 image
SUB = 4                    # supersampling factor per axis (anti-aliasing)
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Media")

# Cell roles in file order.
ROLES = ["L", "R", "T", "B", "TL", "TR", "BL", "BR"]


# Distance from a point to the SQUARE border centreline. Edges are a single
# strip at offset c from the relevant side; corners are the union of the two
# perpendicular strips (min distance), giving sharp 90-degree corners.
def square_dist(role, x, y, oi, t):
    c = oi + t / 2.0
    if role == "L" or role == "T":      # T is drawn like L; engine rotates it
        return abs(x - c)
    if role == "R" or role == "B":      # B is drawn like R
        return abs(x - (N - c))
    if role == "TL":
        cx, cy = c, c
    elif role == "TR":
        cx, cy = N - c, c
    elif role == "BL":
        cx, cy = c, N - c
    else:  # BR
        cx, cy = N - c, N - c
    return min(abs(x - cx), abs(y - cy))


# --- DF Glow: soft square-cornered halo --------------------------------------
def tex_glow(role, x, y):
    oi, t = 1, 10
    d = square_dist(role, x, y, oi, t)
    sigma = t * 0.5
    return 1.0, math.exp(-(d * d) / (2.0 * sigma * sigma))


# --- DF Double: two thin square lines ----------------------------------------
def tex_double(role, x, y):
    oi, lt, gap = 2, 2, 2
    if role in ("L", "T"):
        fa = x
    elif role in ("R", "B"):
        fa = N - x
    if role in ("L", "R", "T", "B"):
        for d in (oi, oi + lt + gap):
            if d <= fa < d + lt:
                return 1.0, 1.0
        return 1.0, 0.0
    # corners
    if role == "TL":
        fa, fb = x, y
    elif role == "TR":
        fa, fb = N - x, y
    elif role == "BL":
        fa, fb = x, N - y
    else:  # BR
        fa, fb = N - x, N - y
    for d in (oi, oi + lt + gap):
        if ((d <= fa < d + lt) and fb >= d) or ((d <= fb < d + lt) and fa >= d):
            return 1.0, 1.0
    return 1.0, 0.0


# --- DF Bevel / DF Inset: solid band shaded for a 3D edge --------------------
# Top + left edges are lit, bottom + right are shadowed (raised look); Inset
# swaps them (recessed look). Corners split along the diagonal.
LIGHT = 1.0
DARK = 0.4


def _bevel_shade(role, x, y, oi, t):
    c = oi + t / 2.0
    if role in ("L", "T", "TL"):
        return LIGHT
    if role in ("R", "B", "BR"):
        return DARK
    if role == "TR":   # top (light) vs right (dark)
        return LIGHT if abs(y - c) <= abs(x - (N - c)) else DARK
    # BL: left (light) vs bottom (dark)
    return LIGHT if abs(x - c) <= abs(y - (N - c)) else DARK


def make_bevel(recessed):
    def fn(role, x, y):
        oi, t = 1, 8
        if square_dist(role, x, y, oi, t) > t / 2.0:
            return 1.0, 0.0
        shade = _bevel_shade(role, x, y, oi, t)
        if recessed:
            shade = DARK if shade == LIGHT else LIGHT
        return shade, 1.0
    return fn


def build(fn):
    """Return rows (top->bottom); each entry is (shade_byte, alpha_byte)."""
    w = N * 8
    rows = []
    for py in range(N):
        row = []
        for px in range(w):
            cell = px // N
            role = ROLES[cell]
            lx = px - cell * N
            sacc, aacc = 0.0, 0.0
            for sy in range(SUB):
                for sx in range(SUB):
                    fx = lx + (sx + 0.5) / SUB
                    fy = py + (sy + 0.5) / SUB
                    s, a = fn(role, fx, fy)
                    sacc += s * a   # weight shade by coverage so AA edges blend
                    aacc += a
            alpha = aacc / (SUB * SUB)
            shade = (sacc / aacc) if aacc > 0 else 1.0
            row.append((int(round(255.0 * shade)), int(round(255.0 * alpha))))
        rows.append(row)
    return rows


def write_tga(path, rows):
    h = len(rows)
    w = len(rows[0])
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08,
    )
    with open(path, "wb") as f:
        f.write(header)
        # bottom-left origin -> write rows bottom (last) to top (first)
        for py in range(h - 1, -1, -1):
            for shade, alpha in rows[py]:
                f.write(bytes((shade, shade, shade, alpha)))  # B, G, R, A


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    targets = {
        "DF_Glow.tga":   tex_glow,
        "DF_Bevel.tga":  make_bevel(False),
        "DF_Inset.tga":  make_bevel(True),
        "DF_Double.tga": tex_double,
    }
    for name, fn in targets.items():
        out = os.path.join(OUTDIR, name)
        write_tga(out, build(fn))
        print("wrote", os.path.normpath(out))


if __name__ == "__main__":
    main()
