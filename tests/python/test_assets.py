"""Offline tests: python3 -m unittest discover -s tests/python -v."""
from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import copy
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error
import urllib.parse
import urllib.request
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts import download_assets as downloader  # noqa: E402
from tool import validate_assets as validator  # noqa: E402


def entry_for(path="assets/test.png", payload=b"approved asset"):
    source_path = path.split("/", 1)[1]
    return {
        "pack": "test", "path": path, "source_path": source_path,
        "url": f"https://api.github.com/repos/creator/pack/contents/{source_path}?ref={'a' * 40}",
        "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest(),
        "git_blob_sha1": hashlib.sha1(f"blob {len(payload)}\0".encode() + payload).hexdigest(),
        "purpose": "Unit test fixture", "downloaded_on": "2026-09-07",
    }


class AssetTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.entry = entry_for()
        self.payload = b"approved asset"

    def fetch(self, entry=None, **kwargs):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return downloader.fetch(entry or self.entry, root=self.root, **kwargs)

    def write_existing(self, payload):
        path = self.root / self.entry["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        return path


class DownloadTests(AssetTestCase):
    def test_missing_file_is_downloaded_and_verified(self):
        with patch.object(downloader, "open_download", return_value=io.BytesIO(self.payload)) as network:
            self.assertTrue(self.fetch())
        request = network.call_args.args[0]
        self.assertEqual(request.full_url, self.entry["url"])
        self.assertEqual(request.get_header("Accept"), "application/vnd.github.raw+json")
        self.assertEqual((self.root / self.entry["path"]).read_bytes(), self.payload)
        self.assertEqual(list(self.root.rglob("*.tmp")), [])

    def test_missing_offline_verify_is_read_only(self):
        before = list(self.root.rglob("*"))
        with patch.object(downloader, "open_download") as network:
            self.assertFalse(self.fetch(verify_only=True))
            network.assert_not_called()
        self.assertEqual(list(self.root.rglob("*")), before)

    def test_existing_good_file_does_not_use_network(self):
        dest = self.write_existing(self.payload)
        before = dest.stat().st_mtime_ns
        with patch.object(downloader, "open_download") as network:
            self.assertTrue(self.fetch())
            self.assertTrue(self.fetch(verify_only=True))
            network.assert_not_called()
        self.assertEqual(dest.stat().st_mtime_ns, before)

    def test_same_length_corruption_is_detected(self):
        dest = self.write_existing(b"x" * len(self.payload))
        with patch.object(downloader, "open_download") as network:
            self.assertFalse(self.fetch())
            self.assertFalse(self.fetch(verify_only=True))
            network.assert_not_called()
        self.assertEqual(dest.read_bytes(), b"x" * len(self.payload))

    def test_repair_requires_and_accepts_approved_bytes(self):
        dest = self.write_existing(b"broken")
        with patch.object(downloader, "open_download", return_value=io.BytesIO(self.payload)):
            self.assertTrue(self.fetch(repair=True))
        self.assertEqual(dest.read_bytes(), self.payload)

    def test_failed_repair_preserves_old_file(self):
        dest = self.write_existing(b"broken")
        with patch.object(downloader, "open_download", return_value=io.BytesIO(b"x" * len(self.payload))):
            self.assertFalse(self.fetch(repair=True))
        self.assertEqual(dest.read_bytes(), b"broken")
        self.assertEqual(list(self.root.rglob("*.tmp")), [])

    def test_truncated_response_never_becomes_a_final_file(self):
        with patch.object(downloader, "open_download", return_value=io.BytesIO(self.payload[:-1])):
            self.assertFalse(self.fetch())
        self.assertFalse((self.root / self.entry["path"]).exists())
        self.assertEqual(list(self.root.rglob("*.tmp")), [])

    def test_oversized_response_is_rejected(self):
        with patch.object(downloader, "open_download", return_value=io.BytesIO(self.payload + b"extra")):
            self.assertFalse(self.fetch())
        self.assertFalse((self.root / self.entry["path"]).exists())
        self.assertEqual(list(self.root.rglob("*.tmp")), [])

    def test_network_failure_leaves_no_partial_file(self):
        with patch.object(downloader, "open_download", side_effect=urllib.error.URLError("offline")):
            self.assertFalse(self.fetch())
        self.assertFalse((self.root / self.entry["path"]).exists())
        self.assertEqual(list(self.root.rglob("*.tmp")), [])

    def test_destination_traversal_and_scripts_are_rejected(self):
        for path in ("../escape.png", "/tmp/escape.png", "assets/../../escape.png",
                     "assets\\escape.png", "assets/./x.png", "assets//x.png",
                     "scripts/code.gd", "assets/plugin.gd", "ASSET_LICENSES/../x.txt"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                downloader.destination_for(path, self.root)

    def test_symlink_destination_is_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.root / "assets").symlink_to(outside, target_is_directory=True)
        with patch.object(downloader, "open_download") as network:
            self.assertFalse(self.fetch())
            network.assert_not_called()
        self.assertEqual(list(outside.iterdir()), [])

    def test_unapproved_redirects_are_rejected(self):
        handler = downloader.ApprovedRedirects()
        req = urllib.request.Request(self.entry["url"])
        for url in ("http://api.github.com/no-tls", "https://example.org/asset",
                    "file:///etc/passwd", "https://api.github.com:444/file",
                    "https://user:password@api.github.com/file"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                handler.redirect_request(req, None, 302, "Found", {}, url)


class ManifestTests(AssetTestCase):
    def setUp(self):
        super().setUp()
        self.manifest = {
            "schema_version": 1,
            "sources": {"test": {
                "name": "Test Pack", "creator": "Creator", "source_url": "https://example.org/pack",
                "download_repository": "https://github.com/creator/pack", "revision": "a" * 40,
                "license": "CC0-1.0", "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                "attribution": "None", "reviewed_on": "2026-09-07", "commercial_use": True,
                "compiled_redistribution": True, "modification_permitted": True,
                "license_file": "ASSET_LICENSES/test.txt",
            }},
            "files": [self.entry, entry_for("ASSET_LICENSES/test.txt", b"CC0")],
        }

    def load(self):
        path = self.root / "manifest.json"
        path.write_text(json.dumps(self.manifest))
        return downloader.load_manifest(path, self.root)

    def test_reviewed_manifest_loads_without_downloading(self):
        self.assertEqual(len(self.load()["files"]), 2)

    def test_empty_manifest_fails(self):
        self.manifest["files"] = []
        with self.assertRaises(ValueError):
            self.load()

    def test_missing_checksum_fails(self):
        del self.entry["sha256"]
        with self.assertRaises(ValueError):
            self.load()

    def test_floating_revision_fails(self):
        self.manifest["sources"]["test"]["revision"] = "main"
        with self.assertRaises(ValueError):
            self.load()

    def test_duplicate_destination_fails(self):
        self.manifest["files"].append(copy.deepcopy(self.entry))
        with self.assertRaises(ValueError):
            self.load()

    def test_missing_license_record_fails(self):
        self.manifest["files"].pop()
        with self.assertRaises(ValueError):
            self.load()

    def test_unapproved_license_fails(self):
        self.manifest["sources"]["test"]["license"] = "unknown"
        with self.assertRaises(ValueError):
            self.load()

    def test_missing_commercial_permission_fails(self):
        self.manifest["sources"]["test"]["commercial_use"] = False
        with self.assertRaises(ValueError):
            self.load()

    def test_url_must_match_reviewed_source(self):
        self.entry["url"] = "https://example.org/unapproved.png"
        with self.assertRaises(ValueError):
            self.load()

    def test_oversized_lock_entry_fails(self):
        self.entry["bytes"] = downloader.MAX_FILE_BYTES + 1
        with self.assertRaises(ValueError):
            self.load()

    def test_mit_notice_is_reviewed_and_required(self):
        self.manifest["sources"]["test"]["license"] = "MIT"
        self.assertEqual(self.load()["sources"]["test"]["license"], "MIT")
        self.manifest["files"].pop()
        with self.assertRaises(ValueError):
            self.load()

    def test_shared_notice_requires_explicit_matching_pack(self):
        extra = copy.deepcopy(self.manifest["sources"]["test"])
        extra["license_pack"] = "test"
        self.manifest["sources"]["mirror"] = extra
        self.assertIn("mirror", self.load()["sources"])
        extra["license"] = "MIT"
        with self.assertRaises(ValueError):
            self.load()

    def test_unknown_shared_notice_pack_rejected(self):
        self.manifest["sources"]["test"]["license_pack"] = "unknown"
        with self.assertRaises(ValueError):
            self.load()


class FormatTests(AssetTestCase):
    def test_truncated_glb_is_rejected(self):
        path = self.root / "model.glb"
        path.write_bytes(b"glTF")
        with self.assertRaises(ValueError):
            validator.gltf_document(path)

    def test_unapproved_external_dependency_is_rejected(self):
        path = self.root / "model.gltf"
        path.write_text(json.dumps({"asset": {"version": "2.0"}, "meshes": [{}], "scenes": [{}],
                                    "buffers": [{"uri": "https://example.org/missing.bin", "byteLength": 1}]}))
        with self.assertRaisesRegex(ValueError, "remote/unapproved"):
            validator.check_model(path, set())

    def test_png_crc_is_checked(self):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        path = self.root / "tiny.png"
        data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff")) + chunk(b"IEND", b""))
        path.write_bytes(data)
        validator.check_png(path)
        path.write_bytes(data[:-1] + bytes([data[-1] ^ 1]))
        with self.assertRaisesRegex(ValueError, "CRC"):
            validator.check_png(path)

    def test_shipped_files_have_valid_checksums(self):
        manifest = downloader.load_manifest()
        for entry in manifest["files"]:
            with self.subTest(path=entry["path"]):
                self.assertEqual(downloader.verification_problem(entry), "")

    def test_shipped_catalog_and_formats_pass(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(validator.main(), 0)

    def test_music_loops_are_real_vorbis_not_preview_html(self):
        for name in ("arena_menu", "arena_gameplay", "arena_calm", "arena_boss", "arena_victory"):
            info = validator.ogg_info(ROOT / f"assets/audio/music/{name}.ogg")
            self.assertGreater(info["duration_seconds"], 10)
            self.assertEqual(info["channels"], 2)


class CoverageTests(AssetTestCase):
    def test_fresh_godot_import_keeps_embedded_textures_in_cache(self):
        settings = (ROOT / "project.godot").read_text()
        self.assertIn('[importer_defaults]', settings)
        self.assertIn('"gltf/embedded_image_handling": 2', settings)

    def test_untracked_download_is_detected(self):
        self.write_existing(self.payload)
        with patch.object(validator, "ROOT", self.root), self.assertRaisesRegex(ValueError, "untracked"):
            validator.check_asset_inventory(set())

    def test_missing_runtime_reference_is_detected(self):
        path = self.root / "scenes/test.tscn"
        path.parent.mkdir()
        path.write_text('[ext_resource path="res://assets/missing.glb"]')
        with patch.object(validator, "ROOT", self.root), self.assertRaisesRegex(ValueError, "missing runtime"):
            validator.check_asset_inventory(set())

    def test_content_ids_come_from_resources_not_filenames(self):
        path = self.root / "data/enemies/anything.tres"
        path.parent.mkdir(parents=True)
        path.write_text('archetype_id = &"ranged"')
        with patch.object(validator, "ROOT", self.root):
            self.assertEqual(validator.content_ids("enemies", "archetype_id"), {"ranged"})

    def test_catalog_covers_expanded_game(self):
        catalog = json.loads((ROOT / "assets/catalog.json").read_text())
        self.assertEqual(set(catalog["characters"]), validator.content_ids("enemies", "archetype_id") | {"player"})
        for category, field in (("weapons", "weapon_id"), ("skills", "skill_id"),
                                ("pickups", "pickup_id"), ("arenas", "arena_id")):
            self.assertEqual(set(catalog["gameplay_" + category]), validator.content_ids(category, field))

    def test_pickup_runtime_uses_catalog_models(self):
        catalog = json.loads((ROOT / "assets/catalog.json").read_text())
        for name, entry in catalog["gameplay_pickups"].items():
            data = (ROOT / "data/pickups" / (name + ".tres")).read_text()
            self.assertIn('path="res://' + entry["model"] + '"', data)
            self.assertIn('visual_scene = ExtResource("2_visual")', data)


if __name__ == "__main__":
    unittest.main()
