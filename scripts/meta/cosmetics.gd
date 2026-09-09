class_name Cosmetics
extends RefCounted

## Cosmetic catalogue: turns the prestige-unlocked cosmetic IDs (previously just
## rows in the save file) into typed, applyable definitions. Each entry declares a
## `kind` (what system renders it) plus visual parameters. The PlayerCosmetics node
## and the arena decorator read this table so a cosmetic that unlocks in save
## actually attaches to the player / arena / HUD.
##
## Pure data + selection helpers — no tree access. Callers pass the player's
## unlocked-cosmetic list (SaveManager.get_unlocked_cosmetics()).

const KIND_TRAIL := &"trail"
const KIND_AURA := &"aura"
const KIND_BANNER := &"banner"
const KIND_TITLE := &"title"

## Definition per cosmetic id. `rank_order` breaks ties when several of one kind
## are unlocked (only the highest-order trail/aura is worn; every banner shows).
const CATALOG := {
	&"banner_survivor": {
		"kind": KIND_BANNER, "name": "Survivor's Banner",
		"color": Color(0.80, 0.20, 0.20), "rank_order": 1,
	},
	&"trail_ember": {
		"kind": KIND_TRAIL, "name": "Ember Trail",
		"color": Color(1.0, 0.55, 0.18), "rank_order": 2,
	},
	&"title_champion": {
		"kind": KIND_TITLE, "name": "Champion", "rank_order": 3,
		"color": Color(1.0, 0.85, 0.35),
	},
	&"aura_legend": {
		"kind": KIND_AURA, "name": "Legend's Aura",
		"color": Color(1.0, 0.85, 0.35), "rank_order": 5,
	},
	&"trail_frost": {
		"kind": KIND_TRAIL, "name": "Frost Trail",
		"color": Color(0.55, 0.85, 1.0), "rank_order": 7,
	},
	&"banner_last_stand": {
		"kind": KIND_BANNER, "name": "Last Stand Banner",
		"color": Color(0.35, 0.55, 1.0), "rank_order": 10,
	},
}


static func is_known(cosmetic_id: StringName) -> bool:
	return CATALOG.has(cosmetic_id)


static func definition(cosmetic_id: StringName) -> Dictionary:
	return CATALOG.get(cosmetic_id, {})


static func kind_of(cosmetic_id: StringName) -> StringName:
	return StringName(String(definition(cosmetic_id).get("kind", "")))


static func color_of(cosmetic_id: StringName) -> Color:
	return definition(cosmetic_id).get("color", Color.WHITE)


static func display_name(cosmetic_id: StringName) -> String:
	return String(definition(cosmetic_id).get("name", String(cosmetic_id)))


## Normalize a raw unlocked list (String or StringName) into known StringName ids.
static func _known_ids(unlocked: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for raw in unlocked:
		var id := StringName(String(raw))
		if is_known(id) and id not in out:
			out.append(id)
	return out


## The single trail the player wears: highest rank_order among unlocked trails
## (frost outranks ember). Returns &"" when none unlocked.
static func active_trail(unlocked: Array) -> StringName:
	return _highest_of_kind(unlocked, KIND_TRAIL)


## The aura the player wears (highest-order unlocked aura), or &"" when none.
static func active_aura(unlocked: Array) -> StringName:
	return _highest_of_kind(unlocked, KIND_AURA)


## The worn title cosmetic (highest-order unlocked title), or &"" when none.
static func active_title(unlocked: Array) -> StringName:
	return _highest_of_kind(unlocked, KIND_TITLE)


## Every unlocked banner id (all show on the arena walls), highest order last.
static func active_banners(unlocked: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _known_ids(unlocked):
		if kind_of(id) == KIND_BANNER:
			out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return int(definition(a).get("rank_order", 0)) < int(definition(b).get("rank_order", 0)))
	return out


static func _highest_of_kind(unlocked: Array, kind: StringName) -> StringName:
	var best: StringName = &""
	var best_order := -1
	for id in _known_ids(unlocked):
		if kind_of(id) != kind:
			continue
		var order := int(definition(id).get("rank_order", 0))
		if order > best_order:
			best_order = order
			best = id
	return best
