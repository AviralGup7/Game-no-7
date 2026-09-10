# Last Stand: Arena

A polished, expandable **third-person arena survival / action game** for Android,
built with **Godot 4.x** and **GDScript** (landscape, touch controls, mobile-optimised
rendering).

You fight waves of enemies in a compact arena. Enemies pursue and attack; you move
with a virtual joystick, attack with a melee weapon, dodge, pick upgrades between
waves, and chase a high score. When you fall — or win — you see your run summary
and can instantly restart.

> **Project status — gameplay loop overhaul (see `CHANGELOG.md`).** Beyond the
> Phase 1–4 foundation and meta game, the loop now includes: **5 game modes**
> (Standard, Boss Rush, Survival, Challenge, Campaign) with distinct objectives and
> wave scripts; **8 transformative upgrades** (chain lightning melee, fire/frost
> dodge trails, kill summons, thorn nova, execute, lifesteal burst, static aura);
> **differentiated arenas** (pressure plates, orbiting movers, denser hazard grids);
> a **narrator + campaign beat sheet**; and a **prestige endgame** (permanent score/
> currency mults, titles, cosmetics). Still ships 8 enemy archetypes, switchable
> weapons, skills, mutators, armory, achievements, and daily challenge — and
> enemies now fight like individuals: perception (sight/hearing/reaction/memory),
> deterministic personalities, maneuver-based pursuit, pack awareness. Nothing
> walks through objects: a shared nav grid routes AI around the same obstacles
> (pillars, central landmark) that physics collides with.
> All content stays data-driven (`.tres` under `res://data/`) and headless-tested.
> See `docs/ENEMY_AI_RESEARCH.md`.

---

## Key principles

- **Data-driven content.** New enemies, arenas, upgrades, weapons, cameras and audio
  are added as typed `.tres` resources under `res://data/`, discovered + validated by
  the `ContentRegistry` autoload. Core systems are not rewritten to add content.
- **One collision contract.** Every 3D layer/mask bit comes from
  `CollisionLayers` (`scripts/core/collision_layers.gd`) — bodies *and* spatial
  queries — and `tests/python/test_regress_collision_contract.py` pins the authored
  scene bits, the reserved layers and the deliberate no-body-block decision to it.
  Movement integrates in `_physics_process` with `physics/common/physics_interpolation`
  enabled, so the fixed 60 Hz tick can never alias against the render rate.
- **Deterministic + testable.** Score, wave generation, upgrade selection, save
  validation and spawn logic expose pure/deterministic functions exercised headlessly.
- **Graceful failure.** Missing optional assets, a corrupted save, or an invalid
  content resource produce diagnostics + fallback, never a crash.
- **Legally safe assets.** Every third-party asset is logged with its licence in
  `THIRD_PARTY_ASSETS.md` / `AUDIO_MANIFEST.md`; no unattributed or unclear assets.
- **Reproducible.** Godot version, Android requirements, build + CI steps are pinned
  in `docs/BUILD.md`; `scripts/build_android.sh` and the GitHub Actions workflow build
  from a fresh clone.

---

## Getting started (development)

1. Install the pinned Godot 4.x editor (see `docs/BUILD.md` for the exact version).
2. Clone this repository.
3. `godot --path . --editor` to import assets, then press **F5** (or run the
   `scenes/main/main.tscn` scene).
4. Keyboard dev controls: `WASD`/arrows to move, `Space`/`Enter` to attack,
   `Shift` to dodge, `Q`/`E`/`R` for skills, `Tab` to switch weapons, `Esc` to pause
   (attack/dodge/skills/weapon-switch are remappable in Settings).
5. On an Android device/emulator, touch: left-side floating joystick, right-side
   attack + dodge + weapon-switch buttons, tappable skill bar.

Run the headless unit tests:

```bash
godot --headless --path . --import          # first run: import + generate caches
godot --headless --path . --script res://tests/run_tests.gd
```

Offline gates (no Godot binary needed — these run in CI's `validate-resources`
stage and anywhere python3 is available):

```bash
python3 -m unittest discover -s tests/python     # 820 unit + regression guards
python3 tool/check_typed_arch.py                 # typed-architecture contract
python3 tool/validate_guards.py                  # inlined-guard needles
python3 tool/check_engine_api.py                 # engine-API contract: every typed member
                                                 # access + .tscn/.tres property checked against
                                                 # the pinned Godot's own ClassDB
                                                 # (tool/godot_api_manifest.json)
python3 tool/check_scene_paths.py                # scene-path contract: every get_node/NodePath
                                                 # literal resolved against the actual .tscn node
                                                 # trees (+ runtime names, autoloads); `as` casts
                                                 # checked against declared node classes
```

---

## Downloaded 3D asset kit

The reviewed asset library contains **9 downloaded rigged/animated character models,
81 downloaded models, photo-PBR arena texture sets, real HDRI panorama skies,
UI/particle textures, 2 fonts, 29 sound effects and 5 music loops**
(~49.08 MiB of locked downloads), plus the **Arena Warden hero and PBR gladius**
(~4.93 MiB of checksum-locked authored assets). All source files have pinned provenance,
SHA-256 checksums and preserved licences.

**Integrated — HD realism pass:** the arena was rebuilt with photo-PBR rock floor,
aged-brick walls, marble dais/cornices, an iron-banded wooden gate, corner towers
and flickering torch sconces; each arena gets its own real Poly Haven CC0 HDRI
sky (sunrise / sunset / moonlit) with image-based lighting; 2× MSAA, 8×
anisotropic filtering, high-quality PCF shadows and glow are enabled; every
character, enemy and arena prop receives a role-tuned PBR material pass
(`HdMaterials`). Earlier work — six pickup models, approved characters/enemies on
live actors, KayKit dungeon props, per-arena themes, pooled VFX and registered
SFX/music — remains. See the [asset catalogue](docs/ASSET_CATALOG.md) and
[quality audit](docs/ASSET_AUDIT.md) for exact additions, replacement selections,
upstream checks and limitations. **Hero fidelity:** the live player now uses a new human-proportioned PBR armored
Warden, with all **76 clips retargeted**, 23 deform bones, one body surface, shared
1K PBR maps and a matching gladius. The existing attack timing, four dodges,
hurt/death, casts and hand sockets are retained; incomplete imports safely fall
back to KayKit. This is authored armored art, **not a scanned photoreal human**;
enemy meshes remain the approved stylized set. See [hero fidelity](docs/HERO_FIDELITY.md)
for the reproducible recipe, compatibility gate, review tool and validation limits.

```bash
python3 scripts/download_assets.py --verify  # offline integrity check
python3 tool/validate_assets.py              # downloads + derived art + combat coverage
python3 tool/serve_art.py --port 8000         # optional live hero comparison / clip viewer
# If files are missing: python3 scripts/download_assets.py
```

## Repository map

```
assets/        reviewed 3D models, animations, textures, UI, fonts, audio + source lock
scenes/        main, arena, player, ui (canonical scene tree)
scripts/       core autoloads + per-system controllers/state
data/          typed .tres content: enemies, upgrades, arenas, cameras, weapons,
               skills, status, pickups, waves, audio
tests/         unit suites + doubles + run_tests.gd (headless runner)
docs/          BUILD.md, ART_STYLE.md, EXTENDING.md
tool/          repository/resource validation tooling
scripts/       build automation (build_android.sh, download_assets.py)
.github/       CI workflow that builds + tests from a fresh clone
```

See `docs/EXTENDING.md` for how to add a new enemy / upgrade / arena / weapon / cue
/ UI panel / test.

## Documentation

| Doc | Purpose |
|---|---|
| `docs/BUILD.md` | Godot/Android versions, export + signing, build/test commands |
| `docs/ANDROID_PERMISSIONS.md` | why the app requests no Android permissions + how to verify |
| `docs/ART_STYLE.md` | Visual style, palette, scale, lighting, UI + future content rules |
| `docs/HERO_FIDELITY.md` | New Warden, retarget recipe, complete clip/socket gate + validation limits |
| `docs/ASSET_CATALOG.md` | Downloaded asset inventory, file/role map, animation names + integration status |
| `docs/EXTENDING.md` | Step-by-step extension guides |
| `THIRD_PARTY_ASSETS.md` | Visual asset licences + provenance |
| `AUDIO_MANIFEST.md` | Audio asset licences + provenance |
| `CHANGELOG.md` | Per-phase progress |
