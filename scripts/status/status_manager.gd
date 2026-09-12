class_name StatusManager
extends Node

## Component owning all status effects on one entity (player or enemy).
## Siblings: HealthComponent (DoT/HoT sink), CharacterController/EnemyBase
## (speed factors are QUERIED via getters). Effects tick in _physics_process;
## expiry and cleanse remove their shield contribution as well as their effect.
##
## Caster status power is read from the caster's ProgressionComponent and copied
## into each StatusEffect instance. Shared .tres resources are never mutated.
##
## ---------------------------------------------------------------------------
## The read path is a cache, not a scan.
##
## Every derived number this component answers with (move speed, outgoing damage,
## incoming damage, stun, root, shield pool) is a fold over the active effects.
## Those queries are the hottest reads in the game: player.gd and enemy_base.gd ask
## for the speed factor and the stun flag *every physics tick per entity*, and the
## incoming factor plus absorb() run on every hit. Folding on each read used to mean
## ~80 Dictionary walks with an `as StatusEffect` cast and three pow() calls per
## effect, per tick, at a full wave — to recompute five numbers that only change when
## an effect is applied, stacked, removed or expires.
##
## So the fold happens once, lazily, when `_aggregates_dirty` is set — and it is set
## only by those four events. That is the Dirty Flag pattern (defer derived work until
## a read actually finds it stale), the same way Godot itself keeps a body's global
## transform, and the same way Unreal's GameplayEffects folds modifiers into an
## attribute aggregator and marks it dirty instead of re-evaluating per frame.
##
## Correctness rests on an invariant the type system now enforces: nothing outside
## scripts/status/ holds or mutates a StatusEffect (grep it), and the only per-frame
## mutation is tick() advancing time. Advancing time cannot change a modifier — only
## crossing zero can, and that flips `_aggregates_dirty` explicitly. `get_debug_snapshot()`
## exposes `recomputes`/`aggregate_reads` so a test can prove the cache is live.
## ---------------------------------------------------------------------------

signal effect_applied(effect_id: StringName, stacks: int)
signal effect_expired(effect_id: StringName)
signal effect_cleansed(effect_id: StringName)

## Typed so every read hands back a StatusEffect, not a Variant to cast. This table is
## runtime-only and must stay that way: Godot 4.4 cannot parse a typed Dictionary whose
## values are Resources inside a .tres (godot#100889) and rejects one assigned from
## JSON.parse_string (godot#97137), so exporting or saving it would break the load.
var _effects: Dictionary[StringName, StatusEffect] = {}
var _health: HealthComponent = null
var _owner_body: Node = null
var _bus: EventBusService = null
var _registry: ContentRegistryService = null

## Cached folds. `shield_pool` is derived state too — it used to be a third table
## (`_shield_layers`) re-summed from `.values()` on every apply, remove and absorbed hit.
var _move_factor: float = 1.0
var _outgoing_factor: float = 1.0
var _incoming_factor: float = 1.0
var _stunned: bool = false
var _rooted: bool = false
var _shield_pool: float = 0.0
var _aggregates_dirty: bool = true

## Scratch used to iterate the table without allocating, and the re-entrancy flag that
## makes reusing it safe (a damage signal can cleanse an effect mid-tick).
var _tick_keys: Array[StringName] = []
var _expiring: Array[StringName] = []
var _ticking: bool = false
var _recomputes: int = 0
var _aggregate_reads: int = 0


func _ready() -> void:
	_owner_body = get_parent()
	_health = get_parent().get_node_or_null("HealthComponent") as HealthComponent if get_parent() != null else null
	_bus = _autoload_node("EventBus") as EventBusService
	_registry = _autoload_node("ContentRegistry") as ContentRegistryService
	# A component with nothing to tick should not be ticked: an idle enemy used to pay a
	# _physics_process call plus an is_empty() test 60 times a second, and a wave of them
	# made "no effects at all" the most common state in the game. set_physics_process() is
	# how the rest of this project idles a node (RingFade, muzzle flashes).
	set_physics_process(not _effects.is_empty())


## Explicit health binding for hosts that add this StatusManager dynamically
## (the scene-wired path resolves in _ready above).
func bind_health(health_node: HealthComponent) -> void:
	_health = health_node


## Apply one effect by config. Returns the resulting stack count (0 = rejected).
##
## The config is audited once, here — never per tick. `StatusEffectConfig` now extends
## ValidatedConfig, so authored data is also checked at load; this call is what covers a
## config built in code (tests, future drop-in effects). The old tick loop re-ran the
## whole 14-rule audit — allocating an Array[String] each time — for every active effect
## every frame, to catch an "old save" that does not exist: status state is never
## serialized (SaveManager has no status path).
func apply_effect(config: StatusEffectConfig, stacks: int = 1, source: Node = null) -> int:
	if config == null or not config.validate().is_empty():
		return 0
	var id := config.effect_id
	var power := _power_for(source)
	var fx: StatusEffect = _effects.get(id, null)
	var folded := false
	if fx != null:
		var capacity_before := fx.shield_total()
		var layer_before := fx.shield_layer
		folded = fx.reapply(stacks, source, power.x, power.y, power.y)
		var capacity_after := fx.shield_total()
		if config.stack_mode == StatusEffectConfig.STACK_ADD:
			# ADD only grants the newly acquired capacity; refreshing at max does
			# not create an infinite shield loop.
			fx.shield_layer = layer_before + maxf(capacity_after - capacity_before, 0.0)
		else:
			# REFRESH/RESET replenish this effect's own layer to its authored
			# capacity while leaving other effect layers untouched.
			fx.shield_layer = capacity_after
		folded = folded or fx.shield_layer != layer_before
	else:
		fx = StatusEffect.new(config, stacks, source)
		fx.set_power_modifiers(power.x, power.y, power.y)
		_effects[id] = fx
		folded = true
	# A refresh that only renewed `remaining` cannot change a fold, so it does not
	# invalidate one: re-applying burn on every swing of a fire weapon is the common case.
	if folded:
		_aggregates_dirty = true
	set_physics_process(true)
	var total := fx.stacks
	effect_applied.emit(id, total)
	var bus := _event_bus()
	if bus != null:
		bus.status_applied.emit(_owner_body, id, total)
	return total


## Apply several effect ids at once (unknown ids are skipped with a warning).
func apply_effects(effect_ids: Array, source: Node = null) -> Dictionary:
	var applied: Dictionary = {}
	var registry := _content_registry()
	if registry == null:
		return applied
	for raw in effect_ids:
		var id := StringName(String(raw))
		var cfg: StatusEffectConfig = registry.get_status_effect(id)
		if cfg == null:
			var bus := _event_bus()
			if bus != null:
				bus.report_warning("Unknown status effect %s" % String(id))
			continue
		applied[id] = apply_effect(cfg, 1, source)
	return applied


func has_effect(effect_id: StringName) -> bool:
	return _effects.has(effect_id)


func stack_count(effect_id: StringName) -> int:
	var fx: StatusEffect = _effects.get(effect_id, null)
	return fx.stacks if fx != null else 0


func remaining_time(effect_id: StringName) -> float:
	var fx: StatusEffect = _effects.get(effect_id, null)
	return fx.remaining if fx != null else 0.0


func effect_count() -> int:
	return _effects.size()


## Cold path (HUD, debug): this allocates, so it is not what the tick or the combat
## queries use — they read the cached folds below.
func active_effect_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _effects:
		out.append(id)
	return out


## Remove one effect early (cleanse), including its unspent shield. Returns true
## when something was removed.
func cleanse(effect_id: StringName) -> bool:
	if not _effects.has(effect_id):
		return false
	_remove_effect(effect_id)
	effect_cleansed.emit(effect_id)
	return true


## Remove all harmful (or all) effects. Returns the number cleansed.
func cleanse_all(only_harmful: bool = true) -> int:
	var removed := 0
	# Snapshot first: erasing while iterating a Dictionary is undefined (Godot docs) and
	# this loop shrinks `_effects`. A local copy, deliberately not the tick scratch — a
	# pickup can call cleanse_all() from a damage signal while the tick is mid-loop.
	for id in _effects.keys():
		if not _effects.has(id):
			continue
		var fx: StatusEffect = _effects.get(id, null)
		if fx == null:
			continue
		if only_harmful and fx.config != null and not fx.config.is_harmful:
			continue
		_remove_effect(id)
		effect_cleansed.emit(id)
		removed += 1
	return removed


func clear_all() -> void:
	# keys() already returns a fresh Array; the old .duplicate() on top of it was a
	# second allocation for nothing.
	var removed: Array[StringName] = _effects.keys()
	_effects.clear()
	_shield_pool = 0.0
	_aggregates_dirty = true
	set_physics_process(false)
	for id in removed:
		effect_cleansed.emit(id)


func _physics_process(delta: float) -> void:
	if _effects.is_empty():
		# Safety: shield pool cannot outlive its effects.
		if _shield_pool != 0.0:
			_shield_pool = 0.0
			_aggregates_dirty = true
		set_physics_process(false)
		return
	if not is_inside_tree():
		return
	if delta <= 0.0 or not is_finite(delta):
		return
	if _ticking:
		# Re-entrant tick (a signal handler that applied damage that re-entered here).
		# The scratch arrays are shared, so the outer pass owns them.
		return
	_ticking = true
	var expired_count := 0
	# Cleared on entry as well as exit: an append that survived a future early return would
	# otherwise duplicate every key forever, and this array is the reason the tick allocates
	# nothing.
	_tick_keys.clear()
	for id in _effects:
		_tick_keys.append(id)
	for i in _tick_keys.size():
		var effect_id: StringName = _tick_keys[i]
		if not _effects.has(effect_id):
			continue
		var fx: StatusEffect = _effects.get(effect_id, null)
		if fx == null:
			_expiring.append(effect_id)
			expired_count += 1
			continue
		var was_expired := fx.is_expired()
		var ticks := fx.tick(delta)
		if ticks > 0:
			_apply_ticks(fx, ticks)
		if not was_expired and fx.is_expired():
			# The one time-dependent change a fold cares about.
			_aggregates_dirty = true
		if fx.is_expired():
			_expiring.append(effect_id)
			expired_count += 1
	_tick_keys.clear()
	if expired_count > 0:
		for exp_idx in _expiring.size():
			var effect_id: StringName = _expiring[exp_idx]
			_remove_effect(effect_id)
			effect_expired.emit(effect_id)
			var bus := _event_bus()
			if bus != null:
				bus.status_expired.emit(_owner_body, effect_id)
		_expiring.clear()
	_ticking = false


func _apply_ticks(fx: StatusEffect, ticks: int) -> void:
	if _health == null or not is_instance_valid(_health):
		return
	var dot := fx.dot_per_tick() * float(ticks)
	var damage_allowed := not _health.is_dead()
	if damage_allowed:
		damage_allowed = not _health.is_invulnerable()
	if dot > 0.0 and damage_allowed:
		dot = absorb_direct(dot)
		if dot > 0.0:
			var payload := DamagePayload.new()
			payload.amount = dot
			payload.source = fx.source if is_instance_valid(fx.source) else null
			payload.source_id = fx.source_id
			payload.damage_type = fx.config.dot_type if fx.config != null else &"physical"
			payload.hit_position = (_owner_body as Node3D).global_position if _owner_body is Node3D else Vector3.ZERO
			if payload.is_valid():
				_health.take_damage(payload)
	var hot := fx.hot_per_tick() * float(ticks)
	if hot > 0.0:
		_health.heal(hot)


func _remove_effect(effect_id: StringName) -> void:
	_effects.erase(effect_id)
	_aggregates_dirty = true
	if _effects.is_empty():
		set_physics_process(false)


## Read status-build multipliers without mutating config resources. The source's
## progression wins; self-applied effects fall back to the affected entity.
##
## A Vector2 pair, not a Dictionary: this ran three string hash lookups per application,
## and it made the shared `status_damage_multiplier` look like a mistake — the fifth
## argument is `hot_mult`, and the two are deliberately the same number because progression
## authors one "status power" stat (`upgrade_config.ALLOWED_STATS`), not a DoT and a HoT
## stat. Kept identical on purpose; now written where a reader can see it.
func _power_for(source: Node) -> Vector2:
	var provider := source
	if provider == null or not is_instance_valid(provider):
		provider = _owner_body
	var prog := provider.get_node_or_null("ProgressionComponent") as ProgressionComponent if provider is Node else null
	var duration := 1.0
	var damage := 1.0
	if prog != null:
		duration = prog.get_stat(&"status_duration_multiplier", 1.0)
		damage = prog.get_stat(&"status_damage_multiplier", 1.0)
	return Vector2(clampf(duration, 0.05, 10.0), clampf(damage, 0.0, 10.0))


# ---------------- Aggregated modifier queries ----------------
#
# Each of these is a field read; the fold runs at most once per tick per entity and only
# if something actually changed. `aggregate_reads`/`recomputes` in get_debug_snapshot()
# let a test assert that (drop the dirty check and the ratio goes 1:1).

func move_speed_factor() -> float:
	_consume_aggregate_read()
	return _move_factor


func outgoing_damage_factor() -> float:
	_consume_aggregate_read()
	return _outgoing_factor


func incoming_damage_factor() -> float:
	_consume_aggregate_read()
	return _incoming_factor


func is_stunned() -> bool:
	_consume_aggregate_read()
	return _stunned


func is_rooted() -> bool:
	_consume_aggregate_read()
	return _rooted


func shield_remaining() -> float:
	_consume_aggregate_read()
	return maxf(_shield_pool, 0.0)


func _consume_aggregate_read() -> void:
	_aggregate_reads += 1
	if _aggregates_dirty:
		_recompute_aggregates()


## The single fold. Multiplicative axes include effects that have expired but are not
## removed yet (that is how the per-read scans behaved, and it self-corrects within the
## same tick); the stun/root locks skip them, because letting a stale lock hold a player
## still for one more frame is a bug the old code deliberately guarded.
## Calling no code outside StatusEffect is what makes it safe to run lazily from an
## arbitrary read site: nothing here can re-enter the manager mid-fold.
func _recompute_aggregates() -> void:
	_recomputes += 1
	_aggregates_dirty = false
	var move := 1.0
	var outgoing := 1.0
	var incoming := 1.0
	var stunned := false
	var rooted := false
	var pool := 0.0
	for id in _effects:
		var fx: StatusEffect = _effects[id]
		move *= fx.move_speed_factor()
		outgoing *= fx.damage_factor()
		incoming *= fx.received_damage_factor()
		if fx.shield_layer > 0.0:
			pool += fx.shield_layer
		if fx.is_expired():
			continue
		if fx.config != null:
			stunned = stunned or fx.config.stuns
			rooted = rooted or fx.config.roots
	# Never NaN-propagate: a finite factor is required so the game keeps running.
	_move_factor = 1.0 if not is_finite(move) else clampf(move, 0.0, 2.0)
	_outgoing_factor = 1.0 if not is_finite(outgoing) else clampf(outgoing, 0.0, 10.0)
	_incoming_factor = 1.0 if not is_finite(incoming) else clampf(incoming, 0.0, 10.0)
	_shield_pool = pool if is_finite(pool) else 0.0
	_stunned = stunned
	_rooted = rooted


## Spend shield against a direct hit. Returns the leftover damage. Layers are
## consumed in stable effect insertion order so expiring one shield cannot erase
## another effect's unspent capacity.
func absorb_direct(amount: float) -> float:
	if not is_finite(amount) or amount <= 0.0:
		return 0.0
	var remaining := clampf(amount, 0.0, 10000.0)
	if _effects.is_empty():
		return remaining
	var spent := false
	for id in _effects:
		if remaining <= 0.0:
			break
		var fx: StatusEffect = _effects[id]
		if fx.shield_layer <= 0.0:
			continue
		# One walk over a handful of effects: no key snapshot (the old code allocated an
		# Array and then copied it) and no per-hit Dictionary writes, because the layer
		# lives on the effect that grants it.
		remaining = fx.absorb(remaining)
		spent = true
	if spent:
		_aggregates_dirty = true
	return maxf(remaining, 0.0)


## Resolved once in _ready (and lazily after, for a manager built dynamically): every
## application and every expiry used to walk /root to find the bus, which at a full wave
## is 60+ lookups a second for a node reference that never changes. The path lookup itself
## stays: headless harnesses do not boot the autoload globals.
func _event_bus() -> EventBusService:
	if _bus == null:
		_bus = _autoload_node("EventBus") as EventBusService
	return _bus


func _content_registry() -> ContentRegistryService:
	if _registry == null:
		_registry = _autoload_node("ContentRegistry") as ContentRegistryService
	return _registry


func _autoload_node(node_name: String) -> Node:
	# Node.get_tree() on a node that is not inside the tree returns null AND logs
	# an engine error ("Parameter \"data.tree\" is null"). Check membership first
	# so detached instances (headless fixtures, unanchored components) never spam
	# that error; the main-loop fallback below still resolves the autoloads.
	var tree: SceneTree = null
	if is_inside_tree():
		tree = get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


func get_debug_snapshot() -> Dictionary:
	var list: Array = []
	for id in _effects:
		list.append(_effects[id].get_debug_snapshot())
	return {
		"effects": list,
		"shield": _shield_pool,
		"recomputes": _recomputes,
		"aggregate_reads": _aggregate_reads,
		"stale": _aggregates_dirty,
	}
