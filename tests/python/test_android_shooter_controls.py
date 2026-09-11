"""Offline source guards. Device input and geometry are exercised by the native UI suite."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text()

def body(path, name):
    return read(path).split("func " + name + "(", 1)[1].split("\n\nfunc ", 1)[0]

class AndroidShooterControlsTests(unittest.TestCase):
    def test_fourth_action_uses_shared_safe_area_solver(self):
        controls = read("scripts/ui/touch_controls.gd")
        self.assertIn('["reload", "request_reload", 52.0]', controls)
        self.assertIn('["attack", "dodge", "swap", "reload"]', controls)
        self.assertIn('"reload": reload_button', read("scripts/ui/ui_layout.gd"))
        ui_tests = read("tests/ui/ui_test_runner.gd")
        self.assertIn('["stick", "skills", "attack", "dodge", "swap", "reload"]', ui_tests)

    def test_drag_capture_is_owned_and_never_drives_camera(self):
        capture = body("scripts/ui/touch_action_button.gd", "_input")
        self.assertIn('drag.index == _touch_index and action_name == "attack"', capture)
        self.assertIn('get_global_transform_with_canvas().affine_inverse() * drag.position', capture)
        self.assertIn('get_viewport().set_input_as_handled()', capture)
        self.assertIn('InputEvent.DEVICE_ID_EMULATION', capture)
        aim = body("scripts/ui/touch_action_button.gd", "_update_aim")
        self.assertIn('raw.limit_length(1.0)', aim)
        self.assertIn('AIM_DEADZONE', aim)
        self.assertIn('not local_position.is_finite()', aim)

    def test_lifecycle_and_disabled_state_clear_both_intents(self):
        for path in ('scripts/ui/touch_controls.gd', 'scripts/ui/touch_action_button.gd', 'scripts/player/player.gd'):
            notification = body(path, '_notification')
            for note in ('APPLICATION_PAUSED', 'APPLICATION_FOCUS_OUT', 'WM_WINDOW_FOCUS_OUT'):
                self.assertIn('NOTIFICATION_' + note, notification)
        clear = body('scripts/player/player.gd', '_clear_input')
        self.assertIn('_touch_fire_held = false', clear)
        self.assertIn('_touch_aim = Vector2.ZERO', clear)
        setter = body('scripts/player/player.gd', 'set_touch_fire_input')
        self.assertIn('not is_control_enabled() or not held or not aim.is_finite()', setter)
        self.assertIn('held and playing', body('scripts/ui/ui_commands.gd', 'fire_input'))

    def test_manual_aim_is_camera_relative_and_survives_strafing(self):
        aim = body('scripts/player/player.gd', '_aim_attack')
        self.assertIn('_controller.screen_to_world_dir(_touch_aim)', aim)
        self.assertIn('20.0 if manual_touch else 65.0', aim)
        physics = body('scripts/player/player.gd', '_physics_process')
        motion = body('scripts/player/player.gd', '_tick_motion')
        self.assertIn('_tick_motion(delta, move)', physics)
        self.assertLess(motion.index('_controller.tick(move, delta)'), motion.index('_controller.face_direction(fire_facing)'))
        self.assertNotIn('_aim_attack()', physics)  # Only _try_attack scans targets, once per tick.
        target = body('scripts/player/targeting_component.gd', 'pick_best_target')
        self.assertIn('acquisition_cone_degrees', target)
        self.assertIn('\n\t_sticky = best\n\treturn best', target)

    def test_android_guidance_never_requires_keyboard(self):
        for path in ('scripts/ui/help_panel.gd', 'scripts/ui/tutorial_manager.gd', 'scripts/ui/game_hud.gd'):
            text = read(path)
            self.assertIn('RELOAD', text)
            self.assertNotIn('Press R', text)
            self.assertNotIn('WASD', text)
        self.assertIn('if not OS.has_feature("mobile"):', read('scripts/ui/settings_panel.gd'))
        camera = body('scripts/main/camera/camera_input_handler.gd', 'handle_touch_look')
        self.assertIn('_touch_accum.x += (relative.x / width)', camera)
        self.assertIn('_touch_accum.y += (relative.y / height)', camera)
        self.assertNotIn('is_mouse_button_pressed', camera)
        project = read('project.godot')
        self.assertIn('window/handheld/orientation=4', project)
        self.assertIn('pointing/emulate_mouse_from_touch=true', project)  # Standard menu Buttons need this.
        self.assertIn('config/quit_on_go_back=false', project)

if __name__ == '__main__':
    unittest.main()
