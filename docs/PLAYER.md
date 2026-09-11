# Player — Architecture, Tuning & Stability Postmortems

Merged successor of the player-integration handoff and the two stability
postmortems. Three sections: the live player contract, the NaN-crash hardening,
and the boot/visibility hardening.

## 1. Player architecture & tuning

Authority chain (see `docs/ARCHITECTURE.md` for the full system map):

```
Player → CharacterController / HealthComponent / WeaponManager / SkillController
       / StatusManager / DodgeController / Stamina / Experience / Targeting
```

Key tuning facts, all exported for art/balance adjustment:

- `scenes/player/player.tscn` instances the hero with a **primitive `Body` capsule
  fallback** — the player is never invisible if the authored model fails to mount.
  Capsule collision stays independent of art.
- `PlayerAnimation` maps idle / walk-run / combo swings / weapon-specific melee /
  ranged release-reload / dodge / hurt / death / respawn. Only the three loop clips
  are duplicated; imported sources are never mutated; animation never applies damage
  or moves the body.
- **Attack buffer** bridges windup/late recovery for one press (`attack_buffer_seconds`
  = 0.18 s) and expires rather than auto-firing; hurt/dodge/switch/disable/reset clear it.
- **Dodge** checks readiness before spending stamina (`DodgeController.stamina_cost`
  = 25), falls back to facing, respects `can_interrupt_attack`, and carries timer
  overshoot across phase transitions.
- **Targeting** is distance-first with a bounded angular preference; dead/out-of-range
  targets rejected; no RNG, no persistent cache. Windup locks facing.
- **PlayerEquipment** attaches bone-mounted weapon models per weapon id (gladius,
  sentinel_spear, stormhammer, sunbow, twinfangs, warreaxe, ember_scepter, moonlance,
  venom_chain) with exported model/length/grip maps; allocated on equip, not per frame.
- **Feedback** uses mesh overlays (damage flash, cyan invulnerability, red low health)
  instead of Node3D `modulate` tweens; reduced-motion suppresses flashes/shake/hitstop;
  vibration follows settings.
- **Audio**: nine `data/audio/player_*.tres` cues (attack/death/dodge/hurt/low-health/
  reload/shot/step/switch) through the pooled `PlayerAudio` API.

Combat-facing forward is the body's world −Z. Do **not** add a second `VisualRoot`
yaw rotation; the imported model's +Z art correction belongs to the model instance only.

## 2. Movement stability — the NaN crash (2026-09-09)

**Symptom:** driving with the on-screen joystick killed the app after a few steps —
no dialog, just a native abort (Android `Fatal signal`, often at the Vulkan renderer).

**Why "a few steps later":** nothing in the chain decays a bad value on its own. A
non-finite stick sample was written into `CharacterBody3D` velocity, integrated into
`global_position`, latched by `PlayerLocomotion` (it only re-reads input when
`_move_input == ZERO`), and `CameraRig` then lerped a NaN collision result forever.
The abort fired frames later in physics broadphase / scene cull.

Root causes fixed (each guard is pinned by `tool/validate_guards.py` so a later
refactor cannot silently drop it):

| Where | Defect | Fix |
|---|---|---|
| `virtual_joystick.gd` | degenerate radius divided, NaN/inf positions used | `_safe_radius()`; non-finite samples dropped; `get_value()` never returns non-finite |
| `touch_controls.gd` | forwarded whatever the stick emitted | non-finite ⇒ neutral stick |
| `player_locomotion.gd` | accepted NaN input; bounds clamp latched poison | reject non-finite; repair transform per axis, zero velocity |
| `character_controller.gd` | no delta validation; raw velocity; bad camera yaw | single choke point `_apply_velocity()` sanitises in/out; delta finite+positive; yaw falls back to 0; speed clamped 0–40 |
| `camera_rig.gd` | unguarded lerp of solver result; non-finite `looking_at` | `_apply_follow_position()` sole writer; degenerate frames skipped; transform validated before assign |
| `camera_math.gd` | only finiteness helper had zero callers | `is_finite_v3()` / `is_finite_transform()` reject-don't-replace |
| `player_animation.gd` | null Animation length became a speed divisor | 0.3 s fallback unless finite + positive |
| shake / FOV controllers | last writer committed unvalidated transform/FOV | non-finite dropped; FOV bounded 1–179 (bad FOV corrupts every HUD unproject) |
| `arena_hazards.gd` | ticked freed markers; non-finite knockback centre | visual resolved via typed `HazardMarker`; non-finite centre skipped |

**Diagnostics:** the first refusal per process logs one warning naming the boundary
(e.g. `CharacterController: refused non-finite …; locomotion held steady instead of
crashing.`) — the game now survives to report the real bug in logcat.

## 3. Startup stability — boot crash & invisible player (2026-09-08)

- **RC1 — invisible player.** `player.tscn` had no primitive `Body`; any runtime model
  load failure left the player invisible with an info-only log. Fixed by the `Body`
  capsule fallback plus mount-failure warnings naming the resolved path and whether a
  fallback exists (`visual_mount.gd`, `character_visuals.gd::_report_mount_issue`).
- **RC2 — non-deterministic autoload order.** `GameRoot` was declared before
  `SaveManager`, so `_ready()` read default bests for the whole session. Fixed with a
  dependency-first autoload order (EventBus → DebugErrorHandler → SaveManager →
  AudioManager → ContentRegistry → GameRoot → …) and `_finalize_run()` re-adopting the
  authoritative bests from the save store after recording.
- **RC3 — silent bootstrap failure.** `Main.build_world()` returned silently on a
  missing `WorldRoot`; spawn/wave failures degraded quietly. Fixed with structured
  `report_error`/`report_diagnostic` guards that fail closed and name the failing
  resource path, plus `_validate_player_visual()`.

**Verification limits (both postmortems):** the fixes were validated statically and
through the headless suites; the on-device confirmation (sideload the CI APK, watch
logcat) remains the release-step check. No runtime behaviour is claimed without it.
