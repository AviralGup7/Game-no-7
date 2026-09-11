class_name HelpPanel
extends Control
signal close_requested()
var _body: VBoxContainer

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_body = UiFactory.center_box(self)
	refresh()

func refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	UiFactory.title("MAKE YOUR FIRST STAND", _body, 34)
	var steps := [
		["01  MOVE", "Drag the left stick with your left thumb. Keep space around you and watch enemy telegraphs."],
		["02  AIM & FIRE", "Hold FIRE with your right thumb. Slide away from where you pressed to aim while moving. Release to stop. Aim assist helps with nearby targets in front; turn it off in Settings for free aim."],
		["03  RELOAD & DODGE", "Tap RELOAD between bursts; empty magazines reload automatically. Tap DODGE to escape in your movement direction. Dodging uses stamina, so let it recover."],
		["04  SKILLS", "Tap a READY skill. A level label means locked; a timer means cooling down. Skills also need stamina."],
		["05  SWITCH & GROW", "Tap SWAP when a second weapon is equipped. Collect XP to level up. Clear waves, then choose ONE upgrade for this run."],
		["06  SURVIVE & RETURN", "Bosses have multiple phases. After defeat, review your run and spend banked credits in the Armory. Run upgrades reset; Armory purchases persist."]
	]
	for step in steps:
		var card := UiFactory.card(_body)
		UiFactory.title(step[0], card, 22).modulate = UiTheme.CYAN
		UiFactory.label(step[1], card, 20)
	UiFactory.label("Minimap: triangle = you (cone = where you face); dots = enemies (ring = closest threat);\nrising ring = new spawn; large purple dot = boss (red rim = boss fight); blue pips = pickups (blinking = expiring).\nTap PAUSE or use Android Back to pause. Swipe empty space on the right to rotate the camera. Settings includes larger text and reduced motion.", _body, 18)
	var coach := get_tree().get_first_node_in_group("tutorial_manager") as TutorialManager
	if coach != null:
		var note := UiFactory.label("", _body, 20)
		UiFactory.button("SHOW GUIDED COACH NEXT RUN", _body, 20).pressed.connect(func() -> void:
			coach.replay_next_run()
			note.text = "The guided coach will return on your next run.")
		if coach.is_active():
			UiFactory.button("SKIP GUIDED COACH", _body, 20).pressed.connect(func() -> void:
				coach.skip_tutorial()
				note.text = "Coach skipped. These instructions are always available here.")
	UiFactory.button("GOT IT", _body, 22).pressed.connect(func() -> void: close_requested.emit())
