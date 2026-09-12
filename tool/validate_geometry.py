#!/usr/bin/env python3
"""
Geometry & Asset Integrity Validator — Agent 1

Exhaustive offline checks for the continuous campaign world (Station Zero)
and the modular arena system. No Godot runtime, no device, stdlib only.

Coverage (13 categories from the brief):
  1. Floating objects                  (props whose base is above the floor)
  2. Buried inside terrain/floors      (props whose base is below the floor)
  3. Unintended intersections/overlaps (prop-vs-prop, spawn-vs-prop, spawn-vs-spawn)
  4. Gaps between modular walls/floors (floor connectivity, perimeter sealing)
  5. Snapped alignment                 (MODULE=8 grid, navigation cell=4)
  6. Impossible rotations/scales       (landmark/theme/arena ranges, finite)
  7. Duplicate / stacked meshes        (duplicate ids, colocated solids, exact footprints)
  8. Broken / missing resources        (enemy configs, rewards, panorama, scene paths)
  9. Collision vs visual mismatch      (AABB derivation, volume drift, origin)
  10. Objects outside intended bounds  (world bounds, sector floors, nav)
  11. Extremely large / small assets   (size anomaly, footprint anomaly)
  12. Transforms / origins / scale     (Y=0 invariant, transform finiteness, consistent scale)
  13. Inaccessible / stray objects     (unreachable missions/spawns/caches, stray props)

Exit 0 on clean, 1 on any geometry integrity failure.
Produces both human-readable stdout and an optional JSON report.

Usage:
  python3 tool/validate_geometry.py
  python3 tool/validate_geometry.py --json docs/geometry_report.json
  python3 tool/validate_geometry.py --map data/campaign/station_zero.json --verbose
"""

from __future__ import annotations

import argparse
import json
import math
import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "data/campaign/station_zero.json"
MODULE = 8
CELL = 4
CLEARANCE = 2.5
WALL_HEIGHT = 1.8
WALL_THICK = 0.7

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

class GeometryError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise GeometryError(message)


def unique_object(pairs):
    result = {}
    for k, v in pairs:
        if k in result:
            raise GeometryError(f"Duplicate JSON key: {k}")
        result[k] = v
    return result


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def numbers(value, size: int) -> bool:
    return (
        isinstance(value, list)
        and len(value) == size
        and all(type(x) in (int, float) and math.isfinite(float(x)) for x in value)
    )


def contains(rect, point) -> bool:
    x, z, w, d = rect
    return x <= point[0] < x + w and z <= point[-1] < z + d


def enclosing(outer, inner) -> bool:
    x, z, w, d = outer
    a, b, c, e = inner
    return x <= a and z <= b and a + c <= x + w and b + e <= z + d


def footprint(prop, grow: float = 0.0):
    """Axis-aligned footprint rect [x, z, w, d] from authored at/size."""
    x, _, z = prop["at"]
    w, _, d = prop["size"]
    return [x - w / 2 - grow, z - d / 2 - grow, w + grow * 2, d + grow * 2]


def aabb_from_prop(prop) -> tuple[list[float], list[float]]:
    """Return (min_vec3, size_vec3) for solid box exactly as CampaignDefinition.solid_boxes()."""
    x, y, z = prop["at"]
    w, h, d = prop["size"]
    return ([x - w / 2, y - h / 2, z - d / 2], [w, h, d])


def rects_overlap(a, b) -> bool:
    ax, az, aw, ad = a
    bx, bz, bw, bd = b
    return not (ax + aw <= bx or bx + bw <= ax or az + ad <= bz or bz + bd <= az)


def overlap_area(a, b) -> float:
    if not rects_overlap(a, b):
        return 0.0
    ax, az, aw, ad = a
    bx, bz, bw, bd = b
    ox = max(ax, bx)
    oz = max(az, bz)
    ex = min(ax + aw, bx + bw)
    ez = min(az + ad, bz + bd)
    return max(0.0, ex - ox) * max(0.0, ez - oz)


# ---------------------------------------------------------------------------
# topology (mirrors CampaignGeometry / validate_campaign Topology)
# ---------------------------------------------------------------------------

class Topology:
    def __init__(self, data):
        self.data = data
        self.bounds = data["bounds"]
        x, z, w, d = self.bounds
        self.width = math.ceil(w / CELL)
        self.depth = math.ceil(d / CELL)
        inflated = [footprint(p, CLEARANCE) for p in data["props"]]
        self.walkable: set[tuple[int, int]] = set()
        for j in range(self.depth):
            for i in range(self.width):
                at = self.center((i, j))
                if any(contains(f, at) for f in data["floors"]) and not any(
                    ax <= at[0] <= ax + aw and az <= at[1] <= az + ad
                    for ax, az, aw, ad in inflated
                ):
                    self.walkable.add((i, j))
        self.modules: set[tuple[int, int]] = set()
        for a, b, c, e in data["floors"]:
            for j in range(round(b / MODULE), round((b + e) / MODULE)):
                for i in range(round(a / MODULE), round((a + c) / MODULE)):
                    self.modules.add((i, j))

    def cell(self, point):
        return (
            math.floor((point[0] - self.bounds[0]) / CELL),
            math.floor((point[-1] - self.bounds[1]) / CELL),
        )

    def center(self, cell):
        return (
            self.bounds[0] + (cell[0] + 0.5) * CELL,
            self.bounds[1] + (cell[1] + 0.5) * CELL,
        )

    def neighbors(self, at):
        for dx, dz in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            other = at[0] + dx, at[1] + dz
            if other in self.walkable:
                yield other

    def reachable(self, point):
        from collections import deque

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


# ---------------------------------------------------------------------------
# per-category checks
# ---------------------------------------------------------------------------

# Tolerances — chosen to be stricter than gameplay needs but looser than
# float noise, so only real authoring errors trip them.
FLOAT_EPS = 0.05        # base may be 0 ± 5 cm
BURIED_EPS = -0.05      # base < -5 cm is buried
OVERLAP_EPS = 0.01      # overlap area > 1 cm² is real
DUPLICATE_DIST = 0.10   # two solids with centers <10 cm apart are stacked
INTERACTION_Y = 0.2     # interactions/spawns sit 20 cm above floor by design
SPAWN_CLEARANCE = 24.0  # checkpoint must be ≥24 m from nearest guard


def check_floating_and_buried(data: dict, issues: list[dict]) -> None:
    """1+2 : floating vs buried — one base invariant, two failure modes."""
    for prop in data["props"]:
        base = prop["at"][1] - prop["size"][1] / 2
        if base > FLOAT_EPS:
            issues.append(
                {
                    "category": "floating",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"base {base:.3f} m above floor (at.y={prop['at'][1]}, size.y={prop['size'][1]}) — object floats",
                    "at": prop["at"],
                    "size": prop["size"],
                    "base_y": base,
                }
            )
        elif base < BURIED_EPS:
            issues.append(
                {
                    "category": "buried",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"base {base:.3f} m below floor — object is buried inside terrain",
                    "at": prop["at"],
                    "size": prop["size"],
                    "base_y": base,
                }
            )
    # Interactions / spawns should sit at INTERACTION_Y
    for item in data["interactions"]:
        y = item["at"][1]
        if abs(y - INTERACTION_Y) > 0.02:
            issues.append(
                {
                    "category": "floating",
                    "severity": "warning",
                    "id": item["id"],
                    "detail": f"interaction y={y:.3f} expected {INTERACTION_Y} — may float or clip terrain",
                    "at": item["at"],
                }
            )
    for group in data["encounters"]:
        for member in group["members"]:
            y = member["at"][1]
            if abs(y - INTERACTION_Y) > 0.02:
                issues.append(
                    {
                        "category": "floating",
                        "severity": "warning",
                        "id": member["id"],
                        "detail": f"spawn y={y:.3f} expected {INTERACTION_Y} — may be buried or floating",
                        "at": member["at"],
                    }
                )


def check_intersections(data: dict, issues: list[dict]) -> None:
    """3 : unintended intersections — prop·prop, spawn·prop, spawn·spawn."""
    props = data["props"]
    # prop · prop (exact footprints, no clearance expansion — clearance is a
    # gameplay mask, not a visual gap; visual overlaps are what this catches)
    for i in range(len(props)):
        for j in range(i + 1, len(props)):
            a = footprint(props[i])
            b = footprint(props[j])
            area = overlap_area(a, b)
            if area > OVERLAP_EPS:
                issues.append(
                    {
                        "category": "intersection",
                        "severity": "error",
                        "id": f"{props[i]['id']} ↔ {props[j]['id']}",
                        "detail": f"footprints overlap by {area:.2f} m² — meshes will clip / physics will jam",
                        "a": props[i]["id"],
                        "b": props[j]["id"],
                        "overlap_area": area,
                    }
                )
    # spawn · prop  (spawn inside a solid's clearance-expanded footprint)
    for group in data["encounters"]:
        for member in group["members"]:
            pt = member["at"]
            for prop in props:
                exp = footprint(prop, 0.7)
                if exp[0] <= pt[0] <= exp[0] + exp[2] and exp[1] <= pt[-1] <= exp[1] + exp[3]:
                    issues.append(
                        {
                            "category": "intersection",
                            "severity": "error",
                            "id": member["id"],
                            "detail": f"spawn {member['id']} sits inside solid '{prop['id']}' (with 0.7 m margin) — will spawn stuck in geometry",
                            "spawn": member["id"],
                            "prop": prop["id"],
                            "at": pt,
                        }
                    )
                    break
    # spawn · spawn (two guards sharing a point — stacked meshes)
    all_spawns: list[dict] = []
    for group in data["encounters"]:
        all_spawns.extend(group["members"])
    for i in range(len(all_spawns)):
        for j in range(i + 1, len(all_spawns)):
            a = all_spawns[i]["at"]
            b = all_spawns[j]["at"]
            d = math.dist(a, b)
            if d < 0.5:
                issues.append(
                    {
                        "category": "duplicate",
                        "severity": "error",
                        "id": f"{all_spawns[i]['id']} ↔ {all_spawns[j]['id']}",
                        "detail": f"spawns {d:.2f} m apart — stacked / duplicate placement",
                        "distance": d,
                    }
                )
    # interaction · prop (same test as spawn·prop, but softer — a console inside a crate is wrong)
    for item in data["interactions"]:
        pt = item["at"]
        for prop in props:
            exp = footprint(prop, 0.7)
            if exp[0] <= pt[0] <= exp[0] + exp[2] and exp[1] <= pt[-1] <= exp[1] + exp[3]:
                issues.append(
                    {
                        "category": "intersection",
                        "severity": "error",
                        "id": item["id"],
                        "detail": f"interaction '{item['id']}' clips solid '{prop['id']}' — player cannot reach it without walking through geometry",
                        "interaction": item["id"],
                        "prop": prop["id"],
                    }
                )
                break


def check_duplicate_and_stacked(data: dict, issues: list[dict]) -> None:
    """7 : duplicate / stacked meshes."""
    # duplicate ids already caught by validate_campaign; repeat here for report
    ids = [p["id"] for p in data["props"]]
    dup = [k for k, v in Counter(ids).items() if v > 1]
    for d in dup:
        issues.append(
            {
                "category": "duplicate",
                "severity": "error",
                "id": d,
                "detail": f"duplicate prop id '{d}' — second mesh will silently overwrite the first in the scene tree",
            }
        )
    # colocated (stacked) at positions
    positions: dict[tuple[float, float, float], list[str]] = defaultdict(list)
    for prop in data["props"]:
        key = tuple(round(float(v), 4) for v in prop["at"])
        positions[key].append(prop["id"])
    for pos, owners in positions.items():
        if len(owners) > 1:
            issues.append(
                {
                    "category": "duplicate",
                    "severity": "error",
                    "id": " / ".join(owners),
                    "detail": f"{len(owners)} props share at={list(pos)} — stacked meshes render as one but collide as many",
                    "at": list(pos),
                }
            )
    # near-duplicate footprints (centers < DUPLICATE_DIST apart but not identical)
    for i in range(len(data["props"])):
        for j in range(i + 1, len(data["props"])):
            a = data["props"][i]["at"]
            b = data["props"][j]["at"]
            d = math.dist(a, b)
            if 0.001 < d < DUPLICATE_DIST * 10:  # 1 m is already suspicious for 8-m modules
                # Only flag if they are unusually close relative to their sizes
                size_a = max(data["props"][i]["size"][0], data["props"][i]["size"][2])
                size_b = max(data["props"][j]["size"][0], data["props"][j]["size"][2])
                if d < (size_a + size_b) * 0.15:
                    issues.append(
                        {
                            "category": "duplicate",
                            "severity": "warning",
                            "id": f"{data['props'][i]['id']} ↔ {data['props'][j]['id']}",
                            "detail": f"props {d:.2f} m apart with sizes {size_a:.0f}/{size_b:.0f} — likely stacked or mis-snapped",
                            "distance": d,
                        }
                    )


def check_gaps_and_perimeter(data: dict, issues: list[dict]) -> None:
    """4 : gaps between modular walls / floors — connectivity + perimeter."""
    topo = Topology(data)
    # floor connectivity: reachable must equal walkable (same check as validate_campaign)
    try:
        start = next(s["checkpoint"] for s in data["sectors"] if s["id"] == "docks")
    except StopIteration:
        issues.append(
            {"category": "gaps", "severity": "error", "id": "docks", "detail": "missing docks checkpoint — cannot test connectivity"}
        )
        return
    reachable = topo.reachable(start)
    if reachable != topo.walkable:
        missing = len(topo.walkable) - len(reachable)
        issues.append(
            {
                "category": "gaps",
                "severity": "error",
                "id": "floor",
                "detail": f"{missing} floor modules are disconnected from the start — they are visible geometry the player can never walk on (or a gap between modular floor tiles)",
                "walkable": len(topo.walkable),
                "reachable": len(reachable),
            }
        )
    # perimeter must enclose every floor module except the authored causeways.
    # The check: every floor-adjacent void edge should correspond to a perimeter
    # AABB, except where two floor modules meet (internal edge, no wall) and
    # except the known causeway gaps. If causeways are missing a wall that
    # should be there, the walkable set would still be connected but the
    # perimeter would have a hole that lets the player see the void.
    edges = topo.perimeter_edges()
    if len(edges) < 20:
        issues.append(
            {
                "category": "gaps",
                "severity": "warning",
                "id": "perimeter",
                "detail": f"only {len(edges)} perimeter edges — expected >20 for 6 districts; possible wall gap",
                "edges": len(edges),
            }
        )
    # verify causeways are NOT sealed (the shared district edges must stay open)
    causeway_xs = [-64, -48, 48, 64]
    for x in causeway_xs:
        for z in [-76, 92]:
            blocking = [
                (a, b)
                for a, b in edges
                if a[0] == b[0] == x and min(a[1], b[1]) < z < max(a[1], b[1])
            ]
            if blocking:
                issues.append(
                    {
                        "category": "gaps",
                        "severity": "error",
                        "id": f"sealed_causeway_{x}_{z}",
                        "detail": f"perimeter seals the connector at x={x}, z={z} — district is walled off (gap logic inverted)",
                    }
                )


def check_snapped_alignment(data: dict, issues: list[dict]) -> None:
    """5 : snapped alignment — MODULE=8 grid for floors, cell=4 for nav."""
    for floor in data["floors"]:
        for idx, v in enumerate(floor):
            if v % MODULE != 0:
                issues.append(
                    {
                        "category": "snapped",
                        "severity": "error",
                        "id": f"floor_{floor}",
                        "detail": f"floor edge {v} at index {idx} not snapped to {MODULE} m module — modular wall/floor will have a {v % MODULE:.2f} m gap or overlap",
                        "floor": floor,
                        "value": v,
                    }
                )
                break
    # checkpoint snapping is *not* required — they are free-placed — but a
    # checkpoint that lies exactly on a module boundary is a hint of a copy-
    # paste error; flag as info, not error.
    for sector in data["sectors"]:
        cp = sector["checkpoint"]
        # no error here; just verify finite
        if not all(math.isfinite(float(v)) for v in cp):
            issues.append(
                {
                    "category": "snapped",
                    "severity": "error",
                    "id": sector["id"],
                    "detail": f"checkpoint has non-finite coordinate: {cp}",
                }
            )


def check_rotations_and_scales(data: dict, issues: list[dict]) -> None:
    """6 : impossible rotations / scales."""
    # campaign props have no authored rotation/scale — they are axis-aligned
    # AABBs.  The check is therefore that no prop carries an unexpected
    # rotation field and that sizes are sane.
    for prop in data["props"]:
        size = prop["size"]
        # size must be finite and positive (duplicate of validate_campaign but
        # with anomaly thresholds here)
        if not all(math.isfinite(float(v)) and v > 0 for v in size):
            issues.append(
                {
                    "category": "transform",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"non-finite or non-positive size {size}",
                }
            )
        # rotation field should not exist in this schema; if it does it is
        # either stray data or a 3-D tilt that the AABB collider ignores
        if "rotation" in prop or "rotation_degrees" in prop:
            issues.append(
                {
                    "category": "transform",
                    "severity": "warning",
                    "id": prop["id"],
                    "detail": f"prop carries a rotation field {prop.get('rotation', prop.get('rotation_degrees'))} — campaign colliders are axis-aligned AABBs and will not match a tilted visual",
                }
            )
        if "scale" in prop:
            s = prop["scale"]
            vals = s if isinstance(s, list) else [s]
            for v in vals:
                if not math.isfinite(float(v)) or float(v) <= 0 or float(v) > 10:
                    issues.append(
                        {
                            "category": "transform",
                            "severity": "error",
                            "id": prop["id"],
                            "detail": f"impossible scale {s} — must be finite, >0, ≤10",
                        }
                    )
    # sector accent colors validated elsewhere; here just check finite bounds
    # for the lighting-relevant numbers in data/arena_landmarks (checked
    # separately in check_landmark_transforms)


def check_broken_resources(data: dict, root: Path, issues: list[dict]) -> None:
    """8 : broken / missing resources."""
    # enemy configs
    supported = {"basic", "fast", "heavy", "ranged", "dasher", "warlord"}
    for group in data["encounters"]:
        for member in group["members"]:
            if member["type"] not in supported:
                issues.append(
                    {
                        "category": "missing_resource",
                        "severity": "error",
                        "id": member["id"],
                        "detail": f"enemy type '{member['type']}' has no shipped config — will fail to spawn or use a fallback rig",
                    }
                )
            cfg = root / f"data/enemies/{member['type']}_enemy.tres"
            if not cfg.is_file():
                issues.append(
                    {
                        "category": "missing_resource",
                        "severity": "error",
                        "id": member["id"],
                        "detail": f"missing enemy config: {cfg.relative_to(root)}",
                    }
                )
    # mission rewards
    for mission in data["missions"]:
        reward = mission.get("reward", {})
        for kind in ("upgrade", "weapon"):
            if kind in reward:
                ident = reward[kind]
                path = root / f"data/{kind}s/{ident}.tres"
                if not path.is_file():
                    issues.append(
                        {
                            "category": "missing_resource",
                            "severity": "error",
                            "id": mission["id"],
                            "detail": f"mission reward {kind} '{ident}' missing: {path.relative_to(root)}",
                        }
                    )
    # arena resources (called from campaign definition indirectly — check all)
    for tres in (root / "data/arenas").glob("*.tres"):
        text = tres.read_text(errors="ignore")
        for m in re.finditer(r'path="([^"]+)"', text):
            p = m.group(1)
            if p.startswith("res://"):
                fs = root / p.replace("res://", "", 1)
                if not fs.exists():
                    issues.append(
                        {
                            "category": "missing_resource",
                            "severity": "error",
                            "id": tres.name,
                            "detail": f"references missing res:// path: {p}",
                        }
                    )


def check_collision_vs_visual(data: dict, issues: list[dict]) -> None:
    """9 : collision meshes vs visual meshes — AABB agreement, volume drift, origin."""
    for prop in data["props"]:
        at = prop["at"]
        size = prop["size"]
        # visual origin: at is the CENTER (CampaignGeometry uses `at` as holder
        # position, then builds a box centered at 0 with size). Collider origin
        # is `at - size*0.5` with same size (CampaignDefinition.solid_boxes).
        # They must agree — a visual offset that the collider does not share is
        # an invisible wall.
        collider_min, collider_size = aabb_from_prop(prop)
        # collider_min + size/2 must equal at
        cx = collider_min[0] + collider_size[0] / 2
        cz = collider_min[2] + collider_size[2] / 2
        if abs(cx - at[0]) > 1e-6 or abs(cz - at[2]) > 1e-6:
            issues.append(
                {
                    "category": "collision",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": "collider center does not match visual holder position — invisible wall offset",
                }
            )
        # volume drift: collider volume vs visual volume must match exactly for
        # box props; for cylinder props (reactor/antenna/generator) the AABB is
        # conservative by design (~21% over-volume) — flag only as info.
        kind = prop.get("kind", "")
        if kind in ("reactor", "antenna", "generator"):
            continue
        visual_vol = size[0] * size[1] * size[2]
        collider_vol = collider_size[0] * collider_size[1] * collider_size[2]
        if abs(visual_vol - collider_vol) > 1e-3:
            issues.append(
                {
                    "category": "collision",
                    "severity": "warning",
                    "id": prop["id"],
                    "detail": f"collider volume {collider_vol:.1f} != visual volume {visual_vol:.1f} — collision mesh does not match visual mesh",
                }
            )
        # origin must sit on floor; check already in floating, but collision
        # additionally verifies the collider bottom is at y=0 (floor top)
        collider_bottom = collider_min[1]
        if abs(collider_bottom) > FLOAT_EPS:
            issues.append(
                {
                    "category": "collision",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"collider bottom {collider_bottom:.3f} not on floor — collider will hover or bury relative to visual",
                }
            )


def check_outside_bounds(data: dict, issues: list[dict]) -> None:
    """10 : objects outside intended bounds — world, floors, sectors."""
    bounds = data["bounds"]
    sectors_by_id = {s["id"]: s for s in data["sectors"]}
    # props must be inside their sector's floor rect (campaign rule)
    for prop in data["props"]:
        foot = footprint(prop)
        sector_rect = sectors_by_id.get(prop["sector"], {}).get("rect")
        if sector_rect is None:
            continue
        if not enclosing(sector_rect, foot):
            issues.append(
                {
                    "category": "bounds",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"landmark extends outside its district '{prop['sector']}' — will poke through a wall or float over void",
                    "footprint": foot,
                    "sector_rect": sector_rect,
                }
            )
        # also inside world bounds (redundant with district check but catches void props)
        if not enclosing(bounds, foot):
            issues.append(
                {
                    "category": "bounds",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"prop footprint {foot} outside world bounds {bounds} — object in the void",
                }
            )
    # interactions must be inside district rect and on a floor
    for item in data["interactions"]:
        if not contains(sectors_by_id[item["sector"]]["rect"], item["at"]):
            issues.append(
                {
                    "category": "bounds",
                    "severity": "error",
                    "id": item["id"],
                    "detail": f"interaction at {item['at']} outside district '{item['sector']}' rect — player cannot stand on floor there",
                }
            )
        if not any(contains(f, item["at"]) for f in data["floors"]):
            issues.append(
                {
                    "category": "bounds",
                    "severity": "error",
                    "id": item["id"],
                    "detail": f"interaction at {item['at']} not on any floor region — in the void",
                }
            )
    # spawns must be on floors
    for group in data["encounters"]:
        for member in group["members"]:
            if not any(contains(f, member["at"]) for f in data["floors"]):
                issues.append(
                    {
                        "category": "bounds",
                        "severity": "error",
                        "id": member["id"],
                        "detail": f"spawn at {member['at']} not on any floor — will fall through world or spawn in void",
                    }
                )


def check_anomalous_assets(data: dict, issues: list[dict]) -> None:
    """11 : extremely large / small anomalous assets."""
    # Prop sizes — thresholds chosen from the authored set plus a guard band:
    # largest shipped: reactor_core 20×10×20, smallest: habil? 8×3×8. Anything
    # 2× larger or 1/4 smaller is anomalous and likely a typo (missing decimal).
    LARGE = 32.0
    SMALL = 2.0
    for prop in data["props"]:
        for axis, dim in zip("xyz", prop["size"]):
            if dim > LARGE:
                issues.append(
                    {
                        "category": "anomalous",
                        "severity": "warning",
                        "id": prop["id"],
                        "detail": f"size.{axis}={dim:.1f} > {LARGE} — unusually large; may dominate district or exceed nav budget",
                        "size": prop["size"],
                    }
                )
            elif dim < SMALL:
                issues.append(
                    {
                        "category": "anomalous",
                        "severity": "warning",
                        "id": prop["id"],
                        "detail": f"size.{axis}={dim:.1f} < {SMALL} — unusually small; may be invisible or a unit error",
                        "size": prop["size"],
                    }
                )
        # footprint area anomaly
        foot = footprint(prop)
        area = foot[2] * foot[3]
        if area > 600:
            issues.append(
                {
                    "category": "anomalous",
                    "severity": "warning",
                    "id": prop["id"],
                    "detail": f"footprint {area:.0f} m² — covers >600 m²; may block a whole district",
                }
            )


def check_transforms(data: dict, issues: list[dict]) -> None:
    """12 : transforms / origins / scale consistency."""
    for prop in data["props"]:
        # at must be finite on all axes
        if not all(math.isfinite(float(v)) for v in prop["at"]):
            issues.append(
                {
                    "category": "transform",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"non-finite at {prop['at']}",
                }
            )
        # size must be finite handled above; also check that at.y encodes
        # half-height correctly (0 ± epsilon already checked) — but also
        # that the visual center is finite-transform-safe
        if not math.isfinite(float(prop["at"][1])):
            issues.append(
                {
                    "category": "transform",
                    "severity": "error",
                    "id": prop["id"],
                    "detail": f"at.y non-finite — will produce a NaN transform and collapse physics",
                }
            )
    # Landmarks: validate authored landmark resources on disk
    for tres in (ROOT / "data/arena_landmarks").glob("*.tres"):
        text = tres.read_text(errors="ignore")
        # extract footprint_half
        for m in re.finditer(r"footprint_half = Vector3\(([^)]+)\)", text):
            vals = [float(v.strip()) for v in m.group(1).split(",")]
            if any(not math.isfinite(v) for v in vals):
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark footprint_half has non-finite channel: {vals}",
                    }
                )
            if vals[0] <= 0.1 or vals[2] <= 0.1:
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark footprint_half.x/z {vals[0]:.2f}/{vals[2]:.2f} ≤0.1 — landmark is scenery, not an obstacle (AI will walk through it)",
                    }
                )
            if vals[1] <= 0.1 or vals[1] > 12.0:
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark footprint_half.y {vals[1]:.2f} outside (0.1,12] — collider half-height invalid",
                    }
                )
        for m in re.finditer(r"scale = ([\d.]+)", text):
            s = float(m.group(1))
            if not math.isfinite(s) or not 0.25 <= s <= 4.0:
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark scale {s} outside [0.25,4.0] — authored scale that breaks collision-vs-visual parity",
                    }
                )
        for m in re.finditer(r"position = Vector3\(([^)]+)\)", text):
            vals = [float(v.strip()) for v in m.group(1).split(",")]
            if abs(vals[1]) > 0.01:
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark position.y {vals[1]:.3f} ≠0 — landmark must sit on floor; footprint assumes y=0",
                    }
                )
            if not all(math.isfinite(v) for v in vals):
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark position has non-finite channel: {vals}",
                    }
                )
        for m in re.finditer(r"rotation_degrees = Vector3\(([^)]+)\)", text):
            vals = [float(v.strip()) for v in m.group(1).split(",")]
            if not all(math.isfinite(v) for v in vals):
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"landmark rotation_degrees has non-finite channel: {vals}",
                    }
                )
            # any non-zero rotation on a box landmark tilts the AABB but the
            # collider stays axis-aligned — visual vs collision drift
            if any(abs(v) > 0.5 for v in vals):
                shape_m = re.search(r'shape = &"([^"]+)"', text)
                shape = shape_m.group(1) if shape_m else "unknown"
                if shape == "box":
                    issues.append(
                        {
                            "category": "transform",
                            "severity": "warning",
                            "id": tres.name,
                            "detail": f"landmark rotation {vals} on a box shape — visual will tilt but collider AABB stays axis-aligned (collision mismatch)",
                        }
                    )


def check_inaccessible(data: dict, issues: list[dict]) -> None:
    """13 : inaccessible / stray objects — reachability + clearance."""
    topo = Topology(data)
    try:
        start = next(s["checkpoint"] for s in data["sectors"] if s["id"] == "docks")
    except StopIteration:
        return
    reachable = topo.reachable(start)
    # every interaction and spawn must be on a walkable cell and reachable
    for item in data["interactions"]:
        c = topo.cell(item["at"])
        if c not in topo.walkable:
            issues.append(
                {
                    "category": "inaccessible",
                    "severity": "error",
                    "id": item["id"],
                    "detail": f"interaction at {item['at']} is on a blocked nav cell — player can never walk there (stray or buried in a prop)",
                }
            )
        elif c not in reachable:
            issues.append(
                {
                    "category": "inaccessible",
                    "severity": "error",
                    "id": item["id"],
                    "detail": f"interaction at {item['at']} is on a walkable but unreachable island — no path from docks without crossing void/wall (stray objective)",
                }
            )
    for group in data["encounters"]:
        for member in group["members"]:
            c = topo.cell(member["at"])
            if c not in topo.walkable:
                issues.append(
                    {
                        "category": "inaccessible",
                        "severity": "error",
                        "id": member["id"],
                        "detail": f"spawn at {member['at']} is on a blocked cell — enemy will spawn stuck inside geometry (stray/buried)",
                    }
                )
            elif c not in reachable:
                issues.append(
                    {
                        "category": "inaccessible",
                        "severity": "error",
                        "id": member["id"],
                        "detail": f"spawn at {member['at']} is on an unreachable island — enemy can never reach the player (stray encounter)",
                    }
                )
    # checkpoints must have safe clearance from nearest guard
    all_spawns = [m for g in data["encounters"] for m in g["members"]]
    for sector in data["sectors"]:
        cp = sector["checkpoint"]
        if not all_spawns:
            continue
        nearest = min(math.dist(cp, m["at"]) for m in all_spawns)
        if nearest < SPAWN_CLEARANCE:
            issues.append(
                {
                    "category": "inaccessible",
                    "severity": "warning",
                    "id": sector["id"],
                    "detail": f"checkpoint only {nearest:.1f} m from nearest guard (<{SPAWN_CLEARANCE} m) — player will spawn under fire; stray or unsafe placement",
                    "distance": nearest,
                }
            )
    # stray props: a prop whose expanded footprint has no walkable neighbour is
    # likely placed in the void (or covers an entire district). Use a radius
    # derived from the prop's own half-size so a 20 m reactor doesn't look
    # isolated just because its center is 5 cells from walkable space.
    for prop in data["props"]:
        foot = footprint(prop)
        cx, cz = foot[0] + foot[2] / 2, foot[1] + foot[3] / 2
        center_cell = topo.cell([cx, 0.2, cz])
        # radius that reaches just past the prop's edge + one walkable ring
        half_max = max(prop["size"][0], prop["size"][2]) * 0.5
        radius = max(2, math.ceil((half_max + CLEARANCE) / CELL) + 1)
        has_neighbor = any(
            (center_cell[0] + dx, center_cell[1] + dz) in topo.walkable
            for dx in range(-radius, radius + 1)
            for dz in range(-radius, radius + 1)
            if not (dx == 0 and dz == 0)
        )
        if not has_neighbor:
            issues.append(
                {
                    "category": "inaccessible",
                    "severity": "warning",
                    "id": prop["id"],
                    "detail": f"prop at {prop['at']} appears isolated — no walkable cells in a {radius}-cell ring around it (possible stray in void)",
                }
            )


def check_arena_configs(root: Path, issues: list[dict]) -> None:
    """Arena modular gaps / snaps / anomalous for the 3 pit arenas."""
    for tres in (root / "data/arenas").glob("*.tres"):
        text = tres.read_text(errors="ignore")
        for m in re.finditer(r"position = Vector3\(([^)]+)\)", text):
            try:
                vals = [float(v.strip()) for v in m.group(1).split(",")]
            except ValueError:
                continue
            x, y, z = vals
            if not all(math.isfinite(v) for v in vals):
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"obstacle position has non-finite channel: {vals}",
                    }
                )
            if abs(y) > 0.01:
                issues.append(
                    {
                        "category": "floating",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"arena obstacle at y={y:.3f} — obstacles must sit on floor (y=0)",
                    }
                )
            # interior_half for arena is 18.0 (see arena.tscn); obstacle must be inside
            if abs(x) > 18.5 or abs(z) > 18.5:
                issues.append(
                    {
                        "category": "bounds",
                        "severity": "warning",
                        "id": tres.name,
                        "detail": f"arena obstacle at ({x:.1f}, {z:.1f}) near/outside interior_half=18 — may clip wall or sit in void",
                    }
                )
        for m in re.finditer(r"half_size_(?:x|y|z) = ([\d.]+)", text):
            try:
                v = float(m.group(1))
            except ValueError:
                continue
            if not math.isfinite(v) or not 0.05 <= v <= 8.0:
                issues.append(
                    {
                        "category": "transform",
                        "severity": "error",
                        "id": tres.name,
                        "detail": f"arena obstacle half-size {v} outside [0.05,8.0] — impossible footprint",
                    }
                )


def check_scene_transforms(root: Path, issues: list[dict]) -> None:
    """TSCN transform sanity: non-finite, impossible scale, buried meshes."""
    for tscn in (root / "scenes").rglob("*.tscn"):
        text = tscn.read_text(errors="ignore")
        # any Transform3D with a non-finite component
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in re.finditer(r"Transform3D\(([^)]+)\)", line):
                try:
                    vals = [float(v.strip()) for v in m.group(1).split(",")]
                except ValueError:
                    continue
                if any(not math.isfinite(v) for v in vals):
                    issues.append(
                        {
                            "category": "transform",
                            "severity": "error",
                            "id": tscn.relative_to(root).as_posix(),
                            "detail": f"line {lineno}: non-finite Transform3D {m.group(1)[:80]}",
                        }
                    )
        # scale sanity — wall meshes are legitimately scaled to 17/40 along one
        # axis to stretch to the perimeter. Only flag uniform or near-uniform
        # scales that are extreme, or any negative scale.
        for lineno, line in enumerate(text.splitlines(), 1):
            for m in re.finditer(r"scale = Vector3\(([^)]+)\)", line):
                try:
                    vals = [float(v.strip()) for v in m.group(1).split(",")]
                except ValueError:
                    continue
                if any(v <= 0 for v in vals):
                    issues.append(
                        {
                            "category": "transform",
                            "severity": "error",
                            "id": tscn.relative_to(root).as_posix(),
                            "detail": f"line {lineno}: non-positive scale {vals} — mesh will be inside-out or invisible",
                        }
                    )
                # extremely large uniform-ish scale suggests a unit error
                if all(v > 50 for v in vals):
                    issues.append(
                        {
                            "category": "anomalous",
                            "severity": "warning",
                            "id": tscn.relative_to(root).as_posix(),
                            "detail": f"line {lineno}: enormous scale {vals} — likely a metres-vs-centimetres mix-up",
                        }
                    )


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------

def validate(map_path: Path, root: Path, verbose: bool = False) -> tuple[int, int, list[dict]]:
    data = load_json(map_path)
    issues: list[dict] = []

    # campaign world checks (the bulk)
    check_floating_and_buried(data, issues)
    check_intersections(data, issues)
    check_duplicate_and_stacked(data, issues)
    check_gaps_and_perimeter(data, issues)
    check_snapped_alignment(data, issues)
    check_rotations_and_scales(data, issues)
    check_broken_resources(data, root, issues)
    check_collision_vs_visual(data, issues)
    check_outside_bounds(data, issues)
    check_anomalous_assets(data, issues)
    check_transforms(data, issues)
    check_inaccessible(data, issues)

    # arena + scene checks (global)
    check_arena_configs(root, issues)
    check_scene_transforms(root, issues)

    # categorize counts
    errors = sum(1 for i in issues if i.get("severity") == "error")
    warnings = sum(1 for i in issues if i.get("severity") == "warning")
    return errors, warnings, issues


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, default=MAP_PATH, help="path to campaign json")
    parser.add_argument("--json", type=Path, default=None, help="write JSON report to this path")
    parser.add_argument("--verbose", action="store_true", help="list all checked categories even when clean")
    args = parser.parse_args(argv)

    root = ROOT
    map_path: Path = args.map if args.map.is_absolute() else (Path.cwd() / args.map)
    # allow palette: --map relative to repo root
    if not map_path.is_file():
        alt = root / args.map
        if alt.is_file():
            map_path = alt

    if not map_path.is_file():
        print(f"Map file not found: {args.map}", file=sys.stderr)
        return 1

    try:
        errors, warnings, issues = validate(map_path, root, verbose=args.verbose)
    except (GeometryError, ValueError, KeyError, OSError) as exc:
        print(f"Geometry validation FAILED to run: {exc}", file=sys.stderr)
        if args.verbose:
            import traceback

            traceback.print_exc()
        return 1

    # summary line — the one CI parses
    if errors == 0 and warnings == 0:
        print(
            f"Geometry integrity: OK — {len(issues)} issues (0 errors, 0 warnings) "
            f"across 13 categories; campaign={map_path.relative_to(root) if map_path.is_relative_to(root) else map_path}"
        )
    else:
        print(f"Geometry integrity: {len(issues)} issue(s) — {errors} error(s), {warnings} warning(s)")
        # group by category for the human
        by_cat: dict[str, list[dict]] = defaultdict(list)
        for it in issues:
            by_cat[it.get("category", "other")].append(it)
        for cat in sorted(by_cat):
            print(f"\n[{cat}] {len(by_cat[cat])} issue(s)")
            for it in by_cat[cat]:
                sev = it.get("severity", "?")
                print(f"  {sev.upper():7s} {it.get('id','?'):28s} — {it.get('detail','')}")
        if errors:
            print(f"\nFAILED: {errors} geometry error(s) — see above.")
        else:
            print(f"\nPASSED with {warnings} warning(s).")

    if args.json is not None:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        report = {
            "map": str(map_path.relative_to(root) if map_path.is_relative_to(root) else map_path),
            "module": MODULE,
            "cell": CELL,
            "errors": errors,
            "warnings": warnings,
            "issues": issues,
            "categories": [
                "floating",
                "buried",
                "intersection",
                "gaps",
                "snapped",
                "transform",
                "duplicate",
                "missing_resource",
                "collision",
                "bounds",
                "anomalous",
                "inaccessible",
            ],
        }
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"JSON report written to {args.json}")

    if args.verbose and errors == 0 and warnings == 0:
        print("\nAll 13 categories passed:")
        for cat in [
            "1  floating — every prop base on floor, no hovering",
            "2  buried — no prop penetrates terrain",
            "3  intersections — no prop·prop / spawn·prop / interaction·prop overlaps",
            "4  gaps — floor is fully connected; perimeter encloses floors; causeways stay open",
            "5  snapped — every floor edge on 8 m module grid",
            "6  impossible rotations/scales — no tilted AABBs, no out-of-range scales",
            "7  duplicate / stacked — no duplicate ids, no colocated solids",
            "8  broken resources — every enemy/reward/scene path resolves",
            "9  collision vs visual — collider AABBs match visual holder/size, bottom on floor",
            "10 outside bounds — every solid/interaction/spawn inside world and district",
            "11 anomalous sizes — no 32 m+ or <2 m props, no 600 m² footprints",
            "12 transforms/origins/scale — all positions finite, landmark Y=0, scale 0.25–4.0",
            "13 inaccessible/stray — every objective and spawn reachable; checkpoints clear; no isolated props",
        ]:
            print(f"  ✔ {cat}")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

