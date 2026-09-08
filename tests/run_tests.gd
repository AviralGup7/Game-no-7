extends SceneTree
## DIAGNOSTIC BUILD: per-file compile probe for the enemy pass. Loads each suspect
## script via path (no class_name references in this file, so it always compiles),
## emitting a workflow annotation per file so failures are visible without raw logs.

const PROBES := [
	"res://scripts/enemies/enemy_config.gd",
	"res://scripts/enemies/enemy_state.gd",
	"res://scripts/enemies/enemy_locomotion.gd",
	"res://scripts/enemies/enemy_navigator.gd",
	"res://scripts/enemies/enemy_striker.gd",
	"res://scripts/enemies/enemy_idle_state.gd",
	"res://scripts/enemies/enemy_chase_state.gd",
	"res://scripts/enemies/enemy_attack_state.gd",
	"res://scripts/enemies/enemy_hurt_state.gd",
	"res://scripts/enemies/enemy_dead_state.gd",
	"res://scripts/enemies/enemy_ranged_state.gd",
	"res://scripts/enemies/enemy_dash_state.gd",
	"res://scripts/enemies/enemy_fuse_state.gd",
	"res://scripts/enemies/enemy_state_machine.gd",
	"res://scripts/enemies/enemy_feedback.gd",
	"res://scripts/enemies/enemy_audio.gd",
	"res://scripts/enemies/enemy_animator.gd",
	"res://scripts/enemies/enemy_elite_affix.gd",
	"res://scripts/enemies/boss_phase_config.gd",
	"res://scripts/enemies/boss_controller.gd",
	"res://scripts/enemies/enemy_base.gd",
	"res://scripts/enemies/spawn_ledger.gd",
	"res://scripts/enemies/spawn_placer.gd",
	"res://scripts/enemies/spawn_patterns.gd",
	"res://scripts/enemies/spawn_manager.gd",
	"res://tests/doubles/fake_arena.gd",
	"res://tests/unit/test_enemy_behaviors.gd",
]


func _initialize() -> void:
	var bad := 0
	for path in PROBES:
		var s: Variant = load(path)
		if s == null:
			bad += 1
			print("::error title=Compile probe::%s FAILED to load/compile" % path)
		else:
			print("::notice::compile OK: %s" % path)
	print("DIAG probe: %d files, %d failures" % [PROBES.size(), bad])
	quit(1 if bad > 0 else 0)


func _process(_delta: float) -> bool:
	return false
