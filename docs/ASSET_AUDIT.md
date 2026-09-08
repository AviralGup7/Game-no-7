# Asset audit and quality upgrade — 8 September 2026

## Result

- **Before:** 191/191 locked downloads present and correct (24.75 MiB). No corrupt
  downloads, broken glTF dependencies, or missing referenced scene resources found.
- **Actual gaps:** the old catalogue covered only player + 3 enemies, no explicit
  six-weapon map, no complete six-pickup map, and no skill/arena art coverage checks.
  The live game still used primitive actors, floor/walls and identical pickup prisms.
- **After:** 222/222 locked files (35.05 MiB), including **81 3D models** (+23),
  79 PNGs, 31 audio files and 2 fonts. Added 31 downloads, about **10.30 MiB**.
- All eight enemy archetypes + the player, six weapons, six pickups, five skills
  and three arenas now have explicit source-art mappings. Mappings are not a claim
  that animation, equipment or particle-system integration is finished.

## Downloaded additions and replacement selections

| Role | New selection | Why / status |
|---|---|---|
| Ranged enemy | KayKit Skeleton Mage, 95 clips | Matching skeleton art family; downloaded, rig wiring pending |
| Dasher | Quaternius Rat, 6 clips | Distinct running creature; downloaded, animation adapter pending |
| Exploder | Quaternius Demon, 14 clips | Horned monster silhouette; downloaded, warm palette/animation integration pending |
| Splitter | Quaternius Spider, 5 clips | Broad multi-legged silhouette; downloaded, animation adapter pending |
| Warlord | Quaternius BlueDemon, 14 clips | Dedicated boss silhouette; downloaded, scale/palette/animation integration pending |
| Gladius / spear / hammer / bow / daggers / axe | Quaternius Sword_Golden, Spear, Hammer_Double, Bow_Golden, Dagger, Axe_Double | Actual matching equipment, including previously absent spear/hammer/bow; preferred catalogue selections, attachments pending |
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
  claim. Downloading more sounds does not solve the still-pending audio registration.

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

**Not completed:** replacing live actor primitives, animation-state adapters,
weapon attachments/loadout visuals, UI skinning, full skill VFX and downloaded audio
registration. Those need gameplay-aware integration, not simply renaming downloads.
Android frame-time, texture seams and on-device readability are not yet measured.
