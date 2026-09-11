class_name SpatialVoicePool
extends Node

## Pool of AudioStreamPlayer3D voices for world Foley (enemy hits, dashes,
## explosions, spawn pops). UI and player-centric 2D SFX stay on AudioManager's
## existing pools; this node never plays a Music or UI cue.
##
## Pre-claim distance cull (SpatialAttenuation) drops far emitters before a
## voice is taken. Follow-emitters (play_on) snap the 3D player to the host
## each tick so a running grunt doesn't leave its scream behind.

const MAX_VOICES := 16
const TOKEN_BASE := 200
const UNIT_SIZE := 8.0
const MAX_DISTANCE := 42.0

var _bank := VoiceBank.new()
var _emitters: Array = []  # Node3D or null, parallel to voices
var _queued_place: Dictionary = {}  # idx -> {at: Vector3, emitter: Node3D}
var _listener: Node3D = null
var _policy: SfxPolicy = null


func configure(policy: SfxPolicy, clock: Callable) -> void:
	_policy = policy
	var voices: Array = []
	_emitters.clear()
	for i in MAX_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = UNIT_SIZE
		p.max_distance = MAX_DISTANCE
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		voices.append(p)
		_emitters.append(null)
	_bank.setup(voices, policy, TOKEN_BASE, &"SFX")
	_bank.clock = clock
	process_mode = Node.PROCESS_MODE_ALWAYS


func set_listener(node: Node3D) -> void:
	_listener = node if (node != null and is_instance_valid(node)) else null


func get_listener_position() -> Vector3:
	if _listener != null and is_instance_valid(_listener):
		return _listener.global_position
	return Vector3.ZERO


func has_listener() -> bool:
	return _listener != null and is_instance_valid(_listener)


func active_count() -> int:
	return _bank.active_count()


func owns_token(token: int) -> bool:
	return _bank.owns_token(token)


## World play at a point. Returns false on cull / missing stream / bank full.
func play_at(
		cue_id: StringName,
		at: Vector3,
		vol: float,
		pitch: float,
		stream: AudioStream,
		action: StringName,
		steal_token: int
) -> bool:
	if stream == null:
		return false
	if not _is_finite_vec(at):
		return false
	if not SpatialAttenuation.is_hearable(get_listener_position(), at, MAX_DISTANCE):
		return false
	var ok := _bank.claim(cue_id, vol, pitch, stream, action, steal_token)
	if not ok:
		return false
	_place_claimed(at, null)
	return true


## World play that follows `emitter` until the voice ends or the node frees.
func play_on(
		cue_id: StringName,
		emitter: Node3D,
		vol: float,
		pitch: float,
		stream: AudioStream,
		action: StringName,
		steal_token: int
) -> bool:
	if emitter == null or not is_instance_valid(emitter):
		return false
	var at := emitter.global_position
	if stream == null or not _is_finite_vec(at):
		return false
	if not SpatialAttenuation.is_hearable(get_listener_position(), at, MAX_DISTANCE):
		return false
	var ok := _bank.claim(cue_id, vol, pitch, stream, action, steal_token)
	if not ok:
		return false
	_place_claimed(at, emitter)
	return true


func _place_claimed(at: Vector3, emitter: Node3D) -> void:
	var idx := _bank.last_claimed
	var p: AudioStreamPlayer3D = null
	if idx >= 0 and idx < _bank.size() and _bank.cues[idx] != &"":
		p = _bank.players[idx] as AudioStreamPlayer3D
	if p != null and bool(p.playing):
		p.global_position = at
		_emitters[idx] = emitter
		return
	if _bank.pending.is_empty():
		return
	var victim := int((_bank.pending.back() as Dictionary).get("player_idx", -1))
	if victim < 0:
		return
	_queued_place[victim] = {"at": at, "emitter": emitter}


func _process(delta: float) -> void:
	_bank.tick(delta)
	_flush_queued_places()
	_follow_emitters()


func _flush_queued_places() -> void:
	if _queued_place.is_empty():
		return
	var keep: Dictionary = {}
	for idx in _queued_place.keys():
		var i := int(idx)
		var p: AudioStreamPlayer3D = null
		if i >= 0 and i < _bank.size():
			p = _bank.players[i] as AudioStreamPlayer3D
		if p == null or not bool(p.playing) or _bank.cues[i] == &"":
			keep[i] = _queued_place[idx]
			continue
		var rec: Dictionary = _queued_place[idx]
		var at: Vector3 = rec.get("at", Vector3.ZERO)
		if _is_finite_vec(at):
			p.global_position = at
		var emitter: Node3D = rec.get("emitter") as Node3D
		_emitters[i] = emitter
	_queued_place = keep


func _follow_emitters() -> void:
	for i in _emitters.size():
		var node := _emitters[i] as Node3D
		if node == null:
			continue
		var p: AudioStreamPlayer3D = _bank.players[i] as AudioStreamPlayer3D
		if p == null or not bool(p.playing):
			_emitters[i] = null
			continue
		if not is_instance_valid(node):
			_emitters[i] = null
			continue
		var at := node.global_position
		if _is_finite_vec(at):
			p.global_position = at


func stop_all() -> void:
	_bank.stop_all()
	for i in _emitters.size():
		_emitters[i] = null


func _is_finite_vec(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func get_debug_snapshot() -> Dictionary:
	var snap: Dictionary = _bank.get_debug_snapshot()
	snap["listener"] = has_listener()
	snap["following"] = _following_count()
	return snap


func _following_count() -> int:
	var n := 0
	for slot in _emitters:
		if slot != null:
			n += 1
	return n
