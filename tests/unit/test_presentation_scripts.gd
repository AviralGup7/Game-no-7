extends RefCounted

## Compile smoke test for the runtime-only presentation scripts (arena theme,
## decorator, character/enemy mounting, VFX director, audio integrator). These are
## normally only instantiated in-game, so under CI we force them to parse by loading
## each script resource and asserting it compiles (load() returns a GDScript, or null
## on a parse error). No autoloads or live scenes are needed.

const SCRIPTS := [
	"res://scripts/audio/audio_asset_integrator.gd",
	"res://scripts/arena/arena.gd",
	"res://scripts/arena/arena_decorator.gd",
	"res://scripts/visuals/character_visuals.gd",
	"res://scripts/visuals/effect_director.gd",
	"res://scripts/visuals/ring_fade.gd",
	"res://scripts/visuals/visual_mount.gd",
]


static func suite() -> Array:
	var results: Array = []
	for path in SCRIPTS:
		var s := load(path)
		results.append({
			"name": "script parses: %s" % path.get_file(),
			"passed": s != null,
			"why": "load() returned %s" % ("GDScript" if s != null else "null (parse error)"),
		})
	_ring_fade_honors_authored_alpha(results)
	return results


static func _ring_fade_honors_authored_alpha(results: Array) -> void:
	var ring := RingFade.new()
	var mi := MeshInstance3D.new()
	mi.name = "Disc"
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.08, 0.95)
	mi.material_override = mat
	ring.add_child(mi)
	ring.trigger(0.5)
	var got := (mi.material_override as StandardMaterial3D).albedo_color.a
	results.append({
		"name": "ring fade keeps authored boss/high-contrast alpha",
		"passed": is_equal_approx(got, 0.95),
		"why": "a=%.3f" % got,
	})
	var spent := RingFade.new()
	var disc := MeshInstance3D.new()
	disc.name = "Disc"
	var spent_mat := StandardMaterial3D.new()
	spent_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	disc.material_override = spent_mat
	spent.add_child(disc)
	spent.trigger(0.5)
	var reset := (disc.material_override as StandardMaterial3D).albedo_color.a
	results.append({
		"name": "ring fade restores alpha on a fully-faded pooled ring",
		"passed": is_equal_approx(reset, 0.45),
		"why": "a=%.3f" % reset,
	})
	ring.free()
	spent.free()
