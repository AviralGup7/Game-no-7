class_name GameRootService
extends Node
## Autoload: GameRoot
## Owns global game state: the canonical state machine, the current RunState, pause
## overlay handling, content selection, and a narrow command interface consumed by UI
## controllers. Scoring/combo/currency math lives in RunScorekeeper and the upgrade
## selection flow in UpgradeService; combat, AI, save and detailed UI logic live in
## their owning systems.

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
	State.PLAYING: [State.WAVE_TRANSITION, State.GAME_OVER, State.STARTING_RUN, State.MAIN_MENU, State.ERROR],
	State.WAVE_TRANSITION: [State.PLAYING, State.UPGRADE_SELECTION, State.GAME_OVER, State.STARTING_RUN, State.MAIN_MENU, State.ERROR],
	State.UPGRADE_SELECTION: [State.PLAYING, State.GAME_OVER, State.STARTING_RUN, State.MAIN_MENU, State.ERROR],
	State.PAUSED: [State.PLAYING, State.WAVE_TRANSITION, State.UPGRADE_SELECTION, State.STARTING_RUN, State.MAIN_MENU, State.ERROR],
	State.GAME_OVER: [State.STARTING_RUN, State.MAIN_MENU],
	State.LOADING: [State.STARTING_RUN, State.MAIN_MENU, State.PLAYING, State.ERROR],
	State.ERROR: [State.MAIN_MENU],
}

var _current_state: StringName = State.MAIN_MENU
var _resume_state: StringName = State.PLAYING
var _current_run := RunState.new()
var _score := RunScorekeeper.new()
var _best_score: int = 0
var _best_wave: int = 0
var _paused := false
var _active_player: Player = null
## World-build seam (registered by Main / test harnesses; see _call_build_world).
var _world_builder: Callable = Callable()
var _daily: Dictionary = {}  # DailyChallenge card for daily runs, {} for standard.
var _pending_mode: StringName = GameMode.MODE_STANDARD
var _prestige_rank: int = 0


func _ready() -> void:
	# GameRoot must outlive pause: the pause toggle + state machine run while
	# the tree is paused (elapsed time/combo already gate on _paused).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_best_score = SaveManager.get_best_score()
	_best_wave = SaveManager.get_best_wave()
	_prestige_rank = SaveManager.get_prestige_rank()
	_score.bind(_current_run, _player_derived_stat)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.objective_resolved.connect(_on_objective_resolved)
	_sync_player_control()
	EventBus.diagnostic.connect(func(_m: String, _s: StringName) -> void: pass)
	EventBus.report_info("GameRoot ready")


func _process(delta: float) -> void:
	if not _paused and _current_state in [State.PLAYING, State.WAVE_TRANSITION] and _current_run.player_alive:
		_current_run.elapsed_seconds += delta
		_score.tick_combo()
		# Survival mode: victory on the clock, not on a wave cap.
		if GameMode.is_survival_victory(_current_run.mode_id, _current_run.elapsed_seconds):
			_declare_victory()


func get_current_state() -> StringName:
	return _current_state


func get_run() -> RunState:
	return _current_run


# NOTE: no get_best_score()/get_best_wave() accessors here on purpose. The save
# store (SaveManager) is the single source of truth for persisted bests — the
# startup-stability fix routed menu_panel, run_summary_panel and the UI test
# runner directly at it because GameRoot only mirrored them at _ready. The
# _best_score/_best_wave mirrors below stay internal: they exist to report the
# run's best through the run_ended fan-out and the debug snapshot, not as a
# public read path.


func get_active_player() -> Player:
	return _active_player


func set_active_player(player: Player) -> void:
	_active_player = player


func is_paused() -> bool:
	return _paused


func _unhandled_input(event: InputEvent) -> void:
	# "pause" and "ui_cancel" both default to Escape, so they must be handled as one
	# toggle: two independent `if`s would pause and immediately resume on one press.
	if not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	# Keyboard pause path: buttons already click through UiFactory, so only the
	# key-driven toggle needs its tick here (avoids a double tick on buttons).
	if _current_state == State.PAUSED:
		request_resume()
		_click(&"ui_confirm")
	elif _can_pause_from(_current_state):
		request_pause()
		_click(&"ui_back")
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


## ---------- Command interface (called by UI controllers / inputs) ----------

func request_play() -> void:
	if _current_state != State.MAIN_MENU and _current_state != State.GAME_OVER:
		return
	_daily = {}
	if _pending_mode == &"":
		_pending_mode = GameMode.MODE_STANDARD
	transition_to(State.STARTING_RUN)


## Start a run in a specific game mode (standard / boss rush / survival / ...).
func request_play_mode(mode_id: StringName) -> void:
	if _current_state != State.MAIN_MENU and _current_state != State.GAME_OVER:
		return
	_daily = {}
	_pending_mode = GameMode.validated(mode_id)
	transition_to(State.STARTING_RUN)


## Start today's seeded daily challenge (shared seed, fixed mutators + weapon).
func start_daily_run() -> void:
	if _current_state != State.MAIN_MENU and _current_state != State.GAME_OVER:
		return
	if DailyChallenge == null:
		return
	_daily = DailyChallenge.challenge_for_today()
	_pending_mode = GameMode.MODE_STANDARD
	transition_to(State.STARTING_RUN)


func is_daily_run() -> bool:
	return not _daily.is_empty()


func get_daily_challenge() -> Dictionary:
	return _daily


func set_pending_mode(mode_id: StringName) -> void:
	_pending_mode = GameMode.validated(mode_id)


func get_pending_mode() -> StringName:
	return _pending_mode


func get_run_mode() -> StringName:
	return _current_run.mode_id if _current_run != null else GameMode.MODE_STANDARD


func get_prestige_rank() -> int:
	return _prestige_rank


func set_prestige_rank(rank: int) -> void:
	_prestige_rank = Prestige.clamp_rank(rank)


## Starter weapon for the current run (mode fixed loadout > daily > gladius).
func get_daily_weapon() -> StringName:
	var mode_weapon := GameMode.fixed_weapon(_pending_mode if _current_run == null else _current_run.mode_id)
	if mode_weapon != &"":
		return mode_weapon
	if _daily.is_empty():
		return &"gladius"
	return StringName(String(_daily.get("weapon", "gladius")))


## Called by WaveManager when a mode's win condition is met (wave cap or survival clock).
func declare_victory() -> void:
	_declare_victory()


func _declare_victory() -> void:
	if _current_run.victory:
		return
	if _current_state not in [State.PLAYING, State.WAVE_TRANSITION, State.UPGRADE_SELECTION]:
		return
	_current_run.victory = true
	_current_run.completed_objectives.append(&"mode_victory")
	Narrator.announce_victory(_current_run.mode_id)
	# Survival/time modes earn a flat completion bonus scaled by mode score mult
	# (prestige-tier scaled for Challenge).
	var bonus := int(500.0 * GameMode.score_multiplier_for(_current_run.mode_id, _prestige_rank))
	if bonus > 0:
		_score.award_bonus(bonus)
	transition_to(State.GAME_OVER)


## Objective director (Hold the Line / Relic Hunt) resolved its win/lose condition.
## Success routes through the shared victory path; failure ends the run in a loss.
func _on_objective_resolved(_mode_id: StringName, success: bool) -> void:
	if _current_state not in [State.PLAYING, State.WAVE_TRANSITION, State.UPGRADE_SELECTION]:
		return
	if success:
		_declare_victory()
	else:
		_current_run.player_alive = false
		request_game_over()


func request_restart() -> void:
	# Keep the same mode (and daily card) so "Retry" replays what the player just ran.
	if _current_run != null and _current_run.mode_id != &"":
		_pending_mode = GameMode.validated(_current_run.mode_id)
	# Restart must succeed from any gameplay state. If direct transition is illegal
	# (e.g. future states), fall back through MAIN_MENU so the canonical path still runs.
	if not transition_to(State.STARTING_RUN):
		# Ensure pause does not survive the restart.
		_paused = false
		if get_tree() != null:
			get_tree().paused = false
		_current_run.paused = false
		# Force reset via MAIN_MENU when direct edge is missing.
		if _current_state != State.MAIN_MENU:
			_apply_state(State.MAIN_MENU)
		transition_to(State.STARTING_RUN)


func request_main_menu() -> void:
	# Must go through _set_paused so SceneTree.paused / RunState.paused are cleared
	# too. Writing _paused directly leaves the tree paused forever, and the guard in
	# _set_paused ("if _paused == value: return") would then swallow every later
	# unpause, so the next run starts frozen with a live UI.
	_set_paused(false)
	transition_to(State.MAIN_MENU)


func request_pause() -> void:
	transition_to(State.PAUSED)


func request_resume() -> void:
	if _current_state == State.PAUSED:
		_set_paused(false)
		transition_to(_resume_state)


## UI tick for pause/resume. AudioManager is a project autoload like GameRoot
## itself: whenever this code runs, the audio singleton exists — no theater guards.
func _click(cue_id: StringName) -> void:
	AudioManager.play_sfx(cue_id, -10.0)


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
	var enabled := _current_state in [State.PLAYING, State.WAVE_TRANSITION]
	_active_player.set_control_enabled(enabled)


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
	var tree := get_tree()
	if tree != null:
		tree.paused = value
	EventBus.pause_changed.emit(value)


## ---------- Run lifecycle ----------

func _start_new_run() -> void:
	var arena_id: StringName = ContentRegistry.get_selected_arena_id()
	_current_run.reset()
	_current_run.run_id = _next_run_id()
	_current_run.seed = randi()
	if _current_run.seed == 0:
		_current_run.seed = 1
	if not _daily.is_empty():
		var ds := int(_daily.get("seed", _current_run.seed))
		_current_run.seed = ds if ds != 0 else 1
	_current_run.arena_id = arena_id
	_current_run.mode_id = GameMode.validated(_pending_mode)
	_current_run.elapsed_seconds = 0.0
	_score.reset_run(_current_run)
	EventBus.report_info("Starting run %d mode=%s arena=%s seed=%d%s" % [
		_current_run.run_id, String(_current_run.mode_id), String(arena_id), _current_run.seed,
		(" [" + String(_daily.get("label", "Daily")) + "]") if not _daily.is_empty() else ""])
	# World assembly is delegated so each owning system can expand independently.
	_call_build_world(arena_id)
	if _world_builder.is_valid() and _active_player == null:
		EventBus.report_error("Failed to build world or spawn player for arena %s" % String(arena_id))
		transition_to(State.ERROR)
		return
	EventBus.run_started.emit(_current_run.run_id, _current_run.seed)
	Narrator.announce_run_start(_current_run.mode_id, arena_id)
	if not _daily.is_empty():
		var muts: Array = _daily.get("mutators", [])
		var names: PackedStringArray = PackedStringArray()
		for m in muts:
			names.append(WaveMutators.display_name(StringName(String(m))))
		EventBus.announcement.emit(&"daily", "%s — mutators: %s" % [
			String(_daily.get("label", "Daily")), ", ".join(names)], &"warning")
	elif _current_run.mode_id != GameMode.MODE_STANDARD:
		var mode_title := GameMode.display_name(_current_run.mode_id)
		# Challenge announces its live prestige tier so the escalation is legible.
		if GameMode.scales_with_prestige(_current_run.mode_id):
			mode_title = "%s — %s" % [mode_title, GameMode.challenge_tier_label(_current_run.mode_id, _prestige_rank)]
		EventBus.announcement.emit(&"mode", "%s — %s" % [
			mode_title, GameMode.blurb(_current_run.mode_id)], &"info")
	transition_to(State.PLAYING)


func _call_build_world(arena_id: StringName) -> void:
	# World-build seam: Main registers itself as the builder at startup; headless
	# UI harnesses register their own. A typed Callable reference (NOT string
	# dispatch) keeps the contract explicit — see docs/ARCHITECTURE.md.
	if _world_builder.is_valid():
		_world_builder.call(arena_id)
		return
	EventBus.report_warning("No world builder registered; skipping world build (headless/direct use)")


func _finalize_run() -> void:
	_sync_run_build_mirror()
	var summary := _current_run.summary()
	# Persist best score/wave and lifetime stats via the save/analytics systems.
	_best_score = maxi(_best_score, _current_run.score)
	_best_wave = maxi(_best_wave, _current_run.current_wave)
	SaveManager.record_run_completed(summary)
	# The save store owns the authoritative bests (it loads from disk before
	# GameRoot in the autoload order — see project.godot note); adopt them after
	# recording so the emitted best is never a stale startup cache.
	_best_score = maxi(_best_score, SaveManager.get_best_score())
	_best_wave = maxi(_best_wave, SaveManager.get_best_wave())
	RunAnalytics.record_run_end(summary)
	EventBus.run_ended.emit(_current_run.score, _current_run.current_wave, _best_score)
	# The run-end sting fires exactly once with the run_ended fan-out (the music
	# director handles the bed separately via its own run_ended/state hooks).
	_click(&"game_over")
	_set_paused(false)


## Register the run-world builder (Main at runtime; a test harness headlessly).
func set_world_builder(builder: Callable) -> void:
	_world_builder = builder


func _next_run_id() -> int:
	return int(Time.get_ticks_msec()) + randi()


## ---------- Wave integration (record + bonus, routed through GameRoot scoring) ----------

## Keep the run's wave number in sync with the WaveManager-driven waves.
func record_current_wave(wave_number: int) -> void:
	_current_run.current_wave = maxi(wave_number, 0)
	if _active_player != null and is_instance_valid(_active_player):
		var player := _active_player
		player.get_progression_component().set_current_wave(maxi(wave_number, 1))
		player.get_weapon_manager().set_current_wave(maxi(wave_number, 1))
		var skills := player.get_skill_controller()
		if skills != null:
			skills.set_current_wave(maxi(wave_number, 1))
			skills.unlock_available()


func _on_wave_started(wave_number: int, _planned: int) -> void:
	record_current_wave(wave_number)


## Exactly-once completion bonus (WaveManager guards emission).
func _on_wave_completed(_wave_number: int, completion_bonus: int) -> void:
	award_wave_completion_bonus(completion_bonus)


func award_wave_completion_bonus(bonus: int) -> void:
	_score.award_bonus(bonus)


## Clean inter-wave break through the canonical state machine.
func begin_wave_transition() -> void:
	if _current_state == State.PLAYING:
		transition_to(State.WAVE_TRANSITION)


func end_wave_transition() -> void:
	if _current_state == State.WAVE_TRANSITION:
		transition_to(State.PLAYING)


## ---------- Progression commands (data-driven, deterministic) ----------

## The WaveManager calls this when a completed wave requests an upgrade. The choice
## set comes from UpgradeService (run seed + wave + current stacks); this method only
## gates on state/liveness, stores the offer, routes PLAYING -> WAVE_TRANSITION ->
## UPGRADE_SELECTION, and announces it. Returns false (state unchanged) when no
## eligible upgrade exists — the caller then continues to the next wave.
func present_upgrade_selection_for_wave(wave_number: int) -> bool:
	if _current_state != State.PLAYING:
		EventBus.report_warning("present_upgrade_selection_for_wave requires PLAYING state")
		return false
	if not _current_run.player_alive:
		return false
	var chosen := UpgradeService.choose_for_wave(_current_run, _active_player, wave_number)
	if chosen.is_empty():
		return false
	_current_run.upgrade_choices = chosen
	# Route through the legal state path PLAYING -> WAVE_TRANSITION -> UPGRADE_SELECTION.
	transition_to(State.WAVE_TRANSITION)
	transition_to(State.UPGRADE_SELECTION)
	EventBus.upgrade_choices_presented.emit(_current_run.upgrade_choices)
	EventBus.report_info("Upgrade choices presented (wave %d): %s" % [wave_number, str(_current_run.upgrade_choices)])
	return true


## Validate + apply a player-selected upgrade. Only an id currently offered (and still
## legal given the live progression state) can be chosen; arbitrary ids are rejected.
## On success it emits upgrade_selected and resumes into PLAYING so the WaveManager
## can start the next wave.
func request_upgrade_selection(upgrade_id: StringName) -> bool:
	if _current_state != State.UPGRADE_SELECTION:
		EventBus.report_warning("request_upgrade_selection requires UPGRADE_SELECTION state")
		return false
	if not UpgradeService.validate_selection(_current_run, _active_player, upgrade_id).is_empty():
		return false
	if not UpgradeService.apply_selection(_current_run, _active_player, upgrade_id):
		return false
	_sync_run_build_mirror()
	EventBus.upgrade_selected.emit(upgrade_id)
	EventBus.report_info("Upgrade selected: %s" % String(upgrade_id))
	# Back into PLAYING; WaveManager observes the state to launch the next wave.
	transition_to(State.PLAYING)
	return true


## ---------- Combat scoring (exactly-once per enemy_killed) ----------

func _on_enemy_killed(_enemy: Node, archetype_id: StringName, score_value: int, currency_value: int) -> void:
	_score.record_kill(score_value, currency_value, archetype_id)


func get_combat_log() -> CombatLog:
	return _score.get_combat_log()


## Player progression lookup feeding the scorekeeper's multipliers. Tolerant when no
## live player/progression exists (multipliers fall back to their base).
func _player_derived_stat(key: StringName, base: float) -> float:
	var player := _active_player
	if player == null or not is_instance_valid(player):
		return base
	var prog := player.get_progression_component()
	if prog == null:
		return base
	return prog.get_stat(key, base)


## ---------- Snapshots / diagnostics ----------

func _sync_run_build_mirror() -> void:
	if _active_player == null or not is_instance_valid(_active_player):
		return
	_current_run.set_build_snapshot(_active_player.get_build_snapshot())


func get_debug_snapshot() -> Dictionary:
	return {
		"state": String(_current_state),
		"paused": _paused,
		"best_score": _best_score,
		"best_wave": _best_wave,
		"run": _current_run.summary(),
	}

