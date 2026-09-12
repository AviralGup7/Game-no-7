# Last Stand: Station Zero

An Android **third-person campaign shooter**, built with **Godot 4.4.1-stable**
and **GDScript**. Landscape, touch-first, fully offline.

Explore **one fixed, connected station** rather than starting an arena or choosing
a seed. Travel from the docks through transit, hydroponics, the foundry, cargo, the
reactor, the medical ward, habitat, salvage, the archive, comms and command; restore
station systems, recover evacuation manifests and open the way home.
There are no chapter-loading gates between districts.

- **864 × 672 m world footprint** (6.1× the original station), twelve districts and
  thirteen story objectives.
- **Thirty-two finite encounters / 96 authored enemies**, including a three-phase
  commander. Defeated enemies stay defeated across checkpoint retries.
- **Checkpoints and persistent campaign progress**: objectives, credits, upgrades,
  XP and equipped weapons/skills survive Continue. Green rest pads refill health
  and stamina when safe; completed missions also advance your checkpoint.
- **Android budgets**: at most 18 active enemies, two activations per streaming tick
  and three visible district batches. Instanced floor modules and merged static
  collision keep the connected paths loaded without simulating every district.
- Native touch **INTERACT**, **MAP**, pause, move, aim/fire, reload, dodge, swap and
  skills. The station chart shows the current objective and a navigable route.

[Campaign guide and validation status](docs/campaign/README.md) ·
[Authored station overview](docs/campaign/STATION_ZERO_MAP.svg)

> **Implementation status:** the default scene is now
> `scenes/campaign/station_zero.tscn`. Offline topology/content and regression checks
> pass; the new native campaign suite is registered in CI but has **not run in the
> current workspace**, which has no Godot/Android toolchain or device. This is not
> an APK/device certification. Existing audit evidence predates the campaign.
>
> The old arena/mode scenes remain as development/regression fixtures, not the
> shipping menu. Existing firearm/robot resources, combat and Android fixes are
> reused. Legacy content IDs (for example `gladius`, the Pulse Carbine) and saved
> settings/Armory purchases remain compatible through additive save schema 8.

---

## Key principles

- **Data-driven content.** New enemies, upgrades, weapons, cameras and audio
  are added as typed `.tres` resources under `res://data/`, discovered + validated by
  the `ContentRegistry` autoload. The fixed world lives in `data/campaign/station_zero.json`;
  its physics, navigation and station chart read the same coordinates.
- **One collision contract.** Every 3D layer/mask bit comes from
  `CollisionLayers` (`scripts/core/collision_layers.gd`) — bodies *and* spatial
  queries — and `tests/python/test_regress_collision_contract.py` pins the authored
  scene bits, the reserved layers and the deliberate no-body-block decision to it.
  Movement integrates in `_physics_process` with `physics/common/physics_interpolation`
  enabled, so the fixed 60 Hz tick can never alias against the render rate.
- **Authored + testable.** World topology, stable encounter IDs, once-only rewards
  and save migration have offline/native regression suites. Native/device execution
  is reported separately from static validation.
- **Graceful failure.** Missing optional assets, a corrupted save, or an invalid
  content resource are handled with diagnostics and fallbacks rather than silently ignored.
- **Legally safe assets.** Every third-party asset is logged with its licence in
  `THIRD_PARTY_ASSETS.md` / `AUDIO_MANIFEST.md`; no unattributed or unclear assets.
- **Reproducible.** Godot version, Android requirements, build + CI steps are pinned
  in `docs/BUILD.md`; `scripts/build_android.sh` and the GitHub Actions workflow build
  from a fresh clone.

---

## Build and use the Android app

The shipping target is **Android / ARM64**, using the **Mobile renderer**, not a
PC game. Install Godot 4.4.1-stable with matching export templates, Java 17, and
Android SDK platform/build-tools 34 (details in [BUILD.md](docs/BUILD.md)).

```bash
bash scripts/build_android.sh
# Produces build/LastStandArena-debug.apk (debug-signed for sideload testing).
# The build checks the real APK's package, SDK levels, native ABI, permissions,
# Mobile-renderer metadata and signature; it does not just check ZIP size.
ANDROID_SERIAL=<device-serial> bash scripts/device_qa.sh
```

On the phone, move with the left stick, hold/drag FIRE to shoot/aim, and tap
RELOAD, DODGE, SWAP or a READY skill. INTERACT appears near a console or supply locker; MAP shows the connected
station. Skills, MAP, INTERACT and PAUSE handle independent touch fingers; no keyboard is required. Android Back opens/closes pause and navigates
screens. Complete [DEVICE_QA.md](docs/DEVICE_QA.md) on a real phone: host tests are
not proof of Android input, driver, thermal or power-loss behavior.

### Optional development-host preview

Open `project.godot` in the pinned Godot editor and press **F5** after import.
The Compatibility/Xvfb helper is only for host import previews and regression
tests. APK export stays headless and preserves the Android Mobile renderer.

<details>
<summary>Keyboard / controller development controls (not required on Android)</summary>

`WASD`/arrows move, left mouse/`Space`/`Enter` fire, `R` reloads, `Shift` dodges,
`Q`/`E`/`F` cast skills, `G` interacts, `M` opens the station map,
`Tab` switches weapons and `Esc` pauses. `J`/`L` orbit
camera yaw, `I`/`K` pitch. These optional bindings are remappable on the host;
see [PLAYER.md](docs/PLAYER.md) and [SAVE_RESILIENCE.md](docs/SAVE_RESILIENCE.md).

</details>

Run native tests with an **isolated profile** and the strict log checker; see
[BUILD.md](docs/BUILD.md#validation--tests) for the copyable command. Do not run
save-mutating UI/game-flow tests against your normal player profile. A zero Godot
exit code alone is not sufficient: script errors can otherwise look like a pass.

Offline gates (no Godot binary needed — these run in CI's `validate-resources`
stage and anywhere python3 is available):

```bash
python3 tool/validate_campaign.py               # fixed-world topology + clearance
python3 -m unittest discover -s tests/python     # unit + regression guards
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
python3 tool/check_string_formats.py             # string-format contract: every `"..." %` use
                                                 # verified against the engine's String::sprintf
                                                 # rules (arity, placeholder syntax, literal types)
python3 tool/check_signals.py                    # signal contract: every signal name + emit arity
                                                 # resolved against declaring classes (self chains,
                                                 # autoloads, engine signals); connected callables
                                                 # checked for parameter compatibility
```

---

## Asset library and provenance

The runtime uses the robot and firearm models in `assets/scifi/`. The reviewed
library also retains the earlier downloaded character/arena kits, authored Warden
rig, PBR textures, HDRI skies, fonts, effects and music. Source files are
checksum-locked with provenance and preserved licences; the old Warden/gladius
art reports describe that asset lineage, **not the current live player loadout**.

See [the asset catalogue](docs/ASSET_CATALOG.md), [asset audit](docs/ASSET_AUDIT.md)
and [hero rig tooling](docs/HERO_FIDELITY.md). The inventory and lock verifiers
below are the source of truth for current counts and sizes. Headless import tests
check structure and animation contracts, not visual quality or phone frame rate.

```bash
python3 scripts/download_assets.py --verify  # offline integrity check
python3 tool/validate_assets.py              # downloads + derived art + combat coverage
python3 tool/serve_art.py --port 8000         # optional live hero comparison / clip viewer
# If files are missing: python3 scripts/download_assets.py
```

## Repository map

```
assets/        reviewed 3D models, animations, textures, UI, fonts, audio + source lock
scenes/        campaign (shipping), player, ui; main/arena legacy test fixtures
scripts/       core autoloads + per-system controllers/state
data/campaign/ authored JSON coordinates, checkpoints, finite encounters and missions
data/          typed .tres content: enemies, upgrades, arenas, cameras, weapons,
               skills, status, pickups, waves, audio
tests/         unit suites + doubles + run_tests.gd (headless runner)
docs/          canonical guides (BUILD, ARCHITECTURE, EXTENDING, ART_STYLE) +
               per-system notes (camera, player, audio, enemy AI, performance,
               Android, assets, saves, minimap)
tool/          repository/resource validation tooling
scripts/       build automation (build_android.sh, download_assets.py)
.github/       CI workflow that builds + tests from a fresh clone
```

See `docs/EXTENDING.md` for how to add a new enemy / upgrade / arena / weapon / cue
/ UI panel / test.

## Documentation

| Doc | Purpose |
|---|---|
| `docs/campaign/README.md` | Connected world, persistence, authoring and validation status |
| `docs/BUILD.md` | Godot/Android versions, export + signing, build/test commands |
| `docs/ARCHITECTURE.md` | Systems map, ownership, determinism, timing + hardening contracts |
| `docs/EXTENDING.md` | Step-by-step extension guides (enemy / upgrade / arena / weapon / cue / UI) |
| `docs/ART_STYLE.md` | Visual style, palette, scale, lighting, UI + future content rules |
| `docs/ANDROID_PERMISSIONS.md` | VIBRATE-only permission policy + how to verify |
| `docs/ANDROID_PERFORMANCE.md` | Mobile performance posture + adaptive quality governor |
| `docs/PERFORMANCE_GOVERNOR.md` | Frame-time governor algorithm write-up |
| `docs/DEBUG_MODE.md` | Debug-mode error trap (freeze + copyable report) |
| `docs/DEVICE_QA.md` | On-device play checklist |
| `docs/PROJECT_AUDIT.md` | Project-wide audit fixes, regression evidence and remaining validation limits |
| `docs/HARDENING.md` | Hardening pass summary + pinned contracts |
| `docs/PLAYER.md` | Player contract + movement/startup stability postmortems |
| `docs/CAMERA.md` | Modular third-person camera rig + design principles |
| `docs/ENEMY_AI_RESEARCH.md` | Enemy AI design ("feels human") + robustness hardening |
| `docs/AUDIO_ENGINE.md` | SFX voice management, click-safe playback, music ownership |
| `docs/MINIMAP_RADAR.md` | Minimap/radar design |
| `docs/SAVE_RESILIENCE.md` | Save backup generations, migration + corruption recovery |
| `docs/ASSET_CATALOG.md` | Downloaded asset inventory, file/role map, animation names + integration status |
| `docs/ASSET_AUDIT.md` | Asset quality audit + limitations |
| `docs/HERO_FIDELITY.md` | Warden, retarget recipe, complete clip/socket gate + validation limits |
| `docs/REFACTOR_PLAN.md` | Typed-architecture refactor plan |
| `THIRD_PARTY_ASSETS.md` | Visual asset licences + provenance |
| `AUDIO_MANIFEST.md` | Audio asset licences + provenance |
| `CHANGELOG.md` | Per-phase progress |
