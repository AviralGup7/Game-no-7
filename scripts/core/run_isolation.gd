class_name RunIsolation
extends RefCounted

## End-of-run freeze while the arena is still on screen (GAME_OVER).
##
## MAIN_MENU later frees WorldRoot; until then projectiles, pickups, VFX and
## spatial Foley would keep simulating under the summary overlay. This walks
## the live tree by group, drains those pools, and unbinds run-scoped non-UI
## EventBus listeners. UI observers (HUD, banners, settings) stay connected.
##
## Combat numbers, hit radii and pity are not touched. Audio is resolved by
## child path (SpatialVoices) so this script never names the AudioManager
## autoload identifier — the hermetic --script harness can load it.

const GROUP_PROJECTILES := &"projectile_pool"
const GROUP_PICKUPS := &"pickup_manager"
const GROUP_EFFECTS := &"effect_director"
const GROUP_HITSTOP := &"hitstop_manager"
const GROUP_OBJECTIVES := &"objective_director"
const GROUP_NUMBERS := &"damage_number_layer"
const GROUP_PLAYER := &"player"
const AUDIO_PATH := "/root/AudioManager"
const SPATIAL_CHILD := "SpatialVoices"


## Isolate every run-scoped pool reachable from `from`. Safe with a null or
## detached node (returns an empty report). Does not free WorldRoot.
static func isolate_from(from: Node) -> Dictionary:
	var report := empty_report()
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return report
	var tree := from.get_tree()
	if tree == null:
		return report
	_drain_projectiles(tree, report)
	_drain_pickups(tree, report)
	_drain_effects(tree, report)
	_drain_hitstop(tree, report)
	_drain_objectives(tree, report)
	_drain_numbers(tree, report)
	_drain_players(tree, report)
	report["audio"] = _isolate_audio(tree)
	return report


static func empty_report() -> Dictionary:
	return {
		"projectiles": -1,
		"pickups": -1,
		"effects": false,
		"hitstop": false,
		"objectives": false,
		"numbers": false,
		"players": 0,
		"audio": false,
	}


static func _drain_projectiles(tree: SceneTree, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(GROUP_PROJECTILES)):
		var pool := n as ProjectilePool
		if pool == null:
			continue
		pool.isolate_run()
		report["projectiles"] = pool.active_count()


static func _drain_pickups(tree: SceneTree, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(GROUP_PICKUPS)):
		var pickups := n as PickupManager
		if pickups == null:
			continue
		pickups.isolate_run()
		report["pickups"] = pickups.live_count()


static func _drain_effects(tree: SceneTree, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(GROUP_EFFECTS)):
		var fx := n as EffectDirector
		if fx == null:
			continue
		fx.isolate_run()
		report["effects"] = true


static func _drain_hitstop(tree: SceneTree, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(GROUP_HITSTOP)):
		var hit := n as HitstopManager
		if hit == null:
			continue
		hit.isolate_run()
		report["hitstop"] = true


static func _drain_objectives(tree: SceneTree, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(GROUP_OBJECTIVES)):
		var obj := n as ObjectiveDirector
		if obj == null:
			continue
		obj.isolate_run()
		report["objectives"] = true


static func _drain_numbers(tree: SceneTree, report: Dictionary) -> void:
	for n in tree.get_nodes_in_group(String(GROUP_NUMBERS)):
		var numbers := n as DamageNumberLayer
		if numbers == null:
			continue
		numbers.clear_all()
		report["numbers"] = true


static func _drain_players(tree: SceneTree, report: Dictionary) -> void:
	var players := 0
	for n in tree.get_nodes_in_group(String(GROUP_PLAYER)):
		var player := n as Player
		if player == null:
			continue
		player.isolate_run()
		players += 1
	report["players"] = players


## Parks spatial Foley. The AudioManager autoload also exposes isolate_run()
## (listener + spatial); Main calls that with the autoload identifier. This
## path is the harness-safe fallback when only the node tree is available.
static func _isolate_audio(tree: SceneTree) -> bool:
	if tree == null or tree.root == null:
		return false
	var audio_node := tree.root.get_node_or_null(AUDIO_PATH)
	if audio_node == null:
		return false
	var spatial := audio_node.get_node_or_null(SPATIAL_CHILD) as SpatialVoicePool
	if spatial != null:
		spatial.isolate_run()
	return true


## True when every drained pool in `report` is empty / flagged. Unknown (-1)
## counts are treated as "not present", not as a leak.
static func is_quiet(report: Dictionary) -> bool:
	if int(report.get("projectiles", 0)) > 0:
		return false
	if int(report.get("pickups", 0)) > 0:
		return false
	return true


## Group names the governor and isolator share, so a renamed group cannot
## silently split the two walkers.
static func known_groups() -> PackedStringArray:
	return PackedStringArray([
		String(GROUP_PROJECTILES),
		String(GROUP_PICKUPS),
		String(GROUP_EFFECTS),
		String(GROUP_HITSTOP),
		String(GROUP_OBJECTIVES),
		String(GROUP_NUMBERS),
		String(GROUP_PLAYER),
	])
