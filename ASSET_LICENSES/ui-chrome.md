# UI chrome previews — project-authored asset provenance

`data/ui/chrome/` (HUD frame, panels, buttons, icons, `menu_backdrop.jpg`) and
`data/ui/ui_page_render.png` are **project-authored design previews**, not Kenney
downloads. They are excluded from the Android APK (`export_presets.cfg`
`exclude_filter` lists `data/ui/chrome/menu_backdrop.jpg` and
`data/ui/chrome/icon_*.png`).

- Author: this project.
- Licence: the repository's existing terms; no third-party licence applies.
- Runtime HUD/icons used in-game come from the checksum-locked Kenney packs
  under `assets/ui/` (see `THIRD_PARTY_ASSETS.md` and `kenney-*.txt`).
