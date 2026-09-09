class_name CollisionLayers
extends RefCounted

## THE 3D COLLISION CONTRACT — every layer/mask bit in the project comes from here.
##
## Before this file existed, the same bits were written as magic numbers in .tscn
## files (`collision_layer = 4`, `collision_mask = 5`) and in code
## (`query.collision_mask = 1`, `# world + player + enemy`). A one-bit typo in a
## mask silently changes game feel — enemies stop blocking, the camera starts
## colliding with the crowd, projectiles fall through a pillar — and nothing
## failed loudly. These names make the contract readable at every use site, and
## `tests/python/test_regress_collision_contract.py` pins the authored scene bits
## to these values (scenes cannot reference GDScript constants, so the test IS
## the link between `player.tscn` and this file).
##
## Bit N of the mask matches bit N of a body's layer. Godot's UI numbers layers
## from 1 (layer_1 = bit value 1), which is what `[layer_names]` in project.godot
## declares; the constants below are the *bit values*.
##
## ---------------------------------------------------------------------------
## THE DELIBERATE DECISIONS (change one, and you must change the pinned test):
##
##   * PLAYER does not collide with ENEMY, and vice versa. Bodies block only on
##     WORLD_STATIC. Contact damage is resolved by math (MeleeResolver /
##     AreaDamage), and crowding is resolved by steering (EnemyPack separation on
##     ENEMY). Making bodies shove each other would fight that steering and put
##     the physics solver in charge of crowd spacing; the arena is a horde game
##     with up to `maximum_simultaneous_enemies` bodies, and soft steering is
##     both cheaper and more readable. If you ever want hard body-blocking,
##     add `ENEMY` to PLAYER_BODY_MASK and `PLAYER` to ENEMY_BODY_MASK together,
##     then re-tune EnemyPack.SEP_RADIUS (peer spacing becomes redundant).
##   * CAMERA queries WORLD_STATIC only. A horde must never push the player's
##     view around; pillars and walls must.
##   * PICKUP and PLAYER_ATTACK/ENEMY_ATTACK layers are declared but not yet
##     used: pickups are polled by radius (Pickup._tick_collect) and attacks are
##     arc/radius math, not hitbox areas. They are reserved here so nothing else
##     can claim the bit while that stays true.
## ---------------------------------------------------------------------------

# ---- Layers (bit values; keep in sync with [layer_names] in project.godot) ----

## Static arena geometry: walls, floor, pillars, landmark bodies, movers.
const WORLD_STATIC := 1 << 0
## The player body (Damageable protocol, CharacterBody3D).
const PLAYER := 1 << 1
## Any enemy body, including bosses (EnemyBase, CharacterBody3D).
const ENEMY := 1 << 2
## Reserved: player-side attack hitbox areas (no hitbox areas exist yet).
const PLAYER_ATTACK := 1 << 3
## Reserved: enemy-side attack hitbox areas (no hitbox areas exist yet).
const ENEMY_ATTACK := 1 << 4
## Reserved: world-space pickup areas (pickups are polled, not detected).
const PICKUP := 1 << 5

# ---- Body layers ----

const PLAYER_BODY_LAYER := PLAYER
const ENEMY_BODY_LAYER := ENEMY
const WORLD_BODY_LAYER := WORLD_STATIC
## Pooled pickups/projectiles are detection-only: they answer to no query and
## collide with nothing as bodies.
const NO_LAYER := 0

# ---- Body masks ----

## The hero is blocked by arena geometry and by nothing else (see the note above).
const PLAYER_BODY_MASK := WORLD_STATIC
## Enemies are blocked by arena geometry and by each other, so a pack piles up
## against a pillar instead of streaming through it.
const ENEMY_BODY_MASK := WORLD_STATIC | ENEMY
## Everything a projectile may be stopped or hit by.
const PROJECTILE_HIT_MASK := WORLD_STATIC | PLAYER | ENEMY

# ---- Query masks ----

## Third-person spring-arm: solid geometry only, never actors.
const CAMERA_QUERY_MASK := WORLD_STATIC
## EnemyPack soft separation: peers only.
const SEPARATION_QUERY_MASK := ENEMY
## Nothing is detected by physics; collection is a radius poll.
const PICKUP_QUERY_MASK := NO_LAYER

# ---- Convenience groups ----

## Every actor that can take damage.
const ALL_ACTORS := PLAYER | ENEMY
## Everything a spatial "can I see it" test should consider solid.
const OBSTRUCTORS := WORLD_STATIC


## True when `mask` includes every bit of `layer`. Used by debug UI + tests so a
## contract violation can be reported with the bit that went missing.
static func has(mask: int, layer: int) -> bool:
	return (mask & layer) == layer


## Human-readable bit list for `push_warning`/debug snapshots
## ("WorldStatic|Enemy") — never in a hot path (it builds strings).
static func describe(mask: int) -> String:
	if mask == NO_LAYER:
		return "none"
	var parts := PackedStringArray()
	if has(mask, WORLD_STATIC):
		parts.append("WorldStatic")
	if has(mask, PLAYER):
		parts.append("Player")
	if has(mask, ENEMY):
		parts.append("Enemy")
	if has(mask, PLAYER_ATTACK):
		parts.append("PlayerAttack")
	if has(mask, ENEMY_ATTACK):
		parts.append("EnemyAttack")
	if has(mask, PICKUP):
		parts.append("Pickup")
	if parts.is_empty():
		return "bits:%d" % mask
	return "|".join(parts)


## Snapshot for the debug/inspector path: the whole contract as data.
static func get_debug_snapshot() -> Dictionary:
	return {
		"player_layer": describe(PLAYER_BODY_LAYER),
		"player_mask": describe(PLAYER_BODY_MASK),
		"enemy_layer": describe(ENEMY_BODY_LAYER),
		"enemy_mask": describe(ENEMY_BODY_MASK),
		"projectile_mask": describe(PROJECTILE_HIT_MASK),
		"camera_mask": describe(CAMERA_QUERY_MASK),
		"separation_mask": describe(SEPARATION_QUERY_MASK),
		"body_blocks_body": has(PLAYER_BODY_MASK, ENEMY),
	}
