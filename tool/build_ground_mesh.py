#!/usr/bin/env python3
"""Generates high-detail modular sci-fi ground tile 3D geometry."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

verts = []
faces = []

def add_quad(v0, v1, v2, v3):
    faces.append([v0, v1, v2, v3])

def add_tri(v0, v1, v2):
    faces.append([v0, v1, v2])

def add_vertex(x, y, z):
    idx = len(verts)
    verts.append([round(x, 6), round(y, 6), round(z, 6)])
    return idx

def build_ground_tile():
    global verts, faces
    verts = []
    faces = []

    # Outer bounds: X: [-0.5, 0.5], Z: [-0.5, 0.5], Y: [-0.06, 0.0]
    # We create a detailed modular tile surface with:
    # 1. Base bottom & outer side walls
    # 2. Outer beveled frame rim
    # 3. Recessed cross channels (conduits / LED seams)
    # 4. 4 Raised quadrant walking tread plates with chamfered borders
    # 5. 4 Corner mounting pads with hex bolt caps
    # 6. Central junction / vent plate

    H_BASE = -0.06
    H_RIM = 0.0
    H_PANEL = -0.006
    H_CHANNEL = -0.025
    H_CORNER = 0.008
    H_BOLT = 0.016

    # 1. Bottom plate
    b0 = add_vertex(-0.5, H_BASE, -0.5)
    b1 = add_vertex( 0.5, H_BASE, -0.5)
    b2 = add_vertex( 0.5, H_BASE,  0.5)
    b3 = add_vertex(-0.5, H_BASE,  0.5)
    add_quad(b3, b2, b1, b0)

    # 2. Outer side walls
    t0 = add_vertex(-0.5, H_RIM, -0.5)
    t1 = add_vertex( 0.5, H_RIM, -0.5)
    t2 = add_vertex( 0.5, H_RIM,  0.5)
    t3 = add_vertex(-0.5, H_RIM,  0.5)

    add_quad(b0, b1, t1, t0) # -Z
    add_quad(b1, b2, t2, t1) # +X
    add_quad(b2, b3, t3, t2) # +Z
    add_quad(b3, b0, t0, t3) # -X

    # 3. Outer Frame Rim (inner edge at +/- 0.46)
    r0 = add_vertex(-0.46, H_RIM, -0.46)
    r1 = add_vertex( 0.46, H_RIM, -0.46)
    r2 = add_vertex( 0.46, H_RIM,  0.46)
    r3 = add_vertex(-0.46, H_RIM,  0.46)

    # Rim quads
    add_quad(t0, t1, r1, r0)
    add_quad(t1, t2, r2, r1)
    add_quad(t2, t3, r3, r2)
    add_quad(t3, t0, r0, r3)

    # 4. Cross channels (center conduits from -0.025 to +0.025 in X and Z)
    # 4 quadrant panel bounding boxes:
    # Q_NW: X in [-0.44, -0.035], Z in [-0.44, -0.035]
    # Q_NE: X in [ 0.035,  0.44], Z in [-0.44, -0.035]
    # Q_SW: X in [-0.44, -0.035], Z in [ 0.035,  0.44]
    # Q_SE: X in [ 0.035,  0.44], Z in [ 0.035,  0.44]

    quadrants = [
        (-0.44, -0.035, -0.44, -0.035),
        ( 0.035,  0.44, -0.44, -0.035),
        (-0.44, -0.035,  0.035,  0.44),
        ( 0.035,  0.44,  0.035,  0.44),
    ]

    # Floor channel bed
    c_bed0 = add_vertex(-0.46, H_CHANNEL, -0.46)
    c_bed1 = add_vertex( 0.46, H_CHANNEL, -0.46)
    c_bed2 = add_vertex( 0.46, H_CHANNEL,  0.46)
    c_bed3 = add_vertex(-0.46, H_CHANNEL,  0.46)

    # Rim bevel down to channel bed
    add_quad(r0, r1, c_bed1, c_bed0)
    add_quad(r1, r2, c_bed2, c_bed1)
    add_quad(r2, r3, c_bed3, c_bed2)
    add_quad(r3, r0, c_bed0, c_bed3)

    # Channel bed floor
    add_quad(c_bed0, c_bed1, c_bed2, c_bed3)

    # Add 4 raised quadrant plates
    for (qx0, qx1, qz0, qz1) in quadrants:
        bevel = 0.015
        # Bottom of panel on channel bed
        p_b0 = add_vertex(qx0, H_CHANNEL, qz0)
        p_b1 = add_vertex(qx1, H_CHANNEL, qz0)
        p_b2 = add_vertex(qx1, H_CHANNEL, qz1)
        p_b3 = add_vertex(qx0, H_CHANNEL, qz1)

        # Lower bevel perimeter
        p_m0 = add_vertex(qx0 + bevel*0.3, H_PANEL - 0.005, qz0 + bevel*0.3)
        p_m1 = add_vertex(qx1 - bevel*0.3, H_PANEL - 0.005, qz0 + bevel*0.3)
        p_m2 = add_vertex(qx1 - bevel*0.3, H_PANEL - 0.005, qz1 - bevel*0.3)
        p_m3 = add_vertex(qx0 + bevel*0.3, H_PANEL - 0.005, qz1 - bevel*0.3)

        # Top surface perimeter
        p_t0 = add_vertex(qx0 + bevel, H_PANEL, qz0 + bevel)
        p_t1 = add_vertex(qx1 - bevel, H_PANEL, qz0 + bevel)
        p_t2 = add_vertex(qx1 - bevel, H_PANEL, qz1 - bevel)
        p_t3 = add_vertex(qx0 + bevel, H_PANEL, qz1 - bevel)

        # Sides from channel bed to mid bevel
        add_quad(p_b0, p_b1, p_m1, p_m0)
        add_quad(p_b1, p_b2, p_m2, p_m1)
        add_quad(p_b2, p_b3, p_m3, p_m2)
        add_quad(p_b3, p_b0, p_m0, p_m3)

        # Chamfer bevels to top
        add_quad(p_m0, p_m1, p_t1, p_t0)
        add_quad(p_m1, p_m2, p_t2, p_t1)
        add_quad(p_m2, p_m3, p_t3, p_t2)
        add_quad(p_m3, p_m0, p_t0, p_t3)

        # Subdivide top plate with an inner recessed tread box (10x10 grid for smooth lighting)
        subdiv = 8
        grid_v = []
        for sy in range(subdiv + 1):
            row = []
            tz = qz0 + bevel + (qz1 - qz0 - 2*bevel) * (sy / subdiv)
            for sx in range(subdiv + 1):
                tx = qx0 + bevel + (qx1 - qx0 - 2*bevel) * (sx / subdiv)
                # Subtle center depression for heavy tread
                cx = (sx / subdiv - 0.5) * 2.0
                cy = (sy / subdiv - 0.5) * 2.0
                dist = math.sqrt(cx*cx + cy*cy)
                h = H_PANEL
                row.append(add_vertex(tx, h, tz))
            grid_v.append(row)

        for sy in range(subdiv):
            for sx in range(subdiv):
                add_quad(grid_v[sy][sx], grid_v[sy][sx+1], grid_v[sy+1][sx+1], grid_v[sy+1][sx])

    # 5. Add 4 Corner Raised Anchor Bolt Brackets
    corner_centers = [
        (-0.44, -0.44), (0.44, -0.44), (-0.44, 0.44), (0.44, 0.44)
    ]
    for (cx, cz) in corner_centers:
        c_rad = 0.045
        c_h = H_CORNER
        # Octagonal pad
        pad_top = []
        pad_bot = []
        num_pts = 8
        for p in range(num_pts):
            ang = p * 2.0 * math.pi / num_pts + math.pi / 8.0
            px = cx + math.cos(ang) * c_rad
            pz = cz + math.sin(ang) * c_rad
            pad_top.append(add_vertex(px, c_h, pz))
            pad_bot.append(add_vertex(px, H_PANEL, pz))

        # Pad sides
        for p in range(num_pts):
            p_next = (p + 1) % num_pts
            add_quad(pad_bot[p], pad_bot[p_next], pad_top[p_next], pad_top[p])

        # Pad top center
        pad_center = add_vertex(cx, c_h, cz)
        for p in range(num_pts):
            p_next = (p + 1) % num_pts
            add_tri(pad_top[p], pad_top[p_next], pad_center)

        # Hex bolt on top
        bolt_rad = 0.022
        bolt_top = []
        bolt_bot = []
        for p in range(6):
            ang = p * 2.0 * math.pi / 6.0
            bx = cx + math.cos(ang) * bolt_rad
            bz = cz + math.sin(ang) * bolt_rad
            bolt_top.append(add_vertex(bx, H_BOLT, bz))
            bolt_bot.append(add_vertex(bx, c_h, bz))

        # Bolt sides
        for p in range(6):
            p_next = (p + 1) % 6
            add_quad(bolt_bot[p], bolt_bot[p_next], bolt_top[p_next], bolt_top[p])

        # Bolt top center
        bolt_center = add_vertex(cx, H_BOLT + 0.002, cz)
        for p in range(6):
            p_next = (p + 1) % 6
            add_tri(bolt_top[p], bolt_top[p_next], bolt_center)

    # 6. Central Junction Cap / Vent Plate (X: [-0.08, 0.08], Z: [-0.08, 0.08])
    j_rad = 0.08
    j_h = H_PANEL + 0.002
    j_top = []
    j_bot = []
    for p in range(12):
        ang = p * 2.0 * math.pi / 12.0
        jx = math.cos(ang) * j_rad
        jz = math.sin(ang) * j_rad
        j_top.append(add_vertex(jx, j_h, jz))
        j_bot.append(add_vertex(jx, H_CHANNEL, jz))

    for p in range(12):
        p_next = (p + 1) % 12
        add_quad(j_bot[p], j_bot[p_next], j_top[p_next], j_top[p])

    j_center = add_vertex(0.0, j_h + 0.003, 0.0)
    for p in range(12):
        p_next = (p + 1) % 12
        add_tri(j_top[p], j_top[p_next], j_center)

    out_json = {
        "verts_count": len(verts),
        "verts": verts,
        "faces_count": len(faces),
        "faces": faces
    }
    with open(ROOT / "ground.json", "w", encoding="utf-8") as f:
        json.dump(out_json, f)
    print(f"Generated ground.json: {len(verts)} verts, {len(faces)} faces.")

if __name__ == "__main__":
    build_ground_tile()
