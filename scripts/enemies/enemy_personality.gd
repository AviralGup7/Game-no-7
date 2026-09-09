class_name EnemyPersonality
extends RefCounted

## Deterministic per-enemy personality, rolled once from (run_seed, serial) —
## the same stream family as the approach offset, so a replay of a run spawns
## the exact same "cast" of individuals.
##
## This is what turns a sheet of identical archetypes into a pack of
## individuals (research: "the trick to making players believe an enemy is
## alive is noise in its decisions, not perfection" — see
## docs/ENEMY_AI_RESEARCH.md):
##
##   * aggression / caution drive flanking, retreat-on-grief and attack cadence;
##   * aim_skill widens ranged shot spread (nobody is a laser);
##   * reaction scales the stimulus-to-response delay so two grunts spotted at
##     the same instant answer at different times;
##   * dash_willingness makes some dashers fake charges by simply not dashing;
##   * strafe_bias prefers a side for flanks so enemies circle their way.

var aggression := 0.5     # 0 docile .. 1 aggressive
var caution := 0.5        # 0 reckless .. 1 cautious
var aim_skill := 0.55     # 0 inaccurate .. 1 precise
var strafe_bias := 0.0    # -1 favors one flank .. +1 the other
var reaction := 1.0       # multiplier on config reaction_time (0.5 .. 1.6)
var wander_scale := 1.0   # scales idle wander radius (0.6 .. 1.5)
var dash_willingness := 0.8  # chance a telegraphed dash is actually taken
var cd_spread := 0.5      # how much of the config cooldown jitter this enemy uses
var home_offset_angle := 0.0  # anchor for its personal idle wander spot


static func roll(run_seed: int, serial: int) -> EnemyPersonality:
	var p := EnemyPersonality.new()
	var rng := RngService.make_generator(run_seed, RngService.STREAM_AI + serial * 13 + 57)
	p.aggression = rng.randf_range(0.2, 0.9)
	p.caution = clampf(1.0 - p.aggression + rng.randf_range(-0.25, 0.25), 0.1, 0.9)
	p.aim_skill = rng.randf_range(0.3, 0.85)
	p.strafe_bias = rng.randf_range(-1.0, 1.0)
	p.reaction = rng.randf_range(0.5, 1.6)
	p.wander_scale = rng.randf_range(0.6, 1.5)
	p.dash_willingness = rng.randf_range(0.35, 1.0)
	p.cd_spread = rng.randf_range(0.2, 1.0)
	p.home_offset_angle = rng.randf_range(0.0, TAU)
	return p
