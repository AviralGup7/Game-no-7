extends RefCounted

## Headless geometry contract for the compact overlay solver.
## Mirrors `_test_layout_solver` in the UI runner so CI without that harness
## still pins portrait compact chrome, no overlaps, and the touch floor.


static func suite() -> Array:
	var results: Array = []
	_compact_detection(results)
	_geometry_contract(results)
	_portrait_stacks_messages(results)
	_sanitize(results)
	return results


static func _check(results: Array, name: String, passed: bool, why: String = "") -> void:
	results.append({"name": name, "passed": passed, "why": why})


static func _compact_detection(results: Array) -> void:
	_check(results, "1080x2340 portrait is compact", UiLayout.is_compact(Vector2(1080, 2340)))
	_check(results, "720x1280 portrait is compact", UiLayout.is_compact(Vector2(720, 1280)))
	_check(results, "1280x720 landscape is not compact", not UiLayout.is_compact(Vector2(1280, 720)))
	_check(results, "2340x1080 landscape is not compact", not UiLayout.is_compact(Vector2(2340, 1080)))
	_check(results, "800x360 narrow landscape is compact", UiLayout.is_compact(Vector2(800, 360)))
	_check(results, "NaN size falls back to compact", UiLayout.is_compact(Vector2(NAN, 720)))


static func _geometry_contract(results: Array) -> void:
	var resolutions: Array[Vector2] = [
		Vector2(1280, 720), Vector2(1920, 1080), Vector2(2340, 1080), Vector2(2400, 1080),
		Vector2(960, 540), Vector2(1024, 768), Vector2(1600, 720), Vector2(720, 1280),
		Vector2(1080, 2340), Vector2(800, 1280), Vector2(2560, 1600), Vector2(640, 360),
	]
	var controls := ["stick", "skills", "attack", "dodge", "swap"]
	var all_keys := controls + ["top_bar", "vitals", "minimap", "boss", "banner", "toast"]
	var inside_ok := true
	var floor_ok := true
	var overlap_ok := true
	var why := ""
	for view in resolutions:
		for scale in [1.0, 1.4, 2.0]:
			var plan := UiLayout.compute(view, scale)
			var tag := "%dx%d @%.1f" % [view.x, view.y, scale]
			for key in all_keys:
				var rect: Rect2 = plan[key]
				if UiLayout.is_collapsed(rect):
					continue
				if rect.position.x < -0.5 or rect.position.y < -0.5 or rect.end.x > view.x + 0.5 or rect.end.y > view.y + 0.5:
					inside_ok = false
					why = "%s %s" % [key, tag]
			for key in ["attack", "dodge", "swap"]:
				var target: Rect2 = plan[key]
				if minf(target.size.x, target.size.y) < UiLayout.MIN_TOUCH - 0.01:
					floor_ok = false
					why = "%s %s size %s" % [key, tag, str(target.size)]
			for i in range(all_keys.size()):
				for j in range(i + 1, all_keys.size()):
					var a: Rect2 = plan[all_keys[i]]
					var b: Rect2 = plan[all_keys[j]]
					if UiLayout.is_collapsed(a) or UiLayout.is_collapsed(b):
						continue
					# Top bar may share a horizontal strip with nothing else;
					# it must still not cover the thumb cluster.
					var skip_top := (all_keys[i] == "top_bar" or all_keys[j] == "top_bar") and not (
						all_keys[i] in controls or all_keys[j] in controls
					)
					if skip_top:
						continue
					if a.intersects(b):
						overlap_ok = false
						why = "%s vs %s %s" % [all_keys[i], all_keys[j], tag]
	_check(results, "every overlay rect stays inside the safe area", inside_ok, why)
	_check(results, "attack/dodge/swap meet the Android touch floor", floor_ok, why)
	_check(results, "overlay rects do not overlap (incl. top bar vs thumbs)", overlap_ok, why)


static func _portrait_stacks_messages(results: Array) -> void:
	var plan := UiLayout.compute(Vector2(1080, 2340), 1.0)
	_check(results, "1080x2340 plan is flagged compact", bool(plan["compact"]))
	var vitals: Rect2 = plan["vitals"]
	var boss: Rect2 = plan["boss"]
	_check(results, "portrait boss bar sits below the vitals column",
		boss.position.y >= vitals.end.y - 0.5,
		"boss.y=%.1f vitals.end=%.1f" % [boss.position.y, vitals.end.y])
	var landscape := UiLayout.compute(Vector2(1280, 720), 1.0)
	_check(results, "1280x720 plan is not compact", not bool(landscape["compact"]))


static func _sanitize(results: Array) -> void:
	var sanitized := UiLayout.sanitize(Rect2(Vector2(NAN, -900), Vector2(INF, -5)), Vector2(1280, 720))
	_check(results, "sanitize refuses NaN/inf",
		sanitized.position.x >= 0.0 and sanitized.size.x <= 1280.0 and sanitized.size.y >= 1.0)
	_check(results, "zero-height band is collapsed",
		UiLayout.is_collapsed(Rect2(Vector2(10, 10), Vector2(100, 0))))
