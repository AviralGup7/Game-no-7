# Skill 02: Textures, Color Palettes & Scene Building Directory

This guide outlines where all visual textures, color grading profiles, materials, and 3D modular assets live across the repository for future scene building and visual consistency.

---

## 1. Arena Color Profiles & Theme Presets

The game features three primary atmospheric themes defined in `data/arena_themes/`:

| Theme ID | Display Name | Primary Color Palette | Key Lighting / Ambient | Fog & Glow Settings |
| :--- | :--- | :--- | :--- | :--- |
| `default_arena.tres` | **Orbital Foundry** | Dark Gunmetal Steel, Cyan LED (`#38bdf8`), Gold (`#d1ad73`) | Sun: `(1.0, 0.92, 0.78)`<br>Ambient: `(0.70, 0.73, 0.80)` | Fog: `0.011`, Glow: `0.55`, Bloom: `0.05` |
| `ember_crucible.tres` | **Reactor Core** | Rust/Charred Carbon, Caution Amber/Orange (`#fb923c`), Red (`#ef4444`) | Sun: `(1.0, 0.50, 0.20)`<br>Ambient: `(0.85, 0.45, 0.28)` | Fog: `0.020`, Glow: `0.55`, Bloom: `0.05` |
| `frost_hollow.tres` | **Cryo Sector** | White Titanium, Cobalt/Ice Blue (`#60a5fa`), Neon Indigo (`#1e3a8a`) | Sun: `(0.70, 0.80, 1.00)`<br>Ambient: `(0.68, 0.80, 1.00)` | Fog: `0.017`, Glow: `0.55`, Bloom: `0.05` |

---

## 2. Directory Map of Textures & PBR Maps

All environment textures and PBR maps are standard 8-bit PNG images formatted for mobile-ready PBR (Albedo, Normal, ORM, Emission):

### A. Modular 3D Wall Variants
- **Standard Military (Sector 07)**: `data/models/wall/textures/`
  - `Wall_albedo.png`, `Wall_normal.png`, `Wall_ORM.png`, `Wall_emission.png`
- **Industrial Reactor Hazard**: `data/models/wall_hazard/textures/`
  - `Wall_Hazard_albedo.png`, `Wall_Hazard_normal.png`, `Wall_Hazard_ORM.png`, `Wall_Hazard_emission.png`
- **Quantum Tech Lab**: `data/models/wall_tech/textures/`
  - `Wall_Tech_albedo.png`, `Wall_Tech_normal.png`, `Wall_Tech_ORM.png`, `Wall_Tech_emission.png`
- **Derelict Wasteland (Rusted)**: `data/models/wall_rusted/textures/`
  - `Wall_Rusted_albedo.png`, `Wall_Rusted_normal.png`, `Wall_Rusted_ORM.png`, `Wall_Rusted_emission.png`

### B. Modular 3D Ground & Floor Tiles
- **Military Diamond Tread Ground**: `data/models/ground/textures/`
  - `Ground_albedo.png`, `Ground_normal.png`, `Ground_ORM.png`, `Ground_emission.png`
- **Industrial Hazard Grate Ground**: `data/models/ground_hazard/textures/`
  - `Ground_Hazard_albedo.png`, `Ground_Hazard_normal.png`, `Ground_Hazard_ORM.png`, `Ground_Hazard_emission.png`
- **Quantum Hex Power Grid Ground**: `data/models/ground_tech/textures/`
  - `Ground_Tech_albedo.png`, `Ground_Tech_normal.png`, `Ground_Tech_ORM.png`, `Ground_Tech_emission.png`

### C. Modular 3D Ceiling / Top Tiles
- **Military Hex Luminaire Ceiling**: `data/models/ceiling/textures/`
  - `Ceiling_albedo.png`, `Ceiling_normal.png`, `Ceiling_ORM.png`, `Ceiling_emission.png`
- **Industrial Hazard Cable Truss Ceiling**: `data/models/ceiling_hazard/textures/`
  - `Ceiling_Hazard_albedo.png`, `Ceiling_Hazard_normal.png`, `Ceiling_Hazard_ORM.png`, `Ceiling_Hazard_emission.png`
- **Quantum Tech Linear Luminaire Ceiling**: `data/models/ceiling_tech/textures/`
  - `Ceiling_Tech_albedo.png`, `Ceiling_Tech_normal.png`, `Ceiling_Tech_ORM.png`, `Ceiling_Tech_emission.png`

### D. Shared Base Materials & Decals
- **Space Station Modular Decals**: `assets/environment/space_station/`
- **Global PBR Materials (`.tres`)**: `assets/materials/`
  - `arena_wall_brick.tres` (Sci-Fi Wall PBR mapped to `Wall_albedo.png`)
  - `arena_wall_stone.tres` (Dark Wall PBR mapped to `Wall_albedo.png`)
  - `arena_floor_rock.tres`, `arena_metal.tres`, `arena_marble.tres`
- **VFX Particle Textures**: `assets/particles/` (smoke, sparks, flares, light blooms)

---

## 3. Assembling Modular Environments in Godot Scenes

All modular units are dimensioned on a 1.0m grid:
- **Walls (`scenes/environment/wall*.tscn`)**: 1.00m Wide × 0.27m High × 0.05m Deep (Scale by integer multiples or tile along perimeter).
- **Ground Tiles (`scenes/environment/ground*.tscn`)**: 1.00m Wide × 1.00m Long × 0.06m Height (Center offset `y = -0.03m`).
- **Ceiling Tiles (`scenes/environment/ceiling*.tscn`)**: 1.00m Wide × 1.00m Long × 0.08m Height (Placed at `y = 3.0m` overhead).

All environment scene instances contain matching `StaticBody3D` and `CollisionShape3D` nodes on Collision Layer 1 (World Geometry).
