# Third-party visual assets

Asset review date: **2026-09-08**. Target: the existing Godot 4.4.1, Android,
**3D third-person** low-poly arena game. Characters and world assets are actual
3D meshes, not sprite replacements. PNGs are only textures, UI, and particles.

## Approved sources

| Pack / creator | Original source and licence evidence | Local destination | Licence |
|---|---|---|---|
| KayKit Adventurers 1.0 — Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | `assets/characters/adventurers/`, `assets/weapons/adventurers/` | CC0-1.0 |
| KayKit Skeletons 1.0 — Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 | `assets/characters/skeletons/`, `assets/weapons/skeletons/` | CC0-1.0 |
| KayKit Dungeon Remastered 1.0 — Kay Lousberg | https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0 | `assets/environment/dungeon/`, `assets/pickups/dungeon/` | CC0-1.0 |
| Particle Pack — Kenney | https://kenney.nl/assets/particle-pack | `assets/effects/kenney/` | CC0-1.0 |
| UI Pack (original 1.0 edition) — Kenney | https://kenney.nl/assets/ui-pack | `assets/ui/panels/` | CC0-1.0 |
| Game Icons — Kenney | https://kenney.nl/assets/game-icons | `assets/ui/icons/` | CC0-1.0 |
| Board Game Icons 1.0 — Kenney | https://kenney.nl/assets/board-game-icons | `assets/ui/upgrades/` | CC0-1.0 |
| Rajdhani Regular / Bold — Indian Type Foundry | https://github.com/google/fonts/tree/main/ofl/rajdhani | `assets/fonts/rajdhani/` | SIL OFL-1.1 |
| HDRI panoramas + sample PBR assets (three.js examples) — three.js authors; HDRIs originally Poly Haven | https://github.com/mrdoob/three.js | `assets/textures/panorama/`, `ASSET_LICENSES/threejs-pbr.txt` | MIT (HDRIs: Poly Haven CC0 captures) |
| Godot Material Testers HD photo PBR texture sets — Godot Engine contributors | https://github.com/godotengine/godot-demo-projects | `assets/textures/rock/`, `assets/textures/brick/`, `assets/textures/stone/`, `assets/textures/wood/`, `assets/textures/metal/`, `ASSET_LICENSES/godot-hd-materials.txt` | MIT |

## Rights and redistribution

- **CC0 assets:** personal and commercial use, modification, and redistribution
  (including source assets and compiled games) are permitted; attribution is not
  required. Credit is voluntarily retained. The particle pack's original notice
  also credits its filter-template contributors; that notice is preserved.
- **Rajdhani:** embedding/bundling in a commercial game is permitted under OFL-1.1.
  Preserve the copyright notice and OFL with distributed copies. Do not sell the
  font by itself; modified fonts must satisfy OFL naming/licensing conditions.
  These font files are unmodified. The font licence does not relicense game code.
- This checkout does not declare a project-wide code licence. These permissive
  assets can be bundled with proprietary or open-source game code subject to the
  above conditions; this document does not assert a licence for the game itself.

## Exact files, mirrors, and integrity

`assets/manifest.json` is the machine-readable, per-file source of truth. It records
original creator/source, reviewed download repository, immutable commit, exact
HTTPS download URL, original source path, local destination, byte size, SHA-256,
Git blob hash, acquisition date, and intended use. Every source has a stored notice
in `ASSET_LICENSES/`. See `docs/ASSET_CATALOG.md` for the usable inventory and
integration status; presence in this table does **not** imply a runtime hookup.

KayKit files come from the creator's repositories. Kenney files are from reviewed
redistributions whose notices identify Kenney and CC0: Calinou's Godot particle
pack, ereborstudios' UI/icon packs, and the Board Game Icons directory in
vr-voyage/stable_diffusion_image_viewer. Only the explicitly listed art/notice files
are downloaded, not those projects' code, plugins, examples, or other assets.
The UI mirror contains the **old 1.0** pack, not the redesigned 2.0 pack currently
shown on Kenney's site. Source revisions are pinned; there are no floating `main`
or `master` downloads. GitHub's public content API is used because direct creator
ZIP/raw-download hosts are not reachable from this workspace. The HD realism pass
reuses the same API: the three.js equirectangular HDRIs (original Poly Haven CC0
captures, redistributed inside the MIT-licensed three.js repository at a pinned
commit) and the Godot Material Testers photo PBR maps (same pinned
`godot-demo-projects` revision already used for the stone set). The download lock
now also accepts `.hdr` and `.jpg` source suffixes — every such file is still
checksum-locked with immutable provenance like any other asset.

Downloads are byte-for-byte copies except for documented **filename/path changes**;
.gltf dependencies retain their relative filenames. Authoring tools, FBX duplicates,
paid/EXTRA-tier content, sample renders, and full pack archives are intentionally
excluded to keep the Android project compact. No generative or ripped assets are
included. Model textures and skeletal animation clips are included with the models.

## Reproduce and verify

```sh
python3 scripts/download_assets.py             # download missing approved files
python3 scripts/download_assets.py --verify    # offline size + SHA-256 verification
python3 scripts/download_assets.py --repair    # replace a damaged approved file
```

New sources require a fresh licence review and additions to the manifest and
`ASSET_LICENSES/`; the downloader accepts no arbitrary URL arguments. Network
failures, checksum mismatches, and missing files fail loudly. Validated downloads
are atomically installed; verification never writes files. Audio has its own
cue-level record in `AUDIO_MANIFEST.md`.

## 8 September quality pass

- **Quaternius:** Easy Enemy, Ultimate Monsters, Medieval Weapons and Ultimate RPG
  selected assets. Original CC0 pack evidence and exact mirrors are recorded in
  `docs/ASSET_AUDIT.md`. Downloaded models live under `assets/characters/creatures/`,
  `assets/characters/monsters/`, `assets/weapons/medieval/`, `assets/pickups/rpg/`.
  A shared original CC0 notice is preserved in `ASSET_LICENSES/quaternius.txt`.
  `license_pack` explicitly links the model sources to that pinned notice source;
  the validator requires the notice to exist and its licence type to match.
- **Godot Engine contributors:** three stone PNG maps from the Material Testers
  demo, pinned repository revision in the lock. **MIT**, not CC0. Retain the exact
  copyright/permission notice in `ASSET_LICENSES/godot-stone.txt` in distributions.
  Local materials are newly authored; downloaded pixels are unmodified.
- **KayKit Skeletons:** added the missing Mage and ranged equipment from the same
  previously approved, unchanged upstream revision and original CC0 notice.

### HD realism pass (same day)

- **three.js examples HDRI panoramas (MIT repo; HDRIs are Poly Haven CC0 captures):**
  `spruit_sunrise_1k.hdr`, `venice_sunset_1k.hdr`, `moonless_golf_1k.hdr` power the
  Default / Ember Crucible / Frost Hollow skies and image-based lighting. The exact
  MIT notice is bundled; Poly Haven's CC0 origin is credited here and in the
  catalogue. Direct Poly Haven hosts remained unreachable from this workspace, so
  the pinned reachable mirror is used instead of placeholder files.
- **Godot Material Testers photo PBR sets (MIT):** rock (albedo/normal/AO/metallic),
  aged brick (albedo/normal/AO/metallic), polished marble, wood planks and brushed
  aluminium (albedo/normal) are locked under `assets/textures/…` and drive the new
  arena materials. Locally authored `.tres` materials are not downloads; they stay
  under `assets/materials/` and are validated by `tool/validate_resources.py`.
- **`.hdr` / `.jpg` suffixes** were added to the downloader's approved extension set
  so these photo assets can be checksum-locked and restored like every other file.

The shared notice provision does not allow unknown licences, unpinned downloads,
missing notice files or licence-type mismatches. No paid tiers or application code
from asset mirrors were downloaded.


## Arena Warden derivative — 9 September 2026

The live hero now uses **project-authored** armor/underlayers/helmet/skin weights
and PBR textures, plus a project-authored gladius. The 76 motions and rest axes
are derived from the already-approved **KayKit Adventurers / Kay Lousberg, CC0**
source; no source download was edited and no new third-party character licence
is assumed. See `ASSET_LICENSES/arena-warden.md` and `docs/HERO_FIDELITY.md`.
`assets/characters/warden/build_report.json` pins the donor, recipe and all five
generated outputs. The normal asset validator checks this derived inventory as
strictly as the upstream download lock; the downloader does not manage it.

The dev-only art viewer's missing `tool/vendor/three.core.js` was restored from
three.js commit `2431a09f46f34c560bc8e44b33be0e567723d5b9`, matching the already
vendored `three.module.js`. The MIT notice is preserved in
`ASSET_LICENSES/threejs-pbr.txt`; `tool/vendor/README.md` records the file hash.

## 9 September music-bed pass (audio)

Recorded CC0 loops now cover all five music states (previously only menu + combat
shipped, and boss/calm/victory shared the combat loop or fell back to procedural
pads). Two already-reviewed mirrors provided the new tracks, so provenance stays
within the existing workflow: RandomMind's medieval loop set (`ashawkey/GlyphChess`,
same pinned revision as the menu track) supplies `arena_calm.ogg` (King's Feast)
and `arena_victory.ogg` (Rejoicing); Juhani Junkala / SubspaceAudio's **JRPG Music
Pack #3 [Evil]** supplies `arena_boss.ogg` (Evil3 – Apocalypse) from Packt
Publishing's official Godot 4 book repository at a pinned commit. Each original
OpenGameArt page displays **CC0**, and the creator-written notice is saved under
`ASSET_LICENSES/jrpg-evil.txt`. Details and the cue map live in `AUDIO_MANIFEST.md`.
