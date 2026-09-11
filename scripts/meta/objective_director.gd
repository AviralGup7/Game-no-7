class_name ObjectiveDirector
extends Node

## Runtime for the non-standard win conditions that GameMode declares but the
## survival/wave loop can't express on its own:
##
##   OBJECTIVE_DEFEND_POINT (Hold the Line) — a beacon stands at the arena's
##     heart. Enemies within its radius drain it; it self-repairs when clear.
##     Win when the mode timer elapses; lose the instant the beacon falls.
##   OBJECTIVE_COLLECT (Relic Hunt) — slain foes drop relic shards on a
##     deterministic cadence; the player banks them until the quota is met.
##
## The director is a per-run Node under WorldRoot (created by Main). It reads the
## active mode from GameRoot, drives EventBus.objective_progress for the HUD, and
## fires EventBus.objective_resolved(success) exactly once; GameRoot turns that
## into a victory or a game over. Modes without a director objective make this a
## no-op, so it is always safe to spawn.

const BEACON_MAX_HP := 100.0
const BEACON_DRAIN_PER_ENEMY := 6.5   # hp/sec per enemy inside the radius
const BEACON_REPAIR_PER_SEC := 4.0    # hp/sec regen while the ring is clear
const BEACON_RADIUS := 4.0
const RELIC_EVERY_N_KILLS := 2        # a relic drops on every Nth ordinary kill
const RELIC_BOSS_DROPS := 3

var _mode_id: StringName = GameMode.MODE_STANDARD
var _objective: StringName = GameMode.OBJECTIVE_CLEAR_WAVES
var _active := false
var _resolved := false

# Defend state.
var _beacon: Node3D = null
var _beacon_hp := BEACON_MAX_HP
var _arena_center := Vector3.ZERO

# Collect state.
var _relics_banked := 0
var _relic_target := 0
var _kill_counter := 0
## Last emitted progress value, so per-frame defend ticks only push the HUD on change.
var _last_emitted := -1

var _pickups: PickupManager = null
var _bus := EventBindings.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("objective_director")


## Bind the per-run world context and arm the objective for the active mode.
## `arena_center` grounds the Defend beacon; `pickups` spawns Relic Hunt shards.
func configure(mode_id: StringName, arena_center: Vector3, pickups: PickupManager) -> void:
	_mode_id = GameMode.validated(mode_id)
	_objective = GameMode.objective(_mode_id)
	_arena_center = arena_center
	_pickups = pickups
	_active = _objective == GameMode.OBJECTIVE_DEFEND_POINT or _objective == GameMode.OBJECTIVE_COLLECT
	_resolved = false
	if not _active:
		return
	if _objective == GameMode.OBJECTIVE_DEFEND_POINT:
		_beacon_hp = BEACON_MAX_HP
		_last_emitted = -1
		_spawn_beacon()
	elif _objective == GameMode.OBJECTIVE_COLLECT:
		_relics_banked = 0
		_relic_target = maxi(GameMode.collect_target(_mode_id), 1)
		_kill_counter = 0
		_bus.bind(EventBus.enemy_killed, _on_enemy_killed)
		_bus.bind(EventBus.pickup_collected, _on_pickup_collected)
	# run_started (emitted just after world build) makes the HUD reseed and clear
	# the objective line; re-emit afterwards so the objective is visible from turn one.
	_bus.bind(EventBus.run_started, _on_run_started)
	_emit_progress()


func _exit_tree() -> void:
	_bus.unbind_all()


## GAME_OVER freeze: stop relic drops / beacon ticks from lingering deaths
## while WorldRoot (and this director) stay up for the summary camera.
func isolate_run() -> void:
	_bus.unbind_all()
	_active = false


func is_active() -> bool:
	return _active and not _resolved


func _on_run_started(_run_id: int, _seed: int) -> void:
	if _active and not _resolved:
		_emit_progress()


## ---------- Defend: beacon drain / repair / win-on-clock ----------

func _physics_process(delta: float) -> void:
	if not _active or _resolved:
		return
	if _objective != GameMode.OBJECTIVE_DEFEND_POINT:
		return
	if GameRoot != null and GameRoot.is_paused():
		return
	# Only tick during live gameplay states — after game over the world is being
	# torn down and the beacon must not keep draining or resolve a stale win.
	if GameRoot != null and GameRoot.get_current_state() not in [
		GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION, GameRoot.State.UPGRADE_SELECTION]:
		return
	var run := GameRoot.get_run() if GameRoot != null else null
	if run == null or not run.player_alive:
		return
	var threats := _enemies_near_beacon()
	if threats > 0:
		_beacon_hp = maxf(_beacon_hp - BEACON_DRAIN_PER_ENEMY * float(threats) * delta, 0.0)
	else:
		_beacon_hp = minf(_beacon_hp + BEACON_REPAIR_PER_SEC * delta, BEACON_MAX_HP)
	_update_beacon_visual()
	# HUD only needs a push when the integer percent actually moves.
	if _progress_value() != _last_emitted:
		_emit_progress()
	if _beacon_hp <= 0.0:
		_resolve(false, "The beacon has fallen!")
		return
	# Win on the clock: the mode timer (GameRoot._process drives elapsed_seconds).
	if run.elapsed_seconds >= GameMode.target_seconds(_mode_id):
		_resolve(true, "The line holds — the beacon endures!")


func _enemies_near_beacon() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var count := 0
	var center := _beacon.global_position if _beacon != null and is_instance_valid(_beacon) else _arena_center
	for e in tree.get_nodes_in_group("enemies"):
		if e is Node3D and (e as Node3D).global_position.distance_to(center) <= BEACON_RADIUS:
			count += 1
	return count


func _spawn_beacon() -> void:
	_beacon = Node3D.new()
	_beacon.name = "DefendBeacon"
	_beacon.global_position = _arena_center
	add_child(_beacon)
	# Glowing crystal pillar so the point to defend is unmistakable.
	var pillar := MeshInstance3D.new()
	pillar.name = "BeaconMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.15
	mesh.bottom_radius = 0.55
	mesh.height = 2.6
	mesh.radial_segments = 6
	pillar.mesh = mesh
	pillar.position = Vector3(0, 1.3, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.85, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.5
	pillar.material_override = mat
	_beacon.add_child(pillar)
	# Ground ring marking the defense radius.
	var ring := MeshInstance3D.new()
	ring.name = "BeaconRing"
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = BEACON_RADIUS
	ring_mesh.bottom_radius = BEACON_RADIUS
	ring_mesh.height = 0.05
	ring_mesh.radial_segments = 32
	ring.mesh = ring_mesh
	ring.position = Vector3(0, 0.03, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.18)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	_beacon.add_child(ring)


func _update_beacon_visual() -> void:
	if _beacon == null or not is_instance_valid(_beacon):
		return
	var mesh := _beacon.get_node_or_null("BeaconMesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	# Cool blue at full health shifts to alarm red as the beacon is bled down.
	var frac := clampf(_beacon_hp / BEACON_MAX_HP, 0.0, 1.0)
	var col := Color(0.45, 0.85, 1.0).lerp(Color(1.0, 0.25, 0.2), 1.0 - frac)
	mat.albedo_color = col
	mat.emission = col
	mat.emission_energy_multiplier = lerpf(0.8, 2.8, frac)


## ---------- Collect: deterministic relic drops + banking ----------

func _on_enemy_killed(enemy: Node, archetype_id: StringName, _score: int, _currency: int) -> void:
	if not _active or _resolved or _pickups == null:
		return
	if _objective != GameMode.OBJECTIVE_COLLECT:
		return
	var at := _arena_center
	if enemy is Node3D and is_instance_valid(enemy):
		at = (enemy as Node3D).global_position
	if archetype_id == &"warlord":
		for i in range(RELIC_BOSS_DROPS):
			_pickups.spawn_pickup(&"relic_shard", at)
		return
	_kill_counter += 1
	if _kill_counter % RELIC_EVERY_N_KILLS == 0:
		_pickups.spawn_pickup(&"relic_shard", at)


func _on_pickup_collected(pickup_id: StringName, _amount: int, _collector: Node) -> void:
	if not _active or _resolved:
		return
	if _objective != GameMode.OBJECTIVE_COLLECT or pickup_id != &"relic_shard":
		return
	_relics_banked += 1
	_emit_progress()
	if _relics_banked >= _relic_target:
		_resolve(true, "All relics recovered!")


## ---------- Progress + resolution ----------

func _progress_value() -> int:
	if _objective == GameMode.OBJECTIVE_DEFEND_POINT:
		return int(round(clampf(_beacon_hp / BEACON_MAX_HP, 0.0, 1.0) * 100.0))
	if _objective == GameMode.OBJECTIVE_COLLECT:
		return _relics_banked
	return 0


func _emit_progress() -> void:
	var run := GameRoot.get_run() if GameRoot != null else null
	var wave := run.current_wave if run != null else 0
	var elapsed := run.elapsed_seconds if run != null else 0.0
	var bosses := run.bosses_slain if run != null else 0
	var progress := _progress_value()
	if run != null:
		run.objective_progress = progress
	var label := GameMode.objective_label(_mode_id, wave, elapsed, bosses, progress)
	var target := GameMode.collect_target(_mode_id) if _objective == GameMode.OBJECTIVE_COLLECT else 100
	_last_emitted = progress
	EventBus.objective_progress.emit(label, progress, target)


func _resolve(success: bool, message: String) -> void:
	if _resolved:
		return
	_resolved = true
	var run := GameRoot.get_run() if GameRoot != null else null
	if run != null and not success:
		run.objective_failed = true
	var severity := &"victory" if success else &"danger"
	EventBus.announcement.emit(&"objective", message, severity)
	EventBus.objective_resolved.emit(_mode_id, success)


func get_debug_snapshot() -> Dictionary:
	return {
		"mode": String(_mode_id),
		"objective": String(_objective),
		"active": _active,
		"resolved": _resolved,
		"beacon_hp": _beacon_hp,
		"relics_banked": _relics_banked,
		"relic_target": _relic_target,
	}
