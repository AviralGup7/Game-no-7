"""Regression: a run's rules and its voice are authored data, not a code table.

Why these pins exist
--------------------
`scripts/meta/game_mode.gd` carried `GameMode.CATALOG`: a Dictionary of Dictionaries, one per
shipped mode, inside the same script that ran them. Its own doc comment promised "Adding a mode is
data-only (plus optional wave helpers)", and `docs/EXTENDING.md`'s game-mode section told modders to
"append an entry to the dict in game_mode.gd" — a data change that required editing core code. Reading it
against its callers turned up:

* thirteen accessors of the shape `float(def(id).get("score_mult", 1.0))`, each with its own silent
  default. `upgrade_every` defaulted to 2 and `boss_interval` to 10, so a mode that omitted a key did
  not lack a rule, it got a number nobody wrote down; `wants_upgrade`'s `maxi(..., 1)` made "never
  offer an upgrade" unauthorisable.
* `def()`/`validated()` clamped any unknown mode id to Standard with no report. A save naming a
  deleted mode, or a misnamed folder, was indistinguishable from a Standard run — at Standard's
  payout, which is the one thing the mode layer exists to vary.
* three of the eleven keys were read by nobody: `unlock_prestige` (on all seven modes),
  `boss_interval` (all seven, superseded by the per-wave boss flags in `data/waves/`), and
  `narrator_id` — whose "defend/collect borrow Standard's intro" intent was unreachable because
  `Narrator.mode_intro()` is handed the mode id and `MODE_INTRO` already had its own entry for them.
* five modes' encounter content was `match` arms in the same file (`_boss_rush_queue`,
  `_survival_queue`, `_defend_queue`, `_collect_queue`, and a fifteen-arm `match wave_number` for
  the campaign), while the campaign's narration was a *second* int-keyed table in `narrator.gd`
  (`CAMPAIGN_BEATS`) keyed by the same wave numbers. Nothing checked the two arcs agreed: rename a
  beat or extend `max_waves` and the run announces a chapter nobody fights, or fights one nobody
  wrote.
* `ENEMY_BLURBS` in the same file: five of eight archetypes, read by no caller at all.
* `Prestige` kept its ladder as an int-keyed `TITLES` Dictionary with a `"Unproven"` default and an
  int-keyed `CHALLENGE_TIERS` Dictionary indexed by `min(floor(rank / 2), CHALLENGE_TIERS.size()-1)`
  — so a gap in the keys silently handed the top-rank player **tier 0**, the easiest run, at full
  price — and the challenge pool lived in `GameMode` as `CHALLENGE_MUTATOR_POOL`, its per-tier
  counts in `Prestige`, reconciled only by `mini(count, pool.size())`.

Now: a mode is `res://data/game_modes/<id>.tres` (`GameModeConfig`, plus inline `GameModeWavePlan`
rows that carry the wave's archetypes *and* its announced beat); the ladder is
`res://data/prestige/ladder.tres` (`PrestigeLadderConfig` with dense `ChallengeTier` /
`PrestigeUnlock` rows); the arena's three announcer lines are fields on `ArenaConfig`. Every
consumer API survived (`GameMode.spawn_queue`, `challenge_mutators`, `Prestige.title_for`, …) and
what the player reads did not move: the numbers below are the ones the code tables carried.

The point is not that the tables moved. It is that the weak shapes are pinned out — a Dictionary
record crossing a boundary, an id literal branched on in code, an authored field no reader
consumes, a code table that can drift from its partner file — and that they cannot come back
quietly. Every check here was verified to fail when the matching defect was re-introduced into a
scratch copy of the tree (see the mutation matrix in docs/HARDENING.md).
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

MODE_DIR = ROOT / "data" / "game_modes"
LADDER = ROOT / "data" / "prestige" / "ladder.tres"
ARENA_DIR = ROOT / "data" / "arenas"

MODE_GD = "scripts/meta/game_mode.gd"
MODE_CFG_GD = "scripts/meta/game_mode_config.gd"
PLAN_GD = "scripts/meta/game_mode_wave_plan.gd"
PRESTIGE_GD = "scripts/meta/prestige.gd"
LADDER_CFG_GD = "scripts/meta/prestige_ladder_config.gd"
TIER_GD = "scripts/meta/challenge_tier.gd"
UNLOCK_GD = "scripts/meta/prestige_unlock.gd"
NARRATOR_GD = "scripts/meta/narrator.gd"
ARENA_CFG_GD = "scripts/arena/arena_config.gd"
LOADER_GD = "scripts/core/content_loader.gd"
REGISTRY_GD = "scripts/core/content_registry.gd"
WAVE_GD = "scripts/waves/wave_manager.gd"
SETUP_GD = "scripts/ui/run_setup_panel.gd"
ARMORY_GD = "scripts/ui/armory_panel.gd"
SCORE_GD = "scripts/core/run_scorekeeper.gd"
OBJECTIVE_GD = "scripts/meta/objective_director.gd"
RUN_STATE_GD = "scripts/core/run_state.gd"
SAVE_SCHEMA_GD = "scripts/save/save_schema.gd"
SAVE_MANAGER_GD = "scripts/save/save_manager.gd"
GAME_ROOT_GD = "scripts/core/game_root.gd"
STAGES_GD = "tests/integration_stages.gd"

IDENTITY_FLOATS = {"1.0", "0.0"}

MODE_FIELDS = (
    "display_name", "blurb", "intro_line", "victory_line", "objective", "score_mult", "currency_mult",
    "max_waves", "target_seconds", "collect_target", "upgrade_every", "fixed_weapon",
    "forced_mutators", "scales_with_prestige", "prestige_mutator_pool", "wave_plans",
    "planner_wave_offset",
    "planner_wave_floor", "every_n_waves", "every_n_append",
)

## The seven modes exactly as `GameMode.CATALOG` + `Narrator.MODE_INTRO` + `CAMPAIGN_BEATS` +
## `announce_victory`'s match authored them. `rows` mirrors the five queue builders: the archetype
## lists the `match` arms returned, wave for wave.
SHIPPED: dict[str, dict[str, object]] = {
    "standard": {
        "display_name": "Standard",
        "blurb": "Endless waves. Kill everything. Climb the scoreboard.",
        "intro_line": "One arena. Endless pressure. Make every stand count.",
        "victory_line": "Victory. The stand holds.",
        "objective": "clear_waves", "score_mult": 1.0, "currency_mult": 1.0,
        "max_waves": 0, "target_seconds": 0.0, "collect_target": 0, "upgrade_every": 2,
        "fixed_weapon": "", "forced_mutators": [], "scales_with_prestige": False,
        "prestige_mutator_pool": [], "planner_wave_offset": 0, "planner_wave_floor": 1,
        "every_n_waves": 0, "every_n_append": [], "rows": {},
    },
    "boss_rush": {
        "display_name": "Boss Rush",
        "blurb": "Five Overseer duels. Short rests. No filler packs.",
        "intro_line": "No warm-up. Five Overseers. Prove you belong in the pantheon.",
        "victory_line": "The pantheon yields. Five crowns are yours.",
        "objective": "slay_bosses", "score_mult": 1.35, "currency_mult": 1.25,
        "max_waves": 5, "target_seconds": 0.0, "collect_target": 0, "upgrade_every": 1,
        "fixed_weapon": "", "forced_mutators": ["elite_surge"], "scales_with_prestige": False,
        "prestige_mutator_pool": [], "planner_wave_offset": 0, "planner_wave_floor": 1,
        "every_n_waves": 0, "every_n_append": [],
        # `mini(2 + wave, 6)` alternating basic/fast adds, a heavy from 3, ranged+dasher at 5.
        "rows": {
            1: ["warlord", "basic", "fast", "basic"],
            2: ["warlord", "basic", "fast", "basic", "fast"],
            3: ["warlord", "basic", "fast", "basic", "fast", "basic", "heavy"],
            4: ["warlord", "basic", "fast", "basic", "fast", "basic", "fast", "heavy"],
            5: ["warlord", "basic", "fast", "basic", "fast", "basic", "fast", "heavy",
                "ranged", "dasher"],
        },
    },
    "survival": {
        "display_name": "Survival",
        "blurb": "Endure five minutes of mounting pressure. Score ticks with time lived.",
        "intro_line": "Five minutes. Mounting waves. Outlast the arena itself.",
        "victory_line": "Five minutes. You outlasted the arena.",
        "objective": "survive_time", "score_mult": 1.15, "currency_mult": 1.1,
        "max_waves": 0, "target_seconds": 300.0, "collect_target": 0, "upgrade_every": 3,
        "fixed_weapon": "", "forced_mutators": [], "scales_with_prestige": False,
        "prestige_mutator_pool": [], "planner_wave_offset": 2, "planner_wave_floor": 3,
        "every_n_waves": 4, "every_n_append": ["heavy"], "rows": {},
    },
    "challenge": {
        "display_name": "Challenge Run",
        "blurb": "Fixed Pulse Carbine loadout, harsh mutators, clear the tier or die trying.",
        "intro_line": "Glass and fire. One rifle. Twelve waves. No excuses.",
        "victory_line": "Challenge complete. The glass did not break you.",
        "objective": "clear_waves", "score_mult": 1.5, "currency_mult": 1.4,
        "max_waves": 12, "target_seconds": 0.0, "collect_target": 0, "upgrade_every": 2,
        "fixed_weapon": "gladius", "forced_mutators": ["glass_cannon", "ember_winds"],
        "scales_with_prestige": True,
        "prestige_mutator_pool": ["glass_cannon", "ember_winds", "iron_hide", "volatile_mix",
                                  "elite_surge"],
        "planner_wave_offset": 0, "planner_wave_floor": 1, "every_n_waves": 0,
        "every_n_append": [], "rows": {},
    },
    "campaign": {
        "display_name": "Campaign: The Last Stand",
        "blurb": "Scripted encounters, lore beats, and a final Warlord reckoning.",
        "intro_line": "They sealed the gate. You are the last line. Hold the stand.",
        "victory_line": "The gate holds. The Last Stand is won \u2014 for now.",
        "objective": "clear_waves", "score_mult": 1.2, "currency_mult": 1.3,
        "max_waves": 15, "target_seconds": 0.0, "collect_target": 0, "upgrade_every": 1,
        "fixed_weapon": "", "forced_mutators": [], "scales_with_prestige": False,
        "prestige_mutator_pool": [], "planner_wave_offset": 2, "planner_wave_floor": 1,
        "every_n_waves": 0, "every_n_append": [],
        # Waves 11-13 carried no list in the old `match` (they fell through to the planner, offset
        # +2) but did carry a beat. An empty row is exactly that, and `spawn_queue` must not let the
        # row suppress the planner.
        "rows": {
            1: ["basic", "basic", "basic", "basic", "basic"],
            2: ["basic", "basic", "fast", "basic", "fast", "basic"],
            3: ["basic", "fast", "ranged", "basic", "fast", "ranged"],
            4: ["basic", "heavy", "fast", "basic", "dasher", "basic"],
            5: ["warlord", "basic", "basic", "fast"],
            6: ["fast", "fast", "ranged", "exploder", "basic", "basic", "dasher"],
            7: ["heavy", "ranged", "basic", "splitter", "fast", "basic", "ranged"],
            8: ["dasher", "exploder", "fast", "heavy", "basic", "ranged", "dasher"],
            9: ["splitter", "heavy", "ranged", "fast", "exploder", "basic", "dasher", "basic"],
            10: ["warlord", "fast", "fast", "ranged", "basic"],
            11: [],
            12: [],
            13: [],
            14: ["heavy", "heavy", "ranged", "dasher", "exploder", "splitter", "fast", "fast"],
            15: ["warlord", "warlord", "heavy", "ranged", "dasher", "basic", "basic"],
        },
        "beats": {
            1: ("Awakening", "The outer gate falls. Footsteps in the dark."),
            2: ("First Blood", "Scouts die easy. The real horde is still coming."),
            3: ("Archers", "Bolts from the gallery. Clear the backline."),
            4: ("The Charge", "Heavies and dashers. Break their momentum."),
            5: ("Warlord I", "A champion of the Pit steps forward. End him."),
            6: ("Aftershock", "The champion falls. The horde does not stop."),
            7: ("Split Spore", "Things that divide when cut. Choose your swings."),
            8: ("Powder Keg", "Exploders in the mix. Kite them into their own."),
            9: ("Gathering Storm", "Every archetype at once. Stay calm."),
            10: ("Warlord II", "A second champion. Stronger. Angrier."),
            11: ("Attrition", "The gate holds \u2014 barely. Buy time with steel."),
            12: ("Breach", "Walls crack. The arena itself is failing."),
            13: ("Last Reserves", "Whatever you have left, spend it now."),
            14: ("The Gauntlet", "No mercy pack. Survive the next minute."),
            15: ("Final Reckoning", "Two Warlords. One last stand. The gate depends on you."),
        },
    },
    "defend": {
        "display_name": "Hold the Line",
        "blurb": "Guard the beacon at the arena's heart. If it falls, the run ends \u2014 survive the "
                 "timer to win.",
        # The mode's own line from MODE_INTRO — the `narrator_id: &"standard"` field that meant it
        # should be Standard's was read by nobody, so the text the player heard is the text kept.
        "intro_line": "The beacon must not fall. Hold the centre \u2014 everything comes for the light.",
        "victory_line": "Victory. The stand holds.",
        "objective": "defend_point", "score_mult": 1.4, "currency_mult": 1.3,
        "max_waves": 0, "target_seconds": 240.0, "collect_target": 0, "upgrade_every": 3,
        "fixed_weapon": "", "forced_mutators": [], "scales_with_prestige": False,
        "prestige_mutator_pool": [], "planner_wave_offset": 1, "planner_wave_floor": 2,
        "every_n_waves": 3, "every_n_append": ["heavy"], "rows": {},
    },
    "collect": {
        "display_name": "Data Recovery",
        "blurb": "Disabled robots drop data. Collect enough before reinforcements arrive.",
        "intro_line": "Recover telemetry from disabled machines before the next security sweep.",
        "victory_line": "Victory. The stand holds.",
        "objective": "collect", "score_mult": 1.3, "currency_mult": 1.35,
        "max_waves": 0, "target_seconds": 0.0, "collect_target": 20, "upgrade_every": 3,
        "fixed_weapon": "", "forced_mutators": ["bounty_hunt"], "scales_with_prestige": False,
        "prestige_mutator_pool": [], "planner_wave_offset": 2, "planner_wave_floor": 3,
        "every_n_waves": 4, "every_n_append": ["ranged"], "rows": {},
    },
}

TITLES = ["Unproven", "Survivor", "Veteran", "Champion", "Warlord-Slayer", "Pit Legend",
          "Ashen Crown", "Frostbound", "Eternal Guard", "Mythic", "Last Stand"]

TIERS = [
    {"label": "Standard Challenge", "unlock_rank": 0, "score_mult": 1.5, "currency_mult": 1.4,
     "mutator_count": 2, "max_waves": 12},
    {"label": "Hard Challenge", "unlock_rank": 2, "score_mult": 1.8, "currency_mult": 1.55,
     "mutator_count": 3, "max_waves": 14},
    {"label": "Nightmare Challenge", "unlock_rank": 4, "score_mult": 2.2, "currency_mult": 1.7,
     "mutator_count": 3, "max_waves": 16},
    {"label": "Mythic Challenge", "unlock_rank": 6, "score_mult": 2.8, "currency_mult": 1.9,
     "mutator_count": 4, "max_waves": 18},
    {"label": "Last Stand Challenge", "unlock_rank": 8, "score_mult": 3.5, "currency_mult": 2.2,
     "mutator_count": 4, "max_waves": 20},
]

COSMETIC_RANKS = {"banner_survivor": 1, "trail_ember": 2, "title_champion": 3, "aura_legend": 5,
                 "trail_frost": 7, "banner_last_stand": 10}

ARENA_LORE = {
    "default_arena": ("Orbital Foundry remembers every stand. Yours begins now.",
                      "Blood has soaked these stones for generations.",
                      "The crowd wants a legend. Don't disappoint them."),
    "ember_crucible": ("The Crucible breathes fire. Vents erupt \u2014 use them, or burn.",
                       "Ash falls like snow. The floor itself is a weapon.",
                       "The forges below roar. Something ancient stirs in the heat."),
    "frost_hollow": ("Cold that bites bone. Ichor pools slow the unwary.",
                     "Frost claims the careless. Keep moving.",
                     "The Hollow freezes hope. Only will remains."),
}


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def lines_of(rel: str):
    return enumerate(read(rel).splitlines(), start=1)


def code(rel: str) -> str:
    """Source without comment lines: these files name the shapes they ban, so a token ban has to
    scan code, not documentation."""
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


def sub_blocks(path: pathlib.Path) -> list[dict[str, str]]:
    """Each [sub_resource] block as a field dict, in file order."""
    blocks: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("[sub_resource"):
            if current is not None:
                blocks.append(current)
            current = {}
            continue
        if line.startswith("[resource]"):
            if current is not None:
                blocks.append(current)
                current = None
            break
        if current is None or not line.strip():
            continue
        m = re.match(r"^([a-z_0-9]+) = (.*)$", line)
        if m:
            current[m.group(1)] = m.group(2)
    return blocks


_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "'": "'", "\\": "\\"}


def unescape(text: str) -> str:
    """Decode copy for source mirrors; production resources use literal UTF-8.

    Native 4.4.1 validation found that escaped high codepoints produce errors,
    contrary to the old ASCII-only rule. Escaped-backslash handling is still
    needed for fixtures and ordinary quoted text.
    """

    def one(m: re.Match) -> str:
        c = m.group(1)
        if c[0] in ("u", "U"):
            return chr(int(c[1:], 16))
        return _ESCAPES.get(c, c)

    return re.sub(r"\\(u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|.)", one, text)


def string_value(raw: str) -> str:
    """`&"basic"` and `"Boss Rush"` both reduce to their text, escapes and all."""
    return unescape(raw.strip().lstrip("&").strip('"'))


def id_list(raw: str) -> list[str]:
    """The elements of `Array[StringName]([&"a", &"b"])` in authored order; `[]` gives []."""
    return re.findall(r'&"([a-z_0-9]+)"', raw or "")


class Bans:
    """Source-scanning assertions. unittest's assertNotIn dumps the whole file into the failure text,
    which makes a 500-line script unreadable in CI, so every ban here reports at most the handful of
    lines that actually broke it."""

    def assertAbsent(self, rel: str, needles, why: str) -> None:
        hits = [f"{rel}:{n}: {line.strip()[:110]}" for n, line in lines_of(rel)
                for needle in needles if needle in line]
        self.assertEqual(hits, [], f"{why}\n" + "\n".join(hits[:8]))

    def assertNoWord(self, rel: str, words, why: str) -> None:
        """Whole-identifier scan: `score_mult` must not match `score_multiplier_for`."""
        pattern = re.compile(r"\b(%s)\b" % "|".join(re.escape(w) for w in words))
        hits = [f"{rel}:{n}: {line.strip()[:110]}" for n, line in lines_of(rel) if pattern.search(line)]
        self.assertEqual(hits, [], f"{why}\n" + "\n".join(hits[:8]))

    def assertNoCodeWord(self, rel: str, words, why: str) -> None:
        """Same, over comment-stripped source: prose about a deleted table is allowed to name it."""
        pattern = re.compile(r"\b(%s)\b" % "|".join(re.escape(w) for w in words))
        hits = [f"{rel}: {line.strip()[:110]}" for line in code(rel).splitlines() if pattern.search(line)]
        self.assertEqual(hits, [], f"{why}\n" + "\n".join(hits[:8]))


class AuthoredModeDataTests(Bans, unittest.TestCase):
    """The catalogue left the script and landed in res://data/game_modes/."""

    def test_the_folder_holds_exactly_the_shipped_modes(self):
        authored = sorted(p.stem for p in MODE_DIR.glob("*.tres"))
        self.assertEqual(authored, sorted(SHIPPED),
                         "the shipped mode set changed: update SHIPPED deliberately, never as a side effect")

    def test_every_mode_file_authors_its_id_as_its_stem(self):
        # `GameMode.MODE_*` are handles for callers; if a handle stops naming a file the mode is
        # unselectable while the const still compiles. The stems are the ids.
        for path in sorted(MODE_DIR.glob("*.tres")):
            fields = fields_of(path)
            self.assertEqual(fields.get("mode_id"), f'&"{path.stem}"',
                             f"{path.name}: the file stem is how a mode is looked up")
        handles = re.search(r"const MODES: Array\[StringName\] = \[(.*?)\]", read(MODE_GD), flags=re.S)
        self.assertIsNotNone(handles, "GameMode.MODES is gone, so the handle/folder check has no anchor")
        decls = dict(re.findall(r'const (MODE_[A-Z_]+) := &"([a-z_]+)"', read(MODE_GD)))
        named = [decls[name] for name in re.findall(r"(MODE_[A-Z_]+)", handles.group(1))]
        self.assertEqual(sorted(named), sorted(SHIPPED),
                         "a MODE_ handle no longer names a mode file (or a new file has no handle)")

    def test_every_shipped_mode_matches_the_values_the_code_table_carried(self):
        for mode_id, expected in SHIPPED.items():
            got = fields_of(MODE_DIR / f"{mode_id}.tres")
            for field in MODE_FIELDS:
                if field == "wave_plans":
                    continue  # the rows are the mode's content; asserted wave for wave below
                want = expected[field]
                raw = got.get(field)
                self.assertIsNotNone(raw, f"{mode_id}: {field} is no longer authored at all")
                if isinstance(want, str):
                    self.assertEqual(string_value(raw), want, f"{mode_id}.{field} changed")
                elif isinstance(want, bool):
                    self.assertEqual(raw.strip(), "true" if want else "false", f"{mode_id}.{field} changed")
                elif isinstance(want, (int, float)) and not isinstance(want, bool):
                    self.assertAlmostEqual(float(raw), float(want), places=4,
                                           msg=f"{mode_id}.{field} changed ({raw} != {want})")
                elif isinstance(want, list):
                    self.assertEqual(id_list(raw), want, f"{mode_id}.{field} changed ({raw})")

    def test_scripted_waves_are_the_rows_the_match_arms_returned(self):
        for mode_id, expected in SHIPPED.items():
            want_rows: dict = expected["rows"]
            # A mode with no script omits the array entirely, so "no rows" and "empty rows" cannot
            # disagree with each other in a file.
            authored_key = "wave_plans" in fields_of(MODE_DIR / f"{mode_id}.tres")
            self.assertEqual(authored_key, bool(want_rows),
                             f"{mode_id}: wave_plans authored {authored_key}, rows {bool(want_rows)}")
            blocks = sub_blocks(MODE_DIR / f"{mode_id}.tres")
            got_rows = {}
            for b in blocks:
                if "wave_number" not in b:
                    continue
                got_rows[int(b["wave_number"])] = id_list(b.get("archetypes", ""))
            self.assertEqual(got_rows, want_rows, f"{mode_id}: its scripted waves changed")

    def test_every_scripted_campaign_wave_is_announced_and_vice_versa(self):
        # The invariant `CAMPAIGN_BEATS` and `_campaign_queue` could never check: same waves, both
        # tables. A beat for an unspawning wave, or a wave with no beat, is now one row either way.
        beats: dict = SHIPPED["campaign"]["beats"]
        rows: dict = SHIPPED["campaign"]["rows"]
        self.assertEqual(sorted(beats), sorted(rows), "the campaign arc's beats and waves must be one list")
        blocks = sub_blocks(MODE_DIR / "campaign.tres")
        authored = {int(b["wave_number"]): (string_value(b.get("beat_title", '""')),
                                           string_value(b.get("beat_line", '""'))) for b in blocks}
        self.assertEqual(authored, beats, "campaign beats moved out of sync with their waves")
        cap = float(fields_of(MODE_DIR / "campaign.tres")["max_waves"])
        self.assertEqual(max(beats), cap,
                         "the campaign's last beat is not its last wave, so the arc ends mid-sentence")

    def test_no_mode_authors_a_field_no_reader_consumes(self):
        # The whole reason `unlock_prestige`, `boss_interval` and `narrator_id` survived: nobody looked.
        # Every @export on the config must be read by the mode layer (or by the config's own
        # non-validating helpers) — a validate() that checks a field is not a reader.
        selector = code(MODE_GD)
        config_body = read(MODE_CFG_GD).split("func validate()")[0]
        for field in exported_names(MODE_CFG_GD):
            if field == "mode_id":
                continue  # the lookup key
            read_in_selector = re.search(r"cfg\.%s\b" % field, selector)
            read_in_helper = re.search(r"\b%s\b" % field, config_body)
            self.assertTrue(read_in_selector or read_in_helper,
                            f"GameModeConfig.{field} is authored and never read — delete it or wire it")

    def test_the_objective_vocabulary_is_the_one_the_modes_use(self):
        consts = dict(re.findall(r'const (OBJECTIVE_[A-Z_]+) := &"([a-z_]+)"', read(MODE_CFG_GD)))
        self.assertEqual(len(consts), 5, "the objective vocabulary grew without the director/HUD agreeing")
        authored = {string_value(v) for v in
                    [fields_of(p).get("objective", '""') for p in MODE_DIR.glob("*.tres")]}
        self.assertTrue(authored <= set(consts.values()), f"a mode authors {authored - set(consts.values())}")
        # GameMode must alias the config's consts, not re-state the literals: two copies is how the
        # label match and the data could disagree.
        for name, literal in consts.items():
            self.assertIn(f"const {name} := GameModeConfig.{name}", read(MODE_GD),
                          f"GameMode.{name} stopped aliasing the config's constant")
            self.assertNotIn(f'const {name} := &"{literal}"', read(MODE_GD),
                             f"GameMode.{name} re-states the literal instead of aliasing it")


class AuthoredPrestigeLadderTests(Bans, unittest.TestCase):
    """The ladder is one validated file, so its sequences cannot have holes."""

    def test_the_ladder_is_one_file_with_the_shipped_curve(self):
        self.assertTrue(LADDER.exists(), "res://data/prestige/ladder.tres is gone")
        got = fields_of(LADDER)
        self.assertEqual(float(got["cost_base"]), 2000.0)
        self.assertEqual(float(got["max_rank"]), 10.0)
        self.assertAlmostEqual(float(got["score_bonus_per_rank"]), 0.08, places=6)
        self.assertAlmostEqual(float(got["currency_bonus_per_rank"]), 0.06, places=6)
        self.assertAlmostEqual(float(got["armory_completion_required"]), 0.6, places=6)

    def test_titles_are_dense_and_exactly_cover_the_ranks(self):
        raw = fields_of(LADDER)["titles"]
        titles = re.findall(r'"([^"]*)"', raw)
        self.assertEqual(titles, TITLES, "a rank's title changed (the summary, armory and HUD print these)")
        self.assertEqual(len(titles), int(float(fields_of(LADDER)["max_rank"])) + 1,
                         "TITLES must cover ranks 0..max_rank — the int-keyed Dictionary could not")

    def test_challenge_tiers_are_the_rungs_the_dictionary_held(self):
        blocks = [b for b in sub_blocks(LADDER) if "unlock_rank" in b and "mutator_count" in b]
        self.assertEqual(len(blocks), len(TIERS))
        for block, want in zip(blocks, TIERS):
            for field, value in want.items():
                raw = block.get(field)
                self.assertIsNotNone(raw, f"tier {want['label']}: {field} is no longer authored")
                if isinstance(value, str):
                    self.assertEqual(string_value(raw), value, f"{want['label']}.{field} changed")
                else:
                    self.assertAlmostEqual(float(raw), float(value), places=4,
                                           msg=f"{want['label']}.{field} changed ({raw} != {value})")
        ranks = [int(float(b["unlock_rank"])) for b in blocks]
        self.assertEqual(ranks, sorted(set(ranks)), "rungs must be strictly ordered and gapless")
        self.assertEqual(ranks[0], 0, "rank 0 must resolve a rung, or an unprestiged run has no tier")
        self.assertEqual(max(ranks), int(float(fields_of(LADDER)["max_rank"])) - 2,
                         "the top rung is unreachable at the ladder's own top rank")

    def test_the_ladder_never_weakens_a_run_as_rank_rises(self):
        for previous, tier in zip(TIERS, TIERS[1:]):
            for field in ("score_mult", "currency_mult", "mutator_count", "max_waves"):
                self.assertGreaterEqual(float(tier[field]), float(previous[field]),
                                        f"{tier['label']}.{field} is below the rung under it")

    def test_cosmetic_ranks_are_the_staircase_and_name_real_cosmetics(self):
        blocks = [b for b in sub_blocks(LADDER) if "cosmetic_id" in b]
        got = {string_value(b["cosmetic_id"]): int(float(b["unlock_rank"])) for b in blocks}
        self.assertEqual(got, COSMETIC_RANKS, "what a prestige rank awards changed")
        catalogue = read("scripts/meta/cosmetics.gd")
        for cid in got:
            self.assertIn(f'&"{cid}"', catalogue, f"{cid} is not a Cosmetics id the player can wear")
        known = [int(float(b["unlock_rank"])) for b in blocks]
        self.assertEqual(known, sorted(known), "PrestigeUnlock rows are walked in order by all_cosmetics_up_to")

    def test_no_per_rank_cosmetic_staircase_or_number_came_back(self):
        # The staircase's signature is a *literal* rank in the comparison (`if rank >= 5:`); reading
        # an authored row's rank is the shape that replaced it.
        stair = re.findall(r"rank >= \d", code(PRESTIGE_GD))
        self.assertEqual(stair, [], "the `if rank >= n` staircase is back; the rows are the data")
        # (The magnitude rule for this file is pinned once, in
        # `test_no_authored_magnitude_survives_in_the_selectors`, so the identity fallbacks are not
        # re-declared as an expected-count list here.)

    def test_the_challenge_escalation_protocol_is_closed_across_the_two_files(self):
        # The pool is on the mode and the counts are on the ladder; tier 0 must be the mode's own
        # opening row, or the setup card and the live run disagree. ContentLoader enforces it in the
        # engine; this enforces it on the shipped numbers so a rebalance cannot half-happen.
        challenge = fields_of(MODE_DIR / "challenge.tres")
        first = TIERS[0]
        for ladder_field, mode_field in (("score_mult", "score_mult"), ("currency_mult", "currency_mult")):
            self.assertAlmostEqual(float(first[ladder_field]), float(challenge[mode_field]), places=6,
                                   msg=f"tier 0 and the challenge mode disagree on {ladder_field}")
        self.assertEqual(int(float(challenge["max_waves"])), int(float(first["max_waves"])),
                         "tier 0's wave cap is not the challenge mode's max_waves")
        pool = id_list(challenge["prestige_mutator_pool"])
        self.assertEqual(len(id_list(challenge["forced_mutators"])), int(float(first["mutator_count"])),
                         "tier 0's mutator_count does not match the mode's tier-0 signature")
        self.assertEqual(pool[:int(float(first["mutator_count"]))], id_list(challenge["forced_mutators"]),
                         "forced_mutators is not the opening of the pool")
        for tier in TIERS:
            self.assertLessEqual(int(float(tier["mutator_count"])), len(pool),
                                 f"{tier['label']} wants more mutators than the mode pools")


class NoCodeTableTests(Bans, unittest.TestCase):
    """The shapes that made the tables untrustworthy are refused, not discouraged."""

    def test_the_mode_layer_hands_over_no_dictionary_records(self):
        # Not "no dict-index reads" but "no record-building": the CATALOG shape was a dict literal per
        # mode, and the bug class was every key being optional.
        for rel in (MODE_GD, PRESTIGE_GD, NARRATOR_GD):
            self.assertAbsent(rel, tuple(f'"{field}":' for field in MODE_FIELDS)
                               + ('"label":', '"mutators":', '"waves":', '"title":', '"line":',
                                  '"intro":', '"mid":', '"late":', '"name":'),
                              f"{rel} builds a record again: a mode, a tier and an arena are "
                              f"typed configs now, so every key is mandatory and typed")
        for gone in ("const CATALOG", "static func def(", "const CHALLENGE_MUTATOR_POOL",
                     "const CHALLENGE_TIERS", "const TITLES", "const ARENA_LORE", "const MODE_INTRO",
                     "const CAMPAIGN_BEATS", "const ENEMY_BLURBS", "const PRESTIGE_COST_BASE",
                     "const MAX_PRESTIGE", "const CHALLENGE_TIER_EVERY"):
            for rel in (MODE_GD, PRESTIGE_GD, NARRATOR_GD):
                self.assertNotIn(gone, code(rel), f"{gone} came back to {rel}")

    def test_nobody_branches_on_a_mode_id_in_code(self):
        # A `match`/comparison on a mode id is the special case that data cannot reach. Handles in
        # `game_mode.gd`'s const block are declarations, not branches, so the banned forms are the
        # comparison and the arm.
        needles = tuple(pat for mid in SHIPPED
                        for pat in (f'== &"{mid}"', f'!= &"{mid}"', f'&"{mid}":', f'in (&"{mid}"'))
        hits = []
        # `game_mode.gd`'s `const MODE_* := &"id"` lines are how a caller names a file; they are the
        # only place an id literal may appear. Skipping the whole file was the loophole a
        # `if mode_id == &"boss_rush"` walked straight through.
        handle = re.compile(r"^const\s+MODE_[A-Z_]+\s*:=")
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            rel = str(path.relative_to(ROOT))
            for n, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), start=1):
                if line.lstrip().startswith("#") or handle.match(line.lstrip()):
                    continue
                for needle in needles:
                    if needle in line:
                        hits.append(f"{rel}:{n}: {line.strip()[:100]}")
        self.assertEqual(hits, [], "a system branches on a mode id instead of on authored data\n"
                         + "\n".join(hits[:8]))

    def test_the_announcer_holds_no_tables_of_its_own(self):
        # `announce_wave` used to `if mode_id == GameMode.MODE_CAMPAIGN` and `ARENA_LORE.get(id,
        # ARENA_LORE[&"default_arena"])`; both are refused here so the file stays a reader. It is
        # *handed* arena, mode and archetype ids and reads them off the configs — that is the whole
        # difference from a table, and an id literal anywhere in this file undoes it.
        body = code(NARRATOR_GD)
        self.assertNotIn("default_arena", body, "the announcer is falling back to one arena's voice again")
        self.assertNotIn("GameMode.MODE_", body, "the announcer special-cases a mode again")
        self.assertNotIn("match mode_id", body, "the announcer keeps a per-mode table of its own")
        self.assertLessEqual(body.count("push_error"), 1, "the announcer became a policy layer")
        self.assertIn("GameMode.beat_for_wave(mode_id, wave_number)", body,
                      "beats are no longer asked of the mode that authors them")
        # The announcement's own kind/severity names are this file's vocabulary; an *id* it invents is
        # not. Everything else in `EventBus.announcement`'s signature is a StringName written here.
        wire = {"narrator", "campaign_beat", "victory", "info", "warning"}
        named = sorted({m.group(1) for m in re.finditer(r'&"([a-z_0-9]+)"', body)} - wire)
        self.assertEqual(named, [], f"the announcer names content it should be handed: {named}")

    def test_the_spawn_queue_is_one_rule_set_not_five_builders(self):
        body = code(MODE_GD).split("static func spawn_queue")[1].split("static func")[0]
        self.assertNotIn("match mode_id", body, "spawn_queue grew its per-mode arms back")
        self.assertNotIn("match wave_number", body, "a per-wave script came back into core code")
        for needle in ("plan_for_wave", "overrides_planner", "extended_queue_for_wave", "every_n_waves"):
            self.assertIn(needle, body, f"spawn_queue stopped honouring `{needle}`")
        # The planner is *asked*, never written into: the old builders appended to the array the
        # planner returned, which is fine only while nobody caches one.
        self.assertIn("out = WavePlanner.extended_queue_for_wave(asked, run_seed)", body,
                      "spawn_queue no longer takes the planner's fresh array as its own base")
        floats = re.findall(r"\d+\.\d+", body)
        self.assertEqual(floats, [], f"spawn_queue is authoring magnitudes: {floats}")

    def test_the_readers_hold_no_prose(self) -> None:
        """No string a player reads is spelled out in the resolver or the announcer.

        `GameMode.victory_line()` used to end in a literal, so a mode that wanted a different epitaph
        had to edit core code, and `Narrator` kept four such tables for as long as it existed. The
        shipped data carries every line — which is exactly why a mutation that puts one back has to
        fail something other than a mirror of the data file.
        """
        for rel in (MODE_GD, NARRATOR_GD, ARENA_CFG_GD):
            for match in re.finditer(r'return\s+"([^"\\\n]*)"', code(rel)):
                words = re.findall(r"[A-Za-z]{2,}", match.group(1))
                self.assertLess(len(words), 3,
                                f"{rel} is carrying player-facing copy: {match.group(1)!r}")

    def test_the_unresolved_id_is_reported_and_never_laundered(self):
        resolve = code(MODE_GD).split("static func resolve(")[1].split("static func")[0]
        self.assertIn("return null", resolve, "resolve() invents a definition for an unknown id again")
        definition = code(MODE_GD).split("static func definition(")[1].split("static func")[0]
        self.assertRegex(definition, r"push_error\(", "definition() clamps without saying so")
        validated = code(MODE_GD).split("static func validated(")[1]
        self.assertRegex(validated, r'push_error\("GameMode: unknown mode id',
                         "an unknown mode id is silently clamped again")

    def test_no_authored_magnitude_survives_in_the_selectors(self):
        # `float(def(id).get("score_mult", 1.0))` was the disease: a per-accessor default is a
        # number nobody authored. What stays legal is the identity element of the type (1.0 for a
        # multiplier, 0.0 for a target, "" for copy), reached only when the *shipped* file is
        # missing, which ContentRegistry already halts on. Any other float in these two files is a
        # balance value that moved back out of the data, exactly like 1.35 or 0.08 used to live.
        for rel in (MODE_GD, PRESTIGE_GD):
            src = code(rel)
            self.assertNotIn(".get(", src, f"{rel} reads a Dictionary with a default again")
            strays = sorted({f for f in re.findall(r"\d+\.\d+", src) if f not in IDENTITY_FLOATS})
            self.assertEqual(strays, [], f"{rel} is authoring magnitudes again: {strays}")


    def test_an_absent_cadence_is_a_rule_not_a_clamp(self) -> None:
        """`upgrade_every = 0` has to mean "never", because that is the only way to author it.

        The old accessor wrote `wave_number % maxi(upgrade_every(id), 1) == 0`: a clamp in place of a
        rule, which made every wave an upgrade wave for a mode that wanted none and made the field a
        lie. Nothing in the shipped data has a zero cadence, so no value test can catch this coming
        back — hence the shape is pinned here.
        """
        txt = read(MODE_GD)
        start = txt.index("static func wants_upgrade")
        body = txt[start:txt.index("\n\n\n", start)]
        self.assertIn("if every <= 0:", body)
        self.assertNotIn("maxi(", body)
        self.assertNotIn("maxf(", body)


class LoaderAndRegistryTests(Bans, unittest.TestCase):
    """Nothing is trusted to "somebody will notice": the references are checked at load."""

    def test_the_loader_registers_and_validates_both_tables(self):
        loader = code(LOADER_GD)
        self.assertIn('&"game_modes": {}', loader)
        self.assertIn('_load_typed(&"res://data/game_modes", &"game_modes", tables, errors)', loader)
        self.assertIn("Not a GameModeConfig", loader)
        self.assertIn("PrestigeLadderConfig", loader)
        self.assertIn('res://data/prestige/ladder.tres', read(LOADER_GD))
        for msg in ("no GameModeConfig resources under res://data/game_modes",
                    "forces unknown mutator", "pools unknown mutator",
                    "which is not an authored weapon", "spawns unknown archetype",
                    "appends unknown archetype", "wants %d mutators but mode",
                    "authors %d in forced_mutators", "Missing prestige ladder", "Not an ArenaConfig"):
            self.assertRegex(loader, r'errors\.append\("[^"]*' + re.escape(msg),
                             f"the loader no longer reports `{msg}` as an error")

    def test_the_registry_owns_the_tables(self):
        registry = read(REGISTRY_GD)
        self.assertIn("func get_game_mode(mode_id: StringName) -> GameModeConfig", registry)
        self.assertIn("func get_all_game_modes() -> Dictionary", registry)
        self.assertIn('func get_prestige_ladder() -> PrestigeLadderConfig', registry)
        self.assertIn('_game_modes = tables[&"game_modes"]', registry)
        self.assertIn("prestige ladder %s", registry, "the startup report stopped saying whether it loaded")

    def test_the_configs_validate_their_own_pairs(self):
        cfg = read(MODE_CFG_GD)
        for rule in ("is not one of", "needs collect_target", "needs a number of bosses",
                     "needs target_seconds", "is dead data under objective", "never fires under a",
                     "must be the opening of prestige_mutator_pool", "two wave plans",
                     "past the %d-wave cap", "is not a spice rule", "must be authored together",
                     "is never drawn", "nothing to escalate", "null row in wave_plans"):
            self.assertIn(rule, cfg, f"GameModeConfig stopped checking: {rule}")
        # Row-level rules live on the row type, which the config folds into its own problem list.
        for rule in ("spawns nothing and says nothing", "empty archetype_id",
                     "the announcer prints them together"):
            self.assertIn(rule, read(PLAN_GD), f"GameModeWavePlan stopped checking: {rule}")
        ladder = read(LADDER_CFG_GD)
        for rule in ("title_for clamps", "must unlock at rank 0", "pays less than",
                     "shorter or gentler", "past the ladder's top rank", "awarded by two ranks",
                     "out of rank order"):
            self.assertIn(rule, ladder, f"PrestigeLadderConfig stopped checking: {rule}")
        # The cosmetic id itself is checked by the row, which is the only place that knows the
        # catalogue it has to name.
        unlock = read(UNLOCK_GD)
        for rule in ("is not a Cosmetics id", "has no cosmetic_id"):
            self.assertIn(rule, unlock, f"PrestigeUnlock stopped checking: {rule}")
        self.assertIn("Cosmetics.is_known(cosmetic_id)", unlock,
                      "the row stopped resolving against the catalogue that wears it")

    def test_every_hazard_mode_overlay_names_a_shipped_mode(self):
        # Cross-folder reference the loader cannot make (hazard overlays are optional per mode), so
        # it is checked here: an overlay for a renamed mode silently stops applying pressure.
        modes = {p.stem for p in MODE_DIR.glob("*.tres")}
        for path in sorted((ROOT / "data" / "hazard_modes").glob("*.tres")):
            self.assertIn(string_value(fields_of(path)["mode_id"]), modes,
                          f"{path.name} overrides hazards for a mode nobody ships")

    def test_every_shipped_arena_authors_its_three_lines(self):
        for path in sorted(ARENA_DIR.glob("*.tres")):
            fields = fields_of(path)
            for i, field in enumerate(("lore_intro", "lore_mid", "lore_late")):
                raw = fields.get(field)
                self.assertIsNotNone(raw, f"{path.stem}: {field} is not authored")
                self.assertEqual(string_value(raw), ARENA_LORE[path.stem][i],
                                 f"{path.stem}.{field} changed (this is what the announcer reads)")
        self.assertEqual(sorted(p.stem for p in ARENA_DIR.glob("*.tres")), sorted(ARENA_LORE),
                         "an arena was added or removed; the lore mirror must move with it")


class ExportLiteralTypeTests(Bans, unittest.TestCase):
    """`@export var x: T = <literal>` — the literal's type has to match `T`.

    Godot 4.4 refuses `NodePath = &"Geometry/Floor"` (a StringName default) with
    `Parse Error: Cannot assign a value of type "StringName" as "NodePath"`, and that parse error
    cascades: the file is a dependency of `ArenaConfig`, which is a dependency of `Prestige`, and the
    headless run then reports failures in `test_nav_grid` and `test_meta_misc` several layers away
    from the one bad character. `gdparse` — the strongest local parser available here — accepts it,
    so the shape is pinned at the text level instead. It is stricter than the engine in one place:
    Godot lets a StringName feed a String field, and this repo declines, because an export's default
    is what the inspector shows and what a `.tres` writes back — the literal should read like the
    field it belongs to. The rule is deliberately one-directional: it
    only fires when the default *starts with a literal of a different family*, so a const expression
    or a constructor call is never guessed at.
    """

    LITERAL_FAMILIES = {
        "node_path": (re.compile(r'^\^"'), "a NodePath literal (^\"...\")"),
        "string_name": (re.compile(r'^&"'), 'a StringName literal (&"...")'),
        "string": (re.compile(r'^"'), 'a string literal ("...")'),
        "number": (re.compile(r"^[-+]?[0-9.]"), "a numeric literal"),
        "color": (re.compile(r"^Color\("), "a Color(...) constructor"),
        "vector": (re.compile(r"^Vector[23]i?\("), "a Vector constructor"),
        "bracket": (re.compile(r"^\["), "an array literal"),
        "brace": (re.compile(r"^\{"), "a dictionary literal"),
    }
    # Declared type -> the families a default may legitimately start with. Anything not listed here
    # (resource classes, `null`, enums, consts) is left alone.
    ALLOWED = {
        "NodePath": {"node_path", "string"},
        "StringName": {"string_name"},
        "String": {"string"},
        "Color": {"color"},
        "Vector2": {"vector"}, "Vector3": {"vector"},
        "Vector2i": {"vector"}, "Vector3i": {"vector"},
        "bool": {"number"},  # true/false are matched separately below
        "int": {"number"}, "float": {"number"},
        "PackedStringArray": {"bracket"}, "PackedFloat32Array": {"bracket"},
        "PackedInt32Array": {"bracket"},
    }

    def test_no_export_default_is_a_literal_of_the_wrong_type(self) -> None:
        pattern = re.compile(
            r"^@export[^\n]*?\bvar ([a-z_0-9]+):\s*([A-Za-z_0-9]+)(?:\[[^\]]*\])?\s*=\s*(\S.*?)\s*$"
        )
        hits: list[str] = []
        for path in sorted((ROOT / "scripts").rglob("*.gd")):
            rel = str(path.relative_to(ROOT))
            for n, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
                stripped = line.strip()
                if not stripped.startswith("@export") or stripped.lstrip("#").startswith("#"):
                    continue
                m = pattern.match(stripped)
                if not m:
                    continue
                name, declared, value = m.group(1), m.group(2), m.group(3)
                if declared not in self.ALLOWED:
                    continue
                if declared == "bool":
                    if not re.match(r"^(true|false)\b", value):
                        hits.append(f"{rel}:{n}: bool {name} = {value!r}")
                    continue
                if re.match(r"^(null|SELF|[A-Z][A-Z_0-9]+)\b", value):
                    continue  # null and ALL_CAPS constants are the compiler's business
                families = self.ALLOWED[declared]
                if any(rgx.match(value) for key, (rgx, _) in self.LITERAL_FAMILIES.items() if key not in families):
                    hits.append(f"{rel}:{n}: {declared} {name} = {value!r} "
                                f"(wants {', '.join(sorted(self.LITERAL_FAMILIES[k][1] for k in families))})")
        self.assertEqual(hits, [], "an @export default cannot be assigned to its declared type\n"
                         + "\n".join(hits[:8]))


class DocCountTests(Bans, unittest.TestCase):
    """`docs/HARDENING.md` closes with counts (files validated, guard needles, scripts hardened).

    Every architecture pass moves those numbers, and a doc that quietly keeps reporting an old one is
    the same failure as a doc that describes a table nobody reads any more — which is what started
    this phase. So the counts are re-derived from the tools that print them instead of trusted.
    """

    def _tool_output(self, *args: str) -> str:
        r = subprocess.run([sys.executable, *args], cwd=ROOT, capture_output=True, text=True, timeout=300)
        self.assertEqual(r.returncode, 0, f"{' '.join(args)} failed:\n{r.stdout[-800:]}{r.stderr[-800:]}")
        return r.stdout

    def test_hardening_counts_are_the_tools_own(self) -> None:
        doc = read("docs/HARDENING.md")
        scripts = len(list((ROOT / "scripts").rglob("*.gd")))
        historical = int(re.search(r"GDScripts under `scripts/`: (\d+)", doc)[1])
        self.assertGreaterEqual(scripts, historical, "historical hardening inventory must not lose coverage")
        guards = self._tool_output("tool/validate_guards.py")
        passed = re.search(r"Passed (\d+), Failed 0", guards)
        self.assertIsNotNone(passed, guards[-400:])
        self.assertIn(f"Guard needles: {passed.group(1)}", doc,
                      "the doc's guard-needle count drifted from validate_guards.py")
        resources = self._tool_output("tool/validate_resources.py")
        validated = re.search(r"Validated (\d+) files", resources)
        self.assertIsNotNone(validated, resources[-400:])
        self.assertIn(f"Validated files: {validated.group(1)}/{validated.group(1)}", doc,
                      "the doc's validated-file count drifted from validate_resources.py")

    def test_the_superseded_heading_stays_historical(self) -> None:
        # "139/139" is the sweep's own frozen number and `test_regress_sweep_fixes` pins it; the new
        # counts live beside it, so neither pass has to rewrite the other's history.
        doc = read("docs/HARDENING.md")
        self.assertIn("Coverage — 139/139 GDScripts hardened", doc)
        self.assertIn("The coverage count above is the sweep's own, frozen", doc)

class FirstOfKindTests(Bans, unittest.TestCase):
    """The one feature the other pass added to `Narrator`, kept and put on the data model.

    `run_analytics.gd` calls `Narrator.note_enemy_spawned()` for every spawn, and the announcement it
    makes is the archetype's `ENEMY_BLURBS` line — the table this pass deleted as unread. Refusing to
    take the feature would have broken that caller; keeping the table would have kept the shape this
    pass exists to remove. So the four functions are theirs and the copy is the enemy's: `data/enemies/
    <id>_enemy.tres` authors `blurb`, and an archetype that authors none (basic, fast, heavy) is never
    announced, which the old five-of-eight table expressed as a missing key.
    """

    SHIPPED_BLURBS = {'basic': 'Security Drone detected. Watch its attack telegraph.', 'fast': 'Interceptor detected. Watch its attack telegraph.', 'heavy': 'Bulwark Mech detected. Watch its attack telegraph.', 'ranged': 'Sentry Gunner detected. Watch its attack telegraph.', 'dasher': 'Dash Hound detected. Watch its attack telegraph.', 'splitter': 'Replication Unit detected. Watch its attack telegraph.', 'exploder': 'Volatile Drone detected. Watch its attack telegraph.', 'warlord': 'Overseer Prime detected. Watch its attack telegraph.'}
    ENEMY_DIR = "data/enemies"

    def test_the_feature_survives_on_the_announcer(self) -> None:
        body = code(NARRATOR_GD)
        self.assertIn("static var _seen_archetypes: Dictionary[StringName, bool] = {}", body)
        self.assertIn("static func reset_run() -> void:", body)
        self.assertIn("_seen_archetypes.clear()", body)
        self.assertIn("static func note_enemy_spawned(archetype_id: StringName) -> void:", body)
        self.assertIn("func announce_first_of_kind(archetype_id: StringName) -> void:", body)
        # one line per archetype per run, and an empty blurb is silence rather than an empty banner
        self.assertIn("if _seen_archetypes.has(archetype_id):", body)
        self.assertIn("if line.is_empty():", body)

    def test_the_copy_is_the_enemy_s(self) -> None:
        body = code(NARRATOR_GD)
        self.assertIn("return cfg.blurb if cfg != null else \"\"", body)
        self.assertIn('var registered: EnemyConfig = ContentRegistry.get_enemy(archetype_id)', body)
        self.assertIn('ResourceLoader.exists(path)', body,
                      "the blurb must resolve without a registry, like every other reader here")
        self.assertAbsent(NARRATOR_GD, ("const ENEMY_BLURBS", "match archetype_id", "&\"warlord\""),
                          "the announcer is a table of enemy copy again")
        self.assertIn('@export var blurb: String = ""', read("scripts/enemies/enemy_config.gd"))

    def test_the_shipped_blurbs_are_the_strings_the_other_pass_wrote(self) -> None:
        authored = {}
        for path in sorted((ROOT / self.ENEMY_DIR).glob("*.tres")):
            raw = fields_of(path).get("blurb")
            if raw is None:
                continue
            authored[path.stem.replace("_enemy", "")] = string_value(raw).replace("\\u2014", "\u2014")
        self.assertEqual(authored, self.SHIPPED_BLURBS,
                          "the first-of-kind copy moved: say so here as well as in the data")


    def test_a_half_built_registry_is_not_an_answer(self):
        # `ContentLoader` validates each file it has read *before* registering the table, so
        # `GameMode.is_known()` is asked mid-load with the autoload present and empty -- which is how
        # four shipped hazard overlays came to be reported as invalid content (a `push_error` in
        # `HazardModeLayout.validate()`) and the registry then asserted itself down, taking the whole
        # headless run with it. An empty registry means "not yet", and the folder cannot be half-loaded.
        for rel in (MODE_GD, "scripts/waves/wave_mutators.gd"):
            scan = read(rel)[read(rel).index("static func _all_configs()"):]
            self.assertIn("if not out.is_empty():", scan,
                          f"{rel} answered from a registry that had nothing in it yet")
            self.assertIn("if not _disk_configs.is_empty():", scan,
                          f"{rel} would cache an empty scan forever")


class ConsumerTests(Bans, unittest.TestCase):
    """The public API survived, and the consumers read fields instead of keys."""

    def test_wave_manager_still_asks_the_mode_for_its_rules(self):
        txt = code(WAVE_GD)
        self.assertIn("GameMode.spawn_queue(mode_id, wave_number, _seed)", txt)
        self.assertIn("GameMode.challenge_mutators(_run_mode(), _prestige_rank())", txt)
        self.assertIn("GameMode.is_victory_wave_for(_run_mode(), _current_wave, _prestige_rank())", txt)
        self.assertIn("GameMode.wants_upgrade(_run_mode(), _current_wave)", txt)
        self.assertIn("Narrator.announce_wave(mode_id, arena_id, wave_number)", txt)

    def test_scorekeeper_still_avoids_double_counting_a_scaling_mode(self):
        txt = code(SCORE_GD)
        self.assertIn("GameMode.score_multiplier_for(_run.mode_id, rank)", txt)
        self.assertIn("GameMode.currency_multiplier_for(_run.mode_id, rank)", txt)
        # Pinned per branch, not per file: the same guard gates score and currency, so a needle that
        # only asks "is this condition anywhere in the file" stays green when one of the two is
        # deleted and a prestige rank is counted twice.
        lines = txt.splitlines()
        for pay, flat in (("score", "Prestige.score_multiplier(rank)"),
                          ("currency", "Prestige.currency_multiplier(rank)")):
            award = next((i for i, l in enumerate(lines) if f"*= {flat}" in l), None)
            self.assertIsNotNone(award, f"RunScorekeeper no longer applies the flat {pay} bonus at all")
            window = "\n".join(lines[max(0, award - 3):award])
            self.assertIn(f"not GameMode.scales_with_prestige(_run.mode_id)", window,
                          f"a scaling run is being paid the flat {pay} bonus on top of its tier")

    def test_the_setup_panel_lists_authored_modes_and_never_invents_copy(self):
        txt = code(SETUP_GD)
        self.assertIn("GameMode.all_mode_ids()", txt)
        self.assertIn("GameMode.display_name(mode_id)", txt)
        self.assertIn("GameMode.blurb(mode_id)", txt)
        self.assertIn("arena.lore_intro", txt, "the panel went back to guessing from tags")
        self.assertAbsent(SETUP_GD, ('"Classic survival"',),
                          "the panel is inventing arena copy again")

    def test_the_armory_copies_come_from_the_ladder(self):
        txt = code(ARMORY_GD)
        self.assertIn("Prestige.score_bonus_per_rank() * 100.0", txt)
        self.assertIn("Prestige.currency_bonus_per_rank() * 100.0", txt)
        self.assertIn("Prestige.armory_completion_required()", txt)
        self.assertIn('"unavailable"', txt, "a missing ladder is not shown as unavailable")
        self.assertAbsent(ARMORY_GD, ('"+8%"', '"+6%"', '"ARMORY 60%"', '"ARMORY 60%+"'),
                          "the panel hard-codes a number the ladder owns")

    def test_save_paths_clamp_against_the_ladder_not_a_const(self):
        for rel in (SAVE_MANAGER_GD, SAVE_SCHEMA_GD, GAME_ROOT_GD):
            self.assertIn("Prestige.clamp_rank(", code(rel),
                          f"{rel} clamps prestige rank against a constant again (zeroing a save on a "
                          f"content-load failure is exactly what clamp_rank exists to avoid)")

    def test_the_run_state_default_is_still_standard(self):
        txt = code(RUN_STATE_GD)
        self.assertIn('var mode_id: StringName = &"standard"', txt)
        self.assertIn("GameMode", read(MODE_GD))

    def test_objective_director_reads_its_targets_from_the_mode(self):
        txt = code(OBJECTIVE_GD)
        self.assertIn("GameMode.objective(_mode_id)", txt)
        self.assertIn("GameMode.collect_target(_mode_id)", txt)
        self.assertIn("GameMode.target_seconds", read(OBJECTIVE_GD))


class LiveRunDefinitionStageTests(Bans, unittest.TestCase):
    """The integration stage that drives an authored mode through a live tree.

    Every other test in this file reads source text or mirrors a `.tres`. A green suite therefore
    still does not prove that `Narrator.announce_wave` emits the row's copy, or that a run's payout
    is the ladder's number — those only show up when a real SceneTree runs. That stage is
    `tests/integration_stages.gd::_run_run_definition_integration`, chained from the encounter stage
    (the runner boots EventBus only, so it also proves the disk fallbacks work with no registry),
    and it is easy to unhook or to hollow out without touching anything else. Hence these pins.
    """

    def test_the_stage_exists_and_is_reached(self) -> None:
        txt = read(STAGES_GD)
        self.assertIn("static func _run_run_definition_integration(_tree: SceneTree) -> Array", txt)
        # Chained, not merely defined: the runner only calls the combat and encounter stages, so a
        # stage nobody appends is a stage that reports zero cases.
        self.assertIn("results.append_array(_run_run_definition_integration(tree))", txt)

    def test_the_announcer_is_compared_to_the_file_not_to_a_copy_of_its_copy(self) -> None:
        txt = code(STAGES_GD)
        self.assertIn('load("res://data/game_modes/campaign.tres") as GameModeConfig', txt)
        self.assertIn("plan_for_wave(5)", txt)
        self.assertIn('load("res://data/game_modes/survival.tres") as GameModeConfig', txt)
        self.assertIn("String(survival.intro_line)", txt)
        # The prose itself must not be transcribed into the test: a hardcoded "Warlord I" would keep
        # passing after someone rewrote the row, which is the failure mode the whole phase is about.
        self.assertAbsent(STAGES_GD, ("Warlord I", "Awakening", "The outer gate falls"),
                          "the stage re-types the campaign copy instead of reading the file")

    def test_the_ladder_is_read_cold_and_the_payout_is_a_number_from_the_file(self) -> None:
        txt = code(STAGES_GD)
        # A cold `Prestige.ladder()` is the only way this harness exercises the content-folder path.
        self.assertIn("Prestige.forget_ladder()", txt)
        # The stage selects the rung through the ladder's own rule and checks the selection against the
        # rows, rather than naming `challenge_tiers[3]` for rank 8 — which is the assertion that was
        # wrong about the data (the rungs unlock at 0/2/4/6/8) and cost a CI round to find out.
        self.assertIn("ladder.tier_index_for_rank(8)", txt)
        self.assertIn("rung.unlock_rank <= 8", txt)
        self.assertIn("ladder.challenge_tiers[selected + 1].unlock_rank > 8", txt)
        self.assertIn("run.score == want_standard", txt)
        self.assertIn("GameMode.score_multiplier_for(GameMode.MODE_CHALLENGE, 8)", txt)
        self.assertIn("GameMode.score_multiplier_for(GameMode.MODE_STANDARD, 8), 1.0", txt)

    def test_the_stage_does_not_become_a_second_table(self) -> None:
        self.assertAbsent(STAGES_GD, ("const CAMPAIGN_BEATS", "const MODE_INTROS", '"score_mult":',
                                     '"intro_line":', "GameMode.def(", "CATALOG"),
                          "the live stage grew its own copy of the run's copy")

def exported_names(rel: str) -> list[str]:
    return [m.group(1) for m in re.finditer(r"^@export[^\n]*?\bvar ([a-z_0-9]+)", read(rel), flags=re.M)]


class DeadFieldTests(unittest.TestCase):
    """The fields this phase deleted must stay deleted, in data and in code."""

    def test_the_unread_keys_are_not_in_the_data(self):
        for path in sorted(MODE_DIR.glob("*.tres")):
            fields = fields_of(path)
            for dead in ("unlock_prestige", "narrator_id", "boss_interval", "status_stacks"):
                self.assertNotIn(dead, fields,
                                 f"{path.name} re-authors {dead}, which nothing reads (that is why it "
                                 f"was deleted, not renamed)")

    def test_the_accessors_that_only_existed_for_them_are_gone(self):
        for rel in (MODE_GD, MODE_CFG_GD):
            body = code(rel)
            for gone in ("static func boss_interval", "static func narrator_id",
                         "static func unlock_prestige"):
                self.assertNotIn(gone, body, f"{gone} came back in {rel}")
        # `enemy_blurb` was dead code while nothing read it. The first-of-kind pass that landed on
        # main is a caller (`run_analytics` → `note_enemy_spawned`), so the reader stays — but it reads
        # the enemy's authored field, and what must stay dead is the table it used to be.
        self.assertIn("static func enemy_blurb", code(NARRATOR_GD),
                      "the first-of-kind announcer lost its reader")
        self.assertNotIn("const ENEMY_BLURBS", code(NARRATOR_GD),
                         "the archetype copy is a Narrator table again")

    def test_the_dead_accessor_pattern_has_a_test_everywhere_it_was_found(self):
        # Every field on every new config is mirrored either by a SHIPPED value above or by an
        # accessor read pinned in ConsumerTests; a config field with neither is how this phase
        # started. This asserts the mirror is complete, not that each name is spelled right.
        mirrored = set(MODE_FIELDS) | {"mode_id"}
        self.assertEqual(set(exported_names(MODE_CFG_GD)), mirrored,
                         "GameModeConfig gained or lost a field; update SHIPPED and MODE_FIELDS together")
        self.assertEqual(set(exported_names(LADDER_CFG_GD)),
                         {"cost_base", "max_rank", "score_bonus_per_rank", "currency_bonus_per_rank",
                          "armory_completion_required", "titles", "challenge_tiers", "cosmetic_unlocks"},
                         "PrestigeLadderConfig gained or lost a field")
        self.assertEqual(set(exported_names(TIER_GD)),
                         {"label", "unlock_rank", "score_mult", "currency_mult", "mutator_count", "max_waves"},
                         "ChallengeTier gained or lost a field")
        self.assertEqual(set(exported_names(UNLOCK_GD)), {"unlock_rank", "cosmetic_id"},
                         "PrestigeUnlock gained a field nobody reads")
        self.assertEqual(set(exported_names(PLAN_GD)),
                         {"wave_number", "archetypes", "beat_title", "beat_line"},
                         "GameModeWavePlan gained or lost a field")
        for field in ("lore_intro", "lore_mid", "lore_late"):
            self.assertIn(f"@export_multiline var {field}", read(ARENA_CFG_GD),
                          f"ArenaConfig.{field} was the point of moving the announcer's table")


if __name__ == "__main__":
    unittest.main()
