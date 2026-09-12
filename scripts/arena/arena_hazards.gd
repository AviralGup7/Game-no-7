class_name ArenaHazards
extends Node3D

## Arena hazards: authored discs that either detonate (fire vents, pressure plates) or
## apply while you stand in them (spike beds, healing wards, slowing pools, moving embers).
## The Arena node owns one of these; Main configures it per arena and applies the game
## mode's extra pressure. Hazards hit BOTH sides — kiting a pack through a vent is a
## legitimate strategy, and a plate the player can bait enemies onto is a legitimate tool.
##
## Everything about *which* hazards exist, where they are, and how hard they hit is
## authored content: res://data/hazards/*.tres (behaviour), ArenaConfig.hazard_layout (per
## arena) and res://data/hazards/modes/*.tres (per mode). The system itself implements two
## mechanics — "pulse" and "field" — and a hazard whose config names anything else is a
## load-time error rather than a silent no-op. Adding an arena is therefore a .tres edit,
## not an edit to this file (docs/EXTENDING.md).
##
## How it runs, and why:
##   * It polls math once per physics tick instead of wiring 30 Area3Ds. Combat, pickups
##     and the minimap all read positions from the tree for the same reason: on mobile a
##     polled squared-distance test is cheaper than a physics monitoring volume, and it is
##     testable headless with no physics server.
##   * Victims are gathered ONCE per tick into a flat snapshot (positions, team bits, hit
##     padding) and bucketed into a RadiusSpatialIndex, so each hazard visits the few
##     entities near it rather than every entity in the arena.
##   * Timers accumulate `delta` on this node's own clock. They used to compare
##     `Time.get_ticks_msec()` against gameplay intervals, which is wall-clock: at the
##     hitstop manager's 0.05x, a 1 s spike immunity spent ~50 ms of game time and vents
##     pulsed at their own speed while the world stood still. Now a paused world stops
##     hazards and hitstop stretches them, which is what the numbers claim to mean.
##   * A hazard never dereferences its marker blindly, and a non-finite centre is skipped
##     rather than pushed as NaN knockback into every body in the bucket.
##
## Layout building is deterministic in (arena_id, seed): placements are expanded in
## authored order and one draw per placement comes off RngService.STREAM_ARENA, so the same
## seed always produces the same layout and the same burst phases.

signal hazard_triggered(hazard_id: StringName, at: Vector3)

## Fallback for an arena that authored no layout: the four compass vents, inset by this
## fraction of the arena's half extent. Same convention as ArenaObstacles' safe default.
const SAFE_LAYOUT_INSET := 0.5
## Discs are laid flat just above the floor. Y is cosmetic: every hazard test is XZ.
const LIFT := 0.05

var _instances: Array[HazardInstance] = []
var _index := RadiusSpatialIndex.new()
var _victims: Array[Node3D] = []
var _damageables: Array[Damageable] = []
var _victim_flags: PackedInt32Array = PackedInt32Array()
var _candidate_scratch: Array = []
var _status_cache: Dictionary = {}

var _enabled: bool = true
var _arena_id: StringName = &""
var _mode_id: StringName = &"standard"
var _arena_half: float = 12.0
var _rng := RngService.new()
## Scaled seconds since this layout was built — the only clock a hazard may use.
var _game_time: float = 0.0
## How many bodies the current gather found. `_require_victims()` gates on it mid-tick and the debug
## snapshot exposes it as `victims_last_tick`, which is what it is by the time anyone reads the
## snapshot: the tick's gather is over. One number, deliberately not two — a second counter would
## only be a chance for the two to disagree.
var _victims_this_tick: int = 0
var _queries_last_tick: int = 0
## True once the victim snapshot for this physics tick has been taken (see _require_victims).
var _snapshot_ready: bool = false
var _unknown_mechanics: Dictionary = {}


## Rebuilds the hazard set for one arena. `seed` is the run seed; the arena id is folded
## in so two arenas in the same run do not share phases.
func configure(arena_id: StringName, arena_half: float, run_seed: int) -> void:
	_arena_id = arena_id
	_arena_half = arena_half if arena_half > 0.0 else 12.0
	_mode_id = GameMode.MODE_STANDARD
	_rng.reseed(run_seed + hash(String(arena_id)))
	_game_time = 0.0
	_status_cache.clear()
	_unknown_mechanics.clear()
	_clear()
	var layout := _authored_layout(arena_id)
	if layout.is_empty():
		layout = _safe_default_layout()
	_index.setup(Vector3.ZERO, _arena_half, _largest_radius(layout))
	for placement in layout:
		_spawn(placement)


## Mode-specific extra hazards, appended to whatever the arena authored.
func apply_mode_pressure(mode_id: StringName) -> void:
	if mode_id == _mode_id and not _instances.is_empty():
		return
	_mode_id = mode_id
	var layout := _mode_layout(mode_id)
	if layout.is_empty():
		return
	_index.setup(Vector3.ZERO, _arena_half, maxf(_largest_radius(layout), _index.cell_size))
	for placement in layout:
		_spawn(placement)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func is_enabled() -> bool:
	return _enabled


## "Burning air": every periodic burst jumps straight to its telegraph so the arena ignites
## on the wave instead of waiting out a full period. Kept as an explicit call for the wave
## mutator path (and for tests) rather than an unused parameter on configure().
func ignite_pulses() -> void:
	for instance in _instances:
		if instance.config != null and instance.config.is_periodic() and instance.period > 0.0:
			instance.timer = maxf(instance.period - instance.telegraph, 0.0)
			instance.armed = true


func hazard_count() -> int:
	return _instances.size()


## Empties the layout without re-seeding. configure() always rebuilds, so this exists for
## callers that author a hazard set themselves: tooling, and the live tests, which need an
## empty arena so a timing assertion measures one hazard and nothing else.
func clear_hazards() -> void:
	_clear()


func instances() -> Array[HazardInstance]:
	return _instances


## Spawn safety uses the damaging footprint, not the telegraph's current phase.
## Avoid the whole orbit path so a random initial angle cannot hit a new player.
func is_spawn_clear(at: Vector3, body_pad: float = 0.65) -> bool:
	if not at.is_finite() or not is_finite(body_pad) or body_pad < 0.0:
		return false
	for instance in _instances:
		var config := instance.config
		if config == null or not config.affects_player:
			continue
		if config.damage <= 0.0 and config.status_effect_id == &"":
			continue
		var reach := instance.radius + body_pad
		var offset := Vector2(at.x - instance.origin.x, at.z - instance.origin.z)
		var orbit := instance.orbit_radius(_arena_half)
		if orbit > 0.0:
			if absf(offset.length() - orbit) <= reach:
				return false
		elif offset.length_squared() <= reach * reach:
			return false
	return true


## Public authoring seam: place one authored HazardPlacement right now. Arena and mode
## layouts go through here, and so do tools/tests that want a specific hazard at a
## specific spot without editing any .tres.
func add_placement(placement: HazardPlacement) -> HazardInstance:
	return _spawn(placement)


## Convenience over add_placement(): resolves a hazard_id through the content table.
func add_hazard(hazard_id: StringName, at: Vector3) -> HazardInstance:
	var placement := HazardPlacement.new()
	placement.config = _lookup_config(hazard_id)
	placement.position = at
	placement.mirror = HazardPlacement.MIRROR_NONE
	return _spawn(placement)


func get_debug_snapshot() -> Dictionary:
	var kinds: Array = []
	var details: Array = []
	for instance in _instances:
		kinds.append(String(instance.config.hazard_id) if instance.config != null else "?")
		details.append(instance.debug_snapshot())
	return {
		"count": _instances.size(),
		"kinds": kinds,
		"arena": String(_arena_id),
		"mode": String(_mode_id),
		"game_time": snappedf(_game_time, 0.01),
		"victims_last_tick": _victims_this_tick,
		"queries_last_tick": _queries_last_tick,
		"index": _index.debug_snapshot(),
		"instances": details,
	}


# ---------------------------------------------------------------- building


func _authored_layout(arena_id: StringName) -> Array[HazardPlacement]:
	# A typed local, not `loaded.hazard_layout if loaded != null else []`: that ternary's type is the
	# plain `Array` the untyped arm contributes, and returning it from a `-> Array[HazardPlacement]`
	# function is a parse error -- the whole hazard layer stops loading over a shorthand.
	var out: Array[HazardPlacement] = []
	if ContentRegistry != null:
		var arena: ArenaConfig = ContentRegistry.get_arena(arena_id)
		if arena != null:
			return arena.hazard_layout
	var loaded := _load_arena(arena_id)
	if loaded != null:
		out = loaded.hazard_layout
	return out


func _mode_layout(mode_id: StringName) -> Array[HazardPlacement]:
	var out: Array[HazardPlacement] = []
	if ContentRegistry != null:
		var mode: HazardModeLayout = ContentRegistry.get_hazard_mode_layout(mode_id)
		if mode != null:
			return mode.extra_placements
	var loaded := _load_mode(mode_id)
	if loaded != null:
		out = loaded.extra_placements
	return out


## Registry-or-disk resolution, shared by both layouts: the headless harness and editor
## tooling run without autoloads, and an arena/mode id has to mean the same thing there as
## it does in a live game (the same shape as HazardConfig.resolve()).
func _load_arena(arena_id: StringName) -> ArenaConfig:
	var path := "res://data/arenas/%s.tres" % String(arena_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ArenaConfig


func _load_mode(mode_id: StringName) -> HazardModeLayout:
	var path := "res://data/hazard_modes/%s.tres" % String(mode_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as HazardModeLayout


## Same registry-or-disk rule as the layouts: a hazard's status must resolve identically
## in a live game and in the headless harness (which deliberately boots without a content
## registry, see tests/run_tests.gd), otherwise "the vent burns you" is untestable.
func _resolve_status(effect_id: StringName) -> StatusEffectConfig:
	if ContentRegistry != null:
		var registered: StatusEffectConfig = ContentRegistry.get_status_effect(effect_id)
		if registered != null:
			return registered
	var path := "res://data/status/%s.tres" % String(effect_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StatusEffectConfig


func _lookup_config(hazard_id: StringName) -> HazardConfig:
	if ContentRegistry != null:
		var authored: HazardConfig = ContentRegistry.get_hazard(hazard_id)
		if authored != null:
			return authored
	# No registry (tooling, headless harness) or an id it never saw: resolve from disk so
	# the same id still means the same hazard.
	return HazardConfig.resolve(hazard_id)


## Four vents at the compass points: enough to make an unauthored arena feel alive without
## a designer having to author anything yet.
## The four compass vents, exposed so tools and tests can assert the fallback without
## instantiating a world.
static func fallback_layout_positions(arena_half: float) -> Array[Vector3]:
	var inset := maxf(arena_half, 2.0) * SAFE_LAYOUT_INSET
	return [Vector3(inset, 0.0, 0.0), Vector3(-inset, 0.0, 0.0), Vector3(0.0, 0.0, inset), Vector3(0.0, 0.0, -inset)]


func _safe_default_layout() -> Array[HazardPlacement]:
	var out: Array[HazardPlacement] = []
	var vent := _lookup_config(&"fire_vent")
	if vent == null:
		return out
	for at in fallback_layout_positions(_arena_half):
		var placement := HazardPlacement.new()
		placement.config = vent
		placement.position = at
		placement.mirror = HazardPlacement.MIRROR_NONE
		placement.phase_jitter = 1.0
		out.append(placement)
	return out


func _largest_radius(layout: Array[HazardPlacement]) -> float:
	var largest := 1.0
	for placement in layout:
		if placement == null or placement.config == null:
			continue
		largest = maxf(largest, placement.effective_radius())
	return largest


func _spawn(placement: HazardPlacement) -> HazardInstance:
	if placement == null or placement.config == null:
		return null
	var limit := _arena_half - 1.0
	for at in placement.mirrored_positions():
		var clamped := Vector3(clampf(at.x, -limit, limit), LIFT, clampf(at.z, -limit, limit))
		var config := placement.config
		var instance := HazardInstance.build(config, _instances.size(), clamped, placement.effective_radius(), config.period)
		# One draw per placement, in authored order: the layout is a function of
		# (arena_id, seed) and appending hazards never shifts existing phases.
		if placement.phase_jitter > 0.0 and instance.period > 0.0:
			instance.timer = _rng.randf_range(RngService.STREAM_ARENA, 0.0, placement.phase_jitter) * instance.period
		_instances.append(instance)
		var marker := HazardMarker.build(config, instance.radius)
		marker.set_center(clamped)
		add_child(marker)
		marker.name = "Hazard%d" % instance.slot
		instance.marker = marker
	return _instances[_instances.size() - 1] if not _instances.is_empty() else null


func _clear() -> void:
	for instance in _instances:
		var marker := instance.visual()
		if marker != null:
			marker.queue_free()
		instance.clear_history()
	_instances.clear()
	_victims.clear()
	_damageables.clear()
	_victim_flags.fill(0)
	_index.clear()


# ---------------------------------------------------------------- ticking


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if not _enabled or _instances.is_empty() or not is_inside_tree():
		return
	_game_time += delta
	_snapshot_ready = false
	for instance in _instances:
		instance.advance(delta)
		if not instance.position_is_sane():
			# A non-finite centre would push NaN knockback into every body in the bucket.
			continue
		if instance.config == null:
			continue
		match instance.config.mechanic:
			HazardConfig.MECHANIC_PULSE:
				_tick_pulse(instance)
			HazardConfig.MECHANIC_FIELD:
				_tick_field(instance)
			_:
				# Unreachable for content that passed validate(); reported once instead of
				# silently doing nothing, which is what the string-keyed version did.
				if not _unknown_mechanics.has(instance.config.mechanic):
					_unknown_mechanics[instance.config.mechanic] = true
					push_error("ArenaHazards: hazard '%s' names unknown mechanic '%s'" % [
						String(instance.config.hazard_id), String(instance.config.mechanic),
					])
		instance.advance_orbit(delta, _arena_half)
		var marker := instance.visual()
		if marker != null and instance.config != null and instance.config.moves():
			marker.set_center(instance.position)
		instance.prune(_game_time)


func _tick_pulse(instance: HazardInstance) -> void:
	var config := instance.config
	if config.is_periodic():
		# The telegraph is pure arithmetic, so it animates even with nobody in the arena.
		instance.armed = instance.telegraph_level() > 0.0
		_sync_visual(instance)
		if not instance.burst_due():
			return
		if not _require_victims():
			return
		_detonate(instance)
		return
	# Proximity: re-arm on the hazard's own clock, then look for a trigger.
	if instance.rearm > 0.0:
		_sync_visual(instance)
		return
	if not instance.scan_due():
		return
	if not _require_victims():
		instance.armed = false
		_sync_visual(instance)
		return
	instance.begin_scan()
	var pressed := _trigger_pressed(instance)
	instance.armed = pressed
	_sync_visual(instance)
	if pressed:
		instance.fire()
		_detonate(instance)


## A proximity hazard is pressed when an allowed victim is on the tread; a plate that
## "needs the player" ignores enemies walking over it (they still eat the blast).
func _trigger_pressed(instance: HazardInstance) -> bool:
	var config := instance.config
	var mask := RadiusSpatialIndex.FLAG_PLAYER if config.proximity_needs_player else _team_mask(config)
	if mask == 0:
		return false
	var found := _index.query(instance.position, instance.contact_radius, mask)
	_queries_last_tick += 1
	for at in found:
		var element := _index.result_index(at)
		if _distance_within(instance.position, element, instance.contact_radius):
			return true
	return false


func _tick_field(instance: HazardInstance) -> void:
	var config := instance.config
	if not instance.scan_due():
		return
	# Checked before begin_scan() on purpose: an empty arena must not close the
	# integration window, or a healing ward would under-heal while nobody was around to
	# see it and over-heal the moment someone arrived.
	if not _require_victims():
		return
	var covered := instance.begin_scan()
	var mask := _team_mask(config)
	if mask == 0:
		return
	var found := _index.query(instance.position, instance.radius, mask)
	_queries_last_tick += 1
	if found == 0:
		return
	_candidate_scratch.clear()
	var throttled := config.victim_cooldown > 0.0
	for at in found:
		var element := _index.result_index(at)
		var victim := _victims[element]
		if victim == null or not is_instance_valid(victim):
			continue
		if not throttled:
			_candidate_scratch.append(victim)
			continue
		var key := victim.get_instance_id()
		if instance.victim_ready(key, _game_time):
			_candidate_scratch.append(victim)
			instance.stamp_victim(key, _game_time)
	if config.needs_health() and config.heal_per_second > 0.0:
		_heal_inside(instance, found, covered)
	if config.damage > 0.0 and not _candidate_scratch.is_empty():
		AreaDamage.apply_radial(
			_candidate_scratch, instance.position, instance.radius, config.damage, self,
			config.source_id, config.knockback, config.knock_up, config.falloff, [], config.damage_type
		)
	if config.has_status():
		_stamp_status(instance, _candidate_scratch)


## One detonation: query the grid, hand the small candidate list to the shared AoE seam,
## then reuse that same list for the status stamp. No hazard scans the whole arena twice.
func _detonate(instance: HazardInstance) -> void:
	var config := instance.config
	var mask := _team_mask(config)
	var center := instance.position
	instance.armed = false
	if mask == 0:
		return
	var found := _index.query(center, instance.radius, mask)
	_queries_last_tick += 1
	if found == 0:
		hazard_triggered.emit(config.hazard_id, center)
		_sync_visual(instance)
		return
	_candidate_scratch.clear()
	for at in found:
		var element := _index.result_index(at)
		var victim := _victims[element]
		if victim != null and is_instance_valid(victim):
			_candidate_scratch.append(victim)
	if config.damage > 0.0:
		AreaDamage.apply_radial(
			_candidate_scratch, center, instance.radius, config.damage, self,
			config.source_id, config.knockback, config.knock_up, config.falloff, [], config.damage_type
		)
	if config.has_status():
		_stamp_status(instance, _candidate_scratch)
	hazard_triggered.emit(config.hazard_id, center)
	_sync_visual(instance)


## Heal is continuous, so it integrates over the time since the last scan: halving the
## scan rate changes the total not at all.
func _heal_inside(instance: HazardInstance, found: int, covered: float) -> void:
	var amount := instance.config.heal_per_second * covered
	if amount <= 0.0:
		return
	for at in found:
		var element := _index.result_index(at)
		if (_victim_flags[element] & RadiusSpatialIndex.FLAG_PLAYER) == 0:
			continue
		var damageable := _damageables[element]
		if damageable == null:
			continue
		if not _distance_within(instance.position, element, instance.radius):
			continue
		var health := damageable.get_health_component()
		if health != null:
			health.heal(amount)


## Burn on a vent and slow in a pool used to be applied by re-scanning every victim in the
## arena with a second distance test. The candidate list already holds those victims.
func _stamp_status(instance: HazardInstance, victims: Array) -> void:
	var config := instance.config
	var effect: StatusEffectConfig = _status_cache.get(config.status_effect_id)
	if effect == null:
		effect = _resolve_status(config.status_effect_id)
		if effect == null:
			# The loader cross-checks authored ids against the status table, so this is a
			# tooling path without a registry — not something a shipped arena should hit.
			return
		_status_cache[config.status_effect_id] = effect
	var throttled := config.victim_cooldown > 0.0
	for victim in victims:
		if not (victim is Node) or not is_instance_valid(victim):
			continue
		var key := (victim as Node).get_instance_id()
		if throttled and not instance.victim_ready(key, _game_time):
			continue
		var damageable := victim as Damageable
		if damageable == null:
			continue
		var manager := damageable.get_status_manager()
		if manager != null:
			manager.apply_effect(effect, config.status_stacks, self)
		if throttled:
			instance.stamp_victim(key, _game_time)


func _sync_visual(instance: HazardInstance) -> void:
	var marker := instance.visual()
	if marker == null:
		return
	var level := instance.telegraph_level()
	if instance.armed and level <= 0.0:
		level = 1.0
	# The shimmer rides the game clock, so a telegraph that is frozen by hitstop stays
	# frozen instead of strobing ahead of the burst it is warning about.
	marker.set_pulse(level, 0.5 + 0.5 * sin(_game_time * 6.0))


# ---------------------------------------------------------------- victims


## Takes the victim snapshot if this tick has not taken one yet, and reports whether there
## is anybody to hit. Every hazard that wants victims calls this instead of gathering its
## own list: one group walk, one bucketing pass, shared by the whole tick — and on a tick
## where no hazard is due to look at anything (every vent between bursts), no snapshot is
## taken at all.
func _require_victims() -> bool:
	if not _snapshot_ready:
		_snapshot_ready = true
		_gather_victims()
	return _victims_this_tick > 0


## Gathers every live combat entity once per tick and buckets it. Positions are read from
## the physics state inside _physics_process, which is the only frame where a polled read
## and the collider the body is about to move through agree.
func _gather_victims() -> void:
	_victims.clear()
	_damageables.clear()
	_victims_this_tick = 0
	_queries_last_tick = 0
	_index.begin_update()
	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group("player"):
			_add_victim(node)
		for node in tree.get_nodes_in_group("enemies"):
			_add_victim(node)
	_victims_this_tick = _victims.size()


func _add_victim(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	if not (node is Node3D):
		return
	var damageable := node as Damageable
	if damageable == null or not damageable.is_alive():
		return
	var flags := 0
	if damageable.is_in_group("player"):
		flags = RadiusSpatialIndex.FLAG_PLAYER
	elif damageable.is_in_group("enemies"):
		flags = RadiusSpatialIndex.FLAG_ENEMY
	if flags == 0:
		return
	var index: int = _victims.size()
	_victims.append(node as Node3D)
	_damageables.append(damageable)
	if _victim_flags.size() <= index:
		_victim_flags.resize(index + RadiusSpatialIndex.MAX_ELEMENTS)
	_victim_flags[index] = flags
	_index.insert(damageable.global_position, flags, damageable.get_hit_radius())


func _distance_within(center: Vector3, element: int, radius: float) -> bool:
	var offset := _index.element_position(element) - center
	var reach := radius + _pad_of(element)
	return offset.x * offset.x + offset.z * offset.z <= reach * reach


func _pad_of(element: int) -> float:
	# Bodies are padded by their own hit radius in AreaDamage; the refined test agrees
	# with it so a hazard never damages a victim its query did not report.
	var damageable := _damageables[element] if element < _damageables.size() else null
	return damageable.get_hit_radius() if damageable != null else 0.0


func _team_mask(config: HazardConfig) -> int:
	var mask := 0
	if config.affects_player:
		mask |= RadiusSpatialIndex.FLAG_PLAYER
	if config.affects_enemies:
		mask |= RadiusSpatialIndex.FLAG_ENEMY
	return mask
