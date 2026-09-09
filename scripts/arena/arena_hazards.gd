class_name ArenaHazards
extends Node3D

## Data-driven arena hazards: fire vents (telegraphed radial burns), spike
## strips (crossing damage), healing circles (player regen zones) and slowing
## ichor pools. The Arena node owns one of these; Main configures it per arena
## id + wave mutators (Ember Winds ignites ambient vents). Hazards hit BOTH
## sides — kiting enemies through vents is a legitimate strategy.
##
## Layouts are deterministic in (arena_id, seed) via SpawnPatterns-style math.

signal hazard_triggered(kind: StringName, at: Vector3)

const KIND_VENT := &"vent"
const KIND_SPIKES := &"spikes"
const KIND_HEAL := &"heal"
const KIND_ICHOR := &"ichor"

const VENT_PERIOD := 4.0
const VENT_TELEGRAPH := 1.0
const VENT_RADIUS := 2.2
const VENT_DAMAGE := 15.0
const SPIKE_DAMAGE := 8.0
const SPIKE_HALF_WIDTH := 1.2
const HEAL_PER_SECOND := 6.0
const HEAL_RADIUS := 2.5
const ICHOR_SLOW := 0.5

var _hazards: Array = []  # [{kind, pos, timer, active, node}]
var _enabled := true
var _arena_half := 12.0
var _rng := RngService.new()


const KIND_PLATE := &"plate"       # player-triggerable pressure plate (damages enemies)
const KIND_MOVER := &"mover"       # slowly orbiting spike hazard

const PLATE_DAMAGE := 22.0
const PLATE_RADIUS := 2.0
const PLATE_COOLDOWN := 6.0
const MOVER_DAMAGE := 10.0
const MOVER_RADIUS := 1.4
const MOVER_SPEED := 1.1

var _mode_id: StringName = &"standard"


func configure(arena_id: StringName, arena_half: float, seed: int, ambient_burn: bool = false) -> void:
	_arena_half = arena_half
	_rng.reseed(seed + hash(String(arena_id)))
	_clear()
	_layout_defaults(arena_id)
	if ambient_burn:
		_ignite_all_vents()


## Mode-specific denser layouts (boss rush / challenge get extra pressure).
func apply_mode_pressure(mode_id: StringName) -> void:
	_mode_id = mode_id
	match mode_id:
		GameMode.MODE_BOSS_RUSH:
			_add(KIND_PLATE, Vector3(0, 0, 0))
			_add(KIND_SPIKES, Vector3(3, 0, 3))
			_add(KIND_SPIKES, Vector3(-3, 0, -3))
		GameMode.MODE_CHALLENGE:
			_add(KIND_VENT, Vector3(0, 0, 5))
			_add(KIND_VENT, Vector3(0, 0, -5))
			_add(KIND_PLATE, Vector3(5, 0, 0))
			_add(KIND_PLATE, Vector3(-5, 0, 0))
		GameMode.MODE_SURVIVAL:
			_add(KIND_MOVER, Vector3(4, 0, 4))
			_add(KIND_MOVER, Vector3(-4, 0, -4))
		GameMode.MODE_CAMPAIGN:
			_add(KIND_PLATE, Vector3(0, 0, 0))
			_add(KIND_HEAL, Vector3(7, 0, 0))
			_add(KIND_HEAL, Vector3(-7, 0, 0))


func set_enabled(enabled: bool) -> void:
	_enabled = enabled


func _layout_defaults(arena_id: StringName) -> void:
	match String(arena_id):
		"ember_crucible":
			# Dense fire grid + player-triggerable center plate + orbiting embers.
			_add(KIND_VENT, Vector3(5, 0, 5))
			_add(KIND_VENT, Vector3(-5, 0, -5))
			_add(KIND_VENT, Vector3(-5, 0, 5))
			_add(KIND_VENT, Vector3(5, 0, -5))
			_add(KIND_VENT, Vector3(0, 0, 7))
			_add(KIND_VENT, Vector3(0, 0, -7))
			_add(KIND_PLATE, Vector3(0, 0, 0))
			_add(KIND_MOVER, Vector3(6, 0, 0))
			_add(KIND_HEAL, Vector3(7, 0, 7))
		"frost_hollow":
			# Slowing corridors, dual heal pockets, frost plate, orbiting ichor.
			_add(KIND_ICHOR, Vector3(4, 0, 0))
			_add(KIND_ICHOR, Vector3(-4, 0, 0))
			_add(KIND_ICHOR, Vector3(0, 0, 5))
			_add(KIND_ICHOR, Vector3(0, 0, -5))
			_add(KIND_ICHOR, Vector3(6, 0, 6))
			_add(KIND_ICHOR, Vector3(-6, 0, -6))
			_add(KIND_HEAL, Vector3(0, 0, 4))
			_add(KIND_HEAL, Vector3(0, 0, -4))
			_add(KIND_PLATE, Vector3(0, 0, 0))
			_add(KIND_MOVER, Vector3(0, 0, 7))
		_:
			# The Pit: spike cross, vents on flanks, pressure plates, a mover.
			_add(KIND_VENT, Vector3(6, 0, 0))
			_add(KIND_VENT, Vector3(-6, 0, 0))
			_add(KIND_SPIKES, Vector3(0, 0, 6))
			_add(KIND_SPIKES, Vector3(0, 0, -6))
			_add(KIND_SPIKES, Vector3(4, 0, 4))
			_add(KIND_SPIKES, Vector3(-4, 0, -4))
			_add(KIND_PLATE, Vector3(3, 0, -3))
			_add(KIND_PLATE, Vector3(-3, 0, 3))
			_add(KIND_MOVER, Vector3(0, 0, 0))
			_add(KIND_HEAL, Vector3(0, 0, -6))
			_add(KIND_HEAL, Vector3(0, 0, 6))


func add_hazard(kind: StringName, at: Vector3) -> void:
	_add(kind, at)


func _add(kind: StringName, at: Vector3) -> void:
	var clamped := Vector3(clampf(at.x, -_arena_half + 1.0, _arena_half - 1.0), 0.05, clampf(at.z, -_arena_half + 1.0, _arena_half - 1.0))
	var marker := _build_marker(kind, clamped)
	add_child(marker)
	_hazards.append({"kind": kind, "pos": clamped, "timer": _rng.randf_range(RngService.STREAM_ARENA, 0.0, VENT_PERIOD), "node": marker})


func _build_marker(kind: StringName, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = at
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = _radius_of(kind)
	cyl.bottom_radius = _radius_of(kind)
	cyl.height = 0.08
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _color_of(kind, 0.35)
	mat.emission_enabled = true
	mat.emission = _color_of(kind, 1.0)
	mat.emission_energy_multiplier = 0.4
	disc.material_override = mat
	root.add_child(disc)
	root.set_meta("disc", disc)
	root.set_meta("base_color", _color_of(kind, 1.0))
	return root


func _radius_of(kind: StringName) -> float:
	match kind:
		KIND_VENT:
			return VENT_RADIUS
		KIND_HEAL:
			return HEAL_RADIUS
		KIND_ICHOR:
			return 2.8
		KIND_SPIKES:
			return SPIKE_HALF_WIDTH
		KIND_PLATE:
			return PLATE_RADIUS
		KIND_MOVER:
			return MOVER_RADIUS
	return 2.0


func _color_of(kind: StringName, alpha: float) -> Color:
	var c := Color.WHITE
	match kind:
		KIND_VENT:
			c = Color(1.0, 0.4, 0.1)
		KIND_SPIKES:
			c = Color(0.8, 0.8, 0.85)
		KIND_HEAL:
			c = Color(0.4, 1.0, 0.5)
		KIND_ICHOR:
			c = Color(0.5, 0.3, 0.9)
		KIND_PLATE:
			c = Color(1.0, 0.85, 0.2)
		KIND_MOVER:
			c = Color(0.9, 0.2, 0.55)
	c.a = alpha
	return c


func _ignite_all_vents() -> void:
	for h in _hazards:
		if h["kind"] == KIND_VENT:
			h["timer"] = VENT_PERIOD - VENT_TELEGRAPH


func _physics_process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	if not _enabled or _hazards.is_empty() or not is_inside_tree():
		return
	var victims := _gather_victims()
	# Filter stale victims that left the tree mid-frame
	victims = victims.filter(func(v): return v != null and is_instance_valid(v) and v.is_inside_tree())
	for h in _hazards:
		match h["kind"]:
			KIND_VENT:
				_tick_vent(h, victims, delta)
			KIND_SPIKES:
				_tick_spikes(h, victims)
			KIND_HEAL:
				_tick_heal(h, victims, delta)
			KIND_ICHOR:
				_tick_ichor(h, victims)
			KIND_PLATE:
				_tick_plate(h, victims, delta)
			KIND_MOVER:
				_tick_mover(h, victims, delta)


func _gather_victims() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	out.append_array(get_tree().get_nodes_in_group("player"))
	out.append_array(get_tree().get_nodes_in_group("enemies"))
	return out


func _inside(pos: Vector3, center: Vector3, radius: float) -> bool:
	var dx := pos.x - center.x
	var dz := pos.z - center.z
	return dx * dx + dz * dz <= radius * radius


func _tick_vent(h: Dictionary, victims: Array, delta: float) -> void:
	h["timer"] = float(h["timer"]) + delta
	# Visuals are optional (see _hazard_emission): a freed marker must never skip the
	# hazard's gameplay, and must never be dereferenced blindly either.
	var mat := _hazard_emission(h)
	if float(h["timer"]) >= VENT_PERIOD - VENT_TELEGRAPH and mat != null:
		# Telegraph: pulse bright.
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 60.0)
		mat.emission_energy_multiplier = 0.4 + pulse * 1.6
	if float(h["timer"]) >= VENT_PERIOD:
		h["timer"] = 0.0
		if mat != null:
			mat.emission_energy_multiplier = 0.4
		var center: Vector3 = h["pos"]
		if not is_finite(center.x) or not is_finite(center.y) or not is_finite(center.z):
			# A non-finite epicentre would push NaN knockback into every victim body.
			return
		AreaDamage.apply_radial(victims, center, VENT_RADIUS, VENT_DAMAGE, self, &"fire_vent", 6.0, false, AreaDamage.FALLOFF_NONE)
		_apply_burn(victims, center)
		hazard_triggered.emit(KIND_VENT, center)


## Emission material of a hazard's visual marker, or null when the visual is gone. The
## marker belongs to the arena, so a world rebuild frees it while the hazard record is
## still ticking; every per-frame tick dereferences it. Reading it through one helper
## keeps the glow optional instead of a per-frame crash on a stale reference.
func _hazard_emission(h: Dictionary) -> StandardMaterial3D:
	var marker: Node3D = h.get("node")
	if marker == null or not is_instance_valid(marker) or not marker.has_meta("disc"):
		return null
	var disc: MeshInstance3D = marker.get_meta("disc")
	if disc == null or not is_instance_valid(disc):
		return null
	return disc.material_override as StandardMaterial3D


func _apply_burn(victims: Array, center: Vector3) -> void:
	var burn: StatusEffectConfig = ContentRegistry.get_status_effect(&"burn")
	if burn == null:
		return
	for v in victims:
		if v is Node3D and _inside((v as Node3D).global_position, center, VENT_RADIUS):
			var sm := (v as Node).get_node_or_null("StatusManager") as StatusManager
			if sm != null:
				sm.apply_effect(burn, 1, self)


func _tick_spikes(h: Dictionary, victims: Array) -> void:
	var center: Vector3 = h["pos"]
	# Use a stable identifier per hazard (index in _hazards + position hash)
	# instead of dictionary hash which may include volatile timer/node identity.
	var hazard_index := _hazards.find(h)
	# Meta identifiers allow [A-Za-z0-9_] only: quantize coords to ints (dots in
	# "%f" keys made set_meta fail, silently disabling the spike cooldown).
	var cell := "%d_%d" % [int(round(center.x * 10.0)), int(round(center.z * 10.0))]
	var stable_id := "%d_%s" % [hazard_index, cell] if hazard_index >= 0 else "pos_%s" % cell
	for v in victims:
		if v is Node3D and _inside((v as Node3D).global_position, center, SPIKE_HALF_WIDTH):
			# Throttled by a per-victim cooldown stored in metadata.
			var key := "spike_cd_%s" % stable_id
			var now := Time.get_ticks_msec() / 1000.0
			if float((v as Node).get_meta(key, 0.0)) > now:
				continue
			(v as Node).set_meta(key, now + 1.0)
			# Damageable protocol: only combat entities take spike damage.
			var damageable := v as Damageable
			if damageable != null:
				var payload := DamagePayload.new()
				payload.amount = SPIKE_DAMAGE
				payload.source = self
				payload.source_id = &"spike_strip"
				payload.hit_position = (v as Node3D).global_position
				if payload.is_valid():
					damageable.apply_damage(payload)


func _tick_heal(h: Dictionary, victims: Array, delta: float) -> void:
	var center: Vector3 = h["pos"]
	for v in victims:
		if not (v is Node) or not (v as Node).is_in_group("player"):
			continue
		if _inside((v as Node3D).global_position, center, HEAL_RADIUS):
			var hp := (v as Node).get_node_or_null("HealthComponent") as HealthComponent
			if hp != null:
				hp.heal(HEAL_PER_SECOND * delta)


func _tick_ichor(h: Dictionary, victims: Array) -> void:
	var center: Vector3 = h["pos"]
	if ContentRegistry == null:
		return
	var slow: StatusEffectConfig = ContentRegistry.get_status_effect(&"slow")
	if slow == null:
		return
	for v in victims:
		if v is Node3D and _inside((v as Node3D).global_position, center, 2.8):
			var sm := (v as Node).get_node_or_null("StatusManager") as StatusManager
			if sm != null:
				sm.apply_effect(slow, 1, self)


## Pressure plate: when the player stands on it, detonate a blast that hurts enemies only.
func _tick_plate(h: Dictionary, victims: Array, delta: float) -> void:
	h["timer"] = float(h.get("timer", 0.0)) + delta
	var center: Vector3 = h["pos"]
	var player_on := false
	for v in victims:
		if v is Node and (v as Node).is_in_group("player") and v is Node3D:
			if _inside((v as Node3D).global_position, center, PLATE_RADIUS):
				player_on = true
				break
	# Visual: brighten when armed / player is on it.
	var mat := _hazard_emission(h)
	if mat != null:
		mat.emission_energy_multiplier = 1.6 if player_on else 0.5
	if not player_on:
		return
	if float(h.get("timer", 0.0)) < PLATE_COOLDOWN:
		return
	h["timer"] = 0.0
	var enemies: Array = []
	for v in victims:
		if v is Node and (v as Node).is_in_group("enemies"):
			enemies.append(v)
	AreaDamage.apply_radial(
		enemies, center, PLATE_RADIUS + 1.5, PLATE_DAMAGE, self, &"pressure_plate",
		8.0, false, AreaDamage.FALLOFF_NONE
	)
	hazard_triggered.emit(KIND_PLATE, center)


## Orbiting hazard: circles the arena origin, damaging anyone it passes through.
func _tick_mover(h: Dictionary, victims: Array, delta: float) -> void:
	var angle := float(h.get("angle", 0.0)) + MOVER_SPEED * delta
	h["angle"] = angle
	var radius := clampf(_arena_half * 0.55, 4.0, 10.0)
	var pos := Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
	h["pos"] = pos
	var marker: Node3D = h.get("node")
	if marker != null and is_instance_valid(marker):
		marker.position = pos
	# Throttled contact damage.
	h["tick"] = float(h.get("tick", 0.0)) + delta
	if float(h["tick"]) < 0.35:
		return
	h["tick"] = 0.0
	for v in victims:
		var body := v as Damageable
		if body != null and _inside(body.global_position, pos, MOVER_RADIUS):
			var payload := DamagePayload.new()
			payload.amount = MOVER_DAMAGE
			payload.source = self
			payload.source_id = &"moving_hazard"
			payload.hit_position = body.global_position
			if payload.is_valid():
				body.apply_damage(payload)


func _clear() -> void:
	for h in _hazards:
		var node: Node = h["node"]
		if is_instance_valid(node):
			node.queue_free()
	_hazards.clear()


func hazard_count() -> int:
	return _hazards.size()


func get_debug_snapshot() -> Dictionary:
	var kinds: Array = []
	for h in _hazards:
		kinds.append(String(h["kind"]))
	return {"count": _hazards.size(), "kinds": kinds}

