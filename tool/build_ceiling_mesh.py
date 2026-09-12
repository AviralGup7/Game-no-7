#!/usr/bin/env python3
"""Generates high-detail modular sci-fi ceiling tile 3D geometry."""
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

def build_ceiling_tile():
    global verts, faces
    verts = []
    faces = []

    # Outer bounds: X: [-0.5, 0.5], Z: [-0.5, 0.5], Y: [0.0, -0.08]
    # Structure:
    # 1. Top back plate at Y = 0.0
    # 2. Outer side walls
    # 3. Outer hanging rim frame (Y = -0.02)
    # 4. 4 Recessed luminaire wells (recessed up towards Y = 0.0)
    # 5. Overhead cross support trusses (Y = -0.05)
    # 6. Center junction hub / conduit box (Y = -0.07)

    H_TOP = 0.0
    H_RIM = -0.02
    H_WELL = -0.005
    H_TRUSS = -0.05
    H_HUB = -0.075

    # 1. Top back plate (facing up)
    t0 = add_vertex(-0.5, H_TOP, -0.5)
    t1 = add_vertex( 0.5, H_TOP, -0.5)
    t2 = add_vertex( 0.5, H_TOP,  0.5)
    t3 = add_vertex(-0.5, H_TOP,  0.5)
    add_quad(t0, t1, t2, t3)

    # 2. Outer side walls
    r0 = add_vertex(-0.5, H_RIM, -0.5)
    r1 = add_vertex( 0.5, H_RIM, -0.5)
    r2 = add_vertex( 0.5, H_RIM,  0.5)
    r3 = add_vertex(-0.5, H_RIM,  0.5)

    add_quad(t1, t0, r0, r1) # -Z
    add_quad(t2, t1, r1, r2) # +X
    add_quad(t3, t2, r2, r3) # +Z
    add_quad(t0, t3, r3, r0) # -X

    # 3. Outer Rim bottom face (inner edge at +/- 0.44)
    ir0 = add_vertex(-0.44, H_RIM, -0.44)
    ir1 = add_vertex( 0.44, H_RIM, -0.44)
    ir2 = add_vertex( 0.44, H_RIM,  0.44)
    ir3 = add_vertex(-0.44, H_RIM,  0.44)

    add_quad(r1, r0, ir0, ir1)
    add_quad(r2, r1, ir1, ir2)
    add_quad(r3, r2, ir2, ir3)
    add_quad(r0, r3, ir3, ir0)

    # 4. Cross Truss Channels (X/Z between -0.03 and +0.03)
    # 4 Recessed Luminaire Wells:
    quads = [
        (-0.42, -0.04, -0.42, -0.04),
        ( 0.04,  0.42, -0.42, -0.04),
        (-0.42, -0.04,  0.04,  0.42),
        ( 0.04,  0.42,  0.04,  0.42),
    ]

    for (qx0, qx1, qz0, qz1) in quads:
        # Well rim at H_RIM
        w_r0 = add_vertex(qx0, H_RIM, qz0)
        w_r1 = add_vertex(qx1, H_RIM, qz0)
        w_r2 = add_vertex(qx1, H_RIM, qz1)
        w_r3 = add_vertex(qx0, H_RIM, qz1)

        # Well inner ceiling at H_WELL
        bevel = 0.02
        w_t0 = add_vertex(qx0 + bevel, H_WELL, qz0 + bevel)
        w_t1 = add_vertex(qx1 - bevel, H_WELL, qz0 + bevel)
        w_t2 = add_vertex(qx1 - bevel, H_WELL, qz1 - bevel)
        w_t3 = add_vertex(qx0 + bevel, H_WELL, qz1 - bevel)

        # Bevel walls up into well
        add_quad(w_r0, w_r1, w_t1, w_t0)
        add_quad(w_r1, w_r2, w_t2, w_t1)
        add_quad(w_r2, w_r3, w_t3, w_t2)
        add_quad(w_r3, w_r0, w_t0, w_t3)

        # Luminaire diffuser plate (facing down)
        # Subdivided for smooth lighting
        subdiv = 6
        grid_v = []
        for sy in range(subdiv + 1):
            row = []
            tz = qz0 + bevel + (qz1 - qz0 - 2*bevel) * (sy / subdiv)
            for sx in range(subdiv + 1):
                tx = qx0 + bevel + (qx1 - qx0 - 2*bevel) * (sx / subdiv)
                row.append(add_vertex(tx, H_WELL, tz))
            grid_v.append(row)

        for sy in range(subdiv):
            for sx in range(subdiv):
                add_quad(grid_v[sy+1][sx], grid_v[sy+1][sx+1], grid_v[sy][sx+1], grid_v[sy][sx])

    # 5. Cross Support Trusses (along center X=0 and Z=0)
    # Truss along X: Z in [-0.03, 0.03], X in [-0.44, 0.44]
    truss_pts = [
        (-0.44, -0.03), (0.44, -0.03), (0.44, 0.03), (-0.44, 0.03)
    ]
    tx_b0 = add_vertex(-0.44, H_TRUSS, -0.03)
    tx_b1 = add_vertex( 0.44, H_TRUSS, -0.03)
    tx_b2 = add_vertex( 0.44, H_TRUSS,  0.03)
    tx_b3 = add_vertex(-0.44, H_TRUSS,  0.03)

    # Truss bottom face
    add_quad(tx_b3, tx_b2, tx_b1, tx_b0)

    # Truss along Z: X in [-0.03, 0.03], Z in [-0.44, 0.44]
    tz_b0 = add_vertex(-0.03, H_TRUSS, -0.44)
    tz_b1 = add_vertex( 0.03, H_TRUSS, -0.44)
    tz_b2 = add_vertex( 0.03, H_TRUSS,  0.44)
    tz_b3 = add_vertex(-0.03, H_TRUSS,  0.44)

    add_quad(tz_b3, tz_b2, tz_b1, tz_b0)

    # 6. Central Junction Hub / Industrial Lantern Box
    hub_rad = 0.09
    hub_top = []
    hub_bot = []
    for p in range(8):
        ang = p * 2.0 * math.pi / 8.0 + math.pi / 8.0
        hx = math.cos(ang) * hub_rad
        hz = math.sin(ang) * hub_rad
        hub_top.append(add_vertex(hx, H_TRUSS, hz))
        hub_bot.append(add_vertex(hx, H_HUB, hz))

    for p in range(8):
        p_next = (p + 1) % 8
        add_quad(hub_top[p], hub_top[p_next], hub_bot[p_next], hub_bot[p])

    hub_center = add_vertex(0.0, H_HUB - 0.005, 0.0)
    for p in range(8):
        p_next = (p + 1) % 8
        add_tri(hub_bot[p_next], hub_bot[p], hub_center)

    out_json = {
        "verts_count": len(verts),
        "verts": verts,
        "faces_count": len(faces),
        "faces": faces
    }
    with open(ROOT / "ceiling.json", "w", encoding="utf-8") as f:
        json.dump(out_json, f)
    print(f"Generated ceiling.json: {len(verts)} verts, {len(faces)} faces.")

if __name__ == "__main__":
    build_ceiling_tile()
