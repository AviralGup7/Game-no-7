class_name UiLayout
extends RefCounted
## Single source of truth for gameplay-overlay geometry (HUD, minimap, boss frame,
## banner, toast, virtual stick, action cluster, skill bar).
##
## Every value is derived from the *safe-area* size and the accessibility text
## scale, so the same math drives every Android aspect ratio (16:9, 18:9, 19.5:9,
## 4:3 tablets, portrait) without magic per-screen offsets. The functions are
## pure and static so they can be exercised headlessly at many resolutions.

## Minimum on-screen size of a touch target in logical units. 1280x720 logical
## on a 1080p phone is ~1.8 physical px per unit, so 88 units clears the 48dp
## Android accessibility floor with margin.
const MIN_TOUCH := 88.0
const GAP := 12.0
const SKILL_SLOTS := 3
const SKILL_SEPARATION := 8.0
## Landscape width below this uses the stacked (portrait) message band even if
## the device is wider than it is tall (small windows, 4:3 splits).
const NARROW_WIDTH := 900.0


static func gutter(size: Vector2) -> float:
	return clampf(minf(size.x, size.y) * 0.028, 12.0, 28.0)


static func top_bar_height(text_scale: float) -> float:
	return 52.0 * clampf(text_scale, 1.0, 2.0)


## Compact chrome: stacked message band, shorter HUD captions.
## Portrait (taller than wide) is always compact — 1080x2340 is the common
## Android portrait and is *wider* than NARROW_WIDTH, so a width-only test
## used to keep landscape chrome on a tall phone.
static func is_compact(size: Vector2) -> bool:
	if not is_finite(size.x) or not is_finite(size.y):
		return true
	return size.x < NARROW_WIDTH or size.x < size.y


## Full overlay solution. Returns Rect2 values keyed by element name, all in
## safe-area local coordinates. Guarantees, verified headlessly at every common
## Android resolution and every accessibility text scale:
##   * every rect lies inside the safe area;
##   * touch targets are never smaller than MIN_TOUCH;
##   * the stick, action cluster and skill bar never overlap each other;
##   * the message band (boss / banner / toast) never covers a control or the
##     side columns, collapsing to zero height instead of stacking on top.
static func compute(size: Vector2, text_scale: float) -> Dictionary:
	var view := Vector2(maxf(size.x, 320.0), maxf(size.y, 240.0))
	if not is_finite(view.x) or not is_finite(view.y):
		view = Vector2(1280.0, 720.0)
	var scale := clampf(text_scale, 0.8, 2.0)
	if not is_finite(scale):
		scale = 1.0
	var pad := gutter(view)
	var bar_h := top_bar_height(scale)
	var top := pad + bar_h + GAP
	var compact := is_compact(view)

	# --- bottom controls -----------------------------------------------------
	var attack_r := clampf(minf(view.x, view.y) * 0.085, MIN_TOUCH * 0.5, 74.0)
	var minor_r := maxf(attack_r * 0.8, MIN_TOUCH * 0.5)
	var cluster_w := attack_r * 2.0 + minor_r * 2.0 + GAP
	var cluster_h := minor_r * 2.0 + attack_r * 2.0 + GAP
	var cluster := Rect2(
		Vector2(view.x - pad - cluster_w, view.y - pad - cluster_h), Vector2(cluster_w, cluster_h)
	)
	var stick := Rect2(
		Vector2(pad, 0.0),
		Vector2(clampf(view.x * 0.32, 180.0, 360.0), clampf(view.y * 0.42, 180.0, 300.0))
	)
	stick.position.y = view.y - pad - stick.size.y

	# Skill bar always sits inline between the stick and the cluster; if that
	# channel is too narrow the stick yields width rather than the bar stacking
	# over the thumb zones.
	var skill_h := (170.0 if scale > 1.3 else 124.0)
	var inline_min := MIN_TOUCH * float(SKILL_SLOTS) + SKILL_SEPARATION * float(SKILL_SLOTS - 1)
	var left := stick.end.x + GAP
	var right := cluster.position.x - GAP
	if right - left < inline_min:
		stick.size.x = maxf(cluster.position.x - GAP - inline_min - GAP - pad, 110.0)
		left = stick.end.x + GAP
	var skills := Rect2(
		Vector2(left, view.y - pad - skill_h), Vector2(maxf(right - left, inline_min), skill_h)
	)
	var controls_top := minf(minf(stick.position.y, cluster.position.y), skills.position.y)
	if controls_top < top:
		# Very short viewport: shrink stick, skills, AND the action cluster.
		# The previous path only shrank stick/skills, so on a 320x240 / large
		# text-scale window the attack cluster climbed through the status strip.
		var floor_y := top
		var room := maxf(view.y - pad - floor_y, MIN_TOUCH)
		var orig_cluster_h := cluster.size.y
		stick.size.y = maxf(minf(stick.size.y, room), MIN_TOUCH)
		stick.position.y = view.y - pad - stick.size.y
		skills.size.y = maxf(minf(skills.size.y, room), MIN_TOUCH)
		skills.position.y = view.y - pad - skills.size.y
		cluster.size.y = maxf(minf(cluster.size.y, room), MIN_TOUCH)
		cluster.position.y = view.y - pad - cluster.size.y
		var s := clampf(cluster.size.y / maxf(orig_cluster_h, 1.0), 0.35, 1.0)
		attack_r *= s
		minor_r *= s
		controls_top = minf(minf(stick.position.y, cluster.position.y), skills.position.y)

	var actions := _action_rects(cluster, attack_r, minor_r)
	var attack: Rect2 = actions["attack"]
	var dodge: Rect2 = actions["dodge"]
	var swap: Rect2 = actions["swap"]

	# --- top strip and side columns -----------------------------------------
	var top_bar := Rect2(Vector2(pad, pad), Vector2(view.x - pad * 2.0, bar_h))
	var available := maxf(controls_top - GAP - top, 0.0)
	var side_h := available
	if compact:
		# Portrait/small: the message band lives below the columns, so reserve it.
		side_h = maxf(available - clampf(available * 0.45, 96.0, 180.0) - GAP, 40.0)
	var map_size := clampf(minf(view.x, view.y) * 0.2, 96.0, 150.0)
	# Below 48px of vertical room the columns are illegible anyway: collapse them
	# rather than squash them into the controls.
	var columns_fit := side_h >= 48.0
	var minimap := Rect2(
		Vector2(view.x - pad - map_size, top),
		Vector2(map_size, minf(map_size, side_h) if columns_fit else 0.0)
	)
	var vitals := Rect2(
		Vector2(pad, top),
		Vector2(
			clampf(view.x * 0.3, 200.0, 300.0),
			minf(200.0 if scale > 1.3 else 148.0, side_h) if columns_fit else 0.0
		)
	)

	# --- message band: boss frame, banner, toast, stacked top to bottom ------
	var band_top := ((maxf(minimap.end.y, vitals.end.y) + GAP) if columns_fit else top) if compact else top
	var band_bottom := controls_top - GAP
	var cursor := band_top
	var band: Array[Rect2] = []
	for preferred in [74.0, 104.0, 52.0]:
		var height := minf(preferred, maxf(band_bottom - cursor, 0.0))
		if height < 20.0:
			# No honest room left: collapse to zero height rather than overlap.
			band.append(Rect2(Vector2(pad, clampf(cursor, 0.0, view.y - 1.0)), Vector2(maxf(view.x - pad * 2.0, 1.0), 0.0)))
			continue
		band.append(Rect2(Vector2(pad, cursor), Vector2(view.x - pad * 2.0, height)))
		cursor += height + GAP
	var boss := band[0]
	var banner := band[1]
	var toast := band[2]
	if not compact:
		var boss_w := clampf(view.x * 0.36, 300.0, 460.0)
		boss.position.x = (view.x - boss_w) * 0.5
		boss.size.x = boss_w
		var inset_l := maxf(vitals.end.x + GAP, pad)
		var inset_r := minf(minimap.position.x - GAP, view.x - pad)
		if inset_r - inset_l >= 240.0:
			banner.position.x = inset_l
			banner.size.x = inset_r - inset_l
			toast.position.x = inset_l
			toast.size.x = inset_r - inset_l
		else:
			# Too narrow to sit beside the columns: drop below them if it fits.
			var shift := maxf(minimap.end.y, vitals.end.y) + GAP - banner.position.y
			if shift > 0.0 and banner.end.y + shift <= band_bottom and toast.end.y + shift <= band_bottom:
				banner.position.y += shift
				toast.position.y += shift

	return {
		"gutter": pad,
		"top_bar": top_bar,
		"vitals": vitals,
		"minimap": minimap,
		"boss": boss,
		"banner": banner,
		"toast": toast,
		"stick": stick,
		"attack": attack,
		"dodge": dodge,
		"swap": swap,
		"skills": skills,
		"compact": compact,
	}


## Attack sits in the cluster's bottom-right, dodge to its left, swap above it.
static func _action_rects(cluster: Rect2, attack_r: float, minor_r: float) -> Dictionary:
	var ar := maxf(attack_r, 1.0)
	var mr := maxf(minor_r, 1.0)
	var attack := Rect2(
		Vector2(cluster.end.x - ar * 2.0, cluster.end.y - ar * 2.0),
		Vector2.ONE * ar * 2.0
	)
	var dodge := Rect2(
		Vector2(cluster.position.x, attack.position.y + ar - mr),
		Vector2.ONE * mr * 2.0
	)
	var swap := Rect2(
		Vector2(attack.position.x + ar - mr, cluster.position.y),
		Vector2.ONE * mr * 2.0
	)
	return {"attack": attack, "dodge": dodge, "swap": swap}


## Hardened: never hand a degenerate rect to a Control.
static func sanitize(rect: Rect2, view: Vector2) -> Rect2:
	var out := rect
	if not is_finite(out.position.x) or not is_finite(out.position.y):
		out.position = Vector2.ZERO
	if not is_finite(out.size.x) or not is_finite(out.size.y):
		out.size = Vector2.ONE
	out.size.x = clampf(out.size.x, 1.0, maxf(view.x, 1.0))
	out.size.y = clampf(out.size.y, 1.0, maxf(view.y, 1.0))
	out.position.x = clampf(out.position.x, 0.0, maxf(view.x - out.size.x, 0.0))
	out.position.y = clampf(out.position.y, 0.0, maxf(view.y - out.size.y, 0.0))
	return out


## True when the solver could not find room for an element on this screen.
static func is_collapsed(rect: Rect2) -> bool:
	return rect.size.x <= 0.0 or rect.size.y <= 0.0


## Apply a solved rect. A collapsed rect means "no room on this screen"; the
## caller decides whether to hide the element (see UiRoot._layout).
static func place(control: Control, rect: Rect2, view: Vector2) -> void:
	if control == null or is_collapsed(rect):
		return
	var safe := sanitize(rect, view)
	control.position = safe.position
	control.size = safe.size
