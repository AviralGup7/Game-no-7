"""Regression: the manager splits keep their test-visible surface.

`scripts/enemies/enemy_base.gd`, `scripts/main/camera_rig.gd`,
`scripts/visuals/effect_director.gd`, `scripts/arena/arena_decorator.gd`,
`scripts/player/player.gd` and `scripts/core/game_root.gd` were split into typed
`RefCounted` collaborators (2026-09-13 changelog entry). The GDScript suites reach
into those managers directly, so a split is only behavior-identical while these
contracts hold:

  * Player declares `_attack_buffer` / `_health_now` / `_gameplay_time` /
    `_locomotion` / `_try_attack` / `_cancel_combat` / `_on_died` by name — the
    integration and UI runners call or read them, so they may delegate but must
    not move off Player.
  * EnemyBase still supports construction as a bare node plus HealthComponent and
    EnemyStateMachine (no feedback/audio/status children), which is what every
    fixture does; the required-vs-optional component split is what keeps it valid.
  * No refactored file reintroduces string dispatch. `tool/check_typed_arch.py`
    bans `.call("...")` and `has_method(` across `scripts/`; this pin keeps the
    refactored surface honest on top of that gate.
  * The managers still delegate to those components, so a future revert of a split
    is visible here instead of silently re-inflating the managers.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

PLAYER = "scripts/player/player.gd"
ENEMY = "scripts/enemies/enemy_base.gd"
CAMERA = "scripts/main/camera_rig.gd"
EFFECTS = "scripts/visuals/effect_director.gd"
DECORATOR = "scripts/arena/arena_decorator.gd"
GAME_ROOT = "scripts/core/game_root.gd"

MANAGERS = (ENEMY, CAMERA, EFFECTS, DECORATOR, PLAYER, GAME_ROOT)

# Extracted collaborators: the split surface this suite pins along with the managers.
COMPONENTS = (
    "scripts/enemies/enemy_combat_response.gd",
    "scripts/enemies/enemy_motion.gd",
    "scripts/enemies/enemy_brain.gd",
    "scripts/enemies/enemy_presentation.gd",
    "scripts/enemies/enemy_elite_kit.gd",
    "scripts/enemies/enemy_debug_view.gd",
    "scripts/main/camera/camera_hitstop_locator.gd",
    "scripts/main/camera/camera_lock_on_controller.gd",
    "scripts/main/camera/camera_rig_debug.gd",
    "scripts/visuals/effect_event_handlers.gd",
    "scripts/visuals/effect_placement.gd",
    "scripts/visuals/effect_priorities.gd",
    "scripts/visuals/effect_readability.gd",
    "scripts/visuals/effect_skill_catalog.gd",
    "scripts/visuals/effect_templates.gd",
    "scripts/arena/decorator_props.gd",
    "scripts/arena/arena_warehouse_yard.gd",
)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def func_body(rel: str, name: str) -> str:
    text = read(rel)
    m = re.search(r"\nfunc %s\(.*?(?=\nfunc |\Z)" % re.escape(name), text, re.S)
    if m is None:
        raise AssertionError("func %s() not found in %s" % (name, rel))
    return m.group(0)


def code_only(text: str) -> str:
    """Drop `#` comments the way the typed-architecture gate does before grepping."""
    lines = []
    for line in text.splitlines():
        if line.lstrip().startswith("#"):
            continue
        lines.append(line.split("#", 1)[0])
    return "\n".join(lines)


class PlayerPrivateSurfaceTests(unittest.TestCase):
    """The four private members the suites poke must stay on Player itself."""

    PRIVATES = (
        "_attack_buffer",
        "_health_now",
        "_gameplay_time",
        "_locomotion",
        "_try_attack",
        "_cancel_combat",
        "_on_died",
    )

    def test_player_declares_the_members_the_suites_poke(self):
        txt = read(PLAYER)
        for name in self.PRIVATES:
            self.assertRegex(
                txt,
                r"(?m)^(?:var|func)\s+%s\b" % re.escape(name),
                msg="Player must keep %s: tests/integration/test_player.gd pokes it directly" % name,
            )

    def test_the_player_suite_still_pokes_them(self):
        txt = read("tests/integration/test_player.gd")
        for name in self.PRIVATES:
            self.assertIn(
                name,
                txt,
                msg="test_player.gd stopped using %s — update the INVIOLABLE list deliberately" % name,
            )


class EnemyBareConstructionTests(unittest.TestCase):
    """Fixtures build EnemyBase.new() + HealthComponent + EnemyStateMachine only."""

    def test_fixtures_still_build_enemies_bare(self):
        fixture = read("tests/integration_stages.gd")
        for needle in ("EnemyBase.new()", "HealthComponent.new()", "EnemyStateMachine.new()"):
            self.assertIn(needle, fixture)

    def test_enemy_base_keeps_the_required_optional_component_split(self):
        txt = read(ENEMY)
        self.assertIn("func _check_required_components() -> bool:", txt)
        for required in ("var _health: HealthComponent = null", "var _machine: EnemyStateMachine = null"):
            self.assertIn(required, txt)
        for optional in (
            "var _feedback: EnemyFeedback = null",
            "var _audio: EnemyAudio = null",
            "var _status: StatusManager = null",
        ):
            self.assertIn(optional, txt)

    def test_component_lookup_is_null_safe(self):
        resolve = func_body(ENEMY, "_resolve_components")
        for needle in ('get_node_or_null("HealthComponent")', 'get_node_or_null("EnemyStateMachine")'):
            self.assertIn(needle, resolve)

    def test_debug_snapshot_survives_a_bare_enemy(self):
        # The headless fixtures call this on enemies with no optional components.
        self.assertIn("func get_debug_snapshot", read(ENEMY))


class RefactorSurfaceTests(unittest.TestCase):
    BANNED = (re.compile(r"\.call\(\s*[\"&]"), re.compile(r"\bhas_method\("))

    def test_no_string_dispatch_in_the_refactored_surface(self):
        for rel in MANAGERS + COMPONENTS:
            code = code_only(read(rel))
            for pattern in self.BANNED:
                self.assertIsNone(
                    pattern.search(code),
                    msg="%s reintroduced string dispatch (%s)" % (rel, pattern.pattern),
                )

    def test_managers_still_delegate_to_their_components(self):
        self.assertIn("var _response := EnemyCombatResponse.new()", read(ENEMY))
        self.assertIn("var _lock_on := CameraLockOnController.new()", read(CAMERA))
        self.assertIn("var _events := EffectEventHandlers.new()", read(EFFECTS))
        self.assertIn("var _props := DecoratorProps.new()", read(DECORATOR))


if __name__ == "__main__":
    unittest.main()
