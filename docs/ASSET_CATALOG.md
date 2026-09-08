# Last Stand: Arena — asset catalogue

Reviewed **8 September 2026** · Godot 4.4.1 · 3D third-person · Android

**222 checksum-locked files, 35.05 MiB: 81 models, 79 PNGs, 31 audio clips,
2 fonts, 14 binary mesh dependencies and 15 licence/credit notices.**

See [the audit](ASSET_AUDIT.md) for additions, online comparisons and limitations.
The machine-readable role map is [`assets/catalog.json`](../assets/catalog.json);
the immutable source/download lock is [`assets/manifest.json`](../assets/manifest.json).

## Integration status — important

- **Integrated (environment/presentation pass, Agent 4):**
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
  - **Pooled VFX** (`EffectDirector`): GPU bursts + ground rings for enemy spawn /
    death, wave start/completion, pickups, boss spawn/slain and status effects.
  - **Recorded audio registered** (`AudioAssetIntegrator`): the approved SFX variants
    (pooled randomizers) and the two looping music tracks mapped onto the existing
    `music_menu/calm/battle/boss/victory` cues, taking precedence over the procedural
    fallback.
- **Still pending (not owned here / not yet wired):** weapon *attachment* visuals on
  the rigged hands, UI skinning, per-arena bespoke art variants, and recorded boss
  music (the approved library ships only a menu loop and one combat loop).
- Existing source art remains available; preferred equipment/reward selections
  replace old choices in the catalogue, not by destructive source-file overwrites.

## Characters

| Game role | Model | Clips | Source triangles |
|---|---|---:|---:|
| Player | `characters/adventurers/Knight.glb` | 76 | 6,952 |
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

`gameplay_weapons` maps all six weapon IDs to detailed medieval GLBs. The catalogue
also retains the compatible KayKit weapon/shield sources, now including skeleton
staff, crossbow and arrow with local `.bin`/atlas dependencies. Never move a `.gltf`
without its referenced neighbours.

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

- 37 KayKit dungeon environment models remain available for walls, floors, gates,
  pillars, banners, crates, barrels, torches and rubble.
- Shared stone colour/normal/AO maps (1024 × 666) power local materials under
  `assets/materials/`. Floor tiling and world-space wall projection prevent wall
  stretch; no parallax, tessellation, displacement or new physics geometry.
- `gameplay_arenas` covers all three arenas; `gameplay_skills` covers all five
  skills with existing particle texture sources. Skill-specific emitters are pending.
- Existing 55 UI PNGs, 15 particle PNGs and Rajdhani Regular/Bold remain. Every
  upgrade has an icon assignment. No font version change was available in the
  pinned source repository.
- Existing 29 SFX and two Ogg music loops remain, with cue mapping in the catalogue
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
