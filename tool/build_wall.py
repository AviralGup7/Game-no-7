#!/usr/bin/env python3
"""Build the 3D wall model from wall.json coordinates and texture_0.webp.

Deterministic generation of:
  - data/models/wall/wall.glb (glTF 2.0 binary with embedded PBR textures)
  - data/models/wall/scene.gltf + scene.bin + texture maps (albedo, normal, ORM, emission)
  - scenes/environment/wall.tscn (Godot 3D scene)

Run:
  python3 tool/build_wall.py
"""
from __future__ import annotations

import io
import json
from pathlib import Path
import struct
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import sobel

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def build_pbr_textures(image_path: Path) -> dict[str, bytes]:
    """Extract PBR maps (albedo, normal, ORM, emission) from the base texture."""
    im = Image.open(image_path).convert('RGB')
    arr = np.array(im, dtype=np.float32)

    # 1. Albedo PNG
    albedo_bio = io.BytesIO()
    im.save(albedo_bio, format='PNG', optimize=True)
    albedo_bytes = albedo_bio.getvalue()

    # 2. Emission map (glowing cyan / blue indicators and white trims)
    is_blue = (arr[:, :, 2] > 140) & (arr[:, :, 1] > 120) & (arr[:, :, 0] < 140)
    is_white = (arr[:, :, 0] > 200) & (arr[:, :, 1] > 200) & (arr[:, :, 2] > 200)
    emission = np.zeros_like(arr, dtype=np.uint8)
    emission[is_blue] = arr[is_blue].astype(np.uint8)
    emission[is_white] = arr[is_white].astype(np.uint8)
    em_bio = io.BytesIO()
    Image.fromarray(emission).save(em_bio, format='PNG', optimize=True)
    emission_bytes = em_bio.getvalue()

    # 3. Normal map from surface luminance gradients
    lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    dx = sobel(lum, axis=1) * 0.05
    dy = sobel(lum, axis=0) * 0.05
    dz = np.ones_like(lum) * 25.0

    norm = np.sqrt(dx**2 + dy**2 + dz**2)
    nx = ((-dx / norm) * 0.5 + 0.5) * 255.0
    ny = ((-dy / norm) * 0.5 + 0.5) * 255.0
    nz = ((dz / norm) * 0.5 + 0.5) * 255.0
    normal_map = np.stack([nx, ny, nz], axis=-1).astype(np.uint8)
    nm_bio = io.BytesIO()
    Image.fromarray(normal_map).save(nm_bio, format='PNG', optimize=True)
    normal_bytes = nm_bio.getvalue()

    # 4. ORM (Occlusion, Roughness, Metallic)
    ao = np.clip(lum / 255.0 * 1.2, 0.2, 1.0) * 255.0
    rough = np.clip(255.0 - lum * 0.6, 60, 220)
    metal = np.clip(lum * 0.9, 40, 200)
    orm_map = np.stack([ao, rough, metal], axis=-1).astype(np.uint8)
    orm_bio = io.BytesIO()
    Image.fromarray(orm_map).save(orm_bio, format='PNG', optimize=True)
    orm_bytes = orm_bio.getvalue()

    return {
        'albedo': albedo_bytes,
        'emission': emission_bytes,
        'normal': normal_bytes,
        'orm': orm_bytes,
    }


def build_wall_geometry(json_path: Path):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    verts = np.array(data['verts'], dtype=np.float32)
    faces = data['faces']

    # Convert quads and triangles to unified triangle indices
    tris = []
    for f in faces:
        if len(f) == 3:
            tris.append(f)
        elif len(f) == 4:
            tris.append([f[0], f[1], f[2]])
            tris.append([f[0], f[2], f[3]])
    tris = np.array(tris, dtype=np.uint32)

    # Compute area-weighted smooth vertex normals
    v0 = verts[tris[:, 0]]
    v1 = verts[tris[:, 1]]
    v2 = verts[tris[:, 2]]
    face_normals = np.cross(v1 - v0, v2 - v0)
    fn_len = np.linalg.norm(face_normals, axis=1, keepdims=True)
    face_normals = np.divide(face_normals, fn_len, out=np.zeros_like(face_normals), where=fn_len > 1e-9)

    vert_normals = np.zeros_like(verts)
    for corner in range(3):
        np.add.at(vert_normals, tris[:, corner], face_normals)
    vn_len = np.linalg.norm(vert_normals, axis=1, keepdims=True)
    vert_normals = np.divide(vert_normals, vn_len, out=np.zeros_like(vert_normals), where=vn_len > 1e-9)

    # Texture UV mapping (aligned to the 3D wall proportions)
    x_min, x_max = verts[:, 0].min(), verts[:, 0].max()
    y_min, y_max = verts[:, 1].min(), verts[:, 1].max()
    u = (verts[:, 0] - x_min) / (x_max - x_min)
    v = (y_max - verts[:, 1]) / (y_max - y_min)
    uvs = np.column_stack([u, v]).astype(np.float32)

    # Tangents for normal mapping
    tangents = np.zeros((len(verts), 4), dtype=np.float32)
    tangents[:, 0] = 1.0
    tangents[:, 3] = 1.0

    return verts, tris, vert_normals, uvs, tangents


def build_glb(verts: np.ndarray, tris: np.ndarray, normals: np.ndarray,
              uvs: np.ndarray, tangents: np.ndarray, textures: dict[str, bytes]) -> bytes:
    """Pack geometry and PBR textures into a self-contained glTF 2.0 binary (.glb)."""
    bin_data = bytearray()

    def append_data(b_data: bytes, align: int = 4) -> tuple[int, int]:
        while len(bin_data) % align != 0:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(b_data)
        return offset, len(b_data)

    buffer_views = []
    accessors = []

    # 1. Indices (SCALAR, uint32)
    off, length = append_data(tris.flatten().tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34963})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5125,
        'count': len(tris) * 3,
        'type': 'SCALAR',
        'min': [int(tris.min())],
        'max': [int(tris.max())]
    })
    idx_accessor = len(accessors) - 1

    # 2. POSITION (VEC3, float32)
    off, length = append_data(verts.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(verts),
        'type': 'VEC3',
        'min': verts.min(axis=0).tolist(),
        'max': verts.max(axis=0).tolist()
    })
    pos_accessor = len(accessors) - 1

    # 3. NORMAL (VEC3, float32)
    off, length = append_data(normals.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(normals),
        'type': 'VEC3',
        'min': normals.min(axis=0).tolist(),
        'max': normals.max(axis=0).tolist()
    })
    norm_accessor = len(accessors) - 1

    # 4. TANGENT (VEC4, float32)
    off, length = append_data(tangents.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(tangents),
        'type': 'VEC4',
        'min': tangents.min(axis=0).tolist(),
        'max': tangents.max(axis=0).tolist()
    })
    tang_accessor = len(accessors) - 1

    # 5. TEXCOORD_0 (VEC2, float32)
    off, length = append_data(uvs.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(uvs),
        'type': 'VEC2',
        'min': uvs.min(axis=0).tolist(),
        'max': uvs.max(axis=0).tolist()
    })
    uv_accessor = len(accessors) - 1

    # 6. Embedded Images
    images = []
    textures_list = []

    # Albedo image (texture 0)
    off, length = append_data(textures['albedo'])
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length})
    images.append({'name': 'Wall_BaseColor', 'mimeType': 'image/png', 'bufferView': len(buffer_views) - 1})
    textures_list.append({'sampler': 0, 'source': len(images) - 1})

    # Normal map image (texture 1)
    off, length = append_data(textures['normal'])
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length})
    images.append({'name': 'Wall_Normal', 'mimeType': 'image/png', 'bufferView': len(buffer_views) - 1})
    textures_list.append({'sampler': 0, 'source': len(images) - 1})

    # ORM map image (texture 2)
    off, length = append_data(textures['orm'])
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length})
    images.append({'name': 'Wall_ORM', 'mimeType': 'image/png', 'bufferView': len(buffer_views) - 1})
    textures_list.append({'sampler': 0, 'source': len(images) - 1})

    # Emission map image (texture 3)
    off, length = append_data(textures['emission'])
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length})
    images.append({'name': 'Wall_Emission', 'mimeType': 'image/png', 'bufferView': len(buffer_views) - 1})
    textures_list.append({'sampler': 0, 'source': len(images) - 1})

    samplers = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}]

    material = {
        'name': 'Wall_SciFi_PBR',
        'pbrMetallicRoughness': {
            'baseColorTexture': {'index': 0},
            'metallicRoughnessTexture': {'index': 2},
            'metallicFactor': 0.8,
            'roughnessFactor': 0.6
        },
        'normalTexture': {'index': 1, 'scale': 1.0},
        'emissiveTexture': {'index': 3},
        'emissiveFactor': [1.0, 1.0, 1.0]
    }

    gltf_doc = {
        'asset': {
            'version': '2.0',
            'generator': 'Game-no-7 3D Wall Builder (PBR Sci-Fi)',
            'copyright': 'Uploaded wall asset model'
        },
        'scene': 0,
        'scenes': [{'name': 'Scene', 'nodes': [0]}],
        'nodes': [{'name': 'Wall', 'mesh': 0}],
        'materials': [material],
        'textures': textures_list,
        'images': images,
        'samplers': samplers,
        'meshes': [{
            'name': 'Wall_Mesh',
            'primitives': [{
                'attributes': {
                    'POSITION': pos_accessor,
                    'NORMAL': norm_accessor,
                    'TANGENT': tang_accessor,
                    'TEXCOORD_0': uv_accessor
                },
                'indices': idx_accessor,
                'material': 0
            }]
        }],
        'accessors': accessors,
        'bufferViews': buffer_views,
        'buffers': [{'byteLength': len(bin_data)}]
    }

    json_bytes = json.dumps(gltf_doc, separators=(',', ':'), ensure_ascii=True).encode('utf-8')
    while len(json_bytes) % 4 != 0:
        json_bytes += b' '
    while len(bin_data) % 4 != 0:
        bin_data += b'\x00'

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    glb_header = struct.pack('<4sII', b'glTF', 2, total_len)
    json_header = struct.pack('<II', len(json_bytes), 0x4E4F534A)
    bin_header = struct.pack('<II', len(bin_data), 0x004E4942)

    return glb_header + json_header + json_bytes + bin_header + bin_data


def build_gltf(verts: np.ndarray, tris: np.ndarray, normals: np.ndarray,
               uvs: np.ndarray, tangents: np.ndarray) -> tuple[dict, bytes]:
    """Generate detached scene.gltf and scene.bin."""
    bin_data = bytearray()

    def append_data(b_data: bytes, align: int = 4) -> tuple[int, int]:
        while len(bin_data) % align != 0:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(b_data)
        return offset, len(b_data)

    buffer_views = []
    accessors = []

    # 1. Indices (SCALAR, uint32)
    off, length = append_data(tris.flatten().tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34963})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5125,
        'count': len(tris) * 3,
        'type': 'SCALAR',
        'min': [int(tris.min())],
        'max': [int(tris.max())]
    })
    idx_accessor = len(accessors) - 1

    # 2. POSITION (VEC3, float32)
    off, length = append_data(verts.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(verts),
        'type': 'VEC3',
        'min': verts.min(axis=0).tolist(),
        'max': verts.max(axis=0).tolist()
    })
    pos_accessor = len(accessors) - 1

    # 3. NORMAL (VEC3, float32)
    off, length = append_data(normals.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(normals),
        'type': 'VEC3',
        'min': normals.min(axis=0).tolist(),
        'max': normals.max(axis=0).tolist()
    })
    norm_accessor = len(accessors) - 1

    # 4. TANGENT (VEC4, float32)
    off, length = append_data(tangents.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(tangents),
        'type': 'VEC4',
        'min': tangents.min(axis=0).tolist(),
        'max': tangents.max(axis=0).tolist()
    })
    tang_accessor = len(accessors) - 1

    # 5. TEXCOORD_0 (VEC2, float32)
    off, length = append_data(uvs.tobytes())
    buffer_views.append({'buffer': 0, 'byteOffset': off, 'byteLength': length, 'target': 34962})
    accessors.append({
        'bufferView': len(buffer_views) - 1,
        'componentType': 5126,
        'count': len(uvs),
        'type': 'VEC2',
        'min': uvs.min(axis=0).tolist(),
        'max': uvs.max(axis=0).tolist()
    })
    uv_accessor = len(accessors) - 1

    gltf_doc = {
        'asset': {
            'version': '2.0',
            'generator': 'Game-no-7 3D Wall Builder (PBR Sci-Fi)',
            'copyright': 'Uploaded wall asset model'
        },
        'scene': 0,
        'scenes': [{'name': 'Scene', 'nodes': [0]}],
        'nodes': [{'name': 'Wall', 'mesh': 0}],
        'materials': [{
            'name': 'Wall_SciFi_PBR',
            'pbrMetallicRoughness': {
                'baseColorTexture': {'index': 0},
                'metallicRoughnessTexture': {'index': 2},
                'metallicFactor': 0.8,
                'roughnessFactor': 0.6
            },
            'normalTexture': {'index': 1, 'scale': 1.0},
            'emissiveTexture': {'index': 3},
            'emissiveFactor': [1.0, 1.0, 1.0]
        }],
        'textures': [
            {'sampler': 0, 'source': 0},
            {'sampler': 0, 'source': 1},
            {'sampler': 0, 'source': 2},
            {'sampler': 0, 'source': 3}
        ],
        'images': [
            {'name': 'Wall_BaseColor', 'uri': 'textures/Wall_albedo.png'},
            {'name': 'Wall_Normal', 'uri': 'textures/Wall_normal.png'},
            {'name': 'Wall_ORM', 'uri': 'textures/Wall_ORM.png'},
            {'name': 'Wall_Emission', 'uri': 'textures/Wall_emission.png'}
        ],
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}],
        'meshes': [{
            'name': 'Wall_Mesh',
            'primitives': [{
                'attributes': {
                    'POSITION': pos_accessor,
                    'NORMAL': norm_accessor,
                    'TANGENT': tang_accessor,
                    'TEXCOORD_0': uv_accessor
                },
                'indices': idx_accessor,
                'material': 0
            }]
        }],
        'accessors': accessors,
        'bufferViews': buffer_views,
        'buffers': [{'uri': 'scene.bin', 'byteLength': len(bin_data)}]
    }

    return gltf_doc, bytes(bin_data)


def main():
    json_path = ROOT / 'wall.json'
    texture_path = ROOT / 'texture_0.webp'
    out_dir = ROOT / 'data/models/wall'
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f'Loading wall geometry from {json_path}...')
    verts, tris, normals, uvs, tangents = build_wall_geometry(json_path)
    print(f'Geometry: {len(verts)} vertices, {len(tris)} triangles.')

    print(f'Processing PBR textures from {texture_path}...')
    textures = build_pbr_textures(texture_path)

    # Save texture files to data/models/wall/textures
    tex_dir = out_dir / 'textures'
    tex_dir.mkdir(parents=True, exist_ok=True)
    (tex_dir / 'Wall_albedo.png').write_bytes(textures['albedo'])
    (tex_dir / 'Wall_normal.png').write_bytes(textures['normal'])
    (tex_dir / 'Wall_ORM.png').write_bytes(textures['orm'])
    (tex_dir / 'Wall_emission.png').write_bytes(textures['emission'])

    # Build GLB
    glb_data = build_glb(verts, tris, normals, uvs, tangents, textures)
    glb_path = out_dir / 'wall.glb'
    glb_path.write_bytes(glb_data)
    print(f'Baked self-contained GLB: {glb_path} ({len(glb_data)} bytes)')

    # Build GLTF + BIN
    gltf_doc, bin_bytes = build_gltf(verts, tris, normals, uvs, tangents)
    (out_dir / 'scene.gltf').write_text(json.dumps(gltf_doc, indent=2))
    (out_dir / 'scene.bin').write_bytes(bin_bytes)
    print(f'Baked glTF scene: {out_dir / "scene.gltf"} and {out_dir / "scene.bin"}')

    # Build Godot .tscn scene
    scene_path = ROOT / 'scenes/environment/wall.tscn'
    scene_path.parent.mkdir(parents=True, exist_ok=True)
    scene_path.write_text(f'''[gd_scene load_steps=3 format=3]

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
''')
    print(f'Authored Godot scene: {scene_path}')

    # Validate output
    from tool.validate_assets import check_model
    check_model(glb_path, {glb_path})
    approved_gltf = {
        (out_dir / 'scene.gltf').resolve(),
        (out_dir / 'scene.bin').resolve(),
        (tex_dir / 'Wall_albedo.png').resolve(),
        (tex_dir / 'Wall_normal.png').resolve(),
        (tex_dir / 'Wall_ORM.png').resolve(),
        (tex_dir / 'Wall_emission.png').resolve()
    }
    check_model(out_dir / 'scene.gltf', approved_gltf)
    print('Validated GLB and glTF against glTF 2.0 asset specification: OK')


if __name__ == '__main__':
    main()
