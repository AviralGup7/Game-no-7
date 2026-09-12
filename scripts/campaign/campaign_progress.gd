class_name CampaignProgress
extends RefCounted
## Save-only campaign state. Position is a named authored checkpoint, not a
## serialized Node, arbitrary transform or generated-world identifier.


static func defaults() -> Dictionary:
	return {"version": 1, "world_id": "station_zero", "started": false,
		"checkpoint": "docks", "mission": 0, "completed": false,
		"defeated": [], "interacted": [], "visited": [], "upgrades": {},
		"weapons": ["gladius"], "active_weapon": "gladius", "skills": [], "xp": 0}


static func normalize(value: Variant) -> Dictionary:
	var result := defaults()
	if not value is Dictionary or value.get("world_id", "station_zero") != "station_zero":
		return result
	for key in ["started", "completed"]:
		if value.get(key) is bool:
			result[key] = value[key]
	result.mission = _number(value.get("mission", 0), 64)
	result.xp = _number(value.get("xp", 0), 1000000)
	for key in ["checkpoint", "active_weapon"]:
		var text: Variant = value.get(key)
		if (text is String or text is StringName) and not String(text).is_empty() and String(text).length() <= 64:
			result[key] = String(text)
	for key in ["defeated", "interacted", "visited", "weapons", "skills"]:
		result[key] = _ids(value.get(key, []), 512 if key in ["defeated", "interacted"] else 32, key not in ["weapons", "skills"])
	if result.weapons.is_empty():
		result.weapons = ["gladius"]
	result.weapons = result.weapons.slice(0, 2)
	result.skills = result.skills.slice(0, 3)
	var upgrades: Variant = value.get("upgrades", {})
	if upgrades is Dictionary:
		for key in upgrades:
			if (key is String or key is StringName) and not String(key).is_empty() and String(key).length() <= 64:
				result.upgrades[String(key)] = _number(upgrades[key], 99)
	return result


## Reconcile disk identifiers against the current authored ledger. The contiguous
## completed objective IDs are authoritative, so an out-of-range/stale cursor
## cannot skip the story or hide an already-marked future console forever.
static func reconcile(value: Variant, definition: CampaignDefinition) -> Dictionary:
	var result := normalize(value)
	if definition == null or not definition.valid:
		return defaults()
	var members := definition.spawn_ids()
	var interactions: Array[String] = []
	var sectors: Array[String] = []
	for row in definition.interactions:
		interactions.append(String(row.id))
	for row in definition.sectors:
		sectors.append(String(row.id))
	result.defeated = result.defeated.filter(func(id: String) -> bool: return id in members)
	result.interacted = result.interacted.filter(func(id: String) -> bool: return id in interactions)
	result.visited = result.visited.filter(func(id: String) -> bool: return id in sectors)
	if result.checkpoint not in sectors:
		result.checkpoint = "docks"
	var cursor := 0
	for mission in definition.missions:
		var cleared := true
		for id in mission.requires:
			for member in definition.encounter(String(id)).members:
				cleared = cleared and member.id in result.defeated
		var done := cleared
		for id in mission.targets:
			done = done and id in result.interacted
		if not done:
			if not cleared:
				for id in mission.targets:
					result.interacted.erase(id)
			break
		cursor += 1
	for index in range(cursor + 1, definition.missions.size()):
		for id in definition.missions[index].targets:
			result.interacted.erase(id)
	result.mission = cursor
	result.completed = cursor == definition.missions.size()
	return result


static func _number(value: Variant, ceiling: int) -> int:
	if (value is int or value is float) and is_finite(float(value)):
		return int(clampf(float(value), 0, ceiling))
	return 0


static func _ids(value: Variant, limit: int, unique: bool = true) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if result.size() >= limit:
				break
			if (item is String or item is StringName) and not String(item).is_empty() and String(item).length() <= 64 and (not unique or String(item) not in result):
				result.append(String(item))
	return result
