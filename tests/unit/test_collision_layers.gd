extends RefCounted

## Headless unit tests for the collision contract (CollisionLayers). Pure integer
## arithmetic + string helpers, no nodes and no physics server, so it runs in the
## synchronous UNIT_SUITES phase.
##
## The .tscn side of the contract (the authored bits must equal these constants) is
## pinned by tests/python/test_regress_collision_contract.py, which can read scene
## text but cannot evaluate GDScript; this file is the mirror image — it can
## evaluate GDScript but has no business parsing scenes.

static func suite() -> Array:
	var results: Array = []
	_bit_layout(results)
	_mask_composition(results)
	_describe(results)
	_contract_decisions(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _bit_layout(results: Array) -> void:
	# One bit each, in [layer_names] order — a shifted constant would silently
	# re-target every mask that composes it.
	_check(results, "layers are one bit each in authored order",
		CollisionLayers.WORLD_STATIC == 1 and CollisionLayers.PLAYER == 2
			and CollisionLayers.ENEMY == 4 and CollisionLayers.PLAYER_ATTACK == 8
			and CollisionLayers.ENEMY_ATTACK == 16 and CollisionLayers.PICKUP == 32)
	_check(results, "no two layers share a bit",
		CollisionLayers.WORLD_STATIC + CollisionLayers.PLAYER + CollisionLayers.ENEMY
			+ CollisionLayers.PLAYER_ATTACK + CollisionLayers.ENEMY_ATTACK + CollisionLayers.PICKUP
			== 63,
		"sum of six distinct low bits must be 63")
	_check(results, "NO_LAYER is empty", CollisionLayers.NO_LAYER == 0)


static func _mask_composition(results: Array) -> void:
	_check(results, "hero is blocked by geometry only",
		CollisionLayers.PLAYER_BODY_MASK == CollisionLayers.WORLD_STATIC)
	_check(results, "enemies are blocked by geometry and by peers",
		CollisionLayers.ENEMY_BODY_MASK == (CollisionLayers.WORLD_STATIC | CollisionLayers.ENEMY))
	_check(results, "projectiles ask about geometry and both teams",
		CollisionLayers.PROJECTILE_HIT_MASK == 7)
	_check(results, "camera queries geometry only",
		CollisionLayers.CAMERA_QUERY_MASK == CollisionLayers.WORLD_STATIC)
	_check(results, "separation queries peers only",
		CollisionLayers.SEPARATION_QUERY_MASK == CollisionLayers.ENEMY)
	_check(results, "pickups are not detected by physics",
		CollisionLayers.PICKUP_QUERY_MASK == CollisionLayers.NO_LAYER)
	_check(results, "ALL_ACTORS is both actor bodies",
		CollisionLayers.ALL_ACTORS == (CollisionLayers.PLAYER | CollisionLayers.ENEMY))


static func _describe(results: Array) -> void:
	_check(results, "has() answers single bits",
		CollisionLayers.has(7, CollisionLayers.WORLD_STATIC)
			and CollisionLayers.has(7, CollisionLayers.ENEMY)
			and not CollisionLayers.has(1, CollisionLayers.ENEMY))
	_check(results, "has() requires every bit of a composed layer",
		CollisionLayers.has(5, CollisionLayers.WORLD_STATIC | CollisionLayers.ENEMY)
			and not CollisionLayers.has(1, CollisionLayers.WORLD_STATIC | CollisionLayers.ENEMY))
	_check(results, "describe() names the bits",
		CollisionLayers.describe(5) == "WorldStatic|Enemy",
		"got " + CollisionLayers.describe(5))
	_check(results, "describe() reports an empty mask honestly",
		CollisionLayers.describe(CollisionLayers.NO_LAYER) == "none")
	_check(results, "describe() never returns empty for an unknown bit",
		CollisionLayers.describe(128).length() > 0)


static func _contract_decisions(results: Array) -> void:
	# These four assertions are the executable form of the docblock in
	# collision_layers.gd. If a decision is reversed ON PURPOSE, the docblock and
	# the python scene test have to move with it — that is the point of failing here.
	_check(results, "hero and enemies never body-block each other",
		not CollisionLayers.has(CollisionLayers.PLAYER_BODY_MASK, CollisionLayers.ENEMY)
			and not CollisionLayers.has(CollisionLayers.ENEMY_BODY_MASK, CollisionLayers.PLAYER),
		"crowd spacing belongs to EnemyPack steering, not the solver")
	_check(results, "world geometry blocks every actor",
		CollisionLayers.has(CollisionLayers.PLAYER_BODY_MASK, CollisionLayers.WORLD_STATIC)
			and CollisionLayers.has(CollisionLayers.ENEMY_BODY_MASK, CollisionLayers.WORLD_STATIC))
	_check(results, "a horde cannot shove the camera",
		not CollisionLayers.has(CollisionLayers.CAMERA_QUERY_MASK, CollisionLayers.ENEMY))
	_check(results, "reserved layers stay unused by body masks",
		not CollisionLayers.has(CollisionLayers.PLAYER_BODY_MASK, CollisionLayers.PLAYER_ATTACK)
			and not CollisionLayers.has(CollisionLayers.ENEMY_BODY_MASK, CollisionLayers.ENEMY_ATTACK)
			and not CollisionLayers.has(CollisionLayers.PROJECTILE_HIT_MASK, CollisionLayers.PICKUP))
	var snap: Dictionary = CollisionLayers.get_debug_snapshot()
	_check(results, "debug snapshot exposes the contract",
		snap.has("player_mask") and snap.has("enemy_mask") and snap.has("body_blocks_body")
			and bool(snap["body_blocks_body"]) == false)
