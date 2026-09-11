"""The signal contract gate: every signal name and emit arity, pinned offline.

`tool/check_signals.py` exists because the tree's messaging — 133 declared
signals, an EventBus-centric architecture, ~210 calls through autoload
receivers, ~138 through implicit self — was checked only at runtime: the
pinned engine's docs (4.4.1-stable `Object.connect` / `Signal.emit`) make a
nonexistent signal name a runtime error, a wrong emit arity a runtime error,
and invoke connected Callables with exactly the signal's arguments (a method
that cannot accept them fails at emit time). gdparse/gdlint see none of it,
and the headless suites only exercise the connections their flows take.

These tests pin the gate the same way the sibling contract suites do: the
tree stays clean, and every error class is proven catchable on synthetic
content — phantom signal names (bare, chained, autoload, legacy string
forms), emit arity, connect-callable arity (including default-parameter
ranges and inherited engine methods), and the dynamic-receiver split where a
name that exists elsewhere stays legal.
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
        "check_signals", ROOT / "tool" / "check_signals.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


AUTOLOAD_TEXT = '[autoload]\n\nBus="*res://scripts/bus.gd"\n'

BUS_SCRIPT = (
    "extends Node\n"
    "signal run_started(mode_id: StringName)\n"
    "signal enemy_killed(killer_id: StringName, victim_id: StringName)\n"
)


class GateFixture:
    def __init__(self, mod, scripts=(), autoload_text=AUTOLOAD_TEXT):
        self.gate = mod.SignalGate()
        self.gate.graph.set_project_godot(autoload_text)
        if autoload_text == AUTOLOAD_TEXT:
            scripts = (("scripts/bus.gd", BUS_SCRIPT),) + tuple(scripts)
        for rel, text in scripts:
            self.gate.add_script(rel, text)
        self.gate.finalize()
        for rel, text in scripts:
            self.gate.check_script(rel, text)


class RepoGateTests(unittest.TestCase):
    """The checked-in tree runs the gate clean with real volume."""

    def test_gate_is_clean_on_the_tree(self) -> None:
        r = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "check_signals.py")],
            cwd=ROOT, capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(r.returncode, 0,
                         "signal gate failed:\n" + r.stdout[-4000:])
        self.assertIn("signal contract: clean", r.stdout)

    def test_gate_checks_the_real_volume(self) -> None:
        mod = load_gate_module()
        gate = mod.SignalGate()
        gate.load_repo()
        self.assertEqual(gate.errors, [])
        self.assertGreaterEqual(gate.bare_checked, 130)
        self.assertGreaterEqual(gate.autoload_checked, 200)
        self.assertGreaterEqual(gate.string_forms, 3)

    def test_manifest_carries_engine_signal_arities(self) -> None:
        mod = load_gate_module()
        engine = mod.ClassGraph(mod.ScriptFacts()).engine
        self.assertEqual(engine["Node"]["signals"].get("ready"), 0)
        self.assertEqual(engine["Area3D"]["signals"].get("body_entered"), 1)


class PhantomSignalTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_bare_phantom_is_caught(self) -> None:
        src = ("extends Node\n"
               "signal real_one\n"
               "func f() -> void:\n"
               "\tnot_a_signal.emit()\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("not_a_signal" in e and "phantom" in e
                            for e in fx.gate.errors), fx.gate.errors)

    def test_bare_declared_self_signal_is_accepted(self) -> None:
        src = ("extends Node\n"
               "signal real_one\n"
               "func f() -> void:\n"
               "\treal_one.emit()\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_signal_declared_elsewhere_is_warning_not_error(self) -> None:
        other = "extends Node\nsignal only_there\n"
        src = ("extends Node\n"
               "func f() -> void:\n"
               "\tonly_there.emit()\n")
        fx = GateFixture(self.mod, (("scripts/other.gd", other),
                                    ("scripts/a.gd", src)))
        self.assertEqual(fx.gate.errors, [])
        self.assertTrue(any("only_there" in w for w in fx.gate.warnings),
                        fx.gate.warnings)

    def test_engine_inherited_signals_are_accepted(self) -> None:
        src = ("extends Node3D\n"
               "func f() -> void:\n"
               "\ttree_entered.connect(_on_tree)\n"
               "\tvisibility_changed.connect(_on_vis)\n"
               "func _on_tree() -> void:\n\tpass\n"
               "func _on_vis() -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_phantom_on_dynamic_chain_is_caught(self) -> None:
        src = ("extends Node\n"
               "func f(x: Node) -> void:\n"
               "\tx.totally_phantom.connect(_h)\n"
               "func _h() -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("totally_phantom" in e for e in fx.gate.errors),
                        fx.gate.errors)

    def test_existing_signal_on_dynamic_chain_is_legal(self) -> None:
        src = ("extends Node\n"
               "func f(x: Node) -> void:\n"
               "\tx.enemy_killed.connect(_h)\n"
               "func _h() -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_variable_receiver_is_recognised_as_dynamic(self) -> None:
        src = ("extends Node\n"
               "func f() -> void:\n"
               "\tvar sig: Signal = ready\n"
               "\tsig.connect(_h)\n"
               "func _h() -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_signal_api_names_are_not_read_as_signals(self) -> None:
        # x.connect(...) — `connect` is the Signal API, not a signal name
        src = ("extends Node\n"
               "func f(x: Node) -> void:\n"
               "\tx.connect(_h)\n"
               "func _h() -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])


class AutoloadReceiverTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_known_autoload_signal_is_accepted(self) -> None:
        src = ("extends Node\n"
               "func f() -> void:\n"
               "\tBus.run_started.emit(&\"standard\")\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_phantom_autoload_signal_is_caught(self) -> None:
        src = ("extends Node\n"
               "func f() -> void:\n"
               "\tBus.never_declared.emit()\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("Bus.never_declared" in e for e in fx.gate.errors),
                        fx.gate.errors)

    def test_autoload_emit_arity_is_checked(self) -> None:
        bad = ("extends Node\n"
               "func f() -> void:\n"
               "\tBus.enemy_killed.emit(&\"one\")\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", bad),))
        self.assertTrue(any("declares 2" in e for e in fx.gate.errors),
                        fx.gate.errors)
        good = ("extends Node\n"
                "func f() -> void:\n"
                "\tBus.enemy_killed.emit(&\"one\", &\"two\")\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", good),))
        self.assertEqual(fx.gate.errors, [])


class EmitArityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_self_emit_arity_mismatch_is_caught(self) -> None:
        src = ("extends Node\n"
               "signal two(a: int, b: int)\n"
               "func f() -> void:\n"
               "\ttwo.emit(1)\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("declares 2" in e and "passes 1" in e
                            for e in fx.gate.errors), fx.gate.errors)

    def test_self_emit_arity_match_is_accepted(self) -> None:
        src = ("extends Node\n"
               "signal two(a: int, b: int)\n"
               "func f() -> void:\n"
               "\ttwo.emit(1, 2)\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])


class ConnectCallableTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_phantom_callable_is_caught(self) -> None:
        src = ("extends Node\n"
               "signal go\n"
               "func f() -> void:\n"
               "\tgo.connect(_does_not_exist)\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("phantom callable" in e for e in fx.gate.errors),
                        fx.gate.errors)

    def test_callable_arity_out_of_range_is_caught(self) -> None:
        src = ("extends Node\n"
               "signal one(x: int)\n"
               "func f() -> void:\n"
               "\tone.connect(_needs_two)\n"
               "func _needs_two(a: int, b: int) -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("carries 1" in e and "accepts 2..2" in e
                            for e in fx.gate.errors), fx.gate.errors)

    def test_default_parameters_widen_the_accepted_range(self) -> None:
        src = ("extends Node\n"
               "signal one(x: int)\n"
               "func f() -> void:\n"
               "\tone.connect(_flexible)\n"
               "func _flexible(a: int, b: int = 0) -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_inherited_engine_method_is_accepted(self) -> None:
        # queue_redraw is CanvasItem's; arity data unavailable, existence is
        src = ("extends Control\n"
               "func _ready() -> void:\n"
               "\tresized.connect(queue_redraw)\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_self_method_form_is_checked_too(self) -> None:
        src = ("extends Node\n"
               "signal one(x: int)\n"
               "func f() -> void:\n"
               "\tone.connect(self._needs_two)\n"
               "func _needs_two(a: int, b: int) -> void:\n\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("carries 1" in e for e in fx.gate.errors),
                        fx.gate.errors)


class LegacyStringFormTests(unittest.TestCase):
    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_bare_emit_signal_phantom_is_caught(self) -> None:
        src = ("extends Node\n"
               "func f() -> void:\n"
               "\temit_signal(\"ghost\")\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("ghost" in e for e in fx.gate.errors),
                        fx.gate.errors)

    def test_bare_emit_signal_arity_is_checked(self) -> None:
        bad = ("extends Node\n"
               "signal one(x: int)\n"
               "func f() -> void:\n"
               "\temit_signal(\"one\", 1, 2)\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", bad),))
        self.assertTrue(any("passes 2" in e and "declares 1" in e
                            for e in fx.gate.errors), fx.gate.errors)
        good = ("extends Node\n"
                "signal one(x: int)\n"
                "func f() -> void:\n"
                "\temit_signal(\"one\", 1)\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", good),))
        self.assertEqual(fx.gate.errors, [])

    def test_has_signal_probes_are_not_flagged(self) -> None:
        src = ("extends Node\n"
               "func f(x: Node) -> void:\n"
               "\tif x.has_signal(\"whatever\"):\n"
               "\t\tpass\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])

    def test_dynamic_receiver_string_form_phantom_is_caught(self) -> None:
        src = ("extends Node\n"
               "func f(x: Node) -> void:\n"
               "\tx.emit_signal(\"ghost_name\")\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertTrue(any("ghost_name" in e for e in fx.gate.errors),
                        fx.gate.errors)

    def test_dynamic_receiver_existing_signal_is_legal(self) -> None:
        # a has_signal-guarded string emit on a dynamic Node stays legal
        src = ("extends Node\n"
               "func f(x: Node) -> void:\n"
               "\tif x.has_signal(\"enemy_killed\"):\n"
               "\t\tx.emit_signal(\"enemy_killed\", &\"a\", &\"b\")\n")
        fx = GateFixture(self.mod, (("scripts/a.gd", src),))
        self.assertEqual(fx.gate.errors, [])


if __name__ == "__main__":
    unittest.main()
