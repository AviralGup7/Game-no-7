class_name EnemyPresentation
extends RefCounted

## In-world feedback for EnemyBase: the ground telegraph ring every windup draws, and
## the archetype visual scale (initialize / elite bump). The one-line feedback/audio
## hooks stay on the host — the AI states call them by name and the headless harness
## string-calls `play_telegraph_feedback`, so they are part of the host's contract.
##
## Every hook here is tolerant: the feedback child is optional (headless fixtures omit
## it) and the bare headless tree has no EffectDirector at all.

## Ground ring in the same yellow/red language as bosses so grunt/heavy windups read
## at 30 FPS on sand arenas, not only as a mesh flash.
const RING_BASE_RADIUS := 1.35
## Boss rings are a two-disc tell: the outer halo sits this much wider.
const RING_BOSS_HALO_OFFSET := 0.45
## Telegraph radius = attack_range * this, clamped into the readable band below.
const RING_RANGE_FACTOR := 0.85
const RING_MIN_RADIUS := 1.1
const RING_MAX_RADIUS := 3.4
## A visually large archetype (ogre, commander) gets a wider ring than its reach.
const RING_LARGE_VISUAL_SCALE := 1.15
const RING_LARGE_SCALE_MULT := 1.25

const COLOR_RING_BOSS_HALO := Color(1.0, 0.95, 0.15)
const COLOR_RING_BOSS := Color(0.95, 0.08, 0.08)
## One ring: yellow-red ink so it still reads on sand without a second disc.
const COLOR_RING_GRUNT := Color(1.0, 0.55, 0.08)


## Shaped ground telegraph (the mesh flash itself stays on EnemyFeedback, which the
## host drives: play_telegraph_feedback() calls both).
func play_telegraph_ring(host: EnemyBase) -> void:
	if not host.is_inside_tree():
		return
	var director := host.get_tree().get_first_node_in_group("effect_director") as EffectDirector
	if director == null:
		return
	var radius := RING_BASE_RADIUS
	var cfg := host.get_config()
	if cfg != null:
		radius = clampf(cfg.attack_range * RING_RANGE_FACTOR, RING_MIN_RADIUS, RING_MAX_RADIUS)
		if cfg.visual_scale > RING_LARGE_VISUAL_SCALE:
			radius *= RING_LARGE_SCALE_MULT
	var is_boss := host.get_boss_controller() != null
	if not director.try_telegraph(is_boss):
		return
	var prio := EffectDirector.PRIORITY_BOSS if is_boss else EffectDirector.PRIORITY_SPAWN
	if is_boss:
		director.ring_at(host.global_position, COLOR_RING_BOSS_HALO, radius + RING_BOSS_HALO_OFFSET, prio)
		director.ring_at(host.global_position, COLOR_RING_BOSS, radius, prio)
	else:
		director.ring_at(host.global_position, COLOR_RING_GRUNT, radius, prio)


func apply_visual_scale(host: EnemyBase, scale_factor: float) -> void:
	var visual := host.get_visual_root()
	if visual != null and scale_factor > 0.0:
		visual.scale = Vector3.ONE * scale_factor


func _show_attack_telegraph_ring(host: EnemyBase) -> void:
	if not host.is_inside_tree():
		return
	var director := host.get_tree().get_first_node_in_group("effect_director") as EffectDirector
	if director == null:
		return
	var radius := RING_BASE_RADIUS
	var cfg := host.get_config()
	if cfg != null:
		radius = clampf(cfg.attack_range * RING_RANGE_FACTOR, RING_MIN_RADIUS, RING_MAX_RADIUS)
		if cfg.visual_scale > RING_LARGE_VISUAL_SCALE:
			radius *= RING_LARGE_SCALE_MULT
	var is_boss := host.get_boss_controller() != null
	if not director.try_telegraph(is_boss):
		return
	var prio := EffectDirector.PRIORITY_BOSS if is_boss else EffectDirector.PRIORITY_SPAWN
	if is_boss:
		director.ring_at(host.global_position, COLOR_RING_BOSS_HALO, radius + RING_BOSS_HALO_OFFSET, prio)
		director.ring_at(host.global_position, COLOR_RING_BOSS, radius, prio)
	else:
		director.ring_at(host.global_position, COLOR_RING_GRUNT, radius, prio)
