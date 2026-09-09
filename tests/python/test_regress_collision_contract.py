"""Regression: the 3D collision contract (CollisionLayers) is the only source of bits.

Before scripts/core/collision_layers.gd, the same bits were hand-written as numbers
in .tscn files and in code (`query.collision_mask = 1`, `collision_mask = 7  # world
+ player + enemy`). A one-bit typo changes game feel silently: the camera starts
reacting to the crowd, projectiles fall through pillars, enemies stop being blocked
by each other. Nothing in the engine or the type system notices, so this test is the
notice.

It pins four things:
  1. CollisionLayers declares one bit per layer, in the order [layer_names] declares
     them in project.godot (renaming a layer without moving the constant fails).
  2. No script assigns a numeric collision_layer / collision_mask any more — every
     one must name the constant.
  3. The authored scene bits equal the contract (scenes cannot reference GDScript
     constants, so this is the only link between player.tscn and CollisionLayers).
  4. The DELIBERATE decisions still hold: hero and enemies do not body-block each
     other, the camera ignores actors, pickups are polled not detected. Flip one of
     these on purpose and this test tells you to say so in the class doc too.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code_lines(text: str):
    """Yield (lineno, line) with comment text stripped, so doc examples that quote
    the old magic numbers do not trip the no-literals check."""
    for i, raw in enumerate(text.splitlines(), start=1):
        line = raw.split("#", 1)[0]
        if line.strip().startswith("##"):
            continue
        yield i, line


## CollisionLayers constant -> (bit index, the name authored in [layer_names]).
LAYERS = ["WORLD_STATIC", "PLAYER", "ENEMY", "PLAYER_ATTACK", "ENEMY_ATTACK", "PICKUP"]
LAYER_INDEX = {name: i for i, name in enumerate(LAYERS)}
LAYER_LABELS = {
    "WORLD_STATIC": "WorldStatic",
    "PLAYER": "Player",
    "ENEMY": "Enemy",
    "PLAYER_ATTACK": "PlayerAttack",
    "ENEMY_ATTACK": "EnemyAttack",
    "PICKUP": "Pickup",
}


class ContractDeclarationTests(unittest.TestCase):
    def setUp(self):
        self.cls = read("scripts/core/collision_layers.gd")

    def test_one_bit_per_layer_in_layer_names_order(self):
        for index, name in enumerate(LAYERS):
            expected = 1 << index
            m = re.search(rf"^const {name} := (.+)$", self.cls, re.M)
            self.assertIsNotNone(m, f"CollisionLayers.{name} is missing")
            expr = m.group(1).split("#")[0].strip()
            self.assertEqual(expr, f"1 << {index}",
                             msg=f"{name} must stay `1 << {index}` (={expected}) to match [layer_names]")

    def test_project_layer_names_agree_with_the_constants(self):
        text = read("project.godot")
        section = text.split("[layer_names]", 1)
        self.assertEqual(len(section), 2, "[layer_names] vanished from project.godot")
        body = section[1].split("[", 1)[0]
        for index, name in enumerate(LAYERS, start=1):
            label = LAYER_LABELS[name]
            self.assertIn(f'3d_physics/layer_{index}="{label}"', body,
                          msg=f"3D layer {index} must be named {label} in project.godot "
                              f"(CollisionLayers.{name} is defined as 1 << {index - 1})")

    def test_masks_are_compositions_not_new_numbers(self):
        for name in ("PLAYER_BODY_MASK", "ENEMY_BODY_MASK", "PROJECTILE_HIT_MASK",
                     "CAMERA_QUERY_MASK", "SEPARATION_QUERY_MASK"):
            m = re.search(rf"^const {name} := (.+)$", self.cls, re.M)
            self.assertIsNotNone(m, f"CollisionLayers.{name} is missing")
            expr = m.group(1).split("#")[0].strip()
            for token in re.split(r"\s*\|\s*", expr):
                if token == "NO_LAYER":
                    continue
                self.assertIn(token, LAYERS,
                              msg=f"{name} composes {token!r}, which is not a declared layer")


class NoMagicBitsTests(unittest.TestCase):
    def test_scripts_never_assign_numeric_collision_layers(self):
        offenders = []
        for gd in sorted((ROOT / "scripts").rglob("*.gd")):
            for i, line in code_lines(gd.read_text(encoding="utf-8", errors="ignore")):
                m = re.search(r"collision_(?:layer|mask)\s*(?:=|\+=)\s*(.+)$", line)
                if not m:
                    continue
                value = m.group(1).strip()
                if re.search(r"\b\d+\b", value) and "CollisionLayers" not in value:
                    offenders.append(f"{gd.relative_to(ROOT)}:{i}: {line.strip()}")
        self.assertEqual(offenders, [], msg="numeric collision bits; use CollisionLayers.*:\n  " + "\n  ".join(offenders))

    def test_query_masks_are_named_too(self):
        # The bug class is queries as much as bodies: these three used to hardcode 1/4/7.
        for rel, needle in (
            ("scripts/main/camera/camera_collision_solver.gd", "CollisionLayers.CAMERA_QUERY_MASK"),
            ("scripts/enemies/enemy_pack.gd", "CollisionLayers.SEPARATION_QUERY_MASK"),
            ("scripts/weapons/projectile.gd", "CollisionLayers.PROJECTILE_HIT_MASK"),
            ("scripts/weapons/projectile_pool.gd", "CollisionLayers.PROJECTILE_HIT_MASK"),
            ("scripts/arena/arena.gd", "CollisionLayers.WORLD_BODY_LAYER"),
            ("scripts/arena/arena_obstacles.gd", "CollisionLayers.WORLD_BODY_LAYER"),
            ("scripts/arena/arena_decorator.gd", "CollisionLayers.WORLD_BODY_LAYER"),
            ("scripts/pickups/pickup_manager.gd", "CollisionLayers.PICKUP_QUERY_MASK"),
        ):
            self.assertIn(needle, read(rel), msg=f"{rel} must source its bits from CollisionLayers")


class SceneBitTests(unittest.TestCase):
    """Parse the root node's bits out of each .tscn (they are plain lines)."""

    def scene_bits(self, rel: str):
        text = read(rel)
        body = text.split('[node name="', 1)
        self.assertGreater(len(body), 1, f"{rel}: no root node block")
        root = body[1]
        layer = re.search(r"^collision_layer = (\d+)", root, re.M)
        mask = re.search(r"^collision_mask = (\d+)", root, re.M)
        return (int(layer.group(1)) if layer else 0,
                int(mask.group(1)) if mask else 0)

    def test_player_body_bits(self):
        self.assertEqual(self.scene_bits("scenes/player/player.tscn"), (2, 1),
                         msg="player.tscn must stay on PLAYER, colliding with WORLD_STATIC only")

    def test_enemy_base_bits(self):
        self.assertEqual(self.scene_bits("scenes/enemies/enemy_base.tscn"), (4, 5),
                         msg="enemy_base.tscn must stay on ENEMY, colliding with WORLD_STATIC|ENEMY")

    def test_enemy_archetypes_inherit_the_contract(self):
        # Archetypes override shapes/materials, never the collision bits: an override
        # here silently un-syncs one archetype from the pack separation + blocking.
        for scene in sorted((ROOT / "scenes/enemies").glob("*.tscn")):
            if scene.name == "enemy_base.tscn":
                continue
            text = scene.read_text(encoding="utf-8", errors="ignore")
            self.assertNotIn("collision_layer", text,
                             msg=f"{scene.name}: re-declaring collision bits breaks the shared contract")

    def test_arena_world_body_bits(self):
        text = read("scenes/arena/arena.tscn")
        m = re.search(r'\[node name="Collision" type="StaticBody3D"[^\]]*\]\ncollision_layer = (\d+)\ncollision_mask = (\d+)', text)
        self.assertIsNotNone(m, msg="arena.tscn: the world Collision body must keep explicit bits")
        self.assertEqual((int(m.group(1)), int(m.group(2))), (1, 0))


class DecisionTests(unittest.TestCase):
    """The gameplay decisions encoded in the masks. Change one on purpose and the
    CollisionLayers docblock has to change with it — that is the whole point."""

    def setUp(self):
        self.cls = read("scripts/core/collision_layers.gd")

    def bits(self, name: str) -> int:
        """Evaluate a CollisionLayers mask constant the way GDScript would: `1 << n`
        for the layer definitions, `A | B` compositions for the masks."""
        expr = re.search(rf"^const {name} := (.+)$", self.cls, re.M).group(1).split("#")[0].strip()
        value = 0
        for token in re.split(r"\s*\|\s*", expr):
            token = token.strip()
            if token == "NO_LAYER":
                continue
            shift = re.fullmatch(r"1 << (\d+)", token)
            if shift:
                value |= 1 << int(shift.group(1))
                continue
            self.assertIn(token, LAYER_INDEX, f"{name}: {token!r} is not a declared layer")
            value |= 1 << LAYER_INDEX[token]
        return value

    def test_hero_and_enemies_do_not_body_block(self):
        self.assertEqual(self.bits("PLAYER_BODY_MASK") & self.bits("ENEMY"), 0,
                         msg="the player must not be pushed by enemy bodies (crowd spacing is EnemyPack steering)")
        self.assertEqual(self.bits("ENEMY_BODY_MASK") & self.bits("PLAYER"), 0,
                         msg="enemies must not body-block the hero; see the CollisionLayers docblock")

    def test_enemies_block_each_other_and_the_world_blocks_everyone(self):
        self.assertTrue(self.bits("ENEMY_BODY_MASK") & self.bits("ENEMY"))
        self.assertTrue(self.bits("ENEMY_BODY_MASK") & self.bits("WORLD_STATIC"))
        self.assertTrue(self.bits("PLAYER_BODY_MASK") & self.bits("WORLD_STATIC"))

    def test_camera_queries_geometry_only(self):
        cam = self.bits("CAMERA_QUERY_MASK")
        self.assertEqual(cam, self.bits("WORLD_STATIC"),
                         msg="a horde must never shove the camera; geometry only")

    def test_separation_queries_peers_only(self):
        self.assertEqual(self.bits("SEPARATION_QUERY_MASK"), self.bits("ENEMY"))

    def test_projectiles_may_hit_actors_and_geometry(self):
        hit = self.bits("PROJECTILE_HIT_MASK")
        for name in ("WORLD_STATIC", "PLAYER", "ENEMY"):
            self.assertTrue(hit & self.bits(name), f"projectiles must be able to touch {name}")

    def test_pickups_are_polled_not_detected(self):
        self.assertEqual(self.bits("PICKUP_QUERY_MASK"), 0,
                         msg="pickup collection is a radius poll; a nonzero mask invites a phantom overlap path")
        self.assertIn("_tick_collect", read("scripts/pickups/pickup.gd"))


if __name__ == "__main__":
    unittest.main()
