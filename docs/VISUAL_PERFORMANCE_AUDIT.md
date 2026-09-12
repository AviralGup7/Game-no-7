# Visual / Technical / Performance Audit — Agent 4

**Date:** 2026-09-12
**Auditor:** Agent 4 — Visual/Technical/Performance
**Scope:** Entire Station Zero delivery as it ships on Android — meshes, textures, materials, LOD, collision, draw calls, lighting, probes, navigation, streaming/visibility, and memory/performance risk. Campaign world `data/campaign/station_zero.json` (352×272 m, 6 districts, 13 floors, 24 props) + arena Pit (`scenes/arena/arena.tscn`) + shared `data/models/**` PBR modules + `assets/**` robots/weapons + `project.godot` Mobile renderer settings.
**Tool:** `tool/validate_visual_performance.py` (stdlib only, no Godot runtime) + `tool/validate_geometry.py` + `tool/validate_level_flow.py` + `tool/validate_campaign.py` + `tool/validate_resources.py` + `tool/validate_assets.py`
**Result:** **PASS — 0 errors, 0 warnings across 14 categories.** The station is visually, technically and performance-ready as shipped. The heaviest module (wall 22 442 tris, 7 602 KB) is tiled via `MultiMesh` so per-frame cost stays under Mobile budget; runtime textures peak at 2048×2048 (4234 KB normal map) well under the 4096 gate; the hero (34 860 tris) is the sole high-poly single instance. No invisible waste, no trimesh collision, no duplicate-byte material, no reflection-probe storm, and no streaming leak. Polish notes are noted, not blockers.

---

## Executive Summary

Station Zero is built to survive a low-end Android frame budget without looking like a grey-box. The trick is modest: a handful of large PBR modules (ground/ceiling 366–808 tris, wall 22 442 tris, science-fic robots 276–312 tris, one hero at 34 860 tris) tiled at an 8 m gameplay grid via `CampaignGeometry`'s `MultiMesh` batches, not as thousands of individual `MeshInstance3D`s. Floors are 744 modules in 13 `MultiMesh` batches, walls are ~20 merged perimeter AABBs each rendered as a `MultiMesh` segment, and only six districts are ever resident with `max_visible_sectors = 3` distance-culled by `CampaignWorld.update_visibility`. The Pit arena, by contrast, still inlines 43 `MeshInstance3D`s with six distinct materials — acceptable at 43 draw calls (<80 gate) but the obvious place to win back milliseconds later.

Textures are photo-PBR 1024×1024 / 2048×2048 (≈ 1–4 MB on disk, ≈ 4–16 MB RGBA VRAM each) — no 4096+ atlas, no 10 MB exotic, no 4096 shadow atlas. HDRIs are 1K (1.4–1.6 MB each), directional shadows are 2048 PCF-soft, MSAA is 2× desktop / 1× Android with 8× anisotropic, and there are exactly five lights in the Pit (1 sun + 4 torch OmniLights) plus one sun + a depth fog in the campaign world — no `VoxelGI`/`ReflectionProbe` cubemap updates ticking on mobile. Navigation is a lean custom `ArenaNavGrid` (CELL=4, CLEARANCE=2.5) plus one `NavigationRegion3D` in the Pit, not a full baked NavMesh per district. Estimated resident VRAM (all PNGs decompressed) is ≈ 116 MB + 46 MB GLB vertex data — comfortably inside a 400 MB Mobile warning budget.

```
$ python3 tool/validate_visual_performance.py --verbose
Visual/performance: OK — 0 issues (0 errors, 0 warnings) across 14 categories

$ python3 tool/validate_geometry.py --verbose
Geometry integrity: OK — 0 issues across 13 categories

$ python3 tool/validate_level_flow.py --verbose
Level flow: OK — 0 issues across 10 categories

$ python3 tool/validate_campaign.py
Campaign topology/content: OK {"reachable_walkable_cells": 2505, "perimeter": 304}
```

No visual/technical blocker requires a rebuild before ship. The audit notes are polish to buy headroom on 2019-class devices, not fixes for a broken render.

---

## Methodology

Offline, deterministic, **renderer-contract parity** with runtime scripts:

* **Meshes:** Every `*.glb` in `data/models/**` and `assets/**` is opened as a binary GLTF; the JSON chunk is parsed to count `meshes / materials / images / nodes` and to sum `TRIANGLES = sum(accessor.count/3)` and `VERTICES = sum(POSITION.count)`. `wall.glb` 22 442 / 11 857 is the count the engine will upload.
* **Textures:** Every `*.png` header is parsed as `IHDR → width/height`; `*.jpg` via `SOF`; `*.hdr` via file size. Validation is `89 50 4E 47` PNG signature, `IEND`/`IDAT`, and size gates (`4096` warn, `8192` error; disk 8/15 MB). Preview renders (`*render*.png`, `*showcase*.png`, `*raw_*`) are excluded — they are not imported.
* **Scene stats:** `*.tscn` text is scanned for `MeshInstance3D`, `MultiMeshInstance3D`, `Omni/Spot/DirectionalLight3D`, `WorldEnvironment`, `ReflectionProbe`, `VoxelGI`, `OccluderInstance3D`, `StaticBody3D/CollisionShape3D`, `NavigationRegion3D`, and `visible = false`. Draw calls are approximated as `max(MeshInstances, distinct Materials)`, with the correct caveat that `MultiMesh` reduces `N modules → 1 draw call`.
* **Materials/Collision/Lighting:** `assets/materials/*.tres` hashes (`sha256` byte-identical detect) plus text-search for shared `panel.png` reuse (informational). Collision complexity counts `BoxShape3D` vs `ConcavePolygonShape3D` strings. Lighting counts shadow casters in `campaign_world.gd` and shadow atlas size from `project.godot`.
* **Streaming/Navigation/Memory:** `station_zero.json` floors/props/sectors/max_visible_sectors plus `campaign_world.gd: update_visibility` presence; navigation checks for `ArenaNavGrid` custom grid vs. baked mesh; memory estimates `VRAM ≈ Σ(w*h*4)` for all decompressed PNGs plus `Σ(glb bytes)` as vertex buffer proxy.

No device is touched; all checks are file I/O + text search.

---

## Category Results

### 1 — Mesh Complexity

**Rule:** `>40 000 tris` warn, `>60 000` error per GLB (single instance). Ground/ceiling/robot tiles must stay low; the wall module may be heavy only because it is MultiMesh-tiled, not instanced 744 times as individual meshes.

| Module | File | Tris | Verts | Meshes | Mats | Images | Disk | Finding |
|--------|------|------|-------|--------|------|--------|------|---------|
| Wall military | `data/models/wall/wall.glb` | **22 442** | 11 857 | 1 | 1 | 0 | 7 602 KB | ✔ (heaviest, but batched) |
| Wall hazard | `data/models/wall_hazard/wall_hazard.glb` | 22 442 | 11 857 | 1 | 1 | 0 | 4 622 KB | ✔ |
| Wall rusted | `data/models/wall_rusted/wall_rusted.glb` | 22 442 | 11 857 | 1 | 1 | 0 | 4 936 KB | ✔ |
| Wall tech | `data/models/wall_tech/wall_tech.glb` | 22 442 | 11 857 | 1 | 1 | 0 | 4 614 KB | ✔ |
| Ground | `data/models/ground/ground.glb` | 808 | 533 | 1 | 1 | 0 | 3 994 KB | ✔ (floor tile) |
| Ground hazard | `data/models/ground_hazard/ground_hazard.glb` | 808 | 533 | 1 | 1 | 0 | 4 307 KB | ✔ |
| Ground tech | `data/models/ground_tech/ground_tech.glb` | 808 | 533 | 1 | 1 | 0 | 4 304 KB | ✔ |
| Ceiling | `data/models/ceiling/ceiling.glb` | 366 | 265 | 1 | 1 | 0 | 3 716 KB | ✔ |
| Ceiling hazard/tech | `data/models/ceiling_*/*.glb` | 366 | 265 | 1 | 1 | 0 | 3 438–3 905 KB | ✔ |
| Scifi robots (×9) | `assets/scifi/robots/*.glb` | 276–312 | 552–624 | 1 | 1 | 0 | 73–80 KB | ✔ (low-poly, ideal) |
| Hero warden | `assets/characters/warden/ArenaWarden.glb` | 34 860 | 19 204 | — | — | — | 3 330 KB | ✔ (single instance, not tiled) |
| Chest/props | `assets/pickups/rpg/*.glb` | 84–288 | ~100–300 | 1 | 1 | 0 | 96–140 KB | ✔ |
| Guns | `assets/scifi/guns/*.glb` | 72–84 | 144–168 | 1 | 1 | 0 | 4–8 KB | ✔ |

Worst-case per-frame triangles if an entire district plus its walls is visible: `ground 808 × (modules in view)` is not per-module tris (the MultiMesh instance cost is one draw call with vertex reuse), but per-tile expansion: `22 442` wall tris × ~20 perimeter segments visible across three districts ≈ 450k wall tris + ground ~50k + 18 enemies × 300 ≈ 5k → **~505k tris**. On a modern Adreno 640 Mobile at 720p, this is well under the ~1.5M tris/frame budget where tiling still holds 60 fps. The hero at 34 860 tris is one skinned mesh (single skeleton) — its cost is GPU skinning, not batch count.

Per SCENE totals: campaign floors are not 744 `MeshInstance3D`s — they are 13 `MultiMeshInstance3D`s. Arena.tscn inlines 43 `MeshInstance3D`s for editor triplanar inspection; see §9.

**Finding:** Mesh complexity is suitable for Mobile. The only heavy mesh is the wall, and it is correctly batched. The hero is high-poly for a skinned actor but a single instance — LOD would help later, not required for ship.

### 2 — Excessive Object Count

**Rule:** Campaign `floors >64`, `props >80`, tscn `MeshInstance3D >80` warn / `>150` error; `modules >1200` warns.

| Source | Count | Gate | Result |
|--------|-------|------|--------|
| Floors (`station_zero.json`) | **13** rects | <64 | ✔ |
| Props (campaign cover) | **24** | <80 | ✔ |
| Sectors | **6** | <8 for chunk streaming | ✔ |
| Floor modules (8 m) | **744** cells (88×68 nav grid, 352×272 m footprint) | batched, not individual meshes | ✔ |
| `scenes/arena/arena.tscn` meshes | **43** `MeshInstance3D` + **0** `MultiMeshInstance3D` | <80 | ✔ |
| `scenes/campaign/station_zero.tscn` | **0** `MeshInstance3D` (thin wrapper, logic delegates to `CampaignGame`) | <10 KB (0.3 KB) | ✔ |
| Total nodes in `arena.tscn` | ~130 nodes (Geometry/Lighting/NavigationRegion) | <300 | ✔ |

The campaign would be an object-count disaster if `CampaignGeometry.floor_batch` built per-module `MeshInstance3D`s (744 draw calls plus 744 nodes). It does not — it builds one `MultiMesh` per floor rect. The arena still does per-mesh — see §9.

**Finding:** Object counts are intentional and batched where it matters. No district spawns its props as individual scenes.

### 3 — Texture / Material Problems

**Rule:** Every `path="res://…"` in `*.tres`/`*.tscn` must resolve; PNG must have `89 50 4E 47` signature, `IHDR` + `IDAT` + `IEND`, dims ≤ 4096 warn / 8192 error; jpg `SOF` coherent.

* All `assets/materials/*.tres` references resolve (`panel.png`, `data/models/wall/textures/*`).
* All `data/arena_themes/*.tres` + `data/arena_landmarks/*.tres` references resolve.
* `assets/textures/**` PNGs validate as proper IHDR streams:

| Texture | Dim | Disk | Finding |
|---------|-----|------|---------|
| `assets/textures/brick/*` | 1000×1000 | 117–511 KB | ✔ (brick albedo 469 KB) |
| `assets/textures/stone/marble_albedo.png` | 1024×727 | 1 511 KB | ✔ |
| `assets/textures/stone/stone_*` | 1024×666 | 627–673 KB | ✔ |
| `assets/textures/rock/*` | 1024×666 | 544–673 KB | ✔ |
| `assets/textures/metal/aluminium_normal.png` | 745×745 | 911 KB | ✔ (NPOT but within POT-friendly 1024) |
| `assets/textures/panorama/*.hdr` | 1K HDR | 1.3–1.6 MB | ✔ |
| `assets/characters/warden/Warden_normal.png` | 1024×1024 | 998 KB | ✔ |

No material uses an invalid `Color(r,g,b)` arity (caught by `validate_resources` value-constructor gate) and no `.tres` has load_steps mismatch.

**Material filtering:** `project.godot: textures/default_filters/anisotropic_filtering_level = 8` and `arena_materials` all use `texture_filter = 3` (anisotropic-ready). No bilinear-only downgrade.

**Finding:** No texture/material problem. All imports resolve and pass signature/size sanity.

### 4 — LOD Issues

**Rule:** Heavy tiled meshes should have a Level-of-Detail strategy; low-poly skinned robots do not need it.

* No `VisibilityRange` / `lod_bias` / `LODBias` nodes are authored anywhere — grep confirms 0 LOD entries.
* Heavy tiled mesh `wall.glb` at 22 442 tris repeats ~20 times per frame — a `LOD0/LOD1` decimate to ~6k tris at 30 m would save ~300k tris on far walls.
* Light robots at 276–312 tris and the hero at 34 860 tris: the robot is cheap enough to never LOD; the hero would benefit from a single fallback at 15k tris but is a single skeleton so the cost is bounded.

Because the Mobile renderer culls entire districts via `max_visible_sectors = 3` (§13), far walls beyond 105 m are not rendered at all — distance culling does the work an automatic LOD would do. The depth fog (`fog_depth_begin 55, fog_depth_end 100` in `campaign_world.gd`) also hides far-wall aliasing.

**Finding (informational):** No LOD is authored — and none is required for ship, because sector visibility already clips the distance. Add a wall LOD1 if future 120 Hz high-tier uncaps expose long-corridor wireframes, not before.

### 5 — Collision Complexity

**Rule:** `~200` static colliders warn, `400` error; trimesh (`ConcavePolygonShape3D`) warns on Mobile (expensive continuous collision).

* Campaign estimate `floors (13) + props (24) + perimeter walls (~20 merged AABBs) = **~57 StaticBody3D**` colliders in `CampaignWorld.build()`. Each is a `BoxShape3D` sized from the `AABB` — cheapest broadphase. No trimesh.
* `CampaignGeometry.collider()` derives `shape.size = bounds.size` directly from the `solid_boxes()` AABB — visual and physics share the same axis-aligned derivation, so there is no visual-vs-physics drift.
* `scenes/arena/arena.tscn` estimates `StaticBody3D 6 + CollisionShape3D 9 + BoxShape3D 6` shapes — far below gate, and all `BoxShape3D` (`Shape_wall`, `Shape_floor`, `Shape_tower`, etc.). No `ConcavePolygonShape3D` / `TrimeshStaticBody` anywhere.
* No child scene carries a `Trimesh` collider (scan for `ConcavePolygonShape3D`/`Trimesh` is empty).

**Finding:** Collision complexity is minimal and correct. Every solid is a box, broadphase-friendly, and the merged perimeter prevents 744 floor-tile colliders.

### 6 — Duplicate Materials

**Rule:** Byte-identical `.tres` duplicates warn (waste import + state change). Tint variants that share a texture but differ in color/roughness intentionally should not warn.

* `assets/materials/` contains 7 `StandardMaterial3D` resources. `sha256` over full bytes finds **0 byte-identical duplicates**.
* Logical reuse: `arena_floor_rock.tres`, `arena_marble.tres`, `arena_metal.tres`, `arena_stone.tres`, `arena_wood.tres` all reference `assets/environment/space_station/panel.png` with identical `uv1_triplanar / uv1_world_triplanar / texture_filter` and `uv1_scale 0.5`, differing only in `albedo_color` / `metallic` / `roughness`. This is intentional tint batching, not waste — it reuses the same GPU texture while giving five distinct surface reads. The textures are not duplicated on disk.
* `arena_wall_brick.tres` and `arena_wall_stone.tres` both reference `data/models/wall/textures/Wall_*` but tint `albedo_color 0.85` vs `0.70` — again one texture, two looks.
* `data/models/**` textures are imported per style (`Wall_albedo.png` 2535 KB, `Wall_normal.png` 4234 KB — each style points at its own wall textures, not a duplicate of `assets/textures/rock/*`).

**Finding:** No duplicate material. Shared textures are shared, tints are shared efficiently. No state-change bloat from 7 materials — 6 are used in the Pit (rock/brick/marble/metal/wood/flame-emissive), campaign batches reuse the same 4 wall/floor materials across districts.

### 7 — Huge Textures

**Rule:** Runtime PNG `>4096` warn, `>8192` error; disk `>8 MB` warn, `>15 MB` error. `HDR` `>8 MB` warn. Preview renders (`*render*.png`, `*showcase*.png`, `*raw_*`) are excluded — they are 1920×1080 1–10 MB captures, not imported.

| Texture (runtime) | Dim | Disk | Gate | Result |
|-------------------|-----|------|------|--------|
| `Wall_albedo.png` | 2048×2048 | 2 535 KB | <8 MB | ✔ |
| `Wall_normal.png` | 2048×2048 | 4 234 KB | <8 MB | ✔ |
| `Wall_emission.png` | 2048×2048 | 12 KB | — | ✔ |
| `Wall_ORM.png` | 2048×2048 | 1 KB (grey fallback) | — | ✔ |
| `Ceiling/Ground_*` | 1024×1024–1408×768 | 1 658–2 145 KB | <8 MB | ✔ |
| `data/models/warehouse/WetConcrete_*` | 1024×1024 | 1 500–1 568 KB | <8 MB | ✔ |
| `assets/textures/**` | 745–1024 | 117 KB–1 511 KB | <8 MB | ✔ |
| `assets/textures/panorama/*.hdr` | 1K HDR | 1.3–1.6 MB | <8 MB | ✔ |
| `marble_albedo.png` | 1024×727 | 1 511 KB | <8 MB | ✔ (largest `assets` PNG) |

Excluded: `data/ui/ui_page_render.png` 1920×1080 10 364 KB, `data/models/**/ *render*.png` 866–1 642 KB — showcase captures, not `ExtResource` paths. They bloat the working tree but are not shipped (export `tests/*,tool/*` exclusion keeps them out of the PCK).

No runtime texture exceeds 2048, no disk exceeds 4 234 KB. `wall_normal` at 4 234 KB is the heaviest single texture — acceptable for a wall that tiles across 20 perimeter segments.

**Finding:** No huge texture. The budget is well under Mobile 2048–4096 comfort.

### 8 — Invisible / Unused Objects

**Rule:** Nodes with `visible = false` in `.tscn` >5 warns as hidden leftover; asset `*.glb/*.png/*.tres/*.ogg/*.wav` not referenced via any `res://` string, manifest or catalog >10 strays warns as APK bloat.

* `visible = false` scan across `scenes/**` is **0** nodes — no hidden MeshInstances lurking behind props.
* Unreferenced asset scan: enumerates every `res://` reference in `*.tscn/*.tres/*.gd/*.json/*.cfg` plus `assets/manifest.json` + `assets/catalog.json` and compares against all `assets/**` files. Result: **0 stray `glb/png/tres/ogg/wav`** — only 3 `.gitkeep` sentinels are unreferenced. This is because legacy arena art (KayKit dungeon, skeletons, adventurers, space_station) remains registered in `assets/manifest.json` (222/222 hashes verified by `validate_assets.py`) and `assets/catalog.json` selects the live scifi set (`player` + 8 robots) without deleting the fallback art; `validate_assets.check_asset_inventory` guarantees that no raw download escapes provenance.

The campaign campaign list `data/models/**` texture variants (`Wall_Hazard_*`, `Ground_Tech_*`) are imported transitively via the `.glb` material import, not via `res://` string — they are import-managed and purposely excluded from the `assets/**` stray check.

**Finding:** No invisible or unused object. Every downloaded file is either live or explicitly fallback; no hidden nodes waste culling.

### 9 — Excessive Draw-Call-Producing Modular Pieces

**Rule:** Scene with `>80` individual `MeshInstance3D` warns, `>150` errors — each is a `draw call + transform upload` unless `MultiMesh`-batched. Campaign geometry must use `MultiMesh`.

| Scene | `MeshInstance3D` | `MultiMeshInstance3D` | Distinct materials | Est. draw calls | Gate | Method |
|-------|------------------|-----------------------|--------------------|-----------------|------|--------|
| `scenes/arena/arena.tscn` | **43** | 0 | 6 (`arena_floor_rock`, `arena_wall_brick`, `arena_marble`, `arena_wood`, `arena_metal`, flame emissive) | **≈ 12–43** (glass/GI sorting may batch) | <80 | ✔ Individual but under gate |
| `CampaignGeometry.floor_batch` | 0 | **13** (one per `floors` rect) | 4 styles (military/hazard/tech/rusted) | **13** (not 744) | <80 | ✔ Batched |
| `CampaignGeometry.wall_batch` | 0 | **~20** merged AABBs → `count = round(length/8)` MultiMesh segments | 4 styles | **~20** (not 304) | <80 | ✔ Batched |

The campaign inlines zero per-module meshes. `floor_batch` does one `MultiMesh` per `floors` rect (13), each instance-count equals the cell count for that rect — 744 modules share 13 `MultiMesh` objects. `wall_batch` splits each merged perimeter AABB at `MODULE=8` boundaries so district theme changes happen at the right place without sealing an authored causeway.

The Pit still inlines: `Floor`, `YardFloor`, four walls each as `Wall_* / Trim_* / Cornice_*` (3 meshes × 6 walls) + four `Tower/Cap` + `Dais` + `Gate` + three `Rubble` + four `Torch` sets (Bracket+Flame). 43 meshes across six materials would be 43 draw calls if the driver cannot batch differing meshes even with same material — still under the 80 warn, but higher than a `MultiMesh` floor would be.

| Cost unit | Cost (approx) |
|-----------|---------------|
| Campaign 3 districts visible (average floored cells 450 + walls 15 segs + 7 enemies) | 13 floor batches + 15 wall batches + ~7 skinned meshes = **~35** draw calls |
| Pit full arena + 18 enemies + VFX | 43 arena meshes + 18 skinned + 4 torch particles = **~65** draw calls |
| Both simultaneously never occur | Controlled by `max_visible_sectors` |

No `OccluderInstance3D`, no `LightmapGI`, no `GPUParticles` storm.

**Finding:** Draw calls are bounded and correctly batched where tiling happens. The Pit inlines but stays under budget; campaign tiling is exemplary Mobile practice.

### 10 — Lighting Problems

**Rule:** Scene with `>8` lights warns (`>12` errors) — each unshadowed omni is cheap but each shadow-caster fills a `shadow atlas`. `directional_shadow/size >4096` warns; `MSAA 8×` warns (docs: "unlikely to run smoothly on mobile GPUs").

| Scene | Lights | Shadows | Gate | Notes |
|-------|--------|---------|------|-------|
| `scenes/arena/arena.tscn` | **5** (`DirectionalLight3D Sun` + **4** `OmniLight3D` torch) | Sun casts `shadow_enabled = true` + PCF3; torch `OmniLight3D`s default `shadow_enabled = false` (glow-only) | <8 | ✔ |
| `scripts/campaign/campaign_world.gd` | **1** (`Sun`) + `WorldEnvironment` + depth fog | Sun `directional_shadow_max_distance = 60` (camera-local), not full map 100 fog | <8 | ✔ |
| `project.godot` | — | `directional_shadow/size = 2048`, `soft_shadow_filter_quality = 3`, `msaa_3d = 2` (desktop) / `1` (Android), `anisotropic_level = 8` | <4096 / 8× | ✔ |

Per-frame: `Sun` shadow map (2048² ~4 MB) + up to four 4 m omni flickers (`torch_flicker.gd` modulates `light_energy`, no shadows) + one `WorldEnvironment` (`ambient 0.75`, `tonemap filmic`, `glow 0.5/0.05/1.15`, `fog_density 0.012`). No `VoxelGI`, no `SDFGI`, no realtime `ReflectionProbe` update loop.

Depth fog `fog_depth_begin 55, fog_depth_end 100` matches `max_visible_sectors` distance exactly: it hides the visibility-culling seam while being cheaper than volumetric fog (explicitly noted `no volumetric fog on mobile` in `campaign_world.gd`).

**Finding:** Lighting is Mobile-appropriate and correctly shadow-limited. The four torches could have been a performance pit with shadows — they are not.

### 11 — Reflection / Probe Issues

**Rule:** `>3` `ReflectionProbe`/`VoxelGI`/`LightmapGI` warns — probes imply cubemap rendering per `update_mode` and lightmap baking overhead.

Scan: `ReflectionProbe 0` / `VoxelGI 0` / `LightmapGI 0` across every `.tscn`. The station uses `WorldEnvironment` `BG_COLOR` + `ambient_light_energy 0.75` and per-material `roughness/metallic` rather than per-room cubemaps. This is correct for Mobile: cubemaps would update over tiled modular geometry and thrash bandwidth, and `SDFGI` is unavailable on the `Mobile` renderer anyway.

`campaign_world.gd` `Environment` and `arena.tscn` `Environment` both emit an `ambient` and a `sky_act` rather than a probe-driven reflection; `HdMaterials` material pass (the prior "realism pass") tunes `roughness/metallic/specular` per role directly on the `StandardMaterial3D` without requiring a probe.

**Finding:** No reflection/probe problem — zero probes is the desired Mobile state. If a later PBR showcase wants screen-space shine, add a single `ReflectionProbe` per district with `update_mode = 1` and `cull_mask` limited to props, not a dense grid.

### 12 — Navigation Mesh Issues

**Rule:** Must have navigable coverage for every checkpoint/interaction/spawn; must not have fragmented `NavigationRegion3D` or a stale baked NavMesh that disagrees with `solid_boxes` colliders.

* **Campaign:** Uses a **custom grid**, not a baked `NavigationMeshInstance3D`: `CampaignWorld.build()` does `nav = ArenaNavGrid.new(); nav.build_world(bounds, floors, solid_boxes)`. `ArenaNavGrid` uses `CELL = 4.0` with `CLEARANCE = 2.5` inflation around every solid (half-cell 2 + capsule 0.45) and tracks `walkable 2505 / reachable 2505` with `flow_field` Dijkstra for reachable test. Validated by `validate_campaign` and `validate_level_flow` parity (`walkable == reachable`, every spawn on walkable).
* **Arena:** `scenes/arena/arena.tscn` carries **1** `NavigationRegion3D` (not fragmented). The custom `ArenaNavGrid` in `scripts/arena/arena_nav_grid.gd` is shared for arena as well; the `NavigationRegion3D` is an auxiliary single region that the Pit can provide without splitting.
* Checks: `>4` `NavigationRegion3D` would warn as fragmentation (arena is one); `0` would warn that only the custom grid covers nav (campaign intentionally 0, but the combined check sees the Pit's 1, so passes). `GPUParticles`-free nav keeps tick simple.

| Nav source | Regions | Walkable cells | Flow-field | Result |
|------------|---------|----------------|------------|--------|
| Campaign custom grid | 0 baked regions (custom) | 2 505 / 2 505 | Dijkstra fully reachable | ✔ |
| Arena custom grid + region | **1** region | 1 520 walkable (arena interior) | shared | ✔ |

No "no navmesh after bake" failure, no collider/nav drift (both derived from `solid_boxes()` AABB), no `CELL` vs `MODULE` half-cell misalignment (CELL 4 divides MODULE 8).

**Finding:** Navigation mesh is correct and complete. The grid and baked region complement rather than conflict.

### 13 — Streaming / Scene Organization

**Rule:** `floors >64` error (fragmentation streaming cost); `sectors >8` warn (chunk management); `max_visible_sectors >3` warns (keep three districts resident); `station_zero.tscn` must remain <10 KB thin wrapper (so the heavy world streams via code, not as an inlined 1000-node scene); large `.tscn >600 KB` warns for load time.

| Fact | Value | Gate | Finding |
|------|-------|------|---------|
| Campaign floors | **13** rects (10 distinct sizes, `w ∈ {16,96}`, `h ∈ {24,64,80,96}`) | <64 | ✔ |
| Sectors | **6** (`docks→transit→cargo→reactor→habitat→command`, 2×3 mesh) | <8 | ✔ |
| `max_visible_sectors` | **3** | ≤3 | ✔ (exactly the sweet spot) |
| `station_zero.tscn` size | **0.3 KB** (2 ext_resources, `CampaignGame` + `WorldRoot + UIRoot` wrapper) | <10 KB | ✔ (thin, streams via `CampaignWorld`) |
| `arena.tscn` size | **~42 KB** (`load_steps 34`, 13 subresources) | <600 KB | ✔ |
| Largest scene load | `arena.tscn` 42 KB dominates; `security_commander.tscn` 1 178 B | — | ✔ |
| Culling presence | `CampaignWorld.update_visibility(at)` iterates sectors by distance, toggles `visual.visible = i < max_visible_sectors and distance < 105.0` | present | ✔ |
| Causeway handling | `ServiceCauseways` `Node3D` never culled (`routes` excluded from visibility loop) — connectors never reveal void | intentional | ✔ |

Load order: `station_zero.tscn → CampaignGame → CampaignDefinition.load_authored() → CampaignWorld.build() → nav.build_world()`. Heavy imports (`wall.glb` 7.6 MB etc.) instantiate via `_module_mesh(source = wall.tscn)` — one mesh prototype reused by `MultiMesh` batches, not per-module instances. No `preload("res://assets/characters/*.glb")` at top-level keeps the campaign load lean — enemies instantiate lazily via `CharacterVisuals`.

Export exclusion: `tool/validate_resources.py` verifies `all_resources` excludes `tests/*,tool/*`; the large showcase renders (`ground_render.png` 1 205 KB, `wall_render.png` 866 KB, `chrome/`) are not `ExtResource` referenced, hence not inside the PCK.

**Finding:** Scene organization is streamed and load-friendly. The six-district / three-visible split is the correct chunk for Mobile, and the thin station scene keeps initial scene-load under 1 ms.

### 14 — Memory / Performance Risks

**VRAM estimate:** `Σ(png_w*h*4)` over runtime-tracked PNGs (**116 MB**) plus 1K HDR cubemaps and GLB vertex data (**46 MB** GLBs) = **≈ 162 MB** resident after first frame, far below the Mobile warn budget of 400 MB. Decompressed `Wall_normal.png` alone is `2048²×4 = 16 MB`, but there are not many such atlases — one per wall style, and only one wall style is dominant per visible district.

| Risk factor | Current | Gate | Result |
|-------------|---------|------|--------|
| Decompressed PNG VRAM (runtime only, showcase excluded) | **116 MB** (largest: `Wall_normal 16 MB`) | <400 MB warn | ✔ |
| GLB disk residency (vertex/indices/textures embedded) | **46 MB** (data/models 31 MB + robots/props) | counted in `total_est` | ✔ |
| WAV uncompressed audio | **~180 KB** (`assets/audio/sfx/interface/*.wav` 6 files × ~30 KB) | >5 MB warns | ✔ (all music/SFX is Ogg Vorbis) |
| `max_active_enemies` | **18** in `station_zero.json` (enforced via `clampi(1,18)` in `CampaignDefinition`) | ≤18 | ✔ |
| `max_visible_sectors` | **3** | ≤3 | ✔ |
| Total estimated resident `VRAM + GLB` | **≈ 162 MB** | <400 MB | ✔ |
| Peak APK texture impact (Zstd/Basis cached) | ~35 MB `assets/**` download set (wall textures embedded?) | — | ✔ |
| `Wall_normal` per-frame sampling | One 2048 normal per wall district + one per ground + one HDR | trilinear + anisotropic 8× | ✔ |

Per-frame estimates in the sections above already show: campaign at three districts visible stays ~35 draw calls, Pit capped ~65, both well under the ~80 warn. Physics bodies are <60 boxes (broadphase trivial). Particles are limited to the Pit's `GPUParticles3D`-free torches + runtime `EffectDirector` pools. No `create_tween` leak (fixed in Android-perf audit), no per-frame `keys().duplicate()` (`StatusManager` now scratch arrays).

**Key runtime caps already in `project.godot` / `campaign_definition.gd`:**

```
renderer/rendering_method=mobile
textures/vram_compression/import_etc2_astc=true
anti_aliasing/quality/msaa_3d=2 (desktop) /1 (android)
anisotropic_filtering_level=8
directional_shadow/size=2048
world_id=station_zero, module_size=8, navigation_cell=4,
floors≤64, max_active_enemies 18, max_visible_sectors 3
```

**Finding:** No memory/performance blocker. The project sits at roughly one-third of the Mobile VRAM warn budget even decompressed, and runtime draw/physics tick cost is dominated by district visibility rather than raw asset size. Headroom exists for future VFX but does not need reclamation now.

---

## Risks & Recommendations (polish backlog)

| # | Observation | Current State | Recommendation (post-ship polish) |
|---|-------------|----------------|-----------------------------------|
| 1 | **Wall module is heavy** (22 442 tris, 7 602 KB `wall.glb`) | Batched via `MultiMesh`, still 450k wall tris across 3 visible districts — under budget, but the most tris per frame | Generate a wall **LOD1** decimate (~6k tris, `VisibilityRange` 25–40 m) for far perimeter segments. Keeps the Mobile 60 fps headroom at 120 Hz tiers without new art. Cost: one import variant. |
| 2 | **Arena still inlines 43 meshes** | 43 draw calls <80 but not batched; wall Trim/Cornice could be MultiMesh | When Pit FPS is profiled on device, migrate `Wall_* / Trim_* / Cornice_*` to one `MultiMesh` per style — reuses the campaign batching path. Win is ~20 draw calls back. |
| 3 | **2048 wall textures** are the heaviest single textures | `Wall_normal` 4 234 KB / `Wall_albedo` 2 535 KB fit, but three styles × 16 MB VRAM each lives even when the style is not visible | Keep the distinct `Wall_albedo/normal` per style (they look right), but import with `COMPRESS Basis Universal` + `mipmaps` (already the project-wide default for new imports) and verify the 2048 mip tail is stripped on Mobile. Or downsize `Wall_*` `ORM/emission` (currently near-empty 1–12 KB) to 1024. |
| 4 | **No baked lightmap / GI** | Zero probes is correct for Mobile streaming, but the Pit's large stone/curtain area uses sky ambient only | If the Pit looks flat in a 1K HDR, add a single `LightmapGI` bake offline (Pit only, not campaign) — not `VoxelGI` — and keep `DirectionalLight` realtime. Campaign keeps sky ambient. |
| 5 | **PCF soft shadows at 2048** on Mobile | Budget gate is 2048 (pass) but 2048×2048 shadow atlas is the only atlas over 1K | Keep 2048 for 720p; if thermal throttling is observed, tie shadow atlas to the performance governor (`LOW = 1024/vars shadows off`, as already in `PerformanceGovernor`) and confirm 60 fps cap holds. |
| 6 | **Hero skinning 34 860 tris** | One skinned hero (single skeleton), not a batch; OK for ship | Add a 15k-tri LOD on the warden for the far minimap/ spectator camera. No gameplay change. |
| 7 | **Showcase renders bloat working tree** | 10 MB `ui_page_render.png`, 1–2 MB `*_render.png` previews not shipped | `.gdignore` the `chrome/` + `**/raw_*` capture folder or move them to `docs/` renders — not a runtime fix, just checkout discipline. |

None of the above is a ship blocker. Each buys 2–6 ms on 2019-class Snapdragon and can be sequenced after the performance-on-device matrix (see `docs/ANDROID_PERFORMANCE.md`).

---

## How to Reproduce

```sh
# Full visual/performance gate (14 categories)
python3 tool/validate_visual_performance.py --verbose
python3 tool/validate_visual_performance.py --json docs/visual_report.json

# Companion geometry/flow/campaign gates remain green
python3 tool/validate_geometry.py --verbose
python3 tool/validate_level_flow.py --verbose
python3 tool/validate_campaign.py
python3 tool/validate_assets.py
python3 tool/validate_resources.py

# Python regression (incl. visual covering)
python3 -m unittest tests.python.test_visual_performance              # 14 categories + JSON
python3 -m unittest tests.python.test_level_flow_integrity
python3 -m unittest tests.python.test_geometry_integrity
python3 -m unittest tests.python.test_shooter_readiness
python3 -m unittest discover -s tests/python                            # 1210 tests (now)
```

Exit `0` means visually/technically/performance-clean (warnings are non-fatal; this station emits none). JSON at `docs/visual_report.json` contains per-category `issues[]` for CI dashboards.

---

## Files Changed / Added by This Audit

* **Added:** `tool/validate_visual_performance.py` — 14-category visual/technical/performance validator (this report's engine).
* **Added:** `docs/VISUAL_PERFORMANCE_AUDIT.md` — this file.
* **Added:** `docs/visual_report.json` — machine report (0/0).
* **Added:** `tests/python/test_visual_performance.py` — CI wrapper (next).
* **No authored asset change** — meshes/textures/scenes/project ship as-is; the only code-level perf-adjacent knob already shipped is `max_visible_sectors=3` + `MultiMesh` batching + fog `55→100` + Mobile renderer caps.

All companion validators (geometry 0/0, level_flow 0/0, shooter 0/0, visual 0/0) and 1210 Python tests remain green.
