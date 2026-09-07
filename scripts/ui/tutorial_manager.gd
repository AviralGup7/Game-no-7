class_name TutorialManager
extends Node

## First-run coach: ordered hint steps (move -> attack -> dodge -> skill ->
## upgrade -> survive) that complete off real game events. Steps show through
## an AnnouncementBanner-compatible callback; progress persists in the save so
## veterans never see it twice. Each step has an event trigger + a timeout
## fallback so the tutorial can never soft-lock the game.

signal tutorial_step_shown(step_id: StringName, text: String)
signal tutorial_finished()

const STEP_MOVE := &"move"
const STEP_ATTACK := &"attack"
const STEP_DODGE := &"dodge"
const STEP_SKILL := &"skill"
const STEP_UPGRADE := &"upgrade"
const STEP_SURVIVE := &"survive"
const STEP_ORDER := [STEP_MOVE, STEP_ATTACK, STEP_DODGE, STEP_SKILL, STEP_UPGRADE, STEP_SURVIVE]
const STEP_TIMEOUT := 25.0

var _active := false
var _step_index := 0
var _step_timer := 0.0
var _completed: Dictionary = {}
var _banner: AnnouncementBanner = null


func _ready() -> void:
	if EventBus != null:
		EventBus.run_started.connect(_on_run_started)


func bind_banner(banner: AnnouncementBanner) -> void:
	_banner = banner


## Has the player ever finished the tutorial (persisted flag)?
func is_tutorial_done() -> bool:
	if SaveManager != null and SaveManager.has_method("is_tutorial_completed"):
		return bool(SaveManager.call("is_tutorial_completed"))
	return _completed.get(&"finished", false)


func _on_run_started(_run_id: int, _seed: int) -> void:
	if is_tutorial_done():
		return
	_active = true
	_step_index = 0
	_step_timer = 0.0
	_wire_events()
	_show_current()


func _wire_events() -> void:
	if EventBus == null:
		return
	_connect_once(EventBus.upgrade_selected, _on_upgrade_selected)
	_connect_once(EventBus.skill_cast, _on_skill_cast)
	_connect_once(EventBus.wave_completed, _on_wave_completed)


func _connect_once(sig: Signal, fn: Callable) -> void:
	if not sig.is_connected(fn):
		sig.connect(fn)


func _show_current() -> void:
	if _step_index >= STEP_ORDER.size():
		_finish()
		return
	var id: StringName = STEP_ORDER[_step_index]
	_step_timer = 0.0
	tutorial_step_shown.emit(id, step_text(id))
	if _banner != null:
		_banner.announce(step_text(id), &"info")


static func step_text(step_id: StringName) -> String:
	match step_id:
		STEP_MOVE:
			return "Move with the left stick (WASD on keyboard)"
		STEP_ATTACK:
			return "Attack with the sword button (Space)"
		STEP_DODGE:
			return "Dodge through danger (Shift) — brief invulnerability!"
		STEP_SKILL:
			return "Unleash a skill (Q) when the bar lights up"
		STEP_UPGRADE:
			return "Clear waves to earn upgrades — pick one!"
		STEP_SURVIVE:
			return "Survive! Grab orbs, watch the minimap"
	return ""


func _process(delta: float) -> void:
	if not _active:
		return
	_step_timer += delta
	_poll_player_triggers()
	if _step_timer >= STEP_TIMEOUT:
		_complete_current()  # timeout fallback: never trap the player


func _poll_player_triggers() -> void:
	if GameRoot == null or GameRoot.get_active_player() == null:
		return
	var player := GameRoot.get_active_player()
	match _current_step():
		STEP_MOVE:
			if player.has_method("get_debug_snapshot"):
				pass  # movement tracked via velocity below
			if player is CharacterBody3D and (player as CharacterBody3D).velocity.length() > 1.0:
				_complete_current()
		STEP_ATTACK:
			pass  # completed via attack signal wiring below
		STEP_DODGE:
			pass


func _current_step() -> StringName:
	if _step_index < STEP_ORDER.size():
		return STEP_ORDER[_step_index]
	return &""


## Called by player-signal glue (attack_started / dodged) — wire from Main.
func notify_player_attacked() -> void:
	if _active and _current_step() == STEP_ATTACK:
		_complete_current()


func notify_player_dodged() -> void:
	if _active and _current_step() == STEP_DODGE:
		_complete_current()


func _on_skill_cast(_skill_id: StringName, _caster: Node) -> void:
	if _active and _current_step() == STEP_SKILL:
		_complete_current()


func _on_upgrade_selected(_upgrade_id: StringName) -> void:
	if _active and _current_step() == STEP_UPGRADE:
		_complete_current()


func _on_wave_completed(wave_number: int, _bonus: int) -> void:
	if _active and _current_step() == STEP_SURVIVE and wave_number >= 2:
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
	_completed[&"finished"] = true
	if SaveManager != null and SaveManager.has_method("set_tutorial_completed"):
		SaveManager.call("set_tutorial_completed", true)
	tutorial_finished.emit()


func skip_tutorial() -> void:
	if _active:
		_finish()


func is_active() -> bool:
	return _active


func current_step() -> StringName:
	return _current_step()
