# ART_STYLE.md — Visual style guide

A cohesive, **stylized medium-detail** look: colourful but not childish, readable
silhouettes, clean geometry, good contrast, attractive on mobile, and lightweight.

## Core principles

1. **Readability first.** Player, enemies, hazards, pickups and arena props must be
   distinguishable at a glance and against the ground.
2. **Cohesion.** All assets share one palette, scale, lighting and material language.
   Do not mix visually incompatible packs.
3. **Measured budgets, not ultra-low-poly at all costs.** Readable bevels, shaped
   silhouettes and roughly 1K surface detail are welcome. Use shared materials,
   texture compression and few dynamic lights; measure full-wave performance.

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

## UI system rules

- **One skin.** All colours, fonts (Rajdhani Regular/Bold), corner radii and
  button states come from `UiTheme`. Do not hand-tint a control that the theme
  already covers.
- **One spacing scale.** `UiTheme.SPACE_S` (8) / `SPACE_M` (16) / `SPACE_L` (24).
  Margins, separations and grid gaps are multiples of it.
- **One touch floor.** `UiTheme.TOUCH_MIN` = 88 logical px (clears Android's 48dp
  accessibility minimum at the project's 1280x720 design size). `UiFactory`
  enforces it for buttons and checks; custom-drawn touch widgets read
  `UiLayout.MIN_TOUCH`.
- **One overlay solver.** Gameplay-overlay geometry (HUD, minimap, boss frame,
  banner, toast, stick, action cluster, skill bar) is solved once per resize by
  `UiLayout.compute()` from the safe-area size and the text scale — never from
  hardcoded offsets. This is what keeps every Android aspect ratio, safe-area
  cutout and 200% text setting free of overlaps.
- **Readability over decoration.** HUD text sits on translucent scrims or carries
  an outline, and the overlay must never cover the player or the arena centre.

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

## Downloaded art families (partially integrated)

The reviewed kit in `assets/` uses **KayKit Adventurers + Skeletons + Dungeon
Remastered** for matching characters, weapons, props and texture language, with
Kenney particle/UI assets and Rajdhani fonts. See `docs/ASSET_CATALOG.md` for exact
files, animation names and per-role mappings. Detailed stone surfaces, pickup models (Heart/Crystal/Star), Quaternius creature/equipment additions (Rat/Spider/Demon/BlueDemon + 9 weapons via PlayerEquipment socket `handslot.r/l`), and all 8 character/9 enemy models (Knight + Skeletons + creatures via CharacterVisuals fitted bounds + EnemyAnimator/PlayerAnimation) are now integrated. Combat/camera behaviour preserved. See `ASSET_AUDIT.md` / `ASSET_CATALOG.md` for exact mappings; remaining art gap is per-arena bespoke meshes (themes+decorator suffice) and boss-music procedural fallback.

Keep the original textured materials when applying the role palette; tint accents
or duplicate materials rather than flattening every surface to a single colour.
The character rigs have multiple mesh parts and 1024px gradient atlases: share
materials/textures where possible, select appropriate import LODs/texture sizes,
and profile full enemy waves on the target phone. "Low poly" is not an FPS guarantee.

## Future content rules

New enemies, arenas, cosmetics, pickups and UI must follow the palette + scale above,
register their `.tres` under `res://data/`, and log any third-party asset in
`THIRD_PARTY_ASSETS.md` / `AUDIO_MANIFEST.md` first.
