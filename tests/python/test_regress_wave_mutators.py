"""Regression: wave mutators are authored data, and the wave's rules are one typed record.

Why these pins exist
--------------------
`scripts/waves/wave_mutators.gd` used to contain the seven shipped mutators as a
`match mutator_id` over hand-written Dictionaries, ending in a fall-through that
returned a *neutral* definition for any id it did not recognise. Selection, the
definition table, the fold, and three more Dictionary hand-offs
(`DifficultyDirector.next_wave_multipliers()`, `SpawnManager._difficulty` and
`SpawnManager._wave_mods`) agreed on a key vocabulary that nothing checked. The
result, found by grepping every key against every consumer before touching
anything:

* `set_wave_modifiers` copied four keys, so `currency_mult` (Bounty Hunt's entire
  "double currency" pitch) and `player_damage_mult` (Glass Cannon's "take +25%")
  were folded, clamped and then thrown away at the spawner boundary.
* `score_mult` was copied but read by nobody — six of seven mutators advertised
  richer kills on their banner line.
* `burn_tick` was read by nobody: Ember Winds was a banner and a signal, nothing else.
* the director's `score_mult`/`elite_bonus` (elite_bonus only via one fold in
  WaveManager) and the folded `severity` were read by nobody, so "dominating
  players get richer waves" was a comment, and every mutator shouted at one volume.
* `RunState.active_modifiers` was cleared, duplicated and serialized but never
  *written*, so every run summary in the game said "no mutators".

Now: a mutator is a validated `WaveMutatorConfig` in `res://data/mutators/`, the
fold's result is a typed `WaveModifiers` value object, `WaveMutators` only selects
and resolves, and each knob is read by exactly the consumer that can honour it.
A completely neutral mutator is refused at load, and an unknown id is reported —
never folded as "mild".

Like the hazard, status and arena suites, the point is not that numbers moved: the
weak shape is pinned out so it cannot come back quietly, and the shipped values are
mirrored so a "cleanup" that changes what a player sees must be a deliberate edit
here. Each check was verified to fail when the matching regression was injected
into a scratch copy of the repo.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

SELECTOR_GD = "scripts/waves/wave_mutators.gd"
CONFIG_GD = "scripts/waves/wave_mutator_config.gd"
RECORD_GD = "scripts/waves/wave_modifiers.gd"
SPAWN_GD = "scripts/enemies/spawn_manager.gd"
WAVE_GD = "scripts/waves/wave_manager.gd"
DIRECTOR_GD = "scripts/waves/difficulty_director.gd"
SCORE_GD = "scripts/core/run_scorekeeper.gd"
WEAPON_GD = "scripts/weapons/weapon_manager.gd"
RUN_STATE_GD = "scripts/core/run_state.gd"
LOADER_GD = "scripts/core/content_loader.gd"
REGISTRY_GD = "scripts/core/content_registry.gd"
DAILY_GD = "scripts/meta/daily_challenge.gd"
MODE_GD = "scripts/meta/game_mode.gd"
SAVE_SCHEMA_GD = "scripts/save/save_schema.gd"

MUTATOR_DIR = ROOT / "data" / "mutators"
STATUS_DIR = ROOT / "data" / "status"

# The seven shipped mutators, exactly as the deleted `match` table authored them, with the
# numbers the `.tres` files must keep carrying. Names and descriptions are player-facing copy:
# only Ember Winds' line was rewritten, because it advertised "burn builds faster" — a stacking
# rule the fold could never express (see HARDENING.md: no modifier layer).
SHIPPED: dict[str, dict[str, object]] = {
    "swift_horde": {
        "display_name": "Swift Horde",
        "description": "Enemies are 30% faster but 15% frailer.",
        "severity": "minor", "roll_order": 0, "min_wave": 1,
        "hp_mult": 0.85, "speed_mult": 1.3, "score_mult": 1.1,
    },
    "iron_hide": {
        "display_name": "Iron Hide",
        "description": "Enemies are much tougher but slower.",
        "severity": "major", "roll_order": 1, "min_wave": 1,
        "hp_mult": 1.6, "speed_mult": 0.85, "score_mult": 1.25,
    },
    "elite_surge": {
        "display_name": "Elite Surge",
        "description": "+20% elite chance. Rich kills.",
        "severity": "major", "roll_order": 2, "min_wave": 1,
        "score_mult": 1.2, "elite_bonus": 0.2,
    },
    "glass_cannon": {
        "display_name": "Glass Cannon",
        "description": "Everyone hits harder \u2014 including you. Enemies deal +40%, take +25%.",
        "severity": "major", "roll_order": 3, "min_wave": 6,
        "hp_mult": 0.8, "damage_mult": 1.4, "player_damage_mult": 1.25, "score_mult": 1.3,
    },
    "bounty_hunt": {
        "display_name": "Bounty Hunt",
        "description": "Double currency, tougher marks.",
        "severity": "minor", "roll_order": 4, "min_wave": 1,
        "hp_mult": 1.2, "damage_mult": 1.1, "currency_mult": 2.0, "elite_bonus": 0.05,
    },
    "volatile_mix": {
        "display_name": "Volatile Mix",
        "description": "35% of enemies explode on death.",
        "severity": "major", "roll_order": 5, "min_wave": 1,
        "speed_mult": 1.05, "score_mult": 1.15, "explode_chance": 0.35,
    },
    "ember_winds": {
        "display_name": "Ember Winds",
        "description": "Burning air: everything takes fire ticks.",
        "severity": "major", "roll_order": 6, "min_wave": 1,
        "score_mult": 1.2, "status_effect_id": "ember_air", "status_stacks": 1,
        "status_targets": "all",
    },
}

MULT_FIELDS = ("hp_mult", "damage_mult", "speed_mult", "score_mult", "currency_mult",
               "player_damage_mult")
CHANCE_FIELDS = ("elite_bonus", "explode_chance")
FOLD_FIELDS = MULT_FIELDS + CHANCE_FIELDS

# Who reads each folded field. The Dictionary shape could not express "this key is dead"; a
# table in a test can, and it fails the moment a reader is deleted.
READERS: dict[str, tuple[str, str]] = {
    "hp_mult": (SPAWN_GD, "enemy_scaling"),
    "damage_mult": (SPAWN_GD, "enemy_scaling"),
    "speed_mult": (SPAWN_GD, "enemy_scaling"),
    "score_mult": (SCORE_GD, "modifiers.score_mult"),
    "currency_mult": (SCORE_GD, "modifiers.currency_mult"),
    "player_damage_mult": (WEAPON_GD, "modifiers.player_damage_mult"),
    "elite_bonus": (SPAWN_GD, "_wave.elite_bonus"),
    "explode_chance": (SPAWN_GD, "_wave.explode_chance"),
    "count_bonus": (WAVE_GD, "_wave_mods.count_bonus"),
    "severity": (WAVE_GD, "_wave_mods.severity"),
    "status_effect": (SPAWN_GD, "_wave.status_effect"),
    "status_stacks": (SPAWN_GD, "_wave.status_stacks"),
    "status_targets_enemies": (SPAWN_GD, "status_targets_enemies"),
    "status_targets_player": (SPAWN_GD, "status_targets_player"),
    "mutator_ids": (RUN_STATE_GD, "modifiers.mutator_ids"),
}


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def lines_of(rel: str) -> list[str]:
    """Code lines (comments stripped) with their original 1-based numbers, for compact failures."""
    out = []
    for n, line in enumerate(read(rel).splitlines(), 1):
        if not line.lstrip().startswith("#"):
            out.append((n, line))
    return out


def code(rel: str) -> str:
    """Source without comment lines. These files name the designs they ban in prose, so a token
    ban has to scan code, not documentation."""
    return "\n".join(l for l in read(rel).splitlines() if not l.lstrip().startswith("#"))


def fields_of(path: pathlib.Path) -> dict[str, str]:
    """`key = value` pairs from a .tres [resource] block, verbatim strings."""
    out: dict[str, str] = {}
    inside = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("[resource]"):
            inside = True
            continue
        if not inside or not line.strip():
            continue
        m = re.match(r"^([a-z_0-9]+) = (.*)$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def number(raw: str) -> float:
    return float(raw)


def string_value(raw: str) -> str:
    """`&"minor"` and `"Swift Horde"` both reduce to their text."""
    return raw.strip().lstrip("&").strip('"')


def exported_names(rel: str) -> list[str]:
    return [m.group(1) for m in re.finditer(r"^@export[^\n]*?\bvar ([a-z_0-9]+)", read(rel), flags=re.M)]


class Bans:
    """Source-scanning assertions. unittest's assertNotIn dumps the whole file into the failure
    text, which makes a 500-line script unreadable in CI, so every ban here reports at most the
    handful of lines that actually broke it."""

    def assertAbsent(self, rel: str, needles: tuple[str, ...], why: str) -> None:
        hits = [f"{rel}:{n}: {line.strip()[:110]}" for n, line in lines_of(rel)
                for needle in needles if needle in line]
        self.assertEqual(hits, [], f"{why}\n" + "\n".join(hits[:8]))

    def assertNoWord(self, rel: str, words: tuple[str, ...], why: str) -> None:
        """Whole-identifier scan: `score_mult` must not match `score_multiplier_for`."""
        pattern = re.compile(r"\b(%s)\b" % "|".join(re.escape(w) for w in words))
        hits = [f"{rel}:{n}: {line.strip()[:110]}" for n, line in lines_of(rel) if pattern.search(line)]
        self.assertEqual(hits, [], f"{why}\n" + "\n".join(hits[:8]))


class AuthoredDataTests(Bans, unittest.TestCase):
    """The definitions left the script and landed in res://data/mutators/."""

    def test_the_folder_holds_exactly_the_shipped_mutators(self):
        authored = sorted(p.stem for p in MUTATOR_DIR.glob("*.tres"))
        self.assertEqual(authored, sorted(SHIPPED),
                         "the shipped mutator set changed: update SHIPPED deliberately, never as a side effect")

    def test_every_shipped_mutator_matches_the_numbers_it_used_to_have(self):
        for mid, expected in SHIPPED.items():
            got = fields_of(MUTATOR_DIR / f"{mid}.tres")
            self.assertEqual(got.get("mutator_id"), f'&"{mid}"', f"{mid}: the key must equal the file name")
            for field, value in expected.items():
                raw = got.get(field)
                self.assertIsNotNone(raw, f"{mid}: {field} is no longer authored")
                if isinstance(value, str):
                    self.assertEqual(string_value(raw), value, f"{mid}.{field} changed")
                elif isinstance(value, bool):
                    self.assertEqual(raw, "true" if value else "false", f"{mid}.{field} changed")
                elif isinstance(value, int):
                    self.assertEqual(int(number(raw)), value, f"{mid}.{field} changed")
                else:
                    self.assertAlmostEqual(number(raw), value, places=6, msg=f"{mid}.{field} changed")

    def test_what_is_not_authored_is_neutral_by_default(self):
        """Leaving `explode_chance` out must mean 0.0 and leaving `hp_mult` out must mean 1.0 —
        i.e. the *class* defaults are the neutral values. This is what lets a mutator author only
        the two knobs it twists, and it is why an un-listed key used to be indistinguishable from a
        typo'd one: the defaults were the only truth, so they have to be neutral."""
        src = code(CONFIG_GD)
        for field in MULT_FIELDS:
            self.assertRegex(src, rf"var {field}: float = 1\.0",
                             f"{field}'s default stopped being neutral, so an omitted knob is a value")
        for field in CHANCE_FIELDS:
            self.assertRegex(src, rf"var {field}: float = 0\.0", f"{field}'s default stopped being zero")
        for mid, expected in SHIPPED.items():
            got = set(fields_of(MUTATOR_DIR / f"{mid}.tres")) - {"script"}
            self.assertEqual(got, set(expected) | {"mutator_id"},
                             f"{mid} authors fields its definition never had (or lost one)")

    def test_every_authored_field_name_exists_on_the_config(self):
        names = set(exported_names(CONFIG_GD))
        for mid in SHIPPED:
            for field in fields_of(MUTATOR_DIR / f"{mid}.tres"):
                if field == "script":
                    continue
                self.assertIn(field, names,
                              f"{mid}.tres sets `{field}`, which WaveMutatorConfig does not declare "
                              "(a typo'd export is dropped silently by the loader)")

    def test_the_status_a_mutator_carries_exists_and_is_a_dot(self):
        ember = fields_of(STATUS_DIR / "ember_air.tres")
        self.assertEqual(ember.get("effect_id"), '&"ember_air"', "the mutator's status id is its own key")
        self.assertAlmostEqual(number(ember["dot_per_second"]), 1.5, places=6,
                               msg="1.5/s is the old `burn_tick`; the number is the mechanic")
        self.assertGreaterEqual(number(ember["tick_interval"]), 0.5,
                                msg="a sub-tick interval here would re-open the per-frame DoT argument")
        self.assertEqual(ember.get("is_harmful"), "true")

    def test_roll_order_is_unique_and_preserves_the_shipped_order(self):
        orders = {}
        for mid in SHIPPED:
            got = fields_of(MUTATOR_DIR / f"{mid}.tres")
            orders[int(number(got["roll_order"]))] = mid
        self.assertEqual(len(orders), len(SHIPPED), "two mutators claim the same roll_order")
        # The order is a contract, not cosmetics: DailyChallenge.mutators_for_stamp() pops
        # indices out of this list, so a reshuffle silently changes what "today's challenge" is.
        self.assertEqual([orders[i] for i in range(len(SHIPPED))], list(SHIPPED),
                         "the roll order diverged from the order the deleted ALL const used")
        selector = read(SELECTOR_GD)
        self.assertIn("ordered_ids", selector)
        self.assertIn("roll_order", selector)
        self.assertIn("ordered_ids().duplicate()", code(DAILY_GD),
                      "the daily challenge no longer draws from the authored roll order")


class NoCodeTableTests(Bans, unittest.TestCase):
    """The shapes that made the defects possible are gone, and cannot come back quietly."""

    def test_the_selector_holds_no_definitions_and_no_id_consts(self):
        src = code(SELECTOR_GD)
        self.assertNotIn("match mutator_id", src, "a per-id `match` is how mutators were defined")
        self.assertNotIn("definition(", src, "`definition()` returned a neutral Dictionary for unknown ids")
        self.assertNotIn("const ALL", src, "the id list came back; the pool is authored roll order")
        for mid in SHIPPED:
            self.assertNotIn(f'"{mid}"', src,
                             f"{SELECTOR_GD} special-cases {mid} again (the wave floor is `min_wave`)")
        for field in FOLD_FIELDS:
            self.assertNotIn(field, src,
                             "per-key fold arithmetic moved back into the selector instead of "
                             "iterating each config's FOLD rules")
        # Stronger than naming fields: the selector has no business containing a magnitude at
        # all. Every number a mutator carries is authored in data (the two integer constants here
        # are the roll cadence), so any float literal is a definition that came back.
        floats = re.findall(r"\d+\.\d+", src)
        self.assertEqual(floats, [],
                         f"wave_mutators.gd is authoring magnitudes again: {floats[:6]}")

    def test_the_selector_neutralises_nothing_it_cannot_resolve(self):
        src = code(SELECTOR_GD).split("static func resolve(")[1].split("static func")[0]
        self.assertIn("return null", src, "resolve() must report a miss, not invent a definition")
        self.assertNotIn("WaveModifiers.neutral()", src,
                         "a fallback record is the neutral-Dictionary bug wearing a typed hat")

    def test_no_mutator_definition_or_special_case_lives_in_scripts(self):
        # No mutator id may be special-cased in code: `GameMode` names the ids its modes force
        # (validated by ContentLoader's reference check), and nothing else needs to know one exists.
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            rel = str(path.relative_to(ROOT))
            if rel == MODE_GD or rel == "scripts/meta/prestige.gd":
                continue
            self.assertAbsent(rel, tuple(f'&"{mid}"' for mid in SHIPPED),
                              "a mutator id is special-cased in code again")

    def test_the_wave_multipliers_are_never_a_dictionary_record_in_a_consumer(self):
        # The shape that let five knobs go unread was a Dictionary of `hp_mult`-style keys crossing
        # a boundary. Several other systems use that vocabulary for their OWN scalars — boss phases
        # (`BossController`/`BossPhaseConfig`) and the run-wide mode/prestige multipliers
        # (`GameMode.CATALOG`, `Prestige.CHALLENGE_TIERS`, read by `score_multiplier_for`) — and
        # they are deliberately still Dictionaries, pinned by `test_regress_prestige_meta_teeth.py`
        # and out of this phase's scope. The distinction that matters is not the key name but whose
        # record it is: a *wave* rule is `WaveModifiers`'s field, and an exemption that stops being
        # used has to be deleted rather than left to rot.
        holders = set()
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            rel = str(path.relative_to(ROOT))
            text = code(rel)
            if any(f'"{field}":' in text for field in FOLD_FIELDS) or '"burn_tick":' in text:
                holders.add(rel)
        allowed = {CONFIG_GD, RECORD_GD, MODE_GD, "scripts/meta/prestige.gd",
                   "scripts/enemies/boss_controller.gd", "scripts/enemies/boss_phase_config.gd"}
        self.assertEqual(holders, allowed,
                         "the set of files allowed to hand-roll a multiplier Dictionary changed. A "
                         "*wave* rule belongs in a WaveModifiers field; if you genuinely added a "
                         "different subsystem, name it in `allowed` with the reason above")

    def test_the_stacking_rules_are_the_documented_ones(self):
        # `FOLD` is the designer's answer to "how do two of these combine", and the fold has no
        # opinion of its own — so the *rules* are pinned here, per field. Flipping one is a balance
        # decision, not a refactor: explode_chance ADDITIVE would let two "sometimes explodes"
        # mutators make an always-exploding horde, and MULTIPLY on elite_bonus would make a
        # second elite mutator *shrink* the first one's bonus.
        folded = re.search(r"const FOLD := \{(.*?)\n\}", code(CONFIG_GD), flags=re.S).group(1)
        rules = dict(re.findall(r'"([a-z_]+)":\s*(STACK_\w+)', folded))
        self.assertEqual(set(rules), set(FOLD_FIELDS), "FOLD no longer covers exactly the folded fields")
        for field in MULT_FIELDS:
            self.assertEqual(rules[field], "STACK_MULTIPLY", f"{field} stopped multiplying")
        self.assertEqual(rules["elite_bonus"], "STACK_ADD")
        self.assertEqual(rules["explode_chance"], "STACK_MAX")

    def test_the_target_helpers_are_exact_id_tests_not_substring_checks(self):
        # `"enemies" in "all"` is False in GDScript, because `in` on two strings is a substring
        # test: the accessor would have reported "targets nobody" for the shipped Ember Winds and
        # still validated clean. The bug is invisible to any test that only checks the happy path,
        # so it is pinned at the source.
        src = code(CONFIG_GD).split("func status_targets_enemies")[1].split("func is_neutral")[0]
        self.assertNotIn("in status_targets", src,
                        "a `TARGET in status_targets` substring check came back: use `==`")
        self.assertIn("== TARGET_ENEMIES", code(CONFIG_GD).split("func status_targets_enemies")[1])
        self.assertIn("TARGET_ALL", code(CONFIG_GD).split("func status_targets_enemies")[1],
                      "ALL must expand to enemies *and* player in both accessors")

    def test_the_volatile_draw_only_happens_when_the_wave_can_explode(self):
        # Determinism is about the RNG *order*, not just the seed: an unconditional `randf()` here
        # would shift every later draw in the spawn stream for a wave whose explode_chance is 0.
        self.assertIn("explode_chance > 0.0 and _rng.randf() < explode_chance", code(SPAWN_GD))

    def test_a_neutral_mutator_cannot_be_shipped(self):
        src = code(CONFIG_GD)
        self.assertIn("is_neutral()", src)
        self.assertRegex(src, r'problems\.append\("[^"]*completely neutral',
                         "the refusal that stops 'a banner line that does nothing' was removed (or "
                         "left as a message nobody appends)")
        self.assertIn("func is_neutral() -> bool", src)


class TypedHandoffTests(Bans, unittest.TestCase):
    """Every wave-scaling boundary is a `WaveModifiers`, with one documented Dictionary left."""

    def test_the_consumers_take_the_record_not_a_dictionary(self):
        # The director keeps one Dictionary — its debug snapshot, like every system's. What may
        # not come back is a *multiplier* record: `next_wave_multipliers()` returns the typed value
        # (asserted above) and no `hp_mult`-style key is spelled anywhere in the file.
        self.assertAbsent(DIRECTOR_GD, tuple(f'"{field}":' for field in FOLD_FIELDS),
                          "DifficultyDirector is describing wave multipliers as Dictionary keys "
                          "again; that is the hand-off whose `score_mult` and `count_bonus` no one read")
        self.assertIn("func set_wave_modifiers(mods: WaveModifiers) -> void", code(SPAWN_GD))
        self.assertIn("func get_wave_modifiers() -> WaveModifiers", code(SPAWN_GD))
        self.assertIn("func next_wave_multipliers() -> WaveModifiers", code(DIRECTOR_GD))
        self.assertIn("var modifiers: WaveModifiers", code(RUN_STATE_GD))

    def test_the_spawner_reads_nothing_by_string_key(self):
        self.assertAbsent(SPAWN_GD,
                          tuple(f'"{field}"' for field in FOLD_FIELDS + ("severity", "burn_tick"))
                          + ("var _difficulty", "_difficulty.get", "_difficulty[", "_wave_mods"),
                          "SpawnManager went back to pulling wave numbers out of a Dictionary, the "
                          "shape that let a key be missed with no error. `set_difficulty_scalars("
                          "Dictionary)` is allowed (the planner seam); the record it lands in is not.")

    def test_the_record_folds_without_naming_keys_in_the_callers(self):
        record = code(RECORD_GD)
        self.assertIn("cfg.FOLD.keys()", record,
                      "the fold must iterate each mutator's declared stacking rule, not a key list")
        self.assertIn("STACK_MULTIPLY", record)
        self.assertIn("STACK_ADD", record)
        self.assertIn("STACK_MAX", record)
        selector = code(SELECTOR_GD)
        self.assertIn("fold_mutator(cfg)", selector)

    def test_the_fold_order_is_plan_then_director_then_mutators_then_bounds(self):
        body = code(WAVE_GD).split("func _fold_modifiers(")[1].split("\nfunc ")[0]
        marks = [body.index(needle) for needle in
                 ("apply_plan_scalars", "fold_director", "fold_into")]
        self.assertEqual(marks, sorted(marks),
                          "the documented fold order changed; the spawner's multipliers depend on it")
        fold = code(SELECTOR_GD).split("static func fold_into(")[1].split("\nstatic func ")[0]
        self.assertIn("clamp_bounds()", fold,
                      "clamping moved out of the fold, so a consumer can read an unbounded value")

    def test_the_only_dictionary_left_is_the_planner_seam_and_it_is_documented(self):
        record = read(RECORD_GD)
        self.assertIn("func apply_plan_scalars(scalars: Dictionary) -> void", record)
        self.assertIn("WavePlanner.calculate_difficulty_scalars", record,
                      "the one remaining Dictionary hand-off must say where it comes from")
        self.assertIn('scalars.get("hp", 1.0)', code(RECORD_GD))
        self.assertIn("static func calculate_difficulty_scalars(wave_number: int) -> Dictionary",
                      code("scripts/waves/wave_planner.gd"),
                      "the planner's pinned scalar function changed shape; tests/unit/test_waves.gd "
                      "reads its keys and this seam is the only place the record absorbs them")
        self.assertNotIn('scalars.get("hp"', code(LOADER_GD) + code(SPAWN_GD))

    def test_a_broken_number_is_reported_before_it_is_bounded(self):
        # The clamp must not be a quiet repair: a NaN that lands on 1.0 with no message is the same
        # "unobservable wiring mistake" the Dictionary hand-offs had.
        body = code(RECORD_GD).split("func clamp_bounds()")[1].split("\nfunc ")[0]
        self.assertIn("push_error(", body, "clamp_bounds() repairs a non-finite value silently")
        self.assertIn("MULT_CEIL", body, "+INF must land on the ceiling, not on neutral")

    def test_debug_dictionary_is_a_snapshot_boundary_only(self):
        self.assertIn('snap["wave_mods"] = _wave.debug_dictionary()', code(SPAWN_GD))
        for rel in (WAVE_GD, SCORE_GD, WEAPON_GD, DIRECTOR_GD):
            self.assertNotIn("debug_dictionary()", code(rel),
                             f"{rel} folds gameplay numbers out of a debug Dictionary")


class EveryKnobHasAReaderTests(Bans, unittest.TestCase):
    """The gate that would have caught all five dead knobs."""

    def test_every_folded_field_is_read_by_the_consumer_that_can_honour_it(self):
        for field, (rel, needle) in READERS.items():
            self.assertIn(needle, code(rel),
                          f"`{field}` is no longer read in {rel} — it is a banner line again")

    def test_the_reads_are_on_the_path_the_player_experiences(self):
        # An accessor in the same file is not a reader: `score_mult` was "stored" for as long as
        # `set_wave_modifiers` copied it, and nothing called anything. So each of the three
        # late-joining consumers is pinned at the function that produces the number the player
        # sees, not merely somewhere in the file.
        for fn, call, rel in (
                ("_score_multiplier", "_wave_score_mult()", SCORE_GD),
                ("_currency_multiplier", "_wave_currency_mult()", SCORE_GD),
                ("_apply_derived_stats", "_wave_damage_mult()", WEAPON_GD)):
            body = code(rel).split(f"func {fn}(")[1].split("\nfunc ")[0]
            self.assertIn(call, body,
                          f"{rel}.{fn}() no longer folds the wave's number into what it returns")
            self.assertTrue(body.count(call) >= 1)

    def test_the_wave_seam_refreshes_weapon_stats(self):
        body = code(WEAPON_GD).split("func set_current_wave(")[1].split("\nfunc ")[0]
        self.assertIn("refresh_derived_stats()", body,
                      "`set_current_wave()` stopped propagating: Glass Cannon's player bonus would "
                      "then only land on the next upgrade pick")
        assign, call = body.index("_current_wave ="), body.index("refresh_derived_stats()")
        self.assertLess(assign, call, "the refresh must follow the wave number it is refreshing for")
        self.assertNotIn("return", body[:call], "an early return makes the refresh dead code")

    def test_every_config_field_is_either_folded_or_read(self):
        folded = re.search(r"const FOLD := \{(.*?)\}", code(CONFIG_GD), flags=re.S).group(1)
        presentation = {"mutator_id", "display_name", "description", "severity",
                        "roll_order", "min_wave", "status_effect_id", "status_stacks",
                        "status_targets"}
        for name in exported_names(CONFIG_GD):
            if name in presentation:
                self.assertNotIn(name, folded, f"{name} is presentation, it does not belong in FOLD")
                continue
            self.assertIn(f'"{name}":', folded,
                          f"{name} is an authored multiplier with no stacking rule: the fold would "
                          "skip it, which is exactly how currency_mult was lost")
        # ...and each presentation field must still be read by something: a consumer, or this
        # class's own accessor (`status_targets` is read by `status_targets_enemies()`, and the
        # helpers are what the fold calls). An inspector-only field with no accessor is dead data.
        own = code(CONFIG_GD).split("func validate()")[0]
        for name in presentation:
            accessor = re.search(rf"func \w+\([^)]*\) -> \w+:\n\t.*\b{name}\b", own)
            hits = [rel for rel in (SELECTOR_GD, SPAWN_GD, WAVE_GD, SCORE_GD, WEAPON_GD,
                                    RUN_STATE_GD, LOADER_GD, REGISTRY_GD, MODE_GD)
                    if re.search(rf"\b{re.escape(name)}\b", code(rel))]
            self.assertTrue(hits or accessor is not None,
                            f"{name} is authored but read by no script — delete it or wire it")

    def test_the_record_and_the_config_agree_on_which_fields_exist(self):
        folded = sorted(re.findall(r'"([a-z_]+)":', re.search(
            r"const FOLD := \{(.*?)\}", code(CONFIG_GD), flags=re.S).group(1)))
        record = sorted(re.findall(r'"([a-z_]+)"', re.search(
            r"const FOLD_FIELDS := \[(.*?)\]", code(RECORD_GD), flags=re.S).group(1)))
        self.assertEqual(folded, record,
                         "a field was added to one list and not the other; the fold would be partial")

    def test_multipliers_are_bounded_once_and_the_bounds_live_with_the_data(self):
        record = code(RECORD_GD)
        self.assertEqual(record.count("func clamp_bounds()"), 1,
                         "a second clamping routine means two opinions about the floor")
        config = code(CONFIG_GD)
        self.assertIn("const MULT_FLOOR := 0.01", config)
        self.assertIn("const ELITE_BONUS_MAX := 0.5", config)
        self.assertIn("const CHANCE_MAX := 1.0", config)
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            rel = str(path.relative_to(ROOT))
            if rel in (CONFIG_GD, RECORD_GD):
                continue
            self.assertNotIn("MULT_FLOOR", code(rel),
                             f"{rel} clamps wave multipliers itself instead of trusting the fold")

    def test_status_stamping_goes_through_the_status_manager(self):
        src = code(SPAWN_GD)
        self.assertIn("apply_effect(", src)
        self.assertIn("get_status_manager()", src)
        for banned in ("take_damage(", "deal_damage(", "DamagePayload.new"):
            self.assertNotIn(banned, src.split("func _stamp_wave_status")[1].split("\nfunc ")[0],
                            "a mutator must not get its own damage path; DoT is StatusManager's")


class SelectionDeterminismTests(Bans, unittest.TestCase):
    """What the roller promises, in the shape it has to keep."""

    def test_the_roll_stream_and_gates_are_unchanged(self):
        src = code(SELECTOR_GD)
        self.assertIn("RngService.STREAM_WAVES + wave * 7", src,
                      "the roll stream moved: every saved replay and daily stamp changes")
        self.assertIn("const MIN_ROLL_WAVE := 4", src)
        self.assertIn("wave >= 8", src)
        self.assertIn("wave >= cfg.min_wave", src,
                      "the pool stopped honouring each mutator's authored wave floor")
        self.assertIn("SPICE_WAVE_OFFSET", src)
        self.assertIn("pop_at(rng.randi_range(0, pool.size() - 1))", code(DAILY_GD))

    def test_resolve_keeps_its_signature_for_forced_and_authored_waves(self):
        src = code(SELECTOR_GD)
        self.assertIn("static func resolve_for_wave(declared: Array, wave: int, seed: int, "
                      "breather: bool, spice: bool) -> Array[StringName]", src)
        self.assertIn("break", src.split("spice")[2].split("static func display_name")[0]
                      if "spice" in src else "", "the spice pick must stop at the first distinct id")

    def test_wave_manager_still_owns_the_three_sources_of_a_forced_set(self):
        src = code(WAVE_GD)
        self.assertIn("WaveMutators.resolve_for_wave(declared, wave_number, _seed", src)
        self.assertIn("_forced_mutators.duplicate()", src)
        self.assertIn("GameMode.challenge_mutators(", src)
        self.assertIn("cfg.arena_modifier_ids.duplicate()", src)


class ContentValidationTests(Bans, unittest.TestCase):
    """The registry knows the table, and a stale reference is a startup error."""

    def test_the_loader_registers_and_validates_the_table(self):
        loader = code(LOADER_GD)
        self.assertIn('&"mutators": {}', loader)
        self.assertIn('_load_typed(&"res://data/mutators", &"mutators", tables, errors)', loader)
        self.assertIn("Not a WaveMutatorConfig", loader)
        # Each rule has to be an *appended error*, not a message that survived a "cleanup" of the
        # `errors.append(` around it: a reported-but-not-failing check is how the arena's stale-id
        # bug stayed invisible for so long.
        for msg in ("references unknown status", "both claim roll_order", "declares unknown mutator",
                    "forces unknown mutator", "challenge mutator pool references unknown mutator",
                    "no WaveMutatorConfig resources"):
            self.assertRegex(loader, r'errors\.append\("[^"]*' + re.escape(msg),
                             f"the loader no longer reports `{msg}` as an error")

    def test_the_registry_exposes_the_table(self):
        registry = code(REGISTRY_GD)
        self.assertIn("func get_wave_mutator(mutator_id: StringName) -> WaveMutatorConfig", registry)
        self.assertIn("func get_all_wave_mutators() -> Dictionary", registry)
        self.assertIn('_mutators = tables[&"mutators"]', registry)
        self.assertIn("%d mutators", read(REGISTRY_GD), "the startup report stopped counting them")

    def test_authored_references_in_the_repo_still_resolve(self):
        known = {p.stem for p in MUTATOR_DIR.glob("*.tres")}
        waves = re.findall(r'arena_modifier_ids = Array\[StringName\]\(\[(.*?)\]\)',
                           "\n".join(p.read_text(encoding="utf-8")
                                      for p in (ROOT / "data" / "waves").glob("*.tres")))
        declared = set()
        for blob in waves:
            declared.update(re.findall(r'&"([a-z_0-9]+)"', blob))
        self.assertTrue(declared, "no wave declares a mutator any more; the authored path is unpinned")
        self.assertEqual(declared - known, set(), "a wave .tres names a mutator nobody ships")
        pool = set(re.findall(r'&"([a-z_0-9]+)"', re.search(
            r"const CHALLENGE_MUTATOR_POOL[^\n]*\n\t(.*?)\n\]", code(MODE_GD), flags=re.S).group(1)))
        self.assertEqual(pool - known, set(), "the challenge pool names a mutator nobody ships")
        forced = set(re.findall(r'&"([a-z_0-9]+)"', re.search(
            r'"forced_mutators": \[(.*?)\]', code(MODE_GD), flags=re.S).group(1)))
        for mid in forced:
            self.assertIn(mid, known, f"game mode forces {mid}, which is not authored")


class RunStateAndSaveTests(Bans, unittest.TestCase):
    """Ids persist, multipliers do not."""

    def test_run_state_publishes_both_and_resets_together(self):
        src = code(RUN_STATE_GD)
        self.assertIn("func set_wave_modifiers(mods: WaveModifiers) -> void", src)
        self.assertIn("active_modifiers = modifiers.mutator_ids.duplicate()", src)
        self.assertIn("modifiers = WaveModifiers.neutral()", src,
                      "clear() stopped resetting the live record, so a new run inherits the last one")

    def test_multipliers_are_never_serialized_as_floats(self):
        schema = code(SAVE_SCHEMA_GD)
        for field in FOLD_FIELDS:
            self.assertNotIn(field, schema,
                             "the save started storing folded floats instead of the ids they came from")
        self.assertIn("_string_list", schema)

    def test_the_summary_reports_the_mutators_it_was_given(self):
        run = read(RUN_STATE_GD)
        self.assertIn('"active_modifiers": active_modifiers.duplicate()', run)
        # Both snapshot shapes carry the ids; neither carries a multiplier.
        self.assertNotIn("modifiers.debug_dictionary()", run)


class DocumentationTests(Bans, unittest.TestCase):
    def test_the_docs_describe_the_data_and_not_the_old_table(self):
        extending = read("docs/EXTENDING.md")
        for needle in ("data/mutators", "WaveMutatorConfig", "WaveMutators", "WaveModifiers",
                       "roll_order", "min_wave", "clamp_bounds", "status_effect_id"):
            self.assertTrue(needle in extending, f"EXTENDING.md no longer mentions {needle}")
        self.assertAbsent("docs/EXTENDING.md", ("apply_to_wave_mods", "definition(mutator_id)",
                         "`ALL`, `resolve_for_wave`"),
                         "EXTENDING still documents the deleted code table")
        arch = read("docs/ARCHITECTURE.md")
        for needle in ("Wave rules", "WaveModifiers", "data/mutators", "clamp_bounds",
                       "active_modifiers"):
            self.assertTrue(needle in arch, f"ARCHITECTURE.md no longer mentions {needle}")
        changelog = read("CHANGELOG.md")
        for needle in ("currency_mult", "player_damage_mult", "burn_tick", "active_modifiers"):
            self.assertTrue(needle in changelog,
                            f"the changelog has to name what actually started working ({needle})")

    def test_the_extension_doc_says_a_new_mutator_needs_no_code(self):
        extending = read("docs/EXTENDING.md").lower()
        self.assertTrue("add a mutator without touching code" in extending,
                        "the doc must tell a designer their new mutator is a .tres, not a PR")

    def test_hardening_no_longer_recommends_the_banned_pattern(self):
        hardening = read("docs/HARDENING.md")
        self.assertAbsent("docs/HARDENING.md", ("2. Add a `_validated_*` helper",),
                          "HARDENING told contributors to add the helper validate_guards.py "
                          "rejects; that advice has to be replaced, not left next to the new rules")
        self.assertTrue("A field must have a reader" in hardening,
                        "the rule this phase bought for the game belongs in HARDENING")


class RecordCompletenessTests(Bans, unittest.TestCase):
    """READERS is the whole point of the rebuild: it has to stay as wide as the record."""

    def test_every_folded_field_has_a_named_reader(self):
        for field in FOLD_FIELDS:
            self.assertIn(field, READERS, f"{field} has no pinned reader — check whether it is dead")

    def test_every_field_on_the_record_is_accounted_for(self):
        declared = set(re.findall(r"^var ([a-z_0-9]+)[:, ]", code(RECORD_GD), flags=re.M))
        accounted = set(READERS) | {"status_effect_id"}
        self.assertEqual(declared - accounted, set(),
                         "a field was added to WaveModifiers with no reader and no pin; that is "
                         "exactly how `burn_tick` shipped as a banner line")
        self.assertGreaterEqual(len(declared), 12, "the record got thinner than the system it replaces")

    def test_the_ui_shows_the_authored_promise(self):
        panel = code("scripts/ui/run_setup_panel.gd")
        self.assertIn("WaveMutators.description(id)", panel,
                      "`description` is authored copy; if no panel shows it, it is dead data")
        self.assertIn("_daily_info.tooltip_text", panel)
