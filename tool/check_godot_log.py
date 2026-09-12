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


def validate_log(text: str, exit_code: int = 0, required: str | None = None,
                 allow_test_errors: bool = False) -> list[str]:
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
    parser.add_argument("--require", help="Regex that must match a successful test summary")
    args = parser.parse_args(argv)
    try:
        if args.require is not None:
            re.compile(args.require)
        text = args.log.read_text(encoding="utf-8", errors="replace")
        problems = validate_log(text, args.exit_code, args.require, args.allow_test_errors)
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
