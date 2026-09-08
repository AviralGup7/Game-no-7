class_name MenuPanel
extends Control

signal navigate(screen: StringName)
signal quit_requested()
var _records: Label

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var box := UiFactory.center_box(self)
	UiFactory.label("S U R V I V E   /   A D A P T   /   R I S E", box, 18).modulate = UiTheme.CYAN
	UiFactory.title("LAST STAND", box, 68)
	UiFactory.title("A R E N A", box, 30).modulate = UiTheme.GOLD
	UiFactory.label("One arena. Endless pressure. Make every stand count.", box, 22)
	var play := UiFactory.button("START RUN", box, 26, Vector2(240, 68))
	UiTheme.decorate(play, "play")
	play.pressed.connect(func() -> void: navigate.emit(&"run_setup"))
	var daily := UiFactory.button("DAILY CHALLENGE  /  TODAY'S SEED", box, 22)
	UiTheme.decorate(daily, "star")
	daily.pressed.connect(func() -> void: navigate.emit(&"daily"))
	var row := HBoxContainer.new()
	box.add_child(row)
	for entry in [["ARMORY", &"armory", "trophy"], ["SETTINGS", &"settings", "gear"], ["HOW TO PLAY", &"help", "gamepad"]]:
		var b := UiFactory.button(entry[0], row, 20, Vector2(0, 56))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		UiTheme.decorate(b, entry[2])
		var destination: StringName = entry[1]
		b.pressed.connect(func() -> void: navigate.emit(destination))
	_records = UiFactory.label("", box, 20)
	if not OS.has_feature("mobile"):
		UiFactory.button("QUIT", box, 18).pressed.connect(func() -> void: quit_requested.emit())
	refresh()

func refresh() -> void:
	_records.text = "PERSONAL BEST  %s    /    WAVE %d    /    BANK %d" % [
		SaveManager.get_best_score(), SaveManager.get_best_wave(), SaveManager.get_meta_wallet()]
	if not SaveManager.is_tutorial_completed():
		_records.text += "\nFirst stand? Controls and a guided coach are ready for you."
