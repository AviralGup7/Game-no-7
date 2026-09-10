# Camera — Modular Third-Person Rig

## Overview

The camera is a small coordinator (`CameraRig`, ~350 lines) plus 12 focused
`RefCounted` modules under `scripts/main/camera/`, all driven by a data-driven
`CameraProfile` (`data/cameras/*.tres`). This is the merged successor to the
monolithic 800-line rig and its "perfect camera" rewrite; the design principles
below are the distilled, tunable behaviours from that work.

## Modules

| # | Module | Responsibility |
|---|--------|----------------|
| 1 | `camera_math.gd` | Pure helpers: framerate-independent `exp_weight`, angle lerps, spherical offset. |
| 2 | `camera_input_handler.gd` | Yaw/pitch from actions, right stick, mouse, touch drag; deadzones, sensitivity, reset. |
| 3 | `camera_velocity_tracker.gd` | Smoothed target velocity/speed/direction; 10 m teleport guard. |
| 4 | `camera_focus_tracker.gd` | Predictive focus point; separate H/V smoothing to cut jump bobbing. |
| 5 | `camera_orbit_state.gd` | Pure orbit data (yaw/pitch/distance), setup/snap from profile. |
| 6 | `camera_auto_follow_controller.gd` | Gentle drag-behind: 0.55 s sustain, 28° deadzone, toward-camera + strafe suppression, 2 s manual cooldown. |
| 7 | `camera_orbit_controller.gd` | Manual + auto orbit; distance = profile × mode multiplier + combat boost; fast-in/slow-out smoothing. |
| 8 | `camera_collision_solver.gd` | Sphere-cast on `CAMERA_QUERY_MASK` + whiskers + ground clearance; pooled query objects, cached every 1/60 s or 0.4 m of arm travel. |
| 9 | `camera_framing_controller.gd` | Desired position/look target with shoulder offset; combat framing widens on 2/4/6 nearby enemies. |
| 10 | `camera_fov_controller.gd` | Base FOV + sprint boost + combat boost + mode multiplier. |
| 11 | `camera_shake_controller.gd` | `HitstopManager` trauma + event shakes via FastNoiseLite (28 Hz); idle breathing; reduced-motion disables. |
| 12 | `camera_mode_controller.gd` | EXPLORE / COMBAT / BOSS / LOCKED modes with blended FOV/distance multipliers; lock-on target. |

## Coordinator loop (`camera_rig.gd`)

```
velocity → combat framing → orbit → focus → desired position
→ collision solve → follow (exponential decay) → look-at → FOV → shake
```

Public API: `set_target`, `set_camera_profile`, `add_shake`, `reset_transform`,
`reset_orbit`, `set_reduced_motion`, `get_debug_snapshot`.

## Design principles

- **No fighting the camera** — toward-camera suppression + deadzone means strafing
  and walking toward the camera don't spin the view.
- **No clipping** — sphere-cast + whiskers + ground clearance; pull-in fast (14),
  push-out slow (2.8) to avoid doorway jitter; recovery delay 0.12 s.
- **Cinematic but playable** — shoulder offset, look-ahead, predictive focus, sprint
  FOV boost; auto-follow gentle enough that manual orbit is optional.
- **Framerate independent** — exponential-decay smoothing everywhere, never `delta*const`.
- **Accessible** — reduced-motion lowers smoothing and disables shake.
- **Data-driven** — `CameraProfile` exposes 30+ tuned fields per arena.

## Profiles

- `default.tres` — balanced arena (9 m, 62° FOV, 32° pitch).
- `combat.tres` — wider when surrounded (10.5 m, 66° FOV, faster auto-follow).
- `boss.tres` — cinematic boss (12.5 m, 68° FOV, 38° pitch, 6 whiskers).

Mode multipliers widen the view on boss spawn without scene changes; an arena can
still pin `default_camera_profile = &"boss"`.

## Files

```
scripts/main/camera_profile.gd
scripts/main/camera_rig.gd
scripts/main/camera/{camera_math,camera_input_handler,camera_velocity_tracker,
  camera_focus_tracker,camera_orbit_state,camera_auto_follow_controller,
  camera_orbit_controller,camera_collision_solver,camera_framing_controller,
  camera_fov_controller,camera_shake_controller,camera_mode_controller}.gd
data/cameras/{default,combat,boss}.tres
```

## References

- GDC 2005 Haigh-Hutchinson, *Fundamentals of Real-Time Camera Design*
- GDC Vault 2018, *God of War — Evolving God of War* (camera as character)
- Unreal SpringArm docs; community third-person-camera postmortems
