# docs/ — index

Live operating docs first. Dated audits keep the numbers they executed; do not
rewrite those counts. Agent rules: [AGENTS.md](AGENTS.md). Shipping pitch:
[README.md](../README.md).

## Start here

| File | What it is |
|---|---|
| [AGENTS.md](AGENTS.md) | Architecture rules, **11 offline gates** with baseline outputs, CI, licensing, release tooling |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Typed component model, campaign composition, autoload policy, determinism, timing |
| [EXTENDING.md](EXTENDING.md) | How to add enemies, weapons, skills, modes, arenas — data, not core rewrites |
| [BUILD.md](BUILD.md) | Reproduce import, tests, Android export, APK checker, size report |
| [HARDENING.md](HARDENING.md) | Inlined runtime guards; DocCountTests pins 183 resources / 201 needles |
| [DEVICE_QA.md](DEVICE_QA.md) | Physical-device campaign + touch/lifecycle checklist |
| [RELEASE_NOTES_TEMPLATE.md](RELEASE_NOTES_TEMPLATE.md) | Next GitHub Release body (campaign stats + known limitations) |
| [ANDROID_PERMISSIONS.md](ANDROID_PERMISSIONS.md) | Offline + `VIBRATE` only (bundled in the APK) |
| [SAVE_RESILIENCE.md](SAVE_RESILIENCE.md) | On-device save fault checklist |
| [DEBUG_MODE.md](DEBUG_MODE.md) | Error-freeze overlay, session log, crash files |

## Campaign world

| File | What it is |
|---|---|
| [campaign/README.md](campaign/README.md) | Station Zero play flow, authored stats, validation status |
| [campaign/STATION_ZERO_MAP.svg](campaign/STATION_ZERO_MAP.svg) | Overview generated from the same JSON the game loads |

## Content / presentation reference

| File | What it is |
|---|---|
| [ART_STYLE.md](ART_STYLE.md) | Visual language, orientation, stretch |
| [ASSET_CATALOG.md](ASSET_CATALOG.md) | Live inventory vs `assets/manifest.json` / `assets/catalog.json` |
| [AUDIO_ENGINE.md](AUDIO_ENGINE.md) | Voice policy, buses, vertical stems |
| [CAMERA.md](CAMERA.md) | Rig modules, coordinator, profiles |
| [ENEMY_AI_RESEARCH.md](ENEMY_AI_RESEARCH.md) | Perception, nav grid, pack research |
| [HERO_FIDELITY.md](HERO_FIDELITY.md) | Arena Warden recipe, measurements, limits |
| [MINIMAP_RADAR.md](MINIMAP_RADAR.md) | Threat radar design |
| [PERFORMANCE_GOVERNOR.md](PERFORMANCE_GOVERNOR.md) | Frame-time tiers |
| [PLAYER.md](PLAYER.md) | Player contract, NaN/boot postmortems |

## Agent skills (authoring recipes)

| File | What it is |
|---|---|
| [agent_skills/README.md](agent_skills/README.md) | Index of the five skills |
| [agent_skills/01_codebase_architecture_and_rules.md](agent_skills/01_codebase_architecture_and_rules.md) | Typing, guards, gates |
| [agent_skills/02_texture_and_color_matching.md](agent_skills/02_texture_and_color_matching.md) | Texture / colour matching |
| [agent_skills/03_3d_asset_pipeline_from_ai_images.md](agent_skills/03_3d_asset_pipeline_from_ai_images.md) | 3D modules from authored images |
| [agent_skills/04_time_saving_tricks_and_pitfalls.md](agent_skills/04_time_saving_tricks_and_pitfalls.md) | Pitfalls |
| [agent_skills/05_skill_focus_asset_recipe.md](agent_skills/05_skill_focus_asset_recipe.md) | Skill-focus GLB recipe |

## Spatial / combat / visual audits (re-run 2026-09-12; live tools still apply)

| File | What it is |
|---|---|
| [GEOMETRY_AUDIT.md](GEOMETRY_AUDIT.md) | 13-category geometry integrity (see the 2026-09-13 correction banner) |
| [LEVEL_FLOW_AUDIT.md](LEVEL_FLOW_AUDIT.md) | 10-category spatial flow |
| [SHOOTER_READINESS_AUDIT.md](SHOOTER_READINESS_AUDIT.md) | 15-category cover-shooter readiness |
| [VISUAL_PERFORMANCE_AUDIT.md](VISUAL_PERFORMANCE_AUDIT.md) | 14-category visual/perf (see the 2026-09-13 correction banner) |
| [geometry_report.json](geometry_report.json) | Machine geometry report |
| [level_flow_report.json](level_flow_report.json) | Machine level-flow report |
| [shooter_report.json](shooter_report.json) | Machine shooter report |
| [visual_report.json](visual_report.json) | Machine visual/perf report |

## Historical audits (executed counts stay; banners only)

| File | Snapshot date |
|---|---|
| [CODE_QUALITY_AUDIT_2026-09-12.md](CODE_QUALITY_AUDIT_2026-09-12.md) | 2026-09-12 (1,138 Python / 175 resources) |
| [PROJECT_AUDIT.md](PROJECT_AUDIT.md) | 2026-09-11 (1,074 Python / 163 resources) |
| [ANDROID_HARDENING.md](ANDROID_HARDENING.md) | 2026-09-12 (1,099 Python) |
| [ANDROID_PERFORMANCE.md](ANDROID_PERFORMANCE.md) | 2026-09-08 (502 → 513 Python) |
| [ASSET_AUDIT.md](ASSET_AUDIT.md) | 2026-09-08 (222 locks / 37 tests) |
| [REFACTOR_PLAN.md](REFACTOR_PLAN.md) | typed-architecture overhaul (353 tests / 8 autoloads then) |
| [ui_redesign/README.md](ui_redesign/README.md) | UI redesign notes (427 tests then) |
| [../GAME_FORENSIC_AUDIT.md](../GAME_FORENSIC_AUDIT.md) | 2026-09-10 forensic audit (repo root, ~908 Python methods) |

## Texture contact sheets

| File |
|---|
| [texture_assets_contact_sheet.jpg](texture_assets_contact_sheet.jpg) |
| [texture_pbr_contact_sheet.jpg](texture_pbr_contact_sheet.jpg) |
| [texture_ui_contact_sheet.jpg](texture_ui_contact_sheet.jpg) |

## UI redesign previews

| File |
|---|
| [ui_redesign/ui_main_menu.png](ui_redesign/ui_main_menu.png) |
| [ui_redesign/ui_gameplay_hud.png](ui_redesign/ui_gameplay_hud.png) |
| [ui_redesign/ui_pause.png](ui_redesign/ui_pause.png) |
| [ui_redesign/ui_upgrade.png](ui_redesign/ui_upgrade.png) |
| [ui_redesign/ui_run_summary.png](ui_redesign/ui_run_summary.png) |

## Godot run logs (`docs/godot-runs/`)

Committed engine logs. They are historical evidence for the revision that
produced them, not proof of the current campaign world.

| File | What it is |
|---|---|
| [godot-runs/audit-2026-09-11/README.md](godot-runs/audit-2026-09-11/README.md) | How the 2026-09-11 native logs were captured |
| [godot-runs/audit-2026-09-11/SHA256SUMS.txt](godot-runs/audit-2026-09-11/SHA256SUMS.txt) | Checksums of that audit's logs |
| [godot-runs/audit-2026-09-11/assets.log](godot-runs/audit-2026-09-11/assets.log) | Native asset-import suite |
| [godot-runs/audit-2026-09-11/cold-import.log](godot-runs/audit-2026-09-11/cold-import.log) | First `--import` |
| [godot-runs/audit-2026-09-11/flow.log](godot-runs/audit-2026-09-11/flow.log) | `verify_flow.gd` |
| [godot-runs/audit-2026-09-11/loops.log](godot-runs/audit-2026-09-11/loops.log) | Five-loop stress |
| [godot-runs/audit-2026-09-11/offline-gates.log](godot-runs/audit-2026-09-11/offline-gates.log) | Offline contract gates |
| [godot-runs/audit-2026-09-11/player.log](godot-runs/audit-2026-09-11/player.log) | Player runtime suite |
| [godot-runs/audit-2026-09-11/python.log](godot-runs/audit-2026-09-11/python.log) | Python unittest discover |
| [godot-runs/audit-2026-09-11/soak.log](godot-runs/audit-2026-09-11/soak.log) | Six-minute soak |
| [godot-runs/audit-2026-09-11/strict-log-checks.txt](godot-runs/audit-2026-09-11/strict-log-checks.txt) | Strict log-checker results (expected rejects) |
| [godot-runs/audit-2026-09-11/systems.log](godot-runs/audit-2026-09-11/systems.log) | Systems stress |
| [godot-runs/audit-2026-09-11/ui-existing.log](godot-runs/audit-2026-09-11/ui-existing.log) | UI suite, existing save |
| [godot-runs/audit-2026-09-11/ui-fresh.log](godot-runs/audit-2026-09-11/ui-fresh.log) | UI suite, fresh save |
| [godot-runs/audit-2026-09-11/unit.log](godot-runs/audit-2026-09-11/unit.log) | `run_tests.gd` |
| [godot-runs/diagnostics-fix-report.md](godot-runs/diagnostics-fix-report.md) | Godot 4.7.2 diagnostics remediation (dated) |
| [godot-runs/diagnostics-4.7.2-check.log](godot-runs/diagnostics-4.7.2-check.log) | 4.7.2 check pass |
| [godot-runs/diagnostics-4.7.2-editor.log](godot-runs/diagnostics-4.7.2-editor.log) | 4.7.2 editor pass |
| [godot-runs/diagnostics-4.7.2-import.log](godot-runs/diagnostics-4.7.2-import.log) | 4.7.2 import |
| [godot-runs/diagnostics-4.7.2-lsp-editor.log](godot-runs/diagnostics-4.7.2-lsp-editor.log) | LSP editor |
| [godot-runs/diagnostics-4.7.2-lsp.err](godot-runs/diagnostics-4.7.2-lsp.err) | LSP stderr |
| [godot-runs/diagnostics-4.7.2-lsp.txt](godot-runs/diagnostics-4.7.2-lsp.txt) | LSP diagnostics dump |
| [godot-runs/diagnostics-4.7.2-summary.txt](godot-runs/diagnostics-4.7.2-summary.txt) | Diagnostics summary |
| [godot-runs/diagnostics-4.7.2-tests.log](godot-runs/diagnostics-4.7.2-tests.log) | 4.7.2 headless tests |
| [godot-runs/diagnostics-4.7.2-wae-import.log](godot-runs/diagnostics-4.7.2-wae-import.log) | Warnings-as-errors import |
| [godot-runs/diagnostics-4.7.2-wae-probe.log](godot-runs/diagnostics-4.7.2-wae-probe.log) | Warnings-as-errors probe |
| [godot-runs/diagnostics-4.7.2-wae-tests.log](godot-runs/diagnostics-4.7.2-wae-tests.log) | Warnings-as-errors tests |
| [godot-runs/import.log](godot-runs/import.log) | Older import log |
| [godot-runs/run_tests.log](godot-runs/run_tests.log) | Older `run_tests.gd` log |

Root-level licence/audio records (not under `docs/`):
[THIRD_PARTY_ASSETS.md](../THIRD_PARTY_ASSETS.md),
[AUDIO_MANIFEST.md](../AUDIO_MANIFEST.md),
[ASSET_LICENSES/README.md](../ASSET_LICENSES/README.md),
[CHANGELOG.md](../CHANGELOG.md).
