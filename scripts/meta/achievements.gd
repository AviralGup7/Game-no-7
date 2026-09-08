class_name Achievements
extends Node

## Achievement definitions + run tracker. Wires to EventBus (kills, waves,
## score, upgrades, skills, pickups) and unlocks achievements whose predicates
## hold; unlocks persist via SaveManager and announce through the banner bus.
## Definitions are pure data so the gallery UI and tests share one source.

signal achievement_unlocked_local(achievement_id: StringName)

const RARITY_BRONZE := &"bronze"
const RARITY_SILVER := &"silver"
const RARITY_GOLD := &"gold"
const RARITY_PLATINUM := &"platinum"

var _unlocked: Dictionary = {}   # StringName -> true (persisted mirror)
var _run_kills := 0
var _run_max_combo := 0
var _run_crit_kills := 0
var _run_flawless_waves := 0
var _run_damage_taken := 0.0
var _run_skills_cast := 0
var _run_pickups := 0
var _run_elites := 0
var _wired := false
var _player_health: Node = null


## Static definition table: id -> {name, description, rarity, hint}.
static func definitions() -> Dictionary:
	return {
		&"first_blood": {"name": "First Blood", "description": "Kill your first enemy.", "rarity": RARITY_BRONZE, "hint": "The arena welcomes you."},
		&"slayer_50": {"name": "Slayer", "description": "Kill 50 enemies in one run.", "rarity": RARITY_BRONZE, "hint": "Keep swinging."},
		&"slayer_200": {"name": "Whirlwind of Death", "description": "Kill 200 enemies in one run.", "rarity": RARITY_SILVER, "hint": "Endless hunger."},
		&"slayer_500": {"name": "Arena Legend", "description": "Kill 500 enemies in one run.", "rarity": RARITY_GOLD, "hint": "Mythic carnage."},
		&"combo_10": {"name": "Heating Up", "description": "Reach a 10-kill combo.", "rarity": RARITY_BRONZE, "hint": "Chain kills quickly."},
		&"combo_25": {"name": "Unstoppable", "description": "Reach a 25-kill combo.", "rarity": RARITY_SILVER, "hint": "Never stop."},
		&"combo_50": {"name": "Godlike", "description": "Reach a 50-kill combo.", "rarity": RARITY_GOLD, "hint": "Transcend."},
		&"wave_5": {"name": "Survivor", "description": "Clear wave 5.", "rarity": RARITY_BRONZE, "hint": "Hold the line."},
		&"wave_10": {"name": "Champion", "description": "Clear wave 10 (the Warlord).", "rarity": RARITY_SILVER, "hint": "Dethrone the Warlord."},
		&"wave_20": {"name": "Eternal", "description": "Clear wave 20.", "rarity": RARITY_GOLD, "hint": "Beyond the end."},
		&"upgrader": {"name": "Power Hungry", "description": "Take 5 upgrades in one run.", "rarity": RARITY_BRONZE, "hint": "Every choice matters."},
		&"crit_fan": {"name": "Lucky Strikes", "description": "Land 25 critical hits in one run.", "rarity": RARITY_SILVER, "hint": "Crit builds help."},
		&"flawless": {"name": "Untouchable", "description": "Clear a wave past wave 3 without taking damage.", "rarity": RARITY_SILVER, "hint": "Dodge everything."},
		&"elite_hunter": {"name": "Big Game", "description": "Kill 5 elite enemies in one run.", "rarity": RARITY_SILVER, "hint": "Gold-rimmed prey."},
		&"skill_spammer": {"name": "Showoff", "description": "Cast 15 skills in one run.", "rarity": RARITY_BRONZE, "hint": "Q, E, R on cooldown."},
		&"hoarder": {"name": "Hoarder", "description": "Collect 30 pickups in one run.", "rarity": RARITY_BRONZE, "hint": "Shiny things save lives."},
		&"boss_slayer": {"name": "Giantslayer", "description": "Defeat the Arena Warlord.", "rarity": RARITY_GOLD, "hint": "Three phases. No mercy."},
		&"score_10k": {"name": "Ten Thousand", "description": "Score 10,000 in one run.", "rarity": RARITY_SILVER, "hint": "Combos multiply."},
		&"score_100k": {"name": "Century", "description": "Score 100,000 in one run.", "rarity": RARITY_PLATINUM, "hint": "Perfection, sustained."},
	}


func _ready() -> void:
	_load_persisted()
	_wire()


func _load_persisted() -> void:
	_unlocked.clear()
	if SaveManager != null:
		for raw in SaveManager.get_unlocked_achievements():
			_unlocked[StringName(String(raw))] = true


func _wire() -> void:
	if _wired or EventBus == null:
		return
	_wired = true
	EventBus.run_started.connect(_on_run_started)
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.combo_changed.connect(_on_combo_changed)
	EventBus.wave_completed.connect(_on_wave_completed)
	EventBus.wave_started.connect(_on_wave_started)
	EventBus.upgrade_selected.connect(_on_upgrade_selected)
	EventBus.skill_cast.connect(_on_skill_cast)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.score_changed.connect(_on_score_changed)


func _on_run_started(_run_id: int, _seed: int) -> void:
	_run_kills = 0
	_run_max_combo = 0
	_run_crit_kills = 0
	_run_flawless_waves = 0
	_run_damage_taken = 0.0
	_run_skills_cast = 0
	_run_pickups = 0
	_run_elites = 0
	_rebind_player_damage()
	# Player may not exist yet when run_started fires (world builds after); retry next frame.
	if _player_health == null:
		_rebind_player_damage.call_deferred()


func is_unlocked(achievement_id: StringName) -> bool:
	return bool(_unlocked.get(achievement_id, false))


func unlock(achievement_id: StringName) -> bool:
	if is_unlocked(achievement_id):
		return false
	if not definitions().has(achievement_id):
		return false
	_unlocked[achievement_id] = true
	if SaveManager != null:
		SaveManager.unlock_achievement(achievement_id)
	achievement_unlocked_local.emit(achievement_id)
	if EventBus != null:
		EventBus.achievement_unlocked.emit(achievement_id)
		var def: Dictionary = definitions()[achievement_id]
		EventBus.announcement.emit(&"achievement", "Achievement: %s" % String(def["name"]), &"victory")
	return true


func unlocked_count() -> int:
	return _unlocked.size()


func total_count() -> int:
	return definitions().size()


func _on_enemy_killed(enemy: Node, archetype_id: StringName, _score: int, _currency: int) -> void:
	_run_kills += 1
	unlock(&"first_blood")
	if _run_kills >= 50:
		unlock(&"slayer_50")
	if _run_kills >= 200:
		unlock(&"slayer_200")
	if _run_kills >= 500:
		unlock(&"slayer_500")
	var elite := enemy as EnemyBase
	if elite != null and elite.is_elite():
		_run_elites += 1
		if _run_elites >= 5:
			unlock(&"elite_hunter")
	if archetype_id == &"warlord":
		unlock(&"boss_slayer")


func _on_enemy_damaged(_enemy: Node, result: DamageResult) -> void:
	if result != null and result.was_critical:
		_run_crit_kills += 1
		if _run_crit_kills >= 25:
			unlock(&"crit_fan")


func _on_combo_changed(combo: int, _best: int) -> void:
	_run_max_combo = maxi(_run_max_combo, combo)
	if combo >= 10:
		unlock(&"combo_10")
	if combo >= 25:
		unlock(&"combo_25")
	if combo >= 50:
		unlock(&"combo_50")


func _on_wave_started(_wave: int, _planned: int) -> void:
	_run_damage_taken = 0.0
	_rebind_player_damage()


## UI/debug damage observers forward player damage here (same seam as the
## DifficultyDirector) so flawless waves can be detected.
func record_player_damage(amount: float) -> void:
	_run_damage_taken += maxf(amount, 0.0)


func _rebind_player_damage() -> void:
	if _player_health != null and is_instance_valid(_player_health):
		if _player_health.has_signal("damaged") and _player_health.damaged.is_connected(_on_player_damaged):
			_player_health.damaged.disconnect(_on_player_damaged)
	_player_health = null
	if GameRoot == null or GameRoot.get_active_player() == null:
		return
	var hp := (GameRoot.get_active_player() as Node).get_node_or_null("HealthComponent")
	if hp == null or not hp.has_signal("damaged"):
		return
	if not hp.damaged.is_connected(_on_player_damaged):
		hp.damaged.connect(_on_player_damaged)
	_player_health = hp


func _on_player_damaged(result: DamageResult) -> void:
	if result != null and result.accepted:
		record_player_damage(result.final_amount)


func _exit_tree() -> void:
	if _player_health != null and is_instance_valid(_player_health) and _player_health.has_signal("damaged") and _player_health.damaged.is_connected(_on_player_damaged):
		_player_health.damaged.disconnect(_on_player_damaged)


func _on_wave_completed(wave_number: int, _bonus: int) -> void:
	if wave_number >= 5:
		unlock(&"wave_5")
	if wave_number >= 10:
		unlock(&"wave_10")
	if wave_number >= 20:
		unlock(&"wave_20")
	if wave_number > 3 and _run_damage_taken <= 0.0:
		_run_flawless_waves += 1
		unlock(&"flawless")


func _safe_run() -> RunState:
	if GameRoot == null:
		return null
	return GameRoot.get_run()

func _selected_upgrade_count() -> int:
	var run := _safe_run()
	if run == null:
		return 0
	var count := 0
	for id in run.selected_upgrades:
		count += int(run.selected_upgrades[id])
	return count

func _on_upgrade_selected(_upgrade_id: StringName) -> void:
	if _selected_upgrade_count() >= 5:
		unlock(&"upgrader")


func _on_skill_cast(_skill_id: StringName, _caster: Node) -> void:
	_run_skills_cast += 1
	if _run_skills_cast >= 15:
		unlock(&"skill_spammer")


func _on_pickup_collected(_pickup_id: StringName, _amount: int, _collector: Node) -> void:
	_run_pickups += 1
	if _run_pickups >= 30:
		unlock(&"hoarder")


func _on_score_changed(score: int, _delta: int) -> void:
	if score >= 10000:
		unlock(&"score_10k")
	if score >= 100000:
		unlock(&"score_100k")


func get_debug_snapshot() -> Dictionary:
	return {
		"unlocked": _unlocked.size(),
		"total": total_count(),
		"run_kills": _run_kills,
		"run_max_combo": _run_max_combo,
	}

