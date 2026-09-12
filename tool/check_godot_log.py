#!/usr/bin/env python3
"""Fail closed on Godot errors even when the engine returned exit status zero.

Godot's importer and script runner can print SCRIPT ERROR/ERROR and still exit
successfully (a broken suite can even be skipped). A successful test run must
therefore have a clean error channel AND its expected non-empty summary.
Stdlib-only; shared by CI and local build/test wrappers.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys

ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
ERROR = re.compile(
    r"^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:|"
    r"WARNING: ObjectDB instances leaked at exit|SHADER ERROR:|USER ERROR:|Unicode parsing error:|Failed to load script|FAIL:|UI FAIL:|FAIL\s{2})",
    re.MULTILINE,
)


EXPECTED_BEGIN = "TEST EXPECTED ERRORS: "
EXPECTED_END = "TEST EXPECTED ERRORS END"

# Engine-side lifecycle noise, opt-in via --allow-engine-noise for *native*
# scene-running steps only. With a real OpenGL driver (xvfb + Mesa) the GLES3
# backend emits reports that the dummy renderer used headless never produces.
# None of them carries a res:// path or maps to a game/asset defect, and the
# engine exits 0 afterwards; every entry is matched together with its C++
# `at:` line so a different failure that reuses the same headline still fails.
#   1. Scene-cull material queries hit a material RID in the frame between a
#      node's deferred instance update and its scripted teardown (freed
#      Ref<Material> on the node side). Godot 4.4.1 GLES3 ERR_FAIL_NULL paths.
#   2. The GLES3 texture allocator reports still-resident GL textures from the
#      driver destructor at process exit (viewport windows freed after the
#      driver). Shutdown ordering; no Android/desktop build impact.
#   3. Engine exit reports fired when any object/resource outlives the script
#      engine's teardown windows. Both spelling variants exist (4.4.1 prints
#      the uncounted form; other versions print "N instances were leaked").
# Add a new entry only with the captured log line AND its `at:` context line.
ENGINE_NOISE: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r'^\s*ERROR: Parameter "material" is null\.$'),
        r"at: material_(casts_shadows|is_animated|get_instance_shader_parameters|update_dependency)"
        r" \(drivers/gles3/storage/material_storage\.cpp:\d+\)",
    ),
    (
        re.compile(r"^\s*ERROR: Texture with GL ID of \d+: leaked \d+ bytes\.$"),
        r"at: ~Utilities \(drivers/gles3/storage/utilities\.cpp:\d+\)",
    ),
    (
        # The `--verbose` hint is backticked in some builds and plain in others.
        re.compile(r"^\s*WARNING: (\d+ )?ObjectDB instances (were )?leaked at exit"
                   r" \(run with `?--verbose`? for details\)\.$"),
        r"at: cleanup \(core/object/object\.cpp:\d+\)",
    ),
    (
        re.compile(r"^\s*ERROR: \d+ resources? still in use at exit"
                   r" \(run with `?--verbose`? for details\)\.$"),
        r"at: clear \(core/io/resource\.cpp:\d+\)",
    ),
]


def validate_log(text: str, exit_code: int = 0, required: str | None = None,
                 allow_test_errors: bool = False, allow_engine_noise: bool = False) -> list[str]:
    clean = ANSI.sub("", text)
    problems: list[str] = []
    if exit_code != 0:
        problems.append(f"Godot exited with status {exit_code}")
    if not clean.strip():
        problems.append("Godot produced no log output")
    lines = clean.splitlines()
    expected: Counter[str] | None = None
    for index, line in enumerate(lines):
        if line.startswith(EXPECTED_BEGIN):
            if not allow_test_errors or expected is not None:
                problems.append("Unexpected/nested negative-test error block")
                continue
            try:
                messages = json.loads(line[len(EXPECTED_BEGIN):])
                if not isinstance(messages, list) or not 1 <= len(messages) <= 8 \
                        or not all(isinstance(message, str) and message.startswith("ERROR: ")
                                   for message in messages):
                    raise ValueError("expected 1–8 exact ERROR lines")
                expected = Counter(messages)
            except (ValueError, TypeError) as error:
                problems.append(f"Malformed negative-test error block: {error}")
            continue
        if line == EXPECTED_END:
            if expected is None:
                problems.append("Negative-test error block ended without a start")
            elif any(expected.values()):
                problems.append("Expected test diagnostics were not emitted: " + repr(+expected))
            expected = None
            continue
        if ERROR.match(line):
            if expected is not None and expected[line.strip()] > 0:
                expected[line.strip()] -= 1
                continue
            if allow_engine_noise:
                # Demote only when the headline AND its C++ `at:` line are an
                # enumerated engine-lifecycle pair; anything else still fails.
                context = lines[index + 1] if index + 1 < len(lines) else ""
                if any(headline.match(line) and re.search(at_pattern, context)
                       for headline, at_pattern in ENGINE_NOISE):
                    continue
            # Preserve the nearby res:// stack location, not just the headline.
            problems.append("\n".join(lines[index:index + 4]))
    if expected is not None:
        problems.append("Unterminated negative-test error block")
    if required is not None and re.search(required, clean, re.MULTILINE) is None:
        problems.append(f"Missing successful completion summary: {required}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--exit-code", type=int, default=0)
    parser.add_argument("--allow-test-errors", action="store_true",
                        help="Honor exact, bounded ExpectedErrors blocks in unit tests only")
    parser.add_argument("--allow-engine-noise", action="store_true",
                        help="Demote enumerated GLES3/driver lifecycle reports on native runs "
                             "only (see ENGINE_NOISE in this file); never use for --import logs")
    parser.add_argument("--require", help="Regex that must match a successful test summary")
    args = parser.parse_args(argv)
    try:
        if args.require is not None:
            re.compile(args.require)
        text = args.log.read_text(encoding="utf-8", errors="replace")
        problems = validate_log(text, args.exit_code, args.require, args.allow_test_errors,
                                args.allow_engine_noise)
    except (OSError, re.error) as error:
        print(f"Godot log validation failed: {error}", file=sys.stderr)
        return 1
    if problems:
        print(f"Godot log validation failed: {args.log}", file=sys.stderr)
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1
    print(f"Godot log OK: {args.log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
