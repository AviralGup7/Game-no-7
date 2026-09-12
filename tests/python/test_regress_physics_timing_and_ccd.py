"""Regression: render-tick vs physics-tick timing, and swept projectile collision.

Three failure classes this pins, all of them invisible to the type checker and to
Godot's own validation:

  1. FRAME-RATE ALIASING. Gameplay ticks at a fixed 60 Hz, rendering does not
     (120 Hz panels; PerformanceMonitor steps Engine.max_fps down to 30 on weak
     devices). Without `physics/common/physics_interpolation`, a camera that solves
     in `_process` reads the stale physics-tick transform every render frame and the
     mismatch shows as micro-stutter / hard 2:1 judder. The rig must therefore opt
     OUT of engine interpolation for itself (it is written every render frame, so
     blending it again would add a tick of lag) and read the target's INTERPOLATED
     transform. Same rule for anything that animates a transform from `_process`.

  2. HOT-PATH ALLOCATION. `CameraCollisionSolver.solve()` runs once per render
     frame and used to build a SphereShape3D + PhysicsShapeQueryParameters3D + one
     PhysicsRayQueryParameters3D per whisker, i.e. up to 6 RID-backed objects per
     frame handed to the physics server. Query parameter objects are read at call
     time, so the pooled pattern (already used by EnemyPack._sep_query) is the
     contract: build once, mutate per query, and gate the spatial pass on a clock.

  3. PROJECTILE TUNNELLING. A Projectile moves itself by assigning global_position,
     so the server never integrates it and there is no CCD: at the fastest authored
     shot (24 m/s) that is 0.40 m per tick against a 0.25 m sphere. Each step must
     be swept, and both hit paths (sweep + Area3D overlap) must go through one
     resolver so they cannot disagree about what a hit means.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

TRANSFORM_WRITE = re.compile(
    r"(global_position\s*=|global_transform\s*=|\.position\s*[-+]?=|\.scale\s*[-+]?=|"
    r"\.rotation\s*[-+]?=|look_at\s*\(|rotate_object_local\s*\()"
)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def func_body(text: str, header: str) -> str:
    """Body of the first func whose line starts with `header`, up to the next func."""
    start = text.find(header)
    if start < 0:
        return ""
    nxt = re.search(r"\nfunc ", text[start + len(header):])
    return text[start:start + len(header) + (nxt.start() if nxt else len(text))]


class InterpolationSettingsTests(unittest.TestCase):
    def setUp(self):
        self.proj = read("project.godot")

    def test_physics_interpolation_is_on(self):
        self.assertIn("common/physics_interpolation=true", self.proj,
                      msg="the sim renders at a different rate than it ticks; without "
                          "interpolation the camera shows every tick boundary")

    def test_fixed_tick_still_60hz(self):
        # Interpolation is purely visual, so the deterministic tick rate must NOT be
        # tuned to "fix" judder. Anyone tempted to raise it needs to re-check the
        # per-tick budgets in EnemyPack / wave configs first.
        self.assertIn("common/physics_ticks_per_second=60", self.proj)

    def test_step_cap_is_documented_as_a_brake(self):
        body = self.proj.split("[physics]", 1)[1].split("[", 1)[0]
        self.assertIn("common/max_physics_steps_per_frame=6", body)
        self.assertIn("spiral-of-death", body)
        self.assertIn("NOT extra time", body,
                      msg="the 6-step cap silently discards time beyond 100 ms of hitch; "
                          "the reason has to stay written next to the number")


class CameraTimingTests(unittest.TestCase):
    def test_rig_opts_out_and_reads_the_interpolated_target(self):
        rig = read("scripts/main/camera_rig.gd")
        for needle, why in (
            ("func _configure_interpolation() -> void:", "the opt-out helper vanished"),
            ("physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF",
             "the rig is written every render frame; the engine must not blend it again"),
            ("_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF",
             "the Camera3D transform is assigned by _update_look_at()"),
            ("_target.get_global_transform_interpolated()",
             "the follow point must come from the interpolated target transform"),
            ("get_setting(", "the interpolated read must be gated on the project setting"),
        ):
            self.assertIn(needle, rig.replace("\n", " "), msg=f"camera_rig.gd: {why}")

    def test_rig_follow_reads_interpolated_position_not_the_raw_tick(self):
        rig = read("scripts/main/camera_rig.gd")
        body = func_body(rig, "func _process(delta: float) -> void:")
        self.assertTrue(body, msg="CameraRig._process vanished")
        self.assertIn("var curr_pos := _target_position_render()", body,
                      msg="the render-tick path must use the interpolated reader")
        self.assertNotIn("var curr_pos := _target.global_position", body,
                         msg="reading the raw physics-tick transform in _process is the jitter")

    def test_teleports_invalidate_the_collision_cache(self):
        # A 10 m jump makes the last spring-arm query meaningless; the cached
        # pullback must be dropped for that frame or the camera can swing through
        # the wall it just landed behind.
        rig = read("scripts/main/camera_rig.gd")
        self.assertEqual(rig.count("_collision.invalidate_cache()"), 3,
                         msg="expected invalidation after the teleport guard, the "
                             "retarget snap and reset_transform()")

    def test_no_transform_writer_in_process_without_an_opt_out(self):
        """Anything that animates a transform from `_process` fights interpolation:
        the engine blends between physics-tick snapshots, so its idle-time writes
        arrive a tick late. Either move the write to `_physics_process` or opt the
        node out with PHYSICS_INTERPOLATION_MODE_OFF (the new case must be listed)."""
        offenders = []
        for gd in sorted((ROOT / "scripts").rglob("*.gd")):
            text = gd.read_text(encoding="utf-8", errors="ignore")
            body = func_body(text, "func _process(")
            if not body or not TRANSFORM_WRITE.search(body):
                continue
            if "PHYSICS_INTERPOLATION_MODE_OFF" in text:
                continue
            offenders.append(str(gd.relative_to(ROOT)))
        self.assertEqual(offenders, [],
                         msg="add physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF "
                             "(or tick the movement):\n  " + "\n  ".join(offenders))


class SolverPerfTests(unittest.TestCase):
    def setUp(self):
        self.solver = read("scripts/main/camera/camera_collision_solver.gd")

    def test_query_objects_are_built_once_in_the_pooled_helper(self):
        ensure = func_body(self.solver, "func _ensure_query_objects() -> void:")
        self.assertTrue(ensure, msg="_ensure_query_objects vanished")
        for ctor in ("SphereShape3D.new()", "PhysicsShapeQueryParameters3D.new()",
                     "PhysicsRayQueryParameters3D.new()"):
            self.assertEqual(self.solver.count(ctor), 1,
                             msg=f"{ctor} must appear exactly once, inside _ensure_query_objects()")
            self.assertIn(ctor, ensure)
        # The old bug: the static factory hid an allocation per whisker per frame.
        self.assertNotIn("PhysicsRayQueryParameters3D.create(", self.solver)

    def test_spatial_pass_is_gated_by_time_and_distance(self):
        self.assertIn("const QUERY_INTERVAL", self.solver)
        self.assertIn("const CACHE_SLACK", self.solver)
        gate = func_body(self.solver, "func _needs_fresh_pass(")
        self.assertIn("_time_until_query <= 0.0", gate)
        # Both ends of the arm gate the cache: the desired point sweeps into walls
        # and the focus point slides with shoulder offset / look-ahead.
        self.assertIn("var slack_sq := CACHE_SLACK * CACHE_SLACK", gate)
        self.assertIn("(to - _cached_to).length_squared() > slack_sq", gate)
        self.assertIn("(from - _cached_from).length_squared() > slack_sq", gate)
        self.assertIn("if _needs_fresh_pass(from, to):", func_body(self.solver, "func solve("))

    def test_ground_clearance_reuses_the_cached_probe(self):
        solve = func_body(self.solver, "func solve(")
        self.assertNotIn("intersect_ray", solve,
                         msg="solve() must not issue its own ray; the ground probe is "
                             "part of the gated pass")
        self.assertIn("_cached_ground_hit", solve)

    def test_query_flags_are_explicit_and_bodies_only(self):
        self.assertIn("_shape_query.collide_with_areas = false", self.solver)
        self.assertIn("_ray_query.collide_with_areas = false", self.solver)
        self.assertIn("func get_debug_snapshot() -> Dictionary:", self.solver)

    def test_rig_uses_only_the_public_solver_surface(self):
        rig = read("scripts/main/camera_rig.gd")
        self.assertIn("_collision.tick_recovery(delta)", func_body(rig, "func _process("))
        self.assertIn("func invalidate_cache() -> void:", self.solver)
        self.assertIn("func tick_recovery(delta: float) -> void:", self.solver)


class ProjectileSweepTests(unittest.TestCase):
    def setUp(self):
        self.proj = read("scripts/weapons/projectile.gd")

    def test_sweep_is_on_by_default_and_opt_out(self):
        self.assertIn("@export var swept_collision: bool = true", self.proj)
        self.assertIn("@export var sweep_radius: float = 0.25", self.proj)

    def test_step_is_swept_before_it_is_applied(self):
        step = func_body(self.proj, "func _advance(step: float) -> void:")
        self.assertTrue(step, msg="_advance vanished — the step must go through the sweep")
        self.assertIn("_sweep_first(space, from, from + direction * remaining)", step)
        self.assertIn("cast_motion", self.proj)
        # A spent segment budget must not park the shot mid-flight.
        self.assertIn("MAX_SWEEP_SEGMENTS", step)
        self.assertIn("global_position += direction * (step - consumed)", step)

    def test_no_space_means_old_behaviour_not_a_stall(self):
        step = func_body(self.proj, "func _advance(step: float) -> void:")
        self.assertIn(
            "if space == null or not swept_collision or _sweep_query == null:", step,
            msg="the fallback must cover every missing ingredient, including a caller "
                "that obtained a Projectile without launch()")
        head = func_body(self.proj, "func _direct_space() -> PhysicsDirectSpaceState3D:")
        self.assertIn("if not is_inside_tree():", head,
                      msg="headless fixtures have no space; the sweep must decline, not crash")
        self.assertIn("world == null", head)

    def test_one_resolver_for_both_hit_paths(self):
        entered = func_body(self.proj, "func _on_body_entered(body: Node) -> void:")
        self.assertIn("_resolve_hit(body)", entered,
                      msg="the overlap signal must not keep its own copy of hit rules")
        resolve = func_body(self.proj, "func _resolve_hit(body: Node) -> void:")
        for needle in ("_hit_bodies", "_is_enemy_of", "_is_world", "_release_with_impact",
                       "pierce_remaining"):
            self.assertIn(needle, resolve)
        self.assertIn("_resolve_hit(body)", func_body(self.proj, "func _advance(step: float) -> void:"))

    def test_sweep_never_lets_a_shot_shoot_down_its_own_volley(self):
        ensure = func_body(self.proj, "func _ensure_sweep_state() -> void:")
        self.assertIn("_sweep_query.collide_with_areas = false", ensure)
        self.assertIn("_sweep_ray.collide_with_areas = false", ensure)
        self.assertIn("_sweep_ray.hit_from_inside = true", ensure)

    def test_launcher_is_ignored_for_the_whole_flight(self):
        # A shot spawns inside the shooter's capsule; if the sweep could see that
        # body it would stop the first projectile dead against its own launcher.
        launch = func_body(self.proj, "func launch(config: Dictionary) -> void:")
        self.assertIn("_ignore_rids.clear()", launch)
        self.assertIn("_ignore_body(source)", launch)
        ignore = func_body(self.proj, "func _ignore_body(body: Node) -> void:")
        self.assertIn("is CollisionObject3D", ignore)
        self.assertIn("get_rid()", ignore)
        # ...and the ignore list is rebuilt, never inherited from the previous shot.
        self.assertIn("_ignore_rids.clear()", func_body(self.proj, "func pool_reset() -> void:"))

    def test_sweep_radius_tracks_the_authored_shape(self):
        pool = read("scripts/weapons/projectile_pool.gd")
        self.assertIn("const SWEEP_RADIUS := 0.25", pool)
        self.assertIn("p.sweep_radius = float(authored.radius)", pool)
        self.assertIn("p.sweep_radius = SWEEP_RADIUS", pool)


class InterpolationResetTests(unittest.TestCase):
    """Teleports need reset_physics_interpolation() AFTER the position write —
    before it, the snapshots still point at the old place and the node visibly
    slides to its new one."""

    SITES = {
        "scripts/weapons/projectile.gd": ["global_position = config.get(\"origin\", global_position)",
                                           "global_position = Vector3(0, -100, 0)"],
        "scripts/pickups/pickup.gd": ["global_position = at",
                                       "global_position = Vector3(0, -100, 0)"],
        "scripts/enemies/spawn_manager.gd": ["instance.global_position = jittered if",
                                              "instance.global_position = spawn_position"],
        "scripts/player/character_controller.gd": ["0.0 if not is_finite(pos.z) else clampf(pos.z, -1.0e4, 1.0e4))"],
        "scripts/player/player_locomotion.gd": ["0.0 if not is_finite(p.z) else clampf(p.z, -limit, limit))"],
        "scripts/player/player.gd": ["global_transform = spawn_transform"],
    }

    def test_every_pool_or_teleport_writes_then_resets(self):
        for rel, writes in self.SITES.items():
            text = read(rel)
            for write in writes:
                at = text.find(write)
                self.assertGreaterEqual(at, 0, msg=f"{rel}: teleport write {write!r} disappeared")
                window = text[at:at + 600]
                self.assertRegex(window, r"reset_physics_interpolation\(\)",
                                 msg=f"{rel}: write at {write[:40]!r} is not followed by an "
                                     f"interpolation reset (the node will slide across the jump)")

    def test_the_reset_belongs_to_the_actor_not_its_caller(self):
        # main.gd places the hero via reset_for_new_run(); if the reset lived at the
        # call site, the next caller (menu preview, debug spawn) would forget it.
        player = read("scripts/player/player.gd")
        self.assertIn("func reset_for_new_run(spawn_transform: Transform3D) -> void:\n"
                      "\tglobal_transform = spawn_transform\n", player)
        self.assertLess(player.index("global_transform = spawn_transform"),
                        player.index("reset_physics_interpolation()"),
                        msg="reset must follow the write, never precede it")

    def test_reset_is_a_method_call_not_a_comment(self):
        # A `# reset_physics_interpolation()` line would satisfy the forward-window
        # scan above and still leave the smear, so require live calls.
        for rel in self.SITES:
            text = read(rel)
            live = [ln for ln in text.splitlines() if "reset_physics_interpolation()" in ln]
            self.assertTrue(live, msg=f"{rel}: no live interpolation reset")
            for ln in live:
                self.assertFalse(ln.strip().startswith("#"),
                                 msg=f"{rel}: commented-out reset {ln.strip()!r}")


    def test_pooled_pickup_burst_resets_per_item(self):
        mgr = read("scripts/pickups/pickup_manager.gd")
        burst = func_body(mgr, "func magnet_burst() -> int:")
        self.assertIn("p.reset_physics_interpolation()", burst)


if __name__ == "__main__":
    unittest.main()
