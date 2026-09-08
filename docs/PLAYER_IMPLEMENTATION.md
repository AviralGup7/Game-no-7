# Agent 1 — player integration

## Scope

Player commands, motion, presentation and feedback only. No changes to GameRoot,
EventBus, progression, saves, touch UI, enemy AI, camera rig, hitstop manager,
AudioManager, or shared ModelVisual implementation.

The only shared combat edits are small changes to `WeaponInstance` and
`WeaponManager`: preserve ammo/recovery on cancellation, cancel outgoing swings
on switch, advance holstered cooldown/reload timers, and emit the existing reload
signal when an empty-magazine attack starts a reload automatically.

## Features and tuning

- `scenes/player/player.tscn` instances the supplied Knight, with its real skeleton
  and animations. Capsule collision remains independent of art; the model faces
  local -Z and uses a 0.75 cosmetic scale. Floor snap and safe margin are explicit.
- `PlayerAnimation` handles idle, analog walk/run, combo swings, weapon-specific
  melee styles, ranged release/reload, dodge, hurt, death hold and respawn.
  Only the three loop clips are duplicated; imported source resources are not
  mutated. Animation never applies damage or changes body position.
- Weapon windup remains authoritative. The exported `contact_fraction` aligns
  the visual swing to that windup, with the tail fitted to weapon recovery.
  Attack clip mappings and blending are exported for art tuning.
- `PlayerEquipment` supplies a bone-attached model for all six current weapon IDs,
  including both Twinfangs daggers. Source alternate swords/shields are hidden.
  Exported model, length and grip maps permit later art adjustment. Models are
  allocated on equip/switch, not each frame. A short unlit shot flash follows the
  existing `EventBus.projectile_fired` signal; no new lights/particles are spawned.
- Screen right/up now map to camera right/forward, joystick magnitude survives,
  and body facing is shared by visuals, targeting, melee and projectiles. Windup
  locks facing; target selection scans only on accepted attack requests.
- Target scoring is distance-first with a bounded angular preference. Dead/out-of-
  range targets are rejected; ties preserve input order. No RNG or persistent
  target cache is introduced.
- One short buffered attack press bridges windup/late recovery. It expires rather
  than auto-firing indefinitely. Hurt, dodge, switch, disable and reset clear it.
  Export: `Player.attack_buffer_seconds` (default 0.18).
- Dodge checks readiness before spending stamina, falls back to current facing,
  respects `can_interrupt_attack`, stops full-speed travel during recovery, clips
  the final burst step, and carries timer overshoot through phase transitions.
  Export: `DodgeController.stamina_cost` (default 25); other dodge tuning stays in
  the existing component and progression path.
- Dodge and ordinary bounds clamps cancel only outward velocity, retaining wall
  sliding. Touch-stop callbacks no longer call `move_and_slide` outside physics.
- Player invulnerability uses the HealthComponent's existing injectable clock,
  advanced only by enabled gameplay. Ignored hits cannot consume shields or apply
  status riders. Damage interrupts pending attacks; death clears input/velocity.
- Mesh overlays replace the invalid Node3D `modulate` tween. Feedback includes
  damage flash, steady cyan invulnerability and steady red low health. Reduced
  motion suppresses transient flashes/shake/hitstop; vibration follows settings.
  Cleave feedback is bounded to one hitstop request per physics frame and delegates
  to the existing manager. Death/respawn have explicit presentation transitions.
- Nine small `data/audio/player_*.tres` resources bind already-reviewed recordings
  via ContentLoader/ContentRegistry. PlayerAudio uses the existing pooled API for
  swings, hits, rolls, death, grounded steps, switches, shots, reloads and a single
  warning when entering low health. No source audio bytes or licences changed.

## Merge/API notes

- Existing Player and EventBus signal signatures and command signatures are intact.
  `Player.attack_started` now also fires when WeaponManager accepts a command.
  The pre-existing WeaponManager-path `Player.attack_finished` timing (resolution,
  not end of recovery) is intentionally preserved.
- Additive methods: `Player.is_control_enabled()`,
  `CharacterController.face_direction(Vector3)`, `CharacterController.stop()`,
  `WeaponInstance.cancel_attack()`, `PlayerFeedback.play_impact_feedback(bool)`.
- `WeaponManager.cancel_in_progress()` now means **cancel combat**, not **refill
  magazines/reset recovery**. Reloads continue. `reset_for_new_run()` still uses
  the original full reset. Switching cancels the outgoing combo and pending hit;
  holstered timers continue through `WeaponManager.tick()`.
- Combat-facing forward is now the actual Player body's world -Z. Do not add a
  second VisualRoot yaw rotation in another branch; the Knight's +Z art correction
  belongs to the imported model instance only.
- All weapon IDs, progression-derived values and save formats are unchanged.
  `DODGE_STAMINA_COST` remains available for compatibility, but the live cost comes
  from the DodgeController export.
- Audio ownership: merge the nine **player-only** resources and the five added
  `assets/catalog.json.audio_cues` entries. They use the established registry and
  do not replace enemy/music/UI registration work.

## Focused tests

`tests/run_player_tests.gd` loads `tests/integration/test_player.gd` after autoload
registration. This independent headless suite deliberately avoids edits to the
shared multi-agent runner and checks that every scenario reaches its end (Godot
script errors otherwise can abort a test without a failing exit code). It exercises buffer consumption/expiry,
combo reset, legacy cooldown, cancellation/ammo/reload, camera/touch mapping,
rotation, real two-finger joystick input, bounds, targeting, canonical scene import,
actual animation transitions and source-resource isolation,
weapon models/grips, attack timing/aim, dodge/stamina/i-frames, shield/status
rejection, modal clock freeze, low health, switching/holstered cooldown, stun,
automatic reload, shot flash, death/respawn, recorded cues and delegated feedback.

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_player_tests.gd
godot --headless --path . --script res://tests/validate_asset_imports.gd
python3 scripts/download_assets.py --verify
python3 tool/validate_resources.py
python3 tool/validate_assets.py
python3 -m unittest discover -s tests/python -v
gdlint scripts tests
node tool/validate_gltf.cjs
git diff --check
```

## Executed validation (2026-09-08)

Godot was not installed and release-host downloads failed. Native checks used an
isolated build of the official **4.4.1-stable / 49a5bc7b6** source, with headless
rendering/audio and no system fontconfig. Build products, temporary baseline
checkout and validation scratch files are outside the patch. The build's
"No renderers available" and fontconfig diagnostics are environment limitations,
not project changes.

| Check | Result |
|---|---|
| Focused player integration suite | **122 checks, 0 failed**; all 7 scenarios reached completion |
| Native asset import validator | **193 resources, 0 failures** |
| Resource structure validation | **79 files, OK** |
| Locked source integrity | **222/222 verified**, 0 failed |
| Asset/dependency/clip/cue validation | Passed |
| Existing Python unittest suite | **37 tests passed** |
| Repository-wide `gdlint scripts tests` | Passed |
| Khronos glTF validator | **81 models, 0 errors**, 49 warnings on unchanged sources |
| `git diff --check` | Passed |
| Original GDScript runner and main-scene smoke | **Not clean: pre-existing blockers**, below |

The focused/native asset checks execute successfully but project autoloads still
print the initial-commit errors below. They are not a claim of a clean full-game
launch. To distinguish regressions, the initial `HEAD` was archived to a separate
ignored directory and the original runner, every existing unit suite, and the
main-scene smoke test were also run there. The blockers reproduce unchanged:

- `scripts/combat/combat_log.gd:74`: returns the void result of `Array.reverse()`,
  breaking CombatLog and dependent RunScorekeeper/GameRoot initialization.
- `scripts/ui/ui_text.gd:49`: static `get()` conflicts with Object's native method;
  dependent HUD/root/upgrade UI scripts cannot resolve it.
- `tests/unit/test_waves.gd:92` and `test_upgrades.gd:18`: invalid inferred types.
- `tests/unit/test_extracted_modules.gd:107`: blocked by UiText.
- `tests/unit/test_area_combat.gd:84`: aborts on the invalid CombatLog dependency.
- `tests/unit/test_weapons.gd:120`: its nearest-first test uses nodes outside the
  tree, producing identity global transforms and a failing assertion.
- `scripts/utilities/rng_service.gd:49-51`: unsigned-sized hexadecimal literals
  generate signed-64-bit conversion errors.
- `scripts/main/main.gd:29`: accesses a nonexistent GameRoot `game_state_changed`
  signal (the existing contract lives on EventBus).

The original runner prints "52 total, 0 failed" **after its unit loop aborts**;
that is not a full-suite pass. A separate diagnostic sweep attempted all 20 unit
suites: 209 reported checks, one failed assertion, three compile-blocked suites,
and the AreaCombat runtime abort. Baseline and this branch produce the same
outcome. No unrelated owner files were edited to mask those failures.

## Files changed

- `scenes/player/player.tscn`
- `scripts/player/attack_buffer.gd` (new)
- `scripts/player/attack_controller.gd`
- `scripts/player/character_controller.gd`
- `scripts/player/combo_chain.gd`
- `scripts/player/dodge_controller.gd`
- `scripts/player/player.gd`
- `scripts/player/player_animation.gd` (new)
- `scripts/player/player_audio.gd`
- `scripts/player/player_equipment.gd` (new)
- `scripts/player/player_feedback.gd`
- `scripts/player/player_locomotion.gd`
- `scripts/player/targeting_component.gd`
- `scripts/weapons/weapon_instance.gd`
- `scripts/weapons/weapon_manager.gd`
- `data/audio/player_{attack,death,dodge,hurt,low_health,reload,shot,step,switch}.tres`
  (9 new player-only cue resources)
- `assets/catalog.json` (five player cue entries only)
- `AUDIO_MANIFEST.md` (player registration/provenance notes)
- `tests/run_player_tests.gd` (new)
- `tests/integration/test_player.gd` (new)
- `docs/PLAYER_IMPLEMENTATION.md` (this report)

## Remaining limitations

Headless validation does not establish on-device frame rate, visible hand contact,
sound mix or camera feel. Android hardware testing and a rendered art pass remain
necessary; no APK was built. Contact fraction, stride lengths and grip offsets are
exposed for that tuning. The source clips use authored hand poses; no new IK or
retargeting assets were fabricated. The shot sound is a supplied swish, not a newly
recorded bow sound. Global pause/state and camera implementation remain owned by
their respective systems. Full-project validation remains blocked by the reproduced
initial-commit issues above.
