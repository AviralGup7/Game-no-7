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
##
## Collaborators (typed helpers, no gameplay state of their own):
##  - EffectEventHandlers translates EventBus events into burst/ring calls.
##  - EffectReadability resolves reduced-motion / high-contrast / danger ink.
##  - EffectPriorities holds the saturation ladder these two modules share.
##  - EffectSkillCatalog holds per-skill shape/radius/burst tuning.
##  - EffectTemplates builds the pooled burst/ring nodes.
##  - EffectPlacement answers world queries (arena origin, ground probe).

const MAX_BURSTS := 10
const MAX_RINGS := 14
const MAX_LIVE_TELEGRAPH := 6
const BOSS_RING_RESERVE := 2
const MAX_MUZZLE := 4
const RING_TEXTURE := "res://assets/scifi/fx/ring.png"
const BURST_TEXTURE := "res://assets/scifi/fx/spark.png"

# Pool priorities — higher wins when saturated. Values live in EffectPriorities
# (no cross-references) and are re-exported here for the rest of the codebase.
const PRIORITY_CRITICAL := EffectPriorities.CRITICAL
const PRIORITY_BOSS := EffectPriorities.BOSS
const PRIORITY_PLAYER := EffectPriorities.PLAYER
const PRIORITY_SKILL := EffectPriorities.SKILL
const PRIORITY_ENEMY_DEATH := EffectPriorities.ENEMY_DEATH
const PRIORITY_SPAWN := EffectPriorities.SPAWN
const PRIORITY_PICKUP := EffectPriorities.PICKUP
const PRIORITY_ENEMY_HIT := EffectPriorities.ENEMY_HIT
const PRIORITY_HIT := EffectPriorities.HIT
const PRIORITY_STATUS := EffectPriorities.STATUS
const PRIORITY_AMBIENT := EffectPriorities.AMBIENT

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

## Skill shape/radius/burst tuning lives in EffectSkillCatalog (one table per
## concern); the colour table above stays here with the canonical id list.
var _bursts: Array[GPUParticles3D] = []
var _ring_pool: Array[Node3D] = []
var _burst_prios: Dictionary = {} # GPUParticles3D -> int
var _ring_prios: Dictionary = {} # Node3D -> int
var _wired := false
var _live_telegraphs := 0
var _burst_cap: int = MAX_BURSTS
var _ring_cap: int = MAX_RINGS
var _isolated := false
var _events := EffectEventHandlers.new()


func _ready() -> void:
	add_to_group("effect_director")
	_wire_events()


func _exit_tree() -> void:
	_unbind_events()


## Hide every burst/ring and drop EventBus listeners while the director stays
## in the tree (GAME_OVER keeps WorldRoot). UI observers are not touched.
func isolate_run() -> void:
	_unbind_events()
	_hide_all()
	_isolated = true


func is_isolated() -> bool:
	return _isolated


func apply_budget(bursts: int, rings: int) -> void:
	_burst_cap = clampi(bursts, 1, MAX_BURSTS)
	_ring_cap = clampi(rings, 1, MAX_RINGS)
	_trim_to_budget()


## Status accent colour for the event-handler module — STATUS_COLORS stays here with
## the canonical skill/status id list the configs are validated against.
func status_color(effect_id: StringName) -> Color:
	return STATUS_COLORS.get(effect_id, Color(0.7, 0.7, 0.7))


func burst_cap() -> int:
	return _burst_cap


func ring_cap() -> int:
	return _ring_cap


func _unbind_events() -> void:
	if EventBus != null:
		_events.disconnect_all(EventBus)
		EventBus.unbind(EventBus.skill_cast, _on_skill_cast)
	_wired = false


func _hide_all() -> void:
	for p in _bursts:
		if p != null:
			p.emitting = false
	for r in _ring_pool:
		if r != null:
			r.visible = false
	_live_telegraphs = 0


func _trim_to_budget() -> void:
	var live_bursts := 0
	for p in _bursts:
		if p == null or not p.emitting:
			continue
		live_bursts += 1
		if live_bursts > _burst_cap:
			p.emitting = false
	var live_rings := 0
	for r in _ring_pool:
		if r == null or not r.visible:
			continue
		live_rings += 1
		if live_rings > _ring_cap:
			r.visible = false
	_prune_telegraph_count()


## Death / impact explosion at a world position (pooled, no autoload dependency).
func burst_at(at: Vector3, color: Color, scale: float = 1.0, priority: int = PRIORITY_HIT) -> void:
	if _isolated:
		return
	if EffectReadability.reduced_motion() and priority < PRIORITY_SKILL:
		return
	var p := _claim_burst(priority)
	if p == null:
		return
	p.global_position = at
	var mat := p.process_material as ParticleProcessMaterial
	if mat != null:
		mat.color = color
	p.amount = EffectTemplates.BURST_AMOUNT
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
	if _isolated:
		return false
	_prune_telegraph_count()
	if for_boss:
		return _can_claim_ring(PRIORITY_BOSS)
	if _live_telegraphs >= MAX_LIVE_TELEGRAPH:
		return false
	var bosses_alive := 0
	if is_inside_tree() and get_tree() != null:
		for n in get_tree().get_nodes_in_group(BossController.BOSS_GROUP):
			if n is Damageable and (n as Damageable).is_alive():
				bosses_alive += 1
	var reserve := BOSS_RING_RESERVE if bosses_alive > 0 else 0
	var free_count := 0
	for r in _ring_pool:
		if not r.visible:
			free_count += 1
	free_count += maxi(0, _ring_cap - _ring_pool.size())
	if free_count <= reserve:
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
	if _ring_pool.size() < MAX_RINGS and _ring_pool.size() < _ring_cap:
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
	if _isolated:
		return
	var ring := _claim_ring(priority)
	if ring == null:
		return
	_place_ring_on_floor(ring, at)
	var mi := ring.get_node_or_null("Disc") as MeshInstance3D
	if mi != null:
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			if ResourceLoader.exists(RING_TEXTURE):
				mat.albedo_texture = load(RING_TEXTURE)
			var ink := EffectReadability.telegraph_color(color, priority >= PRIORITY_BOSS)
			var alpha := 0.95 if EffectReadability.high_contrast() else (0.85 if priority >= PRIORITY_BOSS else 0.45)
			mat.albedo_color = Color(ink, alpha)
			mat.emission_enabled = true
			mat.emission = ink
			mat.emission_energy_multiplier = (2.0 if EffectReadability.high_contrast() else 1.4) if priority >= PRIORITY_BOSS else (0.7 if EffectReadability.high_contrast() else 0.35)
	var hold := 1.15 if priority >= PRIORITY_BOSS else 0.6
	if EffectReadability.reduced_motion():
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
	_events.bind(self)
	_events.connect_all(EventBus, self)
	# The cast handler stays here: it paints pooled ring/burst materials itself.
	EventBus.bind(self, EventBus.skill_cast, _on_skill_cast)


func _place_ring_on_floor(ring: Node3D, at: Vector3) -> void:
	if ring == null:
		return
	var floor_y := EffectPlacement.floor_hit(self, at)
	var grounded := at
	grounded.y = float(floor_y.get("y", at.y))
	ring.rotation = Vector3.ZERO
	ring.global_position = grounded + Vector3(0.02, 0.03, 0.02)
	var nrm: Vector3 = floor_y.get("normal", Vector3.UP)
	if nrm.length_squared() > 0.01 and absf(nrm.dot(Vector3.UP)) < 0.95:
		ring.look_at(ring.global_position + nrm, Vector3.UP)


func _on_skill_cast(skill_id: StringName, caster: Node) -> void:
	var at := Vector3.ZERO
	if is_instance_valid(caster) and caster is Node3D:
		at = (caster as Node3D).global_position
	var color: Color = SKILL_COLORS.get(skill_id, Color(0.8, 0.6, 0.2))
	var radius := EffectSkillCatalog.ring_radius(skill_id)
	var burst_scale := EffectSkillCatalog.burst_scale(skill_id)
	var ring_tex := EffectSkillCatalog.ring_texture(skill_id, RING_TEXTURE)
	var burst_tex := EffectSkillCatalog.burst_texture(skill_id, BURST_TEXTURE)
	# Ring with skill-specific shape texture — distinct identity beyond colour.
	var ring := _claim_ring(PRIORITY_SKILL)
	if ring != null:
		_place_ring_on_floor(ring, at)
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
			bmat.spread = EffectSkillCatalog.burst_spread(skill_id)
			burst.amount = EffectSkillCatalog.burst_amount(skill_id)
		else:
			burst.amount = EffectTemplates.BURST_AMOUNT
		if burst.draw_pass_1 is QuadMesh and ResourceLoader.exists(burst_tex):
			var quad := burst.draw_pass_1 as QuadMesh
			var qmat := quad.material as StandardMaterial3D
			if qmat != null:
				qmat.albedo_texture = load(burst_tex)
		burst.scale = Vector3.ONE * burst_scale
		burst.restart()
		_burst_prios[burst] = PRIORITY_SKILL


func _claim_burst(priority: int = PRIORITY_HIT) -> GPUParticles3D:
	if _isolated:
		return null
	# No detached "template" Node: every constructed emitter must enter the
	# owned pool below so world teardown frees its rendering resources.
	var idle: GPUParticles3D = null
	var emitting := 0
	for pooled in _bursts:
		if pooled.emitting:
			emitting += 1
		elif idle == null:
			idle = pooled
	if idle != null and emitting < _burst_cap:
		idle.amount = EffectTemplates.BURST_AMOUNT
		return idle
	# Grow the pool up to the mobile cap, but never past the governor budget.
	if _bursts.size() < MAX_BURSTS and emitting < _burst_cap:
		var burst := _make_burst_template() as GPUParticles3D
		if burst == null:
			return null
		add_child(burst)
		_bursts.append(burst)
		_burst_prios[burst] = priority
		return burst
	# Saturated: steal the lowest-priority active burst if the new request outranks it.
	var lowest: GPUParticles3D = null
	var lowest_prio := 9999
	for pooled in _bursts:
		var pr: int = int(_burst_prios.get(pooled, PRIORITY_HIT))
		if pr < lowest_prio:
			lowest_prio = pr
			lowest = pooled
	if lowest != null and priority > lowest_prio:
		lowest.restart()
		lowest.emitting = false # will be set emitting by caller via restart
		return lowest
	return null


func _claim_ring(priority: int = PRIORITY_HIT) -> Node3D:
	if _isolated:
		return null
	var idle: Node3D = null
	var visible_count := 0
	for pooled in _ring_pool:
		if pooled.visible:
			visible_count += 1
		elif idle == null:
			idle = pooled
	if idle != null and visible_count < _ring_cap:
		return idle
	if _ring_pool.size() < MAX_RINGS and visible_count < _ring_cap:
		var ring := _make_ring()
		if ring != null:
			add_child(ring)
			_ring_pool.append(ring)
			_ring_prios[ring] = priority
			return ring
	# Saturated: steal the lowest-priority visible ring if new request is higher.
	# Never evict a live BOSS ring for a grunt/spawn tell.
	var lowest: Node3D = null
	var lowest_prio := 9999
	for pooled in _ring_pool:
		var pr: int = int(_ring_prios.get(pooled, PRIORITY_HIT))
		if not pooled.visible:
			continue
		if priority < PRIORITY_BOSS and pr >= PRIORITY_BOSS:
			continue
		if pr < lowest_prio:
			lowest_prio = pr
			lowest = pooled
	if lowest != null and priority > lowest_prio:
		lowest.visible = false
		_prune_telegraph_count()
		return lowest
	return null


## One-shot bursts recycle automatically when particles finish (one_shot + short life).
## Returns null when the burst texture is unavailable, keeping the pool a no-op.
func _make_burst_template() -> GPUParticles3D:
	return EffectTemplates.make_burst(BURST_TEXTURE)


## Expanding translucent disc lying flat on the ground (rotates up-facing, fades out).
func _make_ring() -> Node3D:
	return EffectTemplates.make_ring(RING_TEXTURE)


func _show_ring(ring: Node3D, duration: float) -> void:
	ring.visible = true
	var fade := ring as RingFade
	if fade != null:
		fade.trigger(duration)


