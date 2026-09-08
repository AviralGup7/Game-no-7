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
	return results
