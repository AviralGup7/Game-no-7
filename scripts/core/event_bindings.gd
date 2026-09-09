class_name EventBindings
extends RefCounted

## Tracks EventBus (or any) Signal connections so a node can disconnect every
## one in `_exit_tree()`. Per-run observers used to connect and never unbind;
## Godot drops connections when the node dies, but RefCounted callables and
## re-parented listeners leaked. Call `bind()` instead of `connect()` and
## `unbind_all()` on teardown.

var _pairs: Array = []


func bind(sig: Signal, fn: Callable) -> void:
	if sig.is_connected(fn):
		return
	sig.connect(fn)
	_pairs.append({"signal": sig, "fn": fn})


func unbind_all() -> void:
	for pair in _pairs:
		var sig: Signal = pair["signal"]
		var fn: Callable = pair["fn"]
		if sig.get_object() != null and is_instance_valid(sig.get_object()) and sig.is_connected(fn):
			sig.disconnect(fn)
	_pairs.clear()


func size() -> int:
	return _pairs.size()
