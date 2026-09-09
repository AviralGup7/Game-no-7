extends SceneTree
## Native import smoke test (run AFTER `godot --headless --path . --import`).
##   godot --headless --path . --script res://tests/validate_asset_imports.gd
## No gameplay/autoload dependencies; validates all downloaded resource types and
## the exact animation names in assets/catalog.json, not just source-file presence.

var _failures: Array[String] = []
var _checked := 0


func _initialize() -> void:
	var manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/manifest.json")
	)
	var catalog: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/catalog.json")
	)
	if not manifest is Dictionary or not catalog is Dictionary:
		push_error("Cannot read asset manifest/catalog")
		quit(1)
		return
	var derived: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/warden/build_report.json"))
	if not derived is Dictionary or (derived as Dictionary).get("files", []).is_empty():
		push_error("Cannot read the derived hero asset inventory")
		quit(1)
		return
	var entries: Array = manifest.get("files", []).duplicate()
	entries.append_array(derived.get("files", []))
	for entry in entries:
		var path := "res://%s" % entry["path"]
		var extension := path.get_extension()
		if extension not in ["glb", "gltf", "png", "ttf", "ogg", "wav"]:
			continue
		_checked += 1
		var imported := ResourceLoader.load(path)
		match extension:
			"glb", "gltf":
				_check_model(path, imported, catalog)
			"png":
				if not imported is Texture2D:
					_failures.append("Not an imported Texture2D: " + path)
			"ttf":
				if not imported is FontFile:
					_failures.append("Not an imported FontFile: " + path)
			"ogg", "wav":
				if not imported is AudioStream:
					_failures.append("Not an imported AudioStream: " + path)
				elif (imported as AudioStream).get_length() <= 0.0:
					_failures.append("Empty audio stream: " + path)
	_check_integrated_materials_and_pickups(catalog)
	_check_presentation_assets()
	if _checked == 0:
		_failures.append("No importable assets found in the manifest")
	print("Asset imports: %d resources, %d failures" % [_checked, _failures.size()])
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check_model(path: String, imported: Resource, catalog: Dictionary) -> void:
	if not imported is PackedScene:
		_failures.append("Not an imported PackedScene: " + path)
		return
	var instance := (imported as PackedScene).instantiate()
	if not instance is Node3D:
		_failures.append("Not a 3D model: " + path)
		if instance != null:
			instance.free()
		return
	var meshes := instance.find_children("*", "MeshInstance3D", true, false)
	if not instance is MeshInstance3D and meshes.is_empty():
		_failures.append("Imported model has no meshes: " + path)
	for character in catalog.get("characters", {}).values():
		if path != "res://%s" % character["model"]:
			continue
		var skeletons := instance.find_children("*", "Skeleton3D", true, false)
		if not instance is Skeleton3D and skeletons.is_empty():
			_failures.append("Character has no imported Skeleton3D: " + path)
		if character == catalog.get("characters", {}).get("player", {}):
			for missing in HeroRigContract.missing_requirements(instance):
				_failures.append("Hero rig contract: " + missing)
		var players := instance.find_children("*", "AnimationPlayer", true, false)
		if players.is_empty():
			_failures.append("Character has no AnimationPlayer: " + path)
			continue
		for clip in character["animations"].values():
			var found := false
			for player in players:
				if (player as AnimationPlayer).has_animation(StringName(clip)):
					found = true
			if not found:
				_failures.append("Missing imported clip %s in %s" % [clip, path])
	instance.free()


func _check_integrated_materials_and_pickups(catalog: Dictionary) -> void:
	for path in ["res://assets/materials/arena_stone.tres", "res://assets/materials/arena_wall_stone.tres"]:
		var material := load(path) as StandardMaterial3D
		if material == null or material.albedo_texture == null or material.normal_texture == null:
			_failures.append("Detailed material import failed: " + path)
	for id in catalog.get("gameplay_pickups", {}):
		var cfg := load("res://data/pickups/%s.tres" % id) as PickupConfig
		if cfg == null or cfg.visual_scene == null:
			_failures.append("Pickup has no imported visual: " + str(id))
			continue
		var visual := ModelVisual.create(cfg.visual_scene, cfg.visual_extent)
		if visual == null:
			_failures.append("Cannot fit pickup visual: " + str(id))
		else:
			visual.free()


## Verifies the Agent-4 presentation integration: every character/role model path
## mounts, the VFX sprite textures import, and each role exposes its idle clip.
func _check_presentation_assets() -> void:
	for role in CharacterVisuals.ROLE_MODELS:
		var cfg: Dictionary = CharacterVisuals.ROLE_MODELS[role]
		var path := String(cfg["path"])
		var scene := load(path)
		if not scene is PackedScene:
			_failures.append("Character role %s has no imported model: %s" % [String(role), path])
			continue
		var instance := (scene as PackedScene).instantiate()
		if not instance is Node3D:
			_failures.append("Character role %s model is not 3D: %s" % [String(role), path])
			if instance != null:
				instance.free()
			continue
		if (instance as Node3D).find_children("*", "MeshInstance3D", true, false).is_empty():
			_failures.append("Character role %s model has no meshes: %s" % [String(role), path])
		var players := (instance as Node3D).find_children("*", "AnimationPlayer", true, false)
		var idle_clip := String(cfg.get("idle", ""))
		var idle_found := idle_clip.is_empty()
		if not idle_found:
			for p in players:
				if (p as AnimationPlayer).has_animation(StringName(idle_clip)):
					idle_found = true
		if not idle_found:
			_failures.append("Character role %s missing idle clip '%s'" % [String(role), idle_clip])
		instance.free()
	# VFX sprite textures (used by the EffectDirector).
	for tex in ["res://assets/effects/kenney/circle_05.png", "res://assets/effects/kenney/spark_01.png"]:
		if not load(tex) is Texture2D:
			_failures.append("VFX sprite texture missing: " + tex)
