# ART_STYLE.md — Visual style guide

A **grounded PBR armored hero + photo-PBR arena**, with the existing stylized enemy
roster retained for now. Adult hero proportions, readable blue cloth accents and
physically distinct steel/leather/mail replace the oversized-head KayKit hero.
This is not yet an entirely photoreal cast. Keep silhouettes readable, contrast
strong, shared material budgets bounded and mobile performance measured.

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
| UI panel | ember-black `#140c08` over the painted coliseum | leather / bronze plates |
| UI accent | gold `#e8b44a` / copper `#e08a45` | CTAs, ranks, energy |

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

- One directional sun (soft, warm) + a real **HDRI panorama** sky/IBL per arena
  (`PanoramaSkyMaterial`; procedural fallback if the `.hdr` is unimported).
- A handful of flickering torch sconces (4 omni lights, no shadows on them) plus
  the landmark light — never more than ~6 dynamic lights.
- 2× MSAA, 8× anisotropic filtering, high-quality PCF shadows, glow on emissives
  and exposure/contrast are the standard post set; SSAO/SSR stay off (mobile).

## Enemy readability rules

- Distinct **silhouette** (size/shape) per archetype — never only a colour swap.
- Distinct **colour** and optional emissive accent.
- Clear **attack telegraph** (pose/colour/flash before a hit).

## Downloaded art families (HD realism pass)

The reviewed kit in `assets/` uses **KayKit Adventurers + Skeletons + Dungeon
Remastered** for characters, weapons and props, **Quaternius** creatures/equipment,
**photo PBR textures** (rock, brick, marble, wood, aluminium — Godot Material
Testers) for the arena shell, and **Poly Haven CC0 HDRIs** (via the pinned
three.js mirror) for real skies, with Kenney particle/UI assets and Rajdhani fonts.
See `docs/ASSET_CATALOG.md` for exact files and per-role mappings; `ASSET_AUDIT.md`
explains why the rig inventory was kept (its combat clip coverage) while the
presentation (arena, sky, lighting, post, per-actor material tuning via
`HdMaterials`) changed. The subsequent **Arena Warden** replaces the hero mesh
and bakes all 76 motions onto a proportional 23-bone rig; see
`HERO_FIDELITY.md`. The new hero/gladius share base, normal and ORM atlases.
Never clamp their unit metallic/roughness factors to the palette-kit role values
or add a whole-body breathing tween to the baked grounded idle.

Keep the original textured materials when applying the role palette; tint accents
or duplicate materials rather than flattening every surface to a single colour.
The character rigs have multiple mesh parts and 1024px gradient atlases: share
materials/textures where possible, select appropriate import LODs/texture sizes,
and profile full enemy waves on the target phone. "Low poly" is not an FPS
guarantee — the HD shell adds roughly 10.6 MiB of checked-in photo textures and
four omni lights, so keep an eye on device frame time.

## Future content rules

New enemies, arenas, cosmetics, pickups and UI must follow the palette + scale above,
register their `.tres` under `res://data/`, and log any third-party asset in
`THIRD_PARTY_ASSETS.md` / `AUDIO_MANIFEST.md` first.
