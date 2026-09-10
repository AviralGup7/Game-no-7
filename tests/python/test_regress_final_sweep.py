"""Final sweep — exhaustive checks for the typed-architecture refactor.

Supersedes the original 4000-line hardening sweep. The per-file
`_validated_*` needle counts are gone with the theater itself; the
exhaustive file-by-file guarantee is now delegated to
tool/check_typed_arch.py, which is strictly stronger (it parses every
script for duck typing and verifies typed references resolve).
"""
import pathlib
import subprocess
import sys
import unittest
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(p):
    return (ROOT / p).read_text(encoding="utf-8", errors="ignore")


class DocsTests(unittest.TestCase):
    def test_hardening_doc_marked_superseded(self):
        txt = read("docs/HARDENING.md")
        self.assertIn("SUPERSEDED", txt)
        self.assertIn("check_typed_arch.py", txt)

    def test_refactor_plan_exists(self):
        self.assertIn("Phase", read("docs/REFACTOR_PLAN.md"))


class TypedArchGateTests(unittest.TestCase):
    def test_gate_passes(self):
        r = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "check_typed_arch.py")],
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, f"check_typed_arch failed:\n{r.stdout}")

    def test_theater_stays_dead(self):
        # No file may reintroduce the retired helper pattern.
        offenders = []
        for gd in (ROOT / "scripts").rglob("*.gd"):
            txt = gd.read_text(errors="ignore")
            if "func _validated_" in txt or "func _guarded_" in txt or "func _safe_emit" in txt:
                offenders.append(gd.relative_to(ROOT).as_posix())
        self.assertEqual(offenders, [], f"theater returned in: {offenders}")


class ValidateGuardsToolTests(unittest.TestCase):
    def test_tool_runs_clean(self):
        r = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "validate_guards.py")],
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, f"validate_guards failed:\n{r.stdout}")


class RealGuardTests(unittest.TestCase):
    def test_wave_planner_int_division(self):
        self.assertIn("maxi(wave_number, 1)", read("scripts/waves/wave_planner.gd"))

    def test_progression_finite(self):
        self.assertIn("is_finite(base)", read("scripts/player/progression_component.gd"))

    def test_health_finite(self):
        self.assertIn("is_instance_valid(payload)", read("scripts/player/health_component.gd"))


class CIStillSplitTests(unittest.TestCase):
    def test_three_stages_plus_publish(self):
        txt = read(".github/workflows/android.yml")
        self.assertIn("validate-resources:", txt)
        self.assertIn("godot-tests:", txt)
        self.assertIn("build-android:", txt)
        self.assertIn("publish-release:", txt)
        # Each stage uploads reports-* for bisect
        self.assertEqual(txt.count("reports-"), 3)


class ScopeShadowTests(unittest.TestCase):
    """A local that re-declares its own function's parameter is a *parse* error in GDScript -- "There
    is already a parameter named \"half\" declared in this scope" -- so the file does not load, and
    the class of thing that no syntax checker flags: `gdparse` is happy, the engine is not. It got into
    this tree from a merge resolution that added `var half := ...` to a function whose second parameter
    was `half: float` (the arena's half-extent). Indentation is enough to enforce the rule: a `func`
    header's parameter names, against every declaration in the body indented deeper than it.
    """

    HEADER_RE = re.compile(r"^(\t*)(?:static )?func ([A-Za-z_][A-Za-z0-9_]*)\(([^)]*)\)")
    DECL_RE = re.compile(r"^[\t ]+var ([A-Za-z_][A-Za-z0-9_]*)[\t ]*[:=]")
    LOOP_RE = re.compile(r"^[\t ]+for ([A-Za-z_][A-Za-z0-9_]*)(?::[^\n]*)? in ")

    @staticmethod
    def _params(inner: str) -> set:
        names = set()
        for piece in inner.split(","):
            piece = piece.strip()
            if not piece:
                continue
            names.add(re.split(r"[:=]", piece, 1)[0].strip())
        return names

    def test_no_local_redeclares_its_own_parameter(self) -> None:
        root = pathlib.Path(__file__).resolve().parents[2]
        offenders = []
        for gd in sorted((root / "scripts").rglob("*.gd")):
            lines = gd.read_text(encoding="utf-8", errors="ignore").splitlines()
            params: set = set()
            indent = ""
            for line in lines:
                m = self.HEADER_RE.match(line)
                if m:
                    params, indent = self._params(m.group(3)), m.group(1)
                    continue
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                lead = len(line) - len(line.lstrip("\t"))
                if lead <= len(indent):
                    params = set()   # back out of the function body
                    continue
                if not params:
                    continue
                for rx in (self.DECL_RE, self.LOOP_RE):
                    d = rx.match(line)
                    if d and d.group(1) in params:
                        offenders.append(f"{gd.relative_to(root)}: {line.strip()}")
        self.assertEqual(offenders, [],
                         msg="locals shadowing their own parameters (a parse error):\n  "
                             + "\n  ".join(offenders[:12]))

if __name__ == "__main__":
    unittest.main()
