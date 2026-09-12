# Skill cast foci — project-authored asset provenance

The eight skill cast-focus props (`data/models/skills/<skill_id>/focus.glb`), their PBR atlases,
the 128 px skill-bar icons and the verification renders are **authored in this repository** by
`tool/build_skill_foci.py` and the `tool/skill_forge/` package. Nothing in the set is a download,
a scrape, a photograph-derived scan, or a modification of another pack's mesh or texture atlas:
the geometry is written as parametric profiles, the albedo/normal/ORM/emission maps are generated
from the part layout that uses them, and the renders are produced by `tool/skill_forge/raster.py`
reading the GLB that ships.

- Author: this project (no third-party contributor).
- Licence: the repository's existing terms; no third-party licence applies to these files because
  no third-party work is contained in them.
- No motion, audio or font data is included. No network access, no `numpy`, no Blender and no
  image editor are needed to rebuild the set: `python3 tool/build_skill_foci.py` is the whole build.
- The accent colours the props glow with are the same linear RGB values `scripts/visuals/effect_director.gd`
  already uses for each skill's cast ring, so the set adds no new palette entry.
- Source of the three shared reference textures the cast effect still uses:
  `assets/scifi/fx/ring.png` (see `ASSET_LICENSES/kenney-particles.txt` for the pack it belongs to).
  It is unchanged and is not part of the authored focus set.

## Reproduction and verification

`data/models/skills/build_report.json` records the recipe, the SHA-256 of all nine authoring source
files, the SHA-256 of every output, and the measured triangle/vertex/island/byte counts per prop.
`tests/python/test_skill_foci.py` re-derives the asset contract from the shipped GLBs (attributes,
bounds, single material, UV range, socket nodes, unit normals with orthogonal tangents), re-hashes
every reported file, and checks the prop scenes, the skill resources' `icon` wiring and the
`assets/catalog.json` `gameplay_skills` entries.

Use `python3 tool/validate_assets.py` to verify the whole inventory (it re-parses each GLB and each
embedded PNG) and `python3 tool/validate_resources.py` for the scenes and resources. See
`docs/agent_skills/05_skill_focus_asset_recipe.md` for the recipe, the integration seams and the
pitfalls.
