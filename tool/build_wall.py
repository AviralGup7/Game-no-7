#!/usr/bin/env python3
"""Build the 3D wall model from wall.json coordinates and texture_0.webp.

Generates:
  - data/models/wall/wall.glb (glTF 2.0 binary with embedded PBR textures & modular 4-panel UV unwrap)
  - data/models/wall/scene.gltf + scene.bin + textures/
  - scenes/environment/wall.tscn (Godot 3D scene)

Run:
  python3 tool/build_wall.py
"""
import io
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def build_pbr_textures(raw_texture_path: Path, tex_dir: Path) -> dict[str, bytes]:
    tex_dir.mkdir(parents=True, exist_ok=True)
    albedo_path = tex_dir / "Wall_albedo.png"
    emission_path = tex_dir / "Wall_emission.png"
    normal_path = tex_dir / "Wall_normal.png"
    orm_path = tex_dir / "Wall_ORM.png"

    # 1. Albedo: Rotated 90 CW so text and trims run horizontally
    subprocess.run([
        "convert", str(raw_texture_path), "-rotate", "90", str(albedo_path)
    ], check=True)

    # 2. Emission map: extract bright cyan and white lights
    subprocess.run([
        "convert", str(albedo_path),
        "-channel", "R", "-threshold", "70%",
        "-channel", "G", "-threshold", "55%",
        "-channel", "B", "-threshold", "75%",
        str(emission_path)
    ], check=True)

    # 3. Normal map
    subprocess.run([
        "convert", str(albedo_path), "-colorspace", "Gray",
        "-define", "convolve:scale=1.5",
        "-bias", "50%", "-convolve", "-1,0,1,-2,0,2,-1,0,1",
        str(tex_dir / "temp_dx.png")
    ], check=True)
    subprocess.run([
        "convert", str(albedo_path), "-colorspace", "Gray",
        "-define", "convolve:scale=1.5",
        "-bias", "50%", "-convolve", "-1,-2,-1,0,0,0,1,2,1",
        str(tex_dir / "temp_dy.png")
    ], check=True)
    subprocess.run([
        "convert",
        str(tex_dir / "temp_dx.png"),
        str(tex_dir / "temp_dy.png"),
        "(", str(albedo_path), "-fill", "#ffffff", "-colorize", "100%", ")",
        "-combine", str(normal_path)
    ], check=True)
    for p in [tex_dir / "temp_dx.png", tex_dir / "temp_dy.png"]:
        if p.exists(): p.unlink()

    # 4. ORM map (R: Occlusion=230, G: Roughness=140, B: Metal=180)
    subprocess.run([
        "convert", str(albedo_path),
        "-colorspace", "Gray",
        "-channel", "R", "-evaluate", "set", "90%",
        "-channel", "G", "-evaluate", "set", "55%",
        "-channel", "B", "-evaluate", "set", "75%",
        str(orm_path)
    ], check=True)

    return {
        "albedo": albedo_path.read_bytes(),
        "emission": emission_path.read_bytes(),
        "normal": normal_path.read_bytes(),
        "orm": orm_path.read_bytes()
    }


def build_wall_geometry(json_path: Path):
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    raw_verts = data["verts"]
    raw_faces = data["faces"]
    num_v = len(raw_verts)

    # Triangulate faces
    tris = []
    for f in raw_faces:
        if len(f) == 3:
            tris.append((f[0], f[1], f[2]))
        elif len(f) == 4:
            tris.append((f[0], f[1], f[2]))
            tris.append((f[0], f[2], f[3]))

    # Smooth normals
    v_normals = [[0.0, 0.0, 0.0] for _ in range(num_v)]
    for v0, v1, v2 in tris:
        p0 = raw_verts[v0]
        p1 = raw_verts[v1]
        p2 = raw_verts[v2]
        d1 = [p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]
        d2 = [p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]]
        nx = d1[1] * d2[2] - d1[2] * d2[1]
        ny = d1[2] * d2[0] - d1[0] * d2[2]
        nz = d1[0] * d2[1] - d1[1] * d2[0]
        for vi in (v0, v1, v2):
            v_normals[vi][0] += nx
            v_normals[vi][1] += ny
            v_normals[vi][2] += nz

    for i in range(num_v):
        nx, ny, nz = v_normals[i]
        l = math.sqrt(nx * nx + ny * ny + nz * nz)
        if l > 1e-6:
            v_normals[i] = [nx / l, ny / l, nz / l]
        else:
            v_normals[i] = [0.0, 0.0, 1.0]

    # Modular 4-Panel Seamless UV mapping:
    uvs = [[0.0, 0.0] for _ in range(num_v)]
    for i in range(num_v):
        x, y, z = raw_verts[i]

        # 1. Structural Pillars (Left, Center, Right)
        if x < -0.445:
            u = 0.635 + (x - (-0.500)) / 0.055 * 0.070
            v = 0.010 + (0.134 - y) / 0.267 * 0.980
        elif -0.045 <= x <= 0.045:
            u = 0.635 + (x - (-0.045)) / 0.090 * 0.070
            v = 0.010 + (0.134 - y) / 0.267 * 0.980
        elif x > 0.445:
            u = 0.635 + (x - 0.445) / 0.055 * 0.070
            v = 0.010 + (0.134 - y) / 0.267 * 0.980
        # 2. Top Trims
        elif y > 0.085:
            u = 0.610 + (abs(x) * 4.0 % 1.0) * 0.350
            v = 0.010 + (0.134 - y) / 0.048 * 0.080
        # 3. Bottom Louvers
        elif y < -0.070:
            u = 0.150 + (abs(x) * 4.0 % 1.0) * 0.350
            v = 0.720 + (-0.070 - y) / 0.063 * 0.240
        # 4. Four Square Wall Panels
        else:
            if -0.445 <= x < -0.245:
                # Panel 1: SECTOR 07 / A BRIGHTER TOMORROW
                px = (x - (-0.445)) / 0.200
                py = (0.085 - y) / 0.155
                u = 0.400 + px * 0.157
                v = 0.010 + py * 0.117
            elif -0.245 <= x < -0.045:
                # Panel 2: HUMANITY FORWARDS + DELTA LOGO
                px = (x - (-0.245)) / 0.200
                py = (0.085 - y) / 0.155
                u = 0.166 + px * 0.156
                v = 0.585 + py * 0.095
            elif 0.045 <= x < 0.245:
                # Panel 3: HAZARD CAUTION WARNING
                px = (x - 0.045) / 0.200
                py = (0.085 - y) / 0.155
                u = 0.400 + px * 0.157
                v = 0.410 + py * 0.117
            else:
                # Panel 4: BEVELED TECH PANEL
                px = (x - 0.245) / 0.200
                py = (0.085 - y) / 0.155
                u = 0.400 + px * 0.157
                v = 0.527 + py * 0.098

        uvs[i] = [u, v]

    tangents = [[1.0, 0.0, 0.0, 1.0] for _ in range(num_v)]
    return raw_verts, tris, v_normals, uvs, tangents


def build_glb(verts, tris, normals, uvs, tangents, textures: dict[str, bytes]) -> bytes:
    bin_data = bytearray()

    def append_data(b_data: bytes, align: int = 4) -> tuple[int, int]:
        while len(bin_data) % align != 0:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(b_data)
        return offset, len(b_data)

    buffer_views = []
    accessors = []

    # 1. Indices
    idx_flat = []
    for tri in tris:
        idx_flat.extend(tri)
    idx_bytes = struct.pack(f"<{len(idx_flat)}I", *idx_flat)
    off, length = append_data(idx_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34963})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5125,
        "count": len(idx_flat),
        "type": "SCALAR",
        "min": [min(idx_flat)],
        "max": [max(idx_flat)]
    })
    idx_accessor = len(accessors) - 1

    # 2. POSITION
    pos_flat = []
    for v in verts:
        pos_flat.extend(v)
    pos_bytes = struct.pack(f"<{len(pos_flat)}f", *pos_flat)
    off, length = append_data(pos_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(verts),
        "type": "VEC3",
        "min": [min(v[0] for v in verts), min(v[1] for v in verts), min(v[2] for v in verts)],
        "max": [max(v[0] for v in verts), max(v[1] for v in verts), max(v[2] for v in verts)]
    })
    pos_accessor = len(accessors) - 1

    # 3. NORMAL
    norm_flat = []
    for n in normals:
        norm_flat.extend(n)
    norm_bytes = struct.pack(f"<{len(norm_flat)}f", *norm_flat)
    off, length = append_data(norm_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(normals),
        "type": "VEC3",
        "min": [min(n[0] for n in normals), min(n[1] for n in normals), min(n[2] for n in normals)],
        "max": [max(n[0] for n in normals), max(n[1] for n in normals), max(n[2] for n in normals)]
    })
    norm_accessor = len(accessors) - 1

    # 4. TANGENT
    tang_flat = []
    for t in tangents:
        tang_flat.extend(t)
    tang_bytes = struct.pack(f"<{len(tang_flat)}f", *tang_flat)
    off, length = append_data(tang_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(tangents),
        "type": "VEC4",
        "min": [min(t[0] for t in tangents), min(t[1] for t in tangents), min(t[2] for t in tangents), min(t[3] for t in tangents)],
        "max": [max(t[0] for t in tangents), max(t[1] for t in tangents), max(t[2] for t in tangents), max(t[3] for t in tangents)]
    })
    tang_accessor = len(accessors) - 1

    # 5. TEXCOORD_0
    uv_flat = []
    for u in uvs:
        uv_flat.extend(u)
    uv_bytes = struct.pack(f"<{len(uv_flat)}f", *uv_flat)
    off, length = append_data(uv_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(uvs),
        "type": "VEC2",
        "min": [min(u[0] for u in uvs), min(u[1] for u in uvs)],
        "max": [max(u[0] for u in uvs), max(u[1] for u in uvs)]
    })
    uv_accessor = len(accessors) - 1

    # 6. Embedded Images
    images = []
    textures_list = []

    # Albedo
    off, length = append_data(textures["albedo"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": "Wall_BaseColor", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    # Normal
    off, length = append_data(textures["normal"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": "Wall_Normal", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    # ORM
    off, length = append_data(textures["orm"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": "Wall_ORM", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    # Emission
    off, length = append_data(textures["emission"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": "Wall_Emission", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    samplers = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]

    material = {
        "name": "Wall_SciFi_PBR",
        "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0},
            "metallicRoughnessTexture": {"index": 2},
            "metallicFactor": 0.8,
            "roughnessFactor": 0.6
        },
        "normalTexture": {"index": 1, "scale": 1.0},
        "emissiveTexture": {"index": 3},
        "emissiveFactor": [1.0, 1.0, 1.0]
    }

    gltf_doc = {
        "asset": {
            "version": "2.0",
            "generator": "Game-no-7 3D Wall Builder (PBR Sci-Fi Modular Atlas)",
            "copyright": "Uploaded wall asset model"
        },
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"name": "Wall", "mesh": 0}],
        "materials": [material],
        "textures": textures_list,
        "images": images,
        "samplers": samplers,
        "meshes": [{
            "name": "Wall_Mesh",
            "primitives": [{
                "attributes": {
                    "POSITION": pos_accessor,
                    "NORMAL": norm_accessor,
                    "TANGENT": tang_accessor,
                    "TEXCOORD_0": uv_accessor
                },
                "indices": idx_accessor,
                "material": 0
            }]
        }],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_data)}]
    }

    json_bytes = json.dumps(gltf_doc, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "
    while len(bin_data) % 4 != 0:
        bin_data += b"\x00"

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    glb_header = struct.pack("<4sII", b"glTF", 2, total_len)
    json_header = struct.pack("<II", len(json_bytes), 0x4E4F534A)
    bin_header = struct.pack("<II", len(bin_data), 0x004E4942)

    return glb_header + json_header + json_bytes + bin_header + bin_data


def build_gltf(verts, tris, normals, uvs, tangents) -> tuple[dict, bytes]:
    bin_data = bytearray()

    def append_data(b_data: bytes, align: int = 4) -> tuple[int, int]:
        while len(bin_data) % align != 0:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(b_data)
        return offset, len(b_data)

    buffer_views = []
    accessors = []

    # 1. Indices
    idx_flat = []
    for tri in tris:
        idx_flat.extend(tri)
    idx_bytes = struct.pack(f"<{len(idx_flat)}I", *idx_flat)
    off, length = append_data(idx_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34963})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5125,
        "count": len(idx_flat),
        "type": "SCALAR",
        "min": [min(idx_flat)],
        "max": [max(idx_flat)]
    })
    idx_accessor = len(accessors) - 1

    # 2. POSITION
    pos_flat = []
    for v in verts:
        pos_flat.extend(v)
    pos_bytes = struct.pack(f"<{len(pos_flat)}f", *pos_flat)
    off, length = append_data(pos_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(verts),
        "type": "VEC3",
        "min": [min(v[0] for v in verts), min(v[1] for v in verts), min(v[2] for v in verts)],
        "max": [max(v[0] for v in verts), max(v[1] for v in verts), max(v[2] for v in verts)]
    })
    pos_accessor = len(accessors) - 1

    # 3. NORMAL
    norm_flat = []
    for n in normals:
        norm_flat.extend(n)
    norm_bytes = struct.pack(f"<{len(norm_flat)}f", *norm_flat)
    off, length = append_data(norm_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(normals),
        "type": "VEC3",
        "min": [min(n[0] for n in normals), min(n[1] for n in normals), min(n[2] for n in normals)],
        "max": [max(n[0] for n in normals), max(n[1] for n in normals), max(n[2] for n in normals)]
    })
    norm_accessor = len(accessors) - 1

    # 4. TANGENT
    tang_flat = []
    for t in tangents:
        tang_flat.extend(t)
    tang_bytes = struct.pack(f"<{len(tang_flat)}f", *tang_flat)
    off, length = append_data(tang_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(tangents),
        "type": "VEC4",
        "min": [min(t[0] for t in tangents), min(t[1] for t in tangents), min(t[2] for t in tangents), min(t[3] for t in tangents)],
        "max": [max(t[0] for t in tangents), max(t[1] for t in tangents), max(t[2] for t in tangents), max(t[3] for t in tangents)]
    })
    tang_accessor = len(accessors) - 1

    # 5. TEXCOORD_0
    uv_flat = []
    for u in uvs:
        uv_flat.extend(u)
    uv_bytes = struct.pack(f"<{len(uv_flat)}f", *uv_flat)
    off, length = append_data(uv_bytes)
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length, "target": 34962})
    accessors.append({
        "bufferView": len(buffer_views) - 1,
        "componentType": 5126,
        "count": len(uvs),
        "type": "VEC2",
        "min": [min(u[0] for u in uvs), min(u[1] for u in uvs)],
        "max": [max(u[0] for u in uvs), max(u[1] for u in uvs)]
    })
    uv_accessor = len(accessors) - 1

    gltf_doc = {
        "asset": {
            "version": "2.0",
            "generator": "Game-no-7 3D Wall Builder (PBR Sci-Fi Modular Atlas)",
            "copyright": "Uploaded wall asset model"
        },
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"name": "Wall", "mesh": 0}],
        "materials": [{
            "name": "Wall_SciFi_PBR",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicRoughnessTexture": {"index": 2},
                "metallicFactor": 0.8,
                "roughnessFactor": 0.6
            },
            "normalTexture": {"index": 1, "scale": 1.0},
            "emissiveTexture": {"index": 3},
            "emissiveFactor": [1.0, 1.0, 1.0]
        }],
        "textures": [
            {"sampler": 0, "source": 0},
            {"sampler": 0, "source": 1},
            {"sampler": 0, "source": 2},
            {"sampler": 0, "source": 3}
        ],
        "images": [
            {"name": "Wall_BaseColor", "uri": "textures/Wall_albedo.png"},
            {"name": "Wall_Normal", "uri": "textures/Wall_normal.png"},
            {"name": "Wall_ORM", "uri": "textures/Wall_ORM.png"},
            {"name": "Wall_Emission", "uri": "textures/Wall_emission.png"}
        ],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "meshes": [{
            "name": "Wall_Mesh",
            "primitives": [{
                "attributes": {
                    "POSITION": pos_accessor,
                    "NORMAL": norm_accessor,
                    "TANGENT": tang_accessor,
                    "TEXCOORD_0": uv_accessor
                },
                "indices": idx_accessor,
                "material": 0
            }]
        }],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"uri": "scene.bin", "byteLength": len(bin_data)}]
    }

    return gltf_doc, bytes(bin_data)


def main():
    json_path = ROOT / "wall.json"
    texture_path = ROOT / "texture_0.webp"
    out_dir = ROOT / "data/models/wall"
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading wall geometry from {json_path}...")
    verts, tris, normals, uvs, tangents = build_wall_geometry(json_path)
    print(f"Geometry: {len(verts)} vertices, {len(tris)} triangles.")

    tex_dir = out_dir / "textures"
    print(f"Processing PBR textures from {texture_path}...")
    textures = build_pbr_textures(texture_path, tex_dir)

    # Build GLB
    glb_data = build_glb(verts, tris, normals, uvs, tangents, textures)
    glb_path = out_dir / "wall.glb"
    glb_path.write_bytes(glb_data)
    print(f"Baked self-contained GLB: {glb_path} ({len(glb_data)} bytes)")

    # Build GLTF + BIN
    gltf_doc, bin_bytes = build_gltf(verts, tris, normals, uvs, tangents)
    (out_dir / "scene.gltf").write_text(json.dumps(gltf_doc, indent=2))
    (out_dir / "scene.bin").write_bytes(bin_bytes)
    print(f"Baked glTF scene: {out_dir / 'scene.gltf'} and {out_dir / 'scene.bin'}")

    # Build Godot .tscn scene
    scene_path = ROOT / "scenes/environment/wall.tscn"
    scene_path.parent.mkdir(parents=True, exist_ok=True)
    scene_path.write_text("""[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://data/models/wall/wall.glb" id="1_wall_glb"]

[sub_resource type="BoxShape3D" id="Shape_wall_col"]
size = Vector3(1.0, 0.27, 0.05)

[node name="Wall" type="Node3D"]

[node name="WallMesh" parent="." instance=ExtResource("1_wall_glb")]

[node name="StaticBody3D" type="StaticBody3D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="StaticBody3D"]
shape = SubResource("Shape_wall_col")
""")
    print(f"Authored Godot scene: {scene_path}")

    # Validate output assets
    sys.path.insert(0, str(ROOT))
    from tool.validate_assets import check_model
    check_model(glb_path, {glb_path.resolve()})
    approved_gltf = {
        (out_dir / "scene.gltf").resolve(),
        (out_dir / "scene.bin").resolve(),
        (tex_dir / "Wall_albedo.png").resolve(),
        (tex_dir / "Wall_normal.png").resolve(),
        (tex_dir / "Wall_ORM.png").resolve(),
        (tex_dir / "Wall_emission.png").resolve()
    }
    check_model(out_dir / "scene.gltf", approved_gltf)
    print("Validated GLB and glTF against asset specification: OK")


if __name__ == "__main__":
    main()
