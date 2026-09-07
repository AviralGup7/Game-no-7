extends Node
## Autoload: GameRoot
## Owns global game state: the canonical state machine, the current RunState, pause
## overlay handling, content selection, and a narrow command interface consumed by UI
## controllers. It does not implement combat, AI, save or detailed UI logic; those
## live in their owning systems.

const State := {
	MAIN_MENU = &"main_menu",
	STARTING_RUN = &"starting_run",
	PLAYING = &"playing",
	WAVE_TRANSITION = &"wave_transition",
	UPGRADE_SELECTION = &"upgrade_selection",
	PAUSED = &"paused",
	GAME_OVER = &"game_over",
	LOADING = &"loading",
	ERROR = &"error",
}

## Legal direct transitions. Pause is an overlay handled separately (see _resume_state).
const LEGAL_TRANSITIONS := {
	State.MAIN_MENU: [State.STARTING_RUN, State.LOADING],
	State.STARTING_RUN: [State.PLAYING, State.ERROR, State.MAIN_MENU],
	State.PLAYING: [State.WAVE_TRANSITION, State.GAME_OVER, State.MAIN_MENU, State.ERROR],
	State.WAVE_TRANSITION: [State.PLAYING, State.UPGRADE_SELECTION, State.GAME_OVER, State.MAIN_MENU, State.ERROR],
	State.UPGRADE_SELECTION: [State.PLAYING, State.GAME_OVER, State.MAIN_MENU, State.ERROR],
	State.GAME_OVER: [State.STARTING_RUN, State.MAIN_MENU],
	State.LOADING: [State.STARTING_RUN, State.MAIN_MENU, State.PLAYING, State.ERROR],
	State.ERROR: [State.MAIN_MENU],
}

var _current_state: StringName = State.MAIN_MENU
var _resume_state: StringName = State.PLAYING
var _current_run := RunState.new()
var _best_score: int = 0
var _best_wave: int = 0
var _paused := false
var _active_player: Node = null

## Combo lifecycle tuning. Combos decay to 0 after this many seconds without a kill.
const COMBO_WINDOW_SECONDS: float = 4.0
var _last_kill_time: float = 0.0


func _ready() -> void:
	_best_score = SaveManager.get_best_score()
	_best_wave = SaveManager.get_best_wave()
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	_sync_player_control()
	EventBus.game_state_changed.connect(_on_game_state_changed)
	EventBus.diagnostic.connect(func(_m: String, _s: StringName) -> void: pass)
	if TestHarness != null:
		pass
	EventBus.report_info("GameRoot ready")


func _process(delta: float) -> void:
	if not _paused and _current_state in [State.PLAYING, State.WAVE_TRANSITION] and _current_run.player_alive:
		_current_run.elapsed_seconds += delta
		_tick_combo_expiry()


func get_current_state() -> StringName:
	return _current_state


func get_run() -> RunState:
	return _current_run


func get_best_score() -> int:
	return _best_score


func get_best_wave() -> int:
	return _best_wave


func get_active_player() -> Node:
	return _active_player


func set_active_player(node: Node) -> void:
	_active_player = node


func is_paused() -> bool:
	return _paused


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _current_state == State.PLAYING or _current_state == State.WAVE_TRANSITION:
			request_pause()
		elif _current_state == State.PAUSED:
			request_resume()
	if event.is_action_pressed("ui_cancel"):
		if _current_state == State.PAUSED:
			request_resume()


## ---------- Command interface (called by UI controllers / inputs) ----------

func request_play() -> void:
	if _current_state != State.MAIN_MENU and _current_state != State.GAME_OVER:
		return
	transition_to(State.STARTING_RUN)


func request_restart() -> void:
	transition_to(State.STARTING_RUN)


func request_main_menu() -> void:
	_paused = false
	transition_to(State.MAIN_MENU)


func request_pause() -> void:
	transition_to(State.PAUSED)


func request_resume() -> void:
	if _current_state == State.PAUSED:
		_set_paused(false)
		transition_to(_resume_state)


func request_game_over() -> void:
	if _current_state in [State.PLAYING, State.WAVE_TRANSITION, State.UPGRADE_SELECTION]:
		transition_to(State.GAME_OVER)


## ---------- State machine ----------

func transition_to(new_state: StringName) -> bool:
	if new_state == _current_state:
		return false
	if new_state == State.PAUSED:
		# Pause is only legal via request_pause() so we can remember the resume state.
		if not _can_pause_from(_current_state):
			EventBus.report_warning("Illegal pause transition from %s" % String(_current_state))
			return false
		_resume_state = _current_state
		_set_paused(true)
	else:
		var allowed: Array = LEGAL_TRANSITIONS.get(_current_state, [])
		if new_state not in allowed:
			EventBus.report_warning("Illegal state transition %s -> %s" % [String(_current_state), String(new_state)])
			return false
		if _current_state == State.PAUSED:
			_set_paused(false)
	return _apply_state(new_state)


func _can_pause_from(state: StringName) -> bool:
	return state in [State.PLAYING, State.WAVE_TRANSITION, State.UPGRADE_SELECTION]


func _apply_state(new_state: StringName) -> bool:
	var previous := _current_state
	_current_state = new_state
	EventBus.game_state_changed.emit(previous, new_state)
	_sync_player_control()
	_on_state_entered(previous, new_state)
	return true


## Keeps the player's input ownership aligned with the active state so modal panels
## (pause / upgrade / game-over) cannot leak stray movement or attacks.
func _sync_player_control() -> void:
	if _active_player == null or not is_instance_valid(_active_player):
		return
	if not _active_player.has_method("set_control_enabled"):
		return
	var enabled := _current_state in [State.PLAYING, State.WAVE_TRANSITION]
	_active_player.call("set_control_enabled", enabled)


func _on_state_entered(previous: StringName, current: StringName) -> void:
	match current:
		State.STARTING_RUN:
			_start_new_run()
		State.MAIN_MENU:
			EventBus.report_info("Entered main menu")
		State.GAME_OVER:
			_finalize_run()
		_:
			pass


func _set_paused(value: bool) -> void:
	if _paused == value:
		return
	_paused = value
	_current_run.paused = value
	get_tree().paused = value
	EventBus.pause_changed.emit(value)


## ---------- Run lifecycle ----------

func _start_new_run() -> void:
	var arena_id: StringName = ContentRegistry.get_selected_arena_id()
	_current_run.reset()
	_current_run.run_id = _next_run_id()
	_current_run.seed = randi()
	_current_run.arena_id = arena_id
	_current_run.elapsed_seconds = 0.0
	_last_kill_time = 0.0
	EventBus.report_info("Starting run %d in arena %s (seed %d)" % [_current_run.run_id, String(arena_id), _current_run.seed])
	# World assembly is delegated so each owning system can expand independently.
	_call_build_world(arena_id)
	EventBus.run_started.emit(_current_run.run_id, _current_run.seed)
	transition_to(State.PLAYING)


func _call_build_world(arena_id: StringName) -> void:
	# Locate the Main scene root (composition anchor). If not present (headless tests
	# that drive systems directly), building is skipped gracefully.
	var main := _get_main()
	if main == null:
		EventBus.report_warning("Main scene not present; skipping world build (headless/direct use)")
		return
	if main.has_method("build_world"):
		main.call("build_world", arena_id)


func _finalize_run() -> void:
	var summary := _current_run.summary()
	# Persist best score/wave and lifetime stats via the save/analytics systems.
	_best_score = maxi(_best_score, _current_run.score)
	_best_wave = maxi(_best_wave, _current_run.current_wave)
	SaveManager.record_run_completed(summary)
	RunAnalytics.record_run_end(summary)
	EventBus.run_ended.emit(_current_run.score, _current_run.current_wave, _best_score)
	_set_paused(false)


func _get_main() -> Node:
	if get_tree() == null or get_tree().current_scene == null:
		return null
	return get_tree().current_scene


func _next_run_id() -> int:
	return int(Time.get_ticks_msec()) + randi()


func _on_game_state_changed(_previous: StringName, _current: StringName) -> void:
	pass


## ---------- Wave integration (record + bonus, routed through GameRoot scoring) ----------

## Keep the run's wave number in sync with the WaveManager-driven waves.
func record_current_wave(wave_number: int) -> void:
	_current_run.current_wave = wave_number


func _on_wave_started(wave_number: int, _planned: int) -> void:
	record_current_wave(wave_number)


## Exactly-once completion bonus (WaveManager guards emission).
func _on_wave_completed(_wave_number: int, completion_bonus: int) -> void:
	award_wave_completion_bonus(completion_bonus)


func award_wave_completion_bonus(bonus: int) -> void:
	if not _current_run.player_alive or bonus <= 0:
		return
	_current_run.add_score(bonus)
	EventBus.score_changed.emit(_current_run.score, bonus)


## Clean inter-wave break through the canonical state machine.
func begin_wave_transition() -> void:
	if _current_state == State.PLAYING:
		transition_to(State.WAVE_TRANSITION)


func end_wave_transition() -> void:
	if _current_state == State.WAVE_TRANSITION:
		transition_to(State.PLAYING)


## ---------- Combat scoring (exactly-once per enemy_killed) ----------

func _on_enemy_killed(_enemy: Node, _archetype_id: StringName, score_value: int, currency_value: int) -> void:
	if not _current_run.player_alive:
		return
	_current_run.add_kill()
	var multiplier := _score_multiplier()
	# Raise combo by one then award score including the streak bonus; record the kill
	# time so the combo can expire after the window.
	_current_run.set_combo(_current_run.combo + 1)
	_last_kill_time = _current_run.elapsed_seconds
	var gained := Scoring.calculate_kill_score(score_value, _current_run.combo, multiplier)
	_current_run.add_score(gained)
	EventBus.score_changed.emit(_current_run.score, gained)
	var currency_reward := maxi(int(round(float(currency_value) * _currency_multiplier())), 0)
	_current_run.add_currency(currency_reward)
	EventBus.currency_changed.emit(_current_run.currency, currency_reward)
	EventBus.combo_changed.emit(_current_run.combo, _current_run.best_combo)


## Reset the combo to 0 when the kill window elapses without another kill. Emits only
## on an actual value change, and only while the run is still live (game-over-safe:
## _process no longer runs once the player is dead).
func _tick_combo_expiry() -> void:
	if _current_run.combo <= 0:
		return
	if _current_run.elapsed_seconds - _last_kill_time > COMBO_WINDOW_SECONDS:
		_current_run.set_combo(0)
		EventBus.combo_changed.emit(0, _current_run.best_combo)


func _score_multiplier() -> float:
	return 1.0 + _player_derived_stat(&"score_multiplier_add", 0.0)


func _currency_multiplier() -> float:
	return 1.0 + _player_derived_stat(&"currency_multiplier_add", 0.0)


func _player_derived_stat(key: StringName, base: float) -> float:
	var player := _active_player
	if player == null or not is_instance_valid(player):
		return base
	if not player.has_method("get_progression_snapshot"):
		return base
	var prog := player.get_node_or_null("ProgressionComponent")
	if prog == null or not prog.has_method("get_stat"):
		return base
	return float(prog.call("get_stat", key, base))


## ---------- Snapshots / diagnostics ----------

func get_debug_snapshot() -> Dictionary:
	return {
		"state": String(_current_state),
		"paused": _paused,
		"best_score": _best_score,
		"best_wave": _best_wave,
		"run": _current_run.summary(),
	}
