class_name CampaignProgressState
extends RefCounted
## The director-owned mutable campaign save state.
var version: int = 1 ## Save key: version.
var world_id: String = "station_zero" ## Save key: world_id.
var started: bool = false ## Save key: started.
var checkpoint: String = "docks" ## Save key: checkpoint.
var mission: int = 0 ## Save key: mission.
var completed: bool = false ## Save key: completed.
var defeated: Array[String] = [] ## Save key: defeated.
var interacted: Array[String] = [] ## Save key: interacted.
var visited: Array[String] = [] ## Save key: visited.
var upgrades: Dictionary = {} ## Save key: upgrades.
var weapons: Array[String] = ["gladius"] ## Save key: weapons.
var active_weapon: String = "gladius" ## Save key: active_weapon.
var skills: Array[String] = [] ## Save key: skills.
var xp: int = 0 ## Save key: xp.

func to_dict() -> Dictionary:
	return {"version": version, "world_id": world_id, "started": started,
		"checkpoint": checkpoint, "mission": mission, "completed": completed,
		"defeated": defeated.duplicate(), "interacted": interacted.duplicate(),
		"visited": visited.duplicate(), "upgrades": upgrades.duplicate(true),
		"weapons": weapons.duplicate(), "active_weapon": active_weapon,
		"skills": skills.duplicate(), "xp": xp}
