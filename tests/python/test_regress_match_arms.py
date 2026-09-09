"""Regression: GDScript match arms must have a body.

GDScript (unlike `if`/`elif`/`else`) does not allow a match arm with an empty
body: a pattern line immediately followed by another pattern line at the same
indent is a parse error that only surfaces when Godot compiles the script.
This guard scans every .gd file so the mistake cannot ship silently again
(it once took down the whole CI pipeline — see the chase-state STRAFE arm).
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
GD_DIRS = ["scripts", "tests"]

# Lines that END with a colon but are statements, not match patterns.
NON_PATTERN = re.compile(
    r"^(if |elif |else|for |while |return |func |static |var |const |enum |class |signal |export |match )"
)


def _iter_match_pattern_lines(path: pathlib.Path):
    in_match = False
    match_indent = -1
    lines = path.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if re.match(r"^match\s", s):
            in_match = True
            match_indent = len(line) - len(line.lstrip("\t"))
            continue
        if not in_match:
            continue
        indent = len(line) - len(line.lstrip("\t"))
        if indent <= match_indent:
            in_match = False
            continue
        if s.endswith(":") and not s.endswith("::") and not NON_PATTERN.match(s):
            yield i, s, line, lines


class MatchArmGuards(unittest.TestCase):
    def test_no_empty_match_arms(self):
        offenders = []
        for d in GD_DIRS:
            base = ROOT / d
            if not base.exists():
                continue
            for path in base.rglob("*.gd"):
                for i, s, line, lines in _iter_match_pattern_lines(path):
                    # Next code line: another pattern at same/greater indent = empty arm.
                    for nxt in lines[i:]:
                        ns = nxt.strip()
                        if not ns or ns.startswith("#"):
                            continue
                        nind = len(nxt) - len(nxt.lstrip("\t"))
                        if ns.endswith(":") and not ns.endswith("::") \
                                and not NON_PATTERN.match(ns) and nind >= len(line) - len(line.lstrip("\t")):
                            offenders.append("%s:%d: %r -> %r" % (
                                path.relative_to(ROOT), i, s, ns))
                        break
        self.assertEqual(offenders, [], "empty match arm(s):\n" + "\n".join(offenders))
