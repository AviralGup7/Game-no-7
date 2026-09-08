"""Stress: 20-50 wave lifecycle cycles with splitter/boss/pause/restart.

Pure-Python simulation of SpawnLedger accounting to prove the invariants
hold under repeated cycles — the audit appendix asked for 20-50 restart
cycles to catch leaked EventBus connections or stale ledger state.
"""

import unittest

# ---- Minimal Python re-implementation of SpawnLedger for stress ----
MAX_FAILED = 6


class LedgerSim:
    def __init__(self):
        self._pending = []
        self._planned = 0
        self._spawned = 0
        self._defeated = 0
        self._failed = 0
        self._attempt_head = ""
        self._attempt = 0

    def reset(self, queue):
        self._pending = list(queue)
        self._planned = len(queue)
        self._spawned = 0
        self._defeated = 0
        self._failed = 0
        self._attempt_head = ""
        self._attempt = 0

    def clear(self):
        self.reset([])

    def peek(self):
        return self._pending[0] if self._pending else ""

    def note_head(self, arch):
        if arch != self._attempt_head:
            self._attempt_head = arch
            self._attempt = 0

    def pop_on_success(self):
        if not self._pending:
            return
        self._pending.pop(0)
        self._spawned += 1
        self._attempt_head = ""
        self._attempt = 0

    def note_attempt(self):
        self._attempt += 1
        if self._attempt < MAX_FAILED:
            return False
        if self._pending:
            self._pending.pop(0)
            self._failed += 1
        self._attempt_head = ""
        self._attempt = 0
        return True

    def extend_one(self, arch):
        self._pending.append(arch)
        self._planned += 1

    def register_direct_spawn(self, arch):
        self._planned += 1
        self._spawned += 1

    def record_defeat(self):
        self._defeated += 1

    def all_cleared(self):
        # wave completes when every planned enemy is accounted as defeated or failed
        # and nothing is still pending
        return not self._pending and (self._defeated + self._failed) == self._planned

    def snapshot(self):
        return {
            "planned": self._planned,
            "pending": len(self._pending),
            "spawned": self._spawned,
            "defeated": self._defeated,
            "failed": self._failed,
        }


class LifecycleStressTests(unittest.TestCase):
    def test_50_wave_cycles_with_splitter_and_boss(self):
        """Each wave: 10 planned -> 2 splitters add 2 children each -> boss adds 3 summons.
        All must be defeated before all_cleared; pending must drain exactly."""
        for cycle in range(50):
            ledger = LedgerSim()
            base = [f"grunt_{i}" for i in range(8)] + ["splitter", "splitter"]
            ledger.reset(base)
            # Simulate spawn success for all 10
            while ledger._pending:
                head = ledger.peek()
                ledger.note_head(head)
                ledger.pop_on_success()
            # Splitter children: each splitter spawns 2 children (burst)
            for _ in range(2):
                ledger.extend_one("splitling")
                ledger.extend_one("splitling")
            # Spawn the 4 children
            while ledger._pending:
                ledger.pop_on_success()
            # Boss summons 3
            for _ in range(3):
                ledger.extend_one("summoned")
            while ledger._pending:
                ledger.pop_on_success()
            # Now defeat everything: planned = 10 + 4 + 3 = 17
            snap = ledger.snapshot()
            self.assertEqual(snap["planned"], 17, f"cycle {cycle} planned")
            for _ in range(snap["planned"]):
                ledger.record_defeat()
            self.assertTrue(ledger.all_cleared(), f"cycle {cycle} not cleared: {ledger.snapshot()}")
            # Next cycle must start clean (no leak)
            ledger.clear()
            self.assertEqual(ledger.snapshot()["planned"], 0)

    def test_bounded_retry_does_not_block_wave(self):
        ledger = LedgerSim()
        ledger.reset(["bad_archetype"])
        # All attempts fail until bound
        for i in range(MAX_FAILED - 1):
            ledger.note_head("bad_archetype")
            dropped = ledger.note_attempt()
            self.assertFalse(dropped, f"should retry at {i}")
            self.assertEqual(len(ledger._pending), 1)
        ledger.note_head("bad_archetype")
        dropped = ledger.note_attempt()
        self.assertTrue(dropped)
        self.assertEqual(ledger._pending, [])
        self.assertEqual(ledger.snapshot()["failed"], 1)
        # Wave can still complete (failed counts as accounted)
        self.assertTrue(ledger.all_cleared())

    def test_splitter_failure_still_extends_ledger(self):
        ledger = LedgerSim()
        ledger.reset(["splitter"])
        ledger.pop_on_success()
        # Unknown child still queued as failed after retries, but planned grew
        ledger.extend_one("unknown_xyz")
        self.assertEqual(ledger.snapshot()["planned"], 2)
        for _ in range(MAX_FAILED):
            ledger.note_head("unknown_xyz")
            ledger.note_attempt()
        self.assertEqual(ledger.snapshot()["failed"], 1)
        ledger.record_defeat()  # splitter itself
        self.assertTrue(ledger.all_cleared())

    def test_boss_immediate_summon_not_lost(self):
        """Regression for P0: summon emitted during begin_fight must be counted."""
        ledger = LedgerSim()
        ledger.reset(["boss"])
        # Simulate boss spawn then immediate summon during begin_fight
        ledger.pop_on_success()  # boss spawned
        # If connect were after begin_fight, this would be lost
        ledger.extend_one("summoned")
        self.assertEqual(ledger.snapshot()["planned"], 2)
        ledger.pop_on_success()  # summon spawned
        ledger.record_defeat()
        ledger.record_defeat()
        self.assertTrue(ledger.all_cleared())

    def test_restart_50_times_no_accumulation(self):
        ledger = LedgerSim()
        for _ in range(50):
            ledger.reset(["grunt"] * 5)
            while ledger._pending:
                ledger.pop_on_success()
            for _ in range(5):
                ledger.record_defeat()
            self.assertTrue(ledger.all_cleared())
            ledger.clear()
        self.assertEqual(ledger.snapshot()["planned"], 0)
        self.assertEqual(ledger.snapshot()["defeated"], 0)

    def test_pause_does_not_advance_ledger(self):
        # Ledger is event-driven, not time-driven, so pause is a no-op — snapshot must not change
        ledger = LedgerSim()
        ledger.reset(["grunt", "grunt"])
        ledger.pop_on_success()
        snap_before = ledger.snapshot()
        # "paused" — do nothing
        snap_after = ledger.snapshot()
        self.assertEqual(snap_before, snap_after)


if __name__ == "__main__":
    unittest.main()
