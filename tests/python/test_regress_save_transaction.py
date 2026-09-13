"""Pin transactional campaign persistence and save durability ordering."""
from __future__ import annotations

import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def extract_func(src: str, name: str) -> str:
    needle = f"func {name}"
    start = src.index(needle)
    nxt = src.find("\nfunc ", start + 1)
    return src[start:] if nxt < 0 else src[start:nxt]


class SaveDurabilityOrderingTests(unittest.TestCase):
    def test_rotation_runs_after_temp_verify_and_before_rename(self):
        flush = extract_func(read("scripts/save/save_manager.gd"), "_flush_save")
        self.assertLess(flush.index("_stage_temp("), flush.index("_rotate_backups_from_primary()"))
        self.assertLess(flush.index("_rotate_backups_from_primary()"), flush.index("_commit_rename("))
        self.assertNotIn("_rotate_backups_from_primary()", extract_func(read("scripts/save/save_manager.gd"), "_stage_temp"))

    def test_temp_discarded_on_every_failure_path(self):
        src = read("scripts/save/save_manager.gd")
        stage = extract_func(src, "_stage_temp")
        commit = extract_func(src, "_commit_rename")
        self.assertIn("_discard_temp(tmp)", stage)
        self.assertGreaterEqual(stage.count("_discard_temp(tmp)"), 2)
        self.assertIn("_discard_temp(tmp)", commit)
        self.assertIn("never reads", src)
        self.assertNotIn("SAVE_PATH + \".tmp\"", extract_func(src, "_load_from_disk"))


class CampaignTransactionTests(unittest.TestCase):
    def test_director_commits_one_normalized_slice(self):
        director = read("scripts/campaign/campaign_director.gd")
        save = extract_func(director, "save_progress")
        self.assertIn("commit_profile_transaction", save)
        self.assertIn("capture_profile_slice", save)
        self.assertIn("slice.meta_wallet = _meta.get_wallet()", save)
        self.assertNotIn("store_campaign", save)
        complete = extract_func(director, "_complete_mission")
        self.assertIn("_staging_persist = true", complete)
        self.assertLess(complete.index("progress.mission ="), complete.index("_commit_reward"))
        reward = extract_func(director, "_commit_reward")
        self.assertIn("grant_currency(credits, false)", reward)
        self.assertNotIn("grant_currency(credits, true)", director)
        self.assertIn("_restore_runtime(snapshot)", director)
        self.assertIn("_retry_pending_transaction", director)
        root = read("scripts/core/game_root.gd")
        start = extract_func(root, "start_campaign")
        self.assertIn("retry_pending_profile_transaction", start)

    def test_checkpoint_still_stages_then_rolls_back_on_failed_write(self):
        visit = extract_func(read("scripts/campaign/campaign_director.gd"), "_visit_checkpoint")
        self.assertLess(visit.index("previous_checkpoint"), visit.index("progress.checkpoint = near"))
        self.assertLess(visit.index("if save_progress(true):"), visit.index("_checkpoint_inside = near"))
        self.assertIn("progress.checkpoint = previous_checkpoint", visit)
        self.assertIn("_checkpoint_inside = \"\"", visit)
        self.assertIn("retry here", visit)

    def test_wallet_grant_during_campaign_is_unstaged_until_commit(self):
        meta = read("scripts/meta/meta_progression.gd")
        self.assertIn("func restore_wallet(balance: int, persist: bool = false)", meta)
        director = read("scripts/campaign/campaign_director.gd")
        self.assertIn("restore_wallet", director)

    def test_schema_v8_fixture_round_trips_additively(self):
        schema = read("scripts/save/save_schema.gd")
        self.assertIn("const SCHEMA_VERSION := 8", schema)
        fixture = json.loads((ROOT / "tests/python/fixtures/save_v8_min.json").read_text())
        self.assertEqual(fixture["schema_version"], 8)
        defaults = extract_func(schema, "default_save")
        for key in fixture:
            self.assertIn(f'"{key}"', defaults)
        progress = read("scripts/campaign/campaign_progress.gd")
        campaign = fixture["campaign"]
        for key in campaign:
            self.assertIn(f'"{key}"', progress)
        # No extra required on-disk transaction envelope (pending stays in memory).
        self.assertNotIn('"pending_profile"', defaults)
        self.assertNotIn('"pending_transaction"', defaults)
        normalize = extract_func(schema, "normalize_save")
        self.assertIn("CampaignProgress.normalize(data.get(\"campaign\", {}))", normalize)
        self.assertIn("out.schema_version = SCHEMA_VERSION", normalize)


if __name__ == "__main__":
    unittest.main()
