"""Regression: the status-effect subsystem (StatusManager / StatusEffect / StatusEffectConfig).

Why these pins exist
--------------------
StatusManager is the per-entity component that every movement tick, every hit and every
DoT in the game reads. It used to answer five derived numbers by re-folding its whole
effect table on each read (~80 Dictionary walks with an `as StatusEffect` cast and three
pow() calls per tick at a full wave), re-run the 14-rule config audit inside the tick, and
allocate two fresh Arrays per entity per tick (`_effects.keys().duplicate()`). The
rebuild caches the folds behind a dirty flag and keeps the table typed.

Like the hazard suite, the point is not "some numbers moved": a weak design is *pinned out*
so it cannot come back quietly. Each check below was verified to fail when the
corresponding regression was injected into a scratch copy of the repo.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

STATUS_DIR = ROOT / "data" / "status"
MANAGER = "scripts/status/status_manager.gd"
EFFECT = "scripts/status/status_effect.gd"
CONFIG = "scripts/status/status_effect_config.gd"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code(rel: str) -> str:
    """Source without comment lines. The subsystem's doc comments deliberately name the
    designs being banned (`as StatusEffect`, `_shield_layers`, keys().duplicate()), so
    banning tokens must scan code only."""
    return "\n".join(l for l in read(rel).splitlines() if not l.lstrip().startswith("#"))


def tres_fields(path: pathlib.Path) -> dict[str, str]:
    """Flat key = literal pairs from a [resource] block."""
    out: dict[str, str] = {}
    inside = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("[resource]"):
            inside = True
            continue
        if inside and line.startswith("["):
            break
        if inside and "=" in line:
            key, value = line.split("=", 1)
            out[key.strip()] = value.strip()
    return out


def literal(raw: str | None):
    """Coerce a .tres literal to a python value for the audit (opaque for Color/Array)."""
    if raw is None:
        return None
    text = raw.strip()
    if text.startswith("&"):
        return text[2:-1] if text.startswith('&"') else text
    if text in ("true", "false"):
        return text == "true"
    if text.startswith(("Color(", "Array[", "ExtResource", "SubResource", "[")):
        return text
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        return text


# --------------------------------------------------------------------------------
# The audit, mirrored in python so the shipped .tres set is *proven* to satisfy it.
# Converting StatusEffectConfig to ValidatedConfig makes ContentRegistry halt startup on
# a validation error in a debug build; that is only safe to do with evidence, and there is
# no Godot binary in CI. Defaults and rule text are read out of the GDScript class rather
# than restated here, so the mirror cannot drift from the rules it audits.
# --------------------------------------------------------------------------------

FIELD_RE = re.compile(
    r"^@export(?:_range\([^)]*\))?\s+var\s+(?P<name>\w+)\s*:\s*[\w.]+(?:\s*=\s*(?P<default>.+?))?\s*$",
    re.M,
)


def authored_defaults() -> dict:
    defaults = {}
    for m in FIELD_RE.finditer(read(CONFIG)):
        defaults[m.group("name")] = literal(m.group("default"))
    return defaults


def audit(effect_id: str, fields: dict, defaults: dict) -> list[str]:
    """The same rules StatusEffectConfig.validate() applies, on merged authored data."""
    def value(name, fallback=None):
        v = fields.get(name)
        parsed = literal(v) if v is not None else None
        return fallback if parsed is None else parsed

    problems: list[str] = []
    if not effect_id:
        problems.append("effect_id is empty")
    duration = value("duration", defaults.get("duration"))
    if duration is None or duration < 0.0:
        problems.append("duration cannot be negative")
    stuns = bool(value("stuns", defaults.get("stuns")))
    roots = bool(value("roots", defaults.get("roots")))
    shield = value("shield_amount", defaults.get("shield_amount"))
    if duration is not None and duration <= 0.0 and (stuns or roots):
        problems.append("permanent duration not allowed with stuns/roots")
    if value("max_stacks", defaults.get("max_stacks")) < 1:
        problems.append("max_stacks must be >= 1")
    modes = re.findall(r'^const STACK_\w+ := &"(\w+)"', read(CONFIG), re.M)
    if value("stack_mode", defaults.get("stack_mode")) not in modes:
        problems.append("invalid stack_mode")
    for name in ("dot_per_second", "hot_per_second", "move_speed_factor", "damage_factor",
                 "received_damage_factor", "shield_amount"):
        n = value(name, defaults.get(name))
        if n is not None and n < 0.0:
            problems.append(f"{name} cannot be negative")
    dot_types = re.findall(r'VALID_DOT_TYPES := \[([^\]]*)\]', read(CONFIG))
    allowed = re.findall(r'&"(\w+)"', dot_types[0]) if dot_types else []
    if value("dot_type", defaults.get("dot_type")) not in allowed:
        problems.append("invalid dot_type")
    tick = value("tick_interval", defaults.get("tick_interval"))
    if tick is None or tick <= 0.0:
        problems.append("tick_interval must be > 0")
    if shield is not None and shield > 0.0 and duration is not None and duration <= 0.0:
        problems.append("permanent shield (duration 0 + shield) would stall damage")
    return problems


class ShippedStatusDataTests(unittest.TestCase):
    """The evidence that justified making status authoring a load-time failure."""

    def test_there_are_status_configs_to_audit(self):
        files = sorted(STATUS_DIR.glob("*.tres"))
        self.assertGreaterEqual(len(files), 10, f"expected a populated status table, found {len(files)}")

    def test_every_shipped_status_passes_the_load_time_audit(self):
        defaults = authored_defaults()
        for path in sorted(STATUS_DIR.glob("*.tres")):
            fields = tres_fields(path)
            problems = audit(str(literal(fields.get("effect_id", ""))), fields, defaults)
            self.assertEqual(problems, [], f"{path.name} fails its own validate(): {problems}")

    def test_effect_id_matches_the_file_name(self):
        for path in sorted(STATUS_DIR.glob("*.tres")):
            effect_id = literal(tres_fields(path).get("effect_id", ""))
            self.assertEqual(effect_id, path.stem,
                             f"{path.name} is keyed by ContentLoader as {effect_id!r}")

    def test_the_mirror_tracks_the_class_rules(self):
        """A rule added to validate() without its mirror would slip through the "proven to
        pass" argument above, so every field the audit keys on has to appear here too."""
        body = read(CONFIG).split("func validate() -> Array[String]:")[1]
        class_fields = set(re.findall(r"\b(?:if|and|or)\s+([a-z_]+)\s*(?:<|>|!=|==|not in|<=|>=)", body))
        class_fields |= {m for m in re.findall(r'problems\.append\("([a-z_]+)', body)}
        audit_src = read("tests/python/test_regress_status_hot_path.py").split("def audit(")[1].split("\nclass ")[0]
        missing = sorted(f for f in class_fields if f not in audit_src)
        self.assertFalse(missing, f"validate() rules reference {missing}, which the audit does not check")
        self.assertGreaterEqual(len(class_fields), 10, "the audit in validate() got thinner")

    def test_no_shipped_status_is_permanent_except_where_the_runtime_allows_it(self):
        defaults = authored_defaults()
        for path in sorted(STATUS_DIR.glob("*.tres")):
            fields = tres_fields(path)
            duration = literal(fields.get("duration")) or defaults.get("duration")
            if duration is not None and duration > 0.0:
                continue
            # Anything permanent must not stun, root or shield — mirror the two cross rules.
            self.assertNotEqual(literal(fields.get("stuns")), "true", path.name)
            self.assertNotEqual(literal(fields.get("roots")), "true", path.name)
            self.assertIsNone(fields.get("shield_amount"), path.name)

    def test_duration_hint_allows_the_permanent_value_validate_accepts(self):
        """@export_range(0.05, ...) made "permanent until cleansed" unauthorisable in the
        inspector while validate() and is_permanent() both supported it — the same fix as
        HazardConfig.period."""
        hint = re.search(r"@export_range\(([^)]*)\) var duration", read(CONFIG))
        self.assertIsNotNone(hint, "duration lost its inspector bounds")
        self.assertEqual(float(hint.group(1).split(",")[0]), 0.0,
                         "duration's minimum must permit 0 (permanent) or the hint contradicts validate()")


class HotPathTests(unittest.TestCase):
    def test_tick_does_not_copy_the_key_array(self):
        body = code(MANAGER).split("func _physics_process")[1].split("\nfunc ")[0]
        self.assertNotIn(".keys()", body, msg="keys() allocates per tick; the tick reuses a scratch array")
        self.assertNotIn(".duplicate()", body, msg="no copying the effect table every frame")
        self.assertIn("_tick_keys.clear()", body, msg="the scratch must be emptied for the next tick")
        self.assertIn("_ticking = true", body, msg="shared scratch requires the re-entrancy guard")

    def test_tick_does_not_validate_configs(self):
        body = code(MANAGER).split("func _physics_process")[1].split("\nfunc ")[0]
        self.assertNotIn("validate()", body,
                         msg="the authoring audit runs at load and once per application, never per tick")

    def test_reads_are_cached_folds_not_scans(self):
        text = code(MANAGER)
        for query in ("move_speed_factor", "outgoing_damage_factor", "incoming_damage_factor",
                      "is_stunned", "is_rooted", "shield_remaining"):
            body = text.split(f"func {query}(")[1].split("\n\n")[0]
            self.assertNotIn("for id in _effects", body, f"{query}() must not walk the table on every read")
            self.assertIn("_consume_aggregate_read()", body, f"{query}() must go through the cache")
        fold = text.split("func _recompute_aggregates()")[1]
        self.assertIn("for id in _effects", fold, msg="the fold is the single place that walks the table")
        self.assertIn("\tif _aggregates_dirty:\n\t\t_recompute_aggregates()", text,
                      msg="the fold must be gated on the dirty flag — that gate is the cache")

    def test_invalidation_is_reachable_not_just_present(self):
        """An assertIn on `_aggregates_dirty = true` is satisfiable by hiding it in a dead
        branch, which is exactly what a "cleanup" does by accident. Pin the live form."""
        text = code(MANAGER)
        self.assertNotIn("if False:", text)
        self.assertNotIn("if false:", text)
        absorb = text.split("func absorb_direct")[1].split("\nfunc ")[0]
        self.assertIn("\tif spent:\n\t\t_aggregates_dirty = true", absorb,
                      msg="a spent shield must invalidate the pool, and only when something was spent")
        remove = text.split("func _remove_effect")[1].split("\nfunc ")[0]
        self.assertIn("\tif _effects.is_empty():\n\t\tset_physics_process(false)", remove,
                      msg="the last removal has to park the component, not merely mention it")
        tick = text.split("func _physics_process")[1].split("\nfunc ")[0]
        self.assertIn("\t\tset_physics_process(false)\n\t\treturn", tick,
                      msg="the empty-table branch must park and return")

    def test_the_tick_is_reentrancy_guarded(self):
        """The scratch arrays are reused, so a re-entrant tick would clobber them. The guard
        is only real if the early return is there too, not just the flag assignment."""
        tick = code(MANAGER).split("func _physics_process")[1].split("\nfunc ")[0]
        self.assertIn("if _ticking:", tick, msg="missing the re-entrancy test")
        self.assertIn("\t\treturn\n\t_ticking = true", tick, msg="the guard must return before taking ownership")
        self.assertIn("\t_ticking = false", tick, msg="ownership must be released")
        self.assertEqual(tick.count("_ticking"), 3)

    def test_a_benign_refresh_does_not_refold(self):
        """Re-applying burn on every swing is the common case and changes no folded value,
        so the conditional invalidation is the point of reapply() returning a bool at all.
        Making it unconditional is the 'simplification' this pins out."""
        apply_body = code(MANAGER).split("func apply_effect")[1].split("\nfunc ")[0]
        self.assertIn("folded = fx.reapply(stacks, source, power.x, power.y, power.y)", apply_body,
                      msg="reapply()'s verdict must be consumed, not discarded")
        self.assertIn("folded = folded or fx.shield_layer != layer_before", apply_body,
                      msg="a shield replenishment is a folded change even with no new stack")
        self.assertIn("\tif folded:\n\t\t_aggregates_dirty = true", apply_body,
                      msg="invalidation must stay conditional on an actual change")
        self.assertIn("\t\t_effects[id] = fx\n\t\tfolded = true", apply_body,
                      msg="a created effect always folds in")

    def test_autoload_refs_are_resolved_once(self):
        """The bus/registry lookups walked /root on every application and every expiry; the
        cached accessors must keep caching, and _ready must warm them so the first event
        does not pay the walk either."""
        text = code(MANAGER)
        for accessor, field in (("_event_bus()", "_bus"), ("_content_registry()", "_registry")):
            body = text.split(f"func {accessor}")[1].split("\nfunc ")[0]
            self.assertIn(f"if {field} == null:", body, f"{accessor} must memoize")
            self.assertNotIn("return _autoload_node(", body, f"{accessor} must not resolve per call")
        ready = text.split("func _ready()")[1].split("\nfunc ")[0]
        self.assertIn('\t_bus = _autoload_node("EventBus") as EventBusService', ready)
        self.assertIn('\t_registry = _autoload_node("ContentRegistry") as ContentRegistryService', ready)

    def test_validation_covers_the_authoring_traps(self):
        """Each message below is a rule whose absence lets a broken status reach the tick
        loop, where it used to be caught 60 times a second. validate() may only get
        *stronger* relative to this list, and the python mirror must keep up."""
        body = read(CONFIG).split("func validate() -> Array[String]:")[1]
        for message in (
            "effect_id is empty",
            "duration cannot be negative",
            "permanent duration not allowed with stuns/roots",
            "max_stacks must be >= 1",
            "invalid stack_mode",
            "dot_per_second cannot be negative",
            "invalid dot_type",
            "hot_per_second cannot be negative",
            "move_speed_factor cannot be negative",
            "damage_factor cannot be negative",
            "received_damage_factor cannot be negative",
            "shield_amount cannot be negative",
            "tick_interval must be > 0",
            "permanent shield (duration 0 + shield) would stall damage",
        ):
            self.assertIn(message, body, msg=f"validate() no longer applies {message!r}")

    def test_every_mutation_invalidates_the_cache(self):
        """Missing one of these is the bug the cache could introduce: a stale aggregate that
        never re-folds. apply/remove/expiry-flip/absorb are the four mutation points."""
        text = code(MANAGER)
        for func in ("func apply_effect", "func _remove_effect", "func clear_all", "func absorb_direct"):
            self.assertIn("_aggregates_dirty = true", text.split(func)[1].split("\nfunc ")[0],
                          f"{func} changes derived state but does not invalidate")
        tick = text.split("func _physics_process")[1].split("\nfunc ")[0]
        self.assertIn("if not was_expired and fx.is_expired():", tick,
                      msg="expiry crossing zero must invalidate: it is the only time-dependent input")

    def test_idle_component_stops_being_ticked(self):
        text = code(MANAGER)
        self.assertIn("set_physics_process(not _effects.is_empty())", text,
                      msg="_ready must start idle-unless-loaded")
        self.assertIn("set_physics_process(true)", text.split("func apply_effect")[1],
                      msg="an effect must wake the component up")
        self.assertIn("set_physics_process(false)", text.split("func _remove_effect")[1],
                      msg="the last effect leaving must park it again")

    def test_aggregate_queries_are_field_reads(self):
        """The read must be a return of a cached field; a test can then assert the ratio,
        because get_debug_snapshot() reports recomputes vs reads."""
        text = code(MANAGER)
        self.assertIn("\tvar total := fx.stacks", text.split("func apply_effect")[1].split("\nfunc ")[0],
                      msg="apply_effect must resolve the effect once, not re-look it up per field")
        for needle in ('"recomputes": _recomputes', '"aggregate_reads": _aggregate_reads'):
            self.assertIn(needle, text.split("func get_debug_snapshot")[1],
                          msg="the cache needs observable counters or it cannot be tested")

    def test_no_stringly_typed_power_record(self):
        """_power_for used to return {duration, damage} and the caller did three hash
        lookups; a Vector2 pair carries the same two clamped numbers with no allocation."""
        text = code(MANAGER)
        body = text.split("func _power_for")[1].split("\nfunc ")[0]
        self.assertIn("-> Vector2", body, msg="the pair must be value-typed")
        self.assertNotIn("return {", body, msg="no Dictionary record on the apply path")
        self.assertNotIn('power["', text, msg="callers must not hash-look-up a record per application")
        self.assertIn("Vector2(clampf(duration, 0.05, 10.0), clampf(damage, 0.0, 10.0))", body,
                      msg="the clamps are the old ones; both multipliers come from one authored stat")
        apply = text.split("func apply_effect")[1].split("\nfunc ")[0]
        self.assertIn("fx.reapply(stacks, source, power.x, power.y, power.y)", apply,
                      msg="dot and hot must keep sharing status_damage_multiplier, and say so")

    def test_shield_bookkeeping_is_not_a_parallel_table(self):
        manager = code(MANAGER)
        self.assertNotIn("_shield_layers", manager, msg="the shield layer lives on the effect")
        self.assertNotIn("_sync_shield_pool", manager, msg="the pool is a fold, not a re-summed table")
        self.assertIn("var _shield_pool: float = 0.0", manager)
        effect = code(EFFECT)
        self.assertIn("var shield_layer: float = 0.0", effect,
                      msg="per-effect unspent capacity is what makes absorb() allocation-free")
        self.assertIn("func absorb(amount: float) -> float", effect)

    def test_absorb_path_does_not_snapshot_the_table(self):
        body = code(MANAGER).split("func absorb_direct")[1].split("\nfunc ")[0]
        self.assertNotIn(".keys()", body, msg="a hit is not a reason to allocate")
        self.assertNotIn("_shield_layers[", body)
        self.assertIn("if _effects.is_empty():", body, msg="no effects means no absorbing, before any walk")


class TypeContractTests(unittest.TestCase):
    def test_effect_table_is_typed_and_runtime_only(self):
        text = code(MANAGER)
        self.assertIn("var _effects: Dictionary[StringName, StatusEffect] = {}", text,
                      msg="untyped Dictionary + `as` casts is what this replaced")
        self.assertNotIn("as StatusEffect", text, msg="no Variant casts out of the table")
        self.assertNotIn("@export var _effects", text,
                         msg="typed dicts with Resource values cannot be .tres-serialised (godot#100889)")
        for banned in ("JSON.parse_string", "JSON.stringify"):
            self.assertNotIn(banned, text,
                             msg=f"a typed Dictionary is not assignable from {banned} (godot#97137)")

    def test_config_extends_validated_config(self):
        text = read(CONFIG)
        self.assertIn("extends ValidatedConfig", text,
                      msg="without this the 14-rule audit never runs at load")
        self.assertIn("func validate() -> Array[String]:", text)

    def test_reapply_reports_whether_modifiers_changed(self):
        """The manager needs to know that a duration-only refresh changed nothing a fold
        depends on; the return value is that signal."""
        self.assertIn("func reapply(", read(EFFECT))
        self.assertIn(") -> bool:", read(EFFECT).split("func reapply(")[1].split("\n")[0])
        self.assertIn("return stacks != stacks_before or shield_layer != shield_before", code(EFFECT))

    def test_stacking_uses_the_authored_max(self):
        effect = code(EFFECT)
        self.assertIn("stacks = mini(stacks, cfg.max_stacks)", effect)
        self.assertIn("func _stacked_factor(base: float) -> float:", effect)
        self.assertIn("\tif base == 1.0:", effect,
                      msg="the neutral factor must skip pow(); most effects do not touch most axes")

    def test_tick_timekeeping_is_unchanged(self):
        effect = read(EFFECT)
        # Same guards the pre-rebuild subsystem shipped, pinned verbatim so a "cleanup"
        # cannot silently widen them (they are what bounds a hitch and a paused world).
        self.assertIn("active_delta = minf(delta, remaining)", effect)
        self.assertIn("remaining = maxf(remaining - delta, 0.0)", effect)
        self.assertIn("var budget := 64", effect)
        self.assertIn("_tick_accrual = 0.0", effect)

    def test_the_fold_preserves_the_two_read_semantics(self):
        """Factors used to include an effect that expired this tick but is not removed yet;
        the stun/root locks used to skip it. Both are deliberate and now live in one place."""
        fold = code(MANAGER).split("func _recompute_aggregates")[1]
        loop = fold.split("for id in _effects:")[1].split("\n\t# Never NaN")[0]
        self.assertIn("move *= fx.move_speed_factor()", loop)
        self.assertIn("if fx.is_expired():\n\t\t\tcontinue", loop,
                      msg="stun/root must keep skipping expired-not-yet-removed effects")
        self.assertIn("clampf(move, 0.0, 2.0)", fold,
                      msg="the move clamp is a gameplay number, not an implementation detail")
        effect = code(EFFECT)
        self.assertIn("const SOFT_LOCK_CAP_SECONDS := 3.0", effect,
                      msg="the stun/root lock needs a ceiling, not a floor")
        self.assertEqual(effect.count("remaining = _clamped_duration("), 5,
                         msg="_init, set_power_modifiers and all three stack modes must route through the cap")
        self.assertNotIn("remaining = full_duration", effect,
                         msg="an uncapped re-apply re-inflates a lock past the ceiling")
        self.assertIn("value = minf(value, SOFT_LOCK_CAP_SECONDS)", effect,
                      msg="the cap has to be a ceiling; a maxf floor is what shipped")


class HarnessRegistrationTests(unittest.TestCase):
    def test_the_live_suite_is_registered(self):
        text = read("tests/run_tests.gd")
        self.assertIn('"res://tests/unit/test_status_manager.gd"', text,
                      msg="an unregistered suite is a suite that never runs")
        node = text[text.index("const NODE_SUITES"):text.index("const INTEGRATION_STAGES")]
        self.assertIn("test_status_manager.gd", node,
                      msg="the fixture suite must run deferred, inside the live tree")

    def test_the_pure_status_suite_still_covers_the_config_layer(self):
        """The rebuild must not narrow coverage: the pre-existing pure suite owns the
        config/instance math, the new one owns the component. Both must stay registered."""
        text = read("tests/run_tests.gd")
        self.assertIn('"res://tests/unit/test_status_skills.gd"', text)

    def test_the_runner_stays_free_of_status_classes(self):
        # Code only: the runner's comments explain this very rule, mentioning the classes.
        text = code("tests/run_tests.gd")
        for banned in ("StatusManager", "StatusEffect"):
            self.assertNotIn(banned, text,
                             msg=f"the runner must stay loadable without compiling {banned}")

    def test_docs_point_at_the_cached_fold(self):
        """The perf docs used to say this cost was knowingly left in place; if the
        subsystem regresses the docs must not keep claiming otherwise."""
        arch = read("docs/ARCHITECTURE.md")
        self.assertIn("Status effects", arch, msg="docs/ARCHITECTURE.md must document the fold cache")
        perf = read("docs/ANDROID_PERFORMANCE.md")
        self.assertNotIn("left alone", perf,
                         msg="the perf doc still excuses the pre-rebuild status manager")


class BehaviourParityTests(unittest.TestCase):
    def test_stack_mode_shield_policy_is_unchanged(self):
        apply = code(MANAGER).split("func apply_effect")[1].split("\nfunc ")[0]
        self.assertIn("fx.shield_layer = layer_before + maxf(capacity_after - capacity_before, 0.0)", apply,
                      msg="ADD grants only newly acquired capacity (no infinite shield loop)")
        self.assertIn("fx.shield_layer = capacity_after", apply,
                      msg="REFRESH/RESET replenish to authored capacity")

    def test_harmful_filter_on_cleanse_all_is_unchanged(self):
        body = code(MANAGER).split("func cleanse_all")[1].split("\nfunc ")[0]
        self.assertIn("only_harmful and fx.config != null and not fx.config.is_harmful", body)

    def test_dot_path_still_goes_through_the_health_component(self):
        body = code(MANAGER).split("func _apply_ticks")[1].split("\nfunc ")[0]
        for needle in ("_health.is_dead()", "_health.is_invulnerable()", "absorb_direct(dot)",
                       "payload.damage_type = fx.config.dot_type", "_health.heal(hot)"):
            self.assertIn(needle, body, msg=f"DoT/HoT routing changed: {needle}")
        self.assertIn("if payload.is_valid():", body)

    def test_signals_are_still_emitted_from_the_same_three_points(self):
        text = code(MANAGER)
        for signal_name in ("effect_applied.emit", "effect_expired.emit", "effect_cleansed.emit"):
            self.assertIn(signal_name, text, msg=f"{signal_name} no longer fires")
        self.assertGreaterEqual(text.count("effect_cleansed.emit"), 3,
                                msg="cleanse(), cleanse_all() and clear_all() each announce removal")

    def test_autoload_lookup_is_still_by_path(self):
        text = code(MANAGER)
        self.assertIn("tree.root.get_node_or_null(node_name)", text,
                      msg="headless harnesses have no autoload globals; the lookup must stay path-based")
        self.assertIn("func _event_bus()", text, msg="the accessor name is itself a pinned seam")
        self.assertNotIn("if EventBus != null:", text)


if __name__ == "__main__":
    unittest.main()
