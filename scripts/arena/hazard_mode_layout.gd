class_name HazardModeLayout
extends ValidatedConfig

## Mode-specific hazard pressure. Lives under res://data/hazards/modes/ keyed by
## GameMode id and is read by ArenaHazards.apply_mode_pressure().
##
## Before this existed, "boss rush gets two spike beds" was a `match mode_id` arm in the
## hazard system, so differentiating a mode's arena pressure meant editing core code.
## A mode with no file here simply keeps its arena's layout — the absence is data, not
## an error, which is why the loader treats a missing mode file as normal.

@export var mode_id: StringName = &""
@export var display_name: String = ""
## Appended after the arena's own layout, so a mode can only ever add pressure to a
## level design rather than rewrite it.
@export var extra_placements: Array[HazardPlacement] = []


func placement_count() -> int:
	return extra_placements.size()


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(mode_id).is_empty():
		problems.append("mode_id is empty")
	if not GameMode.is_known(mode_id):
		problems.append("mode_id '%s' is not a GameMode" % String(mode_id))
	if extra_placements.is_empty():
		problems.append("a mode layout with no placements is dead data — delete the file")
	for placement in extra_placements:
		if placement == null:
			problems.append("null HazardPlacement in extra_placements")
			continue
		problems.append_array(placement.validate())
	return problems
