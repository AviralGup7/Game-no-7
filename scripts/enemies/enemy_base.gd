extends Damageable
class_name EnemyBase

## Reusable enemy base: the archetype root every enemy scene inherits. It owns the
## lifecycle (spawn/reward state, the StateMachine binding, the movement intent the AI
## writes) and the typed command surface the state scripts, BossController, SpawnManager
## and the campaign call. The behaviour itself lives in cohesive typed components:
##
##   EnemyCombatResponse — damage intake, status riders, poise, exactly-once death
##   EnemyMotion         — locomotion, navigation, movement override, dash gate, facing
##   EnemyBrain          — perception, personality, per-run identity, nav grid, clock
##   EnemyPresentation   — telegraph ring + archetype visual scale
##   EnemyEliteKit       — affix cache, tint/scale, FRENZIED cadence, VAMPIRIC heal
##   EnemyDebugView      — the read-only debug snapshot
##
## TYPED COMPONENT ARCHITECTURE (see docs/ARCHITECTURE.md):
##   REQUIRED : HealthComponent, EnemyStateMachine — every production scene and every
##              test fixture provides both; a variant without them fails fast.
##   OPTIONAL : EnemyFeedback, EnemyAudio, StatusManager, NavigationAgent3D — nullable
##              typed references (minimal headless fixtures legitimately omit them).
## The combat seam to the player is the Damageable protocol (apply_damage/is_alive),
## shared with Player; no has_method()/.call() string dispatch anywhere.
##
## Command surface for states/controllers (states NEVER reach into the components):
##   set_desired_move / face_target / face_direction / get_navigation_direction
##   set_move_override / clear_move_override      (telegraphs, charges, recoveries)
##   set_poise_guard                              (windup interruption budget)
##   perform_enemy_attack / perform_dash_strike / detonate_self
##   try_begin_dash                               (cooldown-gated dash entry)
##   state_machine_change_to / force_state / get_state
## EventBus is resolved lazily through the tree so the same code runs in-game and in
## the autoload-free headless test harness (run_tests.gd is hermetic by design).

signal initialized(archetype_id: StringName)
## Emitted by the state scripts and the combat-response collaborator on the host's
## behalf: the analyzer only counts usages inside this file, so pin the exemption
## right at the declaration.
@warning_ignore("unused_signal")
signal state_changed(previous_state: StringName, current_state: StringName)
@warning_ignore("unused_signal")
signal damaged(result: DamageResult)
@warning_ignore("unused_signal")
signal died()
@warning_ignore("unused_signal")
signal attack_started()
@warning_ignore("unused_signal")
signal attack_hit(target: Node, result: DamageResult)
@warning_ignore("unused_signal")
signal despawn_requested(enemy: Node)

const TARGET_GROUP := "enemies"

## Config fallbacks used when an enemy runs without a config (headless probes).
const FALLBACK_MAX_HEALTH := 1.0
const FALLBACK_MOVE_SPEED := 2.0
const FALLBACK_ATTACK_DAMAGE := 5.0
const FALLBACK_ATTACK_COOLDOWN := 1.2
const FALLBACK_DASH_SPEED := 12.0

## Lifecycle + reward payload (read by the death path and the debug snapshot).
var _archetype_id: StringName = &"uninitialized"
var _config: EnemyConfig = null
var _alive := false
var _death_handled := false
var _score_value: int = 0
var _currency_value: int = 0

## REQUIRED components.
var _health: HealthComponent = null
var _machine: EnemyStateMachine = null

## OPTIONAL components (nullable by design; minimal fixtures omit them).
var _feedback: EnemyFeedback = null
var _audio: EnemyAudio = null
var _status: StatusManager = null
var _boss: BossController = null

var _target: Node3D = null
var _striker := EnemyStriker.new()

## Pack coordination module (hearing alerts, grief retreat, separation
## steering, bus wiring) — see EnemyPack.
var _pack := EnemyPack.new()

## Movement intent produced by the current state; the pack's separation steering
## blends into desired_dir, so both stay public on the host.
var desired_dir := Vector3.ZERO
var desired_speed := 0.0

var _ai_enabled := true

## Per-run difficulty scaling applied at spawn without mutating the shared config.
var _hp_scale := 1.0
var _damage_scale := 1.0
var _speed_scale := 1.0

## Typed components (each file documents its own ownership; the host keeps the API).
var _response := EnemyCombatResponse.new()
var _motion := EnemyMotion.new()
var _brain := EnemyBrain.new()
var _presentation := EnemyPresentation.new()
var _elite := EnemyEliteKit.new()

var _event_bus: EventBusService = null
var _event_bus_resolved := false
var _bus_connected := false


func _ready() -> void:
	if not is_inside_tree():
		return
	add_to_group(TARGET_GROUP)
	_pack.bind(self)
	_connect_bus_signals()
	_resolve_components()
	if not _check_required_components():
		return
	_motion.bind_navigator(get_node_or_null("NavigationAgent3D") as NavigationAgent3D)
	if not _health.damaged.is_connected(_on_damaged):
		_health.damaged.connect(_on_damaged)
	if not _health.died.is_connected(_on_died):
		_health.died.connect(_on_died)


## Resolve every component reference ONCE, as its concrete type. A wrong script on
## a child node yields null here, which the required-component check reports by name.
func _resolve_components() -> void:
	_health = get_node_or_null("HealthComponent") as HealthComponent
	_machine = get_node_or_null("EnemyStateMachine") as EnemyStateMachine
	_feedback = get_node_or_null("EnemyFeedback") as EnemyFeedback
	_audio = get_node_or_null("EnemyAudio") as EnemyAudio
	_status = get_node_or_null("StatusManager") as StatusManager
	_boss = get_node_or_null("BossController") as BossController


## Fail fast when a REQUIRED component is missing: debug/test builds assert on the
## spot, release builds log once and stop processing instead of silently spawning a
## non-functional enemy.
func _check_required_components() -> bool:
	var missing := PackedStringArray()
	if _health == null:
		missing.append("HealthComponent")
	if _machine == null:
		missing.append("EnemyStateMachine")
	if missing.is_empty():
		return true
	push_error("EnemyBase requires components missing from its scene: %s — fix the enemy scene variant." % ", ".join(missing))
	assert(false, "EnemyBase missing required components: %s" % ", ".join(missing))
	set_physics_process(false)
	return false


## Lazy, cached autoload lookup: identical to a direct reference in-game, null-safe
## under the bare headless test SceneTree (run_tests.gd is autoload-free by design).
func _eb() -> EventBusService:
	if not _event_bus_resolved:
		_event_bus_resolved = true
		if is_inside_tree():
			_event_bus = get_node_or_null("/root/EventBus") as EventBusService
	return _event_bus


## Typed form of _eb() for the components (EnemyCombatResponse emits the damage/kill
## contract onto the bus; null in the bare harness, where nothing is emitted).
func get_event_bus() -> EventBusService:
	return _eb()


func _exit_tree() -> void:
	_pack.disconnect_signals()
	_event_bus = null
	_bus_connected = false


## Wire the EventBus signals that drive pack awareness (delegated to
## EnemyPack). Null-safe: in the bare headless harness there is no bus and
## nothing happens; retried on the first physics tick so a bus that appears
## after _ready (test harness ordering) still connects.
func _connect_bus_signals() -> void:
	if _bus_connected:
		return
	var bus := _eb()
	if bus == null:
		return
	_pack.connect_signals(bus)
	_bus_connected = true


## One-shot transition into the dead state; returns false when death was already
## handled (the idempotency guard EnemyCombatResponse relies on). The flags live on
## the host because the AI, the death path and tests all read them.
func mark_dead() -> bool:
	if _death_handled:
		return false
	_death_handled = true
	_alive = false
	return true


func is_death_handled() -> bool:
	return _death_handled


## Components, exposed for the modules that must cooperate (combat response applies
## knockback to the motion integrator; the elite kit bumps the visual scale).
func get_motion() -> EnemyMotion:
	return _motion


func get_presentation() -> EnemyPresentation:
	return _presentation


func set_ai_enabled(enabled: bool) -> void:
	_ai_enabled = enabled
	if not enabled:
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0


func is_ai_enabled() -> bool:
	return _ai_enabled


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_brain.tick(delta)
	if _config == null or not _alive or not _ai_enabled:
		return
	_motion.tick(delta)
	_response.decay_poise(delta)
	_pack.update(delta)
	if _is_status_stunned():
		# Stunned: no AI, no intent; gravity + knockback decay still run.
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		_motion.freeze(self, delta)
		return
	if not _bus_connected:
		_connect_bus_signals()  # the bus may appear after _ready (test harness)
	# Perception runs BEFORE the state machine so every state queries this
	# frame's awareness (a human answers the stimulus it can actually sense).
	var target := get_move_target()
	if target != null:
		_brain.perception.update(delta, global_position, _brain.flat_forward(self), target.global_position, true)
	_machine.physics_update(delta)
	if not _motion.is_overridden():
		_pack.apply_separation(delta)
	_motion.step(self, _status_speed_factor(), delta)


## ---------- Stable command interface (Phase 2 preserved) ----------

func initialize(config: EnemyConfig, target: Node3D, run_seed: int = 0) -> void:
	if config == null:
		push_warning("EnemyBase.initialize received null config")
		return
	_config = config
	_archetype_id = config.archetype_id
	_score_value = config.score_value
	_currency_value = config.currency_value
	_target = target
	_alive = true
	_death_handled = false
	_brain.set_run_seed(run_seed)
	_motion.configure(config)
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	_response.set_poise_guard(false)
	if _health != null:
		_health.reset(config.max_health)
	if _feedback != null:
		_feedback.recolor(config.color_tint)
	_presentation.apply_visual_scale(self, config.visual_scale)
	# Presentation hook (Agent 4): mount the archetype's approved model under
	# VisualRoot/CharacterModel. No gameplay effect; primitives remain if absent.
	# Skip when a dedicated EnemyAnimator node is present — it already mounts
	# the same model via its own PackedScene (avoids double-model overlap).
	if get_node_or_null("EnemyAnimator") == null and CharacterVisuals.has_model(config.archetype_id):
		CharacterVisuals.mount(self, config.archetype_id)
	_machine.force_state(&"idle")
	_motion.reset_navigator(target)
	_brain.remember_home(self)
	_pack.reset()
	_brain.reset_perception(config)
	initialized.emit(_archetype_id)


func get_state() -> StringName:
	if _machine == null:
		return &""
	return _machine.get_current()


func is_alive() -> bool:
	return _alive


func get_archetype_id() -> StringName:
	return _archetype_id


func get_config() -> EnemyConfig:
	return _config


func get_score_value() -> int:
	return _score_value


func get_currency_value() -> int:
	return _currency_value


func force_state(state_id: StringName) -> void:
	if _machine != null:
		_machine.force_state(state_id)


## Regular (non-forcing) transition facade used by AI states; refused if already current.
func state_machine_change_to(state_id: StringName) -> void:
	if _machine != null:
		_machine.change_to(state_id)


func get_move_target() -> Node3D:
	if _target == null or not is_instance_valid(_target):
		return null
	# Damageable is the explicit combat protocol: only a Damageable target has a
	# meaningful alive check (a plain Node3D stand-in is treated as present).
	if _target is Damageable and not (_target as Damageable).is_alive():
		return null
	return _target


func set_desired_move(dir: Vector3, speed: float) -> void:
	desired_dir = dir
	desired_speed = maxf(speed, 0.0)


func get_visual_root() -> Node3D:
	return get_node_or_null("VisualRoot") as Node3D


func get_hit_radius() -> float:
	var cfg := get_config()
	return cfg.bounds_radius if cfg != null else 0.0


func get_debug_snapshot() -> Dictionary:
	return EnemyDebugView.snapshot(self)


## No-op hook kept for the states' "hurt has started" call (reserved for feedback).
func note_hurt_started() -> void:
	pass


## ---------- Damage / death (Phase 2 exactly-once preserved) ----------

func apply_damage(payload: DamagePayload) -> DamageResult:
	return _response.apply_damage(self, payload)


func _on_damaged(result: DamageResult) -> void:
	_response.respond_to_damage(self, result)


func _on_died() -> void:
	_response.handle_death(self)


func get_health_fraction() -> float:
	return _response.health_fraction(self)


## ---------- Attacks ----------

## Controlled melee attack against the current target (see EnemyStriker). Returns
## true when a hit lands; damage is applied exactly once per call.
func perform_enemy_attack() -> bool:
	return _striker.execute(self)


## Dash-charge contact hit (see EnemyStriker.execute_dash): larger radius, scaled
## damage, exactly one hit per charge (the dash state calls this once).
func perform_dash_strike(contact_radius: float) -> bool:
	return _striker.execute_dash(self, contact_radius)


## Lethal self-damage routed through the HealthComponent so the normal exactly-once
## death path fires (score payload, despawn, death-blast dispatch in SpawnManager).
func detonate_self() -> void:
	_response.detonate_self(self)


func target_in_attack_range(target: Node3D) -> bool:
	if target == null:
		return false
	var cfg := _config
	var range_val := cfg.attack_range if cfg != null else 1.5
	return global_position.distance_to(target.global_position) <= range_val


## ---------- Movement, facing, navigation (see EnemyMotion) ----------

## Apply wave difficulty scaling (>=1.0). Resets health to the scaled maximum.
func apply_difficulty(hp_scale: float, damage_scale: float, speed_scale: float) -> void:
	_hp_scale = maxf(hp_scale, 1.0)
	_damage_scale = maxf(damage_scale, 1.0)
	_speed_scale = maxf(speed_scale, 1.0)
	if _health != null:
		_health.reset(_scaled_max_health())


func _scaled_max_health() -> float:
	var cfg := _config
	var base := cfg.max_health if cfg != null else FALLBACK_MAX_HEALTH
	return base * _hp_scale


func get_effective_speed() -> float:
	var cfg := _config
	var base := cfg.move_speed if cfg != null else FALLBACK_MOVE_SPEED
	return base * _speed_scale


func get_effective_attack_damage() -> float:
	var cfg := _config
	var base := cfg.attack_damage if cfg != null else FALLBACK_ATTACK_DAMAGE
	return base * _damage_scale


## Attack cadence: base cooldown, sped up for wounded FRENZIED elites. Never
## mutates the shared config.
func get_effective_attack_cooldown() -> float:
	var cfg := _config
	var base := cfg.attack_cooldown if cfg != null else FALLBACK_ATTACK_COOLDOWN
	return base * _elite.attack_cooldown_multiplier(get_health_fraction())


## Charge speed honoring wave/mutator speed scaling (config never mutated).
func get_effective_dash_speed() -> float:
	var cfg := _config
	var base := cfg.dash_speed if cfg != null else FALLBACK_DASH_SPEED
	return base * _speed_scale


## Boss phase bumps: multiply the CURRENT effective scales (stacks with wave
## scaling without touching the shared config).
func apply_phase_modifiers(damage_mult: float, speed_mult: float) -> void:
	_damage_scale *= maxf(damage_mult, 0.01)
	_speed_scale *= maxf(speed_mult, 0.01)


## Set arena-bound half extent; -1 disables the clamp.
func set_bounds(half: float) -> void:
	_motion.set_bounds(half)


func set_velocity_flat(flat: Vector3) -> void:
	_motion.set_velocity_flat(self, flat)


## While active, the override replaces whatever the AI states request. Pass a
## zero dir + zero speed to root the enemy in place (boss telegraph/recovery).
func set_move_override(dir: Vector3, speed: float, duration: float) -> void:
	_motion.set_override(dir, speed, duration)


func clear_move_override() -> void:
	_motion.clear_override()


func is_move_overridden() -> bool:
	return _motion.is_overridden()


## Poise guard: heavy/boss windups are not interrupted by chip damage.
func set_poise_guard(active: bool) -> void:
	_response.set_poise_guard(active)


func is_poise_guarding() -> bool:
	return _response.is_poise_guarding()


## Cooldown-gated dash entry from the Chase state.
func try_begin_dash() -> bool:
	return _motion.try_begin_dash(self)


func is_dash_ready() -> bool:
	return _motion.is_dash_ready()


func face_direction(dir: Vector3) -> void:
	_motion.face_direction(self, dir)


func face_target(target: Node3D) -> void:
	_motion.face_target(self, target)


## Navigation-aware steering (see EnemyNavigator): prefers the shared nav grid
## (line of sight, else flow field around obstacles), then the navmesh, then
## the caller's direct direction.
func get_navigation_direction(fallback: Vector3) -> Vector3:
	return _motion.direction(self, fallback)


## Steer toward a fixed world point (investigation / waypoint) through the nav
## grid when wired; direct steering otherwise.
func get_navigation_direction_toward(point: Vector3, fallback: Vector3, delta: float) -> Vector3:
	return _motion.direction_toward(self, point, fallback, delta)


## ---------- Brain accessors (read-only, for AI states) ----------

## Wire (or clear) the shared arena navigation grid. Also gives perception its
## line-of-sight check so sight is blocked by the same geometry physics uses.
func set_nav_grid(grid: ArenaNavGrid) -> void:
	_brain.set_nav_grid(grid)
	_motion.set_grid(grid)


func get_nav_grid() -> ArenaNavGrid:
	return _brain.get_nav_grid()


func get_perception() -> EnemyPerception:
	return _brain.perception


func get_personality() -> EnemyPersonality:
	return _brain.personality


## Fresh deterministic 0..1 roll from this enemy's decision stream.
func personality_roll() -> float:
	return _brain.personality_roll()


func get_run_seed() -> int:
	return _brain.get_run_seed()


func get_spawn_serial() -> int:
	return _brain.get_spawn_serial()


## Deterministic per-run identity (approach offset + personality + decision stream).
func set_spawn_serial(serial: int) -> void:
	_brain.set_spawn_serial(self, serial)


## The point this enemy actually tries to stand at: the target position nudged by
## its personal offset, so packs fan out instead of stacking on one pixel.
func get_approach_point(point: Vector3) -> Vector3:
	return _brain.get_approach_point(point)


func get_home_position() -> Vector3:
	return _brain.get_home_position()


## True while a griefed (cautious, wounded) enemy backs off after nearby allies
## died — the chase state honors it for EnemyPack.FEAR_DURATION seconds.
func is_fear_retreating() -> bool:
	return _pack.is_retreating()


## Accumulated physics seconds since spawn (monotonic per run); the pack
## module timestamps grief kills against this clock.
func get_run_time() -> float:
	return _brain.get_run_time()


## Cooldown multiplier for this swing ([-jitter,+jitter] scaled by personality
## spread). Packs stop sharing one attack clock; melee hits land spread out.
func get_attack_cooldown_roll() -> float:
	return _brain.attack_cooldown_roll(self)


## Can this enemy currently see `point` (grid line of sight)? True without a
## grid — physics collision still covers the worst case.
func has_line_of_sight_to(point: Vector3) -> bool:
	return _brain.has_line_of_sight_to(self, point)


## Ranged aim quality (0 sloppy .. 1 precise), from the rolled personality.
func get_aim_skill() -> float:
	return _brain.get_aim_skill()


## ---------- Elite affixes (see EnemyEliteKit) ----------

## Mark this enemy elite with the given affixes (see EliteAffix). Visual tint
## blends the affixes; scale bumps slightly so elites read at a glance.
func set_elite(affixes: Array) -> void:
	_elite.set_affixes(self, affixes)
	# Keep the serial-rolled offset; re-rolling here would break run determinism.
	# Behavior affix hooks: VAMPIRIC elites sustain off the damage they deal.
	if _elite.has(EliteAffix.VAMPIRIC) and not attack_hit.is_connected(_on_vampiric_hit):
		attack_hit.connect(_on_vampiric_hit)


func _on_vampiric_hit(_hit_target: Node, result: DamageResult) -> void:
	_elite.heal_from_hit(self, result)


func is_elite() -> bool:
	return _elite.is_elite()


func get_elite_affixes() -> Array:
	return _elite.get_affixes()


## ---------- Feedback / audio hooks (tolerant when children are absent) ----------

func play_attack_sound() -> void:
	if _audio != null:
		_audio.play_attack()


func play_spawn_sound() -> void:
	if _audio != null:
		_audio.play_spawn()


func play_windup_sound() -> void:
	if _audio != null:
		_audio.play_windup()


func play_dash_sound() -> void:
	if _audio != null:
		_audio.play_dash()


func play_explosion_sound() -> void:
	if _audio != null:
		_audio.play_explosion()


## Telegraph flash (melee windups, dash windups, fuses, boss tells) + the ground
## ring that makes the tell readable on sand.
func play_telegraph_feedback() -> void:
	if _feedback != null:
		_feedback.play_telegraph()
	_presentation.play_telegraph_ring(self)


## ---------- StatusManager queries (optional component; nullable typed ref) ----------

func _is_status_stunned() -> bool:
	return _status != null and _status.is_stunned()


func _status_speed_factor() -> float:
	if _status != null:
		return clampf(_status.move_speed_factor(), 0.0, 2.0)
	return 1.0


## Damageable component seams (see the doc comment on Damageable): these are the refs
## _ready() already resolved, so hazards and AoE never walk the node path again -- except on the null
## branch, which is how a scene variant that attaches its manager after `_ready` (a mod, or a harness
## that packs the enemy in code) reaches the subsystem at all instead of returning nothing forever.
func get_status_manager() -> StatusManager:
	if _status == null:
		_status = get_node_or_null("StatusManager") as StatusManager
	return _status


func get_health_component() -> HealthComponent:
	if _health == null:
		_health = get_node_or_null("HealthComponent") as HealthComponent
	return _health


func get_boss_controller() -> BossController:
	if _boss == null:
		_boss = get_node_or_null("BossController") as BossController
	return _boss


func get_feedback() -> EnemyFeedback:
	if _feedback == null:
		_feedback = get_node_or_null("EnemyFeedback") as EnemyFeedback
	return _feedback


func get_audio() -> EnemyAudio:
	if _audio == null:
		_audio = get_node_or_null("EnemyAudio") as EnemyAudio
	return _audio
