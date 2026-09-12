extends RefCounted

## Headless unit tests for GameMode, its authored configs, Narrator, Prestige, and BuildEffects tags.
##
## The mode/prestige cases used to prove that the code tables had the right numbers in them. The
## numbers are authored data now (`res://data/game_modes/`, `res://data/prestige/ladder.tres`), so
## what these cases prove instead is that a file is *resolved* — that the id in a save, a mode card,
## or a wave plan reaches the config that carries its copy — plus the shape guarantees the loader
## checks and the shipped values themselves (`tests/python/test_regress_run_modes.py` mirrors every
## number, so a rebalance must be a deliberate edit there).


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
		"name": "Every MODE_ handle names a file that resolves (no dead handles)",
		"passed": GameMode.MODES.size() == GameMode.all_mode_ids().size()
			and _every_handle_resolves(),
		"why": "a const that names no .tres is how unlock_prestige survived unread",
	})
	results.append({
		"name": "GameMode.validated falls back to standard",
		"passed": GameMode.validated(&"nope") == GameMode.MODE_STANDARD
			and GameMode.validated(GameMode.MODE_BOSS_RUSH) == GameMode.MODE_BOSS_RUSH,
		"why": "",
	})
	results.append({
		"name": "An unknown mode resolves no config instead of borrowing Standard's",
		"passed": GameMode.resolve(&"nope") == null
			and GameMode.resolve(GameMode.MODE_SURVIVAL) != null,
		"why": "def() used to hand back Standard's record for any id it did not know",
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
	# The five scripted duels, wave for wave. These sizes were a formula (`mini(2 + wave, 6)` adds,
	# a heavy from 3, a ranged+dasher pair at 5) until the row carried them; the row must reproduce it.
	results.append({
		"name": "Boss Rush script escalates wave by wave exactly",
		"passed": GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 1, 42).size() == 4
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 2, 42).size() == 5
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 3, 42).size() == 7
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 4, 42).size() == 8
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 5, 42).size() == 10
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 3, 42).count(&"heavy") == 1
			and GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 2, 42).count(&"heavy") == 0,
		"why": str(GameMode.spawn_queue(GameMode.MODE_BOSS_RUSH, 5, 42)),
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
		"name": "Campaign's unscripted middle waves come from the planner, escalated",
		"passed": GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 12, 7)
				== WavePlanner.extended_queue_for_wave(14, 7)
			and GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 11, 7)
				== WavePlanner.extended_queue_for_wave(13, 7)
			and not GameMode.spawn_queue(GameMode.MODE_CAMPAIGN, 11, 7).is_empty(),
		"why": "waves 11-13 have a beat and no archetype list, so the +2 planner rule must still run",
	})
	results.append({
		"name": "Campaign beat sheet covers the arc and nothing beyond it",
		"passed": not Narrator.beat_text(GameMode.MODE_CAMPAIGN, 1).is_empty()
			and not Narrator.beat_text(GameMode.MODE_CAMPAIGN, 15).is_empty()
			and Narrator.beat_text(GameMode.MODE_CAMPAIGN, 16).is_empty()
			and Narrator.beat_text(GameMode.MODE_SURVIVAL, 1).is_empty(),
		"why": Narrator.beat_text(GameMode.MODE_CAMPAIGN, 15),
	})
	results.append({
		"name": "Every scripted campaign wave is announced",
		"passed": _campaign_arc_is_narrated(),
		"why": "the beat sheet and the spawn script used to be two tables that could drift apart",
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
		"name": "A mutator pool only a scaling mode owns is drawn by count",
		"passed": GameMode.challenge_mutators(GameMode.MODE_BOSS_RUSH, 8) == GameMode.forced_mutators(GameMode.MODE_BOSS_RUSH)
			and GameMode.forced_mutators(GameMode.MODE_BOSS_RUSH) == [&"elite_surge"],
		"why": "non-scaling modes keep their authored list at every rank",
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
	# The cadence rule, measured against the planner it wraps: the mode adds exactly one archetype on
	# its authored wave and nothing otherwise. Pinning the delta (not a count) is what stops the
	# every_n fields from being tuned into a no-op without anyone noticing.
	results.append({
		"name": "Mode cadence adds one archetype on its authored wave only",
		"passed": GameMode.spawn_queue(GameMode.MODE_DEFEND, 3, 7).size()
				- WavePlanner.extended_queue_for_wave(4, 7).size() == 1
			and GameMode.spawn_queue(GameMode.MODE_DEFEND, 2, 7).size()
				- WavePlanner.extended_queue_for_wave(3, 7).size() == 0
			and GameMode.spawn_queue(GameMode.MODE_COLLECT, 4, 7).size()
				- WavePlanner.extended_queue_for_wave(6, 7).size() == 1,
		"why": "%d/%d" % [GameMode.spawn_queue(GameMode.MODE_DEFEND, 3, 7).size(),
				GameMode.spawn_queue(GameMode.MODE_DEFEND, 2, 7).size()],
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
		"name": "Defend + Collect objective labels reflect live progress",
		"passed": "Beacon" in GameMode.objective_label(GameMode.MODE_DEFEND, 1, 10.0, 0, 42)
			and "Relics" in GameMode.objective_label(GameMode.MODE_COLLECT, 1, 0.0, 0, 5)
			and ("5 / %d" % GameMode.collect_target(GameMode.MODE_COLLECT)) in GameMode.objective_label(GameMode.MODE_COLLECT, 1, 0.0, 0, 5),
		"why": GameMode.objective_label(GameMode.MODE_COLLECT, 1, 0.0, 0, 5),
	})

	# --- Authored configs refuse the shapes that used to be legal ---
	results.append({
		"name": "GameModeConfig rejects a target its objective will not read",
		"passed": _rejects(_mode_with(func(cfg: GameModeConfig) -> void:
				cfg.objective = GameModeConfig.OBJECTIVE_CLEAR_WAVES
				cfg.collect_target = 7), "collect_target"),
		"why": "a quota under a wave-count objective is dead data, which is what this phase deleted",
	})
	results.append({
		"name": "GameModeConfig rejects an objective outside its vocabulary",
		"passed": _rejects(_mode_with(func(cfg: GameModeConfig) -> void:
				cfg.objective = &"eat_everything"), "objective"),
		"why": "",
	})
	results.append({
		"name": "GameModeConfig rejects duplicate wave plans",
		"passed": _rejects(_mode_with(func(cfg: GameModeConfig) -> void:
				cfg.wave_plans = [_plan(2, [&"basic"], "", ""), _plan(2, [&"fast"], "", "")]), "two wave plans"),
		"why": "the first row used to win silently inside a Dictionary",
	})
	results.append({
		"name": "GameModeConfig rejects a row that neither spawns nor speaks",
		"passed": _rejects(_mode_with(func(cfg: GameModeConfig) -> void:
				cfg.wave_plans = [_plan(3, [], "", "")]), "delete the row"),
		"why": "",
	})
	results.append({
		"name": "Every shipped mode config validates clean",
		"passed": _all_modes_validate(),
		"why": "the authored files are the contract; this is the layer that reads them as they ship",
	})
	results.append({
		"name": "The shipped prestige ladder validates clean",
		"passed": Prestige.ladder() != null and Prestige.ladder().validate().is_empty(),
		"why": str(Prestige.ladder().validate()) if Prestige.ladder() != null else "no ladder",
	})
	results.append({
		"name": "GameModeConfig rejects a scaling mode with nothing to scale",
		"passed": _rejects(_mode_with(func(cfg: GameModeConfig) -> void:
				cfg.scales_with_prestige = true), "prestige_mutator_pool"),
		"why": "",
	})
	results.append({
		"name": "PrestigeLadderConfig rejects titles that do not cover the ladder",
		"passed": _rejects(_ladder_with(func(cfg: PrestigeLadderConfig) -> void:
				cfg.max_rank = 10
				cfg.titles = PackedStringArray(["Unproven", "Survivor"])), "titles"),
		"why": "TITLES.stop(short) + title_for's default used to print 'Unproven' at rank 9",
	})
	results.append({
		"name": "PrestigeLadderConfig rejects a rung that is gentler than the one below",
		"passed": _rejects(_ladder_with(func(cfg: PrestigeLadderConfig) -> void:
				cfg.challenge_tiers = _softer_ladder()),
				"shorter or gentler"),
		"why": "the ladder promised 'harder, richer, longer'; nothing checked it",
	})
	results.append({
		"name": "ChallengeTier rejects a zero-wave rung",
		"passed": _tier("Broken", 0, 1.5, 1.4, 0).validate().size() > 0,
		"why": "",
	})

	# --- Narrator: the arena's voice is the arena's own ---
	results.append({
		"name": "Narrator has arena lore for all three arenas",
		"passed": not Narrator.arena_intro(&"default_arena").is_empty()
			and not Narrator.arena_intro(&"ember_crucible").is_empty()
			and not Narrator.arena_intro(&"frost_hollow").is_empty(),
		"why": "",
	})
	results.append({
		"name": "An unknown arena says nothing instead of quoting The Pit",
		"passed": Narrator.arena_intro(&"no_such_arena").is_empty()
			and Narrator.arena_mid(&"no_such_arena").is_empty()
			and Narrator.arena_intro(&"frost_hollow") != Narrator.arena_intro(&"default_arena"),
		"why": "ARENA_LORE.get(id, ARENA_LORE[default]) gave every new arena the first arena's voice",
	})
	results.append({
		"name": "Mode intros and victory lines exist for every mode",
		"passed": _every_mode_has_a_voice(),
		"why": "",
	})
	results.append({
		"name": "Victory copy still says what the announcer's match used to say",
		"passed": Narrator.victory_line(GameMode.MODE_BOSS_RUSH) == "The pantheon yields. Five crowns are yours."
			and Narrator.victory_line(GameMode.MODE_CHALLENGE) == "Challenge complete. The glass did not break you."
			and Narrator.victory_line(GameMode.MODE_STANDARD) == "Victory. The stand holds.",
		"why": Narrator.victory_line(GameMode.MODE_SURVIVAL),
	})
	results.append({
		# The first-of-kind pass authored its copy onto the enemy, so the case survives here — but the
		# line now comes out of `data/enemies/<id>_enemy.tres`, which is why an empty blurb is allowed to
		# mean "this archetype is never announced" instead of being a fall-through.
		"name": "Narrator enemy blurbs cover the headline archetypes",
		"passed": not Narrator.enemy_blurb(&"warlord").is_empty()
			and not Narrator.enemy_blurb(&"exploder").is_empty()
			and not Narrator.enemy_blurb(&"dasher").is_empty(),
		"why": Narrator.enemy_blurb(&"warlord"),
	})

	# --- Prestige ladder ---
	results.append({
		"name": "Prestige cost escalates; max gates",
		"passed": Prestige.cost_for_rank(0) == 2000
			and Prestige.cost_for_rank(1) > Prestige.cost_for_rank(0)
			and Prestige.can_prestige(Prestige.max_rank(), 999999, 1.0) == &"maxed"
			and Prestige.can_prestige(0, 0, 1.0) == &"insufficient_funds"
			and Prestige.can_prestige(0, 999999, 0.1) == &"armory_incomplete"
			and Prestige.can_prestige(0, 2000, 0.7) == &"ok",
		"why": "",
	})
	results.append({
		"name": "Prestige multipliers and titles scale",
		"passed": Prestige.score_multiplier(0) == 1.0
			and Prestige.score_multiplier(5) > Prestige.score_multiplier(1)
			and Prestige.title_for(0) == "Unproven"
			and Prestige.title_for(10) == "Last Stand"
			and Prestige.title_for(9) != "Unproven"
			and not Prestige.cosmetics_for_rank(1).is_empty()
			and Prestige.all_cosmetics_up_to(5).size() >= Prestige.cosmetics_for_rank(1).size(),
		"why": Prestige.title_for(5),
	})
	results.append({
		"name": "The ladder's titles cover exactly its ranks",
		"passed": Prestige.ladder() != null
			and Prestige.ladder().titles.size() == Prestige.max_rank() + 1,
		"why": "MAX_PRESTIGE and TITLES were independent and could disagree",
	})
	results.append({
		"name": "Challenge tier unlocks with prestige",
		"passed": Prestige.challenge_tier(0) == 0
			and Prestige.challenge_tier(4) >= 2
			and Prestige.challenge_tier_def(4) != null
			and Prestige.challenge_tier_def(4).score_mult > 1.5,
		"why": str(Prestige.challenge_tier_def(4)),
	})
	results.append({
		"name": "Challenge tier accessors escalate with rank",
		"passed": Prestige.challenge_tier_mutator_count(0) == 2
			and Prestige.challenge_tier_mutator_count(8) >= 4
			and Prestige.challenge_tier_waves(8) > Prestige.challenge_tier_waves(0)
			and Prestige.challenge_tier_currency_mult(8) > Prestige.challenge_tier_currency_mult(0)
			and Prestige.challenge_tier_label(10) == "Last Stand Challenge",
		"why": Prestige.challenge_tier_label(10),
	})
	results.append({
		"name": "Every rank resolves exactly one rung, and never a missing one",
		"passed": _every_rank_resolves(),
		"why": "min(floor(rank/2), size-1) made a gap in the int keys mean the easiest tier",
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
	var all_prestige_cosmetics := Prestige.all_cosmetics_up_to(Prestige.max_rank())
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


## Every MODE_ handle in GameMode must name a file that resolves, and every file must have a handle.
static func _every_handle_resolves() -> bool:
	var listed := PackedStringArray()
	for id in GameMode.all_mode_ids():
		listed.append(String(id))
	for handle in GameMode.MODES:
		if not listed.has(String(handle)):
			return false
		if GameMode.resolve(handle) == null:
			return false
	return listed.size() == GameMode.MODES.size()


static func _campaign_arc_is_narrated() -> bool:
	var cap := GameMode.max_waves(GameMode.MODE_CAMPAIGN)
	if cap <= 0:
		return false
	for wave in range(1, cap + 1):
		if Narrator.beat_text(GameMode.MODE_CAMPAIGN, wave).is_empty():
			return false
	return true


static func _every_mode_has_a_voice() -> bool:
	for mode_id in GameMode.all_mode_ids():
		if GameMode.intro_line(mode_id).is_empty():
			return false
		if GameMode.victory_line(mode_id).is_empty():
			return false
	return true


## Every rank from 0 to the top must resolve a rung, and the rung must never soften as rank rises.
static func _every_rank_resolves() -> bool:
	var ladder := Prestige.ladder()
	if ladder == null or ladder.challenge_tiers.is_empty():
		return false
	var last_waves := 0
	var last_mult := 0.0
	for rank in range(0, Prestige.max_rank() + 1):
		var tier := ladder.tier_for_rank(rank)
		if tier == null or tier.max_waves < 1:
			return false
		if tier.max_waves < last_waves or tier.score_mult < last_mult:
			return false
		last_waves = tier.max_waves
		last_mult = tier.score_mult
	return true


static func _all_modes_validate() -> bool:
	for mode_id in GameMode.all_mode_ids():
		var cfg := GameMode.resolve(mode_id)
		if cfg == null:
			return false
		if not cfg.validate().is_empty():
			return false
	return not GameMode.all_mode_ids().is_empty()


static func _mode_with(mutate: Callable) -> GameModeConfig:
	var cfg := GameModeConfig.new()
	cfg.mode_id = &"test_mode"
	cfg.display_name = "Test Mode"
	cfg.blurb = "A mode built in code for validation tests."
	cfg.intro_line = "Test."
	cfg.victory_line = "Test won."
	cfg.max_waves = 6
	cfg.upgrade_every = 2
	mutate.call(cfg)
	return cfg


static func _ladder_with(mutate: Callable) -> PrestigeLadderConfig:
	var cfg := PrestigeLadderConfig.new()
	var tiers: Array[ChallengeTier] = [_tier("Standard Challenge", 0, 1.5, 1.4, 12)]
	cfg.max_rank = 4
	cfg.titles = PackedStringArray(["Unproven", "Survivor", "Veteran", "Champion", "Warlord-Slayer"])
	cfg.challenge_tiers = tiers
	mutate.call(cfg)
	return cfg


static func _softer_ladder() -> Array[ChallengeTier]:
	var tiers: Array[ChallengeTier] = [_tier("Easy", 0, 2.0, 2.0, 12), _tier("Hard", 2, 1.2, 1.2, 8)]
	return tiers


static func _plan(wave: int, archetypes: Array, title: String, line: String) -> GameModeWavePlan:
	var plan := GameModeWavePlan.new()
	plan.wave_number = wave
	for id in archetypes:
		plan.archetypes.append(StringName(String(id)))
	plan.beat_title = title
	plan.beat_line = line
	return plan


static func _tier(label: String, rank: int, score: float, currency: float, waves: int) -> ChallengeTier:
	var tier := ChallengeTier.new()
	tier.label = label
	tier.unlock_rank = rank
	tier.score_mult = score
	tier.currency_mult = currency
	tier.max_waves = waves
	return tier


## validate() must report something naming `needle` — the message is part of the contract, because a
## config that rejects for the wrong reason is a config that will reject the wrong file.
static func _rejects(cfg: ValidatedConfig, needle: String) -> bool:
	var problems: Array[String] = cfg.validate()
	if problems.is_empty():
		return false
	for problem in problems:
		if needle in problem:
			return true
	return false
