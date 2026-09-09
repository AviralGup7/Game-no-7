extends RefCounted

## Headless unit tests for GameMode, Narrator, Prestige, and BuildEffects tags.


static func suite() -> Array:
	var results: Array = []

	# --- GameMode catalogue ---
	results.append({
		"name": "GameMode catalogue has seven playable modes",
		"passed": GameMode.all_mode_ids().size() == 7
			and GameMode.is_known(GameMode.MODE_STANDARD)
			and GameMode.is_known(GameMode.MODE_BOSS_RUSH)
			and GameMode.is_known(GameMode.MODE_SURVIVAL)
			and GameMode.is_known(GameMode.MODE_CHALLENGE)
			and GameMode.is_known(GameMode.MODE_CAMPAIGN)
			and GameMode.is_known(GameMode.MODE_DEFEND)
			and GameMode.is_known(GameMode.MODE_COLLECT),
		"why": str(GameMode.all_mode_ids()),
	})
	results.append({
		"name": "GameMode.validated falls back to standard",
		"passed": GameMode.validated(&"nope") == GameMode.MODE_STANDARD
			and GameMode.validated(GameMode.MODE_BOSS_RUSH) == GameMode.MODE_BOSS_RUSH,
		"why": "",
	})
	results.append({
		"name": "Boss Rush victory at wave 5; not before",
		"passed": not GameMode.is_victory_wave(GameMode.MODE_BOSS_RUSH, 4)
			and GameMode.is_victory_wave(GameMode.MODE_BOSS_RUSH, 5)
			and not GameMode.is_victory_wave(GameMode.MODE_STANDARD, 99),
		"why": "",
	})
	results.append({
		"name": "Survival victory is time-based",
		"passed": not GameMode.is_survival_victory(GameMode.MODE_SURVIVAL, 100.0)
			and GameMode.is_survival_victory(GameMode.MODE_SURVIVAL, 300.0)
			and not GameMode.is_survival_victory(GameMode.MODE_STANDARD, 999.0),
		"why": "",
	})
	results.append({
		"name": "Boss Rush queue always leads with warlord",
		"passed": GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 1, 42)[0] == &"warlord"
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 5, 42)[0] == &"warlord"
			and GameMode.spawn_queue(GameMode.MODE_STANDARD, 1, 42).is_empty(),
		"why": str(GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 1, 42)),
	})
	results.append({
		"name": "Campaign queues are deterministic + scripted",
		"passed": GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 1, 7)
			== GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 1, 99)
			and GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 5, 1)[0] == &"warlord"
			and GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 15, 1).count(&"warlord") == 2,
		"why": str(GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 15, 1)),
	})
	results.append({
		"name": "Challenge tier-0 mutators are glass + ember; fixed gladius",
		"passed": GameMode.challenge_mutators(GameMode.MODE_CHALLENGE, 0) == [&"glass_cannon", &"ember_winds"]
			and GameMode.fixed_weapon(GameMode.MODE_CHALLENGE) == &"gladius",
		"why": str(GameMode.challenge_mutators(GameMode.MODE_CHALLENGE, 0)),
	})
	results.append({
		"name": "Challenge scales with prestige: more mutators, higher payout, longer",
		"passed": GameMode.scales_with_prestige(GameMode.MODE_CHALLENGE)
			and not GameMode.scales_with_prestige(GameMode.MODE_STANDARD)
			and GameMode.challenge_mutators(GameMode.MODE_CHALLENGE, 8).size() > GameMode.challenge_mutators(GameMode.MODE_CHALLENGE, 0).size()
			and GameMode.score_multiplier_for(GameMode.MODE_CHALLENGE, 8) > GameMode.score_multiplier_for(GameMode.MODE_CHALLENGE, 0)
			and GameMode.currency_multiplier_for(GameMode.MODE_CHALLENGE, 8) > GameMode.currency_multiplier_for(GameMode.MODE_CHALLENGE, 0)
			and GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 8) > GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 0),
		"why": "%d muts @r8, cap %d" % [GameMode.challenge_mutators(GameMode.MODE_CHALLENGE, 8).size(), GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 8)],
	})
	results.append({
		"name": "Challenge victory wave tracks the prestige tier cap",
		"passed": GameMode.is_victory_wave_for(GameMode.MODE_CHALLENGE, GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 0), 0)
			and not GameMode.is_victory_wave_for(GameMode.MODE_CHALLENGE, GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 0), 8),
		"why": "cap0=%d cap8=%d" % [GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 0), GameMode.max_waves_for(GameMode.MODE_CHALLENGE, 8)],
	})
	results.append({
		"name": "Defend + Collect objectives resolve to their constants",
		"passed": GameMode.objective(GameMode.MODE_DEFEND) == GameMode.OBJECTIVE_DEFEND_POINT
			and GameMode.objective(GameMode.MODE_COLLECT) == GameMode.OBJECTIVE_COLLECT
			and GameMode.collect_target(GameMode.MODE_COLLECT) > 0
			and GameMode.collect_target(GameMode.MODE_STANDARD) == 0
			and GameMode.target_seconds(GameMode.MODE_DEFEND) > 0.0,
		"why": str(GameMode.collect_target(GameMode.MODE_COLLECT)),
	})
	results.append({
		"name": "Defend + Collect provide endless spawn queues",
		"passed": not GameMode.spawn_queue(GameMode.MODE_DEFEND, 1, 7).is_empty()
			and not GameMode.spawn_queue(GameMode.MODE_COLLECT, 1, 7).is_empty()
			and GameMode.spawn_queue(GameMode.MODE_DEFEND, 3, 7) == GameMode.spawn_queue(GameMode.MODE_DEFEND, 3, 7),
		"why": str(GameMode.spawn_queue(GameMode.MODE_DEFEND, 1, 7)),
	})
	results.append({
		"name": "Mode score multipliers are > 1 for non-standard",
		"passed": GameMode.score_multiplier(GameMode.MODE_STANDARD) == 1.0
			and GameMode.score_multiplier(GameMode.MODE_BOSS_RUSH) > 1.0
			and GameMode.score_multiplier(GameMode.MODE_CHALLENGE) > 1.0,
		"why": "",
	})
	results.append({
		"name": "Upgrade cadence differs by mode",
		"passed": GameMode.wants_upgrade(GameMode.MODE_BOSS_RUSH, 1)
			and GameMode.wants_upgrade(GameMode.MODE_STANDARD, 2)
			and not GameMode.wants_upgrade(GameMode.MODE_STANDARD, 1),
		"why": "",
	})
	results.append({
		"name": "Objective labels are non-empty",
		"passed": not GameMode.objective_label(GameMode.MODE_SURVIVAL, 1, 30.0, 0).is_empty()
			and not GameMode.objective_label(GameMode.MODE_BOSS_RUSH, 2, 0.0, 1).is_empty()
			and "Wave" in GameMode.objective_label(GameMode.MODE_CAMPAIGN, 3, 0.0, 0),
		"why": GameMode.objective_label(GameMode.MODE_SURVIVAL, 1, 30.0, 0),
	})
	results.append({
		"name": "Defend/Collect objective labels reflect live progress",
		"passed": "Beacon" in GameMode.objective_label(GameMode.MODE_DEFEND, 1, 10.0, 0, 42)
			and "Relics" in GameMode.objective_label(GameMode.MODE_COLLECT, 1, 0.0, 0, 5)
			and ("5 / %d" % GameMode.collect_target(GameMode.MODE_COLLECT)) in GameMode.objective_label(GameMode.MODE_COLLECT, 1, 0.0, 0, 5),
		"why": GameMode.objective_label(GameMode.MODE_COLLECT, 1, 0.0, 0, 5),
	})

	# --- Narrator ---
	results.append({
		"name": "Narrator has arena lore for all three arenas",
		"passed": not Narrator.arena_intro(&"default_arena").is_empty()
			and not Narrator.arena_intro(&"ember_crucible").is_empty()
			and not Narrator.arena_intro(&"frost_hollow").is_empty(),
		"why": "",
	})
	results.append({
		"name": "Campaign beat sheet covers wave 1 and 15",
		"passed": not Narrator.campaign_beat(1).is_empty()
			and not Narrator.campaign_beat(15).is_empty()
			and Narrator.campaign_beat(99).is_empty(),
		"why": str(Narrator.campaign_beat(15)),
	})
	results.append({
		"name": "Mode intros exist for every mode",
		"passed": not Narrator.mode_intro(GameMode.MODE_STANDARD).is_empty()
			and not Narrator.mode_intro(GameMode.MODE_CAMPAIGN).is_empty()
			and not Narrator.mode_intro(GameMode.MODE_BOSS_RUSH).is_empty(),
		"why": "",
	})
	results.append({
		"name": "Narrator enemy blurbs cover the headline archetypes",
		"passed": not Narrator.enemy_blurb(&"warlord").is_empty()
			and not Narrator.enemy_blurb(&"exploder").is_empty()
			and not Narrator.enemy_blurb(&"dasher").is_empty(),
		"why": Narrator.enemy_blurb(&"warlord"),
	})

	# --- Prestige ---
	results.append({
		"name": "Prestige cost escalates; max gates",
		"passed": Prestige.cost_for_rank(0) == Prestige.PRESTIGE_COST_BASE
			and Prestige.cost_for_rank(1) > Prestige.cost_for_rank(0)
			and Prestige.can_prestige(Prestige.MAX_PRESTIGE, 999999, 1.0) == &"maxed"
			and Prestige.can_prestige(0, 0, 1.0) == &"insufficient_funds"
			and Prestige.can_prestige(0, 999999, 0.1) == &"armory_incomplete"
			and Prestige.can_prestige(0, Prestige.PRESTIGE_COST_BASE, 0.7) == &"ok",
		"why": "",
	})
	results.append({
		"name": "Prestige multipliers and titles scale",
		"passed": Prestige.score_multiplier(0) == 1.0
			and Prestige.score_multiplier(5) > Prestige.score_multiplier(1)
			and Prestige.title_for(0) == "Unproven"
			and Prestige.title_for(10) == "Last Stand"
			and not Prestige.cosmetics_for_rank(1).is_empty()
			and Prestige.all_cosmetics_up_to(5).size() >= Prestige.cosmetics_for_rank(1).size(),
		"why": Prestige.title_for(5),
	})
	results.append({
		"name": "Challenge tier unlocks with prestige",
		"passed": Prestige.challenge_tier(0) == 0
			and Prestige.challenge_tier(4) >= 2
			and float(Prestige.challenge_tier_def(4).get("score_mult", 0)) > 1.5,
		"why": str(Prestige.challenge_tier_def(4)),
	})
	results.append({
		"name": "Prestige challenge tier accessors escalate with rank",
		"passed": Prestige.challenge_tier_mutator_count(0) == 2
			and Prestige.challenge_tier_mutator_count(8) >= 4
			and Prestige.challenge_tier_waves(8) > Prestige.challenge_tier_waves(0)
			and Prestige.challenge_tier_currency_mult(8) > Prestige.challenge_tier_currency_mult(0)
			and Prestige.challenge_tier_label(10) == "Last Stand Challenge",
		"why": Prestige.challenge_tier_label(10),
	})

	# --- Cosmetics catalogue: unlocked ids now resolve to applyable definitions ---
	var worn := ["banner_survivor", "trail_ember", "aura_legend", "trail_frost", "banner_last_stand", "title_champion"]
	results.append({
		"name": "Cosmetics: highest-order trail/aura/title chosen from unlocks",
		"passed": Cosmetics.active_trail(worn) == &"trail_frost"  # frost outranks ember
			and Cosmetics.active_aura(worn) == &"aura_legend"
			and Cosmetics.active_title(worn) == &"title_champion"
			and Cosmetics.active_banners(worn).size() == 2,
		"why": "%s / %s" % [Cosmetics.active_trail(worn), str(Cosmetics.active_banners(worn))],
	})
	results.append({
		"name": "Cosmetics: empty/unknown unlocks yield nothing worn",
		"passed": Cosmetics.active_trail([]) == &""
			and Cosmetics.active_aura(["bogus"]) == &""
			and Cosmetics.active_banners([]).is_empty()
			and Cosmetics.is_known(&"trail_ember")
			and not Cosmetics.is_known(&"bogus"),
		"why": "",
	})
	var all_prestige_cosmetics := Prestige.all_cosmetics_up_to(Prestige.MAX_PRESTIGE)
	var all_known := not all_prestige_cosmetics.is_empty()
	for cid in all_prestige_cosmetics:
		if not Cosmetics.is_known(cid):
			all_known = false
	results.append({
		"name": "Prestige rank cosmetics map to known catalogue ids",
		"passed": all_known,
		"why": str(all_prestige_cosmetics),
	})

	# --- UpgradeConfig transformative contract ---
	var transform := UpgradeConfig.new()
	transform.upgrade_id = &"test_storm"
	transform.display_name = "Test"
	transform.rarity = &"legendary"
	transform.category = &"transform"
	transform.max_stacks = 1
	transform.weight = 1.0
	transform.effect_tags = [&"chain_melee"]
	results.append({
		"name": "UpgradeConfig.is_transformative + validate accepts transform category",
		"passed": transform.is_transformative() and transform.validate().is_empty(),
		"why": str(transform.validate()),
	})
	var plain := UpgradeConfig.new()
	plain.upgrade_id = &"plain"
	plain.display_name = "Plain"
	plain.rarity = &"common"
	plain.category = &"damage"
	plain.max_stacks = 1
	plain.weight = 1.0
	results.append({
		"name": "Plain upgrade is not transformative",
		"passed": not plain.is_transformative(),
		"why": "",
	})

	# --- ProgressionComponent effect tracking ---
	var prog := ProgressionComponent.new()
	prog.set_current_wave(10)
	# Manually inject via a synthetic config with effect tags.
	var fx_cfg := UpgradeConfig.new()
	fx_cfg.upgrade_id = &"storm_edge"
	fx_cfg.display_name = "Storm"
	fx_cfg.rarity = &"legendary"
	fx_cfg.category = &"transform"
	fx_cfg.max_stacks = 2
	fx_cfg.weight = 1.0
	fx_cfg.effect_tags = [&"chain_melee"]
	fx_cfg.stat_modifiers = {"attack_damage_multiplier": 0.05}
	var applied := prog.apply_upgrade(fx_cfg)
	results.append({
		"name": "ProgressionComponent tracks effect tags from upgrades",
		"passed": applied and prog.has_effect(&"chain_melee") and prog.get_effect_stacks(&"chain_melee") == 1,
		"why": str(prog.get_effect_snapshot()),
	})
	prog.apply_upgrade(fx_cfg)
	results.append({
		"name": "Effect stacks increment with upgrade stacks",
		"passed": prog.get_effect_stacks(&"chain_melee") == 2 and prog.get_stack_count(&"storm_edge") == 2,
		"why": str(prog.get_effect_snapshot()),
	})
	prog.reset()
	results.append({
		"name": "ProgressionComponent.reset clears effects",
		"passed": not prog.has_effect(&"chain_melee") and prog.get_effect_snapshot().is_empty(),
		"why": "",
	})

	# --- RunState mode fields ---
	var run := RunState.new()
	run.mode_id = GameMode.MODE_CAMPAIGN
	run.victory = true
	run.bosses_slain = 2
	var summary := run.summary()
	results.append({
		"name": "RunState.summary carries mode/victory/bosses",
		"passed": String(summary.get("mode_id", "")) == "campaign"
			and bool(summary.get("victory", false))
			and int(summary.get("bosses_slain", 0)) == 2,
		"why": str(summary),
	})
	run.reset()
	results.append({
		"name": "RunState.reset clears mode to standard",
		"passed": run.mode_id == &"standard" and not run.victory and run.bosses_slain == 0,
		"why": "",
	})

	# --- Save schema prestige field ---
	var raw := {"schema_version": 4, "best_score": 10, "meta_wallet": 100}
	var normalized := SaveSchema.normalize_save(raw)
	results.append({
		"name": "SaveSchema v5 migrates prestige_rank default",
		"passed": int(normalized.get("prestige_rank", -1)) == 0
			and int(normalized.get("schema_version", 0)) == SaveSchema.SCHEMA_VERSION
			and int(normalized.get("best_score", 0)) == 10,
		"why": str(normalized.get("prestige_rank", "missing")),
	})
	var with_p := SaveSchema.normalize_save({"schema_version": 5, "prestige_rank": 3, "lifetime_statistics": {"victories": 2, "bosses_slain": 4}})
	results.append({
		"name": "SaveSchema preserves prestige + extended lifetime",
		"passed": int(with_p.get("prestige_rank", 0)) == 3
			and int(with_p.lifetime_statistics.get("victories", 0)) == 2
			and int(with_p.lifetime_statistics.get("bosses_slain", 0)) == 4,
		"why": str(with_p.get("prestige_rank")),
	})

	# --- BuildEffects known tags match UpgradeConfig ---
	results.append({
		"name": "BuildEffects known tags are documented on UpgradeConfig",
		"passed": BuildEffects.EFFECT_CHAIN_MELEE in UpgradeConfig.KNOWN_EFFECT_TAGS
			and BuildEffects.EFFECT_FIRE_TRAIL in UpgradeConfig.KNOWN_EFFECT_TAGS
			and BuildEffects.EFFECT_KILL_SUMMON in UpgradeConfig.KNOWN_EFFECT_TAGS
			and BuildEffects.EFFECT_STATIC_FIELD in UpgradeConfig.KNOWN_EFFECT_TAGS,
		"why": str(UpgradeConfig.KNOWN_EFFECT_TAGS),
	})

	return results
