"""Android-specific regressions. SDK/adb subprocesses are fakes; no device result
is claimed. Native input/lifecycle behavior has a registered GDScript suite too.
"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

from tool import check_android_apk as apkcheck
from tool import android_device_qa as deviceqa

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


def body(path, name):
    return read(path).split("func " + name + "(", 1)[1].split("\nfunc ", 1)[0]


def elf(abi="arm64-v8a"):
    header = bytearray(64)
    header[:4] = b"\x7fELF"
    header[4], machine = apkcheck.ELF_ABIS[abi]
    header[5:7] = b"\x01\x01"
    struct.pack_into("<HH", header, 16, 3, machine)
    return bytes(header) + b"fixture library bytes"


def badging(debug=True, package="com.laststandarena.game", permission="android.permission.VIBRATE"):
    return (f"package: name='{package}' versionCode='4' versionName='0.7.0'\n"
            "sdkVersion:'24'\ntargetSdkVersion:'34'\n"
            "launchable-activity: name='com.godot.game.GodotApp' label='Station Zero'\n"
            + ("application-debuggable\n" if debug else "")
            + f"uses-permission: name='{permission}'\n")


def xmltree(renderer="mobile"):
    return ('E: manifest\n  E: application\n    E: meta-data\n'
            '      A: android:name(0x01010003)="org.godotengine.rendering.method"\n'
            f'      A: android:value(0x01010024)="{renderer}"\n')


class AndroidRuntimeSourceTests(unittest.TestCase):
    def test_skills_and_pause_use_native_multitouch_not_mouse_emulation(self):
        self.assertIn("TouchButtonInput.attach(button)", read("scripts/ui/skill_bar.gd"))
        self.assertIn("TouchButtonInput.attach(_pause_button)", read("scripts/ui/game_hud.gd"))
        adapter = read("scripts/ui/touch_button_input.gd")
        self.assertIn("_button.gui_input.connect(_on_gui_input)", adapter)
        self.assertIn("InputEvent.DEVICE_ID_EMULATION", adapter)
        self.assertIn("_button.accept_event()", adapter)
        self.assertIn("_button.pressed.emit()", adapter)
        self.assertIn("_button.disabled", adapter)
        self.assertIn("_button.can_process()", adapter)
        self.assertIn("touch.index == _touch_index", adapter)
        self.assertIn("touch.canceled", adapter)

    def test_android_skill_hints_do_not_require_a_keyboard(self):
        hint = body("scripts/ui/skill_bar.gd", "_key_hint")
        self.assertIn('OS.has_feature("mobile")', hint)
        self.assertLess(hint.index('return "TAP / READY"'), hint.index("UiCommands.binding"))

    def test_android_cancel_cannot_recapture_camera_or_joystick(self):
        touch = body("scripts/main/camera_rig.gd", "_handle_look_touch")
        self.assertLess(touch.index("touch.canceled"), touch.index("if touch.pressed"))
        self.assertNotIn("_look_touch_index = drag.index", read("scripts/main/camera_rig.gd"))
        self.assertIn("cancel_touch_input()", body("scripts/main/camera_rig.gd", "_notification"))
        joystick = body("scripts/ui/virtual_joystick.gd", "_gui_input")
        self.assertIn("InputEvent.DEVICE_ID_EMULATION", joystick)
        self.assertIn("event.canceled", joystick)
        self.assertIn("event.canceled", body("scripts/ui/virtual_joystick.gd", "_input"))

    def test_cutout_changes_are_watched_without_resetting_every_poll(self):
        safe = read("scripts/ui/safe_area.gd")
        self.assertIn("signal safe_area_changed", safe)
        self.assertIn("REFRESH_INTERVAL", body("scripts/ui/safe_area.gd", "_process"))
        self.assertIn("NOTIFICATION_APPLICATION_RESUMED", safe)
        self.assertIn("safe.intersection", safe)
        apply = body("scripts/ui/safe_area.gd", "_apply_margins")
        self.assertLess(apply.index("margins == _last_margins"), apply.index("offset_left ="))
        self.assertNotIn("set_anchors_and_offsets_preset", apply)
        self.assertIn("_safe.safe_area_changed.connect", read("scripts/ui/ui_root.gd"))
        self.assertIn("_cancel_camera_touch()", body("scripts/ui/ui_root.gd", "_show_screen"))

    def test_resume_and_focus_are_separate_mute_inputs(self):
        source = body("scripts/audio/audio_manager.gd", "_notification")
        self.assertIn("_application_paused = true", source)
        self.assertIn("_application_paused = false", source)
        self.assertIn("_application_focused = true", source)
        self.assertIn("_application_focused = false", source)
        self.assertIn("NOTIFICATION_APPLICATION_FOCUS_IN", source)
        self.assertIn("_application_paused or not _application_focused", source)
        self.assertNotIn("request_resume()", body("scripts/core/game_root.gd", "_notification"))

    def test_android_runtime_renderer_fps_and_export_exclusions_stay_mobile(self):
        project = read("project.godot")
        self.assertIn('renderer/rendering_method.mobile="mobile"', project)
        self.assertIn("run/max_fps.android=60", project)
        self.assertIn("common/physics_ticks_per_second=60", project)
        self.assertIn("anti_aliasing/quality/msaa_3d.android=1", project)
        for name in ("export_presets.cfg", "export_presets.cfg.example"):
            preset = read(name)
            for excluded in ("build/*", ".cache/*", "docs/godot-runs/*"):
                self.assertIn(excluded, preset)
            self.assertIn('command_line/extra_args=""', preset)
        self.assertEqual(read("export_presets.cfg"), read("export_presets.cfg.example"))

    def test_new_native_regressions_are_registered(self):
        self.assertIn("tests/unit/test_android_runtime.gd", read("tests/run_tests.gd"))
        self.assertIn("await _test_android_controls_and_interruption()", read("tests/ui/ui_test_runner.gd"))
        self.assertIn("SaveManager._notification(Node.NOTIFICATION_APPLICATION_PAUSED)", read("tests/ui/ui_test_runner.gd"))

    def test_ci_verifies_android_apk_and_installs_the_engine_sdk(self):
        ci = read(".github/workflows/android.yml")
        self.assertIn("tool/check_android_apk.py", ci)
        self.assertIn('"platforms;android-34" "build-tools;34.0.0"', ci)
        self.assertIn("code=${PIPESTATUS[1]}", ci)
        self.assertIn("tool/check_android_apk.py", read("scripts/build_android.sh"))


class AndroidApkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.apk = self.root / "game with spaces.apk"
        self.make_apk()
        self.expected = apkcheck.expected_options(ROOT / "export_presets.cfg", "Android")

    def make_apk(self, extra=None, omit=None):
        files = {"AndroidManifest.xml": b"binary manifest fixture", "assets/project.binary": b"project",
                 "lib/arm64-v8a/libgodot_android.so": elf(),
                 "assets/data/campaign/station_zero.json": (ROOT / "data/campaign/station_zero.json").read_bytes()}
        if extra:
            files.update(extra)
        if omit:
            files.pop(omit)
            if omit == "assets/project.binary":
                files.pop("assets/data/campaign/station_zero.json", None)
        with zipfile.ZipFile(self.apk, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, data)

    def test_required_campaign_is_checked_inside_the_apk(self):
        report = apkcheck.inspect_campaign(self.apk)
        self.assertEqual(report["authored_enemies"], 29)
        self.assertEqual(report["world_id"], "station_zero")
        self.make_apk(omit="assets/data/campaign/station_zero.json")
        with self.assertRaisesRegex(ValueError, "missing the required"):
            apkcheck.inspect_campaign(self.apk)

    def test_invalid_campaign_cannot_pass_as_a_nonempty_asset(self):
        for payload in [b"{}", b"not JSON", b'{"world_id":"other"}']:
            self.make_apk({"assets/data/campaign/station_zero.json": payload})
            with self.assertRaises(ValueError):
                apkcheck.inspect_campaign(self.apk)

    def actual(self, **kwargs):
        actual = apkcheck.parse_badging(badging(**kwargs))
        actual["abis"] = ["arm64-v8a"]
        return actual

    def test_real_presets_agree_with_android_package_contract(self):
        self.assertEqual(self.expected["min_sdk"], 24)
        self.assertEqual(self.expected["target_sdk"], 34)
        self.assertEqual(self.expected["abis"], ["arm64-v8a"])
        self.assertEqual(self.expected, apkcheck.expected_options(ROOT / "export_presets.cfg.example", "Android"))
        apkcheck.validate_manifest(self.actual(), self.expected, "debug")

    def test_empty_or_wrong_native_architecture_is_rejected(self):
        for payload in (b"", b"not a library", elf("x86_64")):
            self.make_apk({"lib/arm64-v8a/libgodot_android.so": payload})
            with self.assertRaises(ValueError):
                apkcheck.inspect_archive(self.apk)

    def test_missing_manifest_assets_or_godot_library_fail(self):
        for entry in ("AndroidManifest.xml", "assets/project.binary", "lib/arm64-v8a/libgodot_android.so"):
            self.make_apk(omit=entry)
            with self.assertRaises(ValueError):
                apkcheck.inspect_archive(self.apk)

    def test_test_logs_and_device_reports_are_not_shipped(self):
        for root in apkcheck.FORBIDDEN_ASSETS:
            self.make_apk({root + "fixture.json": b"private development data"})
            with self.assertRaises(ValueError):
                apkcheck.inspect_archive(self.apk)

    def test_actual_package_sdk_versions_and_abis_must_match(self):
        for key, value in (("package", "com.other.game"), ("version_name", "0.1"),
                           ("version_code", 3), ("min_sdk", 21), ("target_sdk", 33),
                           ("abis", ["x86_64"])):
            actual = self.actual()
            actual[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                apkcheck.validate_manifest(actual, self.expected, "debug")

    def test_permissions_are_checked_on_apk_not_just_preset(self):
        actual = self.actual()
        actual["permissions"].append("android.permission.INTERNET")
        apkcheck.validate_manifest(actual, self.expected, "debug")
        for permission in ("android.permission.INTERNET", "android.permission.RECORD_AUDIO", "android.permission.READ_EXTERNAL_STORAGE"):
            actual = self.actual(debug=False)
            actual["permissions"].append(permission)
            with self.assertRaises(ValueError):
                apkcheck.validate_manifest(actual, self.expected, "release")
        with self.assertRaises(ValueError):
            apkcheck.validate_manifest(self.actual(permission="android.permission.INTERNET"), self.expected, "debug")

    def test_launcher_and_debuggable_flag_are_not_optional(self):
        with self.assertRaises(ValueError):
            apkcheck.parse_badging(badging().replace("launchable-activity:", "not-launchable:"))
        with self.assertRaises(ValueError):
            apkcheck.validate_manifest(self.actual(), self.expected, "release")

    def test_signature_verification_and_report_are_part_of_success(self):
        with mock.patch.object(apkcheck, "sdk_tool", side_effect=lambda names: names[0]), \
             mock.patch.object(apkcheck, "run_tool", side_effect=[badging(), xmltree(), "Verifies\n"]) as run:
            report = apkcheck.verify(self.apk, ROOT / "export_presets.cfg", "Android", "debug")
        self.assertTrue(report["valid"] and report["signature_verified"])
        self.assertFalse(report["device_tested"])
        self.assertEqual(len(report["sha256"]), 64)
        self.assertEqual(run.call_args_list[2].args[0][:3], ["apksigner", "verify", "--verbose"])

    def test_invalid_signature_or_debug_certificate_cannot_pass_release(self):
        for signature in (ValueError("bad signature"), "Signer #1 certificate DN: CN=Android Debug, O=Android"):
            with mock.patch.object(apkcheck, "sdk_tool", side_effect=lambda names: names[0]), \
                 mock.patch.object(apkcheck, "run_tool", side_effect=[badging(debug=False), xmltree(), signature]):
                with self.assertRaises(ValueError):
                    apkcheck.verify(self.apk, ROOT / "export_presets.cfg", "Android", "release")

    def test_host_renderer_cannot_leak_into_android_manifest(self):
        with mock.patch.object(apkcheck, "sdk_tool", side_effect=lambda names: names[0]), \
             mock.patch.object(apkcheck, "run_tool", side_effect=[badging(), xmltree("gl_compatibility")]):
            with self.assertRaisesRegex(ValueError, "renderer mismatch"):
                apkcheck.verify(self.apk, ROOT / "export_presets.cfg", "Android", "debug")
        with self.assertRaises(ValueError):
            apkcheck.renderer_metadata('E: application\n A: android:value="mobile"')

    def test_failed_validation_replaces_stale_success_report(self):
        report = self.root / "validation.json"
        report.write_text('{"valid": true}')
        with mock.patch.object(sys, "argv", ["checker", str(self.apk), "--report", str(report)]), \
             mock.patch.object(apkcheck, "verify", side_effect=ValueError("missing SDK")):
            self.assertEqual(apkcheck.main(), 1)
        self.assertFalse(json.loads(report.read_text())["valid"])


class AndroidExportAndDeviceTests(unittest.TestCase):
    def test_export_never_uses_host_compatibility_renderer_or_xvfb(self):
        with tempfile.TemporaryDirectory() as temporary:
            engine = Path(temporary) / "godot"
            engine.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
            engine.chmod(0o755)
            env = dict(os.environ, GODOT_BIN=str(engine))
            env.pop("DISPLAY", None)
            for kind in ("--export-debug", "--export-release"):
                result = subprocess.run(["bash", str(ROOT / "scripts/run_godot.sh"), "--path", ".", kind, "Android", "out.apk"],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines(), ["--headless", "--path", ".", kind, "Android", "out.apk"])
            result = subprocess.run(["bash", str(ROOT / "scripts/run_godot.sh"), "--rendering-method", "gl_compatibility", "--export-debug", "Android", "out.apk"],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")

    def test_no_arbitrary_first_device_or_unauthorized_device(self):
        listing = "List of devices attached\nphone-a\tdevice\nphone-b\tdevice\nphone-c\tunauthorized\n"
        self.assertEqual(deviceqa.choose_device(listing, "phone-b"), "phone-b")
        for requested in (None, "phone-c", "missing"):
            with self.assertRaises(deviceqa.PrerequisiteError):
                deviceqa.choose_device(listing, requested)
        self.assertEqual(deviceqa.choose_device("List of devices attached\nphone-a\tdevice\n", None), "phone-a")

    def test_missing_adb_is_not_reported_as_a_pass(self):
        with tempfile.TemporaryDirectory() as temporary, \
             mock.patch.object(sys, "argv", ["qa", "--output", temporary]), \
             mock.patch.object(deviceqa.shutil, "which", return_value=None):
            self.assertEqual(deviceqa.main(), 2)
            self.assertFalse(json.loads((Path(temporary) / "result.json").read_text())["smoke_passed"])

    def test_install_failure_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as temporary, \
             mock.patch.object(deviceqa, "command", return_value="Failure [INSTALL_FAILED]") as command:
            with self.assertRaises(ValueError):
                deviceqa.smoke("adb", "phone-a", Path("app.apk"), "com.laststandarena.game", 0, Path(temporary))
            self.assertEqual(command.call_count, 1)

    def test_smoke_is_serial_scoped_and_preserves_app_data(self):
        with tempfile.TemporaryDirectory() as temporary, \
             mock.patch.object(deviceqa, "command", side_effect=["Success", "", "Events injected: 1", "I godot: menu ready"]) as run, \
             mock.patch.object(deviceqa, "process_ids", return_value=["42"]):
            report = deviceqa.smoke("adb", "phone-a", Path("app.apk"), "com.laststandarena.game", 0, Path(temporary))
            self.assertTrue(report["smoke_passed"])
            self.assertTrue(report["manual_touch_lifecycle_performance_qa_pending"])
            for call in run.call_args_list:
                self.assertEqual(call.args[0][:3], ["adb", "-s", "phone-a"])
                self.assertNotIn("uninstall", call.args[0])
                self.assertNotIn("clear", call.args[0])
            self.assertIn("--pid=42", run.call_args_list[-1].args[0])

    def test_logcat_script_errors_fail_smoke(self):
        with tempfile.TemporaryDirectory() as temporary, \
             mock.patch.object(deviceqa, "command", side_effect=["Success", "", "Events injected: 1", "E godot: SCRIPT ERROR: bad node"]), \
             mock.patch.object(deviceqa, "process_ids", return_value=["42"]):
            with self.assertRaises(ValueError):
                deviceqa.smoke("adb", "phone-a", Path("app.apk"), "com.laststandarena.game", 0, Path(temporary))
            self.assertTrue((Path(temporary) / "logcat.log").exists())


if __name__ == "__main__":
    unittest.main()
