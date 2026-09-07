extends RefCounted

## Headless unit tests for RngService (seeded streams), WeightedTable
## (deterministic picks) and ObjectPool (generic pooling). All pure.

static func suite() -> Array:
	var results: Array = []

	# --- RngService: same seed + salt => same sequence ---
	var a := RngService.new(1234)
	var b := RngService.new(1234)
	var seq_a: Array = [a.randf_range(1, 0.0, 1.0), a.randi_range(1, 0, 100), a.pick(1, [10, 20, 30])]
	var seq_b: Array = [b.randf_range(1, 0.0, 1.0), b.randi_range(1, 0, 100), b.pick(1, [10, 20, 30])]
	results.append({
		"name": "RngService same seed reproduces the stream",
		"passed": seq_a == seq_b,
		"why": "",
	})

	# --- Streams are independent ---
	var c := RngService.new(777)
	c.randf_range(RngService.STREAM_WAVES, 0.0, 1.0)
	c.randf_range(RngService.STREAM_WAVES, 0.0, 1.0)
	var d := RngService.new(777)
	var wave_first_c := RngService.new(777).randf_range(RngService.STREAM_WAVES, 0.0, 1.0)
	results.append({
		"name": "RngService streams start identically per salt",
		"passed": is_equal_approx(wave_first_c, d.randf_range(RngService.STREAM_WAVES, 0.0, 1.0)),
		"why": "",
	})

	# --- reseed reproduces ---
	var e := RngService.new(5)
	e.randf_range(9, 0.0, 1.0)
	e.reseed(5)
	var f := RngService.new(5)
	results.append({
		"name": "RngService reseed restarts the sequence",
		"passed": is_equal_approx(e.randf_range(9, 0.0, 1.0), f.randf_range(9, 0.0, 1.0)),
		"why": "",
	})

	# --- chance edges ---
	var g := RngService.new(1)
	results.append({
		"name": "RngService chance(0)=false chance(1)=true, empty pick=null",
		"passed": not g.chance(3, 0.0) and g.chance(3, 1.0) and g.pick(3, []) == null,
		"why": "",
	})

	# --- shuffle is deterministic and non-mutating ---
	var src := [1, 2, 3, 4, 5, 6, 7, 8]
	var s1 := RngService.new(42).shuffled(7, src)
	var s2 := RngService.new(42).shuffled(7, src)
	results.append({
		"name": "RngService shuffled deterministic, input untouched",
		"passed": s1 == s2 and src == [1, 2, 3, 4, 5, 6, 7, 8] and s1.size() == 8,
		"why": "",
	})

	# --- point_in_disc stays inside the disc ---
	var h := RngService.new(9)
	var inside := true
	for i in range(50):
		var p := h.point_in_disc(4, 5.0)
		if Vector2(p.x, p.z).length() > 5.001 or absf(p.y) > 0.001:
			inside = false
	results.append({"name": "RngService point_in_disc bounded", "passed": inside, "why": ""})

	# --- WeightedTable: proportional picks ---
	var table := WeightedTable.new([["a", 1.0], ["b", 3.0]])
	results.append({
		"name": "WeightedTable maps samples proportionally",
		"passed": table.roll(0.0) == "a" and table.roll(0.24) == "a" and table.roll(0.25) == "b"
			and table.roll(0.99) == "b" and is_equal_approx(table.total_weight(), 4.0),
		"why": "",
	})

	# --- WeightedTable: empty + unique ---
	var empty := WeightedTable.new()
	var uniq := WeightedTable.new([[1, 1.0], [2, 1.0], [3, 1.0]])
	var picked := uniq.roll_unique([0.0, 0.5, 0.9], 3)
	results.append({
		"name": "WeightedTable empty rolls fallback, unique has no dupes",
		"passed": empty.roll(0.5, "fb") == "fb" and picked.size() == 3
			and picked[0] != picked[1] and picked[1] != picked[2] and picked[0] != picked[2],
		"why": str(picked),
	})

	# --- ObjectPool: acquire/release accounting ---
	var created := [0]
	var pool := ObjectPool.new(
		func() -> Dictionary: created[0] += 1; return {"n": created[0]},
		func(_o: Dictionary) -> void: pass,
		2, 4, "test")
	var o1 = pool.acquire()
	var o2 = pool.acquire()
	var o3 = pool.acquire()  # fresh (prewarmed 2 exhausted)
	pool.release(o1)
	pool.release(o1)  # duplicate release ignored
	results.append({
		"name": "ObjectPool prewarm/acquire/release counts",
		"passed": created[0] == 3 and pool.live_count() == 2 and pool.idle_count() == 1,
		"why": "created=%d live=%d idle=%d" % [created[0], pool.live_count(), pool.idle_count()],
	})
	pool.release(o2)
	pool.release(o3)

	# --- ObjectPool: invalid create fn => null, safe release ---
	var broken := ObjectPool.new()
	results.append({
		"name": "ObjectPool without create fn returns null safely",
		"passed": broken.acquire() == null,
		"why": "",
	})

	return results
