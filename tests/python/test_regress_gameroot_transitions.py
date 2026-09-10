"""Regression: GameRoot legal transitions & restart fallback — guards Batch1 fixes."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class GameRootTests(unittest.TestCase):
    def test_legal_transitions_include_restart(self):
        txt=read("scripts/core/game_root.gd")
        self.assertIn('State.PLAYING: [State.WAVE_TRANSITION, State.GAME_OVER, State.STARTING_RUN',txt)
        self.assertIn('State.WAVE_TRANSITION: [State.PLAYING, State.UPGRADE_SELECTION, State.GAME_OVER, State.STARTING_RUN',txt)
        self.assertIn('State.UPGRADE_SELECTION: [State.PLAYING, State.GAME_OVER, State.STARTING_RUN',txt)
    def test_request_restart_fallback(self):
        txt=read("scripts/core/game_root.gd")
        self.assertIn("func request_restart()",txt)
        self.assertIn("if not transition_to(State.STARTING_RUN):",txt)
        self.assertIn("_apply_state(State.MAIN_MENU)",txt)
        self.assertIn("get_tree().paused = false",txt)
    def test_transitions_are_serialized_against_synchronous_signals(self):
        txt=read("scripts/core/game_root.gd")
        self.assertIn("var _transition_in_progress := false", txt)
        self.assertIn("var _pending_state: StringName", txt)
        self.assertIn("func _transition_now", txt)
        self.assertIn("# A state-enter hook or signal listener may have requested", txt)
        self.assertIn("_transition_now(queued)", txt)
        self.assertIn("MAX_TRANSITION_HISTORY", txt)

    def test_scene_router_guards_invalid(self):
        txt=read("scripts/core/scene_router.gd")
        self.assertIn("get_tree() != null",txt)
        self.assertIn("if is_inside_tree() and get_tree() != null:",txt)
    def test_content_loader_deterministic(self):
        txt=read("scripts/core/content_loader.gd")
        self.assertIn("keys.sort()",txt)
        self.assertIn("keys: Array = arenas.keys()",txt)
if __name__=="__main__": unittest.main()
