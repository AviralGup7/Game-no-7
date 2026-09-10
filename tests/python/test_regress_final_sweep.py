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

class EveryPathReturnsTests(unittest.TestCase):
    """`Not all code paths return a value` is a parse error, so the whole script fails to load -- which
    is what happened to the integration harness when `_run_run_definition_integration` finished with
    `results.append({...})` and no `return results`: every stage in the file reported
    `Nonexistent function ... (via call)` and none of them had run. GDScript demands a `return`
    statement in the body; this pins that no declared-return function is written without one. It cannot
    check that *all* paths return (only the engine can), but the total absence of a `return` is the
    shape that actually ships, because a reviewer sees the last statement and reads it as the answer.
    """

    SIGNATURE_RE = re.compile(
        r"^(?P<indent>\t*)(?:static )?func (?P<name>[A-Za-z_][A-Za-z0-9_]*)\((?P<params>.*)\)"
        r"\s*->\s*(?P<type>[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]]+\])?)\s*:"
    )
    RETURN_RE = re.compile(r"^\t+return\b")

    @staticmethod
    def _strip(source):
        out = []
        for line in source.splitlines():
            if line.lstrip().startswith("#"):
                out.append("")
                continue
            cut = line.find('"')
            while cut != -1:
                if cut > 0 and line[cut - 1] == "\\":
                    cut = line.find('"', cut + 1)
                    continue
                end = cut + 1
                while end < len(line) and line[end] != '"':
                    end += 2 if line[end] == "\\" else 1
                line = line[:cut] + '""' + line[end + 1:]
                cut = line.find('"', end + 1)
            out.append(line)
        return out

    def test_declared_return_functions_return(self):
        offenders = []
        for base in ("scripts", "tests"):
            for path in sorted((ROOT / base).rglob("*.gd")):
                lines = self._strip(path.read_text(encoding="utf-8"))
                for i, line in enumerate(lines):
                    m = self.SIGNATURE_RE.match(line)
                    if m is None or m.group("type") == "void":
                        continue
                    if re.search(r":\s*return\b", line):
                        continue  # one-liner: `func x() -> T: return y`
                    body_indent = m.group("indent") + "\t"
                    returned = False
                    for body in lines[i + 1:]:
                        if body.strip() and not body.startswith(body_indent):
                            break
                        if body.startswith(body_indent) and self.RETURN_RE.match(body):
                            returned = True
                            break
                    if not returned:
                        offenders.append(f"{path.relative_to(ROOT)}:{i + 1}: {m.group('name')}()")
        self.assertEqual([], offenders)


class AttachedResourceTests(unittest.TestCase):
    """A resource that is built, configured and never handed to anything is invisible to every tool and
    invisible in play: `build_nodes` made a `BoxMesh`, sized it, and dropped it on the floor, so the
    arena's obstacle bodies were solid but never drawn -- the exact "invisible walls" bug main had just
    fixed, re-introduced by a merge resolution that preferred the refactored file. The rule: a local
    `var x := <Type>{Mesh,Shape3D,Shape2D,Material3D,StyleBox,Gradient,Curve}.new()` inside a function
    must later be used as a value -- attached, passed, or returned -- or it is dead code that should
    have been a scene property.
    """

    NEW_RE = re.compile(
        r"\bvar\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*:?=\s*[A-Za-z_0-9]*"
        r"(?:Mesh|Shape3D|Shape2D|Material3D|StyleBox|Gradient|Curve)\.new\(\)"
    )

    @staticmethod
    def _strip(source):
        out = []
        for line in source.splitlines():
            if line.lstrip().startswith("#"):
                out.append("")
                continue
            cut = line.find('"')
            while cut != -1:
                if cut > 0 and line[cut - 1] == "\\":
                    cut = line.find('"', cut + 1)
                    continue
                end = cut + 1
                while end < len(line) and line[end] != '"':
                    end += 2 if line[end] == "\\" else 1
                line = line[:cut] + '""' + line[end + 1:]
                cut = line.find('"', end + 1)
            out.append(line)
        return out

    def test_built_resources_are_attached(self):
        offenders = []
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            lines = self._strip(path.read_text(encoding="utf-8"))
            for i, line in enumerate(lines):
                m = self.NEW_RE.search(line)
                if m is None:
                    continue
                name = m.group("name")
                used = re.compile(rf"=\s*{name}\b|\(\s*{name}\s*[,)]|\breturn\s+{name}\b|\[{name}\]")
                if any(used.search(rest) for rest in lines[i + 1:]):
                    continue
                offenders.append(f"{path.relative_to(ROOT)}:{i + 1}: {line.strip()}")
        self.assertEqual([], offenders)


if __name__ == "__main__":
    unittest.main()
