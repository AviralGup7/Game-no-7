class_name EffectSkillCatalog
extends RefCounted

## Per-skill VFX identity for EffectDirector: the shape texture, ground-ring radius,
## burst scale and particle tuning of every skill, extracted so adding or retuning a
## skill's look touches one data table instead of the director's dispatch.
##
## Colour and the legacy aliases stay on EffectDirector.SKILL_COLORS: that table is
## the canonical skill-id list skill configs are validated against.
##
## Every lookup has a default, so an unknown/legacy id still produces the generic
## burst instead of nothing.

const RING_TEXTURES := {
	&"bladestorm": "res://assets/scifi/fx/trace.png",
	&"frost_nova": "res://assets/scifi/fx/ring.png",
	&"frost_nova_skill": "res://assets/scifi/fx/ring.png",
	&"phantom_rush": "res://assets/scifi/fx/smoke.png",
	&"seismic_slam": "res://assets/scifi/fx/smoke.png",
	&"warcry": "res://assets/scifi/fx/spark.png",
	&"warcry_skill": "res://assets/scifi/fx/spark.png",
	&"chain_lightning": "res://assets/scifi/fx/spark.png",
	&"mending_light": "res://assets/scifi/fx/flare.png",
	&"shatterwave": "res://assets/scifi/fx/ring.png",
}
const BURST_TEXTURES := {
	&"bladestorm": "res://assets/scifi/fx/trace.png",
	&"frost_nova": "res://assets/scifi/fx/spark.png",
	&"frost_nova_skill": "res://assets/scifi/fx/spark.png",
	&"phantom_rush": "res://assets/scifi/fx/smoke.png",
	&"seismic_slam": "res://assets/scifi/fx/spark.png",
	&"warcry": "res://assets/scifi/fx/spark.png",
	&"warcry_skill": "res://assets/scifi/fx/spark.png",
	&"chain_lightning": "res://assets/scifi/fx/spark.png",
	&"mending_light": "res://assets/scifi/fx/flare.png",
	&"shatterwave": "res://assets/scifi/fx/ring.png",
}
## Ground-ring radius per skill (metres); the shared default keeps unknown ids visible.
const RADII := {
	&"frost_nova": 4.2,
	&"frost_nova_skill": 4.2,
	&"seismic_slam": 3.6,
	&"bladestorm": 3.2,
	&"shatterwave": 4.8,
	&"chain_lightning": 3.0,
	&"phantom_rush": 2.6,
	&"mending_light": 2.4,
	&"warcry": 2.8,
	&"warcry_skill": 2.8,
}
## Burst scale per skill — bigger tells for the AoE skills.
const BURST_SCALES := {
	&"seismic_slam": 1.55,
	&"shatterwave": 1.65,
	&"frost_nova": 1.45,
	&"frost_nova_skill": 1.45,
	&"bladestorm": 1.35,
	&"chain_lightning": 1.25,
	&"phantom_rush": 1.18,
	&"mending_light": 1.38,
	&"warcry": 1.32,
	&"warcry_skill": 1.32,
}
## Particle spread per skill: whirls (bladestorm) and slams read differently.
const BURST_SPREADS := {
	&"bladestorm": 85.0,
	&"seismic_slam": 45.0,
	&"phantom_rush": 68.0,
	&"chain_lightning": 75.0,
}
## Particle count per skill (the generic burst recipe uses EffectTemplates.BURST_AMOUNT).
const BURST_AMOUNTS := {
	&"bladestorm": 28,
	&"seismic_slam": 26,
	&"phantom_rush": 20,
	&"chain_lightning": 24,
}

const DEFAULT_RADIUS := 2.8
const DEFAULT_BURST_SCALE := 1.35


static func ring_texture(skill_id: StringName, fallback: String) -> String:
	return RING_TEXTURES.get(skill_id, fallback)


static func burst_texture(skill_id: StringName, fallback: String) -> String:
	return BURST_TEXTURES.get(skill_id, fallback)


static func ring_radius(skill_id: StringName) -> float:
	return RADII.get(skill_id, DEFAULT_RADIUS)


static func burst_scale(skill_id: StringName) -> float:
	return BURST_SCALES.get(skill_id, DEFAULT_BURST_SCALE)


## Unlisted skills fall back to the generic template recipe (EffectTemplates).
static func burst_spread(skill_id: StringName) -> float:
	return BURST_SPREADS.get(skill_id, EffectTemplates.BURST_SPREAD_DEGREES)


static func burst_amount(skill_id: StringName) -> int:
	return BURST_AMOUNTS.get(skill_id, EffectTemplates.BURST_AMOUNT)
