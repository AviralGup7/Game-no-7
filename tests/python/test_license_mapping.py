"""Docs, licence-tree mapping, and export-preset identity — no Godot."""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA_SUFFIXES = {
    ".glb", ".gltf", ".bin", ".png", ".jpg", ".jpeg", ".hdr",
    ".ttf", ".otf", ".ogg", ".wav", ".webp", ".mp3",
}

# Project-authored trees (not in assets/manifest.json). Each prefix must appear
# in THIRD_PARTY_ASSETS.md so the mapping cannot silently drift from the doc.
FIRST_PARTY_PREFIXES = (
    "assets/characters/warden/",
    "assets/scifi/",
    "assets/environment/space_station/panel.png",
    "data/models/skills/",
    "data/models/ceiling",
    "data/models/ground",
    "data/models/wall",
    "data/audio/enemy_",
    "data/ui/",
    "data/models/environment_showcase.png",
)

# Third-party media that is not in the download lock.
EXTRA_THIRD_PARTY = {
    "data/models/warehouse/": "ASSET_LICENSES/nicholas3d-warehouse.txt",
}

GATES = (
    "validate_resources.py",
    "validate_assets.py",
    "validate_campaign.py",
    "validate_geometry.py",
    "validate_guards.py",
    "check_typed_arch.py",
    "check_engine_api.py",
    "check_scene_paths.py",
    "check_string_formats.py",
    "check_signals.py",
    "unittest discover",
)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def posix(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def media_files():
    for base in (ROOT / "assets", ROOT / "data"):
        for path in base.rglob("*"):
            if path.is_file() and path.suffix.lower() in MEDIA_SUFFIXES:
                yield posix(path)


def classify(rel: str, locked: set[str]) -> str:
    if rel in locked:
        return "manifest"
    for prefix, notice in EXTRA_THIRD_PARTY.items():
        if rel.startswith(prefix):
            return "extra:" + notice
    for prefix in FIRST_PARTY_PREFIXES:
        if rel.startswith(prefix):
            return "first-party"
    return "unmapped"


class LicenseMappingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads(read("assets/manifest.json"))
        cls.locked = {entry["path"] for entry in cls.manifest["files"]}
        cls.third_party = read("THIRD_PARTY_ASSETS.md")
        cls.licenses_readme = read("ASSET_LICENSES/README.md")

    def test_manifest_sources_have_existing_license_files(self):
        for pack, source in self.manifest["sources"].items():
            notice = source["license_file"]
            with self.subTest(pack=pack, notice=notice):
                self.assertTrue((ROOT / notice).is_file(), notice)
                self.assertIn(notice, self.locked | {notice})

    def test_manifest_license_files_are_locked_or_present(self):
        for pack, source in self.manifest["sources"].items():
            notice = source["license_file"]
            self.assertTrue((ROOT / notice).is_file(), f"{pack}: {notice}")

    def test_every_media_file_is_mapped(self):
        unmapped = []
        for rel in media_files():
            if classify(rel, self.locked) == "unmapped":
                unmapped.append(rel)
        self.assertEqual(unmapped, [], "unmapped third-party/media files:\n" + "\n".join(unmapped[:40]))

    def test_warehouse_is_extra_third_party_with_notice(self):
        notice = EXTRA_THIRD_PARTY["data/models/warehouse/"]
        self.assertTrue((ROOT / notice).is_file())
        self.assertTrue((ROOT / "data/models/warehouse/license.txt").is_file())
        self.assertIn("data/models/warehouse/", self.third_party)
        self.assertIn("nicholas3d-warehouse", self.third_party)
        self.assertIn("CC-BY-4.0", self.third_party)

    def test_kenney_space_station_kit_is_documented(self):
        self.assertIn("kenney-space-station", self.manifest["sources"])
        self.assertIn("Kenney Space Station", self.third_party)
        self.assertIn("assets/environment/space_station/", self.third_party)
        self.assertTrue((ROOT / "ASSET_LICENSES/kenney-space-station.txt").is_file())

    def test_first_party_prefixes_are_documented(self):
        for prefix in FIRST_PARTY_PREFIXES:
            with self.subTest(prefix=prefix):
                self.assertIn(prefix, self.third_party)

    def test_first_party_notices_exist(self):
        for rel in (
            "ASSET_LICENSES/arena-warden.md",
            "ASSET_LICENSES/station-shooter.txt",
            "ASSET_LICENSES/skill-foci.md",
            "ASSET_LICENSES/station-environment.md",
            "ASSET_LICENSES/ui-chrome.md",
        ):
            self.assertTrue((ROOT / rel).is_file(), rel)
            self.assertIn(rel, self.third_party + self.licenses_readme)

    def test_licenses_readme_lists_later_notices(self):
        for needle in (
            "kenney-space-station",
            "nicholas3d-warehouse",
            "arena-warden",
            "skill-foci",
            "station-shooter",
            "station-environment",
            "ui-chrome",
        ):
            self.assertIn(needle, self.licenses_readme)


class DocsIndexTests(unittest.TestCase):
    def test_docs_readme_indexes_every_docs_file(self):
        index = read("docs/README.md")
        missing = []
        for path in sorted((ROOT / "docs").rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(ROOT / "docs").as_posix()
            if rel == "README.md":
                continue
            if rel not in index:
                missing.append("docs/" + rel)
        self.assertEqual(missing, [], "docs/README.md is missing:\n" + "\n".join(missing))

    def test_agents_doc_lists_the_eleven_gates(self):
        text = read("docs/AGENTS.md")
        for gate in GATES:
            self.assertIn(gate, text, gate)
        self.assertIn("NOT TESTED", text)
        self.assertIn("9 autoloads", text)
        self.assertIn("183", text)
        self.assertIn("201", text)

    def test_readme_has_known_limitations(self):
        text = read("README.md")
        self.assertIn("## Known limitations", text)
        self.assertIn("NOT RUNTIME VERIFIED", text)
        self.assertIn("docs/AGENTS.md", text)
        self.assertIn("docs/README.md", text)

    def test_release_notes_template_has_campaign_stats_and_limitations(self):
        text = read("docs/RELEASE_NOTES_TEMPLATE.md")
        self.assertIn("864 × 672", text)
        self.assertIn("Known limitations", text)
        self.assertIn("apk_size_report.py", text)
        self.assertIn("NOT RUNTIME VERIFIED", text)


class OperationalClaimTests(unittest.TestCase):
    def test_architecture_says_nine_autoloads(self):
        text = read("docs/ARCHITECTURE.md")
        self.assertIn("the 9 autoloads", text)
        self.assertNotIn("the 8 autoloads", text)

    def test_hardening_python_count_matches_this_suite(self):
        loader = unittest.defaultTestLoader
        suite = loader.discover(str(ROOT / "tests" / "python"), pattern="test_*.py")
        n = suite.countTestCases()
        text = read("docs/HARDENING.md")
        self.assertIn("Tests: %d python" % n, text)
        campaign = read("docs/campaign/README.md")
        self.assertIn("{:,} Python tests passed".format(n), campaign)

    def test_device_qa_uses_twelve_districts_and_thirteen_missions(self):
        text = read("docs/DEVICE_QA.md")
        self.assertNotIn("six districts", text)
        self.assertNotIn("seven objectives", text)
        self.assertIn("twelve districts", text)
        self.assertIn("thirteen missions", text)

    def test_campaign_readme_does_not_claim_two_export_presets(self):
        text = read("docs/campaign/README.md")
        self.assertNotIn("Both export presets", text)
        self.assertIn("Android export preset", text)

    def test_build_md_documents_apk_size_report(self):
        text = read("docs/BUILD.md")
        self.assertIn("apk_size_report.py", text)
        self.assertIn("build/apk-size-report.json", text)
        self.assertNotIn("Both Android export presets", text)


class ExportPresetTests(unittest.TestCase):
    def test_preset_matches_example(self):
        self.assertEqual(read("export_presets.cfg"), read("export_presets.cfg.example"))

    def test_preset_version_matches_project(self):
        project = read("project.godot")
        preset = read("export_presets.cfg")
        version = re.search(r'^config/version="([^"]+)"', project, re.M).group(1)
        name = re.search(r'^config/name="([^"]+)"', project, re.M).group(1)
        self.assertEqual(name, "Last Stand: Station Zero")
        self.assertIn('version/name="%s"' % version, preset)
        self.assertIn("version/code=4", preset)
        self.assertIn('package/unique_name="com.laststandarena.game"', preset)
        self.assertIn('package/name="Station Zero"', preset)
        self.assertIn("data/campaign/*.json", preset)
        self.assertIn("docs/ANDROID_PERMISSIONS.md", preset)
        self.assertIn("ASSET_LICENSES/*.txt", preset)

    def test_single_android_preset(self):
        preset = read("export_presets.cfg")
        headers = re.findall(r"^\[preset\.\d+\]$", preset, re.M)
        self.assertEqual(headers, ["[preset.0]"])
        self.assertIn('name="Android"', preset)
        self.assertIn('gradle_build/min_sdk="24"', preset)
        self.assertIn('gradle_build/target_sdk="34"', preset)
        self.assertIn("architectures/arm64-v8a=true", preset)


if __name__ == "__main__":
    unittest.main()
