class_name GameModeWavePlan
extends Resource

## One scripted wave of a mode: which archetypes walk in, and the beat the announcer reads over
## it. An inline sub-resource of a `GameModeConfig` (like `HazardPlacement` is of an arena), so it
## has no file of its own and the owning config calls `validate()`.
##
## Before this row existed, the campaign's encounters were a fifteen-arm `match wave_number` in
## `scripts/meta/game_mode.gd` and its narration was a *separate* fifteen-entry int-keyed
## Dictionary in `scripts/meta/narrator.gd`. Nothing connected them: renumbering a beat, adding a
## sixteenth wave, or deleting an arm left the other table intact, so the run either announced a
## chapter nobody fought or fought a wave with no line. Authoring an encounter and its beat in one
## record makes a mismatch a data error instead of a playtest find.


@export_range(1, 200, 1) var wave_number: int = 1
## Archetypes in spawn order. Empty = the mode's planner rule decides this wave, and the row is
## narration only (waves 11-13 of the shipped campaign are exactly that).
@export var archetypes: Array[StringName] = []
## Announcer copy for this wave. Both or neither: a chapter title with no line under it prints a
## headline into the void.
@export var beat_title: String = ""
@export_multiline var beat_line: String = ""


func has_beat() -> bool:
	return not beat_title.is_empty() or not beat_line.is_empty()


func validate() -> Array[String]:
	var problems: Array[String] = []
	if wave_number < 1:
		problems.append("wave_number must be >= 1")
	if archetypes.is_empty() and not has_beat():
		problems.append("wave %d spawns nothing and says nothing — delete the row" % wave_number)
	for archetype_id in archetypes:
		if String(archetype_id).is_empty():
			problems.append("empty archetype_id in archetypes")
	if beat_title.is_empty() != beat_line.is_empty():
		problems.append("wave %d authors one of beat_title/beat_line; the announcer prints them together"
				% wave_number)
	return problems
