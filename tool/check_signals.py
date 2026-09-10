#!/usr/bin/env python3
"""Signal contract gate: every signal name and emit arity, checked offline.

WHY THIS GATE EXISTS
--------------------
The engine-api gate pins engine members, the scene-path gate pins the node
tree, the string-format gate pins the `%` operator. The last big unpinned
messaging surface is the game's own **signals**: 133 declared across 39
scripts, an EventBus-centric architecture, ~210 calls through autoload
receivers, ~138 through implicit `self`, plus dynamic receivers. Per the
pinned engine's docs (4.4.1-stable `Object.connect` / `Signal.emit`):
connecting a name the object does not have is a runtime error, emitting with
the wrong argument count is a runtime error, and a connected Callable is
invoked with exactly the signal's arguments — a method whose parameter list
cannot accept them fails at emit time. gdparse/gdlint see none of that, and
the headless suites only exercise the connections their flows happen to
take. (Scene-file `[connection ...]` blocks would be checked here too; the
tree authors zero of them — every connection is in code.)

WHAT IS INDEXED
---------------
* Every project script: its `signal name(params)` declarations (parameter
  counts parsed), its `func` parameter lists (required vs total, for the
  connect-callable arity rule), and its symbol table (members, params,
  locals, loop variables — so `sig.connect(...)` on a *variable* named
  `sig` is recognised as dynamic, not misread as a signal).
* Every engine class's signals — with parameter counts — from
  `tool/godot_api_manifest.json`, so a script inheriting `Node3D` legally
  reaches `ready`, `visibility_changed`, etc., and an engine-typed receiver
  gets the same strict check.
* The autoloads from `project.godot`: their signals are a hard contract,
  because the receiver's class is known exactly.

WHAT IS CHECKED (severity follows the sibling gates' phantom model)
-------------------------------------------------------------------
* A signal operation whose name resolves on the receiver — implicit self
  (walking the `extends` chain into engine signals), an autoload, or the
  built-in Signal operator names — is verified, including:
    - `sig.emit(args)` arity == the declared parameter count;
    - `sig.connect(method)` where the callable is a method of the same file:
      required <= signal params <= total parameters (defaults widen the
      accepted range, exactly as the engine's call will).
* A name the receiver's class does not declare but that IS declared
  somewhere (project or engine) is reported as an `[unsafe]` warning —
  the engine-analyzer's UNSAFE_PROPERTY_ACCESS analogue, resolved at
  runtime (summary counts them; `--verbose` lists them).
* A name declared NOWHERE is a phantom and fails the build whatever the
  receiver — a phantom is a phantom.
* Legacy string forms `emit_signal("x")`, `connect("x", ...)`,
  `disconnect("x")`, `is_connected("x")` on implicit self are checked like
  their dot-form equivalents; `has_signal("x")` is a deliberate probe and
  is only counted.

Receivers the gate cannot type (chained expressions, `get_node(...)`
results, loop variables) are counted as dynamic; their signal names still
fail the build if they exist nowhere.

Exit status: 1 on any error, 0 otherwise. Hermetic: stdlib-only, no
network, no Godot binary. Run: `python3 tool/check_signals.py [--verbose]`.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "tool" / "godot_api_manifest.json"
GD_DIRS = ("scripts", "tests")

# Built-in Signal methods: a trailing segment equal to one of these is an
# operation on the receiver, not a signal name (`x.connect(...)` where
# `connect` would otherwise pose as a phantom signal).
SIGNAL_OPS = ("connect", "disconnect", "is_connected", "emit")


# --------------------------------------------------------------------------
# Script facts
# --------------------------------------------------------------------------

class ScriptFacts:
    SIG_DECL = re.compile(r"^signal\s+(\w+)\s*(\(([^)]*)\))?", re.M)
    CN = re.compile(r"^class_name\s+(\w+)", re.M)
    EXT = re.compile(r"^extends\s+([A-Za-z_][\w./]*|\"[^\"]+\"|'[^']+')", re.M)
    FUNC = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", re.M)
    LOCAL_VAR = re.compile(r"^\s+(?:var|const)\s+(\w+)", re.M)
    TOP_VAR = re.compile(r"^(?:var|const)\s+(\w+)", re.M)
    FOR_VAR = re.compile(r"^\s*for\s+(\w+)\s+in", re.M)

    def __init__(self) -> None:
        self.files: dict[str, dict] = {}
        self.cn_to_file: dict[str, str] = {}

    @staticmethod
    def param_counts(param_list: str) -> tuple[int, int]:
        """(required, total) parameter counts of a parenthesised list."""
        plist = param_list.strip()
        if not plist:
            return 0, 0
        parts: list[str] = []
        depth = 0
        cur = ""
        for ch in plist:
            if ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            if ch == "," and depth == 0:
                parts.append(cur)
                cur = ""
            else:
                cur += ch
        parts.append(cur)
        parts = [p.strip() for p in parts if p.strip()]
        total = len(parts)
        required = sum(1 for p in parts if "=" not in p and not p.startswith("**"))
        return required, total

    def add(self, rel: str, text: str) -> None:
        sigs: dict[str, int] = {}
        for m in self.SIG_DECL.finditer(text):
            sigs[m.group(1)] = self.param_counts(m.group(3) or "")[1]
        funcs: dict[str, tuple[int, int]] = {}
        for m in self.FUNC.finditer(text):
            funcs[m.group(1)] = self.param_counts(m.group(2))
        symbols = set(funcs)
        symbols |= set(self.TOP_VAR.findall(text))
        symbols |= set(self.LOCAL_VAR.findall(text))
        symbols |= set(self.FOR_VAR.findall(text))
        for fm in self.FUNC.finditer(text):
            for prm in fm.group(2).split(","):
                pm = re.match(r"\s*([A-Za-z_]\w*)", prm)
                if pm:
                    symbols.add(pm.group(1))
        cn = self.CN.search(text)
        ext = self.EXT.search(text)
        self.files[rel] = {
            "cn": cn.group(1) if cn else None,
            "ext": ext.group(1).strip("'\"") if ext else "RefCounted",
            "sigs": sigs,
            "funcs": funcs,
            "symbols": symbols,
        }
        if cn:
            self.cn_to_file[cn.group(1)] = rel


# --------------------------------------------------------------------------
# Class graph: script chains + engine inheritance
# --------------------------------------------------------------------------

class ClassGraph:
    def __init__(self, facts: ScriptFacts) -> None:
        self.facts = facts
        self.engine: dict[str, dict] = {}
        if MANIFEST_PATH.exists():
            self.engine = json.loads(
                MANIFEST_PATH.read_text(encoding="utf-8"))["classes"]
        self.autoloads: dict[str, str] = {}
        self._all_signals: set[str] | None = None

    def set_project_godot(self, text: str) -> None:
        self.autoloads = dict(re.findall(r'^(\w+)="\*res://([^"]+)"', text, re.M))

    def engine_chain(self, cls: str) -> list[str]:
        out: list[str] = []
        seen: set[str] = set()
        while cls and cls not in seen:
            seen.add(cls)
            if cls not in self.engine:
                break
            out.append(cls)
            cls = self.engine[cls].get("inherits") or ""
        return out

    def script_chain(self, rel: str) -> list[tuple[str, str]]:
        """[('gd', file)..., ('eng', BaseClass)] for the class of `rel`."""
        out: list[tuple[str, str]] = []
        cur: str | None = rel
        seen: set[str] = set()
        while cur and cur not in seen:
            seen.add(cur)
            f = self.facts.files.get(cur)
            if f is None:
                return out
            out.append(("gd", cur))
            tok = f["ext"]
            if tok.endswith(".gd"):
                cur = tok[len("res://"):] if tok.startswith("res://") else tok
            elif tok in self.facts.cn_to_file:
                cur = self.facts.cn_to_file[tok]
            else:
                out.append(("eng", tok))
                return out
        return out

    def signal_table(self, rel: str) -> dict[str, tuple[int, str]]:
        """name -> (param_count, origin) for the class of `rel`, inherited."""
        table: dict[str, tuple[int, str]] = {}
        for kind, item in self.script_chain(rel):
            if kind == "gd":
                for s, n in self.facts.files[item]["sigs"].items():
                    if s not in table:
                        table[s] = (n, item)
            else:
                for cls in self.engine_chain(item):
                    for s, n in self.engine[cls].get("signals", {}).items():
                        if s not in table:
                            table[s] = (n, cls)
                break
        return table

    def all_signal_names(self) -> set[str]:
        if self._all_signals is None:
            names: set[str] = set()
            for f in self.facts.files.values():
                names |= set(f["sigs"])
            for entry in self.engine.values():
                names |= set(entry.get("signals", {}))
            self._all_signals = names
        return self._all_signals


# --------------------------------------------------------------------------
# Scanning helpers
# --------------------------------------------------------------------------

def code_only(text: str) -> str:
    """Comment-free, string-content-free view; offsets identical."""
    out: list[str] = []
    for line in text.splitlines():
        buf: list[str] = []
        i, n = 0, len(line)
        while i < n:
            c = line[i]
            if c == "#":
                buf.append(" " * (n - i))
                break
            if c in "\"'":
                buf.append(c)
                i += 1
                while i < n:
                    if line[i] == "\\":
                        buf.append("  ")
                        i += 2
                        continue
                    if line[i] == c:
                        buf.append(c)
                        i += 1
                        break
                    buf.append(" ")
                    i += 1
                continue
            buf.append(c)
            i += 1
        out.append("".join(buf))
    return "\n".join(out)


def take_call_args(text: str, start: int) -> str:
    """`start` sits just after the opening paren; returns the arg text."""
    depth = 1
    j = start
    n = len(text)
    while j < n and depth:
        ch = text[j]
        if ch in "\"'":
            q = ch
            j += 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == q:
                    j += 1
                    break
                j += 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        j += 1
    return text[start:j - 1]


def count_args(arg_text: str) -> int:
    s = arg_text.strip()
    if not s:
        return 0
    parts: list[str] = []
    depth = 0
    cur = ""
    i = 0
    while i < len(s):
        ch = s[i]
        if ch in "\"'":
            q = ch
            i += 1
            while i < len(s):
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == q:
                    i += 1
                    break
                i += 1
            cur += "x"
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
        i += 1
    parts.append(cur)
    return len([p for p in parts if p.strip()])


SIG_OP_CALL = re.compile(
    r"(?<![\w.])([A-Za-z_][\w.]*)\s*\.\s*(connect|disconnect|is_connected|emit)\(")
STRING_FORM = re.compile(
    r"(?<![\w.])(?:([A-Za-z_][\w.]*)\s*\.\s*)?"
    r"(emit_signal|connect|disconnect|is_connected|has_signal)"
    r"\(\s*(?:&|\^)?\"([^\"]+)\"")


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------

class SignalGate:
    def __init__(self) -> None:
        self.facts = ScriptFacts()
        self.graph = ClassGraph(self.facts)
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.bare_checked = 0
        self.autoload_checked = 0
        self.dynamic_seen = 0
        self.string_forms = 0
        self.probes = 0

    # -- ingestion ------------------------------------------------------
    def add_script(self, rel: str, text: str) -> None:
        self.facts.add(rel, text)

    def finalize(self) -> None:
        self.graph._all_signals = None

    # -- checks ---------------------------------------------------------
    def check_script(self, rel: str, text: str) -> None:
        clean = code_only(text)
        table = self.graph.signal_table(rel)
        f = self.facts.files.get(rel, {})
        symbols = f.get("symbols", set())
        all_names = self.graph.all_signal_names()

        for m in SIG_OP_CALL.finditer(clean):
            full, op = m.group(1), m.group(2)
            line = clean[:m.start()].count("\n") + 1
            parts = [x.strip() for x in full.split(".")]
            sig = parts[-1]
            if sig in SIGNAL_OPS and len(parts) >= 2:
                # x.connect(...)/x.emit(...) where the trailing word is the
                # Signal API itself — a dynamic receiver, not a signal name
                self.dynamic_seen += 1
                continue
            # positions come from the clean view; content from the original
            arg_text = take_call_args(text, m.end())

            if len(parts) == 1:
                self.bare_checked += 1
                if sig in table:
                    self._arity(rel, line, f"{sig}.{op}", table[sig][0], op, arg_text)
                    if op == "connect":
                        self._connect_callable(rel, line, sig, table[sig][0],
                                               arg_text, f)
                    continue
                if sig in symbols or sig == "super":
                    self.dynamic_seen += 1
                    continue
                if sig in self.graph.autoloads:
                    # `Bus.connect(...)` is Object.connect on the autoload
                    # object itself, not a signal reference
                    self.dynamic_seen += 1
                    continue
                if sig in all_names:
                    self.warnings.append(
                        f"{rel}:{line}: bare `{sig}.{op}` — not declared on "
                        f"this class (it exists elsewhere); resolved at runtime")
                else:
                    self.errors.append(
                        f"{rel}:{line}: bare `{sig}.{op}` — `{sig}` is not a "
                        f"signal on this class or anywhere else in the project "
                        f"or engine (phantom); the engine errors at runtime")
                continue

            head = parts[0]
            if head in self.graph.autoloads:
                self.autoload_checked += 1
                atable = self.graph.signal_table(self.graph.autoloads[head])
                if sig in atable:
                    self._arity(rel, line, f"{head}.{sig}.{op}",
                                atable[sig][0], op, arg_text)
                    if op == "connect":
                        self._connect_callable(rel, line, sig, atable[sig][0],
                                               arg_text, f)
                    continue
                if sig in all_names:
                    self.errors.append(
                        f"{rel}:{line}: `{head}.{sig}.{op}` — autoload `{head}` "
                        f"declares no signal `{sig}` (it is declared on other "
                        f"classes); connecting/emitting it is a runtime error")
                else:
                    self.errors.append(
                        f"{rel}:{line}: `{head}.{sig}.{op}` — `{sig}` is not a "
                        f"signal anywhere (phantom); runtime error")
                continue

            self.dynamic_seen += 1
            if sig in all_names:
                self.warnings.append(
                    f"{rel}:{line}: `{full}.{op}` — receiver type unknown; "
                    f"`{sig}` is a signal elsewhere, resolved at runtime")
            elif sig not in symbols:
                self.errors.append(
                    f"{rel}:{line}: `{full}.{op}` — `{sig}` is not a signal "
                    f"anywhere (phantom); runtime error whatever the receiver")

        # legacy string forms: bare/self, autoload receivers, then dynamic
        for m in STRING_FORM.finditer(clean):
            # re-extract from the original text: the clean view blanks the
            # signal-name string; offsets are identical
            om = STRING_FORM.match(text, m.start())
            if not om:
                continue
            recv, fn, name = om.group(1), om.group(2), om.group(3)
            line = clean[:m.start()].count("\n") + 1
            if fn == "has_signal":
                self.probes += 1
                continue
            self.string_forms += 1
            label = f"{recv}.{fn}" if recv else fn
            if recv is None or recv == "self":
                owner_table = table
                owner_label = "self"
            elif recv.split(".")[0] in self.graph.autoloads:
                owner_table = self.graph.signal_table(
                    self.graph.autoloads[recv.split(".")[0]])
                owner_label = f"autoload `{recv}`"
            else:
                self.dynamic_seen += 1
                if name not in all_names:
                    self.errors.append(
                        f"{rel}:{line}: {label}(\"{name}\") — `{name}` is not "
                        f"a signal anywhere (phantom); runtime error")
                continue
            if name in owner_table:
                if fn == "emit_signal":
                    # om.end() sits right after the name literal, still inside
                    # the call: the remainder is "", ", a, b" or malformed
                    rest = take_call_args(text, om.end()).strip()
                    if rest.startswith(","):
                        passed = count_args(rest[1:])
                    elif rest == "":
                        passed = 0
                    else:
                        passed = count_args(rest)
                    n_params = owner_table[name][0]
                    if passed != n_params:
                        self.errors.append(
                            f"{rel}:{line}: {label}(\"{name}\") passes "
                            f"{passed} argument(s) but the signal declares "
                            f"{n_params}; runtime error")
                continue
            if name in all_names:
                self.errors.append(
                    f"{rel}:{line}: {label}(\"{name}\") on {owner_label} — "
                    f"that class declares no such signal (it exists "
                    f"elsewhere); the engine errors at runtime")
            else:
                self.errors.append(
                    f"{rel}:{line}: {label}(\"{name}\") — `{name}` is not a "
                    f"signal anywhere (phantom); runtime error")

    def _arity(self, rel: str, line: int, label: str, n_params: int,
               op: str, arg_text: str) -> None:
        if op != "emit":
            return
        passed = count_args(arg_text)
        if passed != n_params:
            self.errors.append(
                f"{rel}:{line}: `{label}` — signal declares {n_params} "
                f"parameter(s) but emit passes {passed}; the engine errors "
                f"at runtime")

    def resolve_callable(self, rel: str, name: str) -> tuple[str, tuple[int, int] | None]:
        """('arity', (req, total)) for a project-script method, ('exists', None)
        for an inherited engine method (the manifest has no param counts),
        ('missing', None) for neither."""
        for kind, item in self.graph.script_chain(rel):
            if kind == "gd":
                funcs = self.graph.facts.files[item]["funcs"]
                if name in funcs:
                    return "arity", funcs[name]
            else:
                for cls in self.graph.engine_chain(item):
                    methods = self.graph.engine[cls].get("methods", {})
                    if name in methods:
                        return "exists", None
                break
        return "missing", None

    def _connect_callable(self, rel: str, line: int, sig: str, n_params: int,
                          arg_text: str, f: dict) -> None:
        """When the connected callable resolves to a method, its parameter
        list must be able to take exactly the signal's arguments."""
        arg = arg_text.strip()
        method: str | None = None
        m = re.match(r"^([A-Za-z_]\w*)$", arg)
        if m:
            method = m.group(1)
        else:
            m = re.match(r"^self\.([A-Za-z_]\w*)$", arg)
            if m:
                method = m.group(1)
            else:
                m = re.match(r'^Callable\(\s*self\s*,\s*"([A-Za-z_]\w*)"\s*\)$', arg)
                if m:
                    method = m.group(1)
        if method is None:
            return
        kind, counts = self.resolve_callable(rel, method)
        if kind == "missing":
            if method not in f.get("symbols", set()):
                self.errors.append(
                    f"{rel}:{line}: `{sig}.connect({method})` — no method "
                    f"`{method}` exists on this class (phantom callable)")
            return
        if kind == "exists":
            return  # inherited engine method: existence verified, no arity data
        assert counts is not None
        req, total = counts
        if not (req <= n_params <= total):
            self.errors.append(
                f"{rel}:{line}: `{sig}.connect({method})` — signal "
                f"`{sig}` carries {n_params} argument(s) but `{method}` "
                f"accepts {req}..{total}; the engine errors when the signal "
                f"fires")

    # -- repo walk ------------------------------------------------------
    def load_repo(self) -> None:
        pg = ROOT / "project.godot"
        if pg.exists():
            self.graph.set_project_godot(pg.read_text(encoding="utf-8"))
        for d in GD_DIRS:
            for p in sorted((ROOT / d).rglob("*.gd")):
                self.add_script(p.relative_to(ROOT).as_posix(),
                                p.read_text(encoding="utf-8"))
        self.finalize()
        for d in GD_DIRS:
            for p in sorted((ROOT / d).rglob("*.gd")):
                rel = p.relative_to(ROOT).as_posix()
                self.check_script(rel, p.read_text(encoding="utf-8"))


def main() -> int:
    verbose = "--verbose" in sys.argv
    gate = SignalGate()
    gate.load_repo()
    for e in sorted(set(gate.errors)):
        print(f"  [error] {e}")
    if verbose:
        for w in sorted(set(gate.warnings)):
            print(f"  [unsafe] {w}")
    summary = (f"{gate.bare_checked} self-signal ops, "
               f"{gate.autoload_checked} autoload-receiver ops, "
               f"{gate.string_forms} legacy string forms, "
               f"{gate.dynamic_seen} dynamic receivers skipped, "
               f"{len(set(gate.warnings))} unsafe-access warnings")
    if gate.errors:
        print(f"\nsignal contract: FAILED — {len(set(gate.errors))} error(s) ({summary})")
        return 1
    print(f"signal contract: clean ({summary}; emit arity and connect-callable "
          f"arity checked against project declarations and the "
          f"{MANIFEST_PATH.name} engine signals)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
