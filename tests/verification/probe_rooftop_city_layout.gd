extends Node
## 探针：远景城市（天台脚下那圈楼体剪影）的摆位契约。
## 只读：加载完整塔楼，读 `TowerAtmosphere3D.get_city_layout()` 的确定性摆位表，
## 逐栋核算「到塔楼外墙的最近距离 / 环间距 / 同环间距 / 顶面分层」四组约束。
## ⚠️ 不读 MultiMesh：headless 下 `get_instance_transform()` 恒为零向量。

const EXPECTED_NEAREST_GAP_M := 15.0
const EXPECTED_RING_SPACING_M := 20.0
const EXPECTED_SLOT_SPACING_M := 20.0
const EXPECTED_RING_COUNT := 3
const EXPECTED_TOP_BASE_Y := -20.0
const EXPECTED_TOP_RING_STEP_M := 18.0
const EXPECTED_TOP_STAGGER_M := 12.0
const TOLERANCE := 0.01

var _failures: Array[String] = []


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("CITY_LAYOUT_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for _i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	var atmosphere := tower.get_node_or_null("TowerAtmosphere3D")
	if atmosphere == null:
		print("CITY_LAYOUT_FAIL: 塔楼里没有 TowerAtmosphere3D")
		get_tree().quit(1)
		return
	var placements: Array = atmosphere.call("get_city_layout")
	_expect(not placements.is_empty(), "远景城市摆位为空（_ready 未跑到 _build_city_silhouette）")
	if placements.is_empty():
		_report()
		return
	_verify_distances(tower, placements)
	_verify_top_layering(placements)
	_verify_no_overlap(placements)
	if placements.size() < 60:
		_failures.append("楼体数量只有 %d，环带没铺满" % placements.size())
	_report()


## 逐栋把「内表面中心」反算回世界坐标，再量它到塔楼外墙矩形的距离。
## 这是从摆位本身重新量出来的，不复用生成时的 gap 常量 —— 常量写错也会被抓到。
func _verify_distances(tower: Node, placements: Array) -> void:
	var rect := _tower_world_rect(tower)
	var by_ring: Dictionary = {}
	var nearest := INF
	for entry in placements:
		var placement := entry as Dictionary
		var transform: Transform3D = placement["transform"]
		var size: Vector3 = placement["size"]
		var ring := int(placement["ring"])
		var outward: Vector3 = transform.basis.z.normalized()
		# 楼体进深沿 +Z ⇒ 内表面中心 = 中心 - 外法线 * 进深/2
		var inner := transform.origin - outward * (size.z * 0.5)
		var planar := Vector2(inner.x, inner.z)
		var clamped := Vector2(
			clampf(planar.x, rect.position.x, rect.end.x),
			clampf(planar.y, rect.position.y, rect.end.y)
		)
		var distance := planar.distance_to(clamped)
		nearest = minf(nearest, distance)
		if not by_ring.has(ring):
			by_ring[ring] = []
		(by_ring[ring] as Array).append(distance)
	_expect(
		absf(nearest - EXPECTED_NEAREST_GAP_M) <= TOLERANCE,
		"最近一圈离外墙 %.3f m，期望 %.1f m" % [nearest, EXPECTED_NEAREST_GAP_M]
	)
	print("CITY_LAYOUT nearest_gap=%.3f m" % nearest)
	var ring_keys: Array = by_ring.keys()
	ring_keys.sort()
	_expect(
		ring_keys.size() == EXPECTED_RING_COUNT,
		"环数 %d，期望 %d" % [ring_keys.size(), EXPECTED_RING_COUNT]
	)
	var ring_index := 0
	for key in ring_keys:
		var distances: Array = by_ring[key]
		var expected_gap := EXPECTED_NEAREST_GAP_M + float(key) * EXPECTED_RING_SPACING_M
		var closest := INF
		var farthest := -INF
		for value in distances:
			closest = minf(closest, float(value))
			farthest = maxf(farthest, float(value))
		# 环线上必须真有「贴着环线」的楼 —— 最小值恰等于该环 gap，证明环带贴住了外墙。
		# （角部那几栋到墙角本来就比 gap 远，所以只看最小值，不看全体。）
		_expect(
			absf(closest - expected_gap) <= TOLERANCE,
			"第 %d 环最近距 %.3f m，期望恰好 %.1f m（环带没贴住外墙）"
			% [ring_index, closest, expected_gap]
		)
		# 近侧不许捅进 gap 以内。
		_expect(
			closest >= expected_gap - TOLERANCE,
			"第 %d 环有楼体离外墙 %.3f m，小于该环 gap %.1f m" % [ring_index, closest, expected_gap]
		)
		print(
			"CITY_LAYOUT ring=%d count=%d gap=%.1f m（实测最近 %.3f / 最远 %.3f，最远为角部让位）"
			% [ring_index, distances.size(), expected_gap, closest, farthest]
		)
		ring_index += 1


## 顶面：一律 ≥ 20m 低于楼顶；同环内上下交错；越远的环整体越低。
func _verify_top_layering(placements: Array) -> void:
	var by_ring: Dictionary = {}
	for entry in placements:
		var placement := entry as Dictionary
		var ring := int(placement["ring"])
		if not by_ring.has(ring):
			by_ring[ring] = []
		(by_ring[ring] as Array).append(float(placement["top_y"]))
	var ring_keys: Array = by_ring.keys()
	ring_keys.sort()
	var highest := -INF
	var previous_high := INF
	for key in ring_keys:
		var tops: Array = by_ring[key]
		var ring_high := -INF
		var ring_low := INF
		for value in tops:
			var top := float(value)
			ring_high = maxf(ring_high, top)
			ring_low = minf(ring_low, top)
			highest = maxf(highest, top)
		var spread := ring_high - ring_low
		_expect(
			absf(spread - EXPECTED_TOP_STAGGER_M * 2.0) <= TOLERANCE,
			"第 %d 环顶面上下交错幅度 %.3f m，期望 %.1f m" % [key, spread, EXPECTED_TOP_STAGGER_M * 2.0]
		)
		_expect(
			ring_high <= previous_high + TOLERANCE,
			"第 %d 环整体比内环还高：%.3f > %.3f（近高远低被破坏）" % [key, ring_high, previous_high]
		)
		previous_high = ring_high
		print(
			"CITY_LAYOUT ring=%d top_y=[%.1f, %.1f] 交错幅度=%.1f m"
			% [key, ring_low, ring_high, spread]
		)
	# 最高的顶面必须仍在楼顶（Y=0）下方 EXPECTED_TOP_BASE_Y 处，绝不穿屋面
	_expect(
		absf(highest - EXPECTED_TOP_BASE_Y) <= TOLERANCE,
		"最高顶面 Y=%.3f，期望 %.1f（否则会与可玩屋面穿插）" % [highest, EXPECTED_TOP_BASE_Y]
	)
	print("CITY_LAYOUT 最高顶面 Y=%.3f（楼顶 = 0.0，低 %.1f m）" % [highest, -highest])


## 同一环内相邻楼不叠：切向宽 ≤ 槽距；跨环不叠：内环外表面 < 外环内表面。
func _verify_no_overlap(placements: Array) -> void:
	var widest := 0.0
	var deepest := 0.0
	for entry in placements:
		var placement := entry as Dictionary
		var size: Vector3 = placement["size"]
		widest = maxf(widest, size.x)
		deepest = maxf(deepest, size.z)
	_expect(widest < EXPECTED_SLOT_SPACING_M, "最宽楼体 %.1f m 超过槽距 %.1f m（同环会叠）"
		% [widest, EXPECTED_SLOT_SPACING_M])
	var slack := EXPECTED_RING_SPACING_M - deepest
	_expect(slack > 0.0, "最进深楼体 %.1f m 吃满环间距 %.1f m（跨环会叠）"
		% [deepest, EXPECTED_RING_SPACING_M])
	print("CITY_LAYOUT 最宽=%.1f m 最进深=%.1f m（槽距 %.1f / 环距 %.1f）"
		% [widest, deepest, EXPECTED_SLOT_SPACING_M, EXPECTED_RING_SPACING_M])


func _tower_world_rect(tower: Node) -> Rect2:
	# 与 TowerFloorStage3D 同源：塔楼三层统一壳体的平面矩形（x/z 轴，与 Rect2 同序）。
	# `_outer_world_rect()` 是私有方法，用 call() 拿运行时真值；拿不到再回落常量。
	var stages := tower.get("_floor_stages") as Dictionary
	if stages != null:
		for key in stages.keys():
			var candidate := stages[key] as Node3D
			if candidate == null or not candidate.has_method("_outer_world_rect"):
				continue
			var outer: Rect2 = candidate.call("_outer_world_rect")
			if outer.size.length_squared() > 0.0:
				return outer
	return TowerFloorStage3D.TOWER_SHELL_WORLD_RECT


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("\nPROBE_CITY_LAYOUT_OK 远景城市贴轮廓环带（最近 15m / 环距 20m / 同环 20m / 上下交错）")
		get_tree().quit(0)
		return
	print("\nPROBE_CITY_LAYOUT_FAIL 共 %d 条：" % _failures.size())
	for message in _failures:
		print("  ✗ %s" % message)
	get_tree().quit(1)
