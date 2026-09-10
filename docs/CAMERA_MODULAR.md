# Modular Perfect Camera – Architecture

## Overview
Monolithic 800-line camera split into 11 focused modules under `scripts/main/camera/`. Each module is `RefCounted`, testable, data-driven via `CameraProfile`.

## Modules

### 1. CameraMath (`camera_math.gd`)
Pure static helpers – no state.
- `exp_weight(smoothing, delta)` – framerate independent `1-exp(-s*dt)`
- `lerp_angle_weighted`, `angle_difference`, `yaw_from_direction`, `direction_from_yaw`, `right_from_yaw`, `spherical_offset`
Used everywhere to avoid duplication.

### 2. CameraInputHandler (`camera_input_handler.gd`)
- Gathers yaw/pitch from: actions `camera_look_left/right/up/down` (the InputMap already includes the right stick — do not also read `JOY_AXIS_RIGHT_*`), mouse motion (right/middle button or captured), and `handle_look_delta` for right-half touch drag.
- Deadzone handling, mouse sensitivity, accumulation decay.
- `reset()` clears mouse accum.

### 3. CameraVelocityTracker (`camera_velocity_tracker.gd`)
- Tracks target `velocity`, `speed`, `move_dir`, `last_position`.
- Smoothing via `exp_weight`, teleport guard (>10m snap).
- Used for predictive focus, FOV boost, auto-follow.

### 4. CameraFocusTracker (`camera_focus_tracker.gd`)
- `focus_point` = player + look_height + velocity*predictive + move_dir*look_ahead*speed/6
- Separate H/V smoothing (`follow_smoothing` for XZ, `focus_height_lerp` for Y) to reduce bobbing on jumps.
- `snap_to()` for teleport.

### 5. CameraOrbitState (`camera_orbit_state.gd`)
- Pure data: `current_yaw/target_yaw`, `current_pitch/target_pitch`, `current_distance/target_distance`, `collision_distance`.
- `setup_from_profile`, `snap_to_facing`.

### 6. CameraAutoFollowController (`camera_auto_follow_controller.gd`)
- Elden Ring logic: sustain timer >0.55s, deadzone 28°, toward-camera suppression (`auto_follow_toward_camera_threshold`, default 0.25), strafe suppression 0.65x, speed scales with angle diff.
- `manual_cooldown` suspends auto-follow after manual input (2s).
- `tick()` updates `orbit.target_yaw`.

### 7. CameraOrbitController (`camera_orbit_controller.gd`)
- Composes input + auto-follow + state.
- Manual orbit: `target_yaw -= input.x * orbit_speed * dt *6`, `target_pitch += input.y * ...`, clamp pitch.
- Computes desired target distance = profile distance * mode multiplier (blended) + combat boost.
- Smooths yaw/pitch/distance with in/out speeds (fast-in 14, slow-out 2.8).

### 8. CameraCollisionSolver (`camera_collision_solver.gd`)
- Sphere-cast via a pooled `PhysicsShapeQueryParameters3D.cast_motion` on
  `CollisionLayers.CAMERA_QUERY_MASK` (arena geometry only — a horde never pushes the
  view); whiskers identify what the cast misses.
- Whisker check: 4-6 angled rays ±18-22° to anticipate tight spaces.
- Ground clearance: ray down 6m, enforce `cam_y >= ground_y + clearance`, also `cam_y >= focus_y -1`.
- `recovery_timer` keeps the colliding *flag* held briefly after a clear pass so an arm
  resting on a ledge cannot flicker state (the length itself is not held).
- **Pooled + gated by construction:** the shape and both parameter objects are created
  once in `_ensure_query_objects()`, and a full spatial pass runs only every
  `QUERY_INTERVAL` (1/60 s) or once either end of the arm has moved `CACHE_SLACK`
  (0.4 m). `solve()` is called per *render* frame, so on a 120 Hz panel this halves the
  queries; the cached pullback is applied to the current arm direction every frame, so
  tracking latency is unchanged. `invalidate_cache()` forces a fresh pass after a
  re-target, a `reset_transform()` cut or the rig's 10 m teleport guard.
- `get_debug_snapshot()` reports `queries_last_pass` / `passes_total` — the numbers to
  watch in `PerformanceMonitor` output when tuning `whisker_count`.

### 9. CameraFramingController (`camera_framing_controller.gd`)
- `calculate_desired_position(focus, orbit)` – spherical + height*0.55 + shoulder offset.
- `calculate_look_target(focus, velocity)` – focus + velocity*0.12 + shoulder_y*0.3.
- Combat framing: every `combat_check_interval` (0.25s) counts enemies in group "enemies" within `combat_enemy_radius` (8m). If >=2/4/6 enemies, lerp distance boost (0.4/1.2/2.5) and FOV boost (0/2/4) from profile.

### 10. CameraFovController (`camera_fov_controller.gd`)
- Base FOV + speed boost `clamp((speed-threshold)*boost*0.18)` + combat boost + mode multiplier (boss 1.08, combat 1.04, locked 0.96 blended).
- Smoothed via `exp_weight(fov_smoothing)`.

### 11. CameraShakeController (`camera_shake_controller.gd`)
- Combines `HitstopManager` trauma (noise) + event shakes.
- FastNoiseLite frequency 28Hz, smooth not rand.
- Idle breathing: when speed<0.5, not colliding, shake_remaining<0.01, adds subtle 0.025m noise at 0.6Hz.
- Reduced-motion disables all.

### 12. CameraModeController (`camera_mode_controller.gd`)
- Modes: EXPLORE, COMBAT, BOSS, LOCKED (Z-target).
- `set_mode(new_mode, blend_duration)` – duration from profile (explore 0.5, combat 0.8, boss 1.0, locked 0.35).
- `get_mode_fov_multiplier()`, `get_mode_distance_multiplier()` – from profile.
- Lock-on: `set_lock_target(Node3D)` → LOCKED mode, `is_locked()` validates, `get_lock_target()` for look-at midpoint.
- Blend factor `blend_timer / blend_duration`.

## Coordinator – CameraRig (`camera_rig.gd`)

Now ~350 lines vs 800 before, purely coordination:

```gd
_ready: setup all modules, find Camera3D, make current, position zero
set_target: setup velocity, orbit_state from facing yaw, focus tracker
set_camera_profile: propagate to all modules
_process:
  1. velocity.tick
  2. framing.tick_combat_framing
  3. orbit.tick (manual + auto + mode + combat distance)
  4. focus.tick (predictive)
  5. desired = framing.calculate_desired_position
  6. collided = collision.solve(focus, desired, orbit, target, world)
  7. rig global_position lerp to collided via exp_weight, snap on first frame/teleport
  8. look_at: if locked, midpoint of focus + lock_target, else framing look target
  9. fov.tick (speed + combat + mode)
  10. shake.tick (trauma + breathing)
  11. _update_lock_on_target from TargetingComponent
```

Public API preserved: `set_target`, `set_camera_profile`, `add_shake`, `reset_transform`, `reset_orbit`, `set_reduced_motion`, `get_debug_snapshot`.

## New Profiles

- `default.tres` – balanced arena (9m, 62 FOV, 32° pitch)
- `combat.tres` – wider when surrounded (10.5m, 66 FOV, faster auto-follow 0.45s delay)
- `boss.tres` – cinematic boss (12.5m, 68 FOV, higher pitch 38°, 6 whiskers)

Arena configs still use `default`, but mode controller automatically widens on boss spawn via multiplier, no scene change needed. Designers can set `default_camera_profile = &"boss"` per arena if desired.

## Further Improvements

- **Touch**: `InputEventScreenDrag` on right half → camera orbit, scaled 0.8
- **Teleport guard**: if last_pos dist² >100, reset velocity & snap focus, force rig snap
- **Vertical damping**: focus Y uses `focus_height_lerp` (4.0) vs horizontal `follow_smoothing` (6.0)
- **Lock-on**: queries `TargetingComponent.pick_best_target(enemies)` if locked, validates max distance
- **Idle breathing**: subtle noise when stationary, not colliding, no shake
- **Mode blending**: smooth 0.35-1.0s transitions, no cuts (God of War principle)
- **Debug**: snapshot includes module presence, enemy count, combat boost, mode, etc.

## Testing

- Existing tests (`test_configs`, `stress_loops`, `soak_runtime`) still pass – API preserved, `_target` var still exists via orbit_state but we expose via `get_debug_snapshot`.
- New modules are RefCounted, can be unit tested without Node3D: test `CameraMath.exp_weight`, `CameraAutoFollow` dot suppression, `CameraCollision` safe fraction, etc.
- Future: add `tests/unit/test_camera_modules.gd` covering math, auto-follow, framing.

## File List

```
scripts/main/camera_profile.gd (extended with combat/mode/lock-on groups)
scripts/main/camera_rig.gd (modular coordinator, ~350 lines)
scripts/main/camera/
  camera_math.gd
  camera_input_handler.gd
  camera_velocity_tracker.gd
  camera_focus_tracker.gd
  camera_orbit_state.gd
  camera_auto_follow_controller.gd
  camera_orbit_controller.gd
  camera_collision_solver.gd
  camera_framing_controller.gd
  camera_fov_controller.gd
  camera_shake_controller.gd
  camera_mode_controller.gd
data/cameras/
  default.tres (updated with new fields)
  combat.tres (new)
  boss.tres (new)
docs/
  CAMERA_PERFECT.md (analysis)
  CAMERA_MODULAR.md (this file)
```

## Why Modular is Better

- **Single Responsibility**: each file <150 lines, easy to read, test, replace
- **Data-driven**: designers tweak combat radius, boost values, mode multipliers without code
- **Extensible**: add new mode (e.g., AIM) by adding enum + multipliers, no rig change
- **Performance**: modules only tick when needed (combat check every 0.25s, recovery timer, etc.)
- **Platform**: input handler abstracts mouse/gamepad/touch, easy to add gyro
