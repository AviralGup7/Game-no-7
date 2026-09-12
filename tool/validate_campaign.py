#!/usr/bin/env python3
"""Validate the authored campaign and optionally draw its overview (stdlib only).

This checks actual coordinates/topology, not merely the presence of script names.
It mirrors CampaignGeometry's 8 m floor union and ArenaNavGrid's conservative
4 m campaign mask. It is NOT a Godot or Android runtime/performance test.
"""
from __future__ import annotations

import argparse
from collections import deque
import html
import json
import math
from pathlib import Path
import re
import sys
import textwrap

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "data/campaign/station_zero.json"
CELL = 4
MODULE = 8
CLEARANCE = 2.5  # half a nav cell + the capsule margin
SUPPORTED_ENEMIES = {"basic", "fast", "heavy", "ranged", "dasher", "warlord"}

# Android world budgets. The layout is bounded by the coarse 4 m navigation grid,
# not by the deck meshes: 1,024 m permits an 864 x 672 m station (36,288 cells)
# with headroom, and 40,960 cells keeps the blocked/flow arrays under ~200 KB
# while the bounded flow field (see ArenaNavGrid.rebuild_flow_field) keeps each
# combat rebuild proportional to the local crowd, not to the whole station.
MAX_WORLD_EXTENT = 1024
MAX_NAV_CELLS = 40960
# CampaignDefinition refuses to load more than this offline too, so a future
# expansion cannot author a world the APK loader would silently reject.
MAX_FLOOR_REGIONS = 64
MAX_TABLE_ROWS = 512


class CampaignError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CampaignError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load(path=MAP_PATH):
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def numbers(value, size):
    return (isinstance(value, list) and len(value) == size
            and all(type(x) in (int, float) and math.isfinite(x) for x in value))


def contains(rect, point):
    x, z, w, d = rect
    return x <= point[0] < x + w and z <= point[-1] < z + d


def enclosing(outer, inner):
    x, z, w, d = outer
    a, b, c, e = inner
    return x <= a and z <= b and a + c <= x + w and b + e <= z + d


def footprint(prop, grow=0):
    x, _, z = prop["at"]
    w, _, d = prop["size"]
    return [x - w / 2 - grow, z - d / 2 - grow, w + grow * 2, d + grow * 2]


def in_solid(rect, point):
    x, z, w, d = rect
    return x <= point[0] <= x + w and z <= point[-1] <= z + d


class Topology:
    def __init__(self, data):
        self.data = data
        self.bounds = data["bounds"]
        x, z, w, d = self.bounds
        self.width, self.depth = math.ceil(w / CELL), math.ceil(d / CELL)
        inflated = [footprint(p, CLEARANCE) for p in data["props"]]
        self.walkable = set()
        for j in range(self.depth):
            for i in range(self.width):
                at = self.center((i, j))
                if (any(contains(f, at) for f in data["floors"])
                        and not any(in_solid(p, at) for p in inflated)):
                    self.walkable.add((i, j))
        self.modules = set()
        for a, b, c, e in data["floors"]:
            for j in range(round(b / MODULE), round((b + e) / MODULE)):
                for i in range(round(a / MODULE), round((a + c) / MODULE)):
                    self.modules.add((i, j))

    def cell(self, point):
        return (math.floor((point[0] - self.bounds[0]) / CELL),
                math.floor((point[-1] - self.bounds[1]) / CELL))

    def center(self, cell):
        return (self.bounds[0] + (cell[0] + .5) * CELL,
                self.bounds[1] + (cell[1] + .5) * CELL)

    def neighbors(self, at):
        for dx, dz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            other = at[0] + dx, at[1] + dz
            if other in self.walkable:
                yield other

    def reachable(self, point):
        start = self.cell(point)
        if start not in self.walkable:
            return set()
        seen, queue = {start}, deque([start])
        while queue:
            for other in self.neighbors(queue.popleft()):
                if other not in seen:
                    seen.add(other)
                    queue.append(other)
        return seen

    def path(self, start, end):
        start, end = self.cell(start), self.cell(end)
        if start not in self.walkable or end not in self.walkable:
            return []
        previous, queue = {start: None}, deque([start])
        while queue and end not in previous:
            at = queue.popleft()
            for other in self.neighbors(at):
                if other not in previous:
                    previous[other] = at
                    queue.append(other)
        if end not in previous:
            return []
        result, cursor = [], end
        while cursor is not None:
            result.append(self.center(cursor))
            cursor = previous[cursor]
        return result[::-1]

    def perimeter_edges(self):
        edges = []
        for x, z in sorted(self.modules):
            if (x, z - 1) not in self.modules:
                edges.append(((x * 8, z * 8), ((x + 1) * 8, z * 8)))
            if (x, z + 1) not in self.modules:
                edges.append(((x * 8, (z + 1) * 8), ((x + 1) * 8, (z + 1) * 8)))
            if (x - 1, z) not in self.modules:
                edges.append(((x * 8, z * 8), (x * 8, (z + 1) * 8)))
            if (x + 1, z) not in self.modules:
                edges.append((((x + 1) * 8, z * 8), ((x + 1) * 8, (z + 1) * 8)))
        return edges


def validate(data, root=ROOT):
    require(isinstance(data, dict), "Campaign root must be an object")
    require(data.get("schema_version") == 1, "Unsupported campaign schema")
    require(data.get("world_id") == "station_zero", "Unexpected fixed world id")
    require("seed" not in data and "arena_id" not in data, "Campaign cannot require world rolls")
    bounds = data.get("bounds")
    require(numbers(bounds, 4) and 0 < bounds[2] <= MAX_WORLD_EXTENT
            and 0 < bounds[3] <= MAX_WORLD_EXTENT, "Invalid world bounds")
    require(data.get("module_size") == MODULE and data.get("navigation_cell") == CELL, "Module/nav sizes must match runtime")
    require(1 <= data.get("max_active_enemies", 0) <= 18, "Android enemy budget exceeds 18")
    require(1 <= data.get("max_visible_sectors", 0) <= 3, "Android district budget exceeds 3")
    for key in ("floors", "sectors", "props", "interactions", "encounters", "missions"):
        require(isinstance(data.get(key), list) and data[key], f"Missing/invalid {key}")
    require(len(data["floors"]) <= MAX_FLOOR_REGIONS, "Floor regions exceed the runtime loader budget")
    for key in ("sectors", "props", "interactions", "encounters", "missions"):
        require(len(data[key]) <= MAX_TABLE_ROWS, f"{key} exceed the runtime loader budget")
    for floor in data["floors"]:
        require(numbers(floor, 4) and floor[2] > 0 and floor[3] > 0, "Invalid floor rectangle")
        require(all(v % MODULE == 0 for v in floor), "Floor edges must align to 8 m modules")
        require(enclosing(bounds, floor), "Floor outside world bounds")
    tables = {}
    all_ids = set()
    for key in ("sectors", "props", "interactions", "encounters", "missions"):
        table = {}
        for item in data[key]:
            require(isinstance(item, dict), f"Non-object {key} entry")
            ident = item.get("id")
            require(isinstance(ident, str) and re.fullmatch(r"[a-z][a-z0-9_]{0,63}", ident), f"Invalid {key} id")
            require(ident not in all_ids, f"Duplicate authored id: {ident}")
            all_ids.add(ident)
            table[ident] = item
        tables[key] = table
    require("docks" in tables["sectors"], "Missing starting district")
    members = []
    for sector in data["sectors"]:
        require(sector.get("rect") in data["floors"], f"District {sector['id']} has no matching deck")
        require(numbers(sector.get("checkpoint"), 3), "Invalid checkpoint")
        require(contains(sector["rect"], sector["checkpoint"]), "Checkpoint outside its district")
        require(bool(re.fullmatch(r"#[0-9a-fA-F]{6}", sector.get("accent", ""))), "Invalid sector color")
    for key in ("props", "interactions", "encounters", "missions"):
        for item in data[key]:
            require(item.get("sector") in tables["sectors"], f"Unknown sector: {item['id']}")
    for prop in data["props"]:
        require(numbers(prop.get("at"), 3) and numbers(prop.get("size"), 3), "Invalid prop vectors")
        require(all(v > 0 for v in prop["size"]), "Non-positive prop size")
        require(prop["at"][1] - prop["size"][1] / 2 >= 0, "Prop below the deck")
        require(enclosing(tables["sectors"][prop["sector"]]["rect"], footprint(prop)), "Landmark extends outside its district")
    for group in data["encounters"]:
        require(20 <= group.get("activate_radius", 0) <= 50, "Invalid activation radius")
        require(isinstance(group.get("members"), list) and 0 < len(group["members"]) <= 18, "Invalid encounter members")
        for member in group["members"]:
            require(isinstance(member, dict) and isinstance(member.get("id"), str), "Invalid spawn record")
            require(member["id"] not in all_ids, "Duplicate spawn id")
            all_ids.add(member["id"])
            require(member.get("type") in SUPPORTED_ENEMIES, "Untracked summoning/splitting/exploding archetype")
            require((root / f"data/enemies/{member['type']}_enemy.tres").is_file(), "Missing enemy config")
            require(numbers(member.get("at"), 3), "Invalid spawn position")
            members.append(member)
    for item in data["interactions"]:
        require(numbers(item.get("at"), 3), "Invalid interaction position")
        require(contains(tables["sectors"][item["sector"]]["rect"], item["at"]), "Interaction outside district")
        require(item.get("kind") in {"terminal", "collect", "extraction", "cache"}, "Invalid interaction kind")
        require(0 <= item.get("credits", -1) <= 1000, "Invalid cache credits")
    used_targets = set()
    for mission in data["missions"]:
        require(mission.get("kind") in {"interact", "collect", "clear", "extract"}, "Invalid mission kind")
        require(isinstance(mission.get("targets"), list) and mission["targets"], "Mission without targets")
        for ident in mission["targets"]:
            require(ident in tables["interactions"], "Unknown mission target")
            require(ident not in used_targets, "A mission target is reused: rewards could replay or stall")
            require(tables["interactions"][ident]["kind"] != "cache", "Story target cannot be an optional cache")
            used_targets.add(ident)
        require(all(ident in tables["encounters"] for ident in mission.get("requires", [])), "Unknown encounter prerequisite")
        for kind in ("upgrade", "weapon"):
            if kind in mission.get("reward", {}):
                ident = mission["reward"][kind]
                require((root / f"data/{kind}s/{ident}.tres").is_file(), f"Missing reward: {ident}")
    require(data["missions"][-1]["kind"] == "extract", "Campaign must end with extraction")
    topology = Topology(data)
    require(topology.width * topology.depth <= MAX_NAV_CELLS, "Navigation budget exceeded")
    start = tables["sectors"]["docks"]["checkpoint"]
    reachable = topology.reachable(start)
    require(bool(reachable), "Starting checkpoint is blocked")
    require(reachable == topology.walkable, "Station has disconnected/unreachable floor cells")
    points = ([(s["id"] + " checkpoint", s["checkpoint"]) for s in data["sectors"]]
              + [(i["id"], i["at"]) for i in data["interactions"]]
              + [(m["id"], m["at"]) for m in members])
    for ident, point in points:
        require(topology.cell(point) in reachable, f"Blocked or unreachable point: {ident} at {point}")
        require(not any(in_solid(footprint(p, .7), point) for p in data["props"]), f"Point clips a physical prop: {ident}")
    for sector in data["sectors"]:
        nearest = min(math.dist(sector["checkpoint"], member["at"]) for member in members)
        require(nearest >= 24, f"Unsafe checkpoint: {sector['id']} only {nearest:.1f}m from a guard")
    return {"districts": len(data["sectors"]), "floor_regions": len(data["floors"]),
            "landmarks": len(data["props"]), "interactions": len(data["interactions"]),
            "encounters": len(data["encounters"]), "authored_enemies": len(members),
            "missions": len(data["missions"]), "navigation_cells": topology.width * topology.depth,
            "reachable_walkable_cells": len(reachable), "floor_modules": len(topology.modules),
            "perimeter_edges": len(topology.perimeter_edges())}


def write_svg(data, path):
    """Author-facing overview: layout is derived from the authored world, so a
    larger station or a longer mission chain cannot overflow the canvas."""
    graph = Topology(data)
    x0, z0, world_w, world_d = data["bounds"]
    box_x, box_y, box_w, box_h = 40.0, 178.0, 960.0, 756.0
    pad = 14.0
    scale = min((box_w - pad * 2) / world_w, (box_h - pad * 2) / world_d)
    chart = (world_w * scale, world_d * scale)
    left = box_x + (box_w - chart[0]) * 0.5
    top = box_y + (box_h - chart[1]) * 0.5

    def xy(point):
        return left + (point[0] - x0) * scale, top + (point[-1] - z0) * scale

    def rect(area, color, stroke="none", opacity=1):
        x, y = xy(area[:2])
        parts.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{area[2]*scale:.1f}" '
                     f'height="{area[3]*scale:.1f}" fill="{color}" stroke="{stroke}" opacity="{opacity}"/>')

    def circle(point, radius, color, stroke="none", width=1):
        x, y = xy(point)
        parts.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{radius}" fill="{color}" '
                     f'stroke="{stroke}" stroke-width="{width}"/>')

    missions = data["missions"]
    # Reserve the right-hand column height first: the canvas grows with the
    # mission log instead of clipping it.
    log_x = box_x + box_w + 20.0
    y = 251.0
    for mission in missions:
        y += 21 + 17 * len(textwrap.wrap(mission["brief"], 44)) + 12
    log_bottom = y
    height = max(1080, int(log_bottom + 150))
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1420" height="{height}" '
             f'viewBox="0 0 1420 {height}">',
             f'<rect width="1420" height="{height}" fill="#080f19"/>',
             '<style>text{font-family:Arial,sans-serif}.muted{fill:#92a7bd}.white{fill:#eaf2fa}</style>',
             '<rect x="52" y="50" width="44" height="4" fill="#65d9ed"/>',
             '<text x="112" y="58" fill="#65d9ed" font-size="14" letter-spacing="3">LAST STAND / CAMPAIGN FIELD GUIDE</text>',
             '<text x="52" y="119" class="white" font-size="48" font-weight="700">STATION ZERO</text>',
             '<text x="54" y="154" class="muted" font-size="19" letter-spacing="3">THE LONG WAY HOME</text>',
             f'<rect x="{box_x}" y="{box_y}" width="{box_w}" height="{box_h}" rx="14" fill="#0c1826" stroke="#233d54"/>']
    for floor in data["floors"]:
        rect(floor, "#21364a")
    for sector in data["sectors"]:
        rect(sector["rect"], sector["accent"], opacity=.12)
        rect(sector["rect"], "none", sector["accent"])
        x, y = xy(sector["rect"][:2])
        parts.append(f'<text x="{x+8:.1f}" y="{y+17:.1f}" fill="{sector["accent"]}" font-size="11" '
                     f'font-weight="700">{html.escape(sector["name"])}</text>')
    for prop in data["props"]:
        rect(footprint(prop), "#304453", "#547083")
    current = data["sectors"][0]["checkpoint"]
    interactions = {item["id"]: item for item in data["interactions"]}
    route = []
    for mission in missions:
        for ident in mission["targets"]:
            point = interactions[ident]["at"]
            route.extend(graph.path(current, point))
            current = point
    encoded = " ".join(f"{xy(p)[0]:.1f},{xy(p)[1]:.1f}" for p in route)
    parts.append(f'<polyline points="{encoded}" fill="none" stroke="#eacb79" stroke-width="2" '
                 f'opacity=".65" stroke-dasharray="6 5"/>')
    for sector in data["sectors"]:
        circle(sector["checkpoint"], 5, "#0b1827", "#70e6b8", 2)
    for group in data["encounters"]:
        for member in group["members"]:
            circle(member["at"], 2.6, "#d87871")
    for item in data["interactions"]:
        if item["kind"] == "cache":
            x, y = xy(item["at"])
            parts.append(f'<rect x="{x-3:.1f}" y="{y-3:.1f}" width="6" height="6" fill="#aec3d5"/>')
    for index, mission in enumerate(missions, 1):
        for n, ident in enumerate(mission["targets"]):
            point = interactions[ident]["at"]
            circle(point, 9 if n == 0 else 4, "#f4cf7a", "#101c29", 2)
            if n == 0:
                x, y = xy(point)
                parts.append(f'<text x="{x:.1f}" y="{y+3.5:.1f}" text-anchor="middle" font-size="10" '
                             f'font-weight="700" fill="#152434">{index}</text>')
    parts.extend([f'<text x="{box_x + box_w - 34:.0f}" y="{box_y + 38}" fill="#92a7bd" font-size="14">N</text>',
                  f'<path d="M{box_x + box_w - 14} {box_y + 42} V{box_y + 21} '
                  f'M{box_x + box_w - 19} {box_y + 27} L{box_x + box_w - 14} {box_y + 21} '
                  f'L{box_x + box_w - 9} {box_y + 27}" fill="none" stroke="#92a7bd" stroke-width="1.5"/>',
                  f'<text x="{log_x}" y="207" fill="#65d9ed" font-size="13" letter-spacing="2">MISSION LOG</text>'])
    y = 251.0
    for index, mission in enumerate(missions, 1):
        parts.append(f'<text x="{log_x}" y="{y}" fill="#f4cf7a" font-size="15">{index:02d}</text>')
        parts.append(f'<text x="{log_x + 40}" y="{y}" class="white" font-size="15" '
                     f'font-weight="700">{html.escape(mission["title"])}</text>')
        for line in textwrap.wrap(mission["brief"], 44):
            y += 17
            parts.append(f'<text x="{log_x + 40}" y="{y}" class="muted" font-size="12.5">{html.escape(line)}</text>')
        y += 33
    base = height - 104
    parts.extend([f'<circle cx="57" cy="{base}" r="4" fill="#f4cf7a"/>'
                  f'<text x="70" y="{base+5}" fill="#f4cf7a" font-size="14">STORY OBJECTIVE / ROUTE</text>',
                  f'<circle cx="335" cy="{base}" r="4" fill="none" stroke="#70e6b8" stroke-width="1.5"/>'
                  f'<text x="348" y="{base+5}" fill="#70e6b8" font-size="14">CHECKPOINT</text>',
                  f'<rect x="535" y="{base-4}" width="8" height="8" fill="#aec3d5"/>'
                  f'<text x="552" y="{base+5}" fill="#aec3d5" font-size="14">SUPPLY LOCKER</text>',
                  f'<circle cx="765" cy="{base}" r="3.5" fill="#d87871"/>'
                  f'<text x="779" y="{base+5}" fill="#d87871" font-size="14">AUTHORED GUARD</text>',
                  f'<path d="M52 {base+29} H1370" stroke="#233d54"/>',
                  f'<text x="52" y="{base+65}" class="white" font-size="15">{world_w} × {world_d} m footprint  /  '
                  f'{len(data["sectors"])} connected districts  /  {len(missions)} objectives  /  '
                  f'{len(data["encounters"])} finite encounters</text>',
                  f'<text x="1370" y="{base+65}" text-anchor="end" class="muted" font-size="13">'
                  f'FIXED WORLD · ANDROID-FIRST</text>', '</svg>'])
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(parts) + "\n", encoding="utf-8")



def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, default=MAP_PATH)
    parser.add_argument("--svg", type=Path)
    args = parser.parse_args(argv)
    try:
        data = load(args.map)
        report = validate(data)
        if args.svg:
            write_svg(data, args.svg)
    except (CampaignError, ValueError, KeyError, TypeError, OSError) as exc:
        print(f"Campaign validation FAILED: {exc}", file=sys.stderr)
        return 1
    print("Campaign topology/content: OK " + json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
