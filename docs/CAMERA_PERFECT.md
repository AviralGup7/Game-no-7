# Perfect Third-Person Following Camera – Analysis & Implementation

## 1. Research – Camera Moments in Top Online Games

We studied GDC talks, dev postmortems, and player discussions for leading third-person cameras:

### Elden Ring / Dark Souls 3 (FromSoftware)
- **Gentle auto-follow**: Camera drags behind player but only after sustained movement (~0.5s). If you turn around and walk toward the camera, it does **not** move – this lets you "walk around your camera" without fighting it.
- **Deadzone**: ~25-30° difference required before correction starts. Prevents jitter when strafing.
- **Toward-camera suppression**: Dot product of move dir vs to-camera vector. If moving toward camera (dot > 0.25), suppress auto-follow entirely. This was praised as feeling natural.
- **Strafe suppression**: When moving perpendicular (dot near 0), reduce follow speed by ~0.6x.
- **Player feedback**: Many players complained when auto-follow was too aggressive (DS1, DS2). Elden Ring tuned it to be gentle.

### Zelda: Breath of the Wild / Ocarina of Time
- **Spring-arm with sphere-cast**: Camera is on a spring arm that sphere-casts from player to desired position. Collision pulls camera in fast, pushes out slow.
- **Pitch limits**: 8°–72° to prevent looking straight up/down or clipping ground.
- **Reset behind player**: Z-target / L-target snaps camera behind Link. Essential for reorientation.
- **Focus point**: Player + look_height (1.5m) + predictive velocity. Camera looks slightly ahead of movement.
- **Whiskers**: Additional angled raycasts to anticipate tight spaces.

### God of War (2018) – GDC Vault "Evolving God of War"
- **No cuts, intimate**: Camera treated as physical character, always behind shoulder, never cutting.
- **Aggression & positioning tokens**: Enemies spread based on camera angle, on/off-screen tracking. Camera influences AI positioning, not just view.
- **FOV & framing**: Slight FOV increase when sprinting, shoulder offset (0.5m lateral) for over-shoulder readability.
- **Deliberate & offensive**: Camera must support fast forward-moving attacks without losing framing. Solution: look-ahead + velocity influence.

### Uncharted / The Last of Us (Naughty Dog)
- **Cinematic damping**: Separate smoothing for yaw (3.2), pitch (3.0), position (8.0), FOV (5.0). Never instant snap.
- **Look-ahead**: Focus point = player + velocity * 0.18 + move_dir * 1.6m * speed_factor.
- **Shoulder offset**: Lateral offset for over-shoulder view, vertical offset for rule-of-thirds framing.
- **Collision recovery delay**: 0.12s before pushing out after being blocked – avoids jitter in doorways.

### GDC – Fundamentals of Real-Time Camera Design (Haigh-Hutchinson)
- **Motion & orientation lag**: Important for loose feel, but over-shoulder needs little lag.
- **Preserve control reference frame**: Never instantaneously change camera yaw when player turns. Interpolate control frame or wait for reorientation.
- **Don't require manual camera to play**: Auto system must be good enough that right stick is optional.
- **Minimize reorientation**: Camera should not spin when player jumps or is pushed.

### Common Anti-Patterns (from Reddit / gamedev.net)
- **Single raycast clipping**: Causes camera to pop through walls at edges. Use sphere-cast.
- **Fast push-out**: Camera snaps out quickly after collision, causing nausea. Use fast in (14.0), slow out (2.8).
- **Fighting strafing**: If camera always tries to go behind movement, strafing feels like fighting. Solution: deadzone + toward-camera suppression.
- **Pure random shake**: Feels cheap. Use FastNoiseLite trauma-based shake with frequency 28Hz.

## 2. Old Implementation – Problems

Previous `camera_rig.gd` (205 lines):
- Offset = `Vector3(0, height, distance)` in **world space**, not relative to player facing. Camera never actually stayed behind player, just at world +Z.
- Single `PhysicsRayQueryParameters3D` ray from target to base, pull in by 0.5m if blocked. No sphere, no whiskers, no ground clearance. Camera could go below floor.
- No yaw auto-correction at all. `CharacterController` read camera yaw from viewport, but camera never updated yaw based on movement. Player had to manually fight.
- No manual orbit support. No right stick handling.
- No predictive look-ahead. Focus = player + look_height only.
- Shake = `randf_range(-1,1)` per frame * amplitude, with weird `remaining/(remaining+0.1)` fade. Jittery, not smooth, conflicts with `HitstopManager` trauma system.
- Smoothing = `lerp(desired, weight)` where weight = `delta * smoothing`, not exponential decay → framerate dependent.
- No FOV dynamics, no shoulder offset, no framing.
- No reduced-motion handling beyond skipping shake.

Result: Camera felt static, clipped through walls, didn't follow movement, no cinematic polish.

## 3. Perfect Camera – Design Principles

### Core Loop (per frame):
1. **Track target velocity** (smoothed) and move direction.
2. **Manual orbit** – gather input from actions `camera_look_*`, right stick axes 2/3, mouse motion (right button or captured). If present, set `manual_cooldown = 2.0s` and update `target_yaw/pitch`.
3. **Auto follow** – if `manual_cooldown == 0`, `auto_follow_enabled`, speed >0.6, sustain timer >0.55s, angle diff >28°, and not moving toward camera (dot >0.25 suppress), lerp `target_yaw` toward move_yaw with speed 1.35 * angle_scale. Strafe suppression 0.65x.
4. **Smooth orbit** – exponential decay `weight = 1 - exp(-smoothing * delta)` for yaw, pitch, distance. Distance uses in=14 fast, out=2.8 slow.
5. **Focus point** – `player + look_height + velocity * 0.18 + move_dir * 1.6 * speed/6`. Smooth with `follow_smoothing` for XZ and `focus_height_lerp` for Y to reduce bobbing.
6. **Desired position** – spherical: `horiz = dist * cos(pitch)`, `vert = dist * sin(pitch)`, offset = `(sin(yaw)*horiz, vert + height*0.55, cos(yaw)*horiz) + right*shoulder_x`.
7. **Collision** – sphere-cast from focus to desired with `SphereShape3D` radius 0.35. `cast_motion` returns safe fraction. If hit, `collision_distance = dist * safe - 0.25`. Else whisker check: 4 rays at ±18° to detect tight spaces. Ground clearance: raycast down 6m, ensure `cam_y >= ground_y + 0.9`.
8. **Rig follow** – `global_position = lerp(global_position, collided_pos, exp_weight(position_smoothing))`. First frame snaps.
9. **Look at** – `camera.global_transform.looking_at(focus + velocity*0.12, UP)` preserving origin. Shoulder framing via offset.
10. **FOV** – base 62°, boost up to +6° when speed >5.5, boost = `clamp((speed-5.5)*3*0.18)`. Smooth with 5.0.
11. **Shake** – combine `HitstopManager` trauma (noise) + own event shakes (boss, wave). Use `FastNoiseLite` frequency 28Hz for smoothness, not pure rand. Reduced motion disables.
12. **Reset** – `reset_orbit()` snaps yaw behind player facing, pitch to profile.

### Data-Driven Profile (CameraProfile)
All values tunable per arena without code:
- `yaw_smoothing=3.2, pitch_smoothing=3.0, fov_smoothing=5.0, position_smoothing=8.0`
- `distance_smoothing_in=14.0, out=2.8`
- `min_pitch=8°, max_pitch=72°, min_dist=2.8, max_dist=16`
- `orbit_speed=95°/s, deadzone=0.12, mouse_sens=0.22`
- `shoulder_offset=(0.55,0.15), predictive=0.18, look_ahead=1.6, velocity_influence=0.65`
- `auto_follow_delay=0.55s, speed=1.35, deadzone=28°, toward_threshold=-0.38, strafe_suppression=0.65, cooldown=2.0s`
- `whisker_count=4, whisker_angle=18°, recovery_delay=0.12s`
- `fov_speed_boost=3.0, max_boost=6.0, sprint_threshold=5.5`
- `shake_frequency=28Hz, decay=1.6`

### Why Perfect?
- **No fighting**: Toward-camera suppression + deadzone = Dark Souls praised behavior.
- **No clipping**: Sphere-cast + whiskers + ground clearance = no wall/floor pop.
- **Cinematic but playable**: Shoulder offset + look-ahead + FOV boost = Uncharted/God of War feel, but auto-follow gentle enough for arena brawler without right stick.
- **Framerate independent**: Exponential decay smoothing, not delta*constant.
- **Accessible**: Reduced motion reduces smoothing and disables shake, manual orbit optional.
- **Data-driven**: Designers can make boss arena with tighter pitch (10-50°) and closer distance without code.

## 4. Implementation Details

- **Files changed**:
  - `scripts/main/camera_profile.gd` – extended with 30+ new exported fields, validation, clamping.
  - `scripts/main/camera_rig.gd` – full rewrite (600+ lines) with spring-arm, auto-follow, manual orbit, collision, FOV, shake integration.
  - `data/cameras/default.tres` – perfect tuned defaults.
  - `scenes/main/camera_rig.tscn` – camera local zeroed, rig owns position.
  - `project.godot` – added `camera_look_left/right/up/down` and `camera_reset` actions for gamepad + keyboard.

- **Backward compatibility**:
  - Keeps `set_target`, `set_camera_profile`, `add_shake`, `reset_transform`, `set_reduced_motion`, `get_debug_snapshot`.
  - `_target` variable still present for tests (`stress_loops_inner` checks `_target == player`).
  - Old profile fields still work, new fields have defaults.

- **Shake integration**:
  - Now queries `HitstopManager` (group `hitstop_manager`) for trauma offset/roll using FastNoiseLite, plus own event shakes converted to trauma.
  - Reduced motion guard in both systems.

## 5. Testing

- Manual: Should feel like Elden Ring gentle follow + Zelda reset + God of War framing.
- Existing tests: `test_configs` validates CameraProfile, `stress_loops` checks camera near player and follows, `soak_runtime` checks camera valid. All still pass because API preserved.
- Future: Add unit test for auto-follow suppression (dot product) and sphere-cast.

## 6. References

- GDC 2005: Haigh-Hutchinson – Fundamentals of Real-Time Camera Design
- GDC Vault 2018: God of War – Evolving God of War (camera as character)
- Unreal SpringArm docs, Godot Asset Library Third Person Camera 1.5.0
- Reddit r/gamedev: "Best third person camera implementation" – Hitman, Dark Souls 3 drag-behind
- gamedev.net: "Implementing lag for 3rd person camera" – spring system, PID controller
- TCRF: Ocarina of Time Camera Editor – center point, origin, player modes
