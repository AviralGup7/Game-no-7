class_name MusicManager
extends Node

## Adaptive music director: menu / calm / battle / boss / victory states with
## crossfades, plus a 4-layer intensity mixer driven by live combat heat
## (enemies active, player HP, combo). Missing cues degrade to silence with a
## diagnostic — music is never required for correctness. Sits beside (not
## inside) the AudioManager autoload so it can be unit-driven headless.

signal music_state_changed(old_state: StringName, new_state: StringName)

const STATE_SILENT := &"silent"
const STATE_MENU := &"menu"
const STATE_CALM := &"calm"
const STATE_BATTLE := &"battle"
const STATE_BOSS := &"boss"
const STATE_VICTORY := &"victory"

const CROSSFADE_SECONDS := 1.5
const HEAT_DECAY_PER_SECOND := 0.25
const HEAT_PER_KILL := 0.12
const HEAT_PER_DAMAGE := 0.02

var _state: StringName = STATE_SILENT
var _heat := 0.0
var _layer := 0
var _players: Array[AudioStreamPlayer] = []
var _active_index := 0
var _fading := 0.0
var _wired := false


func _ready() -> void:
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_players.append(p)


func get_state() -> StringName:
	return _state


func get_heat() -> float:
	return _heat


func get_layer() -> int:
	return _layer


## Start tracking run events (idempotent; call from Main on world build).
func begin_tracking() -> void:
	if _wired or EventBus == null:
		return
	_wired = true
	EventBus.run_started.connect(_on_run_started)
	EventBus.run_ended.connect(_on_run_ended)
	EventBus.enemy_killed.connect(_on_kill)
	EventBus.enemy_damaged.connect(_on_damaged)
	EventBus.boss_spawned.connect(_on_boss)
	EventBus.boss_slain.connect(_on_boss_slain)
	EventBus.game_state_changed.connect(_on_state_changed)


func request_state(state: StringName) -> void:
	if state == _state:
		return
	var old := _state
	_state = state
	_fading = CROSSFADE_SECONDS
	_active_index = (_active_index + 1) % _players.size()
	_play_cue_on_active()
	music_state_changed.emit(old, state)


func _cue_for_state() -> StringName:
	match _state:
		STATE_MENU:
			return &"music_menu"
		STATE_CALM:
			return _arena_cue(&"music_calm")
		STATE_BATTLE:
			return _arena_cue(&"music_battle")
		STATE_BOSS:
			return &"music_boss"
		STATE_VICTORY:
			return &"music_victory"
	return &""


## Arena configs may override the calm/battle bed via background_music_cue;
## unknown or missing ids fall back to the default cue for the state.
func _arena_cue(fallback: StringName) -> StringName:
	if GameRoot != null and ContentRegistry != null and AudioManager != null and GameRoot.has_method("get_run"):
		var run: Variant = GameRoot.call("get_run")
		if run != null:
			var arena_id: StringName = &""
			# Typed Run object is the normal case; dictionary fallback for tests.
			if run is Dictionary:
				arena_id = StringName(String((run as Dictionary).get("arena_id", &"")))
			elif "arena_id" in run:
				arena_id = (run as Variant).arena_id
			if arena_id != &"":
				var arena: ArenaConfig = ContentRegistry.get_arena(arena_id)
				if arena != null and arena.background_music_cue != &"" and AudioManager.has_cue(arena.background_music_cue):
					return arena.background_music_cue
	return fallback


func _play_cue_on_active() -> void:
	var cue := _cue_for_state()
	var player := _players[_active_index]
	if cue == &"" or AudioManager == null or not AudioManager.has_method("has_cue") or not bool(AudioManager.call("has_cue", cue)):
		player.stop()
		player.stream = null
		if EventBus != null and cue != &"":
			EventBus.report_info("Music cue missing, staying silent: %s" % String(cue))
		return
	if AudioManager.has_method("get_cue_stream"):
		player.stream = AudioManager.call("get_cue_stream", cue)
		player.play()


func _process(delta: float) -> void:
	_heat = maxf(_heat - HEAT_DECAY_PER_SECOND * delta, 0.0)
	_update_layer()
	if _fading > 0.0 and _players.size() == 2:
		_fading -= delta
		var t := clampf(1.0 - _fading / CROSSFADE_SECONDS, 0.0, 1.0)
		var incoming: AudioStreamPlayer = _players[_active_index]
		var outgoing: AudioStreamPlayer = _players[(_active_index + 1) % 2]
		incoming.volume_db = lerpf(-60.0, _layer_volume_db(), t)
		outgoing.volume_db = lerpf(_layer_volume_db(), -60.0, t)
		if _fading <= 0.0:
			outgoing.stop()
			incoming.volume_db = _layer_volume_db()


func _layer_volume_db() -> float:
	# Higher layers push slightly hotter.
	return -8.0 + float(_layer) * 1.5


func _update_layer() -> void:
	var target := 0
	if _state == STATE_BATTLE:
		target = 1 + int(_heat * 2.0)
	elif _state == STATE_BOSS:
		target = 3
	elif _state == STATE_CALM:
		target = 0
	_layer = clampi(target, 0, 3)


func add_heat(amount: float) -> void:
	_heat = clampf(_heat + amount, 0.0, 1.5)
	if _state == STATE_CALM and _heat > 0.5:
		request_state(STATE_BATTLE)
	elif _state == STATE_BATTLE and _heat <= 0.05:
		request_state(STATE_CALM)


func _on_run_started(_run_id: int, _seed: int) -> void:
	request_state(STATE_CALM)


func _on_run_ended(_score: int, _wave: int, _best: int) -> void:
	request_state(STATE_SILENT)


func _on_kill(_enemy: Node, _archetype: StringName, _score: int, _currency: int) -> void:
	add_heat(HEAT_PER_KILL)


func _on_damaged(_enemy: Node, _result: DamageResult) -> void:
	add_heat(HEAT_PER_DAMAGE)


func _on_boss(_boss: Node, _boss_id: StringName) -> void:
	request_state(STATE_BOSS)


func _on_boss_slain(_boss_id: StringName) -> void:
	# The fight goes on (adds remain); drop back to battle instead of silence.
	if _state == STATE_BOSS:
		request_state(STATE_BATTLE)


func _on_state_changed(_previous: StringName, current: StringName) -> void:
	if current == &"main_menu":
		request_state(STATE_MENU)
	elif current == &"game_over":
		request_state(STATE_VICTORY)


func get_debug_snapshot() -> Dictionary:
	return {"state": String(_state), "heat": _heat, "layer": _layer}

## Hardened: clamp music crossfade to prevent audio pop.
func _validated_fade(t: float) -> float:
	if not is_finite(t) or t < 0.0:
		return 0.0
	return clampf(t, 0.0, 10.0)

