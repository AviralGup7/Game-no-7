class_name WeaponInstance
extends RefCounted

## Runtime state for one equipped weapon: cooldowns, combo step, ammo, crit
## rolls. Binds a WeaponConfig with the wielder's derived stats (damage /
## cooldown / range / knockback / crit modifiers from ProgressionComponent).
## Headless-testable: time advances via explicit tick(); RNG via RngService.

signal combo_step_advanced(step: int)
signal reloaded()

const PHASE_READY := &"ready"
const PHASE_WINDUP := &"windup"
const PHASE_RECOVERY := &"recovery"
const PHASE_RELOADING := &"reloading"

var config: WeaponConfig = null
var phase: StringName = PHASE_READY
var combo_step: int = 0          # 0 = no chain in progress
var ammo: int = 0
var crit_seed_salt: int = RngService.STREAM_CRITS

# Wielder-derived modifiers (1.0 = neutral).
var damage_multiplier: float = 1.0
var cooldown_multiplier: float = 1.0
var range_bonus: float = 0.0
var knockback_multiplier: float = 1.0
var crit_chance_bonus: float = 0.0
var crit_multiplier_bonus: float = 0.0
var status_chance_bonus: float = 0.0
var projectile_count_bonus: int = 0
var projectile_pierce_bonus: int = 0

var _windup_left: float = 0.0
var _recovery_left: float = 0.0
var _chain_left: float = 0.0
var _reload_left: float = 0.0
var _rng := RngService.new()


func _init(cfg: WeaponConfig = null, run_seed: int = 0) -> void:
	config = cfg
	_rng.reseed(run_seed)
	if cfg != null and cfg.has_ammo():
		ammo = cfg.ammo_per_magazine


func reseed(run_seed: int) -> void:
	_rng.reseed(run_seed)


## Attempt to start a swing/shot. Returns the 1-based combo step, or 0 when the
## attack cannot start (cooldown, windup, empty magazine, reloading).
func try_start_attack() -> int:
	if config == null:
		return 0
	match phase:
		PHASE_WINDUP, PHASE_RELOADING:
			return 0
		PHASE_RECOVERY:
			if _chain_left <= 0.0 or combo_step >= config.step_count():
				return 0
			combo_step += 1
		PHASE_READY:
			combo_step = 1
	if config.has_ammo():
		if ammo <= 0:
			start_reload()
			combo_step = 0
			return 0
		ammo -= 1
	phase = PHASE_WINDUP
	_windup_left = config.windup
	combo_step_advanced.emit(combo_step)
	return combo_step


## Advance timers. Returns true on the exact tick the windup finishes (the hit
## must be resolved by the caller NOW via resolve damage helpers).
func tick(delta: float) -> bool:
	if not is_finite(delta) or delta <= 0.0:
		return false
	var resolved := false
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reload_left = 0.0
			phase = PHASE_READY
			combo_step = 0
			if config != null:
				ammo = config.ammo_per_magazine
			reloaded.emit()
		return false
	if phase == PHASE_WINDUP:
		_windup_left -= delta
		if _windup_left <= 0.0:
			phase = PHASE_RECOVERY
			_recovery_left = effective_cooldown()
			_chain_left = config.combo_window if config != null else 0.0
			resolved = true
	elif phase == PHASE_RECOVERY:
		_recovery_left -= delta
		_chain_left -= delta
		if _recovery_left <= 0.0:
			phase = PHASE_READY
			combo_step = 0
	return resolved


func start_reload() -> bool:
	if config == null or not config.has_ammo():
		return false
	if phase == PHASE_RELOADING or ammo >= config.ammo_per_magazine:
		return false
	phase = PHASE_RELOADING
	_reload_left = config.reload_seconds
	combo_step = 0
	return true


func is_reloading() -> bool:
	return phase == PHASE_RELOADING


func is_ready() -> bool:
	return phase == PHASE_READY


func is_chain_open() -> bool:
	return phase == PHASE_RECOVERY and _chain_left > 0.0 and config != null and combo_step < config.step_count()


func cooldown_remaining() -> float:
	return maxf(_recovery_left, 0.0)


func reload_remaining() -> float:
	return maxf(_reload_left, 0.0)


func chain_remaining() -> float:
	return maxf(_chain_left, 0.0)


func reset() -> void:
	phase = PHASE_READY
	combo_step = 0
	_windup_left = 0.0
	_recovery_left = 0.0
	_chain_left = 0.0
	_reload_left = 0.0
	if config != null and config.has_ammo():
		ammo = config.ammo_per_magazine


# ---------------- Derived combat values ----------------

func effective_damage() -> float:
	if config == null:
		return 0.0
	return maxf(config.base_damage * damage_multiplier * config.step_multiplier(maxi(combo_step, 1)), 0.0)


func effective_cooldown() -> float:
	if config == null:
		return 0.5
	return maxf(config.swing_cooldown * cooldown_multiplier, 0.05)


func effective_range() -> float:
	if config == null:
		return 0.0
	return maxf(config.attack_range + range_bonus, 0.5)


func effective_knockback() -> float:
	if config == null:
		return 0.0
	return maxf(config.knockback * knockback_multiplier, 0.0)


func effective_crit_chance() -> float:
	if config == null:
		return 0.0
	return clampf(config.crit_chance + crit_chance_bonus, 0.0, 1.0)


func effective_crit_multiplier() -> float:
	if config == null:
		return 1.0
	return maxf(config.crit_multiplier + crit_multiplier_bonus, 1.0)


func effective_projectile_count() -> int:
	if config == null:
		return 1
	return clampi(config.projectile_count + projectile_count_bonus, 1, RangedResolver.MAX_PROJECTILES_PER_SHOT)


func effective_projectile_pierce() -> int:
	if config == null:
		return 0
	return maxi(config.projectile_pierce + projectile_pierce_bonus, 0)


## Roll a critical hit for the CURRENT swing (uses the isolated crit stream).
func roll_crit() -> bool:
	return _rng.chance(crit_seed_salt, effective_crit_chance())


## Roll whether on-hit status effects apply for the current swing.
func roll_on_hit_effects() -> bool:
	if config == null or config.on_hit_effects.is_empty():
		return false
	return _rng.chance(RngService.STREAM_DROPS, clampf(config.on_hit_effect_chance + status_chance_bonus, 0.0, 1.0))


## Build a DamagePayload for the current swing (crit already rolled when
## `with_crit` is true). Direction/knockback vector is filled by the resolver.
func build_payload(source: Node, source_id: StringName) -> DamagePayload:
	var payload := DamagePayload.new()
	payload.amount = effective_damage()
	payload.source = source
	payload.source_id = source_id
	payload.damage_type = config.damage_type if config != null else &"physical"
	if config != null:
		payload.can_crit = config.crit_chance > 0.0 or crit_chance_bonus > 0.0
		payload.critical_multiplier = effective_crit_multiplier()
	return payload


func get_debug_snapshot() -> Dictionary:
	return {
		"weapon": String(config.weapon_id) if config != null else "none",
		"phase": String(phase),
		"combo_step": combo_step,
		"ammo": ammo,
		"damage": effective_damage(),
		"cooldown": effective_cooldown(),
		"range": effective_range(),
	}


## Interrupt a swing without replenishing ammo, skipping recovery, or cancelling reload.
func cancel_attack() -> void:
	_chain_left = 0.0
	combo_step = 0
	if phase == PHASE_WINDUP:
		_windup_left = 0.0
		_recovery_left = effective_cooldown()
		phase = PHASE_RECOVERY
