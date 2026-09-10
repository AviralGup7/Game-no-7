extends Damageable
class_name EnemyBase

## Reusable enemy base. Owns lifecycle, damage intake, idempotent death + exactly-once
## score payload (Phase 2 guarantees preserved), and the AI behaviour: a state machine
## (Idle/Chase/Attack/Hurt/Dead/Ranged/Dash/Fuse) driving movement intent, integrated
## by EnemyLocomotion (gravity/knockback/clamp/stall), steered by EnemyNavigator
## (navmesh), and striking through EnemyStriker (guarded melee + dash strikes).
## Resistance-aware knockback and arena-bound clamping included; attacks damage the
## player through the existing HealthComponent/apply_damage interface.
##
## TYPED COMPONENT ARCHITECTURE (see docs/ARCHITECTURE.md):
##   REQUIRED : HealthComponent, EnemyStateMachine — every production scene and every
##              test fixture provides both; a variant without them fails fast.
##   OPTIONAL : EnemyFeedback, EnemyAudio, StatusManager, NavigationAgent3D — nullable
##              typed references (minimal headless fixtures legitimately omit them).
## The combat seam to the player is the Damageable protocol (apply_damage/is_alive),
## shared with Player; no has_method()/.call() string dispatch anywhere.
##
## Command surface for states/controllers (states NEVER reach into internals):
##   set_desired_move / face_target / face_direction / get_navigation_direction
##   set_move_override / clear_move_override   (telegraphs, charges, recoveries)
##   set_poise_guard                            (windup interruption budget)
##   perform_enemy_attack / perform_dash_strike / detonate_self
##   try_begin_dash                             (cooldown-gated dash entry)
##   state_machine_change_to / force_state / get_state
## EventBus is resolved lazily through the tree so the same code runs in-game and in
## the autoload-free headless test harness (run_tests.gd is hermetic by design).

signal initialized(archetype_id: StringName)
## Emitted by the state scripts on the host's behalf: the analyzer only counts
## usages inside this file, so pin the exemption right at the declaration.
@warning_ignore("unused_signal")
signal state_changed(previous_state: StringName, current_state: StringName)
signal damaged(result: DamageResult)
signal died()
@warning_ignore("unused_signal")
signal attack_started()
@warning_ignore("unused_signal")
signal attack_hit(target: Node, result: DamageResult)
signal despawn_requested(enemy: Node)

const TARGET_GROUP := "enemies"
## Poise damage decays per second while the guard is up.
const POISE_DECAY_PER_SECOND := 25.0

var _archetype_id: StringName = &"uninitialized"
var _config: EnemyConfig = null
var _alive := false
var _death_handled := false
var _score_value: int = 0
var _currency_value: int = 0
var _run_seed: int = 0

## REQUIRED components.
var _health: HealthComponent = null
var _machine: EnemyStateMachine = null

## OPTIONAL components (nullable by design; minimal fixtures omit them).
var _feedback: EnemyFeedback = null
var _audio: EnemyAudio = null
var _status: StatusManager = null

var _target: Node3D = null
var _locomotion := EnemyLocomotion.new()
var _navigator := EnemyNavigator.new()
var _striker := EnemyStriker.new()

## Movement intent produced by the current state.
var desired_dir := Vector3.ZERO
var desired_speed := 0.0

var _ai_enabled := true

## Per-run difficulty scaling applied at spawn without mutating the shared config.
var _hp_scale := 1.0
var _damage_scale := 1.0
var _speed_scale := 1.0

## Movement override: while > 0 the override wins over whatever the AI states ask
## for. Used by dash charges, boss telegraphs/charges/recovery windows.
var _move_override_dir := Vector3.ZERO
var _move_override_speed := 0.0
var _move_override_time := 0.0

## Poise guard: while armed (windups), accepted damage accumulates instead of
## forcing Hurt until the config's poise budget breaks.
var _poise_guard := false
var _poise_damage := 0.0

## Dash cooldown owned by the host so the Chase state can gate entry without
## reaching into the dash state instance.
var _dash_cooldown_left := 0.0

## Deterministic per-enemy personality: approach offset keeps packs from stacking
## on the exact same spot behind the player.
var _spawn_serial := 0
var _approach_offset := Vector3.ZERO

## ---------- Human-like brain (see docs/ENEMY_AI_RESEARCH.md) ----------
## Perception (sight/FOV/LOS/hearing/reaction/memory) + a rolled personality
## turn identical archetypes into individuals: they notice on their own clock,
## flank, hesitate, grieve nearby kills and stop chasing players they cannot
## see. Both are pure RefCounted modules, headless-testable.
var _perception := EnemyPerception.new()
var _personality: EnemyPersonality = null
var _decisions_rng: RandomNumberGenerator = null
var _home_pos := Vector3.ZERO

## Shared arena navigation grid (flow field + A*). When wired, EnemyNavigator
## routes around pillars/landmark; EnemyPerception uses its LOS for sight.
var _nav_grid: ArenaNavGrid = null

## Pack coordination module (hearing alerts, grief retreat, separation
## steering, bus wiring) — see EnemyPack.
var _pack := EnemyPack.new()
var _bus_connected := false
var _run_time := 0.0

## Elite affix cache (set via set_elite; queried by cadence/vampiric hooks).
var _elite_affixes: Array[StringName] = []

var _event_bus: Node = null
var _event_bus_resolved := false


func _ready() -> void:
	if not is_inside_tree():
		return
	add_to_group(TARGET_GROUP)
	_pack.bind(self)
	_connect_bus_signals()
	_resolve_components()
	if not _check_required_components():
		return
	_navigator.bind(get_node_or_null("NavigationAgent3D") as NavigationAgent3D)
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
func _eb() -> Node:
	if not _event_bus_resolved:
		_event_bus_resolved = true
		if is_inside_tree():
			_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


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


func set_ai_enabled(enabled: bool) -> void:
	_ai_enabled = enabled
	if not enabled:
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_run_time += delta
	if _config == null or not _alive or not _ai_enabled:
		return
	_decay_timers(delta)
	if _is_status_stunned():
		# Stunned: no AI, no intent; gravity + knockback decay still run.
		desired_dir = Vector3.ZERO
		desired_speed = 0.0
		_locomotion.integrate(self, Vector3.ZERO, 0.0, 1.0, delta, false)
		FootPlant.apply(self, 0.16, delta)
		return
	if not _bus_connected:
		_connect_bus_signals()  # the bus may appear after _ready (test harness)
	# Perception runs BEFORE the state machine so every state queries this
	# frame's awareness (a human answers the stimulus it can actually sense).
	var target := get_move_target()
	if _perception != null and target != null:
		_perception.update(delta, global_position, _flat_forward(), target.global_position, true)
	_machine.physics_update(delta)
	if _move_override_time <= 0.0:
		_pack.apply_separation(delta)
	var dir := desired_dir
	var speed := desired_speed
	if _move_override_time > 0.0:
		dir = _move_override_dir
		speed = _move_override_speed
	_locomotion.integrate(self, dir, speed, _status_speed_factor(), delta)
	FootPlant.apply(self, 0.16, delta)


func _decay_timers(delta: float) -> void:
	if _move_override_time > 0.0:
		_move_override_time = maxf(_move_override_time - delta, 0.0)
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	if _poise_guard and _poise_damage > 0.0:
		_poise_damage = maxf(_poise_damage - POISE_DECAY_PER_SECOND * delta, 0.0)
	_pack.update(delta)


## Flat facing direction (visual yaw); used for the perception FOV cone.
func _flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.001:
		return Vector3.FORWARD
	return f.normalized()


## ---------- Stable command interface (Phase 2 preserved) ----------

func initialize(config: EnemyConfig, target: Node3D, run_seed: int = 0) -> void:
	if config == null:
		push_warning("EnemyBase.initialize received null config")
		return
	_config = config
	_archetype_id = config.archetype_id
	_score_value = config.score_value
	_currency_value = config.currency_value
	_run_seed = run_seed
	_target = target
	_alive = true
	_death_handled = false
	_locomotion.reset()
	_locomotion.configure(config.acceleration, _locomotion_bounds(), config.bounds_radius)
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	_move_override_time = 0.0
	_poise_guard = false
	_poise_damage = 0.0
	_dash_cooldown_left = 0.0
	if _health != null:
		_health.reset(config.max_health)
	if _feedback != null:
		_feedback.recolor(config.color_tint)
	_apply_visual_scale(config.visual_scale)
	# Presentation hook (Agent 4): mount the archetype's approved model under
	# VisualRoot/CharacterModel. No gameplay effect; primitives remain if absent.
	# Skip when a dedicated EnemyAnimator node is present — it already mounts
	# the same model via its own PackedScene (avoids double-model overlap).
	if get_node_or_null("EnemyAnimator") == null and CharacterVisuals.has_model(config.archetype_id):
		CharacterVisuals.mount(self, config.archetype_id)
	_machine.force_state(&"idle")
	_navigator.reset(target)
	_home_pos = global_position
	_pack.reset()
	_perception.reset()
	_configure_perception(config)
	initialized.emit(_archetype_id)


## Configure perception from config. detect_range > 0 (legacy) wins over
## vision_range; both zero = always aware (original behavior).
func _configure_perception(config: EnemyConfig) -> void:
	var vision := config.vision_range if config.detect_range <= 0.0 else config.detect_range
	var always_aware := vision <= 0.0
	_perception.configure(vision, config.vision_fov_degrees, config.hearing_range,
			config.reaction_time, config.memory_time, always_aware)
	var reaction := config.reaction_time * (_personality.reaction if _personality != null else 1.0)
	_perception.reaction_base = maxf(reaction, 0.0)
	if _nav_grid != null:
		_perception.set_los_check(Callable(_nav_grid, &"has_line_of_sight"))


func apply_damage(payload: DamagePayload) -> DamageResult:
	var result := DamageResult.new()
	if _health == null:
		result.ignored_reason = &"no_health_component"
		return result
	if not _alive:
		result.ignored_reason = DamageResult.IGNORE_DEAD
		return result
	# Status mitigation/shields are an intake stage, but do not consume a shield
	# for malformed or invulnerable hits that HealthComponent will reject.
	var final_payload := payload
	if payload != null and payload.is_valid() and not _health.is_invulnerable():
		final_payload = _apply_status_intake(payload)
	var res := _health.take_damage(final_payload)
	_on_damage_applied(res, payload)
	# Invulnerability, shields and dead-state rejection must not grant a
	# status proc. Only an accepted hit is allowed to advance a build synergy.
	if res.accepted and res.final_amount > 0.0:
		_apply_payload_status(payload, res)
	return res


## Projectile/melee riders: apply the payload's status effects to our manager.
func _apply_payload_status(payload: DamagePayload, result: DamageResult = null) -> void:
	if payload == null or payload.status_effects.is_empty():
		return
	if _status == null:
		return
	var applied := _status.apply_effects(payload.status_effects, payload.source)
	if result != null:
		for raw_id in applied:
			if int(applied[raw_id]) > 0:
				result.status_effects_applied.append(StringName(String(raw_id)))


func _apply_status_intake(payload: DamagePayload) -> DamagePayload:
	if _status == null or payload == null:
		return payload
	var amount := payload.amount * _status.incoming_damage_factor()
	amount = _status.absorb_direct(amount)
	if is_equal_approx(amount, payload.amount):
		return payload
	return payload.with_amount(amount)


func force_state(state_id: StringName) -> void:
	if _machine != null:
		_machine.force_state(state_id)


## Regular (non-forcing) transition facade used by AI states; refused if already current.
func state_machine_change_to(state_id: StringName) -> void:
	if _machine != null:
		_machine.change_to(state_id)


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


## Set arena-bound half extent; -1 disables the clamp.
func set_bounds(half: float) -> void:
	_locomotion.set_bounds(half)


func set_velocity_flat(flat: Vector3) -> void:
	velocity.x = flat.x
	velocity.z = flat.z


## Apply wave difficulty scaling (>=1.0). Resets health to the scaled maximum.
func apply_difficulty(hp_scale: float, damage_scale: float, speed_scale: float) -> void:
	_hp_scale = maxf(hp_scale, 1.0)
	_damage_scale = maxf(damage_scale, 1.0)
	_speed_scale = maxf(speed_scale, 1.0)
	if _health != null:
		_health.reset(_scaled_max_health())


func _scaled_max_health() -> float:
	var cfg := _config
	var base := cfg.max_health if cfg != null else 1.0
	return base * _hp_scale


func get_effective_speed() -> float:
	var cfg := _config
	var base := cfg.move_speed if cfg != null else 2.0
	return base * _speed_scale


func get_effective_attack_damage() -> float:
	var cfg := _config
	var base := cfg.attack_damage if cfg != null else 5.0
	return base * _damage_scale


## Attack cadence: base cooldown, sped up for wounded FRENZIED elites. Never
## mutates the shared config.
func get_effective_attack_cooldown() -> float:
	var cfg := _config
	var base := cfg.attack_cooldown if cfg != null else 1.2
	if EliteAffix.FRENZIED in _elite_affixes and get_health_fraction() < EliteAffix.FRENZIED_HP_TRIGGER:
		base *= EliteAffix.FRENZIED_COOLDOWN_MULT
	return base


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


## ---------- Movement override (telegraphs / charges / recoveries) ----------

## While active, the override replaces whatever the AI states request. Pass a
## zero dir + zero speed to root the enemy in place (boss telegraph/recovery).
func set_move_override(dir: Vector3, speed: float, duration: float) -> void:
	_move_override_dir = dir
	_move_override_speed = maxf(speed, 0.0)
	_move_override_time = maxf(duration, 0.0)


func clear_move_override() -> void:
	_move_override_time = 0.0


func is_move_overridden() -> bool:
	return _move_override_time > 0.0


## ---------- Poise (heavy/boss windups are not interrupted by chip damage) ----

func set_poise_guard(active: bool) -> void:
	_poise_guard = active
	if not active:
		_poise_damage = 0.0


func is_poise_guarding() -> bool:
	return _poise_guard


## ---------- Dash command (cooldown-gated entry from Chase) ----------

func try_begin_dash() -> bool:
	var cfg := _config
	if cfg == null or cfg.dash_trigger_range <= 0.0:
		return false
	if _dash_cooldown_left > 0.0 or not _alive:
		return false
	_dash_cooldown_left = cfg.dash_cooldown
	return true


func is_dash_ready() -> bool:
	return _dash_cooldown_left <= 0.0


## Charge speed honoring wave/mutator speed scaling (config never mutated).
func get_effective_dash_speed() -> float:
	var cfg := _config
	var base := cfg.dash_speed if cfg != null else 12.0
	return base * _speed_scale


## ---------- Spawn personality (deterministic per run) ----------

func set_spawn_serial(serial: int) -> void:
	_spawn_serial = maxi(serial, 0)
	_roll_approach_offset()
	# The deterministic cast: same (run_seed, serial) always rolls the same
	# individual. Re-entrant safe — identical inputs yield identical values.
	_personality = EnemyPersonality.roll(_run_seed, _spawn_serial)
	_decisions_rng = RngService.make_generator(_run_seed, RngService.STREAM_AI + _spawn_serial * 13 + 901)
	# Personality scales the reaction time now that the cast is known.
	if _config != null:
		_perception.reaction_base = maxf(_config.reaction_time * _personality.reaction, 0.0)


func _roll_approach_offset() -> void:
	if _config == null:
		return
	var rng := RngService.make_generator(_run_seed, RngService.STREAM_AI + _spawn_serial * 7 + 3)
	var angle := rng.randf_range(-PI, PI)
	var radius := rng.randf_range(0.55, 2.1) if is_elite() else rng.randf_range(0.0, 1.6)
	_approach_offset = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## The point this enemy actually tries to stand at: the target position nudged by
## its personal offset, so packs fan out instead of stacking on one pixel.
func get_approach_point(point: Vector3) -> Vector3:
	return point + _approach_offset


## ---------- Navigation / facing ----------

func target_in_attack_range(target: Node3D) -> bool:
	if target == null:
		return false
	var cfg := _config
	var range_val := cfg.attack_range if cfg != null else 1.5
	return global_position.distance_to(target.global_position) <= range_val


func face_direction(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var visual := get_node_or_null("VisualRoot") as Node3D
	if visual == null:
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	visual.look_at(visual.global_position + flat, Vector3.UP)


func face_target(target: Node3D) -> void:
	if target == null:
		return
	face_direction(target.global_position - global_position)


## Navigation-aware steering (see EnemyNavigator): prefers the shared nav grid
## (line of sight, else flow field around obstacles), then the navmesh, then
## the caller's direct direction.
func get_navigation_direction(fallback: Vector3) -> Vector3:
	var interval := _config.navigation_target_update_interval if _config != null else 0.2
	return _navigator.direction(global_position, get_move_target(), fallback, interval)


## Steer toward a fixed world point (investigation / waypoint) through the nav
## grid when wired; direct steering otherwise.
func get_navigation_direction_toward(point: Vector3, fallback: Vector3, delta: float) -> Vector3:
	return _navigator.direction_toward(global_position, point, fallback, delta)


## ---------- Brain accessors (read-only, for AI states) ----------

## Wire (or clear) the shared arena navigation grid. Also gives perception its
## line-of-sight check so sight is blocked by the same geometry physics uses.
func set_nav_grid(grid: ArenaNavGrid) -> void:
	_nav_grid = grid
	_navigator.set_grid(grid)
	_perception.set_los_check(Callable(grid, &"has_line_of_sight") if grid != null else Callable())


func get_nav_grid() -> ArenaNavGrid:
	return _nav_grid


func get_perception() -> EnemyPerception:
	return _perception


func get_personality() -> EnemyPersonality:
	return _personality


## Fresh deterministic 0..1 roll from this enemy's decision stream.
func personality_roll() -> float:
	if _decisions_rng == null:
		return 0.5
	return _decisions_rng.randf()


func get_run_seed() -> int:
	return _run_seed


func get_spawn_serial() -> int:
	return _spawn_serial


func get_home_position() -> Vector3:
	return _home_pos


## True while a griefed (cautious, wounded) enemy backs off after nearby allies
## died — the chase state honors it for EnemyPack.FEAR_DURATION seconds.
func is_fear_retreating() -> bool:
	return _pack.is_retreating()


## Accumulated physics seconds since spawn (monotonic per run); the pack
## module timestamps grief kills against this clock.
func get_run_time() -> float:
	return _run_time


## Cooldown multiplier for this swing ([-jitter,+jitter] scaled by personality
## spread). Packs stop sharing one attack clock; melee hits land spread out.
func get_attack_cooldown_roll() -> float:
	var cfg := _config
	if cfg == null or cfg.attack_cd_jitter <= 0.0:
		return 1.0
	var n := personality_roll()
	var spread := cfg.attack_cd_jitter * (_personality.cd_spread if _personality != null else 0.5)
	return clampf(1.0 + (n * 2.0 - 1.0) * spread, 0.6, 1.4)


## Can this enemy currently see `point` (grid line of sight)? True without a
## grid — physics collision still covers the worst case.
func has_line_of_sight_to(point: Vector3) -> bool:
	if _nav_grid == null or not _nav_grid.is_built():
		return true
	return _nav_grid.has_line_of_sight(global_position, point)


## Ranged aim quality (0 sloppy .. 1 precise), from the rolled personality.
func get_aim_skill() -> float:
	return _personality.aim_skill if _personality != null else 0.55


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
	if not _alive or _health == null:
		return
	var payload := DamagePayload.new()
	payload.amount = _current_health() + 999.0
	payload.source = self
	payload.source_id = _archetype_id
	payload.damage_type = &"explosion"
	_health.take_damage(payload)


func _current_health() -> float:
	if _health != null:
		return maxf(_health.get_current(), 0.0)
	return 0.0


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


## Telegraph flash (melee windups, dash windups, fuses, boss tells).
func play_telegraph_feedback() -> void:
	if _feedback != null:
		_feedback.play_telegraph()
	_show_attack_telegraph_ring()


## Ground ring in the same yellow/red language as bosses so grunt/heavy windups
## read at 30 FPS on sand arenas, not only as a mesh flash.
func _show_attack_telegraph_ring() -> void:
	if not is_inside_tree():
		return
	var director := get_tree().get_first_node_in_group("effect_director") as EffectDirector
	if director == null:
		return
	var radius := 1.35
	var cfg := _config
	if cfg != null:
		radius = clampf(cfg.attack_range * 0.85, 1.1, 3.4)
		if cfg.visual_scale > 1.15:
			radius *= 1.25
	var is_boss := get_node_or_null("BossController") != null
	if not director.try_telegraph(is_boss):
		return
	var prio := EffectDirector.PRIORITY_BOSS if is_boss else EffectDirector.PRIORITY_SPAWN
	if is_boss:
		director.ring_at(global_position, Color(1.0, 0.95, 0.15), radius + 0.45, prio)
		director.ring_at(global_position, Color(0.95, 0.08, 0.08), radius, prio)
	else:
		# One ring: yellow-red ink so it still reads on sand without a second disc.
		director.ring_at(global_position, Color(1.0, 0.55, 0.08), radius, prio)


func _locomotion_bounds() -> float:
	return _locomotion.get_bounds()


func _apply_visual_scale(scale_factor: float) -> void:
	var visual := get_node_or_null("VisualRoot") as Node3D
	if visual != null and scale_factor > 0.0:
		visual.scale = Vector3.ONE * scale_factor


func note_hurt_started() -> void:
	pass


## ---------- Damage / death (Phase 2 exactly-once preserved) ----------

func _on_damage_applied(result: DamageResult, payload: DamagePayload) -> void:
	if not result.accepted:
		return
	# Pain reveals the attacker: even an unaware enemy snaps its attention to
	# whoever hurt it (a stimulus, not a mind read — it still needs its
	# reaction beat before committing).
	if _perception != null and not _perception.can_engage() and payload != null:
		var source := payload.source
		if source != null and source != self and source is Node3D:
			_perception.note_noise((source as Node3D).global_position, 1.0, global_position)
	var cfg := _config
	var resistance := cfg.knockback_resistance if cfg != null else 0.0
	var resisted := payload.knockback * (1.0 - clampf(resistance, 0.0, 1.0))
	# Runtime guard (replaces the dead _validated_knockback helper): a NaN/inf
	# knockback must never reach the integrator, and runaway magnitudes are capped.
	if not is_finite(resisted.x) or not is_finite(resisted.y) or not is_finite(resisted.z):
		resisted = Vector3.ZERO
	elif resisted.length_squared() > 10000.0:
		resisted = resisted.normalized() * 100.0
	_locomotion.add_knockback(resisted)


func _on_damaged(result: DamageResult) -> void:
	damaged.emit(result)
	# EventBus contract: exactly one enemy_damaged per ACCEPTED damage event. HealthComponent
	# emits its local `damaged` signal only on the accepted path, so this is exactly-once.
	var bus := _eb()
	if bus != null:
		bus.enemy_damaged.emit(self, result)
	if result.was_critical and _feedback != null:
		_feedback.play_crit()
	elif _feedback != null:
		_feedback.play_damaged()
	if _audio != null:
		_audio.play_hit()
	if result.was_critical:
		_juice_hitstop(0.04, 0.16)
	if not _alive:
		return
	# Poise: while a windup is guarded, chip damage accumulates instead of
	# interrupting; only breaking the budget (or an over-budget hit) staggers.
	if _poise_guard:
		var cfg := _config
		var budget := cfg.poise if cfg != null else 0.0
		if budget > 0.0:
			_poise_damage += result.final_amount
			if _poise_damage < budget:
				return
			_poise_damage = 0.0
	if _machine != null:
		_machine.force_state(&"hurt")


func _on_died() -> void:
	if _death_handled:
		return
	_death_handled = true
	_alive = false
	desired_dir = Vector3.ZERO
	desired_speed = 0.0
	clear_move_override()
	set_poise_guard(false)
	if _machine != null:
		_machine.force_state(&"dead")
	died.emit()
	var bus := _eb()
	if bus != null:
		bus.report_info("Enemy %s died" % String(_archetype_id))
		# Exactly-once score payload.
		bus.enemy_killed.emit(self, _archetype_id, _score_value, _currency_value)
	despawn_requested.emit(self)
	if _feedback != null:
		_feedback.play_died()
	if _audio != null:
		_audio.play_death()
	_juice_hitstop(0.05, 0.2)
	_fade_and_free()


## Crit/death punch: micro-freeze + trauma through the run's HitstopManager.
func _juice_hitstop(duration: float, trauma: float) -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("hitstop_manager"):
		if node == null or not is_instance_valid(node):
			continue
		var manager := node as HitstopManager
		if manager == null:
			continue
		manager.request_hitstop(duration)
		manager.add_trauma(trauma)
		break  # Only one manager owns the global time_scale; avoid stacking the freeze


func _fade_and_free() -> void:
	if not is_inside_tree():
		queue_free()
		return
	# Slightly longer than the feedback sink so death animations get to land.
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_callback(queue_free)


## ---------- Elite + boss-phase API (SpawnManager / BossController) ----------

## Mark this enemy elite with the given affixes (see EliteAffix). Visual tint
## blends the affixes; scale bumps slightly so elites read at a glance.
func set_elite(affixes: Array) -> void:
	_elite_affixes.clear()
	for raw in affixes:
		_elite_affixes.append(StringName(String(raw)))
	set_meta("elite_affixes", _elite_affixes.duplicate())
	var tint := Color.WHITE
	for affix in _elite_affixes:
		tint = tint.blend(EliteAffix.affix_tint(affix))
	if _feedback != null:
		_feedback.recolor(tint)
	_apply_visual_scale((_config.visual_scale if _config != null else 1.0) * 1.12)
	# Keep the serial-rolled offset; re-rolling here would break run determinism.
	# Behavior affix hooks: VAMPIRIC elites sustain off the damage they deal.
	if EliteAffix.VAMPIRIC in _elite_affixes and not attack_hit.is_connected(_on_vampiric_hit):
		attack_hit.connect(_on_vampiric_hit)


func _on_vampiric_hit(_target: Node, result: DamageResult) -> void:
	if result == null or not result.accepted or not _alive:
		return
	if _health != null:
		_health.heal(result.final_amount * EliteAffix.VAMPIRIC_HEAL_RATIO)


func is_elite() -> bool:
	return not _elite_affixes.is_empty()


func get_elite_affixes() -> Array:
	return _elite_affixes.duplicate()


## Boss phase bumps: multiply the CURRENT effective scales (stacks with wave
## scaling without touching the shared config).
func apply_phase_modifiers(damage_mult: float, speed_mult: float) -> void:
	_damage_scale *= maxf(damage_mult, 0.01)
	_speed_scale *= maxf(speed_mult, 0.01)


## ---------- StatusManager queries (optional component; nullable typed ref) ----------

func _is_status_stunned() -> bool:
	return _status != null and _status.is_stunned()


func _status_speed_factor() -> float:
	if _status != null:
		return clampf(_status.move_speed_factor(), 0.0, 2.0)
	return 1.0


func get_health_fraction() -> float:
	if _health != null:
		return clampf(_health.get_health_ratio(), 0.0, 1.0)
	return 1.0 if _alive else 0.0


## Damageable component seams (see the doc comment on Damageable): these are the refs
## _ready() already resolved, so hazards and AoE never walk the node path again -- except on the null
## branch, which is how a scene variant that attaches its manager after `_ready` (a mod, or a harness
## that packs the enemy in code) reaches the subsystem at all instead of returning nothing forever.
func get_status_manager() -> StatusManager:
	if _status == null:
		_status = get_node_or_null("StatusManager") as StatusManager
	return _status


func get_health_component() -> HealthComponent:
	return _health


func get_hit_radius() -> float:
	var cfg := get_config()
	return cfg.bounds_radius if cfg != null else 0.0


func get_debug_snapshot() -> Dictionary:
	return {
		"archetype": String(_archetype_id),
		"state": String(get_state()),
		"alive": _alive,
		"death_handled": _death_handled,
		"position": global_position,
		"health": _health.get_debug_snapshot() if _health != null else {},
		"desired_dir": desired_dir,
		"desired_speed": desired_speed,
		"move_override": _move_override_time > 0.0,
		"poise_guard": _poise_guard,
		"elite": is_elite(),
		"perception": _perception.get_status_name(),
		"aggression": roundf(_personality.aggression * 100.0) / 100.0 if _personality != null else -1.0,
		"caution": roundf(_personality.caution * 100.0) / 100.0 if _personality != null else -1.0,
		"fear_retreating": is_fear_retreating(),
	}
