# Hero fidelity — Arena Warden

**9 September 2026 · implementation + review notes**

## What changed

The live player now selects `assets/characters/warden/ArenaWarden.glb`, rather
than merely changing the KayKit Knight's roughness. The new visible mesh is a
project-authored, adult-proportioned armored humanoid: closed sallet with a sight
slit, layered pauldrons, breastplate/fauld, articulated gloves, shaped greaves,
boots, mail and a split blue tabard. A narrow, beveled **Warden Gladius** replaces
the starter weapon's broad palette-kit blade.

This is **a proportional PBR armored hero, not a scanned/photoreal human**. There
is no face/facial rig, sculpted skin, motion capture or simulated cloth. Enemy
meshes and the other eight weapon mappings remain the existing approved kit.
Those are still visible style differences against the photo-PBR arena.

### Actual shipped budget

| Item | Measured |
|---|---:|
| Hero triangles | 34,860 |
| Hero exported vertices (including UV/part seams) | 22,001 |
| Deform bones | 23, no source IK/control helpers |
| Body mesh surfaces | 1 opaque surface |
| Texture maps | 3 shared 1024 × 1024 PNGs: base color, tangent normal, ORM |
| Animation clips | All 76 donor names retained; 22 required by the live animator |
| Hero GLB | 3,409,124 bytes |
| Entire hero + gladius + shared map bundle | 5,169,091 bytes (~4.93 MiB) |
| Runtime height | 1.84 m; original collision capsule stays 1.9 m × 0.45 m radius |

The starter blade shares the body atlas but is a separate socket-mounted mesh.
"One body surface" is **not** a total draw-call claim: equipment, shadows, hit
flash overlays and the arena still cost draws. No Android FPS claim is made.

## Retarget, not animation aliases

`tool/build_hero.py` + `tool/hero/` reproduce the committed assets **offline**.
The already-reviewed CC0 KayKit Knight supplies rest axes and motion only. None
of its visible meshes, helmet, face, cape or palette atlas is copied into the
new hero.

1. Author a metric target skeleton with adult femur/tibia, torso, arm and head
   proportions while keeping the donor's local rest axes.
2. Build fresh geometry, skin weights (at most four influences) and inverse bind
   matrices. Preserve `handslot.l` and `handslot.r` for all nine weapon mappings.
3. Resample all 76 clips at 30 Hz using shortest-arc quaternion interpolation.
   Non-root translations use the **new** rest offsets; no animated limb scaling.
4. Condition walking/running swing-leg lift with a fixed-length, offline two-bone
   solve. Keep foot orientation and the donor's stride direction; do not run IK
   or a retargeter in the game. Playback uses the new 1.6 m walk / 2.1 m run cycles.
5. Remove planar root travel and strip net pelvis travel while retaining weight
   shifts. Bake skin-derived floor support; jump clips retain their airtime.
6. Every clip keys all deform translations/rotations, so interrupted poses reset
   cleanly. The donor's zero-duration pose assets receive a one-frame hold rather
   than invalid duplicate timestamps. These are not substituted for combat clips.

### Runtime behavior

- `HeroRigContract` gates **all** live locomotion, combo, heavy, dual, ranged,
  reload, four dodge, hurt, death, skill and victory selections plus hand sockets.
- Mounting is transactional: Warden → complete KayKit fallback → original
  primitive. An importable model lacking combat clips does not pass the gate.
- `HdMaterials` preserves authored base/normal/ORM maps and unit scalar factors;
  the old palette-kit clamps must not make metal plastic or cloth metallic. The
  material pass also uses Godot 4.4.1's actual `metallic_specular` property (the
  previous `specular` spelling was not a valid BaseMaterial3D property).
- The Warden has baked idle motion, so no whole-body breathing/float tween is
  applied, including after death/respawn. Idle autoplay now duplicates its
  animation library instead of mutating shared imported resources.
- The bow receives a per-weapon source-axis correction without moving its centre
  grip; ranged equipment uses the left socket and dual wield uses both.
- Left/right dodge selection is corrected in the Godot -Z-forward coordinate
  frame, including rotated player facings.
- `PlayerAnimation` still follows **WeaponInstance windup/recovery** and the
  existing 0.32 contact fraction. No animation applies damage, grants immunity,
  translates the physics body, resizes collision or changes balance/content IDs.

## Rebuild and verify

No authoring packages are needed for the game, import or normal CI. To rebuild:

```sh
python3 -m venv .venv
.venv/bin/pip install -r tool/hero/requirements.txt
.venv/bin/python tool/build_hero.py

# Rebuild elsewhere for a byte-for-byte comparison on the same pinned toolchain:
.venv/bin/python tool/build_hero.py --output-dir .cache/hero-rebuild
```

The output `build_report.json` is the **derived-asset provenance lock**: recipe
hashes, unchanged CC0 donor hash, every generated file hash, measured inventory
and clip durations. It is deliberately separate from `assets/manifest.json`;
there is no fabricated download URL, and the downloader cannot overwrite authored
art. `tool/derived_assets.py` rejects missing, changed, unreviewed or unlicensed
inputs/outputs. A changed recipe requires an explicit rebuild.

```sh
python3 scripts/download_assets.py --verify
python3 tool/validate_assets.py  # includes derived hashes and hero contract
python3 tool/validate_hero.py
python3 -m unittest discover -s tests/python -p test_hero_fidelity.py -v

# With the pinned Godot 4.4.1 installed:
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/validate_asset_imports.gd
bash tool/test_hero_runtime.sh   # isolated save profile, real Player lifecycle
```

Native tests cover selected model/fallback, missing clips/sockets, private PBR
materials, finite sampled bone poses, death → idle reset, no bob/physics drift,
all nine equipment mappings, contact timing, interruption, reload and respawn.
The runtime check is wired into the Godot CI job and Android build script.

## Visual review

```sh
python3 tool/serve_art.py --port 8000
```

The root page opens `tool/hero_preview.html`. It loads the **actual shipped GLBs,
clips, socket equipment and arena HDRIs**, with orbit/zoom, turntable, KayKit
comparison at equal height, clip scrubbing, speed control and all three arena
lighting environments. `tool/hd_preview.html` also selects the Warden. The missing
`three.core.js` dependency of the existing pinned three.js viewer was restored.

This viewer is three.js, **not a Godot gameplay capture**. It is useful for
silhouette, skin/normal, clipping and animation review, not for certifying Godot
import behavior or mobile frame time.

## Validation status and limits

- All five generated outputs and their report reproduced byte-identically on the
  pinned local Python toolchain.
- **19 focused Python tests pass**; asset/hash/format/resource validation passes.
- Khronos validator: **both new models have 0 errors and 0 warnings**. Entire kit:
  83 models, 0 errors, 49 existing warnings on the unchanged upstream models.
- Changed GDScripts pass `gdlint`. Browser review covers idle, locomotion, attack,
  directional dodge, death, equipment and the before/after comparison. The
  browser smoke test sampled all 22 required clips, attached all nine weapons
  (including both dual-wield sockets), and loaded all three lighting environments
  with no page or resource errors. Desktop and narrow-screen layouts were inspected.
- Initial verification reproduced **seven pre-existing camera/architecture
  failures** in an untouched archive of baseline
  `aedf4d4818253a4ca847be4a7f879a2816452c63`. After incorporating the subsequent
  fixes from `main`, the complete Python suite passes **415/415 tests**. No
  failure allowlist or test suppression was added.
- **Native Godot/Android validation has not run locally**: the sandbox has no
  installed engine and official engine download hosts fail TLS. Added native
  gates are not presented as passed. No APK was built and no phone was profiled.
- Still requires Godot/device visual acceptance: foot slide during acceleration,
  extreme pose armor/tabard intersections, two-hand grip alignment across all
  weapons, texture mip/compression behavior and full-wave frame time. Future
  photoreal art can reuse the same explicit clip/socket gate rather than losing
  combat coverage in a model-only swap.
