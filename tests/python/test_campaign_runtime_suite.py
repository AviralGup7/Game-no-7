"""Campaign runtime suite (audit work item #7) + sibling-agent behavior pins.

The GDScript harness in tests/campaign_runtime/ is CI-only (no Godot binary in
this workspace). These tests pin everything that IS observable offline:

1. Registration and entry commands: the harness/stage/entry/wrapper files,
   their load-order contract, the CI steps, and the log contract (exit code +
   summary line) that makes the suite fail-closed.

2. Behavior pins for the sibling agents' changes (marked "requires Agent NN").
   The sibling work has landed on this branch (typed campaign records,
   retryable save transaction, CampaignBudgets single source), so these pins
   now lock the LANDING implementations against drift; they were written as
   the behavioral spec those implementations had to satisfy:

   - requires Agent #2 — typed campaign records (audit work item #2): the
     reconcile() cursor/erase/completion semantics mirrored in Python.
   - requires Agent #5 — retryable save transaction (audit work item #5): the
     _visit_checkpoint rollback order, the stage/commit/rotation order, and
     the director's first-tick pending retry.
   - requires Agent #6 — single-sourced budgets (audit weakness #6): the
     authored JSON stays inside the CampaignBudgets single source that every
     runtime copy aliases (detailed aliasing pins live in
     tests/python/test_campaign_budgets.py).
"""

import os
import re
import unittest
from pathlib import Path

from tool import validate_campaign as campaign

ROOT = Path(__file__).resolve().parents[2]
INNER = "tests/campaign_runtime/campaign_runtime_inner.gd"
STAGE = "tests/campaign_runtime_stages.gd"
ENTRY = "tests/run_campaign_runtime.gd"
RUNNER = "tests/run_tests.gd"
WRAPPER = "scripts/run_campaign_runtime.sh"


def source(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


class CampaignRuntimeSuiteRegistration(unittest.TestCase):
    """The audit work item #7 suite must be wired, entry-pointed, and CI-run."""

    def test_entry_point_files_exist(self):
        for rel in (INNER, STAGE, ENTRY, RUNNER, WRAPPER):
            self.assertTrue((ROOT / rel).is_file(), f"missing {rel}")

    def test_wrapper_is_executable(self):
        self.assertTrue(os.access(ROOT / WRAPPER, os.X_OK),
                        "scripts/run_campaign_runtime.sh must be executable")

    def test_harness_is_a_pure_node_that_never_quits(self):
        inner = source(INNER)
        self.assertIn("extends Node", inner)
        # The embedding SceneTree (run_tests.gd / run_campaign_runtime.gd) owns
        # process exit and env guarding; the harness stays runnable embedded.
        self.assertNotIn("quit(", inner)
        self.assertNotIn("STATION_ZERO_TEST_PROFILE", inner)
        # Load-order contract: the harness is runtime-loaded, so game classes
        # are referenced by global class_name only — never preloaded.
        self.assertNotIn("preload(", inner)
        # One fixed-delta cycle budget, single-sourced (audit weakness #6).
        self.assertIn("const CYCLE_COUNT := 20", inner)
        self.assertIn("range(CYCLE_COUNT)", inner)
        # The log contract the wrapper's --require regex matches.
        self.assertIn('"CAMPAIGN RUNTIME: %d checks, %d failed"', inner)

    def test_harness_covers_all_five_audit_scenarios(self):
        inner = source(INNER)
        scenarios = {
            "a imported meshes counted": [
                "every environment module ships an imported mesh",
                "zero geometry fallback diagnostics",
            ],
            "b all 13 missions + negative gate": [
                "guarded console refuses early interaction",
                "mission advances once",
                "story objectives plus the extraction are all complete",
                "extraction reaches campaign victory",
            ],
            "c save-write failure": [
                "failed checkpoint save does not advance the checkpoint",
                "failed save leaves the on-disk save byte-identical",
                "failed commit leaves a retryable pending transaction",
                "pending transaction retries on the first tick",
                "checkpoint advances on the immediate retry",
                "failed save corrupted no mission progress",
            ],
            "d 20 pause/map/back/checkpoint cycles": [
                "pause reaches PAUSED",
                "map opens while paused",
                "second back resumes the run",
                "no node leak",
                "transition lock is clear",
            ],
            "e defeat persistence across retry": [
                "defeated set survives checkpoint retry",
                "cleared actor cannot respawn",
                "retry does not re-grant XP",
            ],
        }
        for label, markers in scenarios.items():
            for marker in markers:
                self.assertIn(marker, inner, f"scenario {label} not observable: {marker}")

    def test_harness_has_a_global_error_diagnostic_case(self):
        self.assertIn("no campaign error diagnostics", source(INNER))

    def test_standalone_entry_keeps_the_load_order_contract(self):
        entry = source(ENTRY)
        self.assertIn("extends SceneTree", entry)
        self.assertIn('load("res://tests/campaign_runtime/campaign_runtime_inner.gd")', entry)
        # Env guard: a bare invocation must not write a fresh campaign into a
        # real player save (same contract as tests/verify_campaign.gd).
        self.assertIn('OS.get_environment("STATION_ZERO_TEST_PROFILE") != "1"', entry)
        self.assertIn("quit(0 if failed == 0 else 1)", entry)
        # No game-class references/preloads in the --script main loop file.
        self.assertNotIn("preload(", entry)

    def test_stage_shim_loads_the_harness_at_runtime(self):
        stage = source(STAGE)
        self.assertIn('const HARNESS_PATH := "res://tests/campaign_runtime/campaign_runtime_inner.gd"', stage)
        self.assertNotIn("preload(", stage)

    def test_runner_registers_the_stage_in_the_deferred_phase(self):
        runner = source(RUNNER)
        self.assertIn('const CAMPAIGN_RUNTIME_STAGE := "res://tests/campaign_runtime_stages.gd"', runner)
        self.assertIn("_start_campaign_runtime()", runner)
        self.assertIn("_fold_campaign_runtime()", runner)
        # Load-order contract for the runner file itself.
        self.assertNotIn("preload(", runner)

    def test_wrapper_contracts(self):
        text = source(WRAPPER)
        for token in (
            "godot_test_profile",
            "export STATION_ZERO_TEST_PROFILE=1",
            "tool/check_godot_log.py",
            "--script res://tests/run_campaign_runtime.gd",
            "--headless",
        ):
            self.assertIn(token, text, f"wrapper missing {token}")
        # Strict log gate: exit code + the success summary line, and only that
        # line (a run with failures or zero cases must not pass).
        match = re.search(r"--require '([^']+)'", text)
        self.assertIsNotNone(match, "wrapper must gate the summary line with --require")
        pattern = match.group(1)
        self.assertIsNotNone(re.match(pattern, "CAMPAIGN RUNTIME: 47 checks, 0 failed"))
        self.assertIsNone(re.match(pattern, "CAMPAIGN RUNTIME: 47 checks, 1 failed"))
        self.assertIsNone(re.match(pattern, "CAMPAIGN RUNTIME: 0 checks, 0 failed"))

    def test_ci_runs_the_new_headless_step(self):
        workflow = (ROOT / ".github/workflows/android.yml").read_text(encoding="utf-8")
        self.assertIn("run_campaign_runtime.sh", workflow,
                      "godot-tests job must run the headless campaign runtime step")

    def test_472_diagnostics_job_runs_the_embedded_suite(self):
        workflow = (ROOT / ".github/workflows/gdscript-diagnostics.yml").read_text(encoding="utf-8")
        self.assertIn("res://tests/run_tests.gd", workflow,
                      "the 4.7.2 job parses the same entry point, so the embedded "
                      "campaign runtime stage runs there unchanged")

    def test_docs_document_both_entry_commands(self):
        docs = (ROOT / "docs/BUILD.md").read_text(encoding="utf-8")
        self.assertIn("run_campaign_runtime.sh", docs)
        self.assertIn("res://tests/run_campaign_runtime.gd", docs)


class CampaignRecordBehaviorSpec(unittest.TestCase):
    """requires Agent #2 — typed campaign records (audit work item #2).

    The mirror below is the behavioral spec of
    scripts/campaign/campaign_progress.gd::reconcile(): a typed-record
    migration must keep passing it. The mirror assumes already-normalized
    input (normalize() is pinned separately); it reproduces the cursor walk,
    the stale-target erase rules, and the completion flag exactly.
    """

    @classmethod
    def setUpClass(cls):
        cls.authored = campaign.load()

    @staticmethod
    def _members_for(encounter_id, authored):
        group = next(g for g in authored["encounters"] if g["id"] == encounter_id)
        return [m["id"] for m in group["members"]]

    def _reconcile(self, value):
        data = self.authored
        members = {m for g in data["encounters"] for m in self._members_for(g["id"], data)}
        interactions = {i["id"] for i in data["interactions"]}
        sectors = {s["id"] for s in data["sectors"]}
        result = {
            "checkpoint": value.get("checkpoint", "docks"),
            "defeated": [i for i in value.get("defeated", []) if i in members],
            "interacted": [i for i in value.get("interacted", []) if i in interactions],
        }
        if result["checkpoint"] not in sectors:
            result["checkpoint"] = "docks"
        cursor = 0
        for mission in data["missions"]:
            cleared = True
            for encounter_id in mission.get("requires", []):
                for member in self._members_for(encounter_id, data):
                    cleared = cleared and member in result["defeated"]
            done = cleared
            for target in mission.get("targets", []):
                done = done and target in result["interacted"]
            if not done:
                if not cleared:
                    for target in mission.get("targets", []):
                        if target in result["interacted"]:
                            result["interacted"].remove(target)
                break
            cursor += 1
        for index in range(cursor + 1, len(data["missions"])):
            for target in data["missions"][index].get("targets", []):
                if target in result["interacted"]:
                    result["interacted"].remove(target)
        result["mission"] = cursor
        result["completed"] = cursor == len(data["missions"])
        return result

    def test_default_progress_reconciles_to_a_fresh_campaign(self):
        out = self._reconcile({"checkpoint": "docks", "defeated": [], "interacted": []})
        self.assertEqual(out["mission"], 0)
        self.assertFalse(out["completed"])
        self.assertEqual(out["checkpoint"], "docks")

    def test_fully_cleared_ledger_reconciles_to_completion(self):
        data = self.authored
        value = {
            "checkpoint": data["missions"][-1]["sector"],
            "defeated": [m for g in data["encounters"] for m in self._members_for(g["id"], data)],
            "interacted": [t for mission in data["missions"] for t in mission.get("targets", [])],
        }
        out = self._reconcile(value)
        self.assertEqual(out["mission"], len(data["missions"]))
        self.assertTrue(out["completed"])

    def test_partial_ledger_stops_at_the_first_incomplete_mission(self):
        data = self.authored
        stop = 3
        defeated, interacted = set(), []
        for mission in data["missions"][:stop]:
            for encounter_id in mission.get("requires", []):
                defeated.update(self._members_for(encounter_id, data))
            interacted.extend(mission.get("targets", []))
        out = self._reconcile({
            "checkpoint": data["missions"][stop - 1]["sector"],
            "defeated": sorted(defeated),
            "interacted": interacted,
        })
        self.assertEqual(out["mission"], stop)
        self.assertFalse(out["completed"])

    def test_unmet_requirement_earlier_erases_its_interacted_targets(self):
        data = self.authored
        guard = next(i for i, m in enumerate(data["missions"]) if m.get("requires"))
        defeated, interacted = set(), []
        for mission in data["missions"][:guard]:
            for encounter_id in mission.get("requires", []):
                defeated.update(self._members_for(encounter_id, data))
            interacted.extend(mission.get("targets", []))
        interacted.extend(data["missions"][guard].get("targets", []))
        out = self._reconcile({
            "checkpoint": "docks",
            "defeated": sorted(defeated),
            "interacted": interacted,
        })
        self.assertEqual(out["mission"], guard)
        for target in data["missions"][guard].get("targets", []):
            self.assertNotIn(target, out["interacted"],
                             "targets of an unmet mission must not stay marked")

    def test_stale_future_targets_are_erased(self):
        data = self.authored
        defeated, interacted = set(), []
        for mission in data["missions"][:1]:
            for encounter_id in mission.get("requires", []):
                defeated.update(self._members_for(encounter_id, data))
            interacted.extend(mission.get("targets", []))
        interacted.extend(data["missions"][5].get("targets", []))
        out = self._reconcile({
            "checkpoint": "docks",
            "defeated": sorted(defeated),
            "interacted": interacted,
        })
        self.assertEqual(out["mission"], 1)
        for target in data["missions"][5].get("targets", []):
            self.assertNotIn(target, out["interacted"],
                             "future targets ahead of the cursor must not stay marked")

    def test_unknown_ids_and_bad_checkpoint_are_reset(self):
        valid_member = self._members_for(self.authored["encounters"][0]["id"], self.authored)[0]
        out = self._reconcile({
            "checkpoint": "nowhere",
            "defeated": ["ghost_enemy", valid_member],
            "interacted": ["ghost_terminal"],
        })
        self.assertEqual(out["checkpoint"], "docks")
        self.assertNotIn("ghost_enemy", out["defeated"])
        self.assertIn(valid_member, out["defeated"])
        self.assertNotIn("ghost_terminal", out["interacted"])

    def test_progress_defaults_contract_fields(self):
        # Field-name contract a typed-record migration must preserve (the
        # disk format and every consumer key off these names).
        src = source("scripts/campaign/campaign_progress.gd")
        body = src.split("func defaults()", 1)[1].split("func ", 1)[0]
        for field in ("version", "world_id", "started", "checkpoint", "mission", "completed",
                      "defeated", "interacted", "visited", "upgrades", "weapons",
                      "active_weapon", "skills", "xp"):
            self.assertIn(f'"{field}"', body, f"defaults() dropped {field}")


class CampaignTransactionStagingSpec(unittest.TestCase):
    """requires Agent #5 — retryable save transaction (audit work item #5).

    Source-order pins of the landed transaction: a failed checkpoint commit
    rolls back and stays immediately retryable via a pending profile
    transaction; the commit itself is staged through a temporary file,
    rotated into backups only after the temp verifies, and never deletes the
    only known-good save on failure; the save_failed signal drives the pause
    + retry dialog; and the director retries the pending transaction on the
    first tick. The runtime suite (tests/campaign_runtime/) drives this path
    end-to-end in CI.
    """

    @staticmethod
    def _visit_body():
        src = source("scripts/campaign/campaign_director.gd")
        return src.split("func _visit_checkpoint", 1)[1].split("\n\nfunc ", 1)[0]

    def test_failed_checkpoint_commit_rolls_back_in_order(self):
        body = self._visit_body()
        ordered = [
            "var previous_checkpoint := String(progress.checkpoint)",
            "progress.checkpoint = near",
            "if save_progress(true):",
            "progress.checkpoint = previous_checkpoint",
        ]
        position = 0
        for fragment in ordered:
            found = body.find(fragment, position)
            self.assertNotEqual(found, -1, f"visit rollback missing: {fragment}")
            self.assertGreater(found, position - 1, f"visit rollback out of order: {fragment}")
            position = found + 1
        # The no-pad guard also assigns _checkpoint_inside, so the failure
        # branch is anchored on the rollback assignment itself.
        failure_branch = body[body.find("progress.checkpoint = previous_checkpoint"):]
        for fragment in (
            "save_progress(false)",
            '_checkpoint_inside = ""',
            "_retry_notice = true",
            'message.emit("Restored health. Saving failed — checkpoint not advanced; retry here.")',
        ):
            self.assertIn(fragment, failure_branch, f"failure branch missing: {fragment}")

    def test_rollback_keeps_the_pad_immediately_retryable(self):
        body = self._visit_body()
        failure_branch = body.split("else:", 1)[1]
        self.assertIn('_checkpoint_inside = ""', failure_branch,
                      "the visit lock must clear so the same pad can be re-rested")
        self.assertNotIn("progress.checkpoint = near", failure_branch,
                         "the failed branch must not re-apply the pending checkpoint")

    def test_failed_commit_leaves_a_pending_transaction(self):
        src = source("scripts/save/save_manager.gd")
        body = src.split("func commit_profile_transaction", 1)[1].split("\n\nfunc ", 1)[0]
        pending_set = body.find("_pending_profile = normalized.duplicate(true)")
        apply = body.find("_apply_profile_slice(normalized)")
        rollback = body.find("_apply_profile_slice(previous)")
        self.assertNotEqual(pending_set, -1,
                            "the commit must stage a retryable pending slice")
        self.assertGreater(apply, pending_set, "in-memory state applies after staging")
        self.assertGreater(rollback, body.find("var ok := save_now()"),
                           "a failed flush must roll the in-memory state back")
        self.assertNotIn("_pending_profile.clear()", body.split("var ok := save_now()")[0],
                         "a failed commit must KEEP the pending slice for retry")

    def test_commit_is_staged_through_temporary_file_and_rename(self):
        src = source("scripts/save/save_manager.gd")
        stage = src.split("func _stage_temp", 1)[1].split("\n\nfunc ", 1)[0]
        write = stage.find("FileAccess.open(tmp, FileAccess.WRITE)")
        flush = stage.find("file.flush()")
        self.assertNotEqual(write, -1, "commit must write a temporary file")
        self.assertGreater(flush, write, "flush must precede the commit rename")
        self.assertIn("_discard_temp(tmp)", stage,
                      "every staging failure path must discard the temp")
        commit = src.split("func _commit_rename", 1)[1].split("\n\nfunc ", 1)[0]
        rename = commit.find("DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), "
                             "ProjectSettings.globalize_path(path))")
        self.assertNotEqual(rename, -1, "commit must be a same-directory rename")
        self.assertNotIn("remove_absolute(ProjectSettings.globalize_path(path))", src,
                         "a failed commit must never delete the only known-good save")
        self.assertIn("_discard_temp(tmp)", commit,
                      "a failed rename must clean up its own temporary file")

    def test_flush_stages_then_rotates_then_commits(self):
        src = source("scripts/save/save_manager.gd")
        body = src.split("func _flush_save", 1)[1].split("\n\nfunc ", 1)[0]
        pending_apply = body.find("_apply_profile_slice(_pending_profile)")
        stage = body.find("_stage_temp(tmp, _serialize_save())")
        rotate = body.find("_rotate_backups_from_primary()")
        commit = body.find("_commit_rename(tmp, SAVE_PATH)")
        self.assertNotEqual(pending_apply, -1,
                            "a pending slice must re-apply before the flush serializes")
        self.assertGreater(stage, pending_apply, "staging precedes rotation")
        self.assertGreater(rotate, stage,
                           "backup rotation runs only after the temp verifies")
        self.assertGreater(commit, rotate, "the rename is the commit point")
        self.assertEqual(body.count('EventBus.save_failed.emit(&"write_failed")'), 2,
                         "both failure paths must signal save_failed so the UI can act")
        self.assertIn("_pending_profile.clear()", body,
                      "a successful flush must clear the pending slice")
        self.assertIn("EventBus.save_completed.emit()", body)

    def test_pending_transaction_retries_on_first_director_tick(self):
        src = source("scripts/campaign/campaign_director.gd")
        process = src.split("func _physics_process", 1)[1].split("\n\nfunc ", 1)[0]
        check = process.find("SaveManager.has_pending_profile_transaction()")
        self.assertNotEqual(check, -1,
                            "the first tick must look for a pending profile transaction")
        self.assertGreater(process.find("_clock += delta"), check,
                           "the retry runs before the sim clock advances")
        retry = src.split("func _retry_pending_transaction", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertIn("CampaignProgress.reconcile(pending.get(\"campaign\", {}), definition)", retry)
        self.assertIn("_meta.restore_wallet", retry)
        self.assertIn("SaveManager.retry_pending_profile_transaction()", retry)

    def test_save_failed_signal_pauses_with_retry_dialog(self):
        ui = source("scripts/campaign/campaign_ui.gd")
        body = ui.split("func _on_save_failed", 1)[1].split("\n\nfunc ", 1)[0]
        self.assertIn("EventBus.save_failed.connect(_on_save_failed)",
                      source("scripts/campaign/campaign_ui.gd"))
        self.assertIn("GameRoot.request_pause()", body)
        self.assertIn('confirm("SAVING FAILED"', body)
        self.assertIn("SaveManager.save_now", body,
                      "the retry dialog must re-issue the save")

    def test_runtime_suite_drives_the_failure_path_end_to_end(self):
        inner = source(INNER)
        for marker in (
            "failed checkpoint save does not advance the checkpoint",
            "failed save pauses the run with a save dialog",
            "failed save leaves the on-disk save byte-identical",
            "failed commit leaves a retryable pending transaction",
            "pending transaction retries on the first tick",
            "checkpoint advances on the immediate retry",
            "failed save corrupted no mission progress",
        ):
            self.assertIn(marker, inner)


class CampaignBudgetSingleSourceSpec(unittest.TestCase):
    """requires Agent #6 — single-sourced budgets (audit weakness #6).

    The budgets now live in scripts/campaign/campaign_budgets.gd and every
    runtime copy aliases it (the detailed aliasing/no-drift pins live in
    tests/python/test_campaign_budgets.py). This audit-#6 pin keeps the one
    contract the runtime suite relies on: the authored JSON values stay
    inside the typed single source, and the streaming consumers still read
    the definition field rather than a literal.
    """

    @staticmethod
    def _budgets_const(name: str) -> int:
        match = re.search(r"^const %s := (\d+)" % name,
                          source("scripts/campaign/campaign_budgets.gd"), re.M)
        assert match is not None, f"CampaignBudgets lost {name}"
        return int(match.group(1))

    def test_authored_enemy_budget_stays_inside_the_typed_single_source(self):
        self.assertLessEqual(campaign.load()["max_active_enemies"],
                             self._budgets_const("MAX_ACTIVE_ENEMIES"))
        encounters = source("scripts/campaign/campaign_encounters.gd")
        self.assertGreaterEqual(encounters.count("_definition.max_active_enemies"), 2,
                                "encounters must consume the budget from the typed definition")

    def test_authored_sector_budget_stays_inside_the_typed_single_source(self):
        self.assertLessEqual(campaign.load()["max_visible_sectors"],
                             self._budgets_const("MAX_VISIBLE_DISTRICTS"))
        world = source("scripts/campaign/campaign_world.gd")
        self.assertIn("definition.max_visible_sectors", world,
                      "world must consume the sector budget from the typed definition")


if __name__ == "__main__":
    unittest.main()
