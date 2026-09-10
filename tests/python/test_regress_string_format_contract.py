"""The string-format contract gate: GDScript's `%` operator, pinned offline.

`tool/check_string_formats.py` checks every string literal followed by `%`
against the pinned engine's exact `String::sprintf` semantics (verified in
the 4.4.1-stable source — `String::sprintf`, `OperatorEvaluatorStringFormat`,
and the parser's "Allow for trailing comma"):

  * an Array operand must match the placeholder count exactly — too few is
    "not enough arguments for format string", too many is "not all arguments
    converted during string formatting";
  * a scalar operand is wrapped into a one-element Array, so it demands
    exactly one placeholder;
  * `%d/%o/%x/%X/%f` require numbers, `%v` requires a vector, `%c` a number
    or single character; `%%` is a literal percent; `*` consumes an extra
    value; unknown type characters and a trailing `%` are rejected;
  * any of these is a runtime ERROR in the engine (`ERR_FAIL_MSG`), not a
    warning — which is how `tests/unit/test_wave_mutators.gd` shipped a
    one-placeholder format fed two array elements and nobody noticed: the
    test's assertion never reads the `why` string.

These tests pin the gate: the tree stays clean, and every error class is
proven catchable on synthetic content.
"""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "check_string_formats", ROOT / "tool" / "check_string_formats.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class GateFixture:
    def __init__(self, mod, source: str) -> None:
        self.gate = mod.FormatGate()
        self.gate.check_file("synthetic.gd", source)


class RepoGateTests(unittest.TestCase):
    """The checked-in tree runs the gate clean."""

    def test_gate_is_clean_on_the_tree(self) -> None:
        r = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "check_string_formats.py")],
            cwd=ROOT, capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(r.returncode, 0,
                         "string-format gate failed:\n" + r.stdout[-4000:])
        self.assertIn("string-format contract: clean", r.stdout)

    def test_gate_checks_the_real_volume(self) -> None:
        mod = load_gate_module()
        gate = mod.FormatGate()
        gate.load_repo()
        self.assertEqual(gate.errors, [])
        self.assertGreater(gate.checked, 800,
                           "the tree formats hundreds of messages; a collapse "
                           "in coverage means the scanner regressed")

    def test_the_shipped_bug_stays_fixed(self) -> None:
        # tests/unit/test_wave_mutators.gd:137 once fed two values to a
        # one-placeholder format; the gate now pins the corrected shape.
        txt = (ROOT / "tests/unit/test_wave_mutators.gd").read_text(encoding="utf-8")
        self.assertIn('"one_sided=%s/%s" % [one_sided.status_targets_enemies, '
                      'one_sided.status_targets_player]', txt)


class ArityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def errors_for(self, body: str) -> list[str]:
        src = "extends RefCounted\nfunc f() -> String:\n\tvar x := 1\n\tvar y := 2\n\treturn " + body + "\n"
        return GateFixture(self.mod, src).gate.errors

    def test_array_arity_match_is_accepted(self) -> None:
        self.assertEqual(self.errors_for('"a=%s b=%s" % [x, y]'), [])

    def test_array_too_few_arguments_is_caught(self) -> None:
        errs = self.errors_for('"a=%s b=%s" % [x]')
        self.assertTrue(any("not enough arguments" in e for e in errs), errs)

    def test_array_too_many_arguments_is_caught(self) -> None:
        errs = self.errors_for('"a=%s" % [x, y]')
        self.assertTrue(any("not all arguments converted" in e for e in errs), errs)

    def test_scalar_needs_exactly_one_placeholder(self) -> None:
        self.assertEqual(self.errors_for('"a=%s" % x'), [])
        errs = self.errors_for('"a=" % x')
        self.assertTrue(any("not all arguments converted" in e for e in errs), errs)
        errs = self.errors_for('"a=%s b=%s" % x')
        self.assertTrue(any("not enough arguments" in e for e in errs), errs)

    def test_trailing_comma_is_legal_and_adds_no_element(self) -> None:
        self.assertEqual(self.errors_for('"a=%s b=%s" % [x, y,]'), [])

    def test_multiline_array_with_trailing_comma_is_accepted(self) -> None:
        src = ('extends RefCounted\n'
               'func f() -> String:\n'
               '\tvar x := 1\n\tvar y := 2\n'
               '\treturn "a=%s b=%s" % [\n\t\tx, y,\n\t]\n')
        self.assertEqual(GateFixture(self.mod, src).gate.errors, [])

    def test_double_percent_is_an_escape_not_a_placeholder(self) -> None:
        self.assertEqual(self.errors_for('"100%% done: %s" % x'), [])
        errs = self.errors_for('"100%% done" % x')
        self.assertTrue(any("not all arguments converted" in e for e in errs), errs)

    def test_dynamic_width_star_consumes_an_extra_value(self) -> None:
        self.assertEqual(self.errors_for('"a=%*d" % [5, x]'), [])
        errs = self.errors_for('"a=%*d" % [x]')
        self.assertTrue(any("not enough arguments" in e for e in errs), errs)


class PlaceholderSyntaxTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def errors_for(self, fmt: str) -> list[str]:
        src = f'extends RefCounted\nfunc f() -> String:\n\treturn "{fmt}" % [1]\n'
        return GateFixture(self.mod, src).gate.errors

    def test_unknown_type_character_is_caught(self) -> None:
        errs = self.errors_for("a=%q")
        self.assertTrue(any("unsupported format character" in e for e in errs), errs)

    def test_incomplete_trailing_percent_is_caught(self) -> None:
        errs = self.errors_for("a=%")
        self.assertTrue(any("incomplete format" in e for e in errs), errs)

    def test_all_engine_types_are_accepted(self) -> None:
        errs = self.errors_for("%d %o %x %X %f %s %c")
        # 7 placeholders fed 1 value -> arity error, but NO syntax error
        self.assertTrue(all("unsupported format character" not in e for e in errs), errs)

    def test_vector_type_is_accepted(self) -> None:
        errs = self.errors_for("%v")
        self.assertTrue(all("unsupported format character" not in e for e in errs), errs)


class LiteralTypeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def errors_for(self, body: str) -> list[str]:
        src = "extends RefCounted\nfunc f() -> String:\n\treturn " + body + "\n"
        return GateFixture(self.mod, src).gate.errors

    def test_string_into_numeric_placeholder_is_caught(self) -> None:
        errs = self.errors_for('"n=%d" % ["nope"]')
        self.assertTrue(any("a number is required" in e for e in errs), errs)

    def test_number_into_vector_placeholder_is_caught(self) -> None:
        errs = self.errors_for('"v=%v" % [5]')
        self.assertTrue(any("%v requires a vector" in e for e in errs), errs)

    def test_vector_literal_into_vector_placeholder_is_accepted(self) -> None:
        self.assertEqual(self.errors_for('"v=%v" % [Vector3(1.0, 2.0, 3.0)]'), [])

    def test_long_string_into_char_placeholder_is_caught(self) -> None:
        errs = self.errors_for('"c=%c" % ["ab"]')
        self.assertTrue(any("%c requires" in e for e in errs), errs)
        self.assertEqual(self.errors_for('"c=%c" % ["a"]'), [])

    def test_expr_elements_are_not_falsely_typed(self) -> None:
        self.assertEqual(self.errors_for('"n=%d" % [some_call(x)]'), [])


class NotFormatTests(unittest.TestCase):
    """Things that look adjacent to `%` but are not string formatting."""

    def setUp(self) -> None:
        self.mod = load_gate_module()

    def errors_for(self, body: str) -> list[str]:
        src = "extends RefCounted\nfunc f() -> void:\n\tvar x := 5\n\t" + body + "\n"
        return GateFixture(self.mod, src).gate.errors

    def test_integer_modulo_is_not_checked(self) -> None:
        self.assertEqual(self.errors_for("var y := x % 2"), [])

    def test_stringname_literal_is_not_a_format_operand(self) -> None:
        self.assertEqual(self.errors_for('var n := &"a %s b"'), [])

    def test_nodepath_literal_is_not_a_format_operand(self) -> None:
        self.assertEqual(self.errors_for('var n := ^"a %s b"'), [])

    def test_comment_content_is_ignored(self) -> None:
        self.assertEqual(self.errors_for('var y := 1 # "broken %s %s" % [x]'), [])

    def test_precedence_trap_is_still_caught_per_literal(self) -> None:
        # "a" + "b" % [..] binds as "a" + ("b" % [..]); the second literal is
        # the format and has zero placeholders for one element
        errs = self.errors_for('var s := "pre: " + "b" % [x]')
        self.assertTrue(any("not all arguments converted" in e for e in errs), errs)
        ok = self.errors_for('var s := "pre: " + "b=%s" % [x]')
        self.assertEqual(ok, [])


if __name__ == "__main__":
    unittest.main()
