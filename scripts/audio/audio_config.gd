class_name AudioConfig
extends Resource

## Data-driven audio cue definition: bus routing, volume/pitch ranges (randomized
## per play for variety), voice limits and music-layer tags. Instances live beside
## the streams in res://data/audio/ (there is no data/audio_config/ directory) and
## AudioManager + MusicManager consume them, binding a cue to its stream by id.

@export var cue_id: StringName = &""
@export var display_name: String = ""
@export var bus: StringName = &"SFX"
@export_range(-80.0, 6.0, 0.1) var volume_db: float = 0.0
@export_range(0.0, 24.0, 0.1) var volume_var_db: float = 0.0
@export_range(0.1, 4.0, 0.01) var pitch: float = 1.0
@export_range(0.0, 2.0, 0.01) var pitch_var: float = 0.0
@export_range(1, 32) var max_voices: int = 4
## Minimum seconds between plays of this cue (spam guard).
@export_range(0.0, 60.0, 0.05) var cooldown: float = 0.0
## Music-only: intensity layer (0 calm .. 3 climax) for adaptive mixing.
@export_range(0, 8) var music_layer: int = 0
@export var loop: bool = false
@export var tags: Array[StringName] = []

const VALID_BUSES := [&"Master", &"Music", &"SFX", &"UI"]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if String(cue_id).is_empty():
		problems.append("cue_id is empty")
	if bus not in VALID_BUSES:
		problems.append("invalid bus: %s" % String(bus))
	if volume_db < -60.0 or volume_db > 12.0:
		problems.append("volume_db out of sane range")
	if volume_var_db < 0.0:
		problems.append("volume_var_db cannot be negative")
	if pitch <= 0.0:
		problems.append("pitch must be > 0")
	if pitch_var < 0.0:
		problems.append("pitch_var cannot be negative")
	if max_voices < 1:
		problems.append("max_voices must be >= 1")
	if cooldown < 0.0:
		problems.append("cooldown cannot be negative")
	if music_layer < 0 or music_layer > 3:
		problems.append("music_layer must be in [0,3]")
	return problems


## Randomized volume for one play (deterministic when rng is seeded).
func roll_volume_db(rng: RandomNumberGenerator) -> float:
	if rng == null or volume_var_db <= 0.0:
		return volume_db
	return volume_db + rng.randf_range(-volume_var_db, volume_var_db)


func roll_pitch(rng: RandomNumberGenerator) -> float:
	if rng == null or pitch_var <= 0.0:
		return pitch
	return maxf(pitch + rng.randf_range(-pitch_var, pitch_var), 0.05)


## Built-in playback contract for a cue. This is what makes the schema live:
## the engine consults these defaults for every play, and a registered
## (code- or .tres-sourced) config overrides them per cue.
##
## Tuning notes:
##   * Footsteps/shots/hits are the spam sources — short cooldowns + higher
##     caps keep them alive but bounded (cooldown first, cap second).
##   * One-shot feedback cues (hurt, level up, wave bell) get max_voices 1:
##     a second instance adds muddiness, not information.
##   * UI cues route to the "UI" bus so menus stay out of the combat mix.
##   * Generic cues keep zero variance: multi-variant streams already carry
##     their own ±3 dB randomization (AudioStreamRandomizer), so rolling on
##     top would double-dip the mix.

## cue -> [bus, max_voices, cooldown_s, volume_var_db, pitch_var]
const DEFAULT_MAX_VOICES := 4
const _TUNED: Dictionary = {
	# Spam sources: bounded but allowed to layer.
	"player_step": [&"SFX", 6, 0.05, 0.0, 0.02],
	"player_shot": [&"SFX", 8, 0.02, 1.0, 0.03],
	"enemy_hit": [&"SFX", 6, 0.03, 0.0, 0.02],
	"enemy_dash": [&"SFX", 4, 0.06, 0.0, 0.0],
	"enemy_windup": [&"SFX", 4, 0.10, 0.0, 0.0],
	"enemy_explosion": [&"SFX", 4, 0.08, 0.0, 0.0],
	"enemy_spawn": [&"SFX", 6, 0.04, 0.0, 0.0],
	"player_dodge": [&"SFX", 3, 0.05, 0.0, 0.03],
	"pickup": [&"SFX", 4, 0.05, 1.0, 0.05],
	# One-shot feedback: never layer on itself.
	"player_hurt": [&"SFX", 1, 0.10, 0.0, 0.0],
	"player_death": [&"SFX", 1, 0.5, 0.0, 0.0],
	"player_low_health": [&"SFX", 1, 0.8, 0.0, 0.0],
	"enemy_death": [&"SFX", 8, 0.03, 0.0, 0.05],
	"level_up": [&"SFX", 1, 0.5, 0.0, 0.0],
	"boss_spawned": [&"SFX", 1, 1.0, 0.0, 0.0],
	"boss_slain": [&"SFX", 1, 1.0, 0.0, 0.0],
	"game_over": [&"SFX", 1, 1.0, 0.0, 0.0],
	"wave_started": [&"SFX", 1, 0.5, 0.0, 0.0],
	"wave_completed": [&"SFX", 1, 0.5, 0.0, 0.0],
	# Menus: their own bus, no combat bleed.
	"ui_confirm": [&"UI", 2, 0.05, 0.0, 0.0],
	"ui_back": [&"UI", 2, 0.05, 0.0, 0.0],
	"upgrade_select": [&"UI", 2, 0.05, 0.0, 0.0],
	# Music ids (defensive: they should never reach play_sfx).
	"music_menu": [&"Music", 1, 0.0, 0.0, 0.0],
	"music_calm": [&"Music", 1, 0.0, 0.0, 0.0],
	"music_battle": [&"Music", 1, 0.0, 0.0, 0.0],
	"music_boss": [&"Music", 1, 0.0, 0.0, 0.0],
	"music_victory": [&"Music", 1, 0.0, 0.0, 0.0],
}


static func for_cue(id: StringName) -> AudioConfig:
	var cfg := AudioConfig.new()
	cfg.cue_id = id
	cfg.bus = &"SFX"
	cfg.max_voices = DEFAULT_MAX_VOICES
	var tuned: Variant = _TUNED.get(String(id))
	if tuned == null:
		return cfg
	cfg.bus = tuned[0]
	cfg.max_voices = tuned[1]
	cfg.cooldown = tuned[2]
	cfg.volume_var_db = tuned[3]
	cfg.pitch_var = tuned[4]
	return cfg
