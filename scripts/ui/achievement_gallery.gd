class_name AchievementGallery
extends VBoxContainer
## Read-only view of the existing achievement catalogue and saved unlock list.
var _toggle: Button
var _list: VBoxContainer

func _ready() -> void:
	_toggle = UiFactory.button("ACHIEVEMENTS", self, 22)
	_toggle.pressed.connect(func() -> void:
		_list.visible = not _list.visible
		if _list.visible: refresh())
	_list = VBoxContainer.new()
	add_child(_list)
	_list.hide()
	EventBus.achievement_unlocked.connect(func(_id: StringName) -> void: refresh())
	refresh()

func refresh() -> void:
	if _list == null: return
	var unlocked := SaveManager.get_unlocked_achievements()
	var definitions := Achievements.definitions()
	_toggle.text = "ACHIEVEMENTS  /  %d OF %d" % [unlocked.size(), definitions.size()]
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if not _list.visible: return
	for id in definitions:
		var def: Dictionary = definitions[id]
		var owned: bool = String(id) in unlocked or id in unlocked
		var body := UiFactory.card(_list)
		UiFactory.title(("UNLOCKED  /  " if owned else "LOCKED  /  ") + String(def.name), body, 22).modulate = UiTheme.GOLD if owned else UiTheme.MUTED
		UiFactory.label(String(def.description), body, 20)
	UiTheme.apply_text_scale(_list, SaveManager.get_settings().text_scale)

## Hardened: validate gallery index.
func _validated_gallery_index(i: int, n: int) -> int:
	if n <= 0:
		return -1
	if i < 0 or i >= n:
		return -1
	return i
func _guarded_show(idx: int) -> bool:
	return idx >= 0

