extends SceneTree
## DIAGNOSTIC BUILD: loads the full enemy test runner and four integration slices
## by path (this file references no class_names, so it always compiles). Whichever
## load() returns null for is the slice with the compile error.

const PROBES := [
	"res://tests/diag_var1.gd",
	"res://tests/diag_var2.gd",
	"res://tests/diag_var3.gd",
	"res://tests/diag_var4.gd",
	"res://tests/diag_full.gd",
]


func _initialize() -> void:
	var bad := 0
	for path in PROBES:
		var s: Variant = load(path)
		if s == null:
			bad += 1
			print("::error title=Compile probe::%s FAILED to compile" % path)
		else:
			print("::notice::compile OK: %s" % path)
	print("DIAG probe: %d files, %d failures" % [PROBES.size(), bad])
	quit(1 if bad > 0 else 0)


func _process(_delta: float) -> bool:
	return false
