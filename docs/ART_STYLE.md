# ART_STYLE.md — Visual style guide

A cohesive, **stylized low-poly** look: colourful but not childish, readable
silhouettes, clean geometry, good contrast, attractive on mobile, and lightweight.

## Core principles

1. **Readability first.** Player, enemies, hazards, pickups and arena props must be
   distinguishable at a glance and against the ground.
2. **Cohesion.** All assets share one palette, scale, lighting and material language.
   Do not mix visually incompatible packs.
3. **Lightweight.** Low polygon counts, minimal shaders, small textures (ETC2/ASTC),
   few dynamic lights/shadows.

## Palette

| Role | Colour | Usage |
|---|---|---|
| Player | cool blue `#3d8ff2` | the character; never reuse for enemies |
| Basic enemy | muted green `#6a9b5a` | silhouette 1 |
| Fast enemy | orange/amber `#e0a13a` | thinner, faster shape |
| Heavy enemy | deep red/maroon `#a33c3c` | bulky silhouette |
| Hazard / telegraph | warning red/orange | attack windups, spawn telegraphs |
| Pickup / bonus | gold `#ffd25e` | currency/upgrade pickups |
| Arena ground | mid neutral `#6c856b` | low saturation to contrast actors |
| Environment | desaturated warm/cool props | rocks, walls, decoration |
| UI panel | translucent dark `#14181f` | consistent panels/overlays |
| UI accent | `#7fc7ff` / `#ff8f5e` | CTAs and highlights |

Use high-contrast variant (settings toggle) for accessibility.

## Scale & proportion

- Arena floor ~26 × 26 m; walls ~3 m high.
- Humanoids ~1.8–2 m tall. Keep actors in a similar XZ footprint (capsule ~0.45 m r).
- Camera sits behind/above player (see `data/cameras/default.tres`).

## Lighting

- One directional sun (soft, warm) + sky/ambient from the `Environment` node.
- Minimal dynamic lights; baked/cheap lighting preferred. Shadows only where cheap.

## Enemy readability rules

- Distinct **silhouette** (size/shape) per archetype — never only a colour swap.
- Distinct **colour** and optional emissive accent.
- Clear **attack telegraph** (pose/colour/flash before a hit).

## Future content rules

New enemies, arenas, cosmetics, pickups and UI must follow the palette + scale above,
register their `.tres` under `res://data/`, and log any third-party asset in
`THIRD_PARTY_ASSETS.md` / `AUDIO_MANIFEST.md` first.
