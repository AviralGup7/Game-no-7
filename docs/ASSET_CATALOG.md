# Last Stand: Arena — asset catalogue

Reviewed **10 September 2026** · Godot 4.4.1 · 3D third-person · Android

**256 checksum-locked files, 49.80 MiB: 94 models, 87 PNGs, 4 JPGs, 3 HDRIs,
34 audio clips, 2 fonts, 14 binary mesh dependencies and 18 licence/credit notices.**
In addition, the project-authored Warden bundle has **5 derived files / 4.93 MiB**:
2 GLBs and 3 shared PNG maps (now **96 models** in the combined inventory).
Its independent recipe/input/output hash lock is
`assets/characters/warden/build_report.json`; upstream downloads stay untouched.

See [the audit](ASSET_AUDIT.md) for additions, online comparisons and limitations.
The machine-readable role map is [`assets/catalog.json`](../assets/catalog.json);
the immutable source/download lock is [`assets/manifest.json`](../assets/manifest.json).

## Integration status — important

- **Hero fidelity follow-up:** new Warden body/rig + gladius, complete 76-clip
  retarget, 23 deform bones, one opaque body surface and shared 1K PBR atlas.
  `HeroRigContract` rejects incomplete imports before hiding the fallback;
  the hero's authored material response is preserved rather than clamped to
  palette-kit values. See [HERO_FIDELITY.md](HERO_FIDELITY.md).
- **HD realism pass (presentation overhaul):**
  - **Arena replaced:** photo-PBR rock floor, aged-brick walls with stone trims and
    marble cornices, corner towers with marble caps, wooden gate with iron banding,
    marble dais, littered boulders and four flickering torch sconces
    (`scenes/arena/arena.tscn`; collisions/spawns unchanged).
  - **Real skies:** per-arena Poly Haven CC0 HDRI panoramas (Default sunrise, Ember
    sunset, Frost moonlit) drive `PanoramaSkyMaterial` + IBL with graceful
    procedural fallback in `arena.gd`.
  - **Post + lighting:** glow (torch/lava/crystal bloom), exposure/contrast
    adjustment, tuned fog, softer high-quality PCF shadows and 2× MSAA + 8×
    anisotropic filtering in `project.godot` — mobile renderer kept (no SSAO/SSR).
  - **Actor material pass:** `HdMaterials` applies anisotropic filtering and
    role-tuned roughness/metallic/specular to every mounted player/enemy model and
    every decorator prop (no texture replacement, no rig changes).
  - Detailed arena floor/wall materials; six distinct pickup models.
  - Approved **character + enemy models** mounted onto the live actors (player via
    `VisualRoot/CharacterModel` + a scene mount node; all eight enemy archetypes via
    a narrow `EnemyBase` hook) through `scripts/visuals/character_visuals.gd`. Fitted
    to height, foot-grounded, glTF +Z rotated onto Godot −Z, idle-looped when the rig
    exposes the clip, and always falling back to the primitive if a model is absent.
  - **KayKit dungeon props** (pillars/columns, banners, torches, crates, barrels,
    rubble) placed deterministically by `ArenaDecorator` with per-arena compositions
    and primitive fallback; **arena themes** (sky/fog/sun/ambient + floor/wall tint)
    give Default / Ember Crucible / Frost Hollow distinct identities.
  - **Arena art pass:** per-arena champion shield banners (`banner_shield_*`) on the
    wall ring, gate-flanking sword trophies (Default), a lit candle ring (Frost),
    crate depots + decorated barrel stacks (Ember), and an open vent grate mounted
    under the fire-vent telegraph. Hazard markers also mount the previously unused
    spike-bed and floor-tile locks; torch sconces get a deterministic glow halo on
    the approved Kenney flare sprite. Landmark silhouettes are enriched in code
    (plinth + rim + wide floor ring per arena, lava crust, crystal heart, obelisk
    rune band) with an idle emission pulse — no new textures required.
  - **Pooled VFX** (`EffectDirector`): GPU bursts + ground rings for enemy spawn /
    death, wave start/completion, pickups, boss spawn/slain and status effects.
  - **Recorded audio registered** (`AudioAssetIntegrator`): the approved SFX variants
    (pooled randomizers) and the five looping music tracks mapped onto the existing
    `music_menu/calm/battle/boss/victory` cues, taking precedence over the procedural
    fallback. Each state bed is a distinct recorded loop: tavern (menu), feast (calm),
    orchestral combat (battle), evil apocalypse (boss) and rejoicing (victory).
- **Integrated since review:** weapon *attachment* visuals (9 weapons handslot.r/l + ModelVisual extent + PlayerEquipment equip), UI skinning (Kenney HUD/status), and skill VFX (EffectDirector distinct tints/textures/radii + PlayerAnimation). **Resolved:** per-arena bespoke art variants — per-arena shield banners, gate trophies, frost candle ring, ember depots, hazard floor models and landmark floor rings with idle animation (themes + decorator + markers, all pinned by `test_regress_arena_art.py`). Recorded boss/calm/victory music was previously pending; all five music beds now ship as recorded CC0 loops.
- Existing source art remains available; preferred equipment/reward selections
  replace old choices in the catalogue, not by destructive source-file overwrites.

## Characters

| Game role | Model | Clips | Source triangles |
|---|---|---:|---:|
| Player | `characters/warden/ArenaWarden.glb` | 76 | 34,860 |
| Player fallback / motion donor | `characters/adventurers/Knight.glb` | 76 | 6,952 |
| Basic | `characters/skeletons/Skeleton_Minion.glb` | 95 | 5,288 |
| Fast | `characters/skeletons/Skeleton_Rogue.glb` | 95 | 5,278 |
| Heavy | `characters/skeletons/Skeleton_Warrior.glb` | 95 | 5,934 |
| Ranged | `characters/skeletons/Skeleton_Mage.glb` | 95 | 4,588 |
| Dasher | `characters/creatures/Rat.glb` | 6 | 4,004 |
| Splitter | `characters/creatures/Spider.glb` | 5 | 2,712 |
| Exploder | `characters/monsters/Demon.gltf` | 14 | 6,712 |
| Warlord | `characters/monsters/BlueDemon.gltf` | 14 | 5,800 |

Paths above are relative to `assets/`. Clip counts are per-model, not unique global
animations. The catalogue records exact names and required bones. KayKit uses
`handslot.r` / `handslot.l`; creature rigs deliberately do not promise those bones.
Rat and Spider clip names include their armature prefixes. Demon glTF buffers are
embedded data URIs; they do not require additional network or binary downloads.

## Equipment and pickups

`gameplay_weapons` maps all nine weapon IDs to reviewed local GLB/glTF sources. The
catalogue also retains the compatible KayKit weapon/shield sources, including the
skeleton staff, crossbow and arrow with local `.bin`/atlas dependencies. New
content reuses reviewed art where a dedicated model is not needed. Never move a
`.gltf` without its referenced neighbours.

`gameplay_pickups` maps every pickup ID to its **runtime** source model:

| Pickup | Art |
|---|---|
| health_orb | Heart |
| stamina_brew | Potion1_Filled |
| antidote | Potion3_Filled |
| xp_gem | Crystal1 |
| magnet_core | Crystal2 |
| coin_cache | Coin_Star |

Configs in `data/pickups/` reference these scenes. `ModelVisual` fits source bounds
into a 0.6 m cosmetic envelope without resizing the collection radius. Different
bottle/crystal shapes help identification independently of tint.

## Environment, UI, effects, audio

- The live arena shell is now **photo PBR**: `arena_floor_rock.tres` (rock albedo +
  normal + AO + metallic, triplanar), `arena_wall_brick.tres` (aged-brick set,
  world-space triplanar), plus marble/wood/metal materials for dais, cornices,
  gate and sconces. Sources are the locks under `assets/textures/rock|brick|stone|
  wood|metal/`.
- Three archived **HDRI panoramas** (`assets/textures/panorama/*.hdr`, 1K,
  Poly Haven CC0 captures via the pinned three.js mirror) are mapped per arena in
  `arena.gd`; falling back to the procedural sky if a `.hdr` is unimported.
- 50 KayKit dungeon environment models remain available for props; they now get
  the same anisotropic/PBR material polish, plus the scene's torches/banners.
- No parallax, tessellation, displacement or new physics geometry.
- `gameplay_arenas` covers all three arenas (themes + decorator); `gameplay_skills` covers all eight skills integrated (EffectDirector distinct tint+texture+radius+burst + SkillExecutor behaviour + audio/camera).
- Existing 55 UI PNGs, 15 particle PNGs and Rajdhani Regular/Bold remain. Every
  upgrade has an icon assignment. No font version change was available in the
  pinned source repository.
- Existing 29 SFX and five Ogg music loops remain, with cue mapping in the catalogue
  and provenance in `AUDIO_MANIFEST.md`. Source clips are not new event wiring.

## Verification

```bash
python3 scripts/download_assets.py --verify
python3 tool/validate_resources.py
python3 tool/validate_assets.py
python3 -m unittest discover -s tests/python -v
# Native import/normalization tests:
godot --headless --path . --import
godot --headless --path . --script res://tests/validate_asset_imports.gd
godot --headless --path . --script res://tests/run_tests.gd
# Optional deep source check:
npm install --prefix .cache/asset-validation --no-audit --no-fund gltf-validator@2.0.0-dev.3.10
node tool/validate_gltf.cjs
```

Offline checks cover all locked source bytes, glTF dependencies/rigs/animations,
PNG integrity, audio/font containers, untracked source files, runtime asset paths,
and coverage against real resource IDs (not assumed filenames).

CC0 art/audio, OFL fonts and MIT stone textures retain their notices under
`ASSET_LICENSES/`. Android export includes these notices and provenance manifests.
No asset licence grants or changes the game's own code licence.
