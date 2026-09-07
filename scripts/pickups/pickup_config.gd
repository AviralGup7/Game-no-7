class_name PickupConfig
extends Resource

## Data-driven pickup definition (health orb, coin cache, stamina brew, magnet,
## shield cell, XP gem...). Instances live under res://data/pickups/ and are
## discovered by ContentRegistry. PickupManager interprets `effect` + amount.

const EFFECT_HEAL := &"heal"
const EFFECT_CURRENCY := &"currency"
const EFFECT_STAMINA := &"stamina"
const EFFECT_XP := &"xp"
const EFFECT_SHIELD := &"shield"
const EFFECT_MAGNET := &"magnet"      # pulls all loose pickups to the player
const EFFECT_CLEANSE := &"cleanse"    # removes harmful status effects
const EFFECT_SCORE := &"score"
const VALID_EFFECTS := [EFFECT_HEAL, EFFECT_CURRENCY, EFFECT_STAMINA, EFFECT_XP, EFFECT_SHIELD, EFFECT_MAGNET, EFFECT_CLEANSE, EFFECT_SCORE]

@export var pickup_id: StringName = &""
@export var display_name: String = ""
@export var icon: Texture2D = null
@export var effect: StringName = EFFECT_HEAL
## Base effect magnitude (scaled by `level` at spawn time when > 0).
@export var amount: float = 25.0
## How long the pickup lasts on the ground before expiring (0 = never).
@export var lifetime: float = 20.0
## Collection radius around the player.
@export var collect_radius: float = 1.2
## Radius at which the pickup starts flying toward the player (0 = no magnet).
@export var magnet_radius: float = 3.5
## Magnet flight speed.
@export var magnet_speed: float = 9.0
## Visual tint for the fallback mesh.
@export var tint: Color = Color.WHITE
## Bob amplitude / speed for the idle animation.
@export var bob_amplitude: float = 0.15
@export var bob_speed: float = 2.5
## Drop weight for the default drop table.
@export var drop_weight: float = 1.0
@export var min_wave: int = 1
@export var disabled: bool = false
@export var tags: Array[StringName] = []


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(pickup_id).is_empty():
		problems.append("pickup_id is empty")
	if effect not in VALID_EFFECTS:
		problems.append("invalid effect: %s" % String(effect))
	if amount < 0.0:
		problems.append("amount cannot be negative")
	if lifetime < 0.0:
		problems.append("lifetime cannot be negative")
	if collect_radius <= 0.0:
		problems.append("collect_radius must be > 0")
	if magnet_radius < 0.0:
		problems.append("magnet_radius cannot be negative")
	if magnet_speed <= 0.0:
		problems.append("magnet_speed must be > 0")
	if bob_amplitude < 0.0:
		problems.append("bob_amplitude cannot be negative")
	if drop_weight < 0.0:
		problems.append("drop_weight cannot be negative")
	if min_wave < 1:
		problems.append("min_wave must be >= 1")
	return problems


func scaled_amount(level: int) -> float:
	if level <= 1:
		return amount
	return amount * (1.0 + 0.25 * float(level - 1))
