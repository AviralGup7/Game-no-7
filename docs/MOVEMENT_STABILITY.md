# Movement Stability — joystick → locomotion → physics/camera (2026-09-09)

## Symptom

Menu and run start were fine. As soon as the character was driven with the on-screen
joystick, the app died after a few steps of walking — no error dialog, no stack in the
UI: the process just went away (Android: `Fatal signal`, logcat often pointing at the
Vulkan renderer or `godot--` with an invalid transform/AABB).

## Why "a few steps later" and not on the bad frame

Nothing in this chain decays a bad value on its own:

- `CharacterController.tick()` wrote velocity straight into `CharacterBody3D` and
  called `move_and_slide()`. A non-finite component is integrated into `global_position`
  and the body's physics AABB goes NaN.
- `CameraRig._process()` lerped the collision solver's result into `global_position`.
  `Vector3.lerp()` with a NaN input is NaN forever, so one bad ray result latches.
- `PlayerLocomotion` only re-reads the keyboard when `_move_input == Vector2.ZERO`, so a
  poisoned stick sample is *held* for the rest of the run — the next frames keep feeding
  the same garbage into the body and the camera.

The abort therefore happens some frames downstream, in physics broadphase or in the
scene cull, at the first query that touches the poisoned transform. That is why the
crash looked like "walking breaks the game" instead of "input breaks the game", and why
reading any single file in isolation showed nothing wrong.

## Root causes fixed

| # | Where | Defect | Fix |
|---|-------|--------|-----|
| 1 | `scripts/ui/virtual_joystick.gd` | `delta / radius` divided by the exported/layout radius with no floor, so a degenerate radius produced `±inf`/`NaN` movement values; positions were used unvalidated | `_safe_radius()` (finite, ≥ 8 px) used by the drag clamp, the division and `_draw()`; non-finite press/drag samples are dropped; `get_value()` refuses to hand out a non-finite vector |
| 2 | `scripts/ui/touch_controls.gd` | forwarded whatever the stick emitted, latching it in the player | non-finite value ⇒ publish a neutral stick and stop |
| 3 | `scripts/player/player_locomotion.gd` | `set_move_input()` / `gather()` accepted NaN/inf; `clamp_to_bounds()` clamped NaN through `clampf()` and left a poisoned transform in place | both input hand-offs reject non-finite vectors; the bounds pass repairs the transform per axis and zeroes velocity, breaking the latch |
| 4 | `scripts/player/character_controller.gd` | no delta validation, velocity read/written raw, `_camera_yaw()` fed an unvalidated camera basis, `_turn_toward()`/`face_direction()` could assign a non-finite Euler, `set_move_speed()` let `inf` through | all motion flows through one choke point, `_apply_velocity()`, which sanitises in *and* out and repairs a non-finite body position; `delta` must be finite and positive; camera yaw falls back to `0.0`; rotation is assigned as a whole validated vector; speed is `clampf(value, 0, 40)` |
| 5 | `scripts/main/camera_rig.gd` | the rig lerped the solver result into `global_position` unguarded, and `looking_at()` was called with a non-finite or coincident eye/target — a NaN basis then stayed on the `Camera3D` forever | `_apply_follow_position()` is the only writer of the follow position (rejects a non-finite target *and* a non-finite smoothing weight); `_update_look_at()` rejects non-finite origin/target, skips a degenerate (coincident) frame, and validates the built `Transform3D` before assigning |
| 6 | `scripts/main/camera/camera_math.gd` | the only finiteness helper (`sanitize_vec`) had zero callers and returned `Vector3.ZERO`, which would teleport a rig instead of saving it | added `is_finite_v3()` / `is_finite_transform()` as the reject-don't-replace gate used by the rig |
| 7 | `scripts/player/player_animation.gd` | `_length()` dereferenced the `Animation` returned by `get_animation()` (null after a library swap) and could return a NaN/0 length that then became a playback `speed_scale` divisor | `_length()` returns the 0.3 s fallback unless the resource exists and its length is finite and positive |
| 8 | `scripts/main/camera/camera_shake_controller.gd`, `scripts/main/camera/camera_fov_controller.gd` | the shake pass is the **last** writer of the camera transform in a frame (it runs after the look-at), and it committed `_base_local + trauma_offset` / a `rotated_local()` result unvalidated; the FOV controller assigned `camera.fov` straight from smoothed math | non-finite shake samples are dropped before the position write, the rolled transform is validated before assignment, and FOV goes through `_bounded()` (hold-last-good, clamped to `Camera3D`'s own 1–179 range: a bad FOV is an invalid projection matrix and also corrupts every HUD `unproject_position()`) |
| 9 | `scripts/arena/arena_hazards.gd` | per-frame hazard ticks dereferenced the arena-owned marker / disc / material with no validity check (a world rebuild frees them while the record still ticks), and a non-finite epicentre fed knockback | `_hazard_emission()` resolves the visual (null ⇒ skip the glow only); the vent still damages, and a non-finite centre is skipped rather than applied |

Guardrails are *inlined at the use sites*, per `docs/HARDENING.md`'s post-refactor
contract — no `_validated_*` layer came back. `tool/validate_guards.py` pins every
guard above so it cannot be quietly dropped in a later refactor.

## Diagnostics

Hardening silently would hide which signal was bad. The first refusal in a process logs
one warning (never per frame):

- `CharacterController: refused non-finite <where>; locomotion held steady instead of crashing.`
- `CameraRig: ignored a non-finite camera frame (follow position or look-at target); orientation held.`

If a device run ever prints one of these, the line names the boundary that caught it —
that is the remaining bug, and the game now survives to report it in logcat instead of
dying with an unattributed native abort.

## Reproducing / verifying locally

The stick now also accepts mouse drags (`InputEventMouseButton` / `InputEventMouseMotion`
via `_gui_input`), so the whole path is drivable in the editor without a touch device:

```sh
godot --headless --path . --script res://tests/run_tests.gd   # includes tests/unit/test_locomotion_nan.gd
python3 -m unittest discover -s tests/python                  # regression guards
python3 tool/validate_guards.py                               # real-guard contract
```

## Verification limits (this pass)

- The engine is **not available in this environment**, so the crash could not be
  reproduced or observed fixed here; nothing in this pass is claimed as a measured repro.
  Native Godot CI + a device run are the remaining confirmation.
- The GDScript suite drives only pure, tree-free surfaces on purpose: the cases must not
  be able to destabilise the headless run that guards the game. Node-level physics is
  covered by `tests/integration/test_player.gd`.
- This pass changes no balance, no input map, and no scene: every edit is either a guard
  on a path that was previously unguarded, or a defect fix inside that path
  (`set_move_speed` clamp, hazard visual deref, `_length()` fallback).
