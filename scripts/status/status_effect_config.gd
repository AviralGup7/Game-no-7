class_name StatusEffectConfig
extends ValidatedConfig

## Data-driven status effect definition (burn, bleed, slow, stun, shock,
## weaken, regen, shield...). Instances live under res://data/status/ and are
## discovered by ContentRegistry. Runtime state per affected entity lives in
## StatusEffect instances owned by a StatusManager component.
##
## Extends ValidatedConfig so this audit runs at load (ContentLoader._register_resource()
## validates any ValidatedConfig, and ContentRegistry turns a problem into a startup
## error) instead of being re-run for every active effect on every physics tick, which is
## what StatusManager used to do to guard against "bad numbers from an old save" — a path
## that does not exist, because status state is never serialized.
##
## validate() still runs once per application (StatusManager.apply_effect) so a config
## built in code is held to the same rules as one authored in the editor.

const STACK_REFRESH := &"refresh"    # re-apply refreshes duration, keeps stacks
const STACK_ADD := &"add"            # re-apply adds a stack up to max_stacks
const STACK_RESET := &"reset"        # re-apply restarts a single stack
const VALID_STACK_MODES := [STACK_REFRESH, STACK_ADD, STACK_RESET]

@export var effect_id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D = null
@export var is_harmful: bool = true
## Base duration in seconds (0 = permanent until cleansed). The minimum is 0, not
## 0.05, because validate() and is_permanent() both define 0 as "permanent": a floor
## above it made the supported case unauthorisable in the inspector (same fix as
## HazardConfig.period).
@export_range(0.0, 300.0, 0.05) var duration: float = 4.0
@export_range(1, 20) var max_stacks: int = 1
@export var stack_mode: StringName = STACK_REFRESH
## Damage-over-time per second per stack (0 = none).
@export_range(0.0, 1000.0, 0.1) var dot_per_second: float = 0.0
@export var dot_type: StringName = &"physical"
## Heal-over-time per second per stack (0 = none).
@export_range(0.0, 1000.0, 0.1) var hot_per_second: float = 0.0
## Multiplicative move-speed factor per stack (1.0 = neutral).
@export_range(0.0, 10.0, 0.05) var move_speed_factor: float = 1.0
## Multiplicative outgoing-damage factor per stack (1.0 = neutral).
@export_range(0.0, 10.0, 0.05) var damage_factor: float = 1.0
## Multiplicative incoming-damage factor per stack (1.0 = neutral).
@export_range(0.0, 10.0, 0.05) var received_damage_factor: float = 1.0
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
	if is_permanent() and (stuns or roots):
		problems.append("permanent duration not allowed with stuns/roots — would stop gameplay")
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
	if shield_amount > 0.0 and duration <= 0.0:
		problems.append("permanent shield (duration 0 + shield) would stall damage — set finite duration")
	return problems


func is_permanent() -> bool:
	return duration <= 0.0
