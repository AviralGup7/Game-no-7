# Project audit — 2026-09-11

> **Android follow-up (2026-09-12):** see [ANDROID_HARDENING.md](ANDROID_HARDENING.md).
> The native counts below describe the September 11 revision, not validation of
> the later Android input/lifecycle changes. The shipping project uses Mobile;
> Compatibility is only a host-test backend. Export now explicitly preserves
> the Android renderer and validates the actual APK.


**Project:** Last Stand: Station Zero (`Game-no-7`)

**Scope:** gameplay and lifecycle code, input/UI, persistence, authored resources,
asset integrity, test infrastructure, Android build scripts and CI publication.

This audit fixes reproducible defects; it is not a guarantee that every possible
bug has been eliminated. In particular, native **assertion results** below are
not equivalent to an Android release or a graphical performance certification.

## Findings and repairs

### Persistence and controls — high priority

- **Valid saves rejected their own checksum.** Godot reads JSON integers as
  floats, and its default decimal formatting can also change fractional clocks
  during a round trip. The serializer now hashes the JSON-domain representation
  at full precision. Verification also checks the exact validated on-disk payload
  (excluding only its root integrity member), so legacy integer/decimal spelling
  remains recoverable without bypassing SHA-256. Tampered content still fails.
- **Large daily seeds lost their identity.** Run-build seeds now use decimal
  strings on disk and nonnegative int64 values in memory. Numeric counters remain
  bounded to JSON's exact-integer range. Already-rounded legacy numeric seeds
  cannot have their missing bits reconstructed.
- **Malformed settings/save values:** reject wrong-type booleans, malformed input
  records, non-finite numbers and invalid digest types before applying data.
  Corrupt JSON recovery uses the non-logging instance parser. Check buffered write
  errors before rename; keep deep-merge results independent of their inputs.
- **Conflicting defaults:** separate reload R from Skill 3 F, and camera I/J/K/L
  from movement arrows. Correct controller mappings to Godot 4 button indices.
  Schema 7 migrates only exact old factory bindings, preserving custom maps.
- **Remapping could partially erase working controls.** Validate the final batch
  before committing, include pending edits in conflict checks, replace rather than
  append indefinitely, deduplicate, preserve mouse bindings, and handle invalid
  actions/headless key labels safely.

### Combat, spawning and lifecycle — high priority

- **Fresh runs started on a spike strip.** Native execution reproduced an 8-point
  hit before any input. Finalize the player's pose after decoration and mode
  hazards exist. A deterministic search checks the decorated navigation grid,
  damaging hazard radii plus body clearance, and moving-hazard orbit paths; reset
  player/camera interpolation after relocation. Ordinary movement still interacts
  with hazards normally.
- **Forced and split spawns bypassed capacity/geometry rules.** Enforce caps,
  queue overflow, validate jitter/fallback positions against bounds/navigation,
  carry nav/interpolation setup into split children, reject malformed marker
  restrictions, and free rejected packed-scene roots.
- **Objective lifecycle:** remove old beacons and subscriptions on reconfiguration,
  parent before assigning world position, exclude corpses/queued enemies, and
  reject invalid deltas.
- **Damage reentrancy and non-finite mitigation:** validate without mutating the
  caller's payload; commit death before observers can re-enter damage/healing.
  Preserve health-changed → damaged → died notification order.
- **Bosses enraged while dying:** zero-health notifications no longer apply phase
  buffs, cleanse statuses or play another enrage cue.
- **Upgrade attribution/isolation:** carry source identity into damage results;
  offensive procs require the bound attacker; chain lightning excludes its first
  victim; stop trails/summons/pulses and unsubscribe at run end; rebind once for a
  replacement player and place summoned effects in world space after parenting.
- **Spatial Foley stayed disabled after a run reset.** A valid replacement listener
  now re-arms the spatial bank. Validate expired emitter references before casting
  or following them, including queued placements.
- **Delayed damage referenced freed shooters.** Projectiles, status ticks and
  damage-copy/area/weapon paths discard expired node references while retaining
  stable source IDs, so an in-flight hit can still resolve after its shooter dies.

### UI and resources

- Fix incompatible theme-font member names.
- Create score labels in their actual vertical container instead of trying to
  add already-parented labels again.
- Use an orientation-switchable `BoxContainer` for the portrait menu, not an
  `HBoxContainer` whose orientation cannot change.
- Avoid scene-tree lookups on detached joystick/performance-monitor fixtures.
- Replace high-codepoint escapes in authored resources with literal UTF-8.
  Native 4.4.1 reproduced errors from the escapes; the old ASCII-only validator
  and authoring advice enforced the wrong rule. Correct both and test the rule.

### Tests, build tooling and publication

- Add registered native regression suites for input/save boundaries, runtime
  spawning/objectives, combat ownership/death, expired sources and lifecycle.
- Reject missing, malformed, empty and non-boolean test results. Log suite names.
  Validate process status **and** engine errors **and** a nonempty success summary.
- Deliberate negative unit tests use exact, counted, bounded expected-error blocks.
  They are not a blanket engine-error whitelist and are disabled for other phases.
- Correct obsolete melee-only content expectations, hidden-HUD touch fixtures,
  three-bank audio inspection, controlled projectile baselines and locomotion
  fixtures that assumed an obstacle-free authored spawn. Keep lifecycle listener
  expectations aligned with actual teardown; bound audio sweep batches.
- Free detached test-owned Nodes and drain 2D/3D audio before test shutdown.
- Prune generated/hidden/`.gdignore` directories from the scene-path scanner.
- Share the exact engine/template pin. Stage and validate template archives;
  reject traversal, symlinks and version mismatch; do not overwrite customized
  Android build trees. Support documented signing aliases without writing secrets.
- Isolate HOME **and** XDG paths for save-mutating tests (macOS does not use XDG
  alone). Use a portable Python timeout with process-group cleanup.
- Record build failures, including invalid initial configuration, instead of
  leaving a stale success report or APK.
- Diagnostic APK generation may continue after a native-test failure, but release
  publication requires offline validation, native validation and export success.
- Run official-engine CI checks using a real Compatibility renderer under
  Xvfb/Mesa, rather than hiding Godot 4.4.1 dummy-renderer errors. The launcher has
  command-selection regression tests; this sandbox cannot validate Mesa rendering.

## Validation evidence

Raw logs and strict-checker results are retained in
[`docs/godot-runs/audit-2026-09-11/`](godot-runs/audit-2026-09-11/README.md).
All native engine processes listed below exited 0; the engine limitation below
explains why their strict error-channel gates are not reported as green.

| Check | Result |
|---|---|
| Python unit/regression suite | 1,074 tests passed |
| GDScript lint | Passed |
| Shell syntax / whitespace checks | Passed; no tracked conflict markers found |
| Offline contract gates | Passed: 163 resources; 200 classes / 9 autoloads; 201 guards; 286 GDScripts; 19 scenes / 175 paths; 949 format uses |
| Locked assets and inventory | 265/265 locks (49.89 MiB); 128 models, 135 PNGs, 46 audio files, 2 fonts |
| Native unit/integration assertions | 1,459 checks, 0 failed |
| Native imported-resource checks | 311 resources, 0 failures |
| Native player checks | 155 checks, 0 failed |
| Native UI, fresh + existing profile | 2,638 checks per profile, 0 failed in both |
| Real-game menu/run/pause/death/restart flow | 197 checks, 0 failed |
| Five-loop lifecycle stress | 531 checks, 0 failed |
| Systems/UI/audio/save stress | 296 checks, 0 assertion failures |
| Six-minute scripted soak | 59 checks, 0 failed; 360-second drive plus restart |

### Native engine and strict-log limitation

The sandbox had no usable Godot binary and could not reach the release-binary
CDN. The tagged **4.4.1-stable** source was compiled locally as an editor with
headless/dummy rendering and audio, no GPU/window-system backends, and no
fontconfig. Logging-only instrumentation was used to locate GDScript call sites;
project/runtime semantics were not patched out of the engine.

This custom build reports `ERROR: No renderers available.` at startup. Its cold
editor import also reports unavailable system-font support and null dummy-preview
textures; three native unit teardown paths report null dummy materials. These
messages are **not ignored by the committed strict log checker**. Therefore this
audit distinguishes passing native assertions from a fully passing graphical
release gate. `scripts/run_godot.sh` and CI use the official engine with a real
Compatibility renderer (Xvfb/Mesa on display-less Linux) to avoid relying on the
dummy renderer. That graphical path still needs execution in CI/on a suitable host.

## Remaining validation / limits

- No Android SDK/export/signing, installation, physical touch/controller/haptics,
  real audio output, or device pause/kill/power-loss durability test was performed.
- No GPU screenshot/visual-quality, phone FPS, thermal/battery or memory benchmark
  is claimed. The unoptimized headless engine's frame-rate measurements are not
  representative of a device. The soak uses a deliberately invulnerable player.
- Workflow YAML was structurally parsed; GitHub Actions and actionlint were not
  executed here. The next CI run must validate the software-renderer setup and APK.
- Static gates still report explicitly classified dynamic/unsafe accesses
  (28 API and 310 signal warnings). A
  clean gate is not proof that every dynamic call or every authored mode has run.
- The repository had no `.uid`/`.import` sidecars before this audit. Audit-generated
  default sidecars and caches are not intended as source changes; preserve the
  existing path-based checkout and import before running native checks.

See [BUILD.md](BUILD.md) for reproducible commands and [SAVE_RESILIENCE.md](SAVE_RESILIENCE.md)
for the on-device fault-test checklist. Historical logs elsewhere in `docs/godot-runs/`
are not evidence of this audit's final result.
