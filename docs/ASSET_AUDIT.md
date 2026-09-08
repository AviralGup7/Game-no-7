# Asset audit and quality upgrade — 8 September 2026

## Result

- **Before:** 191/191 locked downloads present and correct (24.75 MiB). No corrupt
  downloads, broken glTF dependencies, or missing referenced scene resources found.
- **Actual gaps:** the old catalogue covered only player + 3 enemies, no explicit
  six-weapon map, no complete six-pickup map, and no skill/arena art coverage checks.
  The live game still used primitive actors, floor/walls and identical pickup prisms.
- **After:** 222/222 locked files (35.05 MiB), including **81 3D models** (+23),
  79 PNGs, 31 audio files and 2 fonts. Added 31 downloads, about **10.30 MiB**.
- All eight enemy archetypes + the player, nine weapons (via PlayerEquipment socket), six pickups, eight skills (distinct VFX/texture/tint) and three arenas (themes+decorator) now have explicit source-art mappings **and runtime integration** (CharacterVisuals/EnemyAnimator/PlayerAnimation/ModelVisual/EffectDirector/AudioAssetIntegrator); remaining gap is per-arena bespoke meshes + boss-music fallback.

## HD realism pass (same review date)

The game now looks visually different — this is a presentation overhaul, **not**
new gameplay, rigs, balance or systems.

| Concern | What changed | Source / status |
|---|---|---|
| Arena map | Flat plane + colour boxes replaced by a photo-PBR shell: rock floor, aged-brick walls with trims and marble cornices, corner towers + caps, iron-banded wooden gate, marble dais, boulders, 4 flickering torches | Realistic textures lock; scene rebuilt (`arena.tscn`); collisions/spawns/navigation untouched |
| Sky & lighting | Procedural sky replaced by real **HDRI panoramas** per arena (IBL); softer shadows, tuned fog, exposure/contrast, glow on emissives | Poly Haven CC0 HDRIs via pinned three.js mirror (MIT) |
| Render settings | 2× MSAA, 8× anisotropic filtering, high-quality PCF shadows | `project.godot`; mobile renderer retained for frame time |
| Character/enemy look | `HdMaterials` material pass on every mounted actor: anisotropic filtering + role-tuned roughness/metallic/specular (armour vs bone vs hide) | Scripts; no texture/model/rig replacement |
| Arena props | KayKit dungeon props + landmarks receive the same material polish; landmarks use the photo-rock/marble materials | Scripts/materials |
| Models | **Kept** the rigged KayKit/Quaternius actors | See "Why not a photoreal rig swap" below |

### Why not a photoreal rig swap

Reviewed candidates for a fully rigged, fully animated, permissively licensed
realistic humanoid were checked on GitHub (three.js `Soldier.glb` / `Xbot.glb` /
`Michelle.glb` / `kira.glb`, Khronos `CesiumMan` / `Fox` / `BrainStem`, Blender
Studio Sintel mirrors, Quaternius Modular Character Outfits — Fantasy):

- `Soldier` — photoreal PBR (2.1 MB, Idle/Walk/Run) but **no attack/hurt/death/
  dodge clips** and a modern rifle asset; swapping it in would leave the hero
  gliding through combat.
- `Michelle` / `kira` / `Nemetona` — no locomotion or combat clip sets.
- `Xbot`/`Fox`/`BrainStem` — no combat clip sets, wrong silhouette/theme.
- Sintel (CC BY mirrors) — no reliable combat clip set; mirror provenance issues.
- Quaternius Outfits — not an animated drop-in; requires full retargeting.

Replacing the working 76/95/14-clip inventories with a rig that lacks the clips the
animators drive would visibly break combat feedback, so the approved rigs were
retained and upgraded at the material level instead. A photoreal animated
character set (with a documented retarget plan) is a future work item; the
candidate URLs stay in this audit for that pass.

## Downloaded additions and replacement selections

| Role | New selection | Why / status |
|---|---|---|
| Ranged enemy | KayKit Skeleton Mage, 95 clips | Matching skeleton art family; integrated via CharacterVisuals height 1.72 PI yaw + EnemyAnimator cast clip |
| Dasher | Quaternius Rat, 6 clips | Distinct running creature; integrated Rat 0.85 PI + DashState |
| Exploder | Quaternius Demon, 14 clips | Horned monster silhouette; integrated Demon 1.65 fuse→explosion |
| Splitter | Quaternius Spider, 5 clips | Broad multi-legged silhouette; integrated Spider 1.00 fuse→scatter |
| Warlord | Quaternius BlueDemon, 14 clips | Dedicated boss silhouette; integrated 2.45 3-phase + BossPhaseLight |
| Gladius / spear / hammer / bow / daggers / axe | Quaternius Sword_Golden, Spear, Hammer_Double, Bow_Golden, Dagger, Axe_Double | Actual matching equipment, including previously absent spear/hammer/bow; integrated 9 weapons via PlayerEquipment socket handslot.r/l ModelVisual extent |
| Ranged equipment | Skeleton staff, crossbow, arrow + their binary dependencies; medieval arrow | Compatible equipment sources; downloaded |
| Six pickups | Heart, two filled potions, two crystals, star coin | **Replaces identical prisms in live pickup spawning**; source materials retained |
| Reward chests | Closed chest / ingot chest | More detailed catalogue replacements; no new chest gameplay |
| Floor / walls | Godot stone albedo, normal, ambient-occlusion maps | **Replaces live flat-colour materials**; 1024 × 666 source maps, non-metallic, no displacement or new geometry |

New creature source geometry ranges from 2,712 to 6,712 triangles; the existing
Knight is 6,952. These are source mesh totals, not a draw-call or device-FPS promise.
Retaining a good model is preferable to increasing triangle count without a visual
benefit. Equipment uses more shaped/bevelled geometry than the original simple kit.

## Online upgrade review

All **13 original pinned download repositories** were checked against their current
HEAD through GitHub's API. Each still matched the manifest's pinned revision.
That checks those repositories, not every vendor storefront or paid edition.

- KayKit's official Skeletons storefront advertises Free 1.1; the creator's Godot
  GitHub distribution remains the pinned 1.0 revision. The storefront also directs
  users to a separate animation library. Kept the verified 76/95-clip rigs rather
  than assuming a newer archive is a compatible drop-in replacement.
  https://kaylousberg.itch.io/kaykit-skeletons
- Reviewed Quaternius **Modular Character Outfits – Fantasy** (November 2025): a
  newer textured, humanoid-retargetable direction, but outfits are not animated
  drop-in KayKit replacements. Full rig/animation retargeting and pack-tier review
  are needed before replacing the working animation inventory. Not downloaded.
  https://quaternius.com/packs/modularcharacteroutfitsfantasy.html
- Reviewed Poly Haven stone materials and ambientCG PavingStones036. Direct texture
  hosts/API were unreachable from this sandbox. No placeholder files or unverified
  mirrors were installed. Used the reachable, pinned Godot material-test texture set.
  https://polyhaven.com/a/monastery_stone_floor
  https://ambientcg.com/view?id=PavingStones036
- Existing fonts, particle textures, UI and sound files remain intact. The UI mirror
  is the older Kenney 1.0 kit, not the redesigned storefront 2.0 kit. A compatible
  licensed/downloadable upgrade was not established in this pass; no false “latest”
  claim. Recorded audio registration is now completed (AudioAssetIntegrator maps 31 catalog cues + procedural 29+5 fallback); simply downloading more raw files without registration remains ineffective.

## Provenance

Original pack pages explicitly state CC0:

- https://quaternius.com/packs/ultimatemonsters.html
- https://quaternius.com/packs/easyenemy.html
- https://quaternius.com/packs/medievalweapons.html
- https://quaternius.com/packs/ultimaterpg.html

Only selected assets were downloaded from the reviewed GLB/glTF redistributions
`trebeljahr/quaternius-showcase` and `511action/descent-3d-assets`. The generic
Quaternius CC0 notice is preserved from `beep2bleep/FreeAssetsByKenneyNLandQuaternius`;
the original pack pages provide the pack-specific licence evidence. The mirror's
application-code licence is **not** being used as proof of asset ownership.

Stone textures are from `godotengine/godot-demo-projects`' Material Testers demo,
under its MIT repository licence. The exact copyright/permission notice is bundled
in `ASSET_LICENSES/godot-stone.txt`. No demo code, shaders or 4.7-specific scenes
were imported. Local StandardMaterial3D resources target this project's Godot 4.4.1.

Every new download has an immutable GitHub revision, source path, byte count,
Git blob SHA-1 and SHA-256 in `assets/manifest.json`. No source bytes were edited.
Existing files are kept because they remain valid fallback/alternate art, not hidden
backups. Newly preferred choices are explicit in `assets/catalog.json`.

## Validation and remaining work

- Offline hash verification: **222/222**.
- Structural resource validation: **70 files**, no errors.
- Python tests: **37 passing**, including provenance, shared-licence safeguards,
  untracked/missing source detection and expanded content coverage.
- Khronos glTF validator: **81 models, 0 errors, 49 warnings**. Warnings concern
  skinned-node transforms/root placement and PNG features; they are not silently
  discarded. Native importer and device review remain necessary.
- **Native Godot 4.4.1 CI passed**, including headless unit tests, all imported
  assets/animation names, detailed materials, six pickup models and normalization.
  Android APK export succeeded for commit `00c432b`:
  https://github.com/AviralGup7/Game-no-7/actions/runs/34171952660
- The post-import audit caught Godot extracting embedded textures into untracked
  PNGs. Set the scene importer default to **Embed as Basis Universal** so fresh
  imports keep textures in the engine cache, not duplicated in source directories.
  The successful CI run verifies this fix on a clean checkout.
- Local Godot execution remains unavailable (engine download host TLS failure);
  native validation above ran on GitHub Actions, not locally or on a phone.

**Completed since audit:** live actor primitives replaced (Knight + 8 enemies via CharacterVisuals fitted bounds), animation-state adapters (EnemyAnimator per-archetype), weapon attachments/loadout visuals (PlayerEquipment 9 weapons socket + ModelVisual), UI skinning (Kenney HUD + status icons), full skill VFX (EffectDirector 10-colour + distinct textures/radii) and recorded audio registration (AudioAssetIntegrator 31 clips mapped). Remaining: device frame-time/texture seams/on-device readability — NOT YET DEVICE-VERIFIED; boss music still procedural fallback (library ships only menu+combat loops).
