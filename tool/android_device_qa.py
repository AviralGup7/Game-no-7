#!/usr/bin/env python3
"""Verify, install and smoke-launch the Android APK on one explicitly selected device.

No uninstall, data clear, global logcat clear, or arbitrary-first-device install.
A missing SDK/device is NOT a successful Android test. --checklist is docs-only.
"""
from __future__ import annotations

import argparse
import configparser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

if __package__:
    from .check_android_apk import ROOT, verify
else:
    from check_android_apk import ROOT, verify


class PrerequisiteError(ValueError):
    pass


def command(args: list[str], timeout: float = 120) -> str:
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise ValueError(f"Command failed ({result.returncode}): {' '.join(args[:5])}\n{(result.stderr or result.stdout)[-1800:]}")
    return result.stdout


def choose_device(listing: str, requested: str | None) -> str:
    states = {}
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) >= 2 and not line.startswith(("List of devices", "*")):
            states[fields[0]] = fields[1]
    if requested:
        if states.get(requested) != "device":
            raise PrerequisiteError(f"Selected device {requested!r} is not authorized/ready")
        return requested
    ready = [serial for serial, state in states.items() if state == "device"]
    if len(ready) != 1:
        raise PrerequisiteError("Connect/authorize one Android device, or select it with ANDROID_SERIAL / --serial")
    return ready[0]


def process_ids(adb: list[str], package: str) -> list[str]:
    result = subprocess.run(adb + ["shell", "pidof", package], capture_output=True, text=True, timeout=15)
    return [value for value in result.stdout.split() if value.isdecimal()] if result.returncode == 0 else []


def smoke(adb: str, serial: str, apk: Path, package: str, seconds: float, output: Path) -> dict:
    target = [adb, "-s", serial]
    installed = command(target + ["install", "-r", str(apk)])
    if "Success" not in installed:
        raise ValueError("adb did not confirm successful installation")
    # Force-stop is scoped to this verified package; progression is preserved.
    command(target + ["shell", "am", "force-stop", package])
    command(target + ["shell", "monkey", "-p", package, "-c", "android.intent.category.LAUNCHER", "1"])
    deadline = time.monotonic() + 15.0
    ids = process_ids(target, package)
    while not ids and time.monotonic() < deadline:
        time.sleep(0.25)
        ids = process_ids(target, package)
    if not ids:
        raise ValueError("APK installed, but its application process did not start")
    pid = ids[0]
    alive = True
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        time.sleep(0.25)
        if pid not in process_ids(target, package):
            alive = False
            break
    logs = command(target + ["logcat", "-d", "-v", "threadtime", "--pid=" + pid, "-t", "1000"])
    output.mkdir(parents=True, exist_ok=True)
    (output / "logcat.log").write_text(logs, encoding="utf-8")
    if not alive:
        raise ValueError("Application exited/restarted during the startup smoke check; inspect logcat.log")
    faults = [line for line in logs.splitlines()
              if re.search(r"SCRIPT ERROR:|SHADER ERROR:|\bERROR:|FATAL EXCEPTION|Fatal signal", line)]
    if faults:
        raise ValueError("Application reported startup errors:\n" + "\n".join(faults[:12]))
    return {"serial": serial, "package": package, "pid": pid,
            "startup_seconds": seconds, "smoke_passed": True,
            "manual_touch_lifecycle_performance_qa_pending": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=Path(os.environ.get("APK", ROOT / "build/LastStandArena-debug.apk")))
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--preset", default=os.environ.get("PRESET_NAME", "Android"))
    parser.add_argument("--presets", type=Path, default=ROOT / "export_presets.cfg")
    parser.add_argument("--output", type=Path, default=ROOT / "build/device-qa")
    parser.add_argument("--startup-seconds", type=float, default=5.0)
    parser.add_argument("--checklist", action="store_true")
    args = parser.parse_args()
    if args.checklist:
        print("CHECKLIST ONLY — no APK or device validation has been performed.\n")
        print((ROOT / "docs/DEVICE_QA.md").read_text(encoding="utf-8"))
        return 0
    if not 0.0 <= args.startup_seconds <= 60.0:
        parser.error("--startup-seconds must be between 0 and 60")
    report = {"smoke_passed": False, "status": "IN PROGRESS", "manual_touch_lifecycle_performance_qa_pending": True}
    status = 1
    try:
        owned_reports = [args.output / name for name in ("result.json", "apk-validation.json", "logcat.log")]
        if args.apk.resolve() in [path.resolve() for path in owned_reports]:
            raise ValueError("Device QA report paths must not overwrite the APK")
        args.output.mkdir(parents=True, exist_ok=True)
        for path in owned_reports:
            path.unlink(missing_ok=True)
        (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        adb = shutil.which("adb")
        if not adb:
            raise PrerequisiteError("adb missing: install Android platform-tools; use --checklist for instructions only")
        serial = choose_device(command([adb, "devices"]), args.serial)
        metadata = verify(args.apk.resolve(), args.presets, args.preset, None)
        # A legacy PKG override is allowed only when it matches the ACTUAL APK,
        # not a different already-installed application that could fake success.
        if os.environ.get("PKG", metadata["package"]) != metadata["package"]:
            raise ValueError("PKG must match the APK's verified package/unique_name")
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "apk-validation.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        report = smoke(adb, serial, args.apk.resolve(), metadata["package"], args.startup_seconds, args.output)
        report["status"] = "SMOKE PASSED"
        print("Android install/launch smoke passed. Complete docs/DEVICE_QA.md on this device.")
        status = 0
    except PrerequisiteError as error:
        report["status"] = "NOT TESTED"
        report["error"] = str(error)
        print(f"NOT TESTED: {error}", file=sys.stderr)
        status = 2
    except (OSError, ValueError, KeyError, IndexError, configparser.Error, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        report["status"] = "FAILED"
        report["error"] = str(error)
        print(f"FAILED: Android device smoke: {error}", file=sys.stderr)
    try:
        if args.apk.resolve() == (args.output / "result.json").resolve():
            return 1
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except OSError as error:
        print(f"Could not write device QA report: {error}", file=sys.stderr)
        return 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
