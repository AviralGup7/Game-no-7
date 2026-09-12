class_name CampaignDefinition
extends RefCounted
## Fixed authored station data. No generator, world roll, or player-entered key.

const PATH := "res://data/campaign/station_zero.json"
const WORLD_ID := "station_zero"
## Largest authored station the coarse 4 m navigation grid may hold. The real
## limit is the cell budget in ArenaNavGrid (40,960 cells), not the deck meshes.
const WORLD_EXTENT_LIMIT := 1024.0
var title := "STATION ZERO"
var bounds := Rect2(-432, -336, 864, 672)
var floors: Array[Rect2] = []
var sectors: Array[Dictionary] = []
var props: Array[Dictionary] = []
var encounters: Array[Dictionary] = []
var interactions: Array[Dictionary] = []
var missions: Array[Dictionary] = []
var max_active_enemies := 18
var max_visible_sectors := 3
var valid := false


func load_authored() -> bool:
	valid = false
	var raw := JsonHelpers.load_dict(PATH)
	if not source_is_valid(raw):
		return false
	title = String(raw.get("title", title))
	bounds = rect(raw.get("bounds", []))
	if not bounds.has_area() or bounds.size.x > WORLD_EXTENT_LIMIT or bounds.size.y > WORLD_EXTENT_LIMIT:
		return false
	floors.clear()
	for value in raw.get("floors", []):
		var area := rect(value)
		if not area.has_area() or not bounds.encloses(area):
			return false
		floors.append(area)
	sectors.assign(raw.get("sectors", []))
	props.assign(raw.get("props", []))
	encounters.assign(raw.get("encounters", []))
	interactions.assign(raw.get("interactions", []))
	missions.assign(raw.get("missions", []))
	max_active_enemies = clampi(int(raw.get("max_active_enemies", 18)), 1, 18)
	max_visible_sectors = clampi(int(raw.get("max_visible_sectors", 3)), 1, 3)
	valid = not floors.is_empty() and not sectors.is_empty() and not missions.is_empty()
	return valid


## APK data is trusted content, but a missing/partial file still fails closed
## rather than spawning fallback objects at (0,0,0). Offline validation additionally
## checks topology, physical clearance and referenced resource files.
static func source_is_valid(raw: Dictionary) -> bool:
	if raw.get("world_id", "") != WORLD_ID or raw.get("schema_version", 0) != 1:
		return false
	if raw.get("module_size", 0) != 8 or raw.get("navigation_cell", 0) != 4:
		return false
	if not raw.get("title") is String or not _numbers(raw.get("bounds"), 4):
		return false
	if not raw.get("floors") is Array or raw.floors.is_empty() or raw.floors.size() > 64:
		return false
	for area in raw.floors:
		if not _numbers(area, 4) or not rect(area).has_area():
			return false
		for number in area:
			if not is_equal_approx(roundf(float(number) / 8.0) * 8.0, float(number)):
				return false
	var fields := {"sectors": ["name", "rect", "checkpoint", "accent"],
		"props": ["sector", "kind", "at", "size"], "encounters": ["sector", "members", "activate_radius"],
		"interactions": ["sector", "kind", "name", "at", "credits"],
		"missions": ["sector", "kind", "title", "brief", "targets", "requires", "reward"]}
	for key in fields:
		if not _rows(raw.get(key), fields[key]):
			return false
	var sector_ids: Array[String] = []
	var encounter_ids: Array[String] = []
	var interaction_ids: Array[String] = []
	for row in raw.sectors:
		if not row.name is String or not _numbers(row.rect, 4) or not _numbers(row.checkpoint, 3):
			return false
		if not row.accent is String or not Color.html_is_valid(row.accent):
			return false
		if row.rect not in raw.floors:
			return false
		sector_ids.append(String(row.id))
	if "docks" not in sector_ids:
		return false
	for key in ["props", "encounters", "interactions", "missions"]:
		for row in raw[key]:
			if row.sector not in sector_ids:
				return false
	for row in raw.props:
		if not row.kind is String or not _numbers(row.at, 3) or not _numbers(row.size, 3):
			return false
		if row.size[0] <= 0 or row.size[1] <= 0 or row.size[2] <= 0:
			return false
	var spawns: Array[String] = []
	for row in raw.encounters:
		if not _rows(row.members, ["type", "at"]) or not _positive_number(row.activate_radius):
			return false
		for member in row.members:
			if not _numbers(member.at, 3) or member.id in spawns or member.type not in ["basic", "fast", "heavy", "ranged", "dasher", "warlord"]:
				return false
			spawns.append(String(member.id))
		encounter_ids.append(String(row.id))
	for row in raw.interactions:
		if not _numbers(row.at, 3) or not row.name is String or not _positive_number(row.credits):
			return false
		if row.kind not in ["terminal", "collect", "extraction", "cache"]:
			return false
		interaction_ids.append(String(row.id))
	var used_targets: Array = []
	for row in raw.missions:
		if not row.title is String or not row.brief is String or not row.targets is Array or not row.requires is Array or not row.reward is Dictionary:
			return false
		if row.targets.is_empty() or row.kind not in ["interact", "collect", "clear", "extract"]:
			return false
		for id in row.targets:
			if id not in interaction_ids or id in used_targets:
				return false
			used_targets.append(id)
		for id in row.requires:
			if id not in encounter_ids:
				return false
		for key in ["credits", "xp"]:
			if not _positive_number(row.reward.get(key, 0)):
				return false
		for key in ["upgrade", "weapon"]:
			if row.reward.has(key) and not row.reward[key] is String:
				return false
	for key in ["max_active_enemies", "max_visible_sectors"]:
		if not _positive_number(raw.get(key)):
			return false
	return true


static func _rows(value: Variant, required: Array) -> bool:
	if not value is Array or value.is_empty() or value.size() > 512:
		return false
	var ids: Array = []
	for row in value:
		if not row is Dictionary or not row.get("id") is String or not row.id.is_valid_identifier():
			return false
		if row.id in ids:
			return false
		ids.append(row.id)
		for key in required:
			if not row.has(key):
				return false
	return true


static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return false
	return true


static func _positive_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0


static func point(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.ZERO
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func rect(value: Variant) -> Rect2:
	if not value is Array or value.size() != 4:
		return Rect2()
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)):
			return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


func sector(id: String) -> Dictionary:
	for item in sectors:
		if String(item.get("id", "")) == id:
			return item
	for item in sectors:
		if String(item.id) == "docks":
			return item
	return {}


func sector_at(at: Vector3) -> Dictionary:
	for item in sectors:
		if rect(item.rect).has_point(Vector2(at.x, at.z)):
			return item
	return {}


func interaction(id: String) -> Dictionary:
	for item in interactions:
		if String(item.id) == id:
			return item
	return {}


func encounter(id: String) -> Dictionary:
	for item in encounters:
		if String(item.id) == id:
			return item
	return {}


func checkpoint(id: String) -> Transform3D:
	return Transform3D(Basis.IDENTITY, point(sector(id).get("checkpoint", [-216, 0.2, 44])))


## Locomotion clamp for the player and every streamed actor: a square that
## circumscribes the authored bounds, so enlarging the station can never leave
## a district outside the clamp (the decks' own perimeter rails still stop
## movement long before this limit).
func containment_half() -> float:
	if not bounds.has_area():
		return 0.0
	var result := 0.0
	for corner in [bounds.position, bounds.position + Vector2(bounds.size.x, 0.0),
			Vector2(bounds.position.x, bounds.position.y + bounds.size.y), bounds.end]:
		result = maxf(result, absf(corner.x))
		result = maxf(result, absf(corner.y))
	return result


func solid_boxes() -> Array[AABB]:
	var result: Array[AABB] = []
	for prop in props:
		var size := point(prop.size)
		result.append(AABB(point(prop.at) - size * 0.5, size))
	return result


func spawn_ids() -> Array[String]:
	var result: Array[String] = []
	for group in encounters:
		for member in group.members:
			result.append(String(member.id))
	return result
