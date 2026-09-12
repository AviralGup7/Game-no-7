class_name CampaignDirector
extends Node
## Story/checkpoint authority. UI sends an interaction request; distance, mission
## order, encounter requirements and once-only rewards are checked here.

signal changed
signal message(text: String)
const INTERACT_RANGE := 4.5
const UPDATE_INTERVAL := 0.25
var definition: CampaignDefinition
var progress: Dictionary
var encounters: CampaignEncounters
var player: Player
var world: CampaignWorld
var route := PackedVector3Array()
var _meta: MetaProgression
var _clock := 0.0
var _checkpoint_inside := ""
var _route_origin := Vector3.INF
var _route_target := ""
var _route_target_position := Vector3.INF
var _ready_to_save := false
var _stopped := false
var _completion_pending := false


func configure(station: CampaignWorld, hero: Player, wallet: MetaProgression) -> void:
	world = station
	definition = station.definition
	player = hero
	_meta = wallet
	progress = CampaignProgress.reconcile(SaveManager.get_campaign(), definition)
	_restore_build()
	encounters = CampaignEncounters.new()
	encounters.name = "CampaignEncounters"
	add_child(encounters)
	encounters.configure(world, player, progress)
	encounters.member_defeated.connect(_on_member_defeated)
	player.get_experience_component().xp_changed.connect(_on_xp_changed)
	EventBus.weapon_equipped.connect(_on_weapon_equipped)
	EventBus.weapon_switched.connect(_on_weapon_switched)
	_ready_to_save = true
	_refresh_markers()
	_update_route()
	save_progress(false)


func _restore_build() -> void:
	var stage := maxi(int(progress.mission) + 1, 1)
	GameRoot.record_current_wave(stage)  # Only legacy combat unlock gates use this mirror.
	player.get_progression_component().restore_progression(progress.upgrades, stage)
	player.get_weapon_manager().configure(0)
	player.get_skill_controller().configure(0)
	for slot in range(progress.weapons.size()):
		var id := StringName(String(progress.weapons[slot]))
		player.get_weapon_manager().equip_by_id(id, slot, true)
		if String(id) == String(progress.active_weapon):
			player.get_weapon_manager().switch_to(slot)
	for slot in range(progress.skills.size()):
		var id := StringName(String(progress.skills[slot]))
		player.get_skill_controller().assign_skill_by_id(id, slot, id == &"seismic_slam" or _meta.is_skill_unlocked_from_start(id))
	player.get_experience_component().restore_total(int(progress.xp))
	_meta.apply_all_to_run()
	# Existing armory purchases survive migration. Only fill an EMPTY secondary
	# slot; never replace the player's saved campaign reward weapon on Continue.
	if player.get_weapon_manager().slot_instance(1) == null:
		for id in _meta.unlocked_targets(&"weapon"):
			if player.get_weapon_manager().equip_by_id(id, 1, true):
				break
	player.rebuild_derived_stats()
	player.get_health_component().heal(player.get_health_component().get_max())
	player.get_stamina_component().restore_full()


func _physics_process(delta: float) -> void:
	if _stopped or not is_instance_valid(player) or GameRoot.get_current_state() != GameRoot.State.PLAYING:
		return
	if _completion_pending:
		_completion_pending = false
		GameRoot.complete_campaign()
		return
	_clock += delta
	if _clock < UPDATE_INTERVAL:
		return
	_clock = 0.0
	world.update_visibility(player.global_position)
	_visit_district()
	_visit_checkpoint()
	# A physical containment backstop for extreme knockback/collision tunneling;
	# ordinary travel always follows the connected decks without teleportation.
	if player.global_position.y < -4.0 or not world.point_is_on_floor(player.global_position):
		player.global_transform = definition.checkpoint(String(progress.checkpoint))
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		message.emit("Returned to the last safe checkpoint.")
	_update_route()
	changed.emit()


func _visit_district() -> void:
	var sector := definition.sector_at(player.global_position)
	if sector.is_empty() or String(sector.id) in progress.visited:
		return
	progress.visited.append(String(sector.id))
	message.emit(String(sector.name))
	save_progress(false)


func _visit_checkpoint() -> void:
	var near := ""
	for sector in definition.sectors:
		if player.global_position.distance_to(CampaignDefinition.point(sector.checkpoint)) <= INTERACT_RANGE:
			near = String(sector.id)
			break
	if near.is_empty():
		_checkpoint_inside = ""
		return
	if near == _checkpoint_inside or not encounters.safe_to_rest(player.global_position):
		return
	_checkpoint_inside = near
	progress.checkpoint = near
	player.get_health_component().heal(player.get_health_component().get_max())
	player.get_stamina_component().restore_full()
	if save_progress(true):
		message.emit("CHECKPOINT SAVED / health and stamina restored")
	else:
		message.emit("Restored health. Saving failed — please retry before closing.")


func current_mission() -> Dictionary:
	var index := int(progress.get("mission", 0))
	return definition.missions[index] if index < definition.missions.size() else {}


func target_ids() -> Array:
	var mission := current_mission()
	var result: Array = []
	for id in mission.get("targets", []):
		if id not in progress.interacted:
			result.append(id)
	return result


func remaining_guards() -> int:
	var count := 0
	for id in current_mission().get("requires", []):
		count += encounters.remaining(String(id))
	return count


func nearest_interaction() -> Dictionary:
	if not is_instance_valid(player):
		return {}
	var nearest: Dictionary = {}
	var distance := INTERACT_RANGE
	var targets := target_ids()
	for item in definition.interactions:
		if item.id in progress.interacted or (item.kind != "cache" and item.id not in targets):
			continue
		var d := CampaignDefinition.point(item.at).distance_to(player.global_position)
		if d <= distance:
			distance = d
			nearest = item
	return nearest


func try_interact() -> bool:
	if _stopped or not player.is_alive() or GameRoot.get_current_state() != GameRoot.State.PLAYING:
		return false
	var item := nearest_interaction()
	if item.is_empty():
		return false
	if item.kind != "cache" and remaining_guards() > 0:
		message.emit("Secure the district first / %d hostiles remaining" % remaining_guards())
		return false
	progress.interacted.append(String(item.id))
	if item.kind == "cache":
		player.get_health_component().heal(30.0)
		_commit_reward(int(item.credits), true)
		message.emit("SUPPLY LOCKER / +%d credits / +30 health" % int(item.credits))
	else:
		var all_done := true
		for id in current_mission().get("targets", []):
			all_done = all_done and id in progress.interacted
		if all_done:
			_complete_mission()
		else:
			save_progress(true)
			message.emit("Manifest recovered. Find the remaining records.")
	_refresh_markers()
	_route_origin = Vector3.INF
	_update_route()
	changed.emit()
	return true


func _complete_mission() -> void:
	var mission := current_mission()
	if mission.is_empty():
		return
	# Advance BEFORE rewards/save. A single atomic save includes the completed
	# target IDs, new mission cursor, build and wallet: Continue cannot replay it.
	progress.mission = int(progress.mission) + 1
	progress.checkpoint = String(mission.sector)
	progress.completed = int(progress.mission) >= definition.missions.size()
	var reward: Dictionary = mission.get("reward", {})
	GameRoot.record_current_wave(int(progress.mission) + 1)
	var upgrade := StringName(String(reward.get("upgrade", "")))
	if upgrade != &"":
		player.get_progression_component().apply_upgrade_by_id(upgrade)
		player.rebuild_derived_stats()
	var weapon := StringName(String(reward.get("weapon", "")))
	if weapon != &"":
		player.get_weapon_manager().equip_by_id(weapon, 1, true)
	player.add_xp(float(reward.get("xp", 0)))
	_commit_reward(int(reward.get("credits", 0)), true)
	message.emit("OBJECTIVE COMPLETE / " + String(mission.title))
	AudioManager.play_sfx(&"upgrade_select", -8.0)
	if bool(progress.completed):
		# A save-error dialog may have paused during the reward transaction.
		# Finish after Resume instead of losing the ending behind that overlay.
		_completion_pending = GameRoot.get_current_state() != GameRoot.State.PLAYING
		GameRoot.complete_campaign()


func _on_member_defeated(_id: String, credits: int) -> void:
	_commit_reward(credits, false)
	changed.emit()


func _commit_reward(credits: int, flush: bool) -> void:
	save_progress(false)
	if credits > 0:
		_meta.grant_currency(credits, flush)
	elif flush:
		SaveManager.save_now()


func _on_xp_changed(_xp: int, _level: int, _into: int, _need: int) -> void:
	save_progress(false)


func _on_weapon_equipped(_id: StringName, _slot: int) -> void:
	save_progress(false)


func _on_weapon_switched(_old: StringName, _id: StringName) -> void:
	save_progress(false)


func save_progress(flush: bool = true) -> bool:
	if not _ready_to_save or not is_instance_valid(player):
		return false
	progress.started = true
	progress.xp = player.get_experience_component().total_xp_earned()
	progress.upgrades = player.get_progression_component().get_progression_snapshot()
	progress.weapons = player.get_weapon_manager().get_loadout_ids()
	progress.active_weapon = String(player.get_weapon_manager().active_weapon_id())
	progress.skills = player.get_skill_controller().get_assigned_skill_ids()
	return SaveManager.store_campaign(progress, flush)


func _refresh_markers() -> void:
	world.update_markers(progress.interacted, target_ids())


func next_target() -> Dictionary:
	var nearest: Dictionary = {}
	var distance := INF
	# When a console is guarded, navigation takes the player to the remaining
	# guards first, rather than stranding them at an inactive terminal.
	for id in current_mission().get("requires", []):
		for member in definition.encounter(String(id)).get("members", []):
			if member.id in progress.defeated:
				continue
			var at := encounters.member_position(member)
			var d := at.distance_squared_to(player.global_position)
			if d < distance:
				distance = d
				nearest = {"id": member.id, "at": [at.x, at.y, at.z], "name": "Secure the district"}
	if not nearest.is_empty():
		return nearest
	for id in target_ids():
		var item := definition.interaction(String(id))
		var d := CampaignDefinition.point(item.at).distance_squared_to(player.global_position)
		if d < distance:
			distance = d
			nearest = item
	return nearest


func _update_route() -> void:
	var target := next_target()
	if target.is_empty():
		route.clear()
		return
	var target_position := CampaignDefinition.point(target.at)
	if _route_origin.is_finite() and _route_origin.distance_to(player.global_position) < 6.0 and _route_target == String(target.id) and _route_target_position.distance_to(target_position) < 4.0:
		return
	_route_origin = player.global_position
	_route_target = String(target.id)
	_route_target_position = target_position
	route = world.nav.find_path(player.global_position, CampaignDefinition.point(target.at))


func distance_to_target() -> float:
	var previous := player.global_position
	var distance := 0.0
	for at in route:
		distance += previous.distance_to(at)
		previous = at
	return distance


## Inventory is derived from completed story rewards, not just equipped slots:
## replacing a reward weapon can never make it disappear from the armory.
func available_weapons() -> Array[StringName]:
	var ids: Array[StringName] = [&"gladius"]
	for id in _meta.unlocked_targets(&"weapon"):
		if id not in ids:
			ids.append(id)
	for index in range(int(progress.mission)):
		var reward: Dictionary = definition.missions[index].get("reward", {})
		var id := StringName(String(reward.get("weapon", "")))
		if id != &"" and id not in ids:
			ids.append(id)
	return ids


func equip_secondary(id: StringName) -> bool:
	if GameRoot.get_current_state() != GameRoot.State.PAUSED or id not in available_weapons():
		return false
	if not player.get_weapon_manager().equip_by_id(id, 1, true):
		return false
	return save_progress(true)


func equip_third_skill(id: StringName) -> bool:
	if GameRoot.get_current_state() != GameRoot.State.PAUSED or not _meta.is_skill_unlocked_from_start(id):
		return false
	if not player.get_skill_controller().assign_skill_by_id(id, 2, true):
		return false
	return save_progress(true)


func stop() -> void:
	_stopped = true
	if encounters != null:
		encounters.stop()


func get_debug_snapshot() -> Dictionary:
	return {"mission": int(progress.mission), "checkpoint": String(progress.checkpoint),
		"completed": bool(progress.completed), "interacted": progress.interacted.duplicate(),
		"encounters": encounters.get_debug_snapshot()}
