#!/usr/bin/env python3
"""Verify a real Android APK, not just a nonempty ZIP.

Requires Android SDK build-tools (aapt2/aapt and apksigner) + Java. Checks the
exported identity, SDK levels, launcher, ABIs, permissions and signature. This is
packaging validation, NOT a claim that touch/rendering/performance ran on a phone.
"""
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import zipfile

try:  # Package import in tests, direct script import in the build wrapper.
    from .validate_campaign import validate as validate_campaign, unique_object
except ImportError:
    from validate_campaign import validate as validate_campaign, unique_object

ROOT = Path(__file__).resolve().parents[1]
ABI_OPTIONS = ("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
ELF_ABIS = {"armeabi-v7a": (1, 40), "arm64-v8a": (2, 183), "x86": (1, 3), "x86_64": (2, 62)}
FORBIDDEN_ASSETS = ("assets/tests/", "assets/tool/", "assets/build/", "assets/.cache/", "assets/docs/godot-runs/")


def unquote(value: str) -> str:
    return value.strip().strip('"')


def expected_options(presets: Path, name: str) -> dict:
    config = configparser.ConfigParser(interpolation=None)
    if not config.read(presets, encoding="utf-8"):
        raise ValueError(f"Missing export presets: {presets}")
    for section in config.sections():
        if not re.fullmatch(r"preset\.\d+", section):
            continue
        if unquote(config[section].get("name", "")) != name:
            continue
        if unquote(config[section].get("platform", "")) != "Android":
            raise ValueError(f"Preset {name} is not Android")
        options = config[section + ".options"]
        return {
            "package": unquote(options["package/unique_name"]),
            "version_name": unquote(options["version/name"]),
            "version_code": int(options["version/code"]),
            "min_sdk": int(unquote(options["gradle_build/min_sdk"])),
            "target_sdk": int(unquote(options["gradle_build/target_sdk"])),
            "abis": sorted(abi for abi in ABI_OPTIONS if options.get("architectures/" + abi) == "true"),
        }
    raise ValueError(f"Android preset not found: {name}")


def inspect_archive(apk: Path) -> list[str]:
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("APK has duplicate ZIP entries")
        if archive.testzip() is not None or "AndroidManifest.xml" not in names:
            raise ValueError("APK has an invalid ZIP or missing AndroidManifest.xml")
        if not archive.getinfo("AndroidManifest.xml").file_size:
            raise ValueError("APK manifest is empty")
        leaked = [name for name in names if name.startswith(FORBIDDEN_ASSETS)]
        if leaked:
            raise ValueError(f"Developer/test data leaked into APK: {leaked[:5]}")
        if not any(name.startswith("assets/") and not name.endswith("/") for name in names):
            raise ValueError("APK has no game assets")
        libraries = [name for name in names if re.fullmatch(r"lib/[^/]+/libgodot_android\.so", name)]
        if not libraries or any(archive.getinfo(name).file_size == 0 for name in libraries):
            raise ValueError("APK has no nonempty Godot Android native library")
        abis = set()
        for name in names:
            if not re.fullmatch(r"lib/[^/]+/[^/]+\.so", name):
                continue
            abi = name.split("/")[1]
            with archive.open(name) as library:
                header = library.read(64)
            if abi not in ELF_ABIS or len(header) < 52 or header[:4] != b"\x7fELF" or header[5] != 1:
                raise ValueError(f"Invalid Android ELF library: {name}")
            elf_class, machine = ELF_ABIS[abi]
            elf_type, actual_machine = struct.unpack_from("<HH", header, 16)
            if len(header) < (64 if elf_class == 2 else 52) or header[6] != 1:
                raise ValueError(f"Truncated/invalid ELF header: {name}")
            if header[4] != elf_class or actual_machine != machine or elf_type != 3:
                raise ValueError(f"Native library architecture mismatch: {name}")
            abis.add(abi)
        return sorted(abis)


def inspect_campaign(apk: Path) -> dict:
    """The configured non-OBB Android export must contain the actual JSON world.

    A generic asset or an old arena APK cannot stand in for this required file.
    Alternate packed/encrypted/OBB exports need an explicit reader before release;
    do not silently waive this check when changing the export configuration.
    """
    name = "assets/data/campaign/station_zero.json"
    with zipfile.ZipFile(apk) as archive:
        if name not in archive.namelist():
            raise ValueError("APK is missing the required Station Zero campaign JSON")
        info = archive.getinfo(name)
        if not 0 < info.file_size <= 1 << 20:
            raise ValueError("APK campaign JSON is empty or oversized")
        payload = archive.read(name)
    data = json.loads(payload.decode("utf-8"), object_pairs_hook=unique_object)
    try:
        report = validate_campaign(data)
    except (TypeError, KeyError) as error:
        raise ValueError(f"APK campaign data is malformed: {error}") from error
    return {"world_id": data["world_id"], "sha256": hashlib.sha256(payload).hexdigest(), **report}


def sdk_tool(names: tuple[str, ...]) -> str:
    # Explicit tool directory supports Android Studio installations outside the
    # default SDK path. Otherwise prefer the pinned engine's build-tools version.
    directories = []
    if os.environ.get("ANDROID_BUILD_TOOLS_DIR"):
        directories.append(Path(os.environ["ANDROID_BUILD_TOOLS_DIR"]))
    for key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        if not os.environ.get(key):
            continue
        base = Path(os.environ[key]) / "build-tools"
        pinned = base / "34.0.0"  # Godot 4.4.1's Android template
        directories.append(pinned)
        if base.is_dir():
            directories.extend(sorted((p for p in base.iterdir() if p.is_dir() and p != pinned), reverse=True))
    for directory in directories:
        for name in names:
            candidate = directory / name
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return str(candidate)
    for name in names:
        located = shutil.which(name)
        if located:
            return located
    raise ValueError(f"Android SDK tool missing: {' / '.join(names)}. Install build-tools and Java 17.")


def run_tool(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise ValueError(f"{Path(command[0]).name} failed ({result.returncode}): {(result.stderr or result.stdout)[-1800:]}")
    return result.stdout


def parse_badging(text: str) -> dict:
    def quoted(label: str) -> str:
        match = re.search(r"^" + re.escape(label) + r":'([^']+)'", text, re.M)
        if not match:
            raise ValueError(f"APK manifest missing {label}")
        return match[1]

    package = re.search(r"^package: (.+)$", text, re.M)
    if not package:
        raise ValueError("APK manifest missing package identity")
    fields = dict(re.findall(r"([A-Za-z]+)='([^']*)'", package[1]))
    activity = re.search(r"^launchable-activity: name='([^']+)'", text, re.M)
    if not activity:
        raise ValueError("APK has no launchable activity")
    return {
        "package": fields.get("name", ""),
        "version_name": fields.get("versionName", ""),
        "version_code": int(fields.get("versionCode", "-1")),
        "min_sdk": int(quoted("sdkVersion")),
        "target_sdk": int(quoted("targetSdkVersion")),
        "launcher": activity[1],
        "debuggable": bool(re.search(r"^application-debuggable(?:\s|$)", text, re.M)),
        "permissions": sorted(set(re.findall(r"^uses-permission(?:-sdk-\d+)?: name='([^']+)'", text, re.M))),
    }


def renderer_metadata(xmltree: str) -> str:
    # aapt/aapt2 xmltree resolves the string-pool values. Bound each metadata
    # element separately so a nearby unrelated android:value cannot match.
    # Attribute names are printed short by old aapt2 ("android:name") but
    # namespace-prefixed by build-tools 34 aapt2
    # ("http://schemas.android.com/apk/res/android:name"), so anchor on the
    # suffix, never crossing an '=' inside a single line.
    attr = r'A:\s*[^\n=]*{}\s*(?:\([0-9a-fx]+\))?\s*=\s*"([^"\n]*)"'
    blocks = re.split(r"^\s*E:", xmltree, flags=re.M)
    for block in blocks:
        if not block.lstrip().startswith("meta-data"):
            continue
        name = re.search(attr.format("android:name"), block)
        value = re.search(attr.format("android:value"), block)
        if name and name[1] == "org.godotengine.rendering.method" and value:
            return value[1]
    raise ValueError("APK manifest lacks Godot rendering-method metadata")


def project_renderer(project: Path = ROOT / "project.godot") -> str:
    text = project.read_text(encoding="utf-8")
    section = text.split("[rendering]", 1)[1].split("\n[", 1)[0]
    for key in ("renderer/rendering_method.android", "renderer/rendering_method.mobile", "renderer/rendering_method"):
        match = re.search(r'^' + re.escape(key) + r'="([^"]+)"$', section, re.M)
        if match:
            return match[1]
    raise ValueError("Android rendering method is not configured in project.godot")


def validate_manifest(actual: dict, expected: dict, build_type: str) -> None:
    for key in ("package", "version_name", "version_code", "min_sdk", "target_sdk", "abis"):
        if actual[key] != expected[key]:
            raise ValueError(f"APK {key} mismatch: expected {expected[key]!r}, found {actual[key]!r}")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", actual["package"]):
        raise ValueError("Invalid Android application ID")
    if actual["debuggable"] != (build_type == "debug"):
        raise ValueError(f"APK debuggable flag does not match {build_type} build")
    allowed = {"android.permission.VIBRATE"}
    if build_type == "debug":
        allowed.add("android.permission.INTERNET")  # Godot remote debugger
    permissions = set(actual["permissions"])
    if "android.permission.VIBRATE" not in permissions or permissions - allowed:
        raise ValueError(f"APK violates the offline/haptics permission policy: {sorted(permissions)}")


def verify(apk: Path, presets: Path, preset: str, build_type: str | None) -> dict:
    abis = inspect_archive(apk)
    campaign = inspect_campaign(apk)
    aapt = sdk_tool(("aapt2", "aapt"))
    actual = parse_badging(run_tool([aapt, "dump", "badging", str(apk)]))
    xml_args = ["--file", "AndroidManifest.xml", str(apk)] if Path(aapt).name.startswith("aapt2") else [str(apk), "AndroidManifest.xml"]
    actual["renderer"] = renderer_metadata(run_tool([aapt, "dump", "xmltree", *xml_args]))
    if actual["renderer"] != project_renderer():
        raise ValueError(f"APK renderer mismatch: expected {project_renderer()}, found {actual['renderer']} (host override leaked into export)")
    actual["abis"] = abis
    kind = build_type or ("debug" if actual["debuggable"] else "release")
    validate_manifest(actual, expected_options(presets, preset), kind)
    signature = run_tool([sdk_tool(("apksigner",)), "verify", "--verbose", "--print-certs", str(apk)])
    if kind == "release" and re.search(r"CN\s*=\s*Android Debug(?:,|\s|$)", signature, re.I):
        raise ValueError("Release APK uses an Android debug signing certificate")
    actual.update(valid=True, build_type=kind, signature_verified=True, apk=str(apk),
                  sha256=hashlib.sha256(apk.read_bytes()).hexdigest(), size_bytes=apk.stat().st_size,
                  device_tested=False, campaign=campaign)
    return actual


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--presets", type=Path, default=ROOT / "export_presets.cfg")
    parser.add_argument("--preset", default="Android")
    parser.add_argument("--build-type", choices=("debug", "release"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.report and args.report.resolve() == args.apk.resolve():
        print("ERROR: The validation report must not overwrite the APK", file=sys.stderr)
        return 1
    try:
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text('{"valid": false, "status": "IN PROGRESS", "device_tested": false}\n', encoding="utf-8")
        report = verify(args.apk.resolve(), args.presets, args.preset, args.build_type)
        encoded = json.dumps(report, indent=2) + "\n"
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(encoded, encoding="utf-8")
        print(encoded, end="")
        return 0
    except (OSError, ValueError, KeyError, IndexError, configparser.Error, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        if args.report:
            try:
                args.report.write_text(json.dumps({"valid": False, "status": "FAILED", "error": str(error), "device_tested": False}, indent=2) + "\n", encoding="utf-8")
            except OSError:
                pass
        print(f"ERROR: Android APK validation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
