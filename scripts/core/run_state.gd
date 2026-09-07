class_name RunState
extends RefCounted

## Runtime-only state for a single run. Never written directly to disk; the only
## serialization path is summary() / lifetime-export which omit live node refs and
## transient objects. Owned by GameRoot and reset per run.

var run_id: int = 0
var seed: int = 0
var arena_id: StringName = &"default_arena"
var current_wave: int = 0
var score: int = 0
var currency: int = 0
var kills: int = 0
var combo: int = 0
var best_combo: int = 0
var damage_taken: float = 0.0
var elapsed_seconds: float = 0.0
var player_alive: bool = true
var paused: bool = false
var upgrade_choices: Array[StringName] = []
var selected_upgrades: Dictionary = {}          # upgrade_id -> stack count
var active_modifiers: Array[StringName] = []
var completed_objectives: Array[StringName] = []
var run_statistics: Dictionary = {}


func reset() -> void:
	run_id = 0
	seed = 0
	arena_id = &"default_arena"
	current_wave = 0
	score = 0
	currency = 0
	kills = 0
	combo = 0
	best_combo = 0
	damage_taken = 0.0
	elapsed_seconds = 0.0
	player_alive = true
	paused = false
	upgrade_choices.clear()
	selected_upgrades.clear()
	active_modifiers.clear()
	completed_objectives.clear()
	run_statistics.clear()


## Add a score delta and update state. Guards against negative drift.
func add_score(delta: int) -> void:
	score += delta
	if score < 0:
		score = 0


func add_currency(delta: int) -> void:
	currency += delta
	if currency < 0:
		currency = 0


func add_kill() -> void:
	kills += 1


func set_combo(value: int) -> void:
	combo = maxi(value, 0)
	if combo > best_combo:
		best_combo = combo


func add_damage_taken(amount: float) -> void:
	damage_taken += maxf(amount, 0.0)


## A safe, serializable snapshot suitable for a run-summary screen or analytics.
func summary() -> Dictionary:
	return {
		"run_id": run_id,
		"seed": seed,
		"arena_id": String(arena_id),
		"current_wave": current_wave,
		"score": score,
		"currency": currency,
		"kills": kills,
		"combo": combo,
		"best_combo": best_combo,
		"damage_taken": damage_taken,
		"elapsed_seconds": elapsed_seconds,
		"player_alive": player_alive,
		"selected_upgrades": selected_upgrades.duplicate(),
		"active_modifiers": active_modifiers.duplicate(),
	}
