class_name TutorialManager
extends Node

## First-run coach: seven steps (move -> attack -> dodge -> winded -> skill ->
## upgrade -> survive). Completes off real game events. Timeout fallback per
## step so it never soft-locks. Only practiced completions persist the save flag.

signal tutorial_step_shown(step_id: StringName, text: String)
signal tutorial_finished()

const STEP_MOVE := &"move"
const STEP_ATTACK := &"attack"
const STEP_DODGE := &"dodge"
const STEP_WINDED := &"winded"
const STEP_SKILL := &"skill"
const STEP_UPGRADE := &"upgrade"
const STEP_SURVIVE := &"survive"
const STEP_ORDER := [STEP_MOVE, STEP_ATTACK, STEP_DODGE, STEP_WINDED, STEP_SKILL, STEP_UPGRADE, STEP_SURVIVE]
const STEP_TIMEOUT := 7.5

var _active := false
var _step_index := 0
var _step_timer := 0.0
var _completed: Dictionary = {}
var _banner: AnnouncementBanner = null
var _hud: GameHud = null
var _practiced_all := true
var _bus := EventBindings.new()
var _resume_guard := 0.0
var _did_dodge := false
var _bound_player: Player = null
var _coach_toasted_index := -1


func _ready() -> void:
	add_to_group("tutorial_manager")
	if EventBus != null:
		_bus.bind(EventBus.run_started, _on_run_started)
		_bus.bind(EventBus.run_ended, _on_run_ended)
		_bus.bind(EventBus.game_state_changed, _on_game_state_changed)
		_bus.bind(EventBus.skill_cast, _on_skill_cast)
		_bus.bind(EventBus.upgrade_selected, _on_upgrade_picked)
		_bus.bind(EventBus.wave_completed, _on_wave_survived)


func _exit_tree() -> void:
	_unbind_player()
	_bus.unbind_all()


func bind_banner(banner: AnnouncementBanner) -> void:
	_banner = banner


func bind_hud(hud: GameHud) -> void:
	_hud = hud


## Composition seam: Main hands the live player so attack/dodge complete off
## the typed Player signals instead of a second set of connects in Main.
func bind_player(player: Player) -> void:
	_bind_player_signals(player)


func is_tutorial_done() -> bool:
	if SaveManager != null:
		return SaveManager.is_tutorial_completed()
	return _completed.get(&"finished", false)


func _on_run_started(_run_id: int, _seed: int) -> void:
	if is_tutorial_done():
		_stop()
		return
	_active = true
	_practiced_all = true
	_did_dodge = false
	_step_index = 0
	_step_timer = 0.0
	_coach_toasted_index = -1
	_completed.clear()
	_show_current()
	_bind_player_signals()


func _bind_player_signals(player: Player = null) -> void:
	if player == null and GameRoot != null:
		player = GameRoot.get_active_player()
	if player == _bound_player:
		return
	_unbind_player()
	_bound_player = player
	if player == null:
		return
	_connect_once(player.attack_started, notify_player_attacked)
	_connect_once(player.dodged, notify_player_dodged)


func _unbind_player() -> void:
	if _bound_player != null and is_instance_valid(_bound_player):
		if _bound_player.attack_started.is_connected(notify_player_attacked):
			_bound_player.attack_started.disconnect(notify_player_attacked)
		if _bound_player.dodged.is_connected(notify_player_dodged):
			_bound_player.dodged.disconnect(notify_player_dodged)
	_bound_player = null


func _on_run_ended(_s: int, _w: int, _b: int) -> void:
	_stop()


func _on_game_state_changed(previous: StringName, current: StringName) -> void:
	if current == GameRoot.State.MAIN_MENU:
		_stop()
	if previous == GameRoot.State.PAUSED and current == GameRoot.State.PLAYING:
		_resume_guard = 0.35


func _show_current() -> void:
	if _step_index >= STEP_ORDER.size():
		_finish()
		return
	var id: StringName = STEP_ORDER[_step_index]
	_step_timer = 0.0
	_coach_toasted_index = -1
	tutorial_step_shown.emit(id, step_text(id))
	_present_coach("COACH %d / %d — %s" % [_step_index + 1, STEP_ORDER.size(), step_text(id)])


func _present_coach(message: String) -> void:
	if _banner != null:
		_banner.set_coach(message)


func _ensure_coach_visible() -> void:
	if not _active or _hud == null:
		return
	if _banner != null and _banner.is_visible_in_tree():
		return
	if _coach_toasted_index == _step_index:
		return
	if _step_index >= STEP_ORDER.size():
		return
	_coach_toasted_index = _step_index
	_hud.show_toast(
		"COACH %d / %d — %s" % [_step_index + 1, STEP_ORDER.size(), step_text(_current_step())],
		int(STEP_TIMEOUT * 1000.0)
	)


static func step_text(step_id: StringName) -> String:
	match step_id:
		STEP_MOVE:
			return "Move with the left stick (WASD on keyboard)"
		STEP_ATTACK:
			return "Tap ATTACK or %s. Face your target and chain hits." % UiCommands.binding(&"attack")
		STEP_DODGE:
			return "DODGE / %s avoids danger but costs stamina." % UiCommands.binding(&"dodge")
		STEP_WINDED:
			return "Stamina empties after dodges — wait for the bar to refill."
		STEP_SKILL:
			return "Tap a READY skill or %s. Level labels mean locked." % UiCommands.binding(&"skill_1")
		STEP_UPGRADE:
			return "Clear waves to earn upgrades — pick one!"
		STEP_SURVIVE:
			return "Survive! Grab orbs, watch the minimap"
	return ""


func _process(delta: float) -> void:
	if not _active:
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	if GameRoot.get_current_state() not in [GameRoot.State.PLAYING, GameRoot.State.WAVE_TRANSITION]:
		return
	if _resume_guard > 0.0:
		_resume_guard = maxf(_resume_guard - delta, 0.0)
		return
	_step_timer += delta
	_poll_player_triggers()
	_ensure_coach_visible()
	if _step_timer >= STEP_TIMEOUT:
		if _current_step() == STEP_WINDED and not _did_dodge and _step_timer < STEP_TIMEOUT * 2.0:
			return
		_practiced_all = false
		_complete_current()


func _poll_player_triggers() -> void:
	var player := GameRoot.get_active_player()
	if player == null or not is_instance_valid(player):
		return
	match _current_step():
		STEP_MOVE:
			if _resume_guard > 0.0:
				return
			var intent := player.get_move_intent()
			var axes := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
			var analog := axes.length() > 0.42
			var keys := axes.length() > 0.18 and axes.length() <= 0.42
			if analog or keys or intent > 0.4:
				_complete_current()
		STEP_ATTACK:
			_bind_player_signals(player)
		STEP_DODGE:
			_bind_player_signals(player)
		STEP_WINDED:
			# Dodge-empty only — walking drain must not skip the lesson.
			pass


func _connect_once(sig: Signal, fn: Callable) -> void:
	if not sig.is_connected(fn):
		sig.connect(fn)


func _current_step() -> StringName:
	if _step_index < STEP_ORDER.size():
		return STEP_ORDER[_step_index]
	return &""


func notify_player_attacked() -> void:
	if _active and _current_step() == STEP_ATTACK:
		_complete_current()


func notify_player_dodged() -> void:
	if not _active:
		return
	_did_dodge = true
	if _current_step() == STEP_DODGE:
		_complete_current()
	elif _current_step() == STEP_WINDED:
		var p := GameRoot.get_active_player()
		if p != null and p.get_stamina_fraction() <= 0.12:
			_complete_current()


func _on_skill_cast(_skill_id: StringName, caster: Node) -> void:
	if not _active or _current_step() != STEP_SKILL:
		return
	var player := GameRoot.get_active_player() if GameRoot != null else null
	if caster != null and player != null and caster != player:
		return
	_complete_current()


func _on_upgrade_picked(_upgrade_id: StringName) -> void:
	if _active and _current_step() == STEP_UPGRADE:
		_complete_current()


func _on_wave_survived(_wave_number: int, _completion_bonus: int) -> void:
	if _active and _current_step() == STEP_SURVIVE:
		_complete_current()


func _complete_current() -> void:
	var id := _current_step()
	_completed[id] = true
	if EventBus != null:
		EventBus.tutorial_step_completed.emit(id)
	_step_index += 1
	_show_current()


func _finish() -> void:
	_active = false
	_present_coach("")
	_unbind_player()
	_completed[&"finished"] = _practiced_all
	if _practiced_all and SaveManager != null:
		SaveManager.set_tutorial_completed(true)
	tutorial_finished.emit()


func skip_tutorial() -> void:
	if _active:
		_practiced_all = true
		_finish()


func is_active() -> bool:
	return _active


func current_step() -> StringName:
	return _current_step()


func _stop() -> void:
	_active = false
	_present_coach("")
	_unbind_player()


func replay_next_run() -> void:
	_stop()
	_did_dodge = false
	_completed.clear()
	_coach_toasted_index = -1
	if SaveManager != null:
		SaveManager.set_tutorial_completed(false)
