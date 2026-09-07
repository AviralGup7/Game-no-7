class_name AudioConfig
extends Resource

## Data-driven audio cue definition: bus routing, volume/pitch ranges (randomized
## per play for variety), voice limits and music-layer tags. Instances live under
## res://data/audio_config/ — actual streams stay in res://data/audio/ and bind by
## matching cue id. The AudioManager + MusicManager consume these.

@export var cue_id: StringName = &""
@export var display_name: String = ""
@export var bus: StringName = &"SFX"
@export var volume_db: float = 0.0
@export var volume_var_db: float = 0.0
@export var pitch: float = 1.0
@export var pitch_var: float = 0.0
@export var max_voices: int = 4
## Minimum seconds between plays of this cue (spam guard).
@export var cooldown: float = 0.0
## Music-only: intensity layer (0 calm .. 3 climax) for adaptive mixing.
@export var music_layer: int = 0
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
