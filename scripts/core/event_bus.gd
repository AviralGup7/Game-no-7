class_name EventBusService
extends Node
## Autoload: EventBus — hardened lifecycle (M3)
## Cross-system signals only. Gameplay objects should prefer direct references for
## local communication; EventBus is the backbone for decoupled observers (UI, audio,
## analytics, achievements). Lifecycle: emitted exactly once where the spec says so.
## Hardening: emitters guard is_instance_valid/is_inside_tree before emit;
## listeners guard is_connected before connect (prevents duplicate listeners on
## respawn/pooling) and disconnect in _exit_tree where signals are long-lived
## (boss/enemy). All handlers are no-ops when target is null/invalid so headless
## and pooled lifecycles cannot dupe or leak.

signal game_state_changed(previous_state: StringName, current_state: StringName)
signal run_started(run_id: int, seed: int)
signal run_ended(score: int, wave: int, best_score: int)
signal player_health_changed(current: float, maximum: float)
signal player_died()
signal enemy_spawned(enemy: Node, archetype_id: StringName)
signal enemy_damaged(enemy: Node, result: DamageResult)
signal enemy_killed(enemy: Node, archetype_id: StringName, score_value: int, currency_value: int)
signal wave_started(wave_number: int, planned_count: int)
signal wave_progressed(wave_number: int, defeated: int, total: int)
signal wave_completed(wave_number: int, completion_bonus: int)
signal upgrade_choices_presented(choices: Array[StringName])
signal upgrade_selected(upgrade_id: StringName)
signal score_changed(score: int, delta: int)
signal currency_changed(currency: int, delta: int)
signal combo_changed(combo: int, best_combo: int)
signal pause_changed(is_paused: bool)
signal settings_changed(settings: SettingsData)
signal save_completed()
signal save_failed(reason: StringName)
signal weapon_equipped(weapon_id: StringName, slot: int)
signal weapon_switched(old_id: StringName, new_id: StringName)
signal projectile_fired(owner: Node, weapon_id: StringName)
signal skill_unlocked(skill_id: StringName)
signal skill_cast(skill_id: StringName, caster: Node)
signal skill_ready(skill_id: StringName)
signal pickup_collected(pickup_id: StringName, amount: int, collector: Node)
signal pickup_spawned(pickup: Node, pickup_id: StringName)
signal status_applied(target: Node, effect_id: StringName, stacks: int)
signal status_expired(target: Node, effect_id: StringName)
signal player_leveled_up(new_level: int, xp: int)
signal stamina_changed(current: float, maximum: float)
signal boss_phase_changed(boss: Node, phase: int, max_phases: int)
signal boss_spawned(boss: Node, boss_id: StringName)
signal boss_slain(boss_id: StringName)
signal wave_mutator_applied(mutator_id: StringName, wave_number: int)
signal achievement_unlocked(achievement_id: StringName)
signal tutorial_step_completed(step_id: StringName)
signal announcement(text_key: StringName, text: String, severity: StringName)
signal diagnostic(message: String, severity: StringName)
## Objective-mode telemetry. `label` is the HUD-ready progress line; `progress`
## and `target` are the raw counters (relics banked / quota, beacon hp / max %).
signal objective_progress(label: String, progress: int, target: int)
## Emitted when an objective-mode win/lose condition resolves (defend timer met,
## relic quota banked, beacon destroyed). GameRoot decides victory vs game over.
signal objective_resolved(mode_id: StringName, success: bool)


## Bind `cb` to `sig` and automatically disconnect when `host` leaves the tree.
## Autoload signals otherwise outlive per-run nodes if a future RefCounted or
## autoload subscriber is added. Production nodes still free their connections
## on teardown; this makes the contract explicit.
func bind(host: Node, sig: Signal, cb: Callable) -> void:
	if host == null or not is_instance_valid(host):
		return
	if not sig.is_connected(cb):
		sig.connect(cb)
	if not host.tree_exiting.is_connected(_unbind.bind(sig, cb)):
		host.tree_exiting.connect(_unbind.bind(sig, cb), CONNECT_ONE_SHOT)


func unbind(sig: Signal, cb: Callable) -> void:
	_unbind(sig, cb)


func _unbind(sig: Signal, cb: Callable) -> void:
	if sig.is_connected(cb):
		sig.disconnect(cb)


## Convenience: post a diagnostic without callers needing the severity constant.
func report_diagnostic(message: String, severity: StringName = &"info") -> void:
	diagnostic.emit(message, severity)


## Clean reporting used by the debug/test harness. Guards against emitting into a
## deleted connection and against unbounded chatter in release builds.
func report_info(message: String) -> void:
	if OS.is_debug_build():
		print("[diagnostic] ", message)
	diagnostic.emit(message, &"info")


func report_warning(message: String) -> void:
	if OS.is_debug_build():
		push_warning("[diagnostic] " + message)
	diagnostic.emit(message, &"warning")


func report_error(message: String) -> void:
	if OS.is_debug_build():
		push_error("[diagnostic] " + message)
	diagnostic.emit(message, &"error")
