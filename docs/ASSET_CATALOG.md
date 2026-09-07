# Last Stand: Arena — downloaded asset kit

**3D · third-person · stylized low-poly · Godot 4.4.1 / Android**  
Downloaded and reviewed: **7 September 2026**

The project already uses `CharacterBody3D`, a 3D arena, and a following perspective
camera. This kit supplies **real rigged 3D models**, not 2D character sprites.

> **Delivery status:** the files are downloaded, extracted into usable formats,
> checksum-locked, and organized in `assets/`. **They are not yet connected to the
> running game.** The live player/enemy scenes still show their original primitives;
> animation states, UI skins, and audio event registration remain a separate
> integration step. Combat, camera controls, and progression have not been changed.

## What is included

**178 asset files + 13 original licence/credit notices = 191 verified downloads,
24.75 MiB (25,952,081 bytes).** No full ZIP packs, FBX duplicates, paid content,
Blender dependency, or remote runtime asset requests.

| Game requirement | Downloaded | Location |
|---|---|---|
| Player + 3 enemy archetypes | **4 rigged GLB characters**, textures embedded; 76 / 95 animation clips per character | `assets/characters/` |
| Melee equipment | **11 weapon/shield models**, matching `.bin` files and texture atlases | `assets/weapons/` |
| Arena / environment | **37 GLB models**: floors, walls, gates, columns, banners, rubble, crates, barrels, torches | `assets/environment/dungeon/` |
| Rewards / pickup art | **6 GLB models**: coin, coin stack, two chests, bottle, key | `assets/pickups/dungeon/` |
| Combat / spawn / reward effects | **15 PNG particle textures** for billboards in a 3D particle system | `assets/effects/kenney/` |
| Menus / touch controls / upgrades | **55 PNGs**: 18 interface icons, 20 combat/upgrade icons, 17 skin elements | `assets/ui/` |
| UI typography | **2 TTFs**: Rajdhani Regular + Bold | `assets/fonts/rajdhani/` |
| Sound effects | **29 clips**, including variants, mapped to gameplay and reserve cues | `assets/audio/sfx/` |
| Music | **2 loop-ready Ogg tracks**, menu + combat | `assets/audio/music/` |

The total includes **58 3D models**. The 76 PNG files include UI/effects and the
six editable character/weapon atlases. Character animations are inside the GLBs;
they are not separate downloads or missing animation packs.

## Characters and animations

One matching KayKit art family supplies the characters, melee equipment and arena.
All four character models include skinning, a skeleton, a texture atlas, and clips
for idle, walking, running, attacking, dodging, taking a hit, and dying.

| Intended role | Model | Clips | Source triangles* | Intended scene |
|---|---|---:|---:|---|
| Player — blue knight | [Knight.glb](../assets/characters/adventurers/Knight.glb) | 76 | 6,952 | `scenes/player/player.tscn` |
| Basic / Grunt | [Skeleton_Minion.glb](../assets/characters/skeletons/Skeleton_Minion.glb) | 95 | 5,288 | `scenes/enemies/basic_enemy.tscn` |
| Fast / Stinger | [Skeleton_Rogue.glb](../assets/characters/skeletons/Skeleton_Rogue.glb) | 95 | 5,278 | `scenes/enemies/fast_enemy.tscn` |
| Heavy / Brute | [Skeleton_Warrior.glb](../assets/characters/skeletons/Skeleton_Warrior.glb) | 95 | 5,934 | `scenes/enemies/heavy_enemy.tscn` |

\*Source-scene totals reported by Khronos' validator, **not** measured Android draw
costs or an FPS guarantee. Characters have multiple mesh parts; profile crowd sizes
and consider mesh consolidation/LODs during integration.

The exact, case-sensitive animation list for each character is in
[`assets/catalog.json`](../assets/catalog.json). Useful common clips:

| Action | Clip name |
|---|---|
| Idle | `Idle` |
| Walk / run | `Walking_A`, `Running_A` |
| Sword slash | `1H_Melee_Attack_Slice_Horizontal` |
| Fast stab | `1H_Melee_Attack_Stab` |
| Heavy chop | `1H_Melee_Attack_Chop` |
| Hurt / death | `Hit_A`, `Death_A` |
| Dodge | `Dodge_Forward`, `Dodge_Backward`, `Dodge_Left`, `Dodge_Right` |
| Skeleton spawn options | `Spawn_Ground_Skeletons`, `Skeletons_Awaken_Standing` |

The clip counts include alternate attacks, poses and nonessential actions, and
**many names are shared across models**; they are not 361 unique animations.
Animation availability does not create new mechanics such as jumping or spellcasting.

### Equipment

- Adventurer kit: `sword_1handed`, `sword_2handed`, `axe_1handed`, `axe_2handed`,
  `dagger`, `shield_badge`, `shield_round`.
- Skeleton kit: `Skeleton_Blade`, `Skeleton_Axe`, `Skeleton_Shield_Small_A`,
  `Skeleton_Shield_Large_A`.
- Keep each `.gltf` beside its `.bin` and PNG dependencies. Never move only the
  `.gltf` file. Character/world `.glb` files embed their mesh data and textures.
- All four rigs expose **`handslot.r`** and **`handslot.l`**. Use a Godot
  `BoneAttachment3D` for weapons/shields and confirm grip offsets in the editor.
  Weapons are supplied separately; a downloaded character is not automatically armed.

## Arena, rewards, and effects

The environment selection covers the current compact arena: stone/dirt floors,
straight/half/broken/corner walls, doorway and gated pieces, pillars, barriers,
stairs, four banner colours, crates/barrels, rubble and lit/unlit torch meshes.
Original long `.gltf.glb` names were shortened to `.glb`; the binary bytes are
unchanged and original names are recorded in the lock file.

Coins and chests cover reward art. The green labelled bottle can represent a health
pickup after UI/material tuning. **Keys and spikes are reserve art, not new game
features.** Chests, doors and spikes have separate mesh parts but **no animation
clips or interaction/collision logic** in these selected files.

The effects map covers hit sparks, dodge dust, a spawn ring, spawn magic, death
smoke, torch flame, pickup glow, upgrade stars and a weapon trail. These PNGs are
normal inputs to `GPUParticles3D` / billboard materials; using them does not make
the game 2D. Particle scenes, emission timing and pooling are not implemented here.

No external skybox, camera, collision mesh or navigation download is required:
the project already has a procedural sky, follow camera, collisions and navigation
setup. Preserve its 26 × 26 m play area and spawn clearance when placing art.

## Interface and audio coverage

[`assets/catalog.json`](../assets/catalog.json) maps all **10 current upgrade IDs**
to downloaded icons: `bloodlust`, `force`, `fortified`, `haste`, `hunter`, `power`,
`reach`, `scavenger`, `swift`, `vitality`. It also lists font roles, character mounts,
weapon choices, effects, arena props and **19 planned audio cue IDs**.

The UI kit contains light icons suitable for the existing dark panels, blue/grey/
yellow button/panel assets, slider pieces and a circular joystick skin. This is the
original Kenney UI Pack 1.0 edition, not the current 2.0 redesign.

All player/enemy cues already named in scripts have a downloaded candidate, plus
wave/game-over/menu cues and footsteps. Menu music is **The Old Tower Inn**
(~49.95 s loop) and combat music is **Epic Boss Battle** (~123.43 s loop).
See [`AUDIO_MANIFEST.md`](../AUDIO_MANIFEST.md) for every cue, file, source and mixing
note. Music Loop flags and gain values in the catalogue are **recommendations**;
they have not been applied in Godot. No speech/voice pack is necessary for the
current game's non-dialogue feature set.

## Integration checklist — still to do

1. **Import with pinned Godot 4.4.1.** Inspect the GLBs and animations in Advanced
   Import. Use the models under the existing `VisualRoot/CharacterModel`, keeping
   `CharacterBody3D`, collision shapes, attack origins, controller and camera intact.
2. **Scale and facing.** Match the ~1.9 m player capsule, then the existing enemy
   scale/tint configuration. glTF is Y-up; check model-facing yaw against the
   controller's **−Z forward** before wiring attacks. Preserve silhouettes and the
   basic green / fast amber / heavy red readability palette from `ART_STYLE.md`.
3. **Animate and equip.** Drive clips from current movement/combat states, set
   locomotion loops, keep hurt/death/attack clips one-shot, and attach equipment to
   the hand-slot bones. Physics remains controller-driven: do not apply root motion
   twice. Use material-based hit flashes rather than a 2D `modulate` on `Node3D`.
4. **Dress the arena.** Reuse the existing bounds/collisions; keep props out of walk
   and spawn paths or supply matching collision/nav changes. Share atlas/material
   resources and use Godot LOD/import settings suitable for mobile.
5. **Connect UI/effects/audio.** Assign `UpgradeConfig.icon` and display it on cards,
   apply the fonts/skin, create pooled particle scenes, and register cue resources
   under `data/audio/`. The existing registry discovers `.tres` audio resources,
   **not** loose Ogg files or this catalogue. Configure music looping and mix SFX.
6. **Device QA.** Check full wave crowds, animation timing vs damage timing, touch
   readability, audio headroom, texture compression, and frame rate on Android.

## Verification and restoration

All downloaded sources are versioned in the repository, so a normal clone is
usable offline. The downloader only restores missing reviewed files; it does not
scrape websites or accept arbitrary URL arguments.

```bash
python3 scripts/download_assets.py --verify   # offline; checks all 191 source files
python3 tool/validate_assets.py               # formats, dependencies, rigs, coverage
python3 -m unittest discover -s tests/python -v

python3 scripts/download_assets.py            # restore missing files only
python3 scripts/download_assets.py --repair   # explicitly replace damaged files
python3 scripts/download_assets.py --list     # pack IDs, sizes and licences
# Optional subset:
python3 scripts/download_assets.py --pack skeletons --verify
```

Native engine validation (also added to CI / the Android build script):

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/validate_asset_imports.gd
```

**Validation performed in this workspace:**

- 191/191 byte sizes and SHA-256 hashes pass; every model dependency is present.
- All 58 models pass Khronos glTF validation with **0 errors**. There are **32
  upstream `NODE_SKINNED_MESH_NON_ROOT` warnings** on the four characters (mesh
  parts under their rig). Original files were preserved; test parent transforms
  and animation playback in Godot when integrating. The validator also emits
  non-error hints about buffer targets and unused tangents/objects.
- All 76 PNGs pass integrity checks; all 31 audio files decode successfully and
  are non-silent; both font containers validate.
- **28 Python tests pass**, including missing/corrupt downloads, interrupted
  transfers, atomic repairs, licence locks, path safety and game-specific coverage.
- Existing `.tscn`/`.tres` structural validation: **25 files pass**.
- **Native Godot import, GDScript execution and Android export were not run here.**
  Godot is not installed and its release-download host is unreachable from this
  workspace. A native import smoke test is provided; source-format validation is
  not being represented as an engine/device test.

Optional reproducible deep format check (Node is a developer tool, not a game dependency):

```bash
npm install --prefix .cache/asset-validation --no-audit --no-fund gltf-validator@2.0.0-dev.3.10
node tool/validate_gltf.cjs
```

## Licences and exact sources

Models, equipment, environment, icons, effects and audio are **CC0**. The two
unmodified fonts are **SIL OFL-1.1**; keep their copyright/licence with distribution.

- [`THIRD_PARTY_ASSETS.md`](../THIRD_PARTY_ASSETS.md) — visual asset provenance and rights
- [`AUDIO_MANIFEST.md`](../AUDIO_MANIFEST.md) — cue-level audio provenance
- [`ASSET_LICENSES/README.md`](../ASSET_LICENSES/README.md) — preserved notices and music licence evidence
- [`assets/manifest.json`](../assets/manifest.json) — exact download URL, immutable source
  commit, original/local path, size and SHA-256 **for every file**

Original creator repositories are used for KayKit and Google Fonts. Reviewed,
credited redistributions supply Kenney and the two Ogg music conversions because
some original download hosts are unavailable here. No code/plugins from those
redistribution projects were imported. Asset licences are bundled by the Android
export presets; these licences do not assign a licence to the game's own code.
