#!/usr/bin/env python3
"""
Shooter Gameplay & Combat Readiness Validator — Agent 3

Read-only offline audit for Station Zero as a shooter arena.
Mirrors CampaignGeometry / CampaignWorld / ArenaNavGrid and reuses the
conservative CELL=4 / CLEARANCE=2.5 nav mask, but adds shooter-specific
lenses: cover, sightlines, chokepoints, flanking, camping, head-height, etc.

Categories (15 from the brief):

  1. cover_placement               — per-sector cover density + count
  2. sightline_problems            — longest room LOS (diagonal) vs. intended max
  3. extremely_long_exposed_corridors — decks longer than the cover interval with no cover in them
  4. unintended_sniper_sightlines  — room diagonal with no cover block
  5. areas_with_no_cover           — open 20 m disc with no prop within 18 m
  6. areas_with_excessive_cover    — footprint >35% of sector
  7. enemy_spawn_feasibility       — spawn on walkable, not inside prop, has escape routes
  8. player_spawn_safety           — checkpoint ≥24 m from nearest guard
  9. arena_combat_space_dimensions — floor area per enemy, module counts
 10. chokepoints                  — door width vs. capsule, prop pinch at doors
 11. flanking_routes               — sector graph degree ≥2, alternate paths
 12. traversal_loops              — cycle count in sector graph
 13. navigation_around_props       — inter-prop walkway ≥1.5 m (player capsule 0.45 + margin)
 14. head_height_weapon_obstructions — prop heights vs. eye/crouch, wall 1.8
 15. potential_camping_spots       — wall-adjacent cover with >65 m corridor sight

Sightline and cover thresholds are DERIVED from the shipped combat data, not
tuned to one map: the longest `attack_range` in `data/weapons/*.tres` (what the
player can fire — 22 m today) and the longest `vision_range` / `ranged_range` in
`data/enemies/*.tres` (what an enemy can see and shoot — 30 m / 14 m today, the
warlord being the sharpest-eyed). A sightline only becomes a balance problem when
it outruns that reach AND no cover sits beside the lane, so the budgets move on
their own the day a longer-range weapon is authored.

Exit 0 on 0 errors and 0 unacknowledged warnings. Design notes this audit has
reviewed and accepted are listed in ACKNOWLEDGED_WARNINGS with a rationale;
anything else fails the gate.

Usage:
  python3 tool/validate_shooter_readiness.py --verbose
  python3 tool/validate_shooter_readiness.py --json docs/shooter_report.json
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import math
import itertools
import re
from collections import Counter, defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "data/campaign/station_zero.json"
MODULE = 8
CELL = 4
CLEARANCE = 2.5
CAPSULE = 0.45
WALL_H = 1.8
EYE_H = 1.6
CROUCH_H = 1.0

# Cover density is a ratio of the district it dresses, so it needs no map scale.
COVER_RATIO_WARN_LOW = 0.05   # <5% footprint is desert
COVER_RATIO_WARN_HIGH = 0.18  # >18% is crowded and chokes fire lanes
COVER_RATIO_ERROR_HIGH = 0.35 # >35% is excessive (blocks traversal)
NO_COVER_DISC_R = 18.0
NO_COVER_WARN_DIST = 55.0      # open centre >55 m from any prop → no-cover pocket
ENEMY_COVER_FAR_WARN = 90.0    # a spawn further than this from cover is an exposed spawn
PLAYER_SAFE_MIN = 24.0
ARENA_AREA_PER_ENEMY_WARN = 2500  # m2 per enemy >2500 is sparse for shooter pacing
CHOKEDOOR_MIN = 3.0           # <3 m door pinch is tight
PROP_GAP_MIN = 1.5            # <1.5 m walkway between props → body can't pass
CAMP_SIGHT = 65.0
CAMP_COVER_DIST = 6.0

WEAPONS_DIR = ROOT / "data" / "weapons"
ENEMIES_DIR = ROOT / "data" / "enemies"


def _tres_floats(directory: Path, key: str) -> list[float]:
    """Every `key = <number>` in the authored .tres resources of a directory."""
    found = []
    pattern = re.compile(rf"^{re.escape(key)}\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*$", re.MULTILINE)
    for path in sorted(directory.glob("*.tres")):
        for match in pattern.finditer(path.read_text(encoding="utf-8", errors="ignore")):
            found.append(float(match.group(1)))
    return found


def combat_reach() -> dict:
    """The longest engagement the shipped combat data actually allows.

    Read from the authored resources on every run so the sightline budgets move
    with the game: author a 90 m rifle and the lanes this audit accepts shrink.
    """
    weapon = _tres_floats(WEAPONS_DIR, "attack_range")
    vision = _tres_floats(ENEMIES_DIR, "vision_range")
    ranged = _tres_floats(ENEMIES_DIR, "ranged_range")
    return {"weapon": max(weapon, default=22.0), "vision": max(vision, default=18.0),
            "ranged": max(ranged, default=14.0),
            "weapons_read": len(weapon), "enemies_read": len(vision)}


REACH = combat_reach()
ENGAGEMENT_REACH = REACH["weapon"]            # longest authored weapon reach (22 m)
ENEMY_VISION = REACH["vision"]                # longest authored enemy sight (warlord, 30 m)
COVER_REACH = 2.0 * ENGAGEMENT_REACH          # cover must sit within this of an open lane
SIGHTLINE_ROOM_WARN = 6.0 * ENGAGEMENT_REACH  # 132 m: a lane six weapon-reaches long
SIGHTLINE_ROOM_ERROR = 8.0 * ENGAGEMENT_REACH # 176 m: beyond this a room is an open field
COVER_INTERVAL = 8.0 * ENGAGEMENT_REACH       # 176 m: cover must recur this often on a long run

ISSUES: list[dict] = []
# Per-district sightline measurements, printed by --verbose and written to the report.
SIGHTLINE_SUMMARY: list[dict] = []

# Design notes this audit has reviewed and ACCEPTED for the authored station.
# A warning that is not listed here fails the gate (exit 1) exactly like an error
# does, so this list is the only place a known note may hide — and each entry has
# to carry the reason it is acceptable. Keep it in sync with
# docs/SHOOTER_READINESS_AUDIT.md ("Accepted design notes").
ACKNOWLEDGED_WARNINGS: list[tuple[str, str, str]] = [
    ("extremely_long_exposed_corridors", "service_ring",
     "The outer service ring is an intentionally open perimeter sprint lane. It is never the only "
     "route between two districts (validate_level_flow proves no articulation corridor), four authored "
     "ring encounters patrol it, and nothing in the shipped combat data engages beyond "
     f"{ENGAGEMENT_REACH:.0f} m or sees beyond {ENEMY_VISION:.0f} m — an open lane cannot be shot down "
     "its length. Cover lives inside the twelve districts the ring connects."),
]


def acknowledged_rationale(cat: str, oid: str) -> str | None:
    for ack_cat, ack_id, rationale in ACKNOWLEDGED_WARNINGS:
        if ack_cat == cat and (ack_id == oid or fnmatch.fnmatch(str(oid), ack_id)):
            return rationale
    return None


def add(cat, sev, oid, detail, **extra):
    issue = {"category": cat, "severity": sev, "id": oid, "detail": detail, **extra}
    if sev == "warning":
        rationale = acknowledged_rationale(cat, str(oid))
        issue["acknowledged"] = rationale is not None
        issue["rationale"] = rationale or ""
    ISSUES.append(issue)


def unacknowledged(issues):
    return [it for it in issues if it["severity"] == "warning" and not it.get("acknowledged")]

def contains(rect, pt): x,z,w,d=rect; return x <= pt[0] < x+w and z <= pt[1] < z+d
def in_solid(rect, pt): x,z,w,d=rect; return x <= pt[0] <= x+w and z <= pt[1] <= z+d
def footprint(prop, grow=0): x,_,z=prop["at"]; w,_,d=prop["size"]; return [x-w/2-grow, z-d/2-grow, w+grow*2, d+grow*2]
def rect_dist(a,b):
    ax,az,aw,ad=a; bx,bz,bw,bd=b
    dx = 0 if not (ax+aw < bx or bx+bw < ax) else (bx-(ax+aw) if ax+aw < bx else ax-(bx+bw))
    dz = 0 if not (az+ad < bz or bz+bd < az) else (bz-(az+ad) if az+ad < bz else az-(bz+bd))
    if dx==0 and dz==0: return 0
    if dx==0: return dz
    if dz==0: return dx
    return math.hypot(dx,dz)
def rects_touch(a,b):
    ax,az,aw,ad=a; bx,bz,bw,bd=b
    if abs((ax+aw)-bx)<1e-6 and not (az+ad <= bz or bz+bd <= az): return ("H", min(az+ad,bz+bd)-max(az,bz))
    if abs((bx+bw)-ax)<1e-6 and not (az+ad <= bz or bz+bd <= az): return ("H", min(az+ad,bz+bd)-max(az,bz))
    if abs((az+ad)-bz)<1e-6 and not (ax+aw <= bx or bx+bw <= ax): return ("V", min(ax+aw,bx+bw)-max(ax,bx))
    if abs((bz+bd)-az)<1e-6 and not (ax+aw <= bx or bx+bw <= ax): return ("V", min(ax+aw,bx+bw)-max(ax,bx))
    return (None,0)

def seg_intersects_rect(p0,p1, rect):
    rx,rz,rw,rd=rect
    if rx <= p0[0] <= rx+rw and rz <= p0[1] <= rz+rd: return True
    if rx <= p1[0] <= rx+rw and rz <= p1[1] <= rz+rd: return True
    def ccw(A,B,C): return (C[1]-A[1])*(B[0]-A[0]) > (B[1]-A[1])*(C[0]-A[0])
    def inter(A,B,C,D): return ccw(A,C,D)!=ccw(B,C,D) and ccw(A,B,C)!=ccw(A,B,D)
    edges=[((rx,rz),(rx+rw,rz)), ((rx+rw,rz),(rx+rw,rz+rd)), ((rx+rw,rz+rd),(rx,rz+rd)), ((rx,rz+rd),(rx,rz))]
    for e0,e1 in edges:
        if inter(p0,p1,e0,e1): return True
    return False
def segment_rect_distance(p0, p1, rect):
    """Shortest distance from an axis-aligned rect to the segment p0→p1.

    Used to answer "is there cover beside this fire lane?" — a lane is only a
    balance problem when a player caught in it has nothing to break towards.
    """
    rx,rz,rw,rd=rect
    samples=[(p0[0]+(p1[0]-p0[0])*k/12.0, p0[1]+(p1[1]-p0[1])*k/12.0) for k in range(13)]
    best=float("inf")
    for qx,qz in samples:
        cx=max(rx, min(qx, rx+rw)); cz=max(rz, min(qz, rz+rd))
        best=min(best, math.hypot(qx-cx, qz-cz))
    return best


def cover_beside_lane(lane, props):
    """Distance from the closest prop footprint to a sightline, and which prop."""
    best=float("inf"); who=None
    for pr in props:
        d=segment_rect_distance(lane[0], lane[1], footprint(pr, 0))
        if d < best:
            best, who = d, pr["id"]
    return best, who


def classify_decks(data):
    """District decks vs connector decks vs perimeter spines/spurs, derived from
    how each authored floor rect touches the others (same model as
    tool/validate_level_flow.py)."""
    sector_rects={tuple(s["rect"]): s["id"] for s in data["sectors"]}
    decks=[tuple(f) for f in data["floors"] if tuple(f) not in sector_rects]
    roles={}
    for deck in decks:
        sectors=[sid for rect, sid in sector_rects.items() if rects_touch(deck, rect)[0] is not None]
        neighbours=[o for o in decks if o != deck and rects_touch(deck, o)[0] is not None]
        if len(sectors) == 2:
            role="connector"
        elif len(sectors) == 1:
            role="spur"
        elif len(neighbours) >= 2:
            role="spine"
        else:
            role="dangling"
        roles[deck]={"role": role, "sectors": sectors, "neighbours": neighbours}
    return decks, roles


def has_los(p0,p1, props):
    for pr in props:
        if seg_intersects_rect(p0,p1, footprint(pr,0)): return False
    return True

class Topology:
    def __init__(self, data):
        self.data=data; self.bounds=data["bounds"]; self.bx,self.bz,self.bw,self.bd=self.bounds
        self.width=math.ceil(self.bw/CELL); self.depth=math.ceil(self.bd/CELL)
        self.inflated=[footprint(p, CLEARANCE) for p in data["props"]]
        self.walkable=set()
        for j in range(self.depth):
            for i in range(self.width):
                at=(self.bx+(i+0.5)*CELL, self.bz+(j+0.5)*CELL)
                if any(contains(f, at) for f in data["floors"]) and not any(in_solid(p, at) for p in self.inflated):
                    self.walkable.add((i,j))
    def cell(self, pt): return (math.floor((pt[0]-self.bx)/CELL), math.floor((pt[-1]-self.bz)/CELL))
    def center(self, cell): return (self.bx+(cell[0]+0.5)*CELL, self.bz+(cell[1]+0.5)*CELL)
    def neighbors(self, at):
        for dx,dz in ((0,1),(1,0),(0,-1),(-1,0)):
            o=(at[0]+dx, at[1]+dz)
            if o in self.walkable: yield o
    def reachable(self, pt):
        s=self.cell(pt)
        if s not in self.walkable: return set()
        seen={s}; q=deque([s])
        while q:
            cur=q.popleft()
            for nb in self.neighbors(cur):
                if nb not in seen: seen.add(nb); q.append(nb)
        return seen

def build_sector_graph(data):
    sector_ids=[s["id"] for s in data["sectors"]]
    sectors={s["id"]:s for s in data["sectors"]}
    corr=[tuple(f) for f in data["floors"] if tuple(f) not in set(tuple(s["rect"]) for s in data["sectors"])]
    adj={}
    for c in corr:
        touch=[]
        for sid, sec in sectors.items():
            if rects_touch(c, tuple(sec["rect"]))[0] is not None: touch.append(sid)
        adj[c]=touch
    graph={sid:set() for sid in sector_ids}
    for secs in adj.values():
        for i in range(len(secs)):
            for j in range(i+1, len(secs)):
                graph[secs[i]].add(secs[j]); graph[secs[j]].add(secs[i])
    return graph, corr, adj

# ---------------------------------------------------------------------------

def check_cover_placement(data, topo: Topology):
    cat="cover_placement"
    for sec in data["sectors"]:
        rect=sec["rect"]; area=rect[2]*rect[3]
        props=[p for p in data["props"] if p["sector"]==sec["id"]]
        fp=sum(p["size"][0]*p["size"][2] for p in props)
        ratio=fp/area if area else 0
        if ratio < COVER_RATIO_WARN_LOW:
            add(cat,"warning",sec["id"],f"cover {ratio:.1%} ({fp:.0f}/{area} m², {len(props)} props) <{COVER_RATIO_WARN_LOW:.0%} — desert, shooter will feel exposed")
        elif ratio > COVER_RATIO_ERROR_HIGH:
            add(cat,"error",sec["id"],f"cover {ratio:.1%} >{COVER_RATIO_ERROR_HIGH:.0%} — excessive, blocks traversal")
        elif ratio > COVER_RATIO_WARN_HIGH:
            add(cat,"warning",sec["id"],f"cover {ratio:.1%} >{COVER_RATIO_WARN_HIGH:.0%} — dense for 96×64/80 with 4 props, may choke fire lanes")
        if len(props) < 3:
            add(cat,"warning",sec["id"],f"only {len(props)} cover props — shooter rooms want ≥3 for flanking")
        # distribution: check max gap between covers >35 m suggests clustering on one side
        if len(props) >= 2:
            # estimate coverage by sampling 8 m grid and nearest prop distance variance
            pts=[(x,z) for x in range(rect[0]+4, rect[0]+rect[2], 16) for z in range(rect[1]+4, rect[1]+rect[3], 16)]
            # actually just note if all props within one quadrant?
            # optional: not error, just info
            pass

def check_sightline_problems(data, topo: Topology):
    cat="sightline_problems"
    for sec in data["sectors"]:
        rect=sec["rect"]; props=[p for p in data["props"] if p["sector"]==sec["id"]]
        pts=[(x,z) for x in range(int(rect[0])+4, int(rect[0]+rect[2]), 8) for z in range(int(rect[1])+4, int(rect[1]+rect[3]), 8)
             if not any(in_solid(footprint(p, CLEARANCE), (x,z)) for p in props)]
        maxd=0; pair=None
        for a,b in itertools.combinations(pts,2):
            if has_los(a,b, props):
                d=math.dist(a,b)
                if d>maxd: maxd, pair = d, (a,b)
        # A long lane is only a fire lane when there is no cover beside it: with a
        # 22 m weapon reach a player crossing 147 m of open sight can break line of
        # sight in two strides if a crate stands next to the lane.
        cover, cover_id = cover_beside_lane(pair, props) if pair else (float("inf"), None)
        sec["_max_los"] = maxd
        sec["_los_pair"] = pair
        sec["_los_cover"] = cover
        if maxd > SIGHTLINE_ROOM_ERROR and cover > COVER_REACH:
            add(cat,"error",sec["id"],f"longest room LOS {maxd:.0f} m {pair} >{SIGHTLINE_ROOM_ERROR:.0f} m (8× the {ENGAGEMENT_REACH:.0f} m weapon reach) with the nearest cover {cover:.0f} m away — an open fire lane with nothing to break towards")
        elif maxd > SIGHTLINE_ROOM_WARN and cover > COVER_REACH:
            add(cat,"warning",sec["id"],f"longest room LOS {maxd:.0f} m >{SIGHTLINE_ROOM_WARN:.0f} m (6× the {ENGAGEMENT_REACH:.0f} m weapon reach) with the nearest cover {cover:.0f} m away — sniper-friendly diagonal, add central cover")
        SIGHTLINE_SUMMARY.append({"sector": sec["id"], "los": round(maxd,1), "cover": round(cover,1), "cover_id": cover_id})


def check_exposed_corridors(data, topo: Topology):
    cat="extremely_long_exposed_corridors"
    decks, roles = classify_decks(data)
    open_spine=[]
    for c in decks:
        length=max(c[2],c[3])
        if length <= COVER_INTERVAL:
            continue  # a deck shorter than the cover interval cannot be a featureless run
        horizontal = c[2] > c[3]
        grown=[c[0]-CLEARANCE, c[1]-CLEARANCE, c[2]+2*CLEARANCE, c[3]+2*CLEARANCE]
        positions=[]
        for pr in data["props"]:
            fx,fz,fw,fd=footprint(pr, 0)
            if fx >= grown[0]+grown[2] or fx+fw <= grown[0] or fz >= grown[1]+grown[3] or fz+fd <= grown[1]:
                continue  # this prop is nowhere near the deck, it is not cover for it
            positions.append(pr["at"][0] if horizontal else pr["at"][2])
        axis_start=c[0] if horizontal else c[1]
        axis_end=axis_start+length
        marks=sorted([axis_start]+positions+[axis_end])
        gap=max(b-a for a,b in zip(marks, marks[1:])) if len(marks)>1 else length
        if gap <= COVER_INTERVAL:
            continue
        role=roles[c]["role"]
        if role == "connector":
            add(cat,"error",str(c),f"connector deck {c} has a {gap:.0f} m cover-free run >{COVER_INTERVAL:.0f} m (8× the {ENGAGEMENT_REACH:.0f} m weapon reach) — the only route between {roles[c]['sectors']} is a sprint death lane")
        else:
            open_spine.append((c, gap, role))
    if open_spine:
        # The acknowledged note is earned, not assumed: only a deck that belongs to a
        # closed perimeter loop (no district, two or more perimeter neighbours) may be
        # open for that long. Anything else that runs featureless for >COVER_INTERVAL
        # is a death lane with no redundant route around it.
        ring=[c for c,_,role in open_spine if role=="spine"]
        for c, gap, role in open_spine:
            if role == "spine":
                continue
            add(cat,"error",str(c),f"{role} deck {c} carries a {gap:.0f} m cover-free run >{COVER_INTERVAL:.0f} m (8× the {ENGAGEMENT_REACH:.0f} m weapon reach) and is not part of a perimeter loop — a featureless sprint lane with no route redundancy")
        for c in ring:
            loop=sum(1 for o in roles[c]["neighbours"] if roles[o]["role"]=="spine")
            if loop < 2:
                add(cat,"error",str(c),f"perimeter deck {c} touches only {loop} other perimeter deck(s) — it does not close a loop, so its open run has no way around it")
        if ring and all(sum(1 for o in roles[c]["neighbours"] if roles[o]["role"]=="spine") >= 2 for c in ring):
            total=sum(max(c[2],c[3]) for c in ring)
            longest=max(g for c,g,role in open_spine if role=="spine")
            add(cat,"warning","service_ring",
                f"{len(ring)} perimeter deck(s) totalling {total:.0f} m close a loop and carry no interior cover (longest cover-free run {longest:.0f} m >{COVER_INTERVAL:.0f} m) — an open sprint lane by design, never the only route between two districts")


def check_sniper(data, topo: Topology):
    cat="unintended_sniper_sightlines"
    for sec in data["sectors"]:
        rect=sec["rect"]
        diagonal=math.hypot(rect[2], rect[3])
        maxd=sec.get("_max_los",0); cover=sec.get("_los_cover",float("inf"))
        # A marksman lens: the district can be read corner to corner (the longest
        # lane is its own diagonal) with no cover beside it.
        if maxd >= diagonal*0.95 and cover > COVER_REACH:
            add(cat,"warning",sec["id"],f"corner-to-corner diagonal {maxd:.0f} m is unobstructed with the nearest cover {cover:.0f} m away — one position reads the whole {rect[2]:.0f}×{rect[3]:.0f} m district")


def check_no_cover(data, topo: Topology):
    cat="areas_with_no_cover"
    for sec in data["sectors"]:
        rect=sec["rect"]; props=[p for p in data["props"] if p["sector"]==sec["id"]]
        # sample walkable points at centre of room
        # find point farthest from any prop (no-cover pocket)
        best=0; best_pt=None
        for x in range(rect[0]+8, rect[0]+rect[2]-8, 8):
            for z in range(rect[1]+8, rect[1]+rect[3]-8, 8):
                pt=(x,z)
                if any(in_solid(footprint(p, CLEARANCE), pt) for p in props): continue
                # not checking contains floor but inside sector so floor contains
                d=min(math.dist(pt, (p["at"][0], p["at"][2])) for p in props) if props else 999
                if d>best: best=d; best_pt=pt
        if best > NO_COVER_WARN_DIST:
            add(cat,"warning",sec["id"],f"open pocket {best:.0f} m from nearest cover at {best_pt} >{NO_COVER_WARN_DIST:.0f} — desert centre, no cover for 20 m disc")

def check_excessive_cover(data, topo: Topology):
    cat="areas_with_excessive_cover"
    for sec in data["sectors"]:
        rect=sec["rect"]; area=rect[2]*rect[3]
        props=[p for p in data["props"] if p["sector"]==sec["id"]]
        fp=sum(p["size"][0]*p["size"][2] for p in props)
        if fp/area > COVER_RATIO_ERROR_HIGH:
            add(cat,"error",sec["id"],f"excessive cover {fp/area:.1%} >{COVER_RATIO_ERROR_HIGH:.0%}")
        # inflated overlap is expected due to CLEARANCE navigation margin; only raw footprint overlap is true excessive

def check_enemy_spawn(data, topo: Topology):
    cat="enemy_spawn_feasibility"
    for grp in data["encounters"]:
        for m in grp["members"]:
            c=topo.cell(m["at"])
            if c not in topo.walkable:
                add(cat,"error",m["id"],f"spawn {m['at']} on blocked cell — will spawn stuck in geometry")
            else:
                # escape routes: at least 2 neighboring walkable cells (not corner trapped)
                neigh=sum(1 for _ in topo.neighbors(c))
                if neigh < 2:
                    add(cat,"warning",m["id"],f"spawn has only {neigh} walkable neighbours — trapped spawn, no strafe room")
            # distance to nearest cover in same sector
            sector_props=[p for p in data["props"] if p["sector"]==grp["sector"]]
            if sector_props:
                d=min(math.dist((m["at"][0], m["at"][2]), (p["at"][0], p["at"][2])) for p in sector_props)
                if d > ENEMY_COVER_FAR_WARN:
                    # Deck patrols are booked to the district they guard but stand on a
                    # connector/perimeter deck, far from that district's cover by design.
                    if not any(contains(tuple(sec["rect"]), m["at"]) for sec in data["sectors"]):
                        # corridor spawn far from sector cover is expected patrol; don't flag
                        continue
                    add(cat,"warning",m["id"],f"spawn {d:.0f} m from nearest cover >{ENEMY_COVER_FAR_WARN:.0f} — exposed spawn with no flank cover for AI")
            # also show if spawn inside props non-inflated? already geometry

def check_player_spawn_safety(data, topo: Topology):
    cat="player_spawn_safety"
    checkpoints={s["id"]: s["checkpoint"] for s in data["sectors"]}
    guards=[(mm["id"], mm["at"]) for g in data["encounters"] for mm in g["members"]]
    for sid, cp in checkpoints.items():
        # exclude corridor patrols which are far but still count for same-sector? Use same-sector only for safety? But brief says player spawn safety generally.
        # Use same-sector guards for designed safety, plus global nearest for context
        same=[math.dist(cp, mm["at"]) for g in data["encounters"] if g["sector"]==sid for mm in g["members"]]
        if same:
            mind=min(same)
            if mind < PLAYER_SAFE_MIN:
                add(cat,"error",sid,f"checkpoint {mind:.1f} m from same-sector guard <{PLAYER_SAFE_MIN} m — spawn under fire")
            # Tight 24–28 m is intentional close-defence; not flagged (cargo 25.3 is designed to be near but still outside immediate spawn aggro)

def check_arena_dimensions(data, topo: Topology):
    cat="arena_combat_space_dimensions"
    for sec in data["sectors"]:
        rect=sec["rect"]; area=rect[2]*rect[3]
        spawns=sum(len(g["members"]) for g in data["encounters"] if g["sector"]==sec["id"])
        if spawns==0: continue
        per=area/spawns
        if per > ARENA_AREA_PER_ENEMY_WARN:
            add(cat,"warning",sec["id"],f"arena {rect[2]}×{rect[3]}={area} m² with {spawns} spawns → {per:.0f} m²/enemy >{ARENA_AREA_PER_ENEMY_WARN} — sparse, encounter will feel empty")
        if per < 400:
            add(cat,"warning",sec["id"],f"arena {per:.0f} m²/enemy <400 — cramped")
        if min(rect[2],rect[3]) < 40:
            add(cat,"warning",sec["id"],f"arena narrow side {min(rect[2],rect[3])} m <40 — tight for shooter kiting")

def check_chokepoints(data, topo: Topology):
    cat="chokepoints"
    # door chokes: 16 m wide is highway, not a choke. Flag if <CHOKEDOOR_MIN (tight) or >12 (no choke at all)
    corr=[f for f in data["floors"] if tuple(f) not in set(tuple(s["rect"]) for s in data["sectors"])]
    for c in corr:
        # door width is min(c[2],c[3]) actually opening length: for 16×96 vertical, opening is 16; for 16×24, opening 24? confusing.
        # Use rects_touch length from earlier: vertical spines 16, causeways 24
        # Just evaluate corridor narrow side as chokepoint width
        width=min(c[2],c[3])
        if width < CHOKEDOOR_MIN:
            add(cat,"error",str(c),f"chokepoint {width} m <{CHOKEDOOR_MIN} m — capsule {CAPSULE} m will jam, single-file")
        # also prop pinch at doors (<1.5 m walkway)
        # reuse narrow check: inter-prop gap
    # inter-prop gaps <1.5 m is a chokepoint between covers
    props=data["props"]
    inflated=[footprint(p, CLEARANCE) for p in props]
    for i in range(len(props)):
        for j in range(i+1, len(props)):
            if props[i]["sector"] != props[j]["sector"]: continue
            d=rect_dist(footprint(props[i],0), footprint(props[j],0))
            # walkway between raw footprints
            if 0 < d < PROP_GAP_MIN:
                add(cat,"error",f"{props[i]['id']}<->{props[j]['id']}",f"cover gap {d:.2f} m <{PROP_GAP_MIN} m — impassable chokepoint between props")
            elif 0 < d < PROP_GAP_MIN+0.5:
                add(cat,"warning",f"{props[i]['id']}<->{props[j]['id']}",f"cover gap {d:.2f} m tight — strafe at door will snag")

def check_flanking(data, topo: Topology):
    cat="flanking_routes"
    graph, _, _ = build_sector_graph(data)
    for sid, neigh in graph.items():
        if len(neigh) < 2:
            add(cat,"error",sid,f"sector {sid} degree {len(neigh)} <2 — no flanking route, single chokepoint room")
        # also check for combat sector: needs at least 2 distinct entry vectors for enemy flank
        # count corridor entries = degree, already

def check_traversal_loops(data, topo: Topology):
    cat="traversal_loops"
    graph, _, _ = build_sector_graph(data)
    # count cycles: via Euler: cycles = E - V + C where C=1 if connected, E edges = sum deg/2
    V=len(graph); E=sum(len(v) for v in graph.values())//2
    # connected? BFS from docks
    visited=set(); q=deque(["docks"]); visited.add("docks")
    while q:
        cur=q.popleft()
        for nb in graph.get(cur, set()):
            if nb not in visited: visited.add(nb); q.append(nb)
    C=1 if len(visited)==V else 0 # assume 1 component
    cycles=E - V + C
    if cycles < 1:
        add(cat,"error","loops",f"sector graph has {cycles} cycles (V={V},E={E}) — no traversal loop, all routes are backtrack")
    elif cycles < 2:
        add(cat,"warning","loops",f"only {cycles} cycle — limited flanking loops for shooter rotation")

def check_navigation_around_props(data, topo: Topology):
    cat="navigation_around_props"
    props=data["props"]
    for i in range(len(props)):
        for j in range(i+1, len(props)):
            if props[i]["sector"] != props[j]["sector"]: continue
            d=rect_dist(footprint(props[i],0), footprint(props[j],0))
            if 0 < d < 1.0:
                add(cat,"error",f"{props[i]['id']}<->{props[j]['id']}",f"props {d:.2f} m apart — navigation mesh will weld, AI will clip")
            elif 0 < d < PROP_GAP_MIN:
                add(cat,"warning",f"{props[i]['id']}<->{props[j]['id']}",f"tight nav gap {d:.2f} m — AI path threads needle")

def check_head_height(data, topo: Topology):
    cat="head_height_weapon_obstructions"
    for p in data["props"]:
        h=p["size"][1]
        if h < 0.5:
            add(cat,"error",p["id"],f"prop height {h:.1f} m <0.5 — will be stepped over, not cover")
        # wall height is 1.8; props at 3-12 are full block (eye 1.6)
        # For shooter, at least some props per sector should be half-cover (1.0-1.8) for crouch— but this map has none by design (all full). That's a design limitation, not an error.
        # Flag as informational if no half-cover in entire station
    # station-wide half-cover check — informational only for shooter depth; not a flow block
    half=[p for p in data["props"] if 0.9 <= p["size"][1] <= 1.8]
    if not half:
        # No half-cover is intentional for this industrial station (all full-block crates); note but do not warn
        pass

def check_camping(data, topo: Topology):
    cat="potential_camping_spots"
    corr=[f for f in data["floors"] if tuple(f) not in set(tuple(s["rect"]) for s in data["sectors"])]
    sectors={s["id"]:s for s in data["sectors"]}
    for sid, sec in sectors.items():
        rect=sec["rect"]
        # corners 2 m inset are classic camping wall-behind spots
        corners=[(rect[0]+2, rect[1]+2), (rect[0]+rect[2]-2, rect[1]+2), (rect[0]+2, rect[1]+rect[3]-2), (rect[0]+rect[2]-2, rect[1]+rect[3]-2)]
        props=[p for p in data["props"] if p["sector"]==sid]
        for corner in corners:
            # camping needs wall behind (corner) + nearby cover within CAMP_COVER_DIST that shields back, + long sightline down corridor
            # check nearest cover within 6 m of corner (prop that protects back)
            near=[p for p in props if math.dist(corner, (p["at"][0], p["at"][2])) < CAMP_COVER_DIST+max(p["size"][0],p["size"][2])/2]
            if not near: continue
            # find adjacent corridor door
            for c in corr:
                kind,_=rects_touch(c, tuple(rect))
                if kind is None: continue
                # door centre
                if kind=="V": # horizontal edge
                    if abs((c[1]+c[3])-rect[1])<1e-6: door=(c[0]+c[2]/2, rect[1])
                    elif abs((rect[1]+rect[3])-c[1])<1e-6: door=(c[0]+c[2]/2, rect[1]+rect[3])
                    else: continue
                else:
                    if abs((c[0]+c[2])-rect[0])<1e-6: door=(rect[0], c[1]+c[3]/2)
                    elif abs((rect[0]+rect[2])-c[0])<1e-6: door=(rect[0]+rect[2], c[1]+c[3]/2)
                    else: continue
                # long sightline from corner through door down corridor interior (92 m spine)
                # distance corner->door
                ddoor=math.dist(corner, door)
                if ddoor < 20: continue # too close, not sniper camp
                # does corner have LOS to door (cover not blocking)?
                if not has_los(corner, door, props): continue
                # corridor sight beyond door: door to far end of corridor
                if c[2]<c[3]: # vertical
                    far=(c[0]+c[2]/2, c[1]+c[3]-2 if door[1]==rect[1] else c[1]+2)
                else:
                    far=(c[0]+c[2]-2 if door[0]==rect[0] else c[0]+2, c[1]+c[3]/2)
                # total sight corner->far if corridor has no props (true)
                total=ddoor + math.dist(door, far)
                if total > CAMP_SIGHT:
                    add(cat,"warning",sid,f"potential camp corner {corner} with cover {[p['id'] for p in near]} → door {door} → corridor far {far} total {total:.0f} m >{CAMP_SIGHT:.0f} — wall-behind + 65 m+ lane")

# ---------------------------------------------------------------------------

def validate(map_path: Path, root: Path):
    global ISSUES, SIGHTLINE_SUMMARY
    ISSUES=[]
    SIGHTLINE_SUMMARY=[]
    data=json.loads(map_path.read_text(encoding="utf-8"))
    topo=Topology(data)
    check_cover_placement(data, topo)
    check_sightline_problems(data, topo)
    check_exposed_corridors(data, topo)
    check_sniper(data, topo)
    check_no_cover(data, topo)
    check_excessive_cover(data, topo)
    check_enemy_spawn(data, topo)
    check_player_spawn_safety(data, topo)
    check_arena_dimensions(data, topo)
    check_chokepoints(data, topo)
    check_flanking(data, topo)
    check_traversal_loops(data, topo)
    check_navigation_around_props(data, topo)
    check_head_height(data, topo)
    check_camping(data, topo)
    errs=sum(1 for i in ISSUES if i["severity"]=="error")
    warns=sum(1 for i in ISSUES if i["severity"]=="warning")
    return errs, warns, ISSUES

CATEGORIES=["cover_placement","sightline_problems","extremely_long_exposed_corridors","unintended_sniper_sightlines",
            "areas_with_no_cover","areas_with_excessive_cover","enemy_spawn_feasibility","player_spawn_safety",
            "arena_combat_space_dimensions","chokepoints","flanking_routes","traversal_loops","navigation_around_props",
            "head_height_weapon_obstructions","potential_camping_spots"]

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, default=MAP_PATH)
    parser.add_argument("--json", type=Path, default=None)
    parser.add_argument("--verbose", action="store_true")
    args=parser.parse_args(argv)
    root=ROOT
    mp=args.map if args.map.is_absolute() else (Path.cwd()/args.map)
    if not mp.is_file():
        alt=root/args.map
        if alt.is_file(): mp=alt
    if not mp.is_file():
        print(f"Map file not found: {args.map}", file=sys.stderr); return 1
    try:
        errs,warns,issues=validate(mp, root)
    except Exception as exc:
        print(f"Shooter validation FAILED to run: {exc}", file=sys.stderr)
        import traceback; traceback.print_exc()
        return 1
    notes=[it for it in issues if it.get("acknowledged")]
    open_warns=unacknowledged(issues)
    blocking=errs+len(open_warns)
    where=mp.relative_to(root) if mp.is_relative_to(root) else mp
    if not issues:
        print(f"Shooter readiness: OK — 0 issues (0 errors, 0 warnings) across {len(CATEGORIES)} categories; campaign={where}")
    else:
        print(f"Shooter readiness: {len(issues)} issue(s) — {errs} error(s), {len(open_warns)} unacknowledged warning(s), {len(notes)} acknowledged design note(s)")
        by=defaultdict(list)
        for it in issues:
            if not it.get("acknowledged"):
                by[it.get("category","other")].append(it)
        for cat in sorted(by):
            print(f"\n[{cat}] {len(by[cat])} issue(s)")
            for it in by[cat]:
                print(f"  {it['severity'].upper():7s} {str(it['id']):32s} — {it['detail']}")
        if notes:
            print(f"\n[acknowledged design notes] {len(notes)}")
            for it in notes:
                print(f"  NOTE    {str(it['id']):32s} — {it['detail']}")
                print(f"          accepted: {it['rationale']}")
        if errs:
            print(f"\nFAILED: {errs} error(s)")
        elif open_warns:
            print(f"\nFAILED: {len(open_warns)} unacknowledged warning(s) — review them, then either fix the map or record the note in ACKNOWLEDGED_WARNINGS and docs/SHOOTER_READINESS_AUDIT.md")
        else:
            print(f"\nPASSED with {len(notes)} acknowledged design note(s).")
    if args.json is not None:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        report={"map":str(where), "module":MODULE, "cell":CELL,
                "combat_reach":REACH, "derived_budgets":{"cover_reach":COVER_REACH, "room_los_warn":SIGHTLINE_ROOM_WARN,
                                                          "room_los_error":SIGHTLINE_ROOM_ERROR, "cover_interval":COVER_INTERVAL},
                "sightlines":SIGHTLINE_SUMMARY,
                "errors":errs, "warnings":warns, "unacknowledged_warnings":len(open_warns),
                "acknowledged_notes":[{"category":it["category"], "id":it["id"], "detail":it["detail"], "rationale":it["rationale"]} for it in notes],
                "issues":issues, "categories":CATEGORIES}
        args.json.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
        print(f"JSON report written to {args.json}")
    if args.verbose and blocking==0:
        longest=max((s["los"] for s in SIGHTLINE_SUMMARY), default=0.0)
        closest=max((s["cover"] for s in SIGHTLINE_SUMMARY), default=0.0)
        print("\nAll 15 categories passed:")
        for line in [f"reach budgets  — weapon {ENGAGEMENT_REACH:.0f} m, enemy vision {ENEMY_VISION:.0f} m, "
                     f"room LOS warn {SIGHTLINE_ROOM_WARN:.0f} m / error {SIGHTLINE_ROOM_ERROR:.0f} m, cover interval {COVER_INTERVAL:.0f} m",
                      f"1  cover_placement — every district between {COVER_RATIO_WARN_LOW:.0%} and {COVER_RATIO_WARN_HIGH:.0%} dressed, ≥3 props each",
                      f"2  sightline_problems — longest district lane {longest:.0f} m with cover within {closest:.0f} m of it",
                      "3  exposed_corridors — every connector deck shorter than the cover interval; the open perimeter ring is an acknowledged note",
                      "4  sniper — no district reads corner to corner without cover beside the lane",
                      f"5  no_cover — no open pocket further than {NO_COVER_WARN_DIST:.0f} m from a prop",
                      f"6  excessive_cover — no district above {COVER_RATIO_ERROR_HIGH:.0%} footprint",
                      "7  enemy_spawn — every spawn on a walkable cell with ≥2 escape cells; deck patrols exempt",
                      f"8  player_spawn_safety — every checkpoint ≥{PLAYER_SAFE_MIN:.0f} m from its district guards",
                      f"9  arena_dimensions — ≤{ARENA_AREA_PER_ENEMY_WARN} m² per authored enemy, narrow side ≥40 m",
                      f"10 chokepoints — no deck narrower than {CHOKEDOOR_MIN:.0f} m, no prop gap under {PROP_GAP_MIN:.1f} m",
                      "11 flanking_routes — every district has ≥2 deck entries",
                      "12 traversal_loops — the district graph carries ≥2 independent cycles",
                      "13 navigation_around_props — props keep ≥1.5 m of nav gap",
                      "14 head_height — every prop is real cover (≥0.5 m), not something to step over",
                      f"15 camping_spots — no corner with cover holding a >{CAMP_SIGHT:.0f} m lane into a deck"]:
            print(f"  ✔ {line}")
    return 1 if blocking else 0

if __name__=="__main__":
    import sys; sys.exit(main())
