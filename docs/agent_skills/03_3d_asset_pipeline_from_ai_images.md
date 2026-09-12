# Skill 03: End-to-End 3D Asset Creation from AI Generated Textures

This document details the complete, hermetic pipeline for transforming AI-generated images into production-grade 3D glTF 2.0 / GLB assets with PBR materials, collision geometry, and headless verification renders.

---

## 1. Step 1: Prompting for Game-Ready Texture Atlases & Tiles
When requesting image textures for 3D modeling, structure the prompt with key constraints:
- **Atlas Type**: `"sci-fi modular texture atlas, game texture sheet, flat orthographic texture map, photorealistic PBR material texture"`
- **Tileable Surface Type**: `"modular ground plate / ceiling tile, top-down flat orthographic view, seamless repeating texture, photorealistic PBR"`
- **Avoid Perspective Distortion**: Specify `"flat orthographic texture map, 2D game asset sheet, no 3D angle"`.

---

## 2. Step 2: Deriving PBR Texture Channels (Albedo, Normal, ORM, Emission)

In headless environments without heavy graphic packages, use ImageMagick (`convert`):

```bash
# 1. Albedo (Rotate if texture orientation needs horizontal alignment)
convert raw_texture.png -rotate 90 Wall_albedo.png

# 2. Normal Map via Sobel Convolution Kernels
convert Wall_albedo.png -colorspace Gray -define convolve:scale=1.5 -bias 50% -convolve "-1,0,1,-2,0,2,-1,0,1" temp_dx.png
convert Wall_albedo.png -colorspace Gray -define convolve:scale=1.5 -bias 50% -convolve "-1,-2,-1,0,0,0,1,2,1" temp_dy.png
convert temp_dx.png temp_dy.png \( Wall_albedo.png -fill "#ffffff" -colorize 100% \) -combine Wall_normal.png
rm temp_dx.png temp_dy.png

# 3. ORM Map (Occlusion in R, Roughness in G, Metalness in B)
convert Wall_albedo.png -colorspace Gray \
  -channel R -evaluate set 90% \
  -channel G -evaluate set 55% \
  -channel B -evaluate set 75% \
  Wall_ORM.png

# 4. Emission Map (Threshold bright LED channels: Cyan, Amber, Blue, or Red)
convert Wall_albedo.png \
  -channel R -threshold 70% \
  -channel G -threshold 55% \
  -channel B -threshold 75% \
  Wall_emission.png
```

---

## 3. Step 3: Pure Python 3D Geometry Authoring & UV Unwrapping

Avoid third-party geometry packages (`trimesh`, `numpy`). Use Python's built-in `math`, `struct`, and `json`:

```python
# Compute vertex normals from triangle cross-products
def compute_normals(verts, tris):
    v_normals = [[0.0, 0.0, 0.0] for _ in range(len(verts))]
    for v0, v1, v2 in tris:
        p0, p1, p2 = verts[v0], verts[v1], verts[v2]
        d1 = [p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]]
        d2 = [p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]]
        nx = d1[1] * d2[2] - d1[2] * d2[1]
        ny = d1[2] * d2[0] - d1[0] * d2[2]
        nz = d1[0] * d2[1] - d1[1] * d2[0]
        for vi in (v0, v1, v2):
            v_normals[vi][0] += nx; v_normals[vi][1] += ny; v_normals[vi][2] += nz
    for i in range(len(verts)):
        nx, ny, nz = v_normals[i]
        l = math.hypot(nx, ny, nz)
        v_normals[i] = [nx/l, ny/l, nz/l] if l > 1e-6 else [0.0, 0.0, 1.0]
    return v_normals
```

### Sub-Panel UV Mapping Strategy:
For modular atlas sheets with distinct sub-panels, map vertex coordinates by region:
- **Vertical Posts / Pillars**: Map column X regions (`x < -0.445`, `abs(x) <= 0.045`, `x > 0.445`) to vertical atlas strips.
- **Top / Bottom Trims**: Map high/low Y regions to horizontal conduit / louver bands.
- **Recessed Panels**: Map internal bounding boxes directly to sub-rectangle UVs (`u0 + px * du`, `v0 + py * dv`).

---

## 4. Step 4: Pure Python glTF 2.0 / Binary GLB Packing

Pack vertices, normals, tangents, UVs, indices, and embedded PNG images directly into binary buffer chunks:

```python
# GLB Binary Header:
# 12-byte header: magic b"glTF", version 2, total_length
# JSON chunk header: chunk_len, chunk_type 0x4E4F534A
# JSON text (padded to 4-byte alignment)
# BIN chunk header: bin_len, chunk_type 0x004E4942
# Binary buffer (padded to 4-byte alignment)
```
See `tool/build_all_environment.py` for the complete standalone reference implementation.

---

## 5. Step 5: Headless C Software Rasterizer for Verification Renders

In environments without X11/GPU drivers, compile a standalone C rasterizer with `gcc -O3 tool/render_showcase.c -lm`:
- Implements 4x4 matrix transforms (Model, View, Perspective Projection).
- Sub-pixel barycentric rasterization with Z-buffering.
- Bilinear texture sampling and multi-light PBR illumination (key light, fill light, rim light, emissive bloom).
- Outputs `.ppm` files and converts them to `.png` with ImageMagick.
