# Third-Party Asset Licences & Provenance

Every externally sourced *visual* asset in this repository is recorded below with its
licence and provenance. We only accept assets whose licence permits the intended use
in a distributed (compiled) game — preferring **CC0 / public domain** and permissive
open-source assets from **Kenney**, **OpenGameArt** (licence permitting), and official
creator pages.

**Policy:** no asset is used if it is a ripped game asset, a copyrighted character or
music track, has unclear licensing, requires attribution we cannot honour, or was
scraped from an untrusted page. Download automation only ever touches URLs explicitly
approved here (see `scripts/download_assets.py`).

## Current state

No third-party visual assets are committed yet. The project currently ships only
placeholders/primitive meshes generated in-scene (no copyrighted material). Before any
real asset is added, this file and `ASSET_LICENSES/` must be updated with the record
below and a **checksum** recorded.

## Per-asset record (template)

| Field | Value |
|---|---|
| Asset name | _e.g. Kenney "Kitchen" humanoid_ |
| Category | characters / environment / ui / effects |
| Creator | _name / handle_ |
| Source URL | _page where found_ |
| Direct download URL | _exact file_ |
| Licence | CC0 / CC-BY… / MIT … |
| Commercial use permitted | yes / no |
| Redistribution in compiled game | yes / no |
| Attribution requirement | none / text + URL |
| Modification permitted | yes / no |
| Local file path | `assets/…` |
| Used in | scene / screen |
| Date downloaded | YYYY-MM-DD |
| Checksum | sha256 |
| Compatible with project licence | yes |

## Asset provenance checklist

For every download we confirm (1) source site, (2) asset name, (3) licence, (4)
commercial use, (5) redistribution in a compiled game, (6) attribution, (7) download
URL, (8) modification rights, and (9) compatibility with the rest of the project —
then store any supplied licence/readme file under `ASSET_LICENSES/`.
