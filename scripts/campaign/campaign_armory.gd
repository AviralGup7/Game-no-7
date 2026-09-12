class_name CampaignArmory
extends VBoxContainer
## Uses the existing persistent wallet/ranks, without arena prestige or wave
## requirements. Purchased and story-earned gear can be equipped while paused.

signal close_requested
var director: CampaignDirector
var _body: VBoxContainer
var _feedback: Label


func _ready() -> void:
	_feedback = UiFactory.label("", self, 20)
	_feedback.modulate = UiTheme.GOLD
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	add_child(_body)
	UiFactory.button("BACK", self, 22).pressed.connect(func() -> void: close_requested.emit())
	EventBus.save_failed.connect(func(_reason: StringName) -> void:
		_feedback.text = "Saving failed. Purchases may not survive closing the app.")
	refresh()


func _meta() -> MetaProgression:
	return get_tree().get_first_node_in_group("meta_progression") as MetaProgression


func refresh() -> void:
	if _body == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var meta := _meta()
	if meta == null:
		return
	UiFactory.label("BANKED CREDITS / %d" % meta.get_wallet(), _body, 26)
	UiFactory.label("Ranks and credits stay with your profile. Mission rewards are earned once per campaign.", _body, 20)
	if is_instance_valid(director):
		UiFactory.title("LOADOUT / SECONDARY WEAPON", _body, 24)
		for id in director.available_weapons():
			var config := ContentRegistry.get_weapon(id)
			if config == null:
				continue
			var weapon_id := id
			UiFactory.button("EQUIP / " + config.display_name, _body, 20).pressed.connect(func() -> void:
				if director.equip_secondary(weapon_id):
					_feedback.text = "Secondary equipped. Use SWAP to switch weapons.")
		for id in meta.unlocked_targets(&"skill"):
			var config := ContentRegistry.get_skill(id)
			if config == null:
				continue
			var skill_id := id
			UiFactory.button("SKILL 3 / " + config.display_name, _body, 20).pressed.connect(func() -> void:
				if director.equip_third_skill(skill_id):
					_feedback.text = "Skill equipped in slot 3.")
	else:
		UiFactory.label("Continue your campaign, then open the paused Armory to equip owned gear.", _body, 18)
	UiFactory.title("PERMANENT REQUISITIONS", _body, 24)
	for raw_id in MetaProgression.ARMORY:
		_build_item(meta, StringName(String(raw_id)))
	UiTheme.apply_text_scale(self, SaveManager.get_settings().text_scale)


func _build_item(meta: MetaProgression, id: StringName) -> void:
	var item: Dictionary = MetaProgression.ARMORY[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_body.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var caption := UiFactory.title("%s / %d of %d" % [_item_name(item), meta.get_rank(id), int(item.max_rank)], info, 22)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var description := String(item.blurb).replace("every run", "every checkpoint")
	if String(item.kind) == "weapon":
		description = "Permanently unlock " + _item_name(item) + "."
		if is_instance_valid(director) and StringName(String(item.target)) in director.available_weapons():
			description += " Available this campaign; purchase keeps it for new campaigns and prerequisites."
	var desc := UiFactory.label(description, info, 18)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var buy := UiFactory.button("BUY / %d" % meta.price_of(id), row, 20, Vector2(170, 88))
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var verdict := meta.can_purchase(id)
	buy.disabled = verdict != &"ok"
	if verdict == &"maxed":
		buy.text = "OWNED"
	elif verdict == &"missing_prerequisite":
		buy.text = "LOCKED"
		var names := PackedStringArray()
		for requirement in item.requires:
			names.append(_item_name(MetaProgression.ARMORY[requirement]))
		desc.text += " Requires " + ", ".join(names) + "."
	buy.pressed.connect(func() -> void:
		if meta.purchase(id):
			_feedback.text = _item_name(item) + " purchased."
		else:
			_feedback.text = "Purchase declined. Check credits and prerequisites."
		refresh())


func _item_name(item: Dictionary) -> String:
	if String(item.kind) == "weapon":
		var weapon := ContentRegistry.get_weapon(StringName(String(item.target)))
		if weapon != null:
			return weapon.display_name
	elif String(item.kind) == "skill":
		var skill := ContentRegistry.get_skill(StringName(String(item.target)))
		if skill != null:
			return skill.display_name
	return String(item.name)
