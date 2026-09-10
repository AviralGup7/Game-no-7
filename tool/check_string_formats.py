#!/usr/bin/env python3
"""String-format contract gate: the `%` operator, checked against the engine.

WHY THIS GATE EXISTS
--------------------
The tree formats ~850 messages with GDScript's `%` operator — every
push_error, every authored-content validation problem, every test `why`,
every combat-log line. The pinned engine's semantics for it (verified in the
4.4.1-stable source: `String::sprintf` in core/string/ustring.cpp,
`OperatorEvaluatorStringFormat` in core/variant/variant_op.h) are strict:

  * placeholders are `%` + flags `-+u` + width/precision digits + optional
    `*` (dynamic width — each `*` consumes one EXTRA value) + one of the
    types `d o x X f v s c`; `%%` is a literal percent;
  * an Array right-hand side must match the consumed-value count EXACTLY —
    too few gives "not enough arguments for format string", too many gives
    "not all arguments converted during string formatting";
  * a non-Array right-hand side is wrapped into a one-element Array, so a
    scalar operand demands exactly one placeholder;
  * `%d/%o/%x/%X/%f` demand numbers ("a number is required"), `%v` demands a
    vector ("%v requires a vector type"), `%c` a number or single character;
  * any mismatch is not a warning: the operator evaluator does
    `ERR_FAIL_MSG("String formatting error: ...")` — a runtime ERROR.

The tree has been stung by this class already — `tests/integration_stages.gd`
carries a comment explaining how a concatenated format string once printed
its own placeholders because `"a" + "b" % [..]` binds as `"a" + ("b" % [..])`.
Before this gate, every format use was checked only at runtime, and only on
the paths the headless flows happen to take.

WHAT IS CHECKED
---------------
Every string literal in `scripts/` and `tests/` followed by `%`:

  * placeholder syntax (unsupported type char, incomplete trailing `%`,
    double precision points) — the engine's own error strings are quoted;
  * arity: Array literals are counted element-by-element (string- and
    nesting-aware, trailing comma legal per the 4.4.1 parser's
    "Allow for trailing comma"), scalar operands need exactly one
    placeholder;
  * literal types: an obvious string/bool element feeding a numeric
    placeholder (or a number feeding `%v`) fails, because `sprintf`
    type-checks values.

Lookups the gate cannot decide (a variable or call on either side) are
counted and reported as dynamic. StringName (&"...") and NodePath (^"...")
literals are not `%` operands and are skipped.

Exit status: 1 on any error, 0 otherwise. Hermetic: stdlib-only, no network,
no Godot binary. Run from anywhere: `python3 tool/check_string_formats.py`.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GD_DIRS = ("scripts", "tests")

FORMAT_TYPES = "doxXfvsc"
NUMERIC_TYPES = set("doxXf")


# --------------------------------------------------------------------------
# Source walk: string tokens + comment-free, string-content-free code view
# --------------------------------------------------------------------------

class Source:
    """One .gd file: string tokens and an offset-preserving code view."""

    def __init__(self, rel: str, text: str) -> None:
        self.rel = rel
        self.text = text
        self.strings: list[tuple[int, int, str, str]] = []  # start, end, content, quote
        self.prefix: dict[int, str] = {}                     # string start -> &/r/^ prefix
        self.code: list[str] = []
        self._walk()

    def _walk(self) -> None:
        text = self.text
        n = len(text)
        i = 0
        code: list[str] = []
        while i < n:
            c = text[i]
            if c == "#":
                j = text.find("\n", i)
                j = n if j < 0 else j
                code.append(" " * (j - i))
                i = j
                continue
            if c in "\"'":
                prefix = ""
                start = i
                if code and code[-1] in ("&", "^"):
                    prefix = code[-1]
                elif code and code[-1] in ("r", "R") and (
                        len(code) < 2 or not (code[-2].isalnum() or code[-2] == "_")):
                    prefix = code[-1]
                quote = c
                code.append(c)
                i += 1
                content: list[str] = []
                closed = False
                while i < n:
                    ch = text[i]
                    if ch == "\\":
                        # escape pair: keep both chars in content, blank in view
                        content.append(text[i:i + 2])
                        code.append("  ")
                        i += 2
                        continue
                    if ch == quote:
                        code.append(ch)
                        i += 1
                        closed = True
                        break
                    if ch == "\n":  # GDScript strings do not span lines
                        break
                    content.append(ch)
                    code.append(" ")
                    i += 1
                if closed and prefix in ("", "r", "R"):
                    self.strings.append((start, i, "".join(content), quote))
                    self.prefix[start] = prefix
                continue
            code.append(c)
            i += 1
        self.code_text = "".join(code)

    def line_of(self, pos: int) -> int:
        return self.text.count("\n", 0, pos) + 1


# --------------------------------------------------------------------------
# Format-string parsing — the engine's rules
# --------------------------------------------------------------------------

class Placeholder:
    __slots__ = ("type", "values")

    def __init__(self, typ: str, values: int) -> None:
        self.type = typ
        self.values = values  # 1, plus one per '*'


def parse_format(content: str) -> tuple[list[Placeholder], str | None, int]:
    """(placeholders, error_reason, error_pos). Mirrors String::sprintf."""
    out: list[Placeholder] = []
    i = 0
    n = len(content)
    while i < n:
        c = content[i]
        if c == "\\":
            i += 2
            continue
        if c != "%":
            i += 1
            continue
        i += 1
        if i >= n:
            return out, "incomplete format", i - 1
        if content[i] == "%":
            i += 1
            continue
        stars = 0
        seen_dot = False
        while i < n:
            ch = content[i]
            if ch in "-+u":
                i += 1
                continue
            if ch.isdigit():
                i += 1
                continue
            if ch == ".":
                if seen_dot:
                    return out, "too many decimal points in format", i
                seen_dot = True
                i += 1
                continue
            if ch == "*":
                stars += 1
                i += 1
                continue
            break
        if i >= n:
            return out, "incomplete format", i - 1
        typ = content[i]
        if typ not in FORMAT_TYPES:
            return out, "unsupported format character", i
        out.append(Placeholder(typ, 1 + stars))
        i += 1
    return out, None, -1


# --------------------------------------------------------------------------
# Right-hand side parsing
# --------------------------------------------------------------------------

def skip_ws(view: str, i: int) -> int:
    while i < len(view) and view[i] in " \t\r\n":
        i += 1
    return i


def parse_array(original: str, i: int) -> tuple[list[str] | None, int]:
    """i points at '['; returns (elements, end_index_after_']').
    Elements are raw slices; None when the literal cannot be closed."""
    assert original[i] == "["
    depth = 0
    elems: list[str] = []
    start = i + 1
    j = i
    n = len(original)
    while j < n:
        c = original[j]
        if c in "\"'":
            q = c
            j += 1
            while j < n:
                if original[j] == "\\":
                    j += 2
                    continue
                if original[j] == q:
                    j += 1
                    break
                if original[j] == "\n":
                    return None, j
                j += 1
            continue
        if c == "#":
            j = original.find("\n", j)
            if j < 0:
                return None, n
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0 and c == "]":
                tail = original[start:j]
                if tail.strip():
                    elems.append(tail)
                return elems, j + 1
        elif c == "," and depth == 1:
            elems.append(original[start:j])
            start = j + 1
        j += 1
    return None, n


NUM_LIT = re.compile(r"^\s*(?:0[xXbB])?[0-9][0-9a-fA-F_]*(?:\.[0-9_]*)?(?:[eE][-+]?[0-9]+)?\s*$")
VEC_LIT = re.compile(r"^\s*Vector[234][i]?\s*\(")


def classify_element(elem: str) -> str:
    e = elem.strip()
    if not e:
        return "empty"
    if e[0] in "\"'":
        return "string"
    if e in ("true", "false", "null"):
        return e
    if VEC_LIT.match(e):
        return "vector"
    if NUM_LIT.match(e):
        return "number"
    return "expr"


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------

class FormatGate:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.checked = 0
        self.array_forms = 0
        self.scalar_forms = 0
        self.dynamic = 0

    def check_file(self, rel: str, text: str) -> None:
        src = Source(rel, text)
        view = src.code_text
        original = src.text
        n = len(view)
        for (start, end, content, _quote) in src.strings:
            if src.prefix.get(start) in ("&", "^"):
                continue  # StringName/NodePath literals are not % operands
            i = skip_ws(view, end)
            if i >= n or view[i] != "%":
                continue
            if i + 1 < n and view[i + 1] == "=":
                continue  # %= is modulo-assignment, not formatting
            j = skip_ws(view, i + 1)
            if j >= n or view[j] in ",)]}=":
                continue  # dangling operator / not a format use we can read
            placeholders, reason, pos = parse_format(content)
            line = src.line_of(start)
            if reason:
                self.errors.append(
                    f"{rel}:{line}: format string {content[:60]!r} — engine "
                    f"sprintf rejects it: \"{reason}\""
                )
                continue
            consumed = sum(p.values for p in placeholders)
            fmt_snip = content if len(content) <= 60 else content[:57] + "..."

            if original[j] == "[":
                elems, _after = parse_array(original, j)
                if elems is None:
                    self.dynamic += 1
                    continue
                # trailing comma is legal and adds no element (4.4.1 parser)
                elems = [e for e in elems if e.strip()]
                self.checked += 1
                self.array_forms += 1
                if len(elems) < consumed:
                    self.errors.append(
                        f"{rel}:{line}: \"{fmt_snip}\" % [...] — not enough "
                        f"arguments for format string ({consumed} placeholder "
                        f"value(s), {len(elems)} array element(s)); the engine "
                        f"raises a runtime error on this format"
                    )
                    continue
                if len(elems) > consumed:
                    self.errors.append(
                        f"{rel}:{line}: \"{fmt_snip}\" % [...] — not all "
                        f"arguments converted during string formatting "
                        f"({consumed} placeholder value(s), {len(elems)} array "
                        f"element(s)); the engine raises a runtime error"
                    )
                    continue
                self._check_types(rel, line, fmt_snip, placeholders, elems)
            else:
                self.checked += 1
                self.scalar_forms += 1
                if consumed == 0:
                    self.errors.append(
                        f"{rel}:{line}: \"{fmt_snip}\" % <scalar> — not all "
                        f"arguments converted during string formatting (the "
                        f"operand is wrapped into a one-element array, but the "
                        f"string has no placeholder); runtime error"
                    )
                elif consumed > 1:
                    self.errors.append(
                        f"{rel}:{line}: \"{fmt_snip}\" % <scalar> — not enough "
                        f"arguments for format string ({consumed} placeholder "
                        f"value(s), scalar operand supplies exactly one); "
                        f"runtime error"
                    )

    def _check_types(self, rel: str, line: int, fmt_snip: str,
                     placeholders: list[Placeholder], elems: list[str]) -> None:
        vi = 0
        for ph in placeholders:
            for k in range(ph.values):
                if vi >= len(elems):
                    return
                kind = classify_element(elems[vi])
                if ph.type in NUMERIC_TYPES and kind in ("string", "true", "false", "null"):
                    self.errors.append(
                        f"{rel}:{line}: \"{fmt_snip}\" — a number is required "
                        f"for %{ph.type}, but argument {vi + 1} is the literal "
                        f"{elems[vi].strip()[:40]!r}; runtime error"
                    )
                elif ph.type == "v" and kind in ("string", "number", "true", "false", "null"):
                    self.errors.append(
                        f"{rel}:{line}: \"{fmt_snip}\" — %v requires a vector "
                        f"type (Vector2/3/4/2i/3i/4i), but argument {vi + 1} "
                        f"is the literal {elems[vi].strip()[:40]!r}; runtime error"
                    )
                elif ph.type == "c" and kind == "string":
                    inner = elems[vi].strip()[1:-1]
                    if len(inner) != 1:
                        self.errors.append(
                            f"{rel}:{line}: \"{fmt_snip}\" — %c requires number "
                            f"or single-character string, but argument {vi + 1} "
                            f"is {elems[vi].strip()[:40]!r}; runtime error"
                        )
                vi += 1

    def load_repo(self) -> None:
        for d in GD_DIRS:
            for p in sorted((ROOT / d).rglob("*.gd")):
                self.check_file(p.relative_to(ROOT).as_posix(),
                                p.read_text(encoding="utf-8"))


def main() -> int:
    gate = FormatGate()
    gate.load_repo()
    for e in sorted(set(gate.errors)):
        print(f"  [error] {e}")
    if gate.errors:
        print(f"\nstring-format contract: FAILED — {len(set(gate.errors))} error(s) "
              f"({gate.checked} format uses checked: {gate.array_forms} array-form, "
              f"{gate.scalar_forms} scalar-form)")
        return 1
    print(f"string-format contract: clean ({gate.checked} format uses checked: "
          f"{gate.array_forms} array-form, {gate.scalar_forms} scalar-form; "
          f"placeholder syntax, arity and literal types verified against the "
          f"4.4.1-stable String::sprintf rules)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
