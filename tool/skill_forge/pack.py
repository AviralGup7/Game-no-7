"""Bake a focus into its atlas and pack the shipped GLB (authoring only).

Two steps, one module, because they have to agree on the UV frame: `bake` paints every
unique material island and hands each part its slot, `to_glb` remaps the part's 0..1 UVs
into that slot and writes the single-mesh GLB. Doing the remap here (rather than while
authoring) is what lets a bolt ring re-use a tile it never saw painted.

The document that comes out is deliberately plain glTF 2.0 — one mesh, one primitive, one
`pbrMetallicRoughness` material with embedded PNGs, occlusion/roughness/metallic packed
into the one ORM texture the spec defines, plus named socket nodes — so it imports the same
way the environment sets do and needs no importer-side special cases.
"""
from __future__ import annotations

from .glb import ELEMENT_ARRAY_BUFFER, ARRAY_BUFFER, FLOAT, UINT, USHORT, GlbWriter
from .material import Atlas, build_shader
from .texture import Tile


def bake(mesh, atlas=None, tile_size=None):
    """Paint one island per unique material, then map every part into its island."""
    atlas = atlas or Atlas(size=mesh.atlas, tile=mesh.tile)
    tile_size = tile_size or atlas.inner
    cache = {}
    for part in mesh.parts:
        key = mesh.island_key(part)
        slot = atlas.slots.get(key)
        if slot is None:
            slot = atlas.island_for(key)
            canvas = Tile(tile_size)
            canvas.paint(build_shader(part.family, part.spec, part.detail))
            canvas.cavity_and_wear(spec_cavity(part), spec_wear(part))
            atlas.blit(slot, canvas)
            cache[key] = canvas
        part.island = slot
    remap_uvs(mesh, atlas)
    return atlas, cache


def spec_cavity(part):
    return part.detail.get('cavity', 0.6)


def spec_wear(part):
    return part.detail.get('wear', 0.5)


def remap_uvs(mesh, atlas):
    """Fold each part's 0..1 frame into its island's painted interior."""
    size, border, inner = atlas.size, atlas.border, atlas.inner
    for part in mesh.parts:
        slot = part.island
        origin_x = slot[0] * atlas.tile + border
        origin_y = slot[1] * atlas.tile + border
        part.uvs = [((origin_x + u * inner) / size, (origin_y + v * inner) / size)
                    for u, v in part.uvs]


def islands(mesh):
    """(part name, island key) inventory, for the build report."""
    return [{'part': part.name, 'family': part.family, 'island': list(part.island)} for part in mesh.parts]


# --------------------------------------------------------------------- packing


def flatten(mesh):
    positions, normals, tangents, uvs, indices = [], [], [], [], []
    for part in mesh.parts:
        offset = len(positions)
        for index in range(len(part.verts)):
            positions.append(part.verts[index])
            normals.append(part.normals[index])
            tangents.append(part.tangents[index])
            uvs.append(part.uvs[index])
        for triangle in part.tris:
            indices.extend(offset + vertex for vertex in triangle)
    return positions, normals, tangents, uvs, indices


def aabb(positions):
    low = [min(point[axis] for point in positions) for axis in range(3)]
    high = [max(point[axis] for point in positions) for axis in range(3)]
    return low, high


def to_glb(mesh, atlas, maps, meta):
    """Write the finished prop: one mesh, one PBR material, embedded textures, sockets."""
    positions, normals, tangents, uvs, indices = flatten(mesh)
    low, high = aabb(positions)
    writer = GlbWriter('Game-no-7 skill focus recipe 1 (%s)' % meta['skill_id'],
                       'Project-authored focus geometry and PBR atlas. No third-party art.')
    document = writer.document

    position_accessor = writer.packed([value for point in positions for value in point], 'VEC3', FLOAT,
                                      ARRAY_BUFFER, bounds=True)
    normal_accessor = writer.packed([value for point in normals for value in point], 'VEC3', FLOAT, ARRAY_BUFFER)
    tangent_accessor = writer.packed([value for point in tangents for value in point], 'VEC4', FLOAT, ARRAY_BUFFER)
    uv_accessor = writer.packed([value for point in uvs for value in point], 'VEC2', FLOAT, ARRAY_BUFFER)
    component = USHORT if len(positions) < 65536 else UINT
    index_accessor = writer.packed(indices, 'SCALAR', component, ELEMENT_ARRAY_BUFFER)

    images = {}
    for name in ('albedo', 'normal', 'orm', 'emissive'):
        images[name] = writer.texture(maps[name], '%s_%s.png' % (meta['slug'], name))
    # A material slot names a `textures` entry, and that entry names the image and sampler.
    # Pointing a slot straight at `images` leaves every index dangling out of range, which the
    # engine importer rejects even though a reader aimed at `images` still finds the maps.
    slots = {}
    for name, (image, sampler) in images.items():
        document.setdefault('textures', []).append({'sampler': sampler, 'source': image})
        slots[name] = len(document['textures']) - 1

    materials = [{
        'name': '%s focus alloy' % meta['display_name'],
        'pbrMetallicRoughness': {
            'baseColorTexture': {'index': slots['albedo'], 'texCoord': 0},
            'metallicRoughnessTexture': {'index': slots['orm'], 'texCoord': 0},
            'metallicFactor': 1.0,
            'roughnessFactor': 1.0,
        },
        'normalTexture': {'index': slots['normal'], 'texCoord': 0, 'scale': 1.0},
        'occlusionTexture': {'index': slots['orm'], 'texCoord': 0, 'strength': 1.0},
        'emissiveTexture': {'index': slots['emissive'], 'texCoord': 0},
        'emissiveFactor': tuple(round(value, 5) for value in meta['accent']),
        'doubleSided': False,
        'alphaMode': 'OPAQUE',
    }]
    document['materials'] = materials
    document['meshes'] = [{'name': '%s Focus' % meta['display_name'],
                           'primitives': [{'attributes': {'POSITION': position_accessor,
                                                          'NORMAL': normal_accessor,
                                                          'TANGENT': tangent_accessor,
                                                          'TEXCOORD_0': uv_accessor},
                                            'indices': index_accessor, 'material': 0}]}]

    mesh_node = {'name': 'FocusHull', 'mesh': 0}
    socket_nodes = [{'name': node['name'], 'translation': [round(value, 5) for value in node['translation']]}
                    for node in mesh.nodes]
    document['nodes'] = [{'name': '%sFocus' % meta['slug'], 'children': [1] + list(range(2, 2 + len(socket_nodes)))},
                         mesh_node] + socket_nodes
    document['scene'] = 0
    document['scenes'] = [{'name': meta['skill_id'], 'nodes': [0]}]
    document['extensionsUsed'] = ['KHR_materials_emissive_strength']
    materials[0]['extensions'] = {'KHR_materials_emissive_strength': {'emissiveStrength': meta['emissive_strength']}}
    document['extras'] = {
        'recipe': 'skill_focus_v1',
        'skill_id': meta['skill_id'],
        'display_name': meta['display_name'],
        'triangles': len(indices) // 3,
        'vertices': len(positions),
        'atlas': atlas.size,
        'islands': atlas.used,
        'size_metres': [round(high[axis] - low[axis], 4) for axis in range(3)],
        'aabb_min': [round(value, 4) for value in low],
        'aabb_max': [round(value, 4) for value in high],
        'parts': islands(mesh),
    }
    return writer.finish()
