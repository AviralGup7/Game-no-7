class_name RunSetupPanel
extends Control
## Catalogue/selection presentation. No unlocks or run fields are modified here.
##
## There is exactly one map (the merged Foundry Depths dungeon), so this panel no longer
## offers an arena picker: the old "02 ARENA" selector and its unlock milestone are gone,
## and the single dungeon's intel is shown as a fixed card instead.
signal back_requested()
var _daily := false
var _weapon_ids: Array = []
var _mode_ids: Array[StringName] = []
var _weapons: OptionButton
var _modes: OptionButton
var _arena_info: Label
var _weapon_info: Label
var _mode_info: Label
var _daily_info: Label
var _feedback: Label
var _start: Button
var _heading: Label
var _daily_stamp := 0

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var body := UiFactory.center_box(self)
	_heading = UiFactory.title("PREPARE YOUR STAND", body, 34)
	UiFactory.label("01  MODE     /     02  LOADOUT", body, 18).modulate = UiTheme.CYAN
	_daily_info = UiFactory.label("", body, 20)

	# Mode picker.
	var mode := UiFactory.select_card(body, "MODE")
	_modes = mode.option
	_mode_info = mode.desc
	_mode_ids = GameMode.all_mode_ids()
	for id in _mode_ids:
		_modes.add_item(GameMode.display_name(id))
	_modes.item_selected.connect(_on_option_picked)

	# Arena intel — a fixed card, not a picker: the run always plays the one merged dungeon.
	var arena := UiFactory.select_card(body, "THE DUNGEON")
	arena.option.queue_free()
	_arena_info = arena.desc
	_arena_info.text = _arena_intel()

	# Weapon (starter loadout) picker.
	var weapon := UiFactory.select_card(body, "LOADOUT INTEL")
	_weapons = weapon.option
	_weapon_info = weapon.desc
	_weapon_ids = ContentRegistry.get_all_weapon_ids()
	_weapon_ids.sort()
	for id in _weapon_ids:
		_weapons.add_item(ContentRegistry.get_weapon(id).display_name)
	_weapons.item_selected.connect(_on_option_picked)

	_feedback = UiFactory.label("", body, 20)
	_feedback.modulate = UiTheme.GOLD
	_start = UiFactory.primary("ENTER THE DEPTHS", body, 24, Vector2(300, 104))
	UiTheme.decorate(_start, "play")
	_start.pressed.connect(_launch)
	UiFactory.button("BACK", body, 20).pressed.connect(func() -> void: back_requested.emit())


## The single map's name + lore, read off its config (there is only one `res://data/arenas/*.tres`).
func _arena_intel() -> String:
	var arena := ContentRegistry.get_arena(&"default_arena")
	if arena == null:
		return "The Foundry Depths\nA single dungeon, three wings."
	return "%s\n%s\n%s" % [
		arena.display_name,
		arena.lore_intro,
		" / ".join(arena.tags) if not arena.tags.is_empty() else "hazards live",
	]


## Every OptionButton refresh on the same live details line when the player picks
## a different mode / loadout.
func _on_option_picked(_index: int) -> void:
	UiFactory.play_press("OPTION")
	_refresh_details()

func present(daily: bool = false) -> void:
	_daily = daily
	_heading.text = "DAILY CHALLENGE" if daily else "PREPARE YOUR STAND"
	var challenge := DailyChallenge.challenge_for_today()
	_daily_stamp = int(challenge.stamp)
	var weapon: StringName = challenge.weapon if daily else (GameRoot.get_pending_weapon() if GameRoot != null else &"gladius")
	if weapon == &"":
		weapon = &"gladius"
	if not _weapon_ids.is_empty(): _weapons.select(maxi(_weapon_ids.find(weapon), 0))
	if not _mode_ids.is_empty():
		var pending := GameMode.MODE_STANDARD
		if GameRoot != null:
			pending = GameRoot.get_pending_mode()
		_modes.select(maxi(_mode_ids.find(pending), 0))
	_modes.disabled = daily
	_daily_info.visible = daily
	var mutators := PackedStringArray()
	# The card has room for names; the *rules* are a tooltip, following skill_bar's pattern.
	# `WaveMutatorConfig.description` is authored copy, so it is shown rather than left in the
	# inspector — a mutator whose promise nobody reads can quietly stop being kept (see HARDENING).
	var mutator_notes := PackedStringArray()
	for id in challenge.mutators:
		mutators.append(WaveMutators.display_name(id))
		mutator_notes.append("%s — %s" % [WaveMutators.display_name(id), WaveMutators.description(id)])
	if not mutator_notes.is_empty():
		_daily_info.tooltip_text = "\n".join(mutator_notes)
	_daily_info.text = "%s UTC  •  Fixed starter / shared seed\n%s\nOffline challenge — no online leaderboard." % [challenge.label, "  +  ".join(mutators)]
	_refresh_details()

## OptionButton.selected is -1 until something is picked (and stays -1 if the
## list is rebuilt), which would index the id arrays out of bounds.
func _selected_weapon_index() -> int:
	return clampi(_weapons.selected, 0, maxi(_weapon_ids.size() - 1, 0))

func _selected_mode_index() -> int:
	return clampi(_modes.selected, 0, maxi(_mode_ids.size() - 1, 0))

func _selected_mode() -> StringName:
	if _mode_ids.is_empty():
		return GameMode.MODE_STANDARD
	return _mode_ids[_selected_mode_index()]

func _refresh_details() -> void:
	if _weapon_ids.is_empty():
		_start.disabled = true
		_feedback.text = "Content unavailable. Return to the menu and try again."
		return
	var mode_id := _selected_mode() if not _daily else GameMode.MODE_STANDARD
	var weapon := ContentRegistry.get_weapon(_weapon_ids[_selected_weapon_index()])
	if weapon == null:
		_start.disabled = true
		_feedback.text = "This content could not be loaded."
		return
	var rank := GameRoot.get_prestige_rank() if GameRoot != null else 0
	_mode_info.text = "%s\n%s" % [GameMode.display_name(mode_id), GameMode.blurb(mode_id)]
	# Challenge previews its live prestige tier (label + escalated cap/payout).
	if GameMode.scales_with_prestige(mode_id):
		_mode_info.text += "\nPrestige tier: %s" % GameMode.challenge_tier_label(mode_id, rank)
	var obj := GameMode.objective(mode_id)
	var obj_line := ""
	match obj:
		GameMode.OBJECTIVE_SURVIVE_TIME:
			obj_line = "Endure %d seconds" % int(GameMode.target_seconds(mode_id))
		GameMode.OBJECTIVE_SLAY_BOSSES:
			obj_line = "Slay %d bosses" % GameMode.max_waves(mode_id)
		GameMode.OBJECTIVE_DEFEND_POINT:
			obj_line = "Hold the point for %d seconds" % int(GameMode.target_seconds(mode_id))
		GameMode.OBJECTIVE_COLLECT:
			obj_line = "Gather %d relics" % GameMode.collect_target(mode_id)
		_:
			var cap := GameMode.max_waves_for(mode_id, rank)
			obj_line = ("Clear %d waves" % cap) if cap > 0 else "Endless waves"
	_mode_info.text += "\nObjective: %s  •  Score x%.2f" % [obj_line, GameMode.score_multiplier_for(mode_id, rank)]
	_weapon_info.text = "%s\n%s  •  Damage %.1f  •  Reach %.1fm  •  Interval %.2fs" % [weapon.description,
		String(weapon.kind).capitalize(), weapon.base_damage, weapon.attack_range, weapon.swing_cooldown]
	var fixed := GameMode.fixed_weapon(mode_id)
	var starter: StringName = DailyChallenge.challenge_for_today().weapon if _daily else (fixed if fixed != &"" else weapon.weapon_id)
	var starter_config := ContentRegistry.get_weapon(starter)
	if starter_config == null:
		_start.disabled = true
		_feedback.text = "Today's starter could not be loaded. Return to the menu."
		return
	_weapons.disabled = _daily or fixed != &""
	var service := UiCommands.meta(get_tree())
	var owned := weapon.weapon_id == &"gladius" or (service != null and service.is_weapon_unlocked(weapon.weapon_id))
	var loadout_locked := not _daily and fixed == &"" and not owned
	_start.disabled = starter_config.disabled or loadout_locked
	_feedback.text = "Starter: %s. Transform upgrades change how you fight — pick boldly." % starter_config.display_name
	if loadout_locked:
		_feedback.text = ("OWNED" if owned else "LOCKED") + " — buy this loadout in the Armory before it can start a run."
	_start.text = "START DAILY RUN" if _daily else "ENTER THE DEPTHS"


func _launch() -> void:
	if _start.disabled:
		return
	if GameRoot.get_current_state() != GameRoot.State.MAIN_MENU:
		_feedback.text = "Return to the main menu before starting a new run."
		return
	if _daily and DailyChallenge.today_stamp() != _daily_stamp:
		present(true)
		_feedback.text = "A new UTC challenge is available. Review the updated loadout, then start."
		return
	# One map: pin the merged dungeon explicitly so the run never depends on a stale selection.
	if not UiCommands.select_arena(&"default_arena"):
		_feedback.text = "The dungeon could not be loaded. Your run has not started."
		return
	if not _daily:
		GameRoot.set_pending_weapon(_weapon_ids[_selected_weapon_index()])
	_start.disabled = true
	if _daily:
		GameRoot.start_daily_run()
	else:
		GameRoot.request_play_mode(_selected_mode())
