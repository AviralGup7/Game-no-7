# Arena Warden — generated asset provenance

The Arena Warden's visible armor, underlayers, helmet, gloves, boots, heraldry,
PBR atlases and Warden Gladius are project-authored geometry/textures generated
by `tool/build_hero.py` and `tool/hero/geometry.py`. They are not a downloaded
photoreal scan or a modification of KayKit's visible mesh/texture atlas.

## Motion donor (CC0-1.0)

The deform rest axes and 76 animation clips are derived from **KayKit Adventurers
1.0 — Knight**, by **Kay Lousberg**. The already-reviewed original remains
unchanged at `assets/characters/adventurers/Knight.glb`.

- Original pack: https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
- Creator: https://kaylousberg.com/
- CC0 legal text: https://creativecommons.org/publicdomain/zero/1.0/
- Preserved original notice: `ASSET_LICENSES/adventurers.txt`
- Immutable source revision, byte count, SHA-256 and download URL:
  `assets/manifest.json`, pack `adventurers`.

The derivative has new human-proportioned bone offsets, inverse bind matrices
and skin weights. Motions are resampled, helper/IK joints removed, locomotion leg
lift conditioned offline, planar root travel removed and floor support baked.
Clip names and both `handslot.l` / `handslot.r` attachment joints are preserved.
No paid/Mixamo animation files or unreviewed character downloads are included.
The original creator does not endorse this project or the derivative.

## Reproduction and verification

`assets/characters/warden/build_report.json` records the exact source hash,
authoring recipe hashes, output file hashes and measured geometry/clip inventory.
The generated files are checked into the repository; neither the game nor a clean
Godot import needs Python authoring dependencies, network access or Blender.
Use `python3 tool/validate_assets.py` to verify both the upstream and derived
inventories. See `docs/HERO_FIDELITY.md` for the reproducible build and scope limits.
