# Station environment modules — project-authored asset provenance

The modular floor, ceiling and wall kits under `data/models/{ceiling,ground,wall}*`
(GLB + glTF/BIN + PBR atlases, plus `raw_texture.png` / `*_render.png` /
`environment_showcase.png` previews) are **authored in this repository**. The
glTF `asset.generator` field is `Game-no-7 3D Modular Environment Builder`.

- Author: this project (no third-party contributor).
- Licence: the repository's existing terms; no third-party licence applies to
  these files because no third-party work is contained in them.
- They are **not** in `assets/manifest.json`. The download lock must not overwrite
  them. `tool/validate_assets.py` still format-checks every GLB/PNG.

Kenney Space Station Kit meshes (containers, computer, display wall, …) remain
under `assets/environment/space_station/` with their own CC0 notice
(`kenney-space-station.txt`). The tiny `panel.png` next to those files is a
**project-authored** triplanar tile (`tool/station_assets.py` /
`assets/environment/space_station/build_report.json`), not a Kenney download.

The Nicholas-3D warehouse (`data/models/warehouse/`) is third-party CC-BY-4.0
and is **not** part of this notice — see `nicholas3d-warehouse.txt`.
