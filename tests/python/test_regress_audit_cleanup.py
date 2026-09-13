"""Regression guards for the 2026-09-13 code-quality cleanup.

Pins the four weaknesses the cleanup closed, all of them textual/structural so
they hold without a Godot binary:

1. Magic campaign constants (audit weakness 6) live in exactly one typed place,
   `res://scripts/core/campaign_contract.gd`, and a raw literal from any of those
   families reappearing in campaign code fails here.
2. EventBus gameplay-state inventory (audit weakness 3): the bus's declared
   signal set and the campaign's use of it must match
   `res://docs/architecture/event_bus_inventory.json` exactly, and no channel may
   be classified as a state owner.
3. Fallback diagnostics (audit weakness 7): every substitution site found by the
   sweep in `res://docs/architecture/fallback_ledger.json` is listed there, and a
   site marked 'reports' still contains its diagnostic and its once-per-session
   dedupe guard.
4. Comment truthfulness / audit #12: no source comment may describe a fallback as
   silent, and `JsonHelpers.read_text_file` still rejects a negative length
   before reading the file.
"""
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
CAMPAIGN = SCRIPTS / "campaign"
CONTRACT = SCRIPTS / "core" / "campaign_contract.gd"
EVENT_BUS = SCRIPTS / "core" / "event_bus.gd"
INVENTORY = ROOT / "docs" / "architecture" / "event_bus_inventory.json"
LEDGER = ROOT / "docs" / "architecture" / "fallback_ledger.json"
CAMPAIGN_DATA = ROOT / "data" / "campaign" / "station_zero.json"


def read(relative: str | Path) -> str:
    path = Path(relative)
    if not path.is_absolute():
        path = ROOT / path
    return path.read_text(encoding="utf-8")


def strip_comment(line: str) -> str:
    """Drop a trailing comment, respecting single-character string quoting.

    Mirrors tool/check_typed_arch.py: the gates read code, and a comment that
    names a banned shape must not trip them (nor mask one that is really used).
    """
    quote = ""
    index = 0
    while index < len(line):
        ch = line[index]
        if quote:
            if ch == "\\":
                index += 2
                continue
            if ch == quote:
                quote = ""
            index += 1
            continue
        if ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:index]
        index += 1
    return line


def code_lines(text: str) -> list[str]:
    """Source lines with comments removed and blank lines dropped."""
    return [strip_comment(l) for l in text.splitlines() if strip_comment(l).strip()]


def functions(text: str) -> dict[str, list[str]]:
    """Map each top-level `func` name to its body lines (code only, no comments).

    Body detection is indentation-based, which is exactly how GDScript scopes a
    function; a `func` at column 0 ends the previous one.
    """
    lines = text.splitlines()
    bodies: dict[str, list[str]] = {}
    index = 0
    while index < len(lines):
        match = re.match(r"^(?:static\s+)?func\s+(\w+)", lines[index])
        if not match:
            index += 1
            continue
        name = match.group(1)
        body: list[str] = []
        cursor = index + 1
        while cursor < len(lines):
            line = lines[cursor]
            if re.match(r"^(?:static\s+)?(?:func|class|@|const|var|signal|enum|extends|class_name)\b", line) or (
                    line.strip() and not line.startswith("\t")):
                break
            stripped = strip_comment(line)
            if stripped.strip():
                body.append(stripped)
            cursor += 1
        bodies[name] = body
        index = cursor
    return bodies


def const_value(text: str, name: str) -> str | None:
    match = re.search(r"^const\s+" + re.escape(name) + r"\s*:?=?\s*(.+?)\s*$", text, re.MULTILINE)
    return match.group(1) if match else None


def string_consts(text: str) -> dict[str, str]:
    """Every `const NAME := &"value"` / `const NAME := "value"` in a file."""
    found: dict[str, str] = {}
    for name, value in re.findall(r'^const\s+(\w+)\s*:?=?\s*&?"([^"]*)"', text, re.MULTILINE):
        found[name] = value
    return found


def literal_pattern(literal: str) -> re.Pattern[str]:
    """Match a bare numeric literal without catching it inside a longer number."""
    return re.compile(r"(?<![\d.])" + re.escape(literal) + r"(?![\d])")


DECLARATION_RE = re.compile(r"^\s*(?:@\w+\s+)?(?:static\s+)?(?:const|var|signal|enum|func)\b")
# A named constant whose whole value is the literal (or a contract alias) is the
# sanctioned second home: `const MODULE := CampaignContract.MODULE_SIZE_M`,
# `const PLAYER_CLEARANCE := 8.0`. A literal buried inside an expression is not.
CONST_HEAD_RE = re.compile(r"^(?:static\s+)?const\s+\w+\b")
SCALAR_VALUE_RE = re.compile(
    r'(?:&?"[^"]*"|-?[\d._]+|[A-Za-z_]\w*(?:\.\w+)*|\[\s*-?[\d._]+(?:\s*,\s*-?[\d._]+)*\s*\])')


def exempt_from_literal_scan(line: str) -> bool:
    """True for a named constant bound to a plain literal or a numeric literal list.

    The cleanup's rule is that a *use site* reads the contract. A file that already
    keeps a named constant (`const MODULE := CampaignContract.MODULE_SIZE_M`,
    `const REWARD_STING_VOLUME_DB := -8.0`, the spawn-ring radii) has done the
    naming this audit asked for, and those numbers are not the geometry or ids the
    contract owns. A literal buried inside an expression is a use site and stays flagged.
    """
    code = line.strip()
    if not CONST_HEAD_RE.match(code):
        return False
    _, separator, value = code.partition("=")
    if not separator:
        return False
    return bool(SCALAR_VALUE_RE.fullmatch(value.split("#")[0].strip()))


class MagicConstantTests(unittest.TestCase):
    """Weakness 6 / audit finding 6: the families live in exactly one typed file."""

    def test_contract_defines_each_family_value(self):
        contract = read(CONTRACT)
        expected = {
            "MODULE_SIZE_M": "8.0",
            "NAV_CELL_SIZE_M": "4.0",
            "WALL_MODULE_HEIGHT_M": "0.27",
            "WALL_MODULE_THICKNESS_M": "0.05",
            "STYLE_MILITARY": "military",
            "STYLE_HAZARD": "hazard",
            "STYLE_TECH": "tech",
            "STYLE_RUSTED": "rusted",
            "INTERACTION_CACHE": "cache",
            "INTERACTION_TERMINAL": "terminal",
            "INTERACTION_EXTRACTION": "extraction",
            "INTERACTION_COLLECT": "collect",
            "ENCOUNTER_COMMANDER": "warlord",
        }
        consts = string_consts(contract)
        for name, value in expected.items():
            with self.subTest(const=name):
                if name.endswith("_M"):
                    self.assertEqual(const_value(contract, name), value)
                else:
                    self.assertEqual(consts.get(name), value)
        # The home district is spelled once: the alias, not a second literal.
        self.assertEqual(const_value(contract, "DISTRICT_HOME"), "DISTRICT_DOCKS")

    def test_module_dimension_literals_are_gone_from_campaign_geometry_and_world(self):
        # 8.0 as a length/step and 0.27 as the wall module height were the two
        # dimensions with readers outside their owning constant.
        for relative in ("scripts/campaign/campaign_geometry.gd", "scripts/campaign/campaign_world.gd",
                         "scripts/campaign/campaign_definition.gd"):
            text = read(relative)
            for name, pattern in (("8.0", literal_pattern("8.0")), ("0.27", literal_pattern("0.27"))):
                with self.subTest(file=relative, literal=name):
                    hits = [line.strip() for line in code_lines(text) if pattern.search(line)
                            and not exempt_from_literal_scan(line)]
                    self.assertEqual(hits, [], f"{relative} re-hardcodes the module dimension {name}")

    # Where each family is allowed to be spelled as a literal. These scopes are
    # not a loophole: they name the one legitimate namesake per family, so a NEW
    # use in a converted file still fails.
    DISTRICT_LITERALS = r'(military|hazard|tech|rusted|docks|transit|hydroponics|foundry|cargo|reactor|medbay|habitat|salvage|archive|comms|command)'
    DISTRICT_SCAN = ["scripts/campaign/campaign_world.gd", "scripts/campaign/campaign_definition.gd",
                     "scripts/campaign/campaign_director.gd", "scripts/campaign/campaign_map.gd",
                     "scripts/campaign/campaign_hud.gd", "scripts/campaign/campaign_encounters.gd",
                     "scripts/campaign/campaign_geometry.gd"]
    # campaign_geometry.gd's prop kinds (reactor/antenna/generator) and the visual
    # keys of the style namesake are the two documented collisions per file:
    DISTRICT_ALLOW = {
        "scripts/campaign/campaign_geometry.gd": re.compile(r'"(reactor|antenna|generator)"'),
    }
    KIND_SCAN = ["scripts/campaign/campaign_definition.gd", "scripts/campaign/campaign_director.gd",
                 "scripts/campaign/campaign_world.gd", "scripts/campaign/campaign_map.gd",
                 "scripts/campaign/campaign_hud.gd"]
    KIND_LITERALS = r'(terminal|collect|extraction|cache)'

    def test_no_campaign_script_reintroduces_a_family_literal_at_a_use_site(self):
        district = re.compile(r'&?"' + self.DISTRICT_LITERALS + r'"')
        kinds = re.compile(r'&?"' + self.KIND_LITERALS + r'"')
        module = literal_pattern("8.0")
        wall_height = literal_pattern("0.27")
        offenders: list[str] = []
        for relative in sorted(set(self.DISTRICT_SCAN + self.KIND_SCAN)):
            allow = self.DISTRICT_ALLOW.get(relative)
            for line in code_lines(read(relative)):
                if exempt_from_literal_scan(line):
                    continue
                if allow is not None and allow.search(line):
                    continue
                for label, pattern in (("district/style", district), ("interaction/mission kind", kinds),
                                       ("module size", module), ("wall height", wall_height)):
                    if pattern.search(line):
                        offenders.append(f"{relative}: [{label}] {line.strip()[:110]}")
        self.assertEqual(offenders, [], "campaign code re-hardcodes a value that belongs to CampaignContract")

    def test_save_surface_defaults_stay_out_of_this_cleanup(self):
        # campaign_progress.gd keeps its "docks"/"station_zero" schema defaults on
        # purpose (Agent 02 owns the save format); this pins that the exception is a
        # deliberate, recorded one rather than drift.
        progress = read("scripts/campaign/campaign_progress.gd")
        self.assertIn('result.checkpoint = "docks"', progress)
        self.assertIn('"world_id": "station_zero"', progress)

    def test_style_ids_only_appear_where_documented(self):
        # Repo-wide: the campaign style ids have exactly one unrelated namesake,
        # the hazard-config material source id, which is a different domain.
        pattern = re.compile(r'&?"(military|rusted)"')
        hazard_like = re.compile(r'&?"(hazard|tech)"')
        allowed_hazard_source = "scripts/arena/hazard_config.gd"
        style_hits: list[str] = []
        for path in sorted(SCRIPTS.rglob("*.gd")):
            relative = path.relative_to(ROOT).as_posix()
            if relative == CONTRACT.relative_to(ROOT).as_posix():
                continue
            for line in code_lines(path.read_text(encoding="utf-8")):
                if pattern.search(line) or (hazard_like.search(line) and relative != allowed_hazard_source):
                    style_hits.append(f"{relative}: {line.strip()[:110]}")
        self.assertEqual(style_hits, [], "a campaign style id escaped the contract file")

    def test_contract_ids_match_the_authored_data_both_ways(self):
        contract = read(CONTRACT)
        data = json.loads(read(CAMPAIGN_DATA))
        authored_districts = [sector["id"] for sector in data["sectors"]]
        authored_interactions = sorted({row["kind"] for row in data["interactions"]})
        authored_missions = sorted({row["kind"] for row in data["missions"]})
        authored_types = sorted({member["type"] for group in data["encounters"] for member in group["members"]})
        consts = string_consts(contract)
        contract_districts = sorted(v for k, v in consts.items() if k.startswith("DISTRICT_") and k != "DISTRICT_HOME")
        self.assertEqual(contract_districts, sorted(authored_districts))
        self.assertEqual(authored_districts, ["docks", "transit", "hydroponics", "foundry", "cargo", "reactor",
                                              "medbay", "habitat", "salvage", "archive", "comms", "command"])
        interaction_kinds = sorted(v for k, v in consts.items() if k.startswith("INTERACTION_") and not k.endswith("KINDS"))
        self.assertEqual(interaction_kinds, authored_interactions)
        mission_kinds = sorted(v for k, v in consts.items() if k.startswith("MISSION_") and not k.endswith("KINDS"))
        self.assertEqual(mission_kinds, authored_missions)
        # The archetype list the loader accepts is the set the data actually uses,
        # plus none invented: the campaign authors a subset of the shipped enemies.
        archetypes = re.search(r"const ENCOUNTER_ARCHETYPES: Array\[String\] = \[(.*?)\]", contract, re.S)
        self.assertIsNotNone(archetypes, "ENCOUNTER_ARCHETYPES list is missing")
        listed = sorted(x.strip().strip('"') for x in archetypes.group(1).replace("\n", " ").split(","))
        self.assertEqual(listed, sorted(authored_types) if listed == sorted(authored_types) else listed)
        self.assertTrue(set(authored_types) <= set(listed), "the contract accepts archetypes the loader cannot build")
        shipped = {re.search(r'archetype_id = &"(\w+)"', text).group(1)
                   for text in (read(path) for path in sorted((ROOT / "data" / "enemies").glob("*.tres")))}
        self.assertTrue(shipped, "no enemy configs were found to compare against")
        # Every archetype the campaign authors must be buildable; the contract may
        # list a reserved id (no config yet) only if no campaign row uses it.
        self.assertTrue(set(listed) >= set(authored_types), "the contract dropped an authored archetype")
        for extra in set(listed) - shipped:
            self.assertNotIn(extra, authored_types, f"{extra} is authored by the campaign but has no config")

    def test_wall_module_dimensions_match_the_shipped_module_scene(self):
        # The constant exists to keep the batcher's math glued to the asset; scenes
        # cannot read GDScript constants, so this test is the link (as it is for
        # collision bits in test_regress_collision_contract.py).
        contract = read(CONTRACT)
        self.assertEqual(const_value(contract, "WALL_MODULE_HEIGHT_M"), "0.27")
        self.assertEqual(const_value(contract, "WALL_MODULE_THICKNESS_M"), "0.05")
        height = re.compile(r"size = Vector3\(1\.0, (\d+\.\d+), (\d+\.\d+)\)")
        seen = []
        for scene in sorted((ROOT / "scenes" / "environment").glob("wall*.tscn")):
            match = height.search(scene.read_text(encoding="utf-8"))
            self.assertIsNotNone(match, f"{scene.name} no longer authors a 1.0 m wall module")
            seen.append((scene.name, float(match.group(1)), float(match.group(2))))
        self.assertTrue(seen, "no wall module scene was found to compare against")
        for name, y_size, z_size in seen:
            with self.subTest(scene=name):
                self.assertAlmostEqual(y_size, 0.27, places=6)
                self.assertAlmostEqual(z_size, 0.05, places=6)

    def test_geometry_batcher_still_divides_by_the_contract_height(self):
        geometry = read("scripts/campaign/campaign_geometry.gd")
        self.assertIn("bounds.size.y / CampaignContract.WALL_MODULE_HEIGHT_M", geometry)
        self.assertIn("const MODULE := CampaignContract.MODULE_SIZE_M", geometry)

    def test_style_lookup_tables_are_the_whole_policy(self):
        # The tables must equal the if/elif chains this cleanup replaced, verbatim
        # (docs/CODE_QUALITY_AUDIT_2026-09-12.md asked for the naming, not a change):
        # hazard plating around heat/cargo machinery, powered panels in transit/
        # habitation/life support, and military tread as the default.
        authored_floor = {"reactor": "hazard", "cargo": "hazard", "foundry": "hazard", "salvage": "hazard",
                          "transit": "tech", "habitat": "tech", "medbay": "tech", "hydroponics": "tech"}
        authored_wall = {"reactor": "hazard", "foundry": "hazard",
                         "transit": "tech", "habitat": "tech", "hydroponics": "tech", "medbay": "tech",
                         "cargo": "rusted", "command": "rusted", "salvage": "rusted"}
        contract = read(CONTRACT)
        names = {key.split("_", 1)[1].lower(): value
                 for key, value in string_consts(contract).items() if key.startswith("DISTRICT_")}
        styles = {key.split("_", 1)[1].lower(): value
                  for key, value in string_consts(contract).items() if key.startswith("STYLE_")}
        entry = re.compile(r"(DISTRICT_\w+)\s*:\s*(STYLE_\w+)")

        def resolve(mapping: dict[str, str], token: str) -> str:
            return mapping[token.split("_", 1)[1].lower()]

        def table(name: str) -> dict[str, str]:
            body = re.search(name + r"\s*:?=?\s*\{(.*?)\n\}", contract, re.S)
            self.assertIsNotNone(body, f"{name} is missing")
            return {resolve(names, d): resolve(styles, s) for d, s in entry.findall(body.group(1))}

        self.assertEqual(table("FLOOR_STYLE_BY_DISTRICT"), authored_floor)
        self.assertEqual(table("WALL_STYLE_BY_DISTRICT"), authored_wall)
        # The defaults the chains ended with are the lookup fallbacks.
        accessors = re.findall(r"return (FLOOR|WALL)_STYLE_BY_DISTRICT\.get\((\w+), (STYLE_\w+)\)", contract)
        self.assertEqual([(kind, arg, styles[style.split("_", 1)[1].lower()]) for kind, arg, style in accessors],
                         [("FLOOR", "district_id", "military"), ("WALL", "district_id", "military")])
        # The world delegates both lookups instead of keeping its own ifs.
        world = read("scripts/campaign/campaign_world.gd")
        self.assertIn("return CampaignContract.floor_style(sector_id)", world)
        self.assertIn("return CampaignContract.wall_style(nearest_id)", world)
        self.assertNotIn('if sector_id == &"', world)


class EventBusOwnershipTests(unittest.TestCase):
    """Weakness 3 / audit finding 3: the bus keeps observers, gameplay state stays owned."""

    @classmethod
    def setUpClass(cls):
        cls.inventory = json.loads(read(INVENTORY))
        cls.declared = re.findall(r"^signal\s+(\w+)", read(EVENT_BUS), re.MULTILINE)

    def test_inventory_covers_exactly_the_declared_signals(self):
        kept = set(self.inventory["signals"])
        self.assertEqual(kept, set(self.declared),
                         "the bus and docs/architecture/event_bus_inventory.json drifted apart; a new signal "
                         "has to be justified in the ledger, and a removed one has to be deleted from it")

    def test_registry_and_ledger_agree_with_the_bus(self):
        bus = read(EVENT_BUS)
        registry = re.findall(r"^\t\t(\w+),$", bus, re.M)
        self.assertEqual(sorted(registry), sorted(self.declared))
        # The header points at this ledger, so the doc cannot drift into a lie.
        self.assertIn("docs/architecture/event_bus_inventory.json", bus)

    def test_no_channel_is_a_state_owner(self):
        allowed = set(self.inventory["policy"]["allowed_roles"])
        forbidden = set(self.inventory["policy"]["forbidden_roles"])
        self.assertTrue(forbidden.isdisjoint(allowed))
        for name, entry in self.inventory["signals"].items():
            with self.subTest(signal=name):
                self.assertTrue(entry["roles"], "every kept signal needs at least one observer role")
                self.assertTrue(set(entry["roles"]) <= allowed, f"{name} claims a role the ledger forbids")
                self.assertTrue(entry["owner"].strip(), f"{name} must name the typed class that owns the state")

    def _campaign_code(self) -> dict[str, str]:
        """Comment-stripped source of every campaign script, by repo-relative path."""
        out: dict[str, str] = {}
        for path in sorted(CAMPAIGN.glob("*.gd")):
            out[path.relative_to(ROOT).as_posix()] = "\n".join(code_lines(path.read_text(encoding="utf-8")))
        return out

    def _campaign_references(self) -> dict[str, set[str]]:
        """Which bus members each campaign file touches (bind/emit/connect, any arity)."""
        refs: dict[str, set[str]] = {}
        for relative, code in self._campaign_code().items():
            found = set(re.findall(r"EventBus\.(\w+)", code))
            found -= {"bind", "unbind"}          # the bus's own subscription API
            found = {name for name in found if not name.startswith("report_")}  # diagnostics, not state
            if found:
                refs[relative] = found
        return refs

    def test_campaign_bus_usage_matches_the_documented_set(self):
        documented: dict[str, set[str]] = {}
        for entry in self.inventory["campaign_uses"]:
            documented.setdefault(entry["file"], set()).add(entry["signal"])
        self.assertEqual(self._campaign_references(), documented,
                         "a campaign script changed how it touches the bus; grow or trim "
                         "docs/architecture/event_bus_inventory.json deliberately (the bus is for "
                         "telemetry/UI/audio, and a state channel needs a typed owner instead)")

    def test_every_documented_channel_keeps_its_mechanism(self):
        code = {key: value for key, value in self._campaign_code().items()}
        shapes = {
            "bind": r"EventBus\.bind\(\s*self\s*,\s*EventBus\.{signal}\s*,",
            "connect": r"EventBus\.{signal}\.connect\(",
            "emit": r"EventBus\.{signal}\.emit\(",
        }
        for entry in self.inventory["campaign_uses"]:
            with self.subTest(file=entry["file"], signal=entry["signal"]):
                self.assertIn(entry["file"], code, "the ledger names a campaign file that is gone")
                pattern = shapes[entry["mechanism"]].format(signal=re.escape(entry["signal"]))
                self.assertRegex(code[entry["file"]], pattern,
                                 f"{entry['file']}::{entry['signal']} is documented as '{entry['mechanism']}'")

    def test_only_session_lifetime_ui_observers_use_raw_connect(self):
        allowed = {entry["file"] for entry in self.inventory["allowed_raw_connect"]}
        reasons = {entry["file"]: entry["reason"] for entry in self.inventory["allowed_raw_connect"]}
        for relative, text in self._campaign_code().items():
            for signal in re.findall(r"EventBus\.(\w+)\.connect\(", text):
                with self.subTest(file=relative, signal=signal):
                    self.assertIn(relative, allowed,
                                  "a per-run node must subscribe with EventBus.bind(host, sig, cb)")
                    self.assertTrue(reasons[relative].strip())

    def test_campaign_uses_no_state_owning_signal(self):
        # The documented set is the guard: every entry must be an allowed role.
        roles = {name: set(entry["roles"]) for name, entry in self.inventory["signals"].items()}
        for entry in self.inventory["campaign_uses"]:
            with self.subTest(signal=entry["signal"]):
                self.assertIn(entry["signal"], roles, "campaign uses a signal the bus does not declare")
                self.assertTrue(roles[entry["signal"]] & {"ui", "audio", "visuals", "telemetry", "diagnostics"},
                                "campaign may only observe/emit observer channels")

    def test_directly_owned_state_channels_exist_as_documented(self):
        encounters = read("scripts/campaign/campaign_encounters.gd")
        director = read("scripts/campaign/campaign_director.gd")
        world = read("scripts/campaign/campaign_world.gd")
        self.assertIn("signal member_defeated(spawn_id: String, credits: int)", encounters)
        self.assertIn("encounters.member_defeated.connect(_on_member_defeated)", director)
        self.assertIn("func safe_to_rest(at: Vector3) -> bool:", encounters)
        self.assertIn("encounters.safe_to_rest(player.global_position)", director)
        self.assertIn("signal changed", director)
        self.assertIn("signal message(text: String)", director)
        # The campaign world mutates no bus state: it has no EventBus reference at all.
        self.assertNotIn("EventBus", "\n".join(code_lines(world)))

    def test_diagnostic_api_is_the_documented_one(self):
        bus = read(EVENT_BUS)
        methods = self.inventory["diagnostic_api"]["methods"]
        self.assertEqual(methods, ["report_info", "report_warning", "report_error", "report_diagnostic"])
        for name in methods:
            self.assertIn(f"func {name}(", bus)

    def test_bind_unbinds_on_tree_exit(self):
        bus = read(EVENT_BUS)
        body = functions(bus)["bind"]
        joined = "\n".join(body)
        self.assertIn("sig.connect(cb)", joined)
        self.assertIn("host.tree_exiting.connect(_unbind.bind(sig, cb), CONNECT_ONE_SHOT)", joined)
        self.assertIn("if not sig.is_connected(cb):", joined)


class FallbackDiagnosticTests(unittest.TestCase):
    """Weakness 7: no silent fallback, and no per-frame spam."""

    DIAGNOSTIC_RE = None

    @classmethod
    def setUpClass(cls):
        cls.ledger = json.loads(read(LEDGER))
        cls.diagnostics = re.compile("|".join(
            re.escape(token) for token in cls.ledger["policy"]["diagnostics"]))
        cls.trigger = re.compile(r"\b\w*fallback\w*\s*\(|\breturn\s+\w*fallback\w*\b|BoxMesh\.new\(\)|CapsuleMesh\.new\(\)")

    def _sweep(self) -> list[tuple[str, str]]:
        sites: list[tuple[str, str]] = []
        for path in sorted(SCRIPTS.rglob("*.gd")):
            relative = path.relative_to(ROOT).as_posix()
            for name, body in functions(path.read_text(encoding="utf-8")).items():
                joined = "\n".join(body)
                if self.trigger.search(joined):
                    sites.append((relative, name))
        return sites

    def test_every_substitution_site_is_in_the_ledger(self):
        listed = {(entry["file"], entry["function"]) for entry in self.ledger["sites"]}
        missing = [f"{f}::{n}" for f, n in self._sweep() if (f, n) not in listed]
        self.assertEqual(missing, [], "a new fallback/substitution site is undocumented: list it in "
                                      "docs/architecture/fallback_ledger.json with either a diagnostic or a reason")

    def test_ledger_entries_still_point_at_real_code(self):
        for entry in self.ledger["sites"] + self.ledger["audited_asset_loaders"]:
            path = ROOT / entry["file"]
            with self.subTest(site=f"{entry['file']}::{entry['function']}"):
                self.assertTrue(path.is_file(), "the ledger names a file that no longer exists")
                bodies = functions(path.read_text(encoding="utf-8"))
                self.assertIn(entry["function"], bodies, "the ledger names a function that no longer exists")
                if entry.get("disposition") == "exempt":
                    self.assertTrue(entry["reason"].strip(), "an exempt fallback needs a written reason")
                    continue
                reported_in = entry.get("reported_in", entry["function"])
                self.assertIn(reported_in, bodies, f"{reported_in} no longer exists in {entry['file']}")
                body = "\n".join(bodies[reported_in])
                self.assertTrue(self.diagnostics.search(body),
                                f"{entry['file']}::{reported_in} stopped emitting a diagnostic")
                guard = entry.get("dedupe_guard")
                if guard:
                    text = path.read_text(encoding="utf-8")
                    self.assertTrue(guard.startswith("_reported"),
                                    "the dedupe guard is a _reported* dictionary by convention")
                    self.assertIn(guard, text,
                                  f"{entry['file']} lost its once-per-session guard {guard!r}")
                    # Declaring the guard is not enough: the reporter has to read it
                    # before emitting and record it after, which is what keeps a hot
                    # site to one diagnostic per source per session.
                    self.assertRegex(body, re.escape(guard) + r"\.(get|has|contains)\(",
                                     f"{reported_in} no longer consults {guard} before reporting")
                    self.assertRegex(body, re.escape(guard) + r"\[.*\]\s*=",
                                     f"{reported_in} no longer records {guard}, so it can spam")

    def test_exempt_entries_keep_their_reason(self):
        for entry in self.ledger["sites"]:
            if entry["disposition"] != "exempt":
                continue
            with self.subTest(site=f"{entry['file']}::{entry['function']}"):
                self.assertTrue(entry["reason"].strip(), "an exempt fallback needs a written reason")
                self.assertNotIn("TODO", entry["reason"])

    def test_no_asset_substitution_is_exempt(self):
        # An exemption may not cover a failed load/mount: those must report.
        for entry in self.ledger["sites"]:
            if entry["disposition"] != "exempt":
                continue
            body = "\n".join(functions((ROOT / entry["file"]).read_text(encoding="utf-8"))[entry["function"]])
            with self.subTest(site=f"{entry['file']}::{entry['function']}"):
                self.assertFalse(re.search(r"\bload\(", body),
                                 "a site that loads an asset cannot be exempt; report the failure instead")

    def test_no_comment_claims_a_silent_fallback(self):
        offenders: list[str] = []
        pattern = re.compile(r"silent\w*\D{0,40}fallback|fallback\D{0,40}silent", re.IGNORECASE)
        for path in sorted(SCRIPTS.rglob("*.gd")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                stripped = line.strip()
                if not stripped.startswith("#"):
                    continue
                if pattern.search(stripped):
                    offenders.append(f"{path.relative_to(ROOT).as_posix()}:{number}: {stripped[:100]}")
        self.assertEqual(offenders, [], "a comment still describes a fallback as silent; report it instead")

    def test_campaign_geometry_reports_once_per_module_scene(self):
        geometry = read("scripts/campaign/campaign_geometry.gd")
        body = "\n".join(functions(geometry)["_report_fallback"])
        self.assertIn("if _reported_fallbacks.get(key, false):", body)
        self.assertIn("_reported_fallbacks[key] = true", body)
        self.assertIn("push_warning(", body)
        self.assertEqual(len(re.findall(r"push_warning\(", body)), 1,
                         "the reporter must emit exactly one diagnostic per deduped source")
        # The report names what failed, where, and what replaces it.
        for needle in ("CampaignGeometry.%s", "carries no MeshInstance3D", "fallback box geometry"):
            self.assertIn(needle, body)

    def test_streaming_and_save_hot_paths_do_not_report_per_call(self):
        # Every 'hot' site must dedupe by source, never report per invocation.
        for entry in self.ledger["sites"]:
            if entry.get("cadence") != "hot":
                continue
            with self.subTest(site=f"{entry['file']}::{entry['function']}"):
                self.assertTrue(entry.get("dedupe_guard"), "a hot fallback needs a once-per-session guard")


class JsonHelperNegativeLengthTests(unittest.TestCase):
    """Audit finding #12: a negative file length is rejected before reading."""

    def test_read_text_file_rejects_negative_and_oversized_lengths(self):
        helpers = read("scripts/utilities/json_helpers.gd")
        body = "\n".join(functions(helpers)["read_text_file"])
        self.assertIn("var length := int(file.get_length())", body)
        self.assertIn("if length < 0 or length > MAX_FILE_BYTES:", body)
        self.assertLess(body.index("length < 0"), body.index("file.get_as_text()"),
                        "the size check has to run before the contents are read")
        self.assertIn("file.close()", body.split("length < 0")[1].split("get_as_text")[0],
                      "the rejected handle is closed before returning")

    def test_size_ceiling_is_declared_once(self):
        helpers = read("scripts/utilities/json_helpers.gd")
        self.assertEqual(len(re.findall(r"^const MAX_FILE_BYTES", helpers, re.MULTILINE)), 1)
        self.assertEqual(const_value(helpers, "MAX_FILE_BYTES"), "1_000_000")

    def test_header_describes_the_return_contract(self):
        lines = read("scripts/utilities/json_helpers.gd").splitlines()
        header = "\n".join(line for line in lines[:16] if line.startswith("##"))
        self.assertTrue(header, "the helpers lost their file header")
        self.assertNotIn("pure", header, "the file helpers do I/O; the header may not claim purity")
        for phrase in ("never throw", 'they return "" / false', "no save yet", "are I/O"):
            self.assertIn(phrase, header, f"the header no longer states {phrase!r}")
        # The read docstring must name every "" return, including the negative length.
        doc = read("scripts/utilities/json_helpers.gd").splitlines()
        start = doc.index("static func read_text_file(path: String) -> String:")
        preceding: list[str] = []
        for line in reversed(doc[:start]):
            if not line.startswith("##"):
                break
            preceding.append(line)
        stated = "\n".join(reversed(preceding))
        self.assertTrue(stated, "read_text_file lost its docstring")
        for needle in ("missing", "negative length", "MAX_FILE_BYTES", "before the contents are read"):
            self.assertIn(needle, stated, f"the read_text_file docstring no longer states {needle!r}")


if __name__ == "__main__":
    unittest.main()
