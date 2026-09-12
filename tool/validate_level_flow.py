#!/usr/bin/env python3
"""
Level Layout & Spatial Flow Validator — Agent 2

Read-only offline audit for Station Zero (`data/campaign/station_zero.json`).
Mirrors CampaignGeometry / CampaignWorld / ArenaNavGrid contracts exactly.

Categories (10 from the brief, mapped to concrete gates):

  1. intended structure      — every district rect is a floor, every connector deck is ≥2 modules
                             wide and snapped, each deck joins the network (2 districts, or 1
                             district + the deck network), no single-entrance district, each
                             district has ≥1 encounter
  2. navigation              — every checkpoint / interaction / spawn walkable + flow-field reachable
  3. dead ends               — no degree-1 nav cells (cul-de-sac) and no dead-end sectors
  4. blocked corridors       — no corridor with a fully blocked cross-section band, no corridor
                             left with less than half its width walkable
  5. narrow passages         — no inter-prop expanded gap < 2.0 m, and every doorway keeps a
                             continuous free nav lane ≥ 8 m (2 cells) wide
  6. door / entrance         — floor edges %8==0, every corridor↔district interface keeps at
                             least one walkable lane on both sides of the door line
  7. vertical transitions    — single-level station, all floors co-planar y=0, no stairs markup
  8. connectivity            — district adjacency via connector decks is single-component, no
                             articulation corridor (blocking any one corridor keeps full reachability)
  9. isolated areas          — single walkable island (walkable==reachable), no spawn/interaction on island
 10. campaign path           — each district visited at most once per run, story beats within
                             MAX_PATH_HOPS district links, traversal budgets scaled from the
                             authored bounds, guard-to-target coupling, escalating rewards

The topology model is DERIVED from the authored data (district decks, connector decks, perimeter
spines and spurs are classified by how each floor rect touches the others), so the same gates hold
for any authored station shape instead of one hard-coded mesh. Thresholds that describe pacing
(traversal length, single leg) scale from `bounds`.

Exit 0 on 0 errors AND 0 unacknowledged warnings. Design notes this audit has reviewed and
accepted are listed in ACKNOWLEDGED_WARNINGS with a rationale; anything else fails the gate.

Usage:
  python3 tool/validate_level_flow.py
  python3 tool/validate_level_flow.py --verbose
  python3 tool/validate_level_flow.py --json docs/level_flow_report.json
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import math
import re
import sys
from collections import Counter, defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "data/campaign/station_zero.json"
MODULE = 8
CELL = 4
CLEARANCE = 2.5
CAPSULE_RADIUS = 0.45
AGENT_MARGIN = 0.5  # same as ArenaNavGrid.AGENT_MARGIN for corridor widening check
MIN_WALKWAY = 2.0      # <2 m expanded gap between two props is a pinch (threshold for warning)
MIN_DOOR_CLEAR = 3.5   # prop inflated rect must stay 3.5 m from door line or it pinches entrance
GUARD_CLOSE_WARN = 10.0  # guard within 10 m of its mission target is "on the switch"
GUARD_FAR_NOTE = 45.0    # guard farther than 45 m from target is loosely coupled

# --- Derived-topology budgets (see the module docstring) ---------------------
MIN_DECK_WIDTH = 2 * MODULE   # a connector deck is at least two 8 m modules (16 m) wide
DOOR_LANE_ERROR = 1 * CELL    # a doorway with less than one free nav cell is sealed shut
DOOR_LANE_WARN = 2 * CELL     # a doorway should keep two free cells (8 m) side by side
BAND_MIN_FRACTION = 0.5       # a corridor cross-section keeps at least half its cells walkable
MAX_PATH_HOPS = 3             # story beats may cross at most three district links (a full
                              # traversal of the authored district grid) without backtracking
TRAVERSAL_AXIS_BUDGET = 7.0   # whole mission loop ≤ 7× the longest authored world axis
LEG_DIAGONAL_BUDGET = 1.0     # a single mission leg ≤ the authored world diagonal


def require(cond, msg):
    if not cond:
        raise ValueError(msg)


def load_json(path: Path):
    def unique(pairs):
        d={}
        for k,v in pairs:
            if k in d:
                raise ValueError(f"Duplicate JSON key: {k}")
            d[k]=v
        return d
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def contains(rect, pt):
    x,z,w,d=rect
    return x <= pt[0] < x+w and z <= pt[1] < z+d


def in_solid(rect, pt):
    x,z,w,d=rect
    return x <= pt[0] <= x+w and z <= pt[1] <= z+d


def footprint(prop, grow=0):
    x,_,z = prop["at"]
    w,_,d = prop["size"]
    return [x - w/2 - grow, z - d/2 - grow, w + grow*2, d+grow*2]


def rects_touch(a,b):
    ax,az,aw,ad=a; bx,bz,bw,bd=b
    if abs((ax+aw)-bx) < 1e-6 and not (az+ad <= bz or bz+bd <= az):
        return ("H", min(az+ad,bz+bd)-max(az,bz))  # vertical edge sharing (left/right)
    if abs((bx+bw)-ax) < 1e-6 and not (az+ad <= bz or bz+bd <= az):
        return ("H", min(az+ad,bz+bd)-max(az,bz))
    if abs((az+ad)-bz) < 1e-6 and not (ax+aw <= bx or bx+bw <= ax):
        return ("V", min(ax+aw,bx+bw)-max(ax,bx))  # horizontal edge sharing (south/north)
    if abs((bz+bd)-az) < 1e-6 and not (ax+aw <= bx or bx+bw <= ax):
        return ("V", min(ax+aw,bx+bw)-max(ax,bx))
    return (None, 0)


def rect_dist(a,b):
    ax,az,aw,ad=a; bx,bz,bw,bd=b
    if ax+aw < bx:
        dx = bx - (ax+aw)
    elif bx+bw < ax:
        dx = ax - (bx+bw)
    else:
        dx = 0
    if az+ad < bz:
        dz = bz - (az+ad)
    elif bz+bd < az:
        dz = az - (bz+bd)
    else:
        dz = 0
    if dx==0 and dz==0:
        return 0
    if dx==0:
        return dz
    if dz==0:
        return dx
    return math.hypot(dx,dz)


class Topology:
    def __init__(self, data):
        self.data=data
        self.bounds=data["bounds"]
        bx,bz,bw,bd=self.bounds
        self.bx,self.bz=bw and bx, bz
        self.bx=bounds_x=bw and data["bounds"][0]
        # simpler
        self.bx=data["bounds"][0]
        self.bz=data["bounds"][1]
        self.bw=data["bounds"][2]
        self.bd=data["bounds"][3]
        self.width=math.ceil(self.bw/CELL)
        self.depth=math.ceil(self.bd/CELL)
        self.inflated=[footprint(p, CLEARANCE) for p in data["props"]]
        self.walkable=set()
        for j in range(self.depth):
            for i in range(self.width):
                at=(self.bx + (i+0.5)*CELL, self.bz + (j+0.5)*CELL)
                if any(contains(f, at) for f in data["floors"]) and not any(in_solid(p, at) for p in self.inflated):
                    self.walkable.add((i,j))
        self.modules=set()
        for a,b,c,e in data["floors"]:
            for j in range(round(b/MODULE), round((b+e)/MODULE)):
                for i in range(round(a/MODULE), round((a+c)/MODULE)):
                    self.modules.add((i,j))

    def cell(self, pt):
        return (math.floor((pt[0]-self.bx)/CELL), math.floor((pt[-1]-self.bz)/CELL))
    def center(self, cell):
        return (self.bx+(cell[0]+0.5)*CELL, self.bz+(cell[1]+0.5)*CELL)
    def neighbors(self, at):
        for dx,dz in ((0,1),(1,0),(0,-1),(-1,0)):
            o=(at[0]+dx, at[1]+dz)
            if o in self.walkable:
                yield o
    def reachable(self, pt):
        s=self.cell(pt)
        if s not in self.walkable:
            return set()
        seen={s}; q=deque([s])
        while q:
            cur=q.popleft()
            for nb in self.neighbors(cur):
                if nb not in seen:
                    seen.add(nb); q.append(nb)
        return seen
    def path(self, a_pt, b_pt):
        a=self.cell(a_pt); b=self.cell(b_pt)
        if a not in self.walkable or b not in self.walkable:
            return None, float("inf")
        prev={a:None}; q=deque([a])
        while q and b not in prev:
            cur=q.popleft()
            for nb in self.neighbors(cur):
                if nb not in prev:
                    prev[nb]=cur; q.append(nb)
        if b not in prev:
            return None, float("inf")
        path=[]; cur=b
        while cur is not None:
            path.append(self.center(cur)); cur=prev[cur]
        path=path[::-1]
        dist=sum(math.dist(path[i], path[i+1]) for i in range(len(path)-1))
        return path, dist


def build_sector_graph(data):
    sector_ids=[s["id"] for s in data["sectors"]]
    sectors={s["id"]:s for s in data["sectors"]}
    corridors=[tuple(f) for f in data["floors"] if tuple(f) not in set(tuple(s["rect"]) for s in data["sectors"])]
    corr_adj={}
    for c in corridors:
        adj=[]
        for sid, sec in sectors.items():
            if rects_touch(c, tuple(sec["rect"]))[0] is not None:
                adj.append(sid)
        corr_adj[c]=adj
    graph={sid:set() for sid in sector_ids}
    for c, secs in corr_adj.items():
        for i in range(len(secs)):
            for j in range(i+1, len(secs)):
                graph[secs[i]].add(secs[j]); graph[secs[j]].add(secs[i])
    return graph, corridors, corr_adj


ISSUES: list[dict] = []
# Derived topology counts, filled by check_intended_structure and printed by --verbose.
STRUCTURE_SUMMARY: dict[str, int] = {}
# Pacing measured by check_campaign_path, printed by --verbose.
PATH_SUMMARY: dict[str, float] = {}

# Design notes this audit has reviewed and ACCEPTED for the authored station.
# A warning that is not listed here fails the gate (exit 1) exactly like an
# error does, so the list is the only place a known note may hide — and each
# entry has to carry the reason it is acceptable. Keep it in sync with
# docs/LEVEL_FLOW_AUDIT.md ("Accepted design notes").
ACKNOWLEDGED_WARNINGS: list[tuple[str, str, str]] = [
    ("campaign_path", "triage",
     "Medical triage is an authored quiet beat. The wardens patrol 11 m from both medkits, so "
     "combat is unavoidable in practice (enemy vision is 17 m), but the consoles deliberately do "
     "not lock behind a district clear: the player may talk to the survivors mid-fight."),
    ("campaign_path", "archive_names",
     "Data Archive is the campaign's stealth beat: three cores sit 8 m from the sentries and the "
     "mission intentionally does not require clearing them, so a player who avoids the stacks is "
     "rewarded. The other nine missions (restore_transit, green_deck, forge_passage, cargo_records, "
     "coolant, survivors, salvage_run, send_signal, commander) each lock their objective behind a "
     "same-district patrol."),
]


def acknowledged_rationale(cat: str, oid: str) -> str | None:
    """Return the recorded rationale when a warning is an accepted design note."""
    for ack_cat, ack_id, rationale in ACKNOWLEDGED_WARNINGS:
        if ack_cat == cat and (ack_id == oid or fnmatch.fnmatch(str(oid), ack_id)):
            return rationale
    return None


def add(cat, severity, oid, detail, **extra):
    issue = {"category": cat, "severity": severity, "id": oid, "detail": detail, **extra}
    if severity == "warning":
        rationale = acknowledged_rationale(cat, str(oid))
        issue["acknowledged"] = rationale is not None
        issue["rationale"] = rationale or ""
    ISSUES.append(issue)


def classify_floors(data):
    """Split the authored floors into the roles the topology gates reason about.

    Derived from the data, never from a hard-coded mesh, so a station may be
    authored as any shape (grid, ring, spine) and still be checked:

      district  — a floor rect that is exactly a sector rect
      connector — a deck touching exactly 2 districts (an inter-district causeway)
      spine     — a deck touching 0 districts but ≥2 other decks (perimeter service ring)
      spur      — a deck touching exactly 1 district (must join the deck network)
    """
    sector_rects = {tuple(s["rect"]): s["id"] for s in data["sectors"]}
    districts = [tuple(s["rect"]) for s in data["sectors"]]
    decks = [tuple(f) for f in data["floors"] if tuple(f) not in sector_rects]
    touching = {}
    for deck in decks:
        sectors = [sid for rect, sid in sector_rects.items() if rects_touch(deck, rect)[0] is not None]
        neighbours = [other for other in decks if other != deck and rects_touch(deck, other)[0] is not None]
        touching[deck] = (sectors, neighbours)
    connectors = [d for d in decks if len(touching[d][0]) == 2]
    spines = [d for d in decks if not touching[d][0] and len(touching[d][1]) >= 2]
    spurs = [d for d in decks if len(touching[d][0]) == 1]
    return {"districts": districts, "decks": decks, "connectors": connectors,
            "spines": spines, "spurs": spurs, "touching": touching, "sector_rects": sector_rects}


def door_lanes(data, topo: Topology):
    """Free nav lanes across every corridor↔district doorway.

    A doorway is passable when at least one 4 m slot along the shared edge has a
    walkable cell 2 m inside the corridor AND 2 m inside the district. Sampling a
    fixed four points (the old rule) reported a sealed door whenever a prop stood
    inside the district near the threshold, even when the rest of the 16 m opening
    was wide open — and missed a real seal when the prop sat exactly on the slots.
    """
    roles = classify_floors(data)
    doors = []
    for deck in roles["decks"]:
        for rect, sid in roles["sector_rects"].items():
            kind, _length = rects_touch(deck, rect)
            if kind is None:
                continue
            if kind == "V":
                if abs((deck[1] + deck[3]) - rect[1]) < 1e-6:
                    line = rect[1]
                elif abs((rect[1] + rect[3]) - deck[1]) < 1e-6:
                    line = deck[1]
                else:
                    continue
                start, end = max(deck[0], rect[0]), min(deck[0] + deck[2], rect[0] + rect[2])
                slots = [(start + (k + 0.5) * CELL, line - 2.0, line + 2.0)
                         for k in range(int(round((end - start) / CELL)))]
                free = [topo.cell([x, 0.2, minus]) in topo.walkable and topo.cell([x, 0.2, plus]) in topo.walkable
                        for x, minus, plus in slots]
                axis = "z"
            else:
                if abs((deck[0] + deck[2]) - rect[0]) < 1e-6:
                    line = rect[0]
                elif abs((rect[0] + rect[2]) - deck[0]) < 1e-6:
                    line = deck[0]
                else:
                    continue
                start, end = max(deck[1], rect[1]), min(deck[1] + deck[3], rect[1] + rect[3])
                slots = [(line - 2.0, line + 2.0, start + (k + 0.5) * CELL)
                         for k in range(int(round((end - start) / CELL)))]
                free = [topo.cell([minus, 0.2, z]) in topo.walkable and topo.cell([plus, 0.2, z]) in topo.walkable
                        for minus, plus, z in slots]
                axis = "x"
            run = best = 0
            for ok in free:
                run = run + 1 if ok else 0
                best = max(best, run)
            doors.append({"deck": deck, "sector": sid, "axis": axis, "line": line,
                          "opening": end - start, "slots": len(free), "free_slots": sum(free),
                          "free_run": best * CELL})
    return doors


def unacknowledged(issues):
    return [it for it in issues if it["severity"] == "warning" and not it.get("acknowledged")]


# ---------------------------------------------------------------------------

def check_intended_structure(data, topo: Topology):
    cat="structure"
    roles=classify_floors(data)
    floors=set(tuple(f) for f in data["floors"])
    for s in data["sectors"]:
        if tuple(s["rect"]) not in floors:
            add(cat,"error",s["id"],f"sector {s['id']} rect {s['rect']} has no matching floor — room will be void")
    # Every deck is module-snapped and at least two modules wide, whatever its length.
    for deck in roles["decks"]:
        if min(deck[2], deck[3]) < MIN_DECK_WIDTH:
            add(cat,"error",str(deck),f"deck {deck} is {min(deck[2], deck[3])} m wide — narrower than {MIN_DECK_WIDTH} m (2 modules), so a body plus its clearance cannot pass")
        for value in deck:
            if value % MODULE != 0:
                add(cat,"error",str(deck),f"deck {deck} edge {value} is not snapped to the {MODULE} m module grid — the deck gaps or overlaps its doorways")
                break
    # A deck has to lead somewhere: two districts (a causeway), one district plus the
    # deck network (a spur off the service ring), or no district plus two decks (a
    # perimeter spine). Anything else is a floor rect that opens onto void.
    for deck in roles["decks"]:
        sectors, neighbours = roles["touching"][deck]
        if len(sectors) == 2:
            continue
        if len(sectors) == 1 and neighbours:
            continue
        if not sectors and len(neighbours) >= 2:
            continue
        add(cat,"error",str(deck),f"deck {deck} touches {len(sectors)} district(s) {sectors} and {len(neighbours)} deck(s) — dangling deck, it leads nowhere")
        if len(sectors) > 2:
            add(cat,"error",str(deck),f"deck {deck} touches {len(sectors)} districts {sectors} — a fan, not a causeway; shared district edges seal the routes they opened")
    # No single-entrance district: one prop, one fight or one sealed door must not
    # be able to lock a district off, so every district keeps at least two decks.
    per_district=Counter()
    for deck in roles["decks"]:
        for sid in roles["touching"][deck][0]:
            per_district[sid]+=1
    for s in data["sectors"]:
        decks=per_district.get(s["id"], 0)
        if decks < 2:
            add(cat,"error",s["id"],f"district {s['id']} has {decks} deck(s) — a single entrance is a dead-end room")
    # each district has >=1 encounter
    per_sector=Counter(g["sector"] for g in data["encounters"])
    for s in data["sectors"]:
        if per_sector.get(s["id"],0)==0:
            add(cat,"error",s["id"],f"sector {s['id']} has no encounter — intended combat section missing (room will feel empty)")
    per_inter=Counter(it["sector"] for it in data["interactions"])
    for s in data["sectors"]:
        if per_inter.get(s["id"],0)==0:
            add(cat,"warning",s["id"],f"sector {s['id']} has no interactions — no objective or cache")
    STRUCTURE_SUMMARY.update({
        "floors": len(data["floors"]),
        "districts": len(roles["districts"]),
        "connector_decks": len(roles["connectors"]),
        "perimeter_spines": len(roles["spines"]),
        "spurs": len(roles["spurs"]),
    })


def check_navigation(data, topo: Topology):
    cat="navigation"
    try:
        start=next(s["checkpoint"] for s in data["sectors"] if s["id"]=="docks")
    except StopIteration:
        add(cat,"error","docks","missing docks checkpoint — cannot test navigation")
        return
    reachable=topo.reachable(start)
    if reachable!=topo.walkable:
        add(cat,"error","navigation",f"walkable {len(topo.walkable)} != reachable {len(reachable)} — {len(topo.walkable)-len(reachable)} cells disconnected")
    points=[(s["id"]+" checkpoint", s["checkpoint"]) for s in data["sectors"]]
    points+=[(it["id"], it["at"]) for it in data["interactions"]]
    points+=[(m["id"], m["at"]) for g in data["encounters"] for m in g["members"]]
    for oid, pt in points:
        c=topo.cell(pt)
        if c not in topo.walkable:
            add(cat,"error",oid,f"point {pt} is on a blocked nav cell (inside prop or void) — player/enemy cannot stand there")
        elif c not in reachable:
            add(cat,"error",oid,f"point {pt} walkable but unreachable from docks — island spawn/objective")
    # also test flow field reachable (conservative LOS flag true for campaign)
    # Already covered via reachable; ArenaNavGrid conservative LOS additionally checks diagonal corner cutting —
    # but walkable set already excludes inflated props by CELL*0.5+AGENT_MARGIN.

def check_dead_ends(data, topo: Topology):
    cat="dead_ends"
    # degree-1 nav cells = cul-de-sac
    dead=[]
    for c in topo.walkable:
        deg=sum(1 for _ in topo.neighbors(c))
        if deg==1:
            dead.append(c)
    if dead:
        add(cat,"error","nav",f"{len(dead)} dead-end nav cells (degree 1) — unintended cul-de-sacs: e.g. {dead[:3]} centers {[topo.center(c) for c in dead[:3]]}")
    # sector dead ends: graph leaf sector with degree 1 is a dead-end room (only one corridor). Current mesh has no leaves.
    graph, _, _ = build_sector_graph(data)
    leaves=[sid for sid, neigh in graph.items() if len(neigh)==1]
    if leaves:
        add(cat,"warning","sectors",f"sector dead ends {leaves} (degree 1) — intentional single-entrance pocket? None expected for this 2×3 grid")

def check_blocked_corridors(data, topo: Topology):
    cat="blocked_corridors"
    roles=classify_floors(data)
    for c in roles["decks"]:
        x,z,w,d=c
        horizontal = w > d
        across=(d if horizontal else w)//CELL      # cells side to side
        bands=(w if horizontal else d)//CELL       # cross-sections along the length
        i0,j0=topo.cell([x,0.2,z])
        counts=[0]*bands
        total=0
        for cell in topo.walkable:
            if not contains(c, topo.center(cell)):
                continue
            total+=1
            k=(cell[0]-i0) if horizontal else (cell[1]-j0)
            if 0 <= k < bands:
                counts[k]+=1
        expected=(w*d)//(CELL*CELL)
        if total==0:
            add(cat,"error",str(c),f"deck {c} has 0 walkable cells — completely blocked (all {expected} cells covered by props or their clearance)")
            continue
        if total < expected*0.9:
            add(cat,"warning",str(c),f"deck {c} walkable {total}/{expected} (<90%) — heavily obstructed")
        sealed=[k for k,n in enumerate(counts) if n==0]
        if sealed:
            add(cat,"error",str(c),f"deck {c} has {len(sealed)} fully blocked cross-section band(s) (first at band {sealed[0]}) — the deck is sealed shut")
        squeeze=math.ceil(across*BAND_MIN_FRACTION)
        pinched=[k for k,n in enumerate(counts) if 0 < n < squeeze]
        if pinched:
            add(cat,"warning",str(c),f"deck {c} keeps under half of its {across}-cell width at {len(pinched)} band(s) (first at band {pinched[0]}) — a squeeze, not a route")


def check_narrow_passages(data, topo: Topology):
    cat="narrow_passages"
    props=data["props"]
    inflated=[footprint(p, CLEARANCE) for p in props]
    # inter-prop expanded gap
    for i in range(len(props)):
        for j in range(i+1, len(props)):
            d=rect_dist(inflated[i], inflated[j])
            if 0 < d < MIN_WALKWAY:
                add(cat,"warning",f"{props[i]['id']}<->{props[j]['id']}",
                    f"expanded footprints gap {d:.2f} m < {MIN_WALKWAY} m (with {CLEARANCE} m clearance) — narrow pinch between props {props[i]['sector']}/{props[j]['sector']}; player capsule {CAPSULE_RADIUS} m may still pass but feels cramped; covers? centers {props[i]['at']} vs {props[j]['at']}",
                    gap=d)
    # Doorway pinch: the free nav lane across each corridor↔district doorway. The
    # old rule measured the distance from a prop to the door LINE, which flagged
    # dressing that stood near a wide opening and missed a prop parked exactly in
    # the 16 m mouth. What matters is the width that is still walkable.
    for door in door_lanes(data, topo):
        if door["free_run"] <= 0:
            continue  # a sealed doorway is a door_alignment error, not a pinch
        if door["free_run"] < DOOR_LANE_WARN:
            add(cat,"warning",f"{door['sector']}<->{door['deck']}",
                f"doorway {door['sector']} ↔ deck {door['deck']} keeps only {door['free_run']:.0f} m of continuous free lane "
                f"(<{DOOR_LANE_WARN:.0f} m) across its {door['opening']:.0f} m opening — props pinch the entrance",
                free_run=door["free_run"], opening=door["opening"])


def check_door_alignment(data, topo: Topology):
    cat="door_alignment"
    # Every floor edge sits on the module grid, or the deck meshes gap/overlap.
    for floor in data["floors"]:
        for v in floor:
            if v % MODULE != 0:
                add(cat,"error",str(tuple(floor)),f"floor edge {v} not snapped to {MODULE} m — misaligned door will gap/overlap")
                break
    roles=classify_floors(data)
    sector_rects=roles["sector_rects"]
    for deck in roles["decks"]:
        for rect, sid in sector_rects.items():
            kind,length=rects_touch(deck, rect)
            if kind is None:
                continue
            # The shared edge is the doorway: it must be whole modules wide, so the
            # deck meshes with the district instead of overlapping half a module.
            if length < MIN_DECK_WIDTH or abs(length % MODULE) > 1e-6:
                add(cat,"warning",f"{sid}<->{deck}",f"doorway {sid} ↔ deck {deck} is {length:.0f} m — not a whole multiple of {MODULE} m at least {MIN_DECK_WIDTH} m wide")
    # Passability: at least one 4 m slot of every doorway has a walkable cell 2 m
    # inside the deck AND 2 m inside the district. Sampled fixed offsets used to
    # report a sealed door for a prop standing near a wide opening, and to miss a
    # prop parked exactly on the sampled slots.
    for door in door_lanes(data, topo):
        if door["free_run"] <= DOOR_LANE_ERROR:
            add(cat,"error",f"{door['sector']}<->{door['deck']}",
                f"doorway {door['sector']} ↔ deck {door['deck']} has no walkable lane across its {door['opening']:.0f} m opening "
                f"(door line {door['axis']}={door['line']:.0f}) — sealed by a prop or a misaligned deck")
        elif door["free_slots"] * 2 < door["slots"]:
            add(cat,"warning",f"{door['sector']}<->{door['deck']}",
                f"doorway {door['sector']} ↔ deck {door['deck']} keeps {door['free_slots']}/{door['slots']} slots walkable — half the opening is dressed shut")


def check_vertical_transitions(data, topo: Topology):
    cat="vertical"
    # Single-level invariant: all floors are co-planar, no "level", "elevation", "lift", "ramp" in schema.
    # Verify authored checkpoints/interactions/spawns at y=0.2 and props base at 0, no floor y.
    for sec in data["sectors"]:
        if sec["checkpoint"][1] != 0.2:
            add(cat,"warning",sec["id"],f"checkpoint y={sec['checkpoint'][1]} !=0.2 — vertical transition or floating checkpoint")
    for it in data["interactions"]:
        if abs(it["at"][1]-0.2) > 1e-6:
            add(cat,"warning",it["id"],f"interaction y={it['at'][1]} !=0.2 — vertical anomaly")
    for g in data["encounters"]:
        for m in g["members"]:
            if abs(m["at"][1]-0.2) > 1e-6:
                add(cat,"warning",m["id"],f"spawn y={m['at'][1]} !=0.2 — vertical anomaly")
    # Check props have no authored "level" or "floor_id" linking differing heights
    for prop in data["props"]:
        base=prop["at"][1] - prop["size"][1]/2
        if abs(base) > 0.05:
            add(cat,"error",prop["id"],f"prop base {base:.3f} — vertical offset (floors are flat at y=0)")
    # Check that no floor rect implies different y (data/bounds contains no y). For completeness note that docs call out single-level.
    # If future verticality is added, this gate must become height-map aware.

def check_connectivity(data, topo: Topology):
    cat="connectivity"
    graph, corridors, _ = build_sector_graph(data)
    # BFS sector connectivity
    visited=set(); q=deque(["docks"])
    visited.add("docks")
    while q:
        cur=q.popleft()
        for nb in graph.get(cur, set()):
            if nb not in visited:
                visited.add(nb); q.append(nb)
    if len(visited)!= len(graph):
        add(cat,"error","sectors",f"sector graph disconnected — visited {visited} vs all {set(graph.keys())}; island districts: {set(graph.keys())-visited}")
    # articulation corridors: removing any single corridor must keep station fully reachable (redundant design)
    for bc in corridors:
        walk=set()
        bx,bz,bw,bd=data["bounds"]
        inflated=[footprint(p, CLEARANCE) for p in data["props"]]
        for j in range(topo.depth):
            for i in range(topo.width):
                at=(bx+(i+0.5)*CELL, bz+(j+0.5)*CELL)
                if contains(bc, at):
                    continue
                if any(contains(f, at) for f in data["floors"]) and not any(in_solid(p, at) for p in inflated):
                    walk.add((i,j))
        if not walk:
            continue
        # BFS from docks inside this reduced walk
        start=next(s["checkpoint"] for s in data["sectors"] if s["id"]=="docks")
        reachable=Topology(data).reachable(start)  # but reuse? Need reachable on reduced set. Compute manually
        # recompute reachable on 'walk'
        s_cell=(math.floor((start[0]-bx)/CELL), math.floor((start[-1]-bz)/CELL))
        if s_cell not in walk:
            add(cat,"warning",str(bc),f"blocking corridor {bc} puts docks checkpoint itself off-mesh")
            continue
        seen={s_cell}; qq=deque([s_cell])
        while qq:
            cur=qq.popleft()
            for dx,dz in ((0,1),(1,0),(0,-1),(-1,0)):
                nb=(cur[0]+dx, cur[1]+dz)
                if nb in walk and nb not in seen:
                    seen.add(nb); qq.append(nb)
        if seen!=walk:
            add(cat,"warning",str(bc),f"corridor {bc} is an articulation: blocking it isolates {len(walk)-len(seen)} cells ({len(seen)}/{len(walk)} remain) — single-point-of-failure corridor")

def check_isolated_areas(data, topo: Topology):
    cat="isolated_areas"
    # already covered in navigation, but also check naive walkable islands count via flood fill
    visited_global=set()
    islands=[]
    for c in topo.walkable:
        if c in visited_global:
            continue
        # BFS island
        seen={c}; q=deque([c])
        while q:
            cur=q.popleft()
            for nb in topo.neighbors(cur):
                if nb not in seen:
                    seen.add(nb); q.append(nb)
        visited_global.update(seen)
        islands.append(seen)
    if len(islands)!=1:
        add(cat,"error","islands",f"walkable has {len(islands)} islands (expected 1) — isolated areas {sorted([len(i) for i in islands])}")
    # Check for corridor-ambush spawns being isolated: west/east service patrols inside corridors are still on same island (they are)
    # Also check objective isolation (duplicate of navigation but with explicit sector)
    if islands and len(islands)==1:
        main=islands[0]
        for g in data["encounters"]:
            for m in g["members"]:
                if topo.cell(m["at"]) not in main:
                    add(cat,"error",m["id"],f"spawn {m['at']} on isolated island (not main)")
        for it in data["interactions"]:
            if topo.cell(it["at"]) not in main:
                add(cat,"error",it["id"],f"interaction on isolated island")

def check_campaign_path(data, topo: Topology):
    cat="campaign_path"
    sectors={s["id"]:s for s in data["sectors"]}
    interactions={it["id"]:it for it in data["interactions"]}
    missions=data["missions"]
    graph, _, _ = build_sector_graph(data)
    bx,bz,bw,bd=data["bounds"]
    world_diagonal=math.hypot(bw, bd)
    total_budget=TRAVERSAL_AXIS_BUDGET*max(bw, bd)
    leg_budget=LEG_DIAGONAL_BUDGET*world_diagonal

    # The run must be a tour, not a shuttle: every district is visited at most once
    # and only the extraction may return to the district the run started in.
    order=[m["sector"] for m in missions]
    if order[0] != "docks" or missions[-1]["sector"] != "docks" or missions[-1]["kind"] != "extract":
        add(cat,"error","home",f"final mission is {missions[-1]['id']} ({missions[-1]['kind']} in {missions[-1]['sector']}) — the run must end with an extraction back in docks, the 'long way home' promise")
    seen=set()
    for index, sid in enumerate(order):
        last = index == len(order)-1
        if sid in seen and not (last and sid == order[0]):
            add(cat,"error",missions[index]["id"],f"mission {missions[index]['id']} returns to {sid}, already played at mission {order.index(sid)+1} — the run backtracks across the station")
        if not last:
            seen.add(sid)

    # Story beats stay within MAX_PATH_HOPS district links of each other. Hops are
    # counted on the connector-deck graph (perimeter spines are a redundant route,
    # not the story route), so the budget scales with the authored district grid
    # instead of assuming one mesh.
    for i in range(1, len(missions)):
        prev=missions[i-1]["sector"]; cur=missions[i]["sector"]
        if cur == prev:
            continue
        visited={prev}; q=deque([(prev,0)]); found=None
        while q:
            node, depth = q.popleft()
            if node==cur:
                found=depth; break
            for nb in graph.get(node, set()):
                if nb not in visited:
                    visited.add(nb); q.append((nb,depth+1))
        if found is None:
            add(cat,"error",missions[i]["id"],f"mission {missions[i]['id']} in {cur} is unreachable from {prev} on the district graph — the story teleports")
        elif found > MAX_PATH_HOPS:
            add(cat,"warning",missions[i]["id"],f"mission {missions[i]['id']} sector {cur} follows {prev} with graph hop {found} (>{MAX_PATH_HOPS}) — noncontiguous campaign path may require excessive backtrack")

    # Traversal pacing, scaled from the authored bounds instead of one fixed map.
    current=sectors["docks"]["checkpoint"]
    total=0.0
    max_leg=0.0
    max_leg_id=""
    for m in missions:
        for tid in m["targets"]:
            if tid not in interactions:
                add(cat,"error",m["id"],f"mission {m['id']} targets unknown interaction {tid}")
                continue
            tgt=interactions[tid]["at"]
            _, dist=topo.path(current, tgt)
            if dist==float("inf"):
                add(cat,"error",tid,f"mission target {tid} unreachable from {current}")
            else:
                total+=dist
                if dist>max_leg:
                    max_leg=dist; max_leg_id=f"{m['id']}:{tid}"
            current=tgt
    PATH_SUMMARY.update({"total": total, "max_leg": max_leg, "max_leg_id": max_leg_id,
                         "total_budget": total_budget, "leg_budget": leg_budget})
    if total>total_budget:
        add(cat,"warning","total_length",f"campaign traversal {total:.0f} m exceeds the authored budget {total_budget:.0f} m ({TRAVERSAL_AXIS_BUDGET:.0f}× the {max(bw,bd):.0f} m world axis) — the run fatigues before extraction")
    if max_leg>leg_budget:
        add(cat,"warning",max_leg_id,f"single leg {max_leg:.0f} m exceeds the authored budget {leg_budget:.0f} m (the {world_diagonal:.0f} m world diagonal) — a long run with no checkpoint in it")

    # Guard-to-target coupling: a mid-campaign mission whose district is guarded but
    # whose objective is not locked behind that guard is a deliberate note, and has
    # to be listed in ACKNOWLEDGED_WARNINGS to pass.
    for index, m in enumerate(missions):
        if m.get("requires"):
            continue
        if index in (0, len(missions)-1):
            continue  # the arrival beat and the extraction are intentionally ungated
        sector_encs=[e for e in data["encounters"] if e["sector"]==m["sector"]]
        if sector_encs:
            total_guards=sum(len(e["members"]) for e in sector_encs)
            add(cat,"warning",m["id"],f"mission {m['id']} sector {m['sector']} has {total_guards} guards but requires=[] — combat is skippable/optional; the objective is not locked behind the district clear")

    credits=[m["reward"].get("credits",0) for m in missions]
    if credits != sorted(credits):
        add(cat,"warning","rewards",f"mission credit rewards not monotonic {credits} — later missions should feel more valuable than earlier")


# ---------------------------------------------------------------------------

def validate(map_path: Path, root: Path, verbose=False):
    global ISSUES, STRUCTURE_SUMMARY, PATH_SUMMARY
    ISSUES=[]
    STRUCTURE_SUMMARY={}
    PATH_SUMMARY={}
    data=load_json(map_path)
    topo=Topology(data)
    check_intended_structure(data, topo)
    check_navigation(data, topo)
    check_dead_ends(data, topo)
    check_blocked_corridors(data, topo)
    check_narrow_passages(data, topo)
    check_door_alignment(data, topo)
    check_vertical_transitions(data, topo)
    check_connectivity(data, topo)
    check_isolated_areas(data, topo)
    check_campaign_path(data, topo)
    errs=sum(1 for i in ISSUES if i["severity"]=="error")
    warns=sum(1 for i in ISSUES if i["severity"]=="warning")
    return errs, warns, ISSUES

CATEGORIES=["structure","navigation","dead_ends","blocked_corridors","narrow_passages",
            "door_alignment","vertical","connectivity","isolated_areas","campaign_path"]

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", type=Path, default=MAP_PATH, help="path to campaign json")
    parser.add_argument("--json", type=Path, default=None, help="write JSON report")
    parser.add_argument("--verbose", action="store_true", help="list categories even when clean")
    args=parser.parse_args(argv)
    root=ROOT
    mp=args.map if args.map.is_absolute() else (Path.cwd()/args.map)
    if not mp.is_file():
        alt=root/args.map
        if alt.is_file(): mp=alt
    if not mp.is_file():
        print(f"Map file not found: {args.map}", file=sys.stderr); return 1
    try:
        errs,warns,issues=validate(mp, root, verbose=args.verbose)
    except (ValueError, KeyError, OSError) as exc:
        print(f"Level flow validation FAILED to run: {exc}", file=sys.stderr)
        if args.verbose:
            import traceback; traceback.print_exc()
        return 1
    notes=[it for it in issues if it.get("acknowledged")]
    open_warns=unacknowledged(issues)
    blocking=errs+len(open_warns)
    where=mp.relative_to(root) if mp.is_relative_to(root) else mp
    if not issues:
        print(f"Level flow: OK — 0 issues (0 errors, 0 warnings) across {len(CATEGORIES)} categories; campaign={where}")
    else:
        print(f"Level flow: {len(issues)} issue(s) — {errs} error(s), {len(open_warns)} unacknowledged warning(s), {len(notes)} acknowledged design note(s)")
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
            print(f"\nFAILED: {len(open_warns)} unacknowledged warning(s) — review them, then either fix the map or record the note in ACKNOWLEDGED_WARNINGS and docs/LEVEL_FLOW_AUDIT.md")
        else:
            print(f"\nPASSED with {len(notes)} acknowledged design note(s).")
    if args.json is not None:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        report={"map":str(where), "module":MODULE, "cell":CELL, "errors":errs, "warnings":warns,
                "unacknowledged_warnings":len(open_warns),
                "acknowledged_notes":[{"category":it["category"], "id":it["id"], "detail":it["detail"], "rationale":it["rationale"]} for it in notes],
                "topology":STRUCTURE_SUMMARY, "pacing":PATH_SUMMARY,
                "issues":issues, "categories":CATEGORIES}
        args.json.write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
        print(f"JSON report written to {args.json}")
    if args.verbose and blocking==0:
        s=STRUCTURE_SUMMARY; pace=PATH_SUMMARY
        print(f"\nAll {len(CATEGORIES)} categories passed:")
        for line in [
            f"1  structure       — {s.get('districts',0)} district decks + {s.get('connector_decks',0)} connector decks "
            f"+ {s.get('spurs',0)} spurs + {s.get('perimeter_spines',0)} perimeter spines ({s.get('floors',0)} floors), every deck snapped and joined",
            "2  navigation      — every checkpoint/interaction/spawn walkable and flow-field reachable",
            "3  dead ends       — 0 degree-1 nav cells, 0 dead-end sectors",
            "4  blocked corridors — no deck with a fully blocked cross-section, none under half width",
            f"5  narrow passages — no inter-prop gap <{MIN_WALKWAY} m, every doorway keeps ≥{DOOR_LANE_WARN:.0f} m of free lane",
            f"6  door/entrance   — floor edges %{MODULE}==0, every doorway keeps a walkable lane on both sides",
            "7  vertical        — single-level y=0 flat, no lift/ramp markup needed",
            "8  connectivity    — district graph connected, no articulation corridor",
            "9  isolated areas  — single walkable island, no island objectives",
            f"10 campaign path   — {pace.get('total',0):.0f} m tour (budget {pace.get('total_budget',0):.0f} m), longest leg "
            f"{pace.get('max_leg',0):.0f} m (budget {pace.get('leg_budget',0):.0f} m), each district visited once",
        ]:
            print(f"  ✔ {line}")
    return 1 if blocking else 0

if __name__=="__main__":
    sys.exit(main())
