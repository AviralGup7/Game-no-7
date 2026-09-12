extends RefCounted
## Native Godot checks for campaign schema, authored coordinates, collision/nav
## topology and silent XP restore. This suite is not an Android device benchmark.


static func suite() -> Array:
	var results: Array = []
	var definition := CampaignDefinition.new()
	_check(results, "campaign data loads without a generated world", definition.load_authored())
	if not definition.valid:
		return results
	_check(results, "fixed station has twelve districts and thirteen missions", definition.sectors.size() == 12 and definition.missions.size() == 13)
	_check(results, "all 96 authored spawn ids are unique", definition.spawn_ids().size() == 96)
	_schema(results)
	_reconcile(results, definition)
	_navigation(results, definition)
	_silent_xp(results)
	var raw := JsonHelpers.load_dict(CampaignDefinition.PATH)
	raw.encounters = "malformed"
	_check(results, "corrupt encounter collection fails closed", not CampaignDefinition.source_is_valid(raw))
	raw = JsonHelpers.load_dict(CampaignDefinition.PATH)
	raw.interactions[0].at = [NAN, 0, 0]
	_check(results, "non-finite campaign point fails closed", not CampaignDefinition.source_is_valid(raw))
	raw = JsonHelpers.load_dict(CampaignDefinition.PATH)
	raw.missions[0].targets = ["unknown_target"]
	_check(results, "unresolved campaign objective fails closed", not CampaignDefinition.source_is_valid(raw))
	return results


static func _check(results: Array, title: String, ok: bool) -> void:
	results.append({"name": title, "passed": ok, "why": ""})


static func _schema(results: Array) -> void:
	var migrated := SaveSchema.normalize_save({"schema_version": 7, "meta_wallet": 237,
		"meta_ranks": {"swift_boots": 2}, "settings": {"vibration_enabled": false, "text_scale": 1.4},
		"achievements": ["first_blood"], "best_score": 987, "best_wave": 12})
	_check(results, "schema 7 migrates additively to campaign schema 8", migrated.schema_version == 8 and not migrated.campaign.started)
	_check(results, "campaign migration preserves wallet and ranks", migrated.meta_wallet == 237 and migrated.meta_ranks.swift_boots == 2)
	_check(results, "campaign migration preserves Android accessibility", not migrated.settings.vibration_enabled and is_equal_approx(float(migrated.settings.text_scale), 1.4))
	_check(results, "legacy results are kept, not mistaken for campaign progress", migrated.best_score == 987 and migrated.best_wave == 12 and migrated.campaign.mission == 0)
	var raw := {"world_id": "station_zero", "started": true, "mission": 3, "checkpoint": "cargo",
		"defeated": ["guard", "guard", 4], "interacted": ["manifest_a"], "xp": 250,
		"weapons": [&"gladius", &"sentinel_spear"], "active_weapon": &"sentinel_spear",
		"skills": [&"seismic_slam", &"bladestorm", &"bladestorm"], "upgrades": {&"power": 1}}
	var normalized := CampaignProgress.normalize(raw)
	_check(results, "runtime StringName loadout is retained", normalized.weapons == ["gladius", "sentinel_spear"] and normalized.upgrades.power == 1)
	_check(results, "save does not collapse assigned skill slots", normalized.skills.size() == 3 and normalized.skills[2] == "bladestorm")
	_check(results, "defeated identities are deduplicated and typed", normalized.defeated == ["guard"])
	var parser := JSON.new()
	parser.parse(JSON.stringify(normalized))
	var round_trip := CampaignProgress.normalize(parser.data)
	_check(results, "JSON round trip preserves the campaign snapshot", round_trip == normalized)
	raw = {"mission": -8, "xp": NAN, "defeated": "bad", "skills": 17, "checkpoint": []}
	var bad := CampaignProgress.normalize(raw)
	_check(results, "malformed campaign values normalize safely", bad.mission == 0 and bad.xp == 0 and bad.defeated.is_empty() and bad.checkpoint == "docks")
	_check(results, "another world cannot corrupt the fixed campaign", not CampaignProgress.normalize({"world_id": "other", "started": true}).started)


static func _reconcile(results: Array, definition: CampaignDefinition) -> void:
	var raw := {"started": true, "mission": 64, "completed": true, "checkpoint": "missing",
		"interacted": ["unknown", "manifest_a"], "visited": ["docks", "missing"], "defeated": ["unknown"]}
	var result := CampaignProgress.reconcile(raw, definition)
	_check(results, "campaign cursor cannot skip uncompleted story", result.mission == 0 and not result.completed)
	_check(results, "unknown checkpoint returns safely to docks", result.checkpoint == "docks")
	_check(results, "unknown and future objective identifiers are dropped", result.interacted.is_empty() and result.defeated.is_empty() and result.visited == ["docks"])
	# Missions 01-03 (dock relay, transit power, hydroponics purge) are complete;
	# a manifest picked up out of order belongs to a later mission and is dropped.
	raw = {"started": true, "interacted": ["dock_link", "transit_power", "hydro_valve", "manifest_a"]}
	raw.defeated = []
	for encounter_id in ["transit_guards", "hydro_drones"]:
		for member in definition.encounter(encounter_id).members:
			raw.defeated.append(String(member.id))
	result = CampaignProgress.reconcile(raw, definition)
	_check(results, "completed ledger restores a stale mission cursor", result.mission == 3)
	_check(results, "partial current-mission collection is preserved", "hydro_valve" in result.interacted and "manifest_a" not in result.interacted)


static func _navigation(results: Array, definition: CampaignDefinition) -> void:
	var grid := ArenaNavGrid.new()
	grid.build_world(definition.bounds, definition.floors, definition.solid_boxes())
	_check(results, "campaign nav is coarse and rectangular", grid.width == 216 and grid.depth == 168 and grid.cell_size == 4)
	_check(results, "campaign nav uses its authored world origin", grid.to_cell(Vector3(-216, 0, 44)) == Vector2i(54, 95))
	_check(results, "void is not walkable", not grid.is_walkable(Vector3(-420, 0, 0)))
	_check(results, "out-of-world coordinates never wrap into the map", not grid.is_walkable(Vector3(10000, 0, 10000)))
	grid.rebuild_flow_field(definition.checkpoint("docks").origin)
	for sector in definition.sectors:
		var at := CampaignDefinition.point(sector.checkpoint)
		_check(results, "reachable checkpoint / " + String(sector.id), grid.is_walkable(at) and grid.flow_field_reachable(at))
	for item in definition.interactions:
		var at := CampaignDefinition.point(item.at)
		_check(results, "reachable interaction / " + String(item.id), grid.is_walkable(at) and grid.flow_field_reachable(at))
	for group in definition.encounters:
		for member in group.members:
			var at := CampaignDefinition.point(member.at)
			_check(results, "clear reachable spawn / " + String(member.id), grid.is_walkable(at) and grid.flow_field_reachable(at))
	var route := grid.find_path(definition.checkpoint("docks").origin, definition.checkpoint("reactor").origin)
	_check(results, "long campaign route exists without a teleport", route.size() > 1)
	_check(results, "floor instancing uses the authored module union", CampaignGeometry.floor_cells(definition.floors).size() == 3768)
	_check(results, "perimeter collision merges adjacent wall modules", CampaignGeometry.perimeter(definition.floors).size() < 260)
	grid.build(12, 0.5, [])
	_check(results, "legacy nav API still resets to a centred fine grid", grid.width == grid.depth and grid.cell_size == 0.5 and grid.to_cell(Vector3.ZERO) == Vector2i(24, 24))


static func _silent_xp(results: Array) -> void:
	var xp := ExperienceComponent.new()
	var boons: Array[int] = [0]
	xp.leveled_up.connect(func(_level: int) -> void: boons[0] += 1)
	xp.set_xp_multiplier(2.0)
	xp.restore_total(190)
	_check(results, "checkpoint XP restore bypasses multipliers", xp.total_xp_earned() == 190)
	_check(results, "checkpoint XP restore calculates the correct level", xp.get_level() == ExperienceComponent.level_for_total_xp(190))
	_check(results, "checkpoint XP restore does not replay level-up boons", boons[0] == 0)
	xp.free()
