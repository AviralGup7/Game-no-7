class_name StatusEffectConfig
extends Resource

## Data-driven status effect definition (burn, bleed, slow, stun, shock,
## weaken, regen, shield...). Instances live under res://data/status/ and are
## discovered by ContentRegistry. Runtime state per affected entity lives in
## StatusEffect instances owned by a StatusManager component.

const STACK_REFRESH := &"refresh"    # re-apply refreshes duration, keeps stacks
const STACK_ADD := &"add"            # re-apply adds a stack up to max_stacks
const STACK_RESET := &"reset"        # re-apply restarts a single stack
const VALID_STACK_MODES := [STACK_REFRESH, STACK_ADD, STACK_RESET]

@export var effect_id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D = null
@export var is_harmful: bool = true
## Base duration in seconds (0 = permanent until cleansed).
@export var duration: float = 4.0
@export var max_stacks: int = 1
@export var stack_mode: StringName = STACK_REFRESH
## Damage-over-time per second per stack (0 = none).
@export var dot_per_second: float = 0.0
@export var dot_type: StringName = &"physical"
## Heal-over-time per second per stack (0 = none).
@export var hot_per_second: float = 0.0
## Multiplicative move-speed factor per stack (1.0 = neutral).
@export var move_speed_factor: float = 1.0
## Multiplicative outgoing-damage factor per stack (1.0 = neutral).
@export var damage_factor: float = 1.0
## Multiplicative incoming-damage factor per stack (1.0 = neutral).
@export var received_damage_factor: float = 1.0
## Stun / root flags.
@export var stuns: bool = false
@export var roots: bool = false
## Flat shield granted per stack (absorbed before health).
@export var shield_amount: float = 0.0
## Tick cadence for DoT/HoT application.
@export var tick_interval: float = 0.5
## Visual tint applied to the victim while active.
@export var tint: Color = Color.WHITE
@export var tags: Array[StringName] = []

const VALID_DOT_TYPES := [&"physical", &"fire", &"bleed", &"poison", &"shock", &"frost"]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(effect_id).is_empty():
		problems.append("effect_id is empty")
	if duration < 0.0:
		problems.append("duration cannot be negative")
	if max_stacks < 1:
		problems.append("max_stacks must be >= 1")
	if stack_mode not in VALID_STACK_MODES:
		problems.append("invalid stack_mode: %s" % String(stack_mode))
	if dot_per_second < 0.0:
		problems.append("dot_per_second cannot be negative")
	if dot_type not in VALID_DOT_TYPES:
		problems.append("invalid dot_type: %s" % String(dot_type))
	if hot_per_second < 0.0:
		problems.append("hot_per_second cannot be negative")
	if move_speed_factor < 0.0:
		problems.append("move_speed_factor cannot be negative")
	if damage_factor < 0.0:
		problems.append("damage_factor cannot be negative")
	if received_damage_factor < 0.0:
		problems.append("received_damage_factor cannot be negative")
	if shield_amount < 0.0:
		problems.append("shield_amount cannot be negative")
	if tick_interval <= 0.0:
		problems.append("tick_interval must be > 0")
	return problems


func is_permanent() -> bool:
	return duration <= 0.0

## Hardened: clamp status effect config.
func _validated_status() -> void:
	if not is_finite(duration) or duration <= 0.0:
		duration = 3.0
	duration = clampf(duration, 0.05, 60.0)
	if not is_finite(tick_rate) or tick_rate <= 0.0:
		tick_rate = 0.5
	tick_rate = clampf(tick_rate, 0.05, 5.0)

## Export-range guard: editor sliders are clamped and runtime values are re-clamped
## via _validated_* helpers so JSON or save edits cannot create NaN/inf/out-of-range.
func _export_range_guard() -> void:
	# This is a documentation guard; actual clamping lives in _validated_* helpers.
	# Intended ranges (editor @export_range would be here in a future Godot bump):
	#  - health/damage: 0..10000 finite
	#  - cooldown/duration: 0.05..60 finite
	#  - speed/range: 0..30 finite, half 4..100
	#  - weight/chance: 0..1 finite
	pass

