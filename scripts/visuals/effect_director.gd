class_name EffectDirector
extends Node

## Lightweight, pooled 3D VFX director for combat + wave + status feedback. It listens
## to existing EventBus signals (no gameplay edits) and spawns short-lived, low-count
## GPUParticles3D bursts + billboard rings so nothing accumulates or runs per frame.
##
## Mobile-safe:
##  - Every emitter is owned by this node and reused across the pool.
##  - Pool caps, one-shot particles, tiny amounts, short lifetimes.
##  - GPU particles only; no scripted per-frame emitter work beyond returning a ring.
##
## All methods are no-ops when particles are unsupported or the event node is invalid.
## Priority & saturation: CRITICAL/BOSS/PLAYER effects are preserved when the pool
## saturates — low-priority hits are dropped rather than evicting a boss burst,
## and a high-priority request will steal the oldest low-priority ring/burst.

const MAX_BURSTS := 10
const MAX_RINGS := 14
const MAX_LIVE_TELEGRAPH := 6
const BOSS_RING_RESERVE := 2
const MAX_MUZZLE := 4
const RING_TEXTURE := "res://assets/effects/kenney/circle_05.png"
const BURST_TEXTURE := "res://assets/effects/kenney/spark_01.png"

# Pool priorities — higher wins when saturated.
const PRIORITY_CRITICAL := 100
const PRIORITY_BOSS := 90
const PRIORITY_PLAYER := 80
const PRIORITY_SKILL := 60
const PRIORITY_ENEMY_DEATH := 50
const PRIORITY_SPAWN := 45
const PRIORITY_PICKUP := 35
const PRIORITY_ENEMY_HIT := 30
const PRIORITY_HIT := 30
const PRIORITY_STATUS := 25
const PRIORITY_AMBIENT := 10

## Status effect visual accent -> colour (matches ART_STYLE readability accents).
## Covers all 13 status ids (8 required +5 extra) so every effect has a distinct tint.
const STATUS_COLORS := {
	&"burn": Color(1.0, 0.45, 0.12),
	&"bleed": Color(0.9, 0.15, 0.15),
	&"shock": Color(0.5, 0.75, 1.0),
	&"slow": Color(0.45, 0.75, 1.0),
	&"stun": Color(1.0, 0.85, 0.3),
	&"guard": Color(0.55, 0.7, 1.0),
	&"regen": Color(0.45, 1.0, 0.55),
	&"warcry": Color(1.0, 0.6, 0.25),
	&"exposed": Color(1.0, 0.65, 0.22),
	&"frenzy": Color(1.0, 0.22, 0.22),
	&"haste": Color(0.62, 0.88, 1.0),
	&"overguard": Color(0.68, 0.78, 1.0),
	&"poison": Color(0.38, 0.78, 0.22),
}

## Distinct per-skill colours — all 8 skills have a unique tint so the player
## reads the cast without text. Legacy aliases frost_nova/warcry kept for
## backward compat with older configs that used the short id.
const SKILL_COLORS := {
	&"bladestorm": Color(0.88, 0.62, 0.18),
	&"frost_nova": Color(0.42, 0.76, 1.0),
	&"frost_nova_skill": Color(0.42, 0.76, 1.0),
	&"phantom_rush": Color(0.64, 0.42, 1.0),
	&"seismic_slam": Color(0.82, 0.48, 0.18),
	&"warcry": Color(1.0, 0.42, 0.22),
	&"warcry_skill": Color(1.0, 0.42, 0.22),
	&"chain_lightning": Color(0.52, 0.74, 1.0),
	&"mending_light": Color(0.48, 1.0, 0.58),
	&"shatterwave": Color(0.78, 0.68, 1.0),
}

## Per-skill ring/burst textures from the shared kenney library — gives each skill
## a shape identity beyond colour/radius (trace for whirl, smoke for dash, dirt for slam, etc).
const SKILL_RING_TEXTURES := {
	&"bladestorm": "res://assets/effects/kenney/trace_01.png",
	&"frost_nova": "res://assets/effects/kenney/circle_05.png",
	&"frost_nova_skill": "res://assets/effects/kenney/circle_05.png",
	&"phantom_rush": "res://assets/effects/kenney/smoke_03.png",
	&"seismic_slam": "res://assets/effects/kenney/dirt_01.png",
	&"warcry": "res://assets/effects/kenney/magic_01.png",
	&"warcry_skill": "res://assets/effects/kenney/magic_01.png",
	&"chain_lightning": "res://assets/effects/kenney/magic_03.png",
	&"mending_light": "res://assets/effects/kenney/flare_01.png",
	&"shatterwave": "res://assets/effects/kenney/circle_01.png",
}
const SKILL_BURST_TEXTURES := {
	&"bladestorm": "res://assets/effects/kenney/trace_01.png",
	&"frost_nova": "res://assets/effects/kenney/star_04.png",
	&"frost_nova_skill": "res://assets/effects/kenney/star_04.png",
	&"phantom_rush": "res://assets/effects/kenney/smoke_01.png",
	&"seismic_slam": "res://assets/effects/kenney/spark_04.png",
	&"warcry": "res://assets/effects/kenney/magic_01.png",
	&"warcry_skill": "res://assets/effects/kenney/magic_01.png",
	&"chain_lightning": "res://assets/effects/kenney/star_01.png",
	&"mending_light": "res://assets/effects/kenney/light_01.png",
	&"shatterwave": "res://assets/effects/kenney/circle_05.png",
}
var _bursts: Array[GPUParticles3D] = []
var _ring_pool: Array[Node3D] = []
var _burst_prios: Dictionary = {} # GPUParticles3D -> int
var _ring_prios: Dictionary = {} # Node3D -> int
var _wired := false
var _bus := EventBindings.new()
var _live_telegraphs := 0


func _ready() -> void:
	add_to_group("effect_director")
	_wire_events()


func _exit_tree() -> void:
	if EventBus != null:
		EventBus.unbind(EventBus.enemy_spawned, _on_enemy_spawned)
		EventBus.unbind(EventBus.enemy_killed, _on_enemy_killed)
		EventBus.unbind(EventBus.enemy_damaged, _on_enemy_damaged)
		EventBus.unbind(EventBus.wave_started, _on_wave_started)
		EventBus.unbind(EventBus.wave_completed, _on_wave_completed)
		EventBus.unbind(EventBus.pickup_collected, _on_pickup_collected)
		EventBus.unbind(EventBus.pickup_spawned, _on_pickup_spawned)
		EventBus.unbind(EventBus.status_applied, _on_status_applied)
		EventBus.unbind(EventBus.boss_spawned, _on_boss_spawned)
		EventBus.unbind(EventBus.boss_slain, _on_boss_slain)
		EventBus.unbind(EventBus.projectile_fired, _on_projectile_fired)
		EventBus.unbind(EventBus.skill_cast, _on_skill_cast)
		EventBus.unbind(EventBus.player_leveled_up, _on_player_leveled_up)
		EventBus.unbind(EventBus.weapon_equipped, _on_weapon_equipped)
	_wired = false


## Death / impact explosion at a world position (pooled, no autoload dependency).
func burst_at(at: Vector3, color: Color, scale: float = 1.0, priority: int = PRIORITY_HIT) -> void:
	if _reduced_motion() and priority < PRIORITY_SKILL:
		return
	var p := _claim_burst(priority)
	if p == null:
		return
	p.global_position = at
	var mat := p.process_material as ParticleProcessMaterial
	if mat != null:
		mat.color = color
	p.amount = 22
	p.scale = Vector3.ONE * scale
	p.restart()
	_burst_prios[p] = priority
	# Gate noisy diagnostics: only high-value telegraphs (SKILL/BOSS/CRITICAL/SPAWN/PICKUP) log; per-hit HITS are silent.
	if priority >= PRIORITY_BOSS:
		EventBus.report_info("EffectDirector burst at %s" % str(at))


## Expanding telegraph/collect ring (flat translucent disc on the ground plane).
## Grunt/heavy windup rings share a small budget so 20 simultaneous swings
## cannot drown the pool (boss/skill rings still steal).
func try_telegraph(for_boss: bool = false) -> bool:
	_prune_telegraph_count()
	if for_boss:
		return _can_claim_ring(PRIORITY_BOSS)
	if _live_telegraphs >= MAX_LIVE_TELEGRAPH:
		return false
	var bosses_alive := 0
	if is_inside_tree() and get_tree() != null:
		for n in get_tree().get_nodes_in_group("enemies"):
			if n != null and n.get_node_or_null("BossController") != null:
				if n is Damageable and (n as Damageable).is_alive():
					bosses_alive += 1
	var reserve := BOSS_RING_RESERVE if bosses_alive > 0 else 0
	var free := 0
	for r in _ring_pool:
		if not r.visible:
			free += 1
	free += maxi(0, MAX_RINGS - _ring_pool.size())
	if free <= reserve:
		return false
	return _can_claim_ring(PRIORITY_SPAWN)


func _prune_telegraph_count() -> void:
	var live := 0
	for r in _ring_pool:
		if not r.visible:
			continue
		var pr: int = int(_ring_prios.get(r, 0))
		# Occupancy is every combat ring, not only spawn-priority, so grunt
		# windups cannot pretend the pool is empty while it is full of hits.
		if pr >= PRIORITY_STATUS:
			live += 1
	_live_telegraphs = live


func _can_claim_ring(priority: int) -> bool:
	for r in _ring_pool:
		if not r.visible:
			return true
	if _ring_pool.size() < MAX_RINGS:
		return true
	for r in _ring_pool:
		var pr: int = int(_ring_prios.get(r, PRIORITY_HIT))
		if not r.visible:
			continue
		if priority < PRIORITY_BOSS and pr >= PRIORITY_BOSS:
			continue
		if priority > pr:
			return true
	return false


func ring_at(at: Vector3, color: Color, radius: float = 1.0, priority: int = PRIORITY_HIT) -> void:
	var ring := _claim_ring(priority)
	if ring == null:
		return
	var grounded := at
	var floor := _floor_hit(at)
	grounded.y = float(floor.get("y", at.y))
	ring.global_position = grounded + Vector3(0.02, 0.03, 0.02)
	var nrm: Vector3 = floor.get("normal", Vector3.UP)
	if nrm.length_squared() > 0.01:
		ring.look_at(ring.global_position + nrm, Vector3.FORWARD if absf(nrm.dot(Vector3.UP)) > 0.95 else Vector3.UP)
	var mi := ring.get_node_or_null("Disc") as MeshInstance3D
	if mi != null:
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			if ResourceLoader.exists(RING_TEXTURE):
				mat.albedo_texture = load(RING_TEXTURE)
			var ink := _telegraph_color(color, priority)
			var alpha := 0.95 if _high_contrast() else (0.85 if priority >= PRIORITY_BOSS else 0.45)
			mat.albedo_color = Color(ink, alpha)
			mat.emission_enabled = true
			mat.emission = ink
			mat.emission_energy_multiplier = (2.0 if _high_contrast() else 1.4) if priority >= PRIORITY_BOSS else (0.7 if _high_contrast() else 0.35)
	var hold := 1.15 if priority >= PRIORITY_BOSS else 0.6
	if _reduced_motion():
		hold = 0.7 if priority >= PRIORITY_BOSS else 0.35
	ring.scale = Vector3(radius, radius, radius)
	_show_ring(ring, hold)
	_ring_prios[ring] = priority
	if priority >= PRIORITY_BOSS:
		EventBus.report_info("EffectDirector ring at %s" % str(at))


# ---------------------- event wiring ----------------------

func _wire_events() -> void:
	if _wired or EventBus == null:
		return
	_wired = true
	# is_connected is enforced inside EventBus.bind (no duplicate listeners).
	EventBus.bind(self, EventBus.enemy_spawned, _on_enemy_spawned)
	EventBus.bind(self, EventBus.enemy_killed, _on_enemy_killed)
	EventBus.bind(self, EventBus.enemy_damaged, _on_enemy_damaged)
	EventBus.bind(self, EventBus.wave_started, _on_wave_started)
	EventBus.bind(self, EventBus.wave_completed, _on_wave_completed)
	EventBus.bind(self, EventBus.pickup_collected, _on_pickup_collected)
	EventBus.bind(self, EventBus.pickup_spawned, _on_pickup_spawned)
	EventBus.bind(self, EventBus.status_applied, _on_status_applied)
	EventBus.bind(self, EventBus.boss_spawned, _on_boss_spawned)
	EventBus.bind(self, EventBus.boss_slain, _on_boss_slain)
	EventBus.bind(self, EventBus.projectile_fired, _on_projectile_fired)
	EventBus.bind(self, EventBus.skill_cast, _on_skill_cast)
	EventBus.bind(self, EventBus.player_leveled_up, _on_player_leveled_up)
	EventBus.bind(self, EventBus.weapon_equipped, _on_weapon_equipped)


func _on_enemy_spawned(enemy: Node, _archetype: StringName) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		ring_at((enemy as Node3D).global_position, Color(0.9, 0.55, 0.3), 1.25, PRIORITY_SPAWN)


func _on_enemy_killed(enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	if is_instance_valid(enemy) and enemy is Node3D:
		var at := (enemy as Node3D).global_position + Vector3(0, 0.35, 0)
		burst_at(at, Color(0.95, 0.55, 0.25), 1.15, PRIORITY_ENEMY_DEATH)
		ring_at((enemy as Node3D).global_position, Color(1.0, 0.62, 0.35), 1.85, PRIORITY_ENEMY_DEATH)


func _on_enemy_damaged(enemy: Node, result: DamageResult) -> void:
	if not is_instance_valid(enemy) or not enemy is Node3D or result == null or not result.accepted:
		return
	var at := (enemy as Node3D).global_position + Vector3(0, 1.1, 0)
	if result.was_critical:
		# Gold crit: larger, brighter, with shock ring for readability — CRITICAL so it never drops.
		burst_at(at, Color(1.0, 0.88, 0.22), 0.82, PRIORITY_CRITICAL)
		ring_at((enemy as Node3D).global_position, Color(1.0, 0.92, 0.45), 1.05, PRIORITY_CRITICAL)
	else:
		burst_at(at, Color(0.9, 0.72, 0.55), 0.42, PRIORITY_ENEMY_HIT)


func _arena_origin() -> Vector3:
	var players := get_tree().get_nodes_in_group(&"player") if get_tree() != null else []
	if players.size() > 0 and players[0] is Node3D:
		var p := (players[0] as Node3D).global_position
		p.y = 0.0
		return p
	return Vector3.ZERO


func _floor_y(at: Vector3) -> float:
	return float(_floor_hit(at).get("y", at.y))


func _world_3d() -> World3D:
	if not is_inside_tree():
		return null
	var host := get_parent() as Node3D
	if host != null:
		return host.get_world_3d()
	var vp := get_viewport()
	return vp.world_3d if vp != null else null


func _floor_hit(at: Vector3) -> Dictionary:
	var world := _world_3d()
	if world == null or world.direct_space_state == null:
		return {"y": at.y, "normal": Vector3.UP}
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2.0, at + Vector3.DOWN * 4.0)
	q.collide_with_areas = false
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return {"y": at.y, "normal": Vector3.UP}
	return {"y": float(hit.position.y), "normal": hit.get("normal", Vector3.UP)}


func _on_wave_started(wave_number: int, _planned: int) -> void:
	var origin := _arena_origin()
	ring_at(origin, Color(0.85, 0.45, 0.22), 6.5, PRIORITY_SPAWN)
	burst_at(origin + Vector3(0, 0.2, 0), Color(1.0, 0.65, 0.3), 1.2, PRIORITY_SPAWN)


func _on_wave_completed(_wave_number: int, _bonus: int) -> void:
	var origin := _arena_origin()
	ring_at(origin, Color(1.0, 0.88, 0.38), 8.0, PRIORITY_SPAWN)
	burst_at(origin + Vector3(0, 0.4, 0), Color(1.0, 0.92, 0.5), 1.45, PRIORITY_SPAWN)


func _on_boss_spawned(boss: Node, _boss_id: StringName) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(boss) and boss is Node3D:
		at = (boss as Node3D).global_position
	# Inner danger disc + outer contrast ring so the telegraph reads on sand arenas
	# and under high-contrast / reduced-motion settings.
	ring_at(at, Color(1.0, 0.95, 0.15), 6.4, PRIORITY_BOSS)
	ring_at(at, Color(0.95, 0.08, 0.08), 4.4, PRIORITY_BOSS)
	if not _reduced_motion():
		burst_at(at + Vector3(0, 0.6, 0), Color(1.0, 0.32, 0.18), 2.0, PRIORITY_BOSS)


func _on_boss_slain(_boss_id: StringName) -> void:
	ring_at(Vector3.ZERO, Color(1.0, 0.85, 0.32), 9.5, PRIORITY_BOSS)
	burst_at(Vector3.ZERO + Vector3(0, 0.5, 0), Color(1.0, 0.88, 0.4), 2.2, PRIORITY_BOSS)


func _on_pickup_collected(pickup_id: StringName, _amount: int, collector: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(collector) and collector is Node3D:
		at = (collector as Node3D).global_position
	ring_at(at, Color(1.0, 0.88, 0.38), 1.0, PRIORITY_PICKUP)
	burst_at(at + Vector3(0, 0.6, 0), Color(1.0, 0.92, 0.55), 0.55, PRIORITY_PICKUP)


func _on_pickup_spawned(pickup: Node, _pickup_id: StringName) -> void:
	if not is_instance_valid(pickup) or not pickup is Node3D:
		return
	ring_at((pickup as Node3D).global_position, Color(0.45, 0.85, 1.0), 0.7, PRIORITY_PICKUP)


func _on_status_applied(target: Node, effect_id: StringName, _stacks: int) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	var color: Color = STATUS_COLORS.get(effect_id, Color(0.7, 0.7, 0.7))
	var at := (target as Node3D).global_position
	ring_at(at, color, 0.85, PRIORITY_STATUS)
	at += Vector3(0, 1.6, 0)
	if effect_id == &"burn" or effect_id == &"shock" or effect_id == &"poison" or effect_id == &"bleed":
		burst_at(at, color, 0.5, PRIORITY_STATUS)


func _on_projectile_fired(owner: Node, _weapon_id: StringName) -> void:
	if not is_instance_valid(owner) or not owner is Node3D:
		return
	var at := (owner as Node3D).global_position + Vector3(0, 1.0, 0)
	burst_at(at, Color(1.0, 0.82, 0.45), 0.48, PRIORITY_HIT)


func _on_skill_cast(skill_id: StringName, caster: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(caster) and caster is Node3D:
		at = (caster as Node3D).global_position
	var color: Color = SKILL_COLORS.get(skill_id, Color(0.8, 0.6, 0.2))
	var radius := _skill_radius(skill_id)
	var burst_scale := _skill_burst_scale(skill_id)
	var ring_tex: String = SKILL_RING_TEXTURES.get(skill_id, RING_TEXTURE)
	var burst_tex: String = SKILL_BURST_TEXTURES.get(skill_id, BURST_TEXTURE)
	# Ring with skill-specific shape texture — distinct identity beyond colour.
	var ring := _claim_ring(PRIORITY_SKILL)
	if ring != null:
		ring.global_position = at + Vector3(0.02, 0, 0.02)
		var mi := ring.get_node_or_null("Disc") as MeshInstance3D
		if mi != null:
			var mat := mi.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(color, 0.45)
				if ResourceLoader.exists(ring_tex):
					mat.albedo_texture = load(ring_tex)
		ring.scale = Vector3(radius, radius, radius)
		_show_ring(ring, 0.6)
		_ring_prios[ring] = PRIORITY_SKILL
	# Burst with skill-specific texture/amount — reuse pooled burst but swap its sprite for variety.
	var burst := _claim_burst(PRIORITY_SKILL)
	if burst != null:
		burst.global_position = at + Vector3(0, 0.3, 0)
		var bmat := burst.process_material as ParticleProcessMaterial
		if bmat != null:
			bmat.color = color
			# Per-skill particle tuning: whirls more particles, slams more spread.
			match skill_id:
				&"bladestorm":
					bmat.spread = 85.0; burst.amount = 28
				&"seismic_slam":
					bmat.spread = 45.0; burst.amount = 26
				&"phantom_rush":
					bmat.spread = 68.0; burst.amount = 20
				&"chain_lightning":
					bmat.spread = 75.0; burst.amount = 24
				_:
					bmat.spread = 68.0; burst.amount = 22
		else:
			burst.amount = 22
		if burst.draw_pass_1 is QuadMesh and ResourceLoader.exists(burst_tex):
			var quad := burst.draw_pass_1 as QuadMesh
			var qmat := quad.material as StandardMaterial3D
			if qmat != null:
				qmat.albedo_texture = load(burst_tex)
		burst.scale = Vector3.ONE * burst_scale
		burst.restart()
		_burst_prios[burst] = PRIORITY_SKILL


func _skill_radius(skill_id: StringName) -> float:
	match skill_id:
		&"frost_nova", &"frost_nova_skill":
			return 4.2
		&"seismic_slam":
			return 3.6
		&"bladestorm":
			return 3.2
		&"shatterwave":
			return 4.8
		&"chain_lightning":
			return 3.0
		&"phantom_rush":
			return 2.6
		&"mending_light":
			return 2.4
		&"warcry", &"warcry_skill":
			return 2.8
		_:
			return 2.8

func _skill_burst_scale(skill_id: StringName) -> float:
	match skill_id:
		&"seismic_slam":
			return 1.55
		&"shatterwave":
			return 1.65
		&"frost_nova", &"frost_nova_skill":
			return 1.45
		&"bladestorm":
			return 1.35
		&"chain_lightning":
			return 1.25
		&"phantom_rush":
			return 1.18
		&"mending_light":
			return 1.38
		&"warcry", &"warcry_skill":
			return 1.32
		_:
			return 1.35


func _on_player_leveled_up(_new_level: int, _xp: int) -> void:
	# Celebratory burst — called from player; find player via group if available.
	var at := Vector3.ZERO
	var players := get_tree().get_nodes_in_group(&"player") if get_tree() != null else []
	if players.size() > 0 and is_instance_valid(players[0]) and players[0] is Node3D:
		at = (players[0] as Node3D).global_position
	ring_at(at, Color(1.0, 0.88, 0.32), 2.2, PRIORITY_PLAYER)
	burst_at(at + Vector3(0, 1.2, 0), Color(1.0, 0.95, 0.55), 1.6, PRIORITY_PLAYER)
	burst_at(at + Vector3(0, 0.4, 0), Color(0.45, 0.85, 1.0), 1.1, PRIORITY_PLAYER)


func _on_weapon_equipped(_weapon_id: StringName, _slot: int) -> void:
	# Brief equip flash at player.
	var at := Vector3.ZERO
	var players := get_tree().get_nodes_in_group(&"player") if get_tree() != null else []
	if players.size() > 0 and is_instance_valid(players[0]) and players[0] is Node3D:
		at = (players[0] as Node3D).global_position + Vector3(0, 1.0, 0)
	burst_at(at, Color(0.72, 0.82, 1.0), 0.62, PRIORITY_PLAYER)


# ---------------------- pool management ----------------------

func _claim_burst(priority: int = PRIORITY_HIT) -> GPUParticles3D:
	# No detached "template" Node: every constructed emitter must enter the
	# owned pool below so world teardown frees its rendering resources.
	for b in _bursts:
		if not b.emitting:
			b.amount = 22
			return b
	# Grow the pool up to the mobile cap.
	if _bursts.size() < MAX_BURSTS:
		var b := _make_burst_template() as GPUParticles3D
		if b == null:
			return null
		add_child(b)
		_bursts.append(b)
		_burst_prios[b] = priority
		return b
	# Saturated: steal the lowest-priority active burst if the new request outranks it.
	var lowest: GPUParticles3D = null
	var lowest_prio := 9999
	for b in _bursts:
		var pr: int = int(_burst_prios.get(b, PRIORITY_HIT))
		if pr < lowest_prio:
			lowest_prio = pr
			lowest = b
	if lowest != null and priority > lowest_prio:
		lowest.restart()
		lowest.emitting = false # will be set emitting by caller via restart
		return lowest
	return null


func _claim_ring(priority: int = PRIORITY_HIT) -> Node3D:
	for r in _ring_pool:
		if not r.visible:
			return r
	if _ring_pool.size() < MAX_RINGS:
		var r := _make_ring()
		if r != null:
			add_child(r)
			_ring_pool.append(r)
			_ring_prios[r] = priority
			return r
	# Saturated: steal the lowest-priority visible ring if new request is higher.
	# Never evict a live BOSS ring for a grunt/spawn tell.
	var lowest: Node3D = null
	var lowest_prio := 9999
	for r in _ring_pool:
		var pr: int = int(_ring_prios.get(r, PRIORITY_HIT))
		if not r.visible:
			continue
		if priority < PRIORITY_BOSS and pr >= PRIORITY_BOSS:
			continue
		if pr < lowest_prio:
			lowest_prio = pr
			lowest = r
	if lowest != null and priority > lowest_prio:
		lowest.visible = false
		_prune_telegraph_count()
		return lowest
	return null


## One-shot bursts recycle automatically when particles finish (one_shot + short life).
func _make_burst_template() -> GPUParticles3D:
	if not _has_particle_texture(BURST_TEXTURE):
		return null
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 68.0
	mat.gravity = Vector3(0, -4.2, 0)
	mat.initial_velocity_min = 1.2
	mat.initial_velocity_max = 4.2
	mat.scale_min = 0.14
	mat.scale_max = 0.38
	mat.color = Color(1.0, 0.85, 0.55)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.angular_velocity_min = -120.0
	mat.angular_velocity_max = 120.0
	var p := GPUParticles3D.new()
	p.process_material = mat
	p.amount = 22
	p.lifetime = 0.68
	p.one_shot = true
	p.explosiveness = 1.0
	p.draw_pass_1 = _make_sprite(BURST_TEXTURE)
	p.emitting = false
	return p


## Expanding translucent disc lying flat on the ground (rotates up-facing, fades out).
func _make_ring() -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = &"Disc"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	mi.rotation_degrees.x = -90.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = load(RING_TEXTURE)
	mat.albedo_color = Color(1, 1, 1, 0.52)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 0.35
	mi.material_override = mat
	holder.add_child(mi)
	holder.visible = false
	holder.set_script(load("res://scripts/visuals/ring_fade.gd"))
	return holder


func _make_sprite(path: String) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(path)
	quad.material = mat
	return quad


func _show_ring(ring: Node3D, duration: float) -> void:
	ring.visible = true
	var fade := ring as RingFade
	if fade != null:
		fade.trigger(duration)


func _has_particle_texture(path: String) -> bool:
	return ResourceLoader.exists(path)


func _reduced_motion() -> bool:
	return SaveManager != null and SaveManager.get_settings() != null and SaveManager.get_settings().reduced_motion


func _high_contrast() -> bool:
	return SaveManager != null and SaveManager.get_settings() != null and SaveManager.get_settings().high_contrast


## Deuteranopia-safe boss/danger ink: yellow outer + red inner, not green-on-sand.
func _telegraph_color(color: Color, priority: int) -> Color:
	if _high_contrast() or priority >= PRIORITY_BOSS:
		if color.g > color.r and color.g > color.b:
			return Color(1.0, 0.92, 0.12)
		if color.r > 0.6:
			return Color(1.0, 0.12, 0.08)
	return color
