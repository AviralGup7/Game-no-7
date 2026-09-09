class_name Narrator
extends RefCounted

## Minimal narrative layer: short arena lore lines, wave beats, and mode intros
## delivered through EventBus.announcement. Pure static lookups — no tree access.
## Campaign mode gets a fuller beat sheet; other modes get light flavour.

const ARENA_LORE := {
	&"default_arena": {
		"name": "The Pit",
		"intro": "The Pit remembers every stand. Yours begins now.",
		"mid": "Blood has soaked these stones for generations.",
		"late": "The crowd wants a legend. Don't disappoint them.",
	},
	&"ember_crucible": {
		"name": "Ember Crucible",
		"intro": "The Crucible breathes fire. Vents erupt — use them, or burn.",
		"mid": "Ash falls like snow. The floor itself is a weapon.",
		"late": "The forges below roar. Something ancient stirs in the heat.",
	},
	&"frost_hollow": {
		"name": "Frost Hollow",
		"intro": "Cold that bites bone. Ichor pools slow the unwary.",
		"mid": "Frost claims the careless. Keep moving.",
		"late": "The Hollow freezes hope. Only will remains.",
	},
}

const MODE_INTRO := {
	&"standard": "One arena. Endless pressure. Make every stand count.",
	&"boss_rush": "No warm-up. Five Warlords. Prove you belong in the pantheon.",
	&"survival": "Five minutes. Mounting waves. Outlast the arena itself.",
	&"challenge": "Glass and fire. One blade. Twelve waves. No excuses.",
	&"campaign": "They sealed the gate. You are the last line. Hold the stand.",
	&"defend": "The beacon must not fall. Hold the centre — everything comes for the light.",
	&"collect": "Their bones carry relics. Reap them from the horde before it buries you.",
}

const CAMPAIGN_BEATS := {
	1: {"title": "Awakening", "line": "The outer gate falls. Footsteps in the dark."},
	2: {"title": "First Blood", "line": "Scouts die easy. The real horde is still coming."},
	3: {"title": "Archers", "line": "Bolts from the gallery. Clear the backline."},
	4: {"title": "The Charge", "line": "Heavies and dashers. Break their momentum."},
	5: {"title": "Warlord I", "line": "A champion of the Pit steps forward. End him."},
	6: {"title": "Aftershock", "line": "The champion falls. The horde does not stop."},
	7: {"title": "Split Spore", "line": "Things that divide when cut. Choose your swings."},
	8: {"title": "Powder Keg", "line": "Exploders in the mix. Kite them into their own."},
	9: {"title": "Gathering Storm", "line": "Every archetype at once. Stay calm."},
	10: {"title": "Warlord II", "line": "A second champion. Stronger. Angrier."},
	11: {"title": "Attrition", "line": "The gate holds — barely. Buy time with steel."},
	12: {"title": "Breach", "line": "Walls crack. The arena itself is failing."},
	13: {"title": "Last Reserves", "line": "Whatever you have left, spend it now."},
	14: {"title": "The Gauntlet", "line": "No mercy pack. Survive the next minute."},
	15: {"title": "Final Reckoning", "line": "Two Warlords. One last stand. The gate depends on you."},
}

const ENEMY_BLURBS := {
	&"warlord": "Arena Warlord — thrice-crowned killer of the Pit.",
	&"exploder": "Powder-gut — dies loud. Keep your distance.",
	&"splitter": "Sporekin — cut once, fight twice.",
	&"dasher": "Blink-blade — telegraphs, then commits.",
	&"ranged": "Gallery bow — soft, but never alone.",
}


static func arena_intro(arena_id: StringName) -> String:
	var lore: Dictionary = ARENA_LORE.get(arena_id, ARENA_LORE[&"default_arena"])
	return String(lore.get("intro", ""))


static func arena_mid(arena_id: StringName) -> String:
	var lore: Dictionary = ARENA_LORE.get(arena_id, ARENA_LORE[&"default_arena"])
	return String(lore.get("mid", ""))


static func arena_late(arena_id: StringName) -> String:
	var lore: Dictionary = ARENA_LORE.get(arena_id, ARENA_LORE[&"default_arena"])
	return String(lore.get("late", ""))


static func mode_intro(mode_id: StringName) -> String:
	return String(MODE_INTRO.get(mode_id, MODE_INTRO[&"standard"]))


static func campaign_beat(wave_number: int) -> Dictionary:
	return CAMPAIGN_BEATS.get(wave_number, {})


static func enemy_blurb(archetype_id: StringName) -> String:
	return String(ENEMY_BLURBS.get(archetype_id, ""))


## Emit the right announcement for a wave start given mode + arena context.
static func announce_wave(mode_id: StringName, arena_id: StringName, wave_number: int) -> void:
	if EventBus == null:
		return
	if mode_id == GameMode.MODE_CAMPAIGN:
		var beat := campaign_beat(wave_number)
		if not beat.is_empty():
			EventBus.announcement.emit(
				&"campaign_beat",
				"%s — %s" % [String(beat.get("title", "")), String(beat.get("line", ""))],
				&"warning" if wave_number % 5 == 0 else &"info"
			)
			return
	# Light flavour on milestone waves for other modes.
	if wave_number == 1:
		var intro := mode_intro(mode_id)
		var arena_line := arena_intro(arena_id)
		EventBus.announcement.emit(&"narrator", intro if not intro.is_empty() else arena_line, &"info")
	elif wave_number == 5:
		EventBus.announcement.emit(&"narrator", arena_mid(arena_id), &"info")
	elif wave_number == 10 or wave_number % 10 == 0:
		EventBus.announcement.emit(&"narrator", arena_late(arena_id), &"warning")


static func announce_run_start(mode_id: StringName, arena_id: StringName) -> void:
	if EventBus == null:
		return
	var line := mode_intro(mode_id)
	if line.is_empty():
		line = arena_intro(arena_id)
	EventBus.announcement.emit(&"narrator", line, &"info")


static func announce_victory(mode_id: StringName) -> void:
	if EventBus == null:
		return
	var line := "Victory. The stand holds."
	match mode_id:
		GameMode.MODE_BOSS_RUSH:
			line = "The pantheon yields. Five crowns are yours."
		GameMode.MODE_SURVIVAL:
			line = "Five minutes. You outlasted the arena."
		GameMode.MODE_CHALLENGE:
			line = "Challenge complete. The glass did not break you."
		GameMode.MODE_CAMPAIGN:
			line = "The gate holds. The Last Stand is won — for now."
	EventBus.announcement.emit(&"victory", line, &"victory")
