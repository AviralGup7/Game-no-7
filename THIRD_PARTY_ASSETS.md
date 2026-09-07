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
ZIP/raw-download hosts are not reachable from this workspace.

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

The shared notice provision does not allow unknown licences, unpinned downloads,
missing notice files or licence-type mismatches. No paid tiers or application code
from asset mirrors were downloaded.
