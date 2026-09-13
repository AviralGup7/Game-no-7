class_name CampaignBudgets
extends RefCounted

## Single typed home for the Station Zero Android performance budgets.
##
## Every runtime copy of a budget reads from here: CampaignDefinition clamps
## the authored caps against MAX_ACTIVE_ENEMIES / MAX_VISIBLE_DISTRICTS /
## WORLD_EXTENT_LIMIT, CampaignEncounters streams on STREAM_TICK_SECONDS with
## SPAWNS_PER_TICK inside SPAWN_DISTANCE / DESPAWN_DISTANCE and a
## FLOW_FIELD_RADIUS combat window, CampaignDirector re-runs A* after
## ROUTE_REFRESH_DISTANCE of player travel, and ArenaNavGrid bounds the coarse
## world build (WORLD_EXTENT_LIMIT / WORLD_CELL_LIMIT) and each one-off A*
## query (ASTAR_EXPANSION_LIMIT). tool/validate_campaign.py mirrors the same
## numbers for offline content checks, and
## tests/python/test_campaign_budgets.py fails the build if any copy drifts
## from this file — a budget changes HERE or not at all.
##
## The budgets exist because the station is 864 x 672 m (6x the original
## arena): 36,288 coarse nav cells fit under the cell cap with headroom, and
## every per-tick cost stays proportional to the ~18 actors around the player
## instead of to the whole deck.

## Simultaneous live encounter actors the streaming cap admits.
const MAX_ACTIVE_ENEMIES := 18

## Encounter actors admitted per streaming tick (spawn-cost ceiling per tick).
const SPAWNS_PER_TICK := 2

## Streaming tick cadence in seconds (spawn/despawn + flow-field guard).
const STREAM_TICK_SECONDS := 0.3

## Simultaneous visible district visual batches; the rest are distance-culled.
const MAX_VISIBLE_DISTRICTS := 3

## Expansion budget for one-off A* queries; hitting it yields the best partial
## route instead of an unbounded search (ArenaNavGrid.find_path).
const ASTAR_EXPANSION_LIMIT := 6000

## Player travel distance in metres that forces a campaign route re-search
## (CampaignDirector._update_route); between refreshes the cached route stands.
const ROUTE_REFRESH_DISTANCE := 12.0

## Largest authored station extent in metres the coarse nav grid accepts.
const WORLD_EXTENT_LIMIT := 1024.0

## Largest coarse-nav cell count (4 m cells) an authored station may occupy;
## keeps the blocked/flow arrays under ~200 KB.
const WORLD_CELL_LIMIT := 40960

## Combat flow-field half-window in metres around the player; it must cover
## every actor that can be live (spawn 70 m / despawn 90 m).
const FLOW_FIELD_RADIUS := 128.0

## Streaming distances in metres for encounter actors.
const SPAWN_DISTANCE := 70.0
const DESPAWN_DISTANCE := 90.0

## Loader row budgets enforced by CampaignDefinition.source_is_valid and
## mirrored by tool/validate_campaign.py, so offline validation rejects any
## table the APK loader would refuse.
const MAX_FLOOR_REGIONS := 64
const MAX_TABLE_ROWS := 512
