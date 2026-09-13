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


DECL = re.compile(
    r"^(?P<indent>[ \t]*)"
    r"(?P<kw>static\s+func|func|var|const|class|enum|signal)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
)
BLOCK = re.compile(r"^(?:if|elif|else|for|while|match)\b")


def _strip_annotations(line):
    """Drop leading @export / @onready / @export_range(...) tokens from a statement."""
    text = line.strip()
    while text.startswith("@"):
        depth = 0
        index = 0
        while index < len(text):
            char = text[index]
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            elif char == " " and depth == 0:
                break
            index += 1
        text = text[index:].strip()
    return text


def member_declarations(source):
    """Yield (name, line_number) for every class-level declaration in one script.

    Mirrors the Godot parser's scope rule: a declaration is a member when the innermost
    enclosing block is the file (or an inner `class`), and a local when it sits inside a
    function body — locals may legally reuse a name across functions or blocks. Function
    and control-flow openers push a block whether or not their header ends in `:`, so a
    signature spread over several lines still scopes its body correctly.
    """
    stack = []  # (indent, kind) where kind is "class", "func" or "local"
    pending = None  # indent of an opener whose header has not closed yet
    for number, raw in enumerate(source.splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" \t"))
        statement = _strip_annotations(raw)
        if pending is not None:
            if statement.rstrip().endswith(":"):
                pending = None  # the header closes here; its body starts below
            continue
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parent = stack[-1][1] if stack else None
        match = DECL.match(statement)
        if match:
            if parent in (None, "class"):
                yield match.group("name"), number
            keyword = match.group("kw")
            if keyword in ("func", "static func"):
                stack.append((indent, "func"))
            elif keyword == "class":
                stack.append((indent, "class"))
            else:
                continue
            pending = None if statement.rstrip().endswith(":") else indent
            continue
        if BLOCK.match(statement):
            stack.append((indent, "local" if parent in ("func", "local") else "block"))
            pending = None if statement.rstrip().endswith(":") else indent


class DuplicateDeclarationTests(unittest.TestCase):
    """The engine rejects a file that declares the same member twice.

    Godot's parser fails the whole script with `Function "x" has the same name as a
    previously declared function` (or the `var` equivalent). A duplicated block left
    behind by a hand splice is invisible to gdlint and to every static gate in `tool/`,
    and the only symptom is a suite failing to load at runtime: this is what turned a
    green 1655-test Godot run into `1612 total, 13 failed` after the manager splits.
    """

    SCRIPT_ROOTS = ("scripts", "tests")

    def test_every_gdscript_file_has_unique_class_level_declarations(self):
        seen = []
        checked = 0
        for root in self.SCRIPT_ROOTS:
            for path in sorted((ROOT / root).rglob("*.gd")):
                checked += 1
                names = {}
                for name, number in member_declarations(
                    path.read_text(encoding="utf-8", errors="replace")
                ):
                    if name in names:
                        rel = path.relative_to(ROOT).as_posix()
                        seen.append(
                            "%s: `%s` declared on lines %d and %d"
                            % (rel, name, names[name], number)
                        )
                    names[name] = number
        self.assertGreater(checked, 100, "expected to scan the whole GDScript tree")
        self.assertEqual([], seen, "duplicate member declarations:\n" + "\n".join(seen))

    def test_the_scan_flags_a_duplicated_member(self):
        """Self-check: the scanner must actually catch the bug it guards against."""
        sample = (
            "class_name Sample\n"
            "extends RefCounted\n"
            "\n"
            "var _cache := {}\n"
            "\n"
            "func walk(host: Node) -> void:\n"
            "\tvar _cache := {}\n"
            "\tif host != null:\n"
            "\t\tvar _cache := {}\n"
            "\n"
            "var _cache := {}\n"
        )
        found = list(member_declarations(sample))
        names = [name for name, _ in found]
        self.assertEqual([("_cache", 4), ("walk", 6), ("_cache", 11)], found)
        self.assertEqual(
            2, names.count("_cache"), "the two locals inside walk() must be skipped"
        )


if __name__ == "__main__":
    unittest.main()
