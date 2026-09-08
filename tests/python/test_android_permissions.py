import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class AndroidPermissionPolicyTests(unittest.TestCase):
    """Guard the no-permission Android policy (see docs/ANDROID_PERMISSIONS.md).

    The game is fully offline and needs no Android runtime permissions. These checks
    fail loudly if someone later enables a preset permission toggle, commits a custom
    manifest, or forgets to bundle the policy doc in the export.
    """

    def test_export_preset_requests_no_permissions(self):
        cfg = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        offending = [ln for ln in cfg.splitlines() if ln.startswith("permissions/")]
        self.assertEqual(
            offending, [], "Android export preset requests a permission: %r" % (offending,)
        )

    def test_no_custom_android_manifest_committed(self):
        # The gradle build template (android/build/) is generated at build time by
        # scripts/install_android_build_template.sh and is never committed.
        for rel in ("android/build/AndroidManifest.xml", "android/AndroidManifest.xml"):
            self.assertFalse(
                (ROOT / rel).exists(),
                "A custom AndroidManifest.xml was committed at %s (would change the permission set)." % rel,
            )

    def test_policy_doc_is_bundled_in_export(self):
        for preset in ("export_presets.cfg", "export_presets.cfg.example"):
            cfg = (ROOT / preset).read_text(encoding="utf-8")
            self.assertIn(
                "docs/ANDROID_PERMISSIONS.md",
                cfg,
                "%s include_filter should bundle the permissions policy doc." % preset,
            )
        self.assertTrue((ROOT / "docs/ANDROID_PERMISSIONS.md").exists())

    def test_offline_no_networking_in_game_scripts(self):
        # The game must stay offline: no outbound sockets or HTTP clients in gameplay.
        forbidden = (
            "HTTPRequest",
            "HTTPClient",
            "StreamPeerTCP",
            "TCPServer",
            "UDPServer",
            "WebSocketPeer",
            "PacketPeerUDP",
            "OS.execute(",
        )
        hits = []
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            text = path.read_text(encoding="utf-8", errors="ignore")
            for token in forbidden:
                if token in text:
                    hits.append("%s: %s" % (path.relative_to(ROOT), token))
        self.assertEqual(
            hits,
            [],
            "Game scripts use an outbound-network API; this would need INTERNET permission "
            "and contradict the offline policy:\n%s" % "\n".join(hits[:10]),
        )


if __name__ == "__main__":
    unittest.main()
