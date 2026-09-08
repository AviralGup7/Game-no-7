extends Node
## Regression probe for soak-found bugs: (1) RunScorekeeper.award_bonus called a
## nonexistent CombatLog.log, so score_changed never fired; (2) first-stack
## upgrade keys errored in ProgressionComponent._accumulate. Boots the real game,
## starts a run, and exercises both paths. Engine script errors are NOT visible
## in-GDScript, so the runner greps the log for "SCRIPT ERROR" (expect zero).

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _total := 0
var _failures: Array[String] = []
var _score_emits := 0


func _check(name: String, passed: bool, extra: String = "") -> void:
	_total += 1
	if passed:
		print("  PASS: %s" % name)
	else:
		_failures.append(name)
		push_error("REGRESS FAIL: %s %s" % [name, extra])


func _run() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		push_error("REGRESS TIMEOUT")
		get_tree().quit(2))
	EventBus.score_changed.connect(func(_s: int, _d: int) -> void: _score_emits += 1)
	get_tree().change_scene_to_file(MAIN_SCENE)
	for i in range(300):
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Main":
			break
	for i in range(10):
		await get_tree().process_frame
	var ui: Node = get_tree().current_scene.get_node("UIRoot/UI")
	(find_button(ui.get("_menu"), "START RUN") as Button).pressed.emit()
	for i in range(4):
		await get_tree().process_frame
	var enter_btn := find_button(ui.get("_setup"), "ENTER ARENA")
	enter_btn.pressed.emit()
	var playing := false
	for i in range(600):
		await get_tree().process_frame
		if GameRoot.get_current_state() == GameRoot.State.PLAYING:
			playing = true
			break
	_check("run starts", playing)
	if not playing:
		_finish()
		return
	for i in range(30):
		await get_tree().physics_frame
	var player: Node = GameRoot.get_active_player()
	var prog: Node = player.get_node("ProgressionComponent")
	# Runtime content sanity: what does the registry actually hold for swift?
	var swift_cfg: Resource = ContentRegistry.get_upgrade(&"swift")
	print("  REGRESS swift stat_modifiers=%s" % str(swift_cfg.get("stat_modifiers")))
	# Bug 1: award_bonus must emit score_changed (pre-fix it errored first).
	var keeper: RefCounted = GameRoot.get("_score")
	var score_before: int = (keeper.get("_run") as RunState).score
	keeper.call("award_bonus", 50)
	await get_tree().process_frame
	var score_after: int = (keeper.get("_run") as RunState).score
	_check("bonus adds score", score_after - score_before == 50, "%d->%d" % [score_before, score_after])
	_check("bonus emits score_changed", _score_emits == 1, "emits=%d" % _score_emits)
	# Bug 2: first-stack fresh keys accumulate without error and with value.
	# Delta asserts: the shared save may carry meta ranks (move_speed +0.03,
	# max_health +20 observed), so compare before/after snapshots, and use
	# base 1.0 for the multiplicative family (base 0 yields 0 by design).
	var dr0 := float(prog.call("get_modifier_snapshot").get(&"damage_resistance_add", 0.0))
	_check("apply fortified", bool(player.call("apply_upgrade", &"fortified")))
	var dr1 := float(prog.call("get_modifier_snapshot").get(&"damage_resistance_add", 0.0))
	_check("resistance delta", is_equal_approx(dr1 - dr0, 0.1), str(dr1 - dr0))
	var kb0 := float(prog.call("get_modifier_snapshot").get(&"knockback_multiplier", 0.0))
	var ms0 := float(prog.call("get_modifier_snapshot").get(&"move_speed_multiplier", 0.0))
	_check("apply force", bool(player.call("apply_upgrade", &"force")))
	var kb1 := float(prog.call("get_modifier_snapshot").get(&"knockback_multiplier", 0.0))
	_check("knockback delta", is_equal_approx(kb1 - kb0, 0.15), str(kb1 - kb0))
	_check("apply swift", bool(player.call("apply_upgrade", &"swift")))
	var ms1 := float(prog.call("get_modifier_snapshot").get(&"move_speed_multiplier", 0.0))
	_check("movespeed delta", is_equal_approx(ms1 - ms0, 0.15), str(ms1 - ms0))
	print("  REGRESS modifiers=%s" % str(prog.call("get_modifier_snapshot")))
	_finish()


func find_button(root: Node, text: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node as Button
	return null


func _finish() -> void:
	print("REGRESS: %d checks, %d failed" % [_total, _failures.size()])
	for f in _failures:
		print("  FAILED: %s" % f)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _ready() -> void:
	_run()
