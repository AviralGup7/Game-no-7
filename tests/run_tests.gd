extends SceneTree
## Headless test runner.
##   godot --headless --path . --import          (first run only)
##   godot --headless --path . --script res://tests/run_tests.gd
## Returns exit code 0 only when every unit + combat integration test passes.
##
## Pure unit suites run synchronously in _initialize(). Node-based integration tests
## are deferred to _process() because nodes added during _initialize() are not yet
## inside the live tree (global transforms return identity there), which would make
## positional/spatial assertions invalid.
##
## LOAD-ORDER CONTRACT — do not add game-class references to this file:
## Godot compiles the --script main loop BEFORE the project autoloads are
## registered as global identifiers (Main::start loads the script, then
## instantiates the autoloads). A compile-time dependency on any script that
## references an autoload (EventBus / GameRoot / AudioManager) would therefore
## fail with "Identifier not found". All integration-stage logic lives in
## res://tests/integration_stages.gd and is load()ed at runtime, when the
## autoloads exist. Keep this file free of game classes: no preloads, no
## class_name bases, no typed vars or .new() calls on project scripts.
## Pure suites: no Node3D, no tree access. Safe to run synchronously.
const UNIT_SUITES := [
	"res://tests/unit/test_save.gd",
	"res://tests/unit/test_combat.gd",
	"res://tests/unit/test_configs.gd",
	"res://tests/unit/test_scoring.gd",
	"res://tests/unit/test_waves.gd",
	"res://tests/unit/test_combo.gd",
	"res://tests/unit/test_upgrades.gd",
	"res://tests/unit/test_upgrade_selection.gd",
	"res://tests/unit/test_progression.gd",
	"res://tests/unit/test_rng_tables.gd",
	"res://tests/unit/test_status_skills.gd",
	"res://tests/unit/test_drops_elites.gd",
	"res://tests/unit/test_locomotion_nan.gd",
	"res://tests/unit/test_camera_arena_containment.gd",
	"res://tests/unit/test_camera_modules.gd",
	"res://tests/unit/test_safe_player_spawn.gd",
	"res://tests/unit/test_systems_completion.gd",
	"res://tests/unit/test_director_mutators.gd",
	"res://tests/unit/test_wave_mutators.gd",
	"res://tests/unit/test_meta_misc.gd",
	"res://tests/unit/test_planner_extended.gd",
	"res://tests/unit/test_extracted_modules.gd",
	"res://tests/unit/test_procedural_sfx.gd",
	"res://tests/unit/test_enemy_behaviors.gd",
	"res://tests/unit/test_nav_grid.gd",
	"res://tests/unit/test_enemy_brain.gd",
	"res://tests/unit/test_content_progression.gd",
	"res://tests/unit/test_presentation_scripts.gd",
	"res://tests/unit/test_game_modes.gd",
	"res://tests/unit/test_collision_layers.gd",
	"res://tests/unit/test_hazards.gd",
	"res://tests/unit/test_arena_world.gd",
	"res://tests/unit/test_performance_monitor.gd",
	"res://tests/unit/test_minimap_radar.gd",
	"res://tests/unit/test_audio_policy.gd",
	"res://tests/unit/test_error_report.gd",
	# No tree access: instantiates the (autoload-free) EventBusService script
	# directly and frees it, so this stays a pure suite.
	"res://tests/unit/test_event_bus_contract.gd",
]

## Node3D-based suites: these build Node3D fixtures and assert on positions.
## They MUST run in the deferred phase. Nodes created during _initialize() are not
## inside the live tree yet, so global_position returns identity — the fixtures set
## .position but production code (AreaDamage, MeleeResolver, ...) reads
## .global_position, so every target collapses onto the origin and spatial
## assertions fail for reasons that have nothing to do with the code under test.
const NODE_SUITES := [
	"res://tests/unit/test_model_visual.gd",
	"res://tests/unit/test_weapons.gd",
	"res://tests/unit/test_area_combat.gd",
	"res://tests/unit/test_character_visuals.gd",
	"res://tests/unit/test_hero_rig.gd",
	"res://tests/unit/test_arena_obstacles_node.gd",
	"res://tests/unit/test_decorator_collision.gd",
	"res://tests/unit/test_enemy_scene_inheritance.gd",
	"res://tests/unit/test_hazards_live.gd",
	"res://tests/unit/test_status_manager.gd",
]

const INTEGRATION_STAGES := "res://tests/integration_stages.gd"

var _failures: Array[String] = []
var _total := 0
var _integration_run := false


func _initialize() -> void:
	# SceneTree `--script` does not inject autoload *identifiers*, but the
	# project's real autoload scripts can still live under /root/<Name> so
	# gameplay code that looks them up by path (arena, StatusManager) compiles
	# and runs. These are the real EventBus/GameRoot scripts, not test fakes.
	_boot_project_autoloads()
	# Unit suites are pure (no nodes) -> safe to run immediately.
	_run_suites(UNIT_SUITES)


func _boot_project_autoloads() -> void:
	# Only EventBus: GameRoot/ContentRegistry _ready() pulls SaveManager and
	# would halt the hermetic suite on content validation. Gameplay scripts that
	# tests compile now look autoloads up by /root path and tolerate null.
	var entries: Array = [
		["EventBus", "res://scripts/core/event_bus.gd"],
	]
	for entry in entries:
		var node_name: String = entry[0]
		if root.get_node_or_null(node_name) != null:
			continue
		var script: GDScript = load(entry[1])
		if script == null:
			continue
		var node: Node = script.new() as Node
		if node == null:
			continue
		node.name = node_name
		root.add_child(node)



## Load each suite and fold its cases into the totals/failures.
func _run_suites(paths: Array) -> void:
	for path in paths:
		var script: GDScript = load(path)
		if script == null:
			_failures.append("Could not load suite: %s" % path)
			print("::error title=Suite load failure::%s did not compile/load" % path)
			_total += 1
			continue
		# `load()` of a script with a parse error returns the object anyway, marked unloadable — and
		# calling a broken script yields nothing, which used to mean a suite that could not compile
		# contributed zero cases and zero failures. The headless run reported 14 failures while a
		# registered suite that does not parse contributed none; that asymmetry is the hole.
		# (`GDScript.reload_failed` is the 3.x name; 4.x asks a Script whether it can instantiate.)
		if not script.can_instantiate():
			_failures.append("Suite failed to compile: %s" % path)
			print("::error title=Suite compile failure::%s has a parse error" % path)
			_total += 1
			continue
		var cases: Array = script.call("suite")
		if cases.is_empty():
			_failures.append("Suite ran no cases: %s" % path)
			_total += 1
			continue
		for c in cases:
			_total += 1
			if not bool(c.get("passed", false)):
				_failures.append("%s :: %s — %s" % [path.get_file(), str(c.get("name", "")), str(c.get("why", ""))])


func _process(_delta: float) -> bool:
	if _integration_run:
		return false
	_integration_run = true
	# Deferred to the first live frame so Node3D children are truly inside the tree.
	# Node3D-based unit suites must run here for the same reason as the integration
	# stages below: global_position is only meaningful once the tree is live.
	_run_suites(NODE_SUITES)
	var combat := _run_combat_integration()
	_total += combat.size()
	for c in combat:
		if not bool(c.get("passed", false)):
			_failures.append("combat :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])

	var encounter := _run_enemy_encounter_integration()
	_total += encounter.size()
	for c in encounter:
		if not bool(c.get("passed", false)):
			_failures.append("encounter :: %s — %s" % [str(c.get("name", "")), str(c.get("why", ""))])

	print("========================================")
	print("GDScript tests: %d total, %d failed" % [_total, _failures.size()])
	for f in _failures:
		print("  FAIL  " + f)
	# GitHub caps ::error annotations at 10 per step, which silently hides the
	# tail of a long failure list and makes it look like fixes "revealed" new
	# breakage. Emit the full list as ONE annotation (newlines escaped per the
	# workflow-command spec) so every failure is always visible.
	if not _failures.is_empty():
		var joined := "\n".join(_failures).replace("\n", "%0A")
		print("::error title=GDScript test failures (%d)::%s" % [_failures.size(), joined])
	print("========================================")
	# Also write the full report to a file: CI uploads *.log artifacts, so the
	# complete failure list is retrievable even when step output is truncated.
	var report := FileAccess.open("res://godot-test-report.log", FileAccess.WRITE)
	if report != null:
		report.store_string("GDScript tests: %d total, %d failed\n" % [_total, _failures.size()])
		for x in _failures:
			report.store_string("FAIL  " + x + "\n")
		report.close()
	quit(0 if _failures.is_empty() else 1)
	return false

## ---------- Integration stages (runtime-loaded; see load-order contract) ----------
##
## The combat stage and the enemy-encounter stage are the two entry points the
## deferred phase drives. The encounter stage internally runs the boss stage
## and the spawn-manager stage (they share the encounter's target fixture);
## their runner-level wrappers keep each stage individually addressable.
var _stages_script: GDScript = null


func _stages() -> GDScript:
	if _stages_script == null:
		_stages_script = load(INTEGRATION_STAGES)
	return _stages_script


func _run_combat_integration() -> Array:
	return _stages().call("_run_combat_integration", self)


func _run_enemy_encounter_integration() -> Array:
	return _stages().call("_run_enemy_encounter_integration", self)


func _run_boss_integration() -> Array:
	return _stages().call("_run_boss_integration", self, null)


func _run_spawn_manager_integration() -> Array:
	return _stages().call("_run_spawn_manager_integration", self)

