#!/usr/bin/env python3
"""Builds all 3D modular wall and ground models with complete PBR texture sets.

Models generated:
  - data/models/wall/wall.glb (Standard Military Sector 07)
  - data/models/wall_hazard/wall_hazard.glb (Industrial Reactor Hazard)
  - data/models/wall_tech/wall_tech.glb (Cryo / Quantum Tech Lab)
  - data/models/wall_rusted/wall_rusted.glb (Derelict / Wasteland)
  - data/models/ground/ground.glb (Standard Military Diamond Tread Tile)
  - data/models/ground/ground_hazard.glb (Industrial Hazard Grate Tile)
  - data/models/ground/ground_tech.glb (Hexagonal Quantum Power Tile)

Godot scenes:
  - scenes/environment/wall.tscn
  - scenes/environment/wall_hazard.tscn
  - scenes/environment/wall_tech.tscn
  - scenes/environment/wall_rusted.tscn
  - scenes/environment/ground.tscn
  - scenes/environment/ground_hazard.tscn
  - scenes/environment/ground_tech.tscn
"""
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def make_pbr_maps(raw_img: Path, out_dir: Path, name_prefix: str, emission_type: str = "cyan", rotate_deg: int = 0) -> dict[str, bytes]:
    out_dir.mkdir(parents=True, exist_ok=True)
    albedo_path = out_dir / f"{name_prefix}_albedo.png"
    normal_path = out_dir / f"{name_prefix}_normal.png"
    orm_path = out_dir / f"{name_prefix}_ORM.png"
    emission_path = out_dir / f"{name_prefix}_emission.png"

    # 1. Albedo
    cmd = ["convert", str(raw_img)]
    if rotate_deg != 0:
        cmd += ["-rotate", str(rotate_deg)]
    cmd.append(str(albedo_path))
    subprocess.run(cmd, check=True)

    # 2. Emission
    if emission_type == "cyan":
        subprocess.run([
            "convert", str(albedo_path),
            "-channel", "R", "-threshold", "70%",
            "-channel", "G", "-threshold", "55%",
            "-channel", "B", "-threshold", "75%",
            str(emission_path)
        ], check=True)
    elif emission_type == "amber":
        subprocess.run([
            "convert", str(albedo_path),
            "-channel", "R", "-threshold", "75%",
            "-channel", "G", "-threshold", "50%",
            "-channel", "B", "-threshold", "30%",
            str(emission_path)
        ], check=True)
    elif emission_type == "blue":
        subprocess.run([
            "convert", str(albedo_path),
            "-channel", "R", "-threshold", "40%",
            "-channel", "G", "-threshold", "55%",
            "-channel", "B", "-threshold", "70%",
            str(emission_path)
        ], check=True)
    elif emission_type == "red":
        subprocess.run([
            "convert", str(albedo_path),
            "-channel", "R", "-threshold", "60%",
            "-channel", "G", "-threshold", "20%",
            "-channel", "B", "-threshold", "20%",
            str(emission_path)
        ], check=True)
    else:
        # Subtle default
        subprocess.run([
            "convert", str(albedo_path),
            "-threshold", "85%",
            str(emission_path)
        ], check=True)

    # 3. Normal Map
    dx_path = out_dir / f"temp_{name_prefix}_dx.png"
    dy_path = out_dir / f"temp_{name_prefix}_dy.png"
    subprocess.run([
        "convert", str(albedo_path), "-colorspace", "Gray",
        "-define", "convolve:scale=1.5",
        "-bias", "50%", "-convolve", "-1,0,1,-2,0,2,-1,0,1",
        str(dx_path)
    ], check=True)
    subprocess.run([
        "convert", str(albedo_path), "-colorspace", "Gray",
        "-define", "convolve:scale=1.5",
        "-bias", "50%", "-convolve", "-1,-2,-1,0,0,0,1,2,1",
        str(dy_path)
    ], check=True)
    subprocess.run([
        "convert",
        str(dx_path), str(dy_path),
        "(", str(albedo_path), "-fill", "#ffffff", "-colorize", "100%", ")",
        "-combine", str(normal_path)
    ], check=True)
    for p in [dx_path, dy_path]:
        if p.exists(): p.unlink()

    # 4. ORM Map (R: Occlusion=90%, G: Roughness=55%, B: Metal=75%)
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
        "normal": normal_path.read_bytes(),
        "orm": orm_path.read_bytes(),
        "emission": emission_path.read_bytes()
    }


def compute_normals(verts, tris):
    num_v = len(verts)
    v_normals = [[0.0, 0.0, 0.0] for _ in range(num_v)]
    for v0, v1, v2 in tris:
        p0 = verts[v0]
        p1 = verts[v1]
        p2 = verts[v2]
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
    return v_normals


def build_glb_file(verts, tris, normals, uvs, tangents, textures: dict[str, bytes], mesh_name: str, mat_name: str) -> bytes:
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

    # 6. Embedded Textures
    images = []
    textures_list = []

    # Albedo
    off, length = append_data(textures["albedo"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": f"{mat_name}_BaseColor", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    # Normal
    off, length = append_data(textures["normal"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": f"{mat_name}_Normal", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    # ORM
    off, length = append_data(textures["orm"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": f"{mat_name}_ORM", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    # Emission
    off, length = append_data(textures["emission"])
    buffer_views.append({"buffer": 0, "byteOffset": off, "byteLength": length})
    images.append({"name": f"{mat_name}_Emission", "mimeType": "image/png", "bufferView": len(buffer_views) - 1})
    textures_list.append({"sampler": 0, "source": len(images) - 1})

    samplers = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]

    material = {
        "name": mat_name,
        "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0},
            "metallicRoughnessTexture": {"index": 2},
            "metallicFactor": 0.85,
            "roughnessFactor": 0.55
        },
        "normalTexture": {"index": 1, "scale": 1.0},
        "emissiveTexture": {"index": 3},
        "emissiveFactor": [1.0, 1.0, 1.0]
    }

    gltf_doc = {
        "asset": {
            "version": "2.0",
            "generator": "Game-no-7 3D Modular Environment Builder",
            "copyright": "Game-no-7 asset repository"
        },
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"name": mesh_name, "mesh": 0}],
        "materials": [material],
        "textures": textures_list,
        "images": images,
        "samplers": samplers,
        "meshes": [{
            "name": f"{mesh_name}_Mesh",
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


def build_gltf_files(verts, tris, normals, uvs, tangents, mesh_name: str, mat_name: str, prefix: str) -> tuple[dict, bytes]:
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
            "generator": "Game-no-7 3D Modular Environment Builder",
            "copyright": "Game-no-7 asset repository"
        },
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": [{"name": mesh_name, "mesh": 0}],
        "materials": [{
            "name": mat_name,
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicRoughnessTexture": {"index": 2},
                "metallicFactor": 0.85,
                "roughnessFactor": 0.55
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
            {"name": f"{mat_name}_BaseColor", "uri": f"textures/{prefix}_albedo.png"},
            {"name": f"{mat_name}_Normal", "uri": f"textures/{prefix}_normal.png"},
            {"name": f"{mat_name}_ORM", "uri": f"textures/{prefix}_ORM.png"},
            {"name": f"{mat_name}_Emission", "uri": f"textures/{prefix}_emission.png"}
        ],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "meshes": [{
            "name": f"{mesh_name}_Mesh",
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


def build_all():
    # 1. Load wall geometry
    with open(ROOT / "wall.json", "r", encoding="utf-8") as f:
        wall_data = json.load(f)
    wall_verts = wall_data["verts"]
    wall_faces = wall_data["faces"]
    wall_tris = []
    for f in wall_faces:
        if len(f) == 3:
            wall_tris.append((f[0], f[1], f[2]))
        elif len(f) == 4:
            wall_tris.append((f[0], f[1], f[2]))
            wall_tris.append((f[0], f[2], f[3]))
    wall_normals = compute_normals(wall_verts, wall_tris)
    wall_tangents = [[1.0, 0.0, 0.0, 1.0] for _ in range(len(wall_verts))]

    # 2. Build Wall Variants UV unwraps:
    # A. Wall Military (Original Sector 07)
    uvs_military = [[0.0, 0.0] for _ in range(len(wall_verts))]
    for i, (x, y, z) in enumerate(wall_verts):
        if x < -0.445:
            u = 0.635 + (x - (-0.500)) / 0.055 * 0.070
            v = 0.010 + (0.134 - y) / 0.267 * 0.980
        elif -0.045 <= x <= 0.045:
            u = 0.635 + (x - (-0.045)) / 0.090 * 0.070
            v = 0.010 + (0.134 - y) / 0.267 * 0.980
        elif x > 0.445:
            u = 0.635 + (x - 0.445) / 0.055 * 0.070
            v = 0.010 + (0.134 - y) / 0.267 * 0.980
        elif y > 0.085:
            u = 0.610 + (abs(x) * 4.0 % 1.0) * 0.350
            v = 0.010 + (0.134 - y) / 0.048 * 0.080
        elif y < -0.070:
            u = 0.150 + (abs(x) * 4.0 % 1.0) * 0.350
            v = 0.720 + (-0.070 - y) / 0.063 * 0.240
        else:
            if -0.445 <= x < -0.245:
                px = (x - (-0.445)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.400 + px * 0.157; v = 0.010 + py * 0.117
            elif -0.245 <= x < -0.045:
                px = (x - (-0.245)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.166 + px * 0.156; v = 0.585 + py * 0.095
            elif 0.045 <= x < 0.245:
                px = (x - 0.045) / 0.200; py = (0.085 - y) / 0.155
                u = 0.400 + px * 0.157; v = 0.410 + py * 0.117
            else:
                px = (x - 0.245) / 0.200; py = (0.085 - y) / 0.155
                u = 0.400 + px * 0.157; v = 0.527 + py * 0.098
        uvs_military[i] = [u, v]

    # B. Wall Hazard (Industrial / Reactor Core)
    uvs_hazard = [[0.0, 0.0] for _ in range(len(wall_verts))]
    for i, (x, y, z) in enumerate(wall_verts):
        if x < -0.445:
            u = 0.640 + (x - (-0.500)) / 0.055 * 0.070
            v = 0.650 + (0.134 - y) / 0.267 * 0.330
        elif -0.045 <= x <= 0.045:
            u = 0.640 + (x - (-0.045)) / 0.090 * 0.070
            v = 0.650 + (0.134 - y) / 0.267 * 0.330
        elif x > 0.445:
            u = 0.640 + (x - 0.445) / 0.055 * 0.070
            v = 0.650 + (0.134 - y) / 0.267 * 0.330
        elif y > 0.085:
            u = 0.355 + (abs(x) * 4.0 % 1.0) * 0.145
            v = 0.020 + (0.134 - y) / 0.048 * 0.320
        elif y < -0.070:
            u = 0.780 + (abs(x) * 4.0 % 1.0) * 0.200
            v = 0.660 + (-0.070 - y) / 0.063 * 0.160
        else:
            if -0.445 <= x < -0.245:
                px = (x - (-0.445)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.015 + px * 0.155; v = 0.015 + py * 0.315
            elif -0.245 <= x < -0.045:
                px = (x - (-0.245)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.180 + px * 0.170; v = 0.340 + py * 0.310
            elif 0.045 <= x < 0.245:
                px = (x - 0.045) / 0.200; py = (0.085 - y) / 0.155
                u = 0.785 + px * 0.195; v = 0.020 + py * 0.310
            else:
                px = (x - 0.245) / 0.200; py = (0.085 - y) / 0.155
                u = 0.630 + px * 0.140; v = 0.340 + py * 0.310
        uvs_hazard[i] = [u, v]

    # C. Wall Tech (Cryo Lab / Quantum)
    uvs_tech = [[0.0, 0.0] for _ in range(len(wall_verts))]
    for i, (x, y, z) in enumerate(wall_verts):
        if x < -0.445:
            u = 0.520 + (x - (-0.500)) / 0.055 * 0.080
            v = 0.500 + (0.134 - y) / 0.267 * 0.460
        elif -0.045 <= x <= 0.045:
            u = 0.520 + (x - (-0.045)) / 0.090 * 0.080
            v = 0.500 + (0.134 - y) / 0.267 * 0.460
        elif x > 0.445:
            u = 0.520 + (x - 0.445) / 0.055 * 0.080
            v = 0.500 + (0.134 - y) / 0.267 * 0.460
        elif y > 0.085:
            u = 0.040 + (abs(x) * 4.0 % 1.0) * 0.440
            v = 0.740 + (0.134 - y) / 0.048 * 0.100
        elif y < -0.070:
            u = 0.740 + (abs(x) * 4.0 % 1.0) * 0.220
            v = 0.740 + (-0.070 - y) / 0.063 * 0.220
        else:
            if -0.445 <= x < -0.245:
                px = (x - (-0.445)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.260 + px * 0.220; v = 0.030 + py * 0.220
            elif -0.245 <= x < -0.045:
                px = (x - (-0.245)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.030 + px * 0.220; v = 0.260 + py * 0.220
            elif 0.045 <= x < 0.245:
                px = (x - 0.045) / 0.200; py = (0.085 - y) / 0.155
                u = 0.500 + px * 0.220; v = 0.260 + py * 0.220
            else:
                px = (x - 0.245) / 0.200; py = (0.085 - y) / 0.155
                u = 0.260 + px * 0.220; v = 0.500 + py * 0.220
        uvs_tech[i] = [u, v]

    # D. Wall Rusted (Derelict / Wasteland)
    uvs_rusted = [[0.0, 0.0] for _ in range(len(wall_verts))]
    for i, (x, y, z) in enumerate(wall_verts):
        if x < -0.445:
            u = 0.005 + (x - (-0.500)) / 0.055 * 0.065
            v = 0.020 + (0.134 - y) / 0.267 * 0.420
        elif -0.045 <= x <= 0.045:
            u = 0.005 + (x - (-0.045)) / 0.090 * 0.065
            v = 0.020 + (0.134 - y) / 0.267 * 0.420
        elif x > 0.445:
            u = 0.005 + (x - 0.445) / 0.055 * 0.065
            v = 0.020 + (0.134 - y) / 0.267 * 0.420
        elif y > 0.085:
            u = 0.500 + (abs(x) * 4.0 % 1.0) * 0.480
            v = 0.760 + (0.134 - y) / 0.048 * 0.080
        elif y < -0.070:
            u = 0.250 + (abs(x) * 4.0 % 1.0) * 0.250
            v = 0.460 + (-0.070 - y) / 0.063 * 0.270
        else:
            if -0.445 <= x < -0.245:
                px = (x - (-0.445)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.040 + px * 0.200; v = 0.020 + py * 0.420
            elif -0.245 <= x < -0.045:
                px = (x - (-0.245)) / 0.200; py = (0.085 - y) / 0.155
                u = 0.250 + px * 0.250; v = 0.750 + py * 0.230
            elif 0.045 <= x < 0.245:
                px = (x - 0.045) / 0.200; py = (0.085 - y) / 0.155
                u = 0.500 + px * 0.240; v = 0.020 + py * 0.420
            else:
                px = (x - 0.245) / 0.200; py = (0.085 - y) / 0.155
                u = 0.750 + px * 0.230; v = 0.020 + py * 0.420
        uvs_rusted[i] = [u, v]

    # Process Wall Variants Textures and Bake
    wall_configs = [
        ("wall", ROOT / "data/models/wall", ROOT / "texture_0.webp", "Wall", "Wall_SciFi_PBR", uvs_military, "cyan", 90, "Wall"),
        ("wall_hazard", ROOT / "data/models/wall_hazard", ROOT / "data/models/wall_hazard/raw_texture.png", "Wall_Hazard", "Wall_Hazard_PBR", uvs_hazard, "amber", 0, "Wall_Hazard"),
        ("wall_tech", ROOT / "data/models/wall_tech", ROOT / "data/models/wall_tech/raw_texture.png", "Wall_Tech", "Wall_Tech_PBR", uvs_tech, "blue", 0, "Wall_Tech"),
        ("wall_rusted", ROOT / "data/models/wall_rusted", ROOT / "data/models/wall_rusted/raw_texture.png", "Wall_Rusted", "Wall_Rusted_PBR", uvs_rusted, "red", 0, "Wall_Rusted"),
    ]

    for model_id, model_dir, raw_tex, mesh_n, mat_n, uvs, em_type, rot, pfx in wall_configs:
        print(f"Baking Wall Variant: {model_id}...")
        tex_dir = model_dir / "textures"
        tex_maps = make_pbr_maps(raw_tex, tex_dir, pfx, em_type, rot)

        glb_data = build_glb_file(wall_verts, wall_tris, wall_normals, uvs, wall_tangents, tex_maps, mesh_n, mat_n)
        (model_dir / f"{model_id}.glb").write_bytes(glb_data)

        gltf_doc, bin_bytes = build_gltf_files(wall_verts, wall_tris, wall_normals, uvs, wall_tangents, mesh_n, mat_n, pfx)
        (model_dir / "scene.gltf").write_text(json.dumps(gltf_doc, indent=2))
        (model_dir / "scene.bin").write_bytes(bin_bytes)

        # Godot scene
        scene_path = ROOT / f"scenes/environment/{model_id}.tscn"
        scene_path.parent.mkdir(parents=True, exist_ok=True)
        scene_path.write_text(f"""[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://data/models/{model_id}/{model_id}.glb" id="1_{model_id}_glb"]

[sub_resource type="BoxShape3D" id="Shape_{model_id}_col"]
size = Vector3(1.0, 0.27, 0.05)

[node name="{mesh_n}" type="Node3D"]

[node name="{mesh_n}Mesh" parent="." instance=ExtResource("1_{model_id}_glb")]

[node name="StaticBody3D" type="StaticBody3D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="StaticBody3D"]
shape = SubResource("Shape_{model_id}_col")
""")

    # 3. Load Ground Geometry
    with open(ROOT / "ground.json", "r", encoding="utf-8") as f:
        ground_data = json.load(f)
    ground_verts = ground_data["verts"]
    ground_faces = ground_data["faces"]
    ground_tris = []
    for f in ground_faces:
        if len(f) == 3:
            ground_tris.append((f[0], f[1], f[2]))
        elif len(f) == 4:
            ground_tris.append((f[0], f[1], f[2]))
            ground_tris.append((f[0], f[2], f[3]))
    ground_normals = compute_normals(ground_verts, ground_tris)
    ground_tangents = [[1.0, 0.0, 0.0, 1.0] for _ in range(len(ground_verts))]

    # Ground UV unwraps:
    # Direct planar XZ unwrap with bevel wrapping
    ground_uvs = [[0.0, 0.0] for _ in range(len(ground_verts))]
    for i, (x, y, z) in enumerate(ground_verts):
        u = (x - (-0.5)) / 1.0
        v = (z - (-0.5)) / 1.0
        ground_uvs[i] = [max(0.001, min(0.999, u)), max(0.001, min(0.999, v))]

    ground_configs = [
        ("ground", ROOT / "data/models/ground", ROOT / "data/models/ground/raw_ground_military.png", "Ground", "Ground_Military_PBR", ground_uvs, "cyan", 0, "Ground"),
        ("ground_hazard", ROOT / "data/models/ground_hazard", ROOT / "data/models/ground/raw_ground_hazard.png", "Ground_Hazard", "Ground_Hazard_PBR", ground_uvs, "amber", 0, "Ground_Hazard"),
        ("ground_tech", ROOT / "data/models/ground_tech", ROOT / "data/models/ground/raw_ground_tech.png", "Ground_Tech", "Ground_Tech_PBR", ground_uvs, "blue", 0, "Ground_Tech"),
    ]

    for model_id, model_dir, raw_tex, mesh_n, mat_n, uvs, em_type, rot, pfx in ground_configs:
        print(f"Baking Ground Variant: {model_id}...")
        tex_dir = model_dir / "textures"
        tex_maps = make_pbr_maps(raw_tex, tex_dir, pfx, em_type, rot)

        glb_data = build_glb_file(ground_verts, ground_tris, ground_normals, uvs, ground_tangents, tex_maps, mesh_n, mat_n)
        (model_dir / f"{model_id}.glb").write_bytes(glb_data)

        gltf_doc, bin_bytes = build_gltf_files(ground_verts, ground_tris, ground_normals, uvs, ground_tangents, mesh_n, mat_n, pfx)
        (model_dir / "scene.gltf").write_text(json.dumps(gltf_doc, indent=2))
        (model_dir / "scene.bin").write_bytes(bin_bytes)

        # Godot scene
        scene_path = ROOT / f"scenes/environment/{model_id}.tscn"
        scene_path.parent.mkdir(parents=True, exist_ok=True)
        scene_path.write_text(f"""[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://data/models/{model_id}/{model_id}.glb" id="1_{model_id}_glb"]

[sub_resource type="BoxShape3D" id="Shape_{model_id}_col"]
size = Vector3(1.0, 0.06, 1.0)

[node name="{mesh_n}" type="Node3D"]

[node name="{mesh_n}Mesh" parent="." instance=ExtResource("1_{model_id}_glb")]

[node name="StaticBody3D" type="StaticBody3D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="StaticBody3D"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.03, 0)
shape = SubResource("Shape_{model_id}_col")
""")

    
    # 4. Load Ceiling Geometry
    with open(ROOT / "ceiling.json", "r", encoding="utf-8") as f:
        ceiling_data = json.load(f)
    ceiling_verts = ceiling_data["verts"]
    ceiling_faces = ceiling_data["faces"]
    ceiling_tris = []
    for f in ceiling_faces:
        if len(f) == 3:
            ceiling_tris.append((f[0], f[1], f[2]))
        elif len(f) == 4:
            ceiling_tris.append((f[0], f[1], f[2]))
            ceiling_tris.append((f[0], f[2], f[3]))
    ceiling_normals = compute_normals(ceiling_verts, ceiling_tris)
    ceiling_tangents = [[1.0, 0.0, 0.0, 1.0] for _ in range(len(ceiling_verts))]

    ceiling_uvs = [[0.0, 0.0] for _ in range(len(ceiling_verts))]
    for i, (x, y, z) in enumerate(ceiling_verts):
        u = (x - (-0.5)) / 1.0
        v = (z - (-0.5)) / 1.0
        ceiling_uvs[i] = [max(0.001, min(0.999, u)), max(0.001, min(0.999, v))]

    ceiling_configs = [
        ("ceiling", ROOT / "data/models/ceiling", ROOT / "data/models/ceiling/raw_ceiling_military.png", "Ceiling", "Ceiling_Military_PBR", ceiling_uvs, "cyan", 0, "Ceiling"),
        ("ceiling_hazard", ROOT / "data/models/ceiling_hazard", ROOT / "data/models/ceiling/raw_ceiling_hazard.png", "Ceiling_Hazard", "Ceiling_Hazard_PBR", ceiling_uvs, "amber", 0, "Ceiling_Hazard"),
        ("ceiling_tech", ROOT / "data/models/ceiling_tech", ROOT / "data/models/ceiling/raw_ceiling_tech.png", "Ceiling_Tech", "Ceiling_Tech_PBR", ceiling_uvs, "blue", 0, "Ceiling_Tech"),
    ]

    for model_id, model_dir, raw_tex, mesh_n, mat_n, uvs, em_type, rot, pfx in ceiling_configs:
        print(f"Baking Ceiling Variant: {model_id}...")
        tex_dir = model_dir / "textures"
        tex_maps = make_pbr_maps(raw_tex, tex_dir, pfx, em_type, rot)

        glb_data = build_glb_file(ceiling_verts, ceiling_tris, ceiling_normals, uvs, ceiling_tangents, tex_maps, mesh_n, mat_n)
        (model_dir / f"{model_id}.glb").write_bytes(glb_data)

        gltf_doc, bin_bytes = build_gltf_files(ceiling_verts, ceiling_tris, ceiling_normals, uvs, ceiling_tangents, mesh_n, mat_n, pfx)
        (model_dir / "scene.gltf").write_text(json.dumps(gltf_doc, indent=2))
        (model_dir / "scene.bin").write_bytes(bin_bytes)

        # Godot scene
        scene_path = ROOT / f"scenes/environment/{model_id}.tscn"
        scene_path.parent.mkdir(parents=True, exist_ok=True)
        scene_path.write_text(f"""[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://data/models/{model_id}/{model_id}.glb" id="1_{model_id}_glb"]

[sub_resource type="BoxShape3D" id="Shape_{model_id}_col"]
size = Vector3(1.0, 0.08, 1.0)

[node name="{mesh_n}" type="Node3D"]

[node name="{mesh_n}Mesh" parent="." instance=ExtResource("1_{model_id}_glb")]

[node name="StaticBody3D" type="StaticBody3D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="CollisionShape3D" type="CollisionShape3D" parent="StaticBody3D"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.04, 0)
shape = SubResource("Shape_{model_id}_col")
""")

    print("All wall, ground, and ceiling variants built successfully!")


if __name__ == "__main__":
    build_all()
