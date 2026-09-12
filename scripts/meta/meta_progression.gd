class_name MetaProgression
extends Node

## Cross-run meta progression: a persistent wallet (banked run currency),
## permanent stat boosts and content unlocks bought from the armory screen.
## Purchases validate funds + prerequisites, apply immediately to the live
## ProgressionComponent when a run is active, and persist through SaveManager.
## All pricing/stats are data (ARMORY) so balance passes never touch logic.

signal purchase_completed(item_id: StringName)
signal wallet_changed(balance: int)

const ARMORY := {
	&"vitality_tome": {"name": "Tome of Vitality", "cost": 100, "requires": [], "stat": &"max_health_add", "per_rank": 10.0, "max_rank": 5, "kind": &"stat", "blurb": "+10 max HP per rank, every run."},
	&"swift_boots": {"name": "Swift Boots", "cost": 120, "requires": [], "stat": &"move_speed_multiplier", "per_rank": 0.03, "max_rank": 5, "kind": &"stat", "blurb": "+3% move speed per rank."},
	&"whetstone": {"name": "Whetstone", "cost": 150, "requires": [], "stat": &"attack_damage_multiplier", "per_rank": 0.04, "max_rank": 5, "kind": &"stat", "blurb": "+4% damage per rank."},
	&"second_wind": {"name": "Second Wind", "cost": 200, "requires": [&"vitality_tome"], "stat": &"stamina_max_add", "per_rank": 15.0, "max_rank": 3, "kind": &"stat", "blurb": "+15 stamina per rank."},
	&"lucky_charm": {"name": "Lucky Charm", "cost": 250, "requires": [], "stat": &"crit_chance_add", "per_rank": 0.02, "max_rank": 3, "kind": &"stat", "blurb": "+2% crit chance per rank."},
	&"unlock_warreaxe": {"name": "Armory: War Axe", "cost": 300, "requires": [], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"weapon", "target": &"warreaxe", "blurb": "Unlock the War Axe loadout."},
	&"unlock_sunbow": {"name": "Armory: Scout Rifle", "cost": 500, "requires": [&"unlock_warreaxe"], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"weapon", "target": &"sunbow", "blurb": "Unlock the Scout Rifle loadout."},
	&"unlock_bladestorm": {"name": "Manual: EMP Burst", "cost": 400, "requires": [], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"skill", "target": &"bladestorm", "blurb": "EMP Burst starts unlocked."},
	&"unlock_sentinel_spear": {"name": "Armory: Rail Rifle", "cost": 260, "requires": [], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"weapon", "target": &"sentinel_spear", "blurb": "Unlock the reach weapon."},
	&"unlock_moonlance": {"name": "Armory: Moonlance", "cost": 650, "requires": [&"unlock_sentinel_spear"], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"weapon", "target": &"moonlance", "blurb": "Unlock the hybrid frost weapon."},
	&"unlock_chain_lightning": {"name": "Manual: Tesla Arc", "cost": 650, "requires": [&"unlock_bladestorm"], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"skill", "target": &"chain_lightning", "blurb": "Unlock the chain-control skill."},
	&"unlock_mending_light": {"name": "Manual: Mending Light", "cost": 500, "requires": [], "stat": &"", "per_rank": 0.0, "max_rank": 1, "kind": &"skill", "target": &"mending_light", "blurb": "Unlock the sustain skill."},
	&"status_lens": {"name": "Status Lens", "cost": 320, "requires": [], "stat": &"status_chance_add", "per_rank": 0.04, "max_rank": 3, "kind": &"stat", "blurb": "+4% status chance per rank."},
}

var _wallet := 0
var _ranks: Dictionary = {}  # item_id -> rank purchased
var _prestige_rank := 0

signal prestige_completed(new_rank: int)


func _ready() -> void:
	add_to_group("meta_progression")
	_load()
	if EventBus != null and not EventBus.run_ended.is_connected(_on_run_ended):
		EventBus.run_ended.connect(_on_run_ended)


func _load() -> void:
	_wallet = 0
	_ranks.clear()
	_prestige_rank = 0
	if SaveManager == null:
		return
	_wallet = maxi(SaveManager.get_meta_wallet(), 0)
	_prestige_rank = SaveManager.get_prestige_rank()
	if GameRoot != null:
		GameRoot.set_prestige_rank(_prestige_rank)
	var ranks := SaveManager.get_meta_ranks()
	if ranks is Dictionary:
		_ranks = ranks.duplicate()
		# Migrate legacy key typo: "vitality Tome" -> "vitality_tome".
		var legacy := StringName("vitality Tome")
		if _ranks.has(legacy):
			var v: Variant = _ranks[legacy]
			_ranks.erase(legacy)
			if not _ranks.has(&"vitality_tome"):
				_ranks[&"vitality_tome"] = v
			else:
				_ranks[&"vitality_tome"] = maxi(int(_ranks[&"vitality_tome"]), int(v))


func _save(flush: bool = true) -> void:
	if SaveManager == null:
		return
	SaveManager.set_meta_wallet(_wallet)
	SaveManager.set_meta_ranks(_ranks.duplicate())
	SaveManager.set_prestige_rank(_prestige_rank)
	if flush:
		SaveManager.save_now()


func _on_run_ended(_score: int, _wave: int, _best: int) -> void:
	# Campaign rewards are banked once as objectives/encounters are completed.
	if GameRoot.is_campaign():
		return
	# Bank a cut of the run's unspent currency into the persistent wallet.
	# Prestige multiplies the banked cut; victory runs bank a slightly larger share.
	var run := GameRoot.get_run()
	if run != null:
		var share := 0.55 if run.victory else 0.5
		var earned := maxi(int(round(float(run.currency) * share * Prestige.currency_multiplier(_prestige_rank))), 0)
		if earned > 0:
			_wallet += earned
			_save()
			wallet_changed.emit(_wallet)


func get_wallet() -> int:
	return _wallet


func grant_currency(amount: int, flush: bool = true) -> void:
	if amount <= 0:
		return
	_wallet += amount
	_save(flush)
	wallet_changed.emit(_wallet)


func get_rank(item_id: StringName) -> int:
	return int(_ranks.get(item_id, 0))


func is_maxed(item_id: StringName) -> bool:
	if not ARMORY.has(item_id):
		return true
	return get_rank(item_id) >= int(ARMORY[item_id]["max_rank"])


func price_of(item_id: StringName) -> int:
	if not ARMORY.has(item_id):
		return -1
	# Linear price growth per rank: cost * (rank+1).
	return int(ARMORY[item_id]["cost"]) * (get_rank(item_id) + 1)


func can_purchase(item_id: StringName) -> StringName:
	if not ARMORY.has(item_id):
		return &"unknown_item"
	if is_maxed(item_id):
		return &"maxed"
	for req in ARMORY[item_id]["requires"]:
		if get_rank(StringName(String(req))) <= 0:
			return &"missing_prerequisite"
	if _wallet < price_of(item_id):
		return &"insufficient_funds"
	return &"ok"


func purchase(item_id: StringName) -> bool:
	if can_purchase(item_id) != &"ok":
		return false
	_wallet -= price_of(item_id)
	_ranks[item_id] = get_rank(item_id) + 1
	_save()
	_apply_live(item_id)
	purchase_completed.emit(item_id)
	wallet_changed.emit(_wallet)
	return true


## Push a stat item into the live run's ProgressionComponent when present.
func _apply_live(item_id: StringName) -> void:
	var def: Dictionary = ARMORY[item_id]
	if String(def["kind"]) != "stat":
		return
	if GameRoot == null or GameRoot.get_active_player() == null:
		return
	var player := GameRoot.get_active_player()
	if player != null:
		player.get_progression_component().add_permanent_bonus(StringName(String(def["stat"])), float(def["per_rank"]))
		player.rebuild_derived_stats()


## Apply ALL owned ranks at run start (called by Main after world build).
func apply_all_to_run() -> void:
	if GameRoot == null or GameRoot.get_active_player() == null:
		return
	var player := GameRoot.get_active_player()
	var prog := player.get_progression_component() if player != null else null
	if prog == null:
		return
	for item_id in _ranks:
		var def: Dictionary = ARMORY.get(item_id, {})
		if def.is_empty() or String(def["kind"]) != "stat":
			continue
		prog.add_permanent_bonus(StringName(String(def["stat"])), float(def["per_rank"]) * float(get_rank(item_id)))


func unlocked_targets(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for item_id in ARMORY:
		var def: Dictionary = ARMORY[item_id]
		if StringName(String(def.get("kind", ""))) != kind:
			continue
		if get_rank(item_id) > 0:
			out.append(StringName(String(def.get("target", ""))))
	return out


func is_weapon_unlocked(weapon_id: StringName) -> bool:
	for item_id in _ranks:
		var def: Dictionary = ARMORY.get(item_id, {})
		if String(def.get("kind", "")) == "weapon" and StringName(String(def.get("target", ""))) == weapon_id:
			return get_rank(item_id) > 0
	return weapon_id == &"gladius"  # starter is always available


func is_skill_unlocked_from_start(skill_id: StringName) -> bool:
	for item_id in _ranks:
		var def: Dictionary = ARMORY.get(item_id, {})
		if String(def.get("kind", "")) == "skill" and StringName(String(def.get("target", ""))) == skill_id:
			return get_rank(item_id) > 0
	return false


func get_prestige_rank() -> int:
	return _prestige_rank


func prestige_title() -> String:
	return Prestige.title_for(_prestige_rank)


## Fraction of armory items that have at least one rank (0..1).
func armory_completion() -> float:
	if ARMORY.is_empty():
		return 1.0
	var owned := 0
	for item_id in ARMORY:
		if get_rank(item_id) > 0:
			owned += 1
	return float(owned) / float(ARMORY.size())


func can_prestige() -> StringName:
	return Prestige.can_prestige(_prestige_rank, _wallet, armory_completion())


func prestige_cost() -> int:
	return Prestige.cost_for_rank(_prestige_rank)


## Spend wallet + reset armory ranks for a permanent prestige rank.
## Keeps weapon/skill unlocks (kind != stat) so the player doesn't lose content.
func perform_prestige() -> bool:
	if can_prestige() != &"ok":
		return false
	var cost := prestige_cost()
	_wallet = maxi(_wallet - cost, 0)
	# Strip stat ranks only; keep unlock purchases.
	var kept: Dictionary = {}
	for item_id in _ranks:
		var def: Dictionary = ARMORY.get(item_id, {})
		if def.is_empty():
			continue
		if String(def.get("kind", "")) != "stat":
			kept[item_id] = _ranks[item_id]
	_ranks = kept
	_prestige_rank = Prestige.clamp_rank(_prestige_rank + 1)
	# Unlock cosmetics for the new rank.
	for c in Prestige.cosmetics_for_rank(_prestige_rank):
		SaveManager.unlock_cosmetic(String(c))
	_save()
	if GameRoot != null:
		GameRoot.set_prestige_rank(_prestige_rank)
	prestige_completed.emit(_prestige_rank)
	wallet_changed.emit(_wallet)
	if EventBus != null:
		EventBus.announcement.emit(
			&"prestige",
			"Prestige %d — %s" % [_prestige_rank, Prestige.title_for(_prestige_rank)],
			&"victory"
		)
	return true


func get_debug_snapshot() -> Dictionary:
	return {
		"wallet": _wallet,
		"ranks": _ranks.duplicate(),
		"prestige_rank": _prestige_rank,
		"title": Prestige.title_for(_prestige_rank),
	}

