class_name EffectPriorities
extends RefCounted

## VFX pool priority ladder — higher wins when a pool saturates.
##
## Lives in its own script with no project references so the event-handler module can
## name tiers without a constants cycle through EffectDirector (which instantiates that
## module). EffectDirector re-exports these as its PRIORITY_* constants.

const CRITICAL := 100
const BOSS := 90
const PLAYER := 80
const SKILL := 60
const ENEMY_DEATH := 50
const SPAWN := 45
const PICKUP := 35
const ENEMY_HIT := 30
const HIT := 30
const STATUS := 25
const AMBIENT := 10
