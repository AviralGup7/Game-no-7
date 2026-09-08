class_name RunSetupPanel
extends Control
## Catalogue/selection presentation. No unlocks or run fields are modified here.
signal back_requested()
var _daily := false
var _arena_ids: Array[StringName] = []
var _weapon_ids: Array = []
var _arenas: OptionButton
var _weapons: OptionButton
var _arena_info: Label
var _weapon_info: Label
var _daily_info: Label
var _feedback: Label
var _start: Button
var _heading: Label
var _daily_stamp := 0

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var body := UiFactory.center_box(self)
	_heading = UiFactory.title("PREPARE YOUR STAND", body, 34)
	UiFactory.label("01  ARENA     /     02  LOADOUT     /     03  ENTER", body, 18).modulate = UiTheme.CYAN
	_daily_info = UiFactory.label("", body, 20)
	var arena_card := UiFactory.card(body)
	UiFactory.title("ARENA INTEL", arena_card, 22)
	_arenas = OptionButton.new()
	_arenas.custom_minimum_size.y = UiTheme.TOUCH_MIN
	arena_card.add_child(_arenas)
	_arena_info = UiFactory.label("", arena_card)
	# Discover supplied arena resources rather than maintaining a duplicate list.
	for raw_file in DirAccess.get_files_at("res://data/arenas"):
		var file := raw_file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var config := load("res://data/arenas/" + file) as ArenaConfig
			if config != null and config.arena_id not in _arena_ids:
				_arena_ids.append(config.arena_id)
				_arenas.add_item(config.display_name)
	_arenas.item_selected.connect(func(_i: int) -> void:
		UiFactory.play_press("OPTION")
		_refresh_details())
	var weapon_card := UiFactory.card(body)
	UiFactory.title("LOADOUT INTEL", weapon_card, 22)
	_weapons = OptionButton.new()
	_weapons.custom_minimum_size.y = UiTheme.TOUCH_MIN
	weapon_card.add_child(_weapons)
	_weapon_ids = ContentRegistry.get_all_weapon_ids()
	_weapon_ids.sort()
	for id in _weapon_ids:
		_weapons.add_item(ContentRegistry.get_weapon(id).display_name)
	_weapons.item_selected.connect(func(_i: int) -> void:
		UiFactory.play_press("OPTION")
		_refresh_details())
	_weapon_info = UiFactory.label("", weapon_card)
	_feedback = UiFactory.label("", body, 20)
	_feedback.modulate = UiTheme.GOLD
	_start = UiFactory.button("ENTER ARENA", body, 24)
	UiTheme.decorate(_start, "play")
	_start.pressed.connect(_launch)
	UiFactory.button("BACK", body, 20).pressed.connect(func() -> void: back_requested.emit())

func present(daily: bool = false) -> void:
	_daily = daily
	_heading.text = "DAILY CHALLENGE" if daily else "PREPARE YOUR STAND"
	var challenge := DailyChallenge.challenge_for_today()
	_daily_stamp = int(challenge.stamp)
	var weapon: StringName = challenge.weapon if daily else &"gladius"
	if not _arena_ids.is_empty(): _arenas.select(maxi(_arena_ids.find(ContentRegistry.get_selected_arena_id()), 0))
	if not _weapon_ids.is_empty(): _weapons.select(maxi(_weapon_ids.find(weapon), 0))
	_daily_info.visible = daily
	var mutators := PackedStringArray()
	for id in challenge.mutators:
		mutators.append(WaveMutators.display_name(id))
	_daily_info.text = "%s UTC  •  Fixed starter / shared seed\n%s\nOffline challenge — no online leaderboard." % [challenge.label, "  +  ".join(mutators)]
	_refresh_details()

func _refresh_details() -> void:
	if _arena_ids.is_empty() or _weapon_ids.is_empty():
		_start.disabled = true
		_feedback.text = "Content unavailable. Return to the menu and try again."
		return
	var arena := ContentRegistry.get_arena(_arena_ids[_arenas.selected])
	var weapon := ContentRegistry.get_weapon(_weapon_ids[_weapons.selected])
	if arena == null or weapon == null:
		_start.disabled = true
		_feedback.text = "This content could not be loaded."
		return
	_arena_info.text = "%s\n%s  •  Unlock milestone: wave %d" % [arena.display_name,
		" / ".join(arena.tags) if not arena.tags.is_empty() else "Classic survival", arena.unlock_wave]
	_weapon_info.text = "%s\n%s  •  Damage %.1f  •  Reach %.1fm  •  Interval %.2fs" % [weapon.description,
		String(weapon.kind).capitalize(), weapon.base_damage, weapon.range, weapon.swing_cooldown]
	var starter: StringName = DailyChallenge.challenge_for_today().weapon if _daily else &"gladius"
	var starter_config := ContentRegistry.get_weapon(starter)
	if starter_config == null:
		_start.disabled = true
		_feedback.text = "Today's starter could not be loaded. Return to the menu."
		return
	var supported := weapon.weapon_id == starter and not weapon.disabled
	var current := arena.arena_id == ContentRegistry.get_selected_arena_id()
	var selectable := current or GameRoot.has_method("request_arena_selection")
	_start.disabled = not supported or not selectable
	_feedback.text = "Starter: %s. Skills unlock as you gain XP; choose upgrades after waves." % starter_config.display_name
	if not current and not selectable:
		_feedback.text = "ARENA PREVIEW ONLY — arena selection is not available in this build. Choose the current arena to launch."
	elif not supported:
		var service := UiCommands.meta(get_tree())
		var owned := service != null and service.is_weapon_unlocked(weapon.weapon_id)
		_feedback.text = ("OWNED" if owned else "CATALOGUE") + " — starter loadout selection is not available in this build. Preview only."
	_start.text = "START DAILY RUN" if _daily else "ENTER ARENA"

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
	if not UiCommands.select_arena(_arena_ids[_arenas.selected]):
		_feedback.text = "Arena selection was declined. Your run has not started."
		return
	_start.disabled = true
	if _daily:
		GameRoot.start_daily_run()
	else:
		GameRoot.request_play()

## Hardened: clamp run seed input.
func _validated_setup_seed(s: int) -> int:
	if s != 0:
		return s
	var r := randi()
	return r if r != 0 else 1

