"""Behavioral audit regressions for fail-closed logs and safe local builds.

All subprocesses use disposable projects/profiles and local fake downloads. No
Godot executable, network, Android SDK, signing material or real saves are used.
"""
from __future__ import annotations

import ast
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

from tool.check_godot_log import validate_log

ROOT = Path(__file__).resolve().parents[2]
SUMMARY = r"^GDScript tests: [1-9][0-9]* total, 0 failed$"
SUCCESS = "Godot Engine v4.4.1.stable\nGDScript tests: 42 total, 0 failed\n"


class TestProfileTests(unittest.TestCase):
    def test_profiles_isolate_home_and_xdg_not_just_linux_saves(self):
        with tempfile.TemporaryDirectory() as temporary:
            profile = Path(temporary) / "test profile"
            result = subprocess.run([
                "bash", "-c", 'source "$1"; godot_test_profile "$2"; printf "%s\\n" "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"',
                "audit", str(ROOT / "scripts/godot_test_env.sh"), str(profile),
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), [str(profile / name) for name in ("home", "data", "config", "cache")])
            self.assertTrue(all((profile / name).is_dir() for name in ("home", "data", "config", "cache")))

    def test_timeout_preserves_engine_failure_and_bounds_hung_runs(self):
        for command, expected in (("raise SystemExit(7)", 7), ("import time; time.sleep(3)", 124)):
            result = subprocess.run([
                "bash", "-c", 'source "$1"; godot_test_timeout 0.15 "$2" -c "$3"',
                "audit", str(ROOT / "scripts/godot_test_env.sh"), sys.executable, command,
            ], capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, expected, result.stderr)


class ResourceEncodingTests(unittest.TestCase):
    def test_utf8_resources_and_literal_backslashes_are_valid(self):
        from tool import validate_resources
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "copy.tres"
            header = '[gd_resource type="Resource" format=3]\n[resource]\n'
            for value in ('description = "Survive — together"\n',
                          'description = "literal \\\\u2014"\n'):
                path.write_text(header + value, encoding="utf-8")
                problems = []
                validate_resources.check_file(str(path), problems)
                self.assertEqual(problems, [])
            path.write_text(header + 'description = "unsafe \\u2014"\n', encoding="utf-8")
            problems = []
            validate_resources.check_file(str(path), problems)
            self.assertTrue(any("escaped Unicode" in p for p in problems))
            path.write_text("")
            problems = []
            validate_resources.check_file(str(path), problems)
            self.assertTrue(any("empty resource" in p for p in problems))


class NativeRendererTests(unittest.TestCase):
    def test_explicit_headless_and_virtual_display_commands(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine = root / "engine"
            engine.write_text('#!/bin/sh\nprintf "ENGINE: %s\\n" "$*"\n')
            engine.chmod(0o755)
            virtual = root / "xvfb-run"
            virtual.write_text('#!/bin/sh\nprintf "SOFTWARE: %s\\n" "$LIBGL_ALWAYS_SOFTWARE"\nshift 3\nexec "$@"\n')
            virtual.chmod(0o755)
            env = dict(os.environ, GODOT_BIN=str(engine), PATH=str(root) + os.pathsep + os.environ["PATH"])
            env.pop("DISPLAY", None)
            # Importing touches no display or GL context, so it always runs
            # headless: the editor's Vulkan/audio probes on a CI host print
            # environment ERROR lines that must never reach the strict gate.
            for headless in ("0", "1"):
                env["GODOT_HEADLESS"] = headless
                result = subprocess.run(["bash", str(ROOT / "scripts/run_godot.sh"), "--path", ".", "--import"],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "ENGINE: --headless --path . --import")
            # Scene-running steps stay native (real GL under a virtual display)
            # with deterministic host driver pins.
            env["GODOT_HEADLESS"] = "0"
            result = subprocess.run(["bash", str(ROOT / "scripts/run_godot.sh"),
                                     "--path", ".", "--script", "res://tests/run_tests.gd"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(),
                             "SOFTWARE: 1\nENGINE: --rendering-method gl_compatibility "
                             "--rendering-driver opengl3 --audio-driver Dummy "
                             "--path . --script res://tests/run_tests.gd")


class GodotLogTests(unittest.TestCase):
    def test_clean_success(self):
        self.assertEqual(validate_log(SUCCESS, required=SUMMARY), [])

    def test_zero_exit_does_not_hide_script_or_engine_errors(self):
        for message in ("SCRIPT ERROR: Invalid access", "ERROR: Failed loading resource",
                        "Parse Error: Wrong type", "Compile Error: Missing member",
                        "UI FAIL: inaccessible button", "  FAIL  a broken assertion",
                        "Unicode parsing error: Invalid unicode codepoint",
                        "WARNING: ObjectDB instances leaked at exit"):
            with self.subTest(message=message):
                self.assertTrue(validate_log(message + "\n" + SUCCESS, required=SUMMARY))

    def test_ansi_colored_errors_are_not_hidden(self):
        self.assertTrue(validate_log("\x1b[31mERROR: bad resource\x1b[0m\n" + SUCCESS))

    def test_nonzero_exit_overrides_successful_summary(self):
        self.assertTrue(validate_log(SUCCESS, exit_code=124, required=SUMMARY))

    def test_empty_or_skipped_suites_fail(self):
        for text in ("", "Godot Engine v4.4.1\n", "GDScript tests: 0 total, 0 failed\n"):
            with self.subTest(text=text):
                self.assertTrue(validate_log(text, required=SUMMARY))

    def test_expected_warnings_are_not_errors(self):
        self.assertEqual(validate_log("WARNING: testing a fallback\n" + SUCCESS, required=SUMMARY), [])

    def test_negative_diagnostics_require_exact_bounded_expectations(self):
        start = 'TEST EXPECTED ERRORS: ["ERROR: deliberate bad fixture"]\n'
        end = 'TEST EXPECTED ERRORS END\n'
        message = 'ERROR: deliberate bad fixture\n'
        valid = start + message + end + SUCCESS
        self.assertTrue(validate_log(valid, required=SUMMARY))  # Not allowed on production logs.
        self.assertEqual(validate_log(valid, required=SUMMARY, allow_test_errors=True), [])
        for text in (start + end, start + message, start + message * 2 + end,
                     start + message + 'SCRIPT ERROR: unrelated bug\n' + end,
                     start + start + message + end,
                     'TEST EXPECTED ERRORS: ["SCRIPT ERROR: never suppress this"]\n' + end):
            with self.subTest(text=text):
                self.assertTrue(validate_log(text + SUCCESS, required=SUMMARY, allow_test_errors=True))

    def test_engine_noise_demotion_is_opt_in_and_context_bound(self):
        pairs = (
            ('ERROR: Parameter "material" is null.\n'
             "   at: material_casts_shadows (drivers/gles3/storage/material_storage.cpp:2501)"),
            ('ERROR: Parameter "t" is null.\n'
             "   at: texture_2d_get (servers/rendering/dummy/storage/texture_storage.h:107)"),
            ("ERROR: Texture with GL ID of 105: leaked 22369620 bytes.\n"
             "   at: ~Utilities (drivers/gles3/storage/utilities.cpp:77)"),
            ("WARNING: ObjectDB instances leaked at exit (run with `--verbose` for details).\n"
             "     at: cleanup (core/object/object.cpp:2378)"),
            ("WARNING: 10 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
             "     at: cleanup (core/object/object.cpp:2378)"),
            ("ERROR: 1 resources still in use at exit (run with `--verbose` for details).\n"
             "   at: clear (core/io/resource.cpp:614)"),
        )
        for pair in pairs:
            with self.subTest(pair=pair):
                noisy = validate_log(pair + "\n" + SUCCESS, required=SUMMARY)
                demoted = validate_log(pair + "\n" + SUCCESS, required=SUMMARY,
                                       allow_engine_noise=True)
                if pair.startswith("WARNING: 10"):
                    # The counted ObjectDB spelling never matched the gate.
                    self.assertEqual(noisy, [])
                else:
                    # Default stays strict: every one of these fails without the flag.
                    self.assertTrue(noisy)
                self.assertEqual(demoted, [])
        # The same headline from a different call site is not lifecycle noise.
        novel = ('ERROR: Parameter "material" is null.\n'
                 "   at: material_free (drivers/gles3/storage/material_storage.cpp:99)")
        self.assertTrue(validate_log(novel + "\n" + SUCCESS, required=SUMMARY,
                                     allow_engine_noise=True))
        # Script errors are never demoted, flag or not.
        self.assertTrue(validate_log("SCRIPT ERROR: Invalid access\n" + SUCCESS,
                                     allow_engine_noise=True))

    def test_missing_file_and_invalid_summary_regex_fail_cli(self):
        for extra in ([], ["--require", "["]):
            result = subprocess.run([sys.executable, str(ROOT / "tool/check_godot_log.py"),
                                     "missing-audit-log", *extra], cwd=ROOT,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("Traceback", result.stderr)


class TemplateInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="godot-audit-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project with spaces"
        self.project.mkdir()
        self.data = self.root / "isolated data"
        self.templates = self.data / "godot/export_templates/4.4.1.stable"
        self.templates.mkdir(parents=True)
        self.env = dict(os.environ)
        for name in ("GODOT_VERSION", "GODOT_TEMPLATE_DIR", "KEYSTORE_PATH", "KEYSTORE_PASSWORD",
                     "KEY_PASSWORD", "KEY_ALIAS", "BUILD_TYPE", "PRESET_NAME"):
            self.env.pop(name, None)
        self.env.update(HOME=str(self.root / "home"), XDG_DATA_HOME=str(self.data))

    def source_zip(self, extra=None, omit=None):
        files = {"build.gradle": "// template\n", "gradlew": "#!/bin/sh\nexit 0\n"}
        if omit:
            files.pop(omit)
        if extra:
            files.update(extra)
        with zipfile.ZipFile(self.templates / "android_source.zip", "w") as archive:
            for name, content in files.items():
                archive.writestr(name, content)

    def install(self):
        return subprocess.run(["bash", str(ROOT / "scripts/install_android_build_template.sh"),
                               str(self.project)], env=self.env, capture_output=True, text=True)

    def test_defaults_and_xdg_profile_work_without_godot_version_env(self):
        self.source_zip()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = self.project / "android/build"
        self.assertTrue((build / ".gdignore").is_file())
        self.assertTrue(os.access(build / "gradlew", os.X_OK))
        self.assertEqual((self.project / "android/.build_version").read_text().strip(), "4.4.1.stable")

    def test_matching_install_preserves_customizations_and_needs_no_archive(self):
        self.source_zip()
        self.assertEqual(self.install().returncode, 0)
        custom = self.project / "android/build/build.gradle"
        custom.write_text("// customized by project owner\n")
        (self.templates / "android_source.zip").unlink()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(custom.read_text(), "// customized by project owner\n")

    def test_incomplete_existing_build_is_never_deleted(self):
        self.source_zip()
        build = self.project / "android/build"
        build.mkdir(parents=True)
        (build / "custom.txt").write_text("keep me")
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((build / "custom.txt").read_text(), "keep me")

    def test_incomplete_archive_is_not_committed(self):
        self.source_zip(omit="gradlew")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertFalse((self.project / "android/build").exists())
        self.assertFalse((self.project / "android/.build_version").exists())
        self.assertEqual(list((self.project / "android").glob(".template.*")), [])

    def test_archive_cannot_escape_staging(self):
        for name in ("../../escape.txt", "/escape.txt", "a\\..\\escape.txt"):
            with self.subTest(name=name):
                self.source_zip(extra={name: "bad"})
                self.assertNotEqual(self.install().returncode, 0)
                self.assertFalse((self.project / "android/build").exists())
                self.assertFalse((self.project / "escape.txt").exists())

    def test_symlink_members_are_rejected(self):
        self.source_zip()
        entry = zipfile.ZipInfo("link")
        entry.create_system = 3
        entry.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(self.templates / "android_source.zip", "a") as archive:
            archive.writestr(entry, "../../elsewhere")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertFalse((self.project / "android/build").exists())

    def _fake_download(self, files):
        payload = self.root / "templates.tpz"
        with zipfile.ZipFile(payload, "w") as archive:
            for name, content in files.items():
                archive.writestr("templates/" + name, content)
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        curl = bin_dir / "curl"
        curl.write_text("#!/usr/bin/env python3\nimport os, shutil, sys\n"
                        "shutil.copyfile(os.environ['AUDIT_TEMPLATE_PAYLOAD'], sys.argv[-1])\n")
        curl.chmod(0o755)
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]
        self.env["AUDIT_TEMPLATE_PAYLOAD"] = str(payload)
        return subprocess.run(["bash", str(ROOT / "scripts/install_export_templates.sh")],
                              env=self.env, capture_output=True, text=True)

    def test_export_archive_checks_actual_version_before_installing(self):
        files = {"android_debug.apk": "debug", "android_release.apk": "release",
                 "android_source.zip": "source", "version.txt": "4.5.stable"}
        result = self._fake_download(files)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.templates / "version.txt").exists())
        files["version.txt"] = "4.4.1.stable"
        result = self._fake_download(files)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_stale_or_empty_cached_templates_cannot_satisfy_a_bad_download(self):
        for name in ("android_debug.apk", "android_release.apk", "android_source.zip", "version.txt"):
            (self.templates / name).write_text("")
        result = self._fake_download({"version.txt": "4.4.1.stable"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.templates / "version.txt").read_text(), "")

    def test_build_rejects_wrong_patch_version_before_expensive_steps(self):
        scripts = self.project / "scripts"
        scripts.mkdir()
        for name in ("build_android.sh", "godot_env.sh", "godot_test_env.sh"):
            shutil.copyfile(ROOT / "scripts" / name, scripts / name)
        shutil.copyfile(ROOT / ".godot-version", self.project / ".godot-version")
        godot = self.root / "fake-godot"
        godot.write_text("#!/bin/sh\necho 4.4.2.stable.official\n")
        godot.chmod(0o755)
        self.env["GODOT_BIN"] = str(godot)
        result = subprocess.run(["bash", str(scripts / "build_android.sh")], env=self.env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match pinned", result.stderr)
        report = (self.project / "build/BUILD_REPORT.txt").read_text()
        self.assertIn("Result: FAILED", report)
        self.assertNotIn("SUCCESS", report)

    def test_invalid_version_cannot_leave_a_stale_success_report(self):
        scripts = self.project / "scripts"
        scripts.mkdir()
        for name in ("build_android.sh", "godot_env.sh", "godot_test_env.sh"):
            shutil.copyfile(ROOT / "scripts" / name, scripts / name)
        shutil.copyfile(ROOT / ".godot-version", self.project / ".godot-version")
        report = self.project / "build/BUILD_REPORT.txt"
        report.parent.mkdir()
        report.write_text("Result: SUCCESS\n")
        self.env["GODOT_VERSION"] = "bad-version"
        result = subprocess.run(["bash", str(scripts / "build_android.sh")], env=self.env,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Result: FAILED", report.read_text())



class AuditContractTests(unittest.TestCase):
    def test_ci_and_local_engine_pins_agree(self):
        workflow = (ROOT / ".github/workflows/android.yml").read_text()
        version = re.search(r'GODOT_VERSION: "([^"]+)"', workflow)[1]
        self.assertEqual(version, (ROOT / ".godot-version").read_text().strip())

    def test_release_requires_every_validation_job(self):
        publish = (ROOT / ".github/workflows/android.yml").read_text().split("  publish-release:", 1)[1]
        for job in ("validate-resources", "godot-tests", "build-android"):
            self.assertIn(f"needs.{job}.result == 'success'", publish)
        self.assertIn("needs: [validate-resources, godot-tests, build-android]", publish)

    def test_all_test_wrappers_check_engine_error_channel(self):
        for path in ("scripts/build_android.sh", "scripts/ui/run_ui_validation.sh", "tool/test_hero_runtime.sh"):
            text = (ROOT / path).read_text()
            self.assertIn("check_godot_log.py", text)
            self.assertIn("--exit-code", text)
            self.assertIn("--require", text)

    def test_scene_provenance_ignores_caches_and_gdignore(self):
        from tool.check_scene_paths import project_scene_paths
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for folder in ("scenes", ".cache/engine", "build/export", "assets/ignored"):
                directory = root / folder
                directory.mkdir(parents=True)
                (directory / "fixture.tscn").write_text('[gd_scene format=3]')
            (root / "assets/ignored/.gdignore").touch()
            self.assertEqual(project_scene_paths(root), [root / "scenes/fixture.tscn"])

    def test_unittest_methods_are_not_silently_overwritten(self):
        for path in (ROOT / "tests/python").glob("test_*.py"):
            for node in ast.walk(ast.parse(path.read_text())):
                if not isinstance(node, ast.ClassDef):
                    continue
                names = [method.name for method in node.body
                         if isinstance(method, ast.FunctionDef) and method.name.startswith("test_")]
                self.assertEqual(len(names), len(set(names)), f"Duplicate tests in {path.name}:{node.name}")


if __name__ == "__main__":
    unittest.main()
