extends Node

const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
# 期望值口径：只列 TowerFloorStage3D.ROOFTOP_LAYOUT_REPLAY_GROUPS 的 6 组。
# 房屋围护（布局源的 shell_reference，60 件）**不在**重放列——Base100UpperShell3D
# 的 prefab 已自带 24 墙 + 36 封顶，重放会逐面 z-fighting（2026-09-21 修正）。
# 计数由布局 JSON 实测推出，非硬编码：
#   greenery 20 / hvac_wall 6 / ivy 16 / parapet_ivy 8 / pipe_loop 54 / pipe_risers 16 = 120
# 2026-09-21 三次修正：立管改「落地」（每处两段 ⇒ 4 立管变 8）+ 支架补低位（4 → 8），
# pipe_risers 8 → 16；全表 112 → 120。
const EXPECTED_INSTANCES := 120
const EXPECTED_GROUP_COUNTS := {
	"hvac_wall": 6,
	"greenery": 20,
	"ivy": 16,
	"parapet_ivy": 8,
	"pipe_loop": 54,
	"pipe_risers": 16,
}
# 落地件在运行时必须贴在承重面 y=0（业主 2026-09-21 报「花圃花盆悬空」的复核断言）。
# 重放把 JSON 的 h 直接写进 instance.position.y ⇒ 对「原点在底面」的组件，position.y 就是
# 实机高度。ivy 只有基座层落地，上层是叠高件。
# ⚠️ 立管**不在**这张表里：倒装件（rotation_x=180°）的原点在上端、position.y=4.945，
# 用 position.y 判落地会得出相反的结论 ⇒ 立管改用**实测可视包络**判（见 _check_riser_runs）。
const EXPECTED_GROUNDED := {
	"greenery": 20,
	"ivy": 11,
	"parapet_ivy": 8,
}
# 墙挂空调必须「风扇朝外」：风扇在 Blender 局部 +Z（组件顶面）；GLB 是 glTF Y-up，
# 导入 Godot 后映射为**局部 +Y**。挂到墙上要绕自身 X 轴倾倒 90°
# ⇒ basis.y 必须指向该面墙的外法线（业主 2026-09-21「需要 90 度旋转，让风扇朝外」）。
# 外法线不查表，由「建筑体 30×30 同心于平面 (0,5)」推出：取「从中心指向挂机」的主导轴。
const SHELL_CENTER_PLANAR := Vector2(0.0, 5.0)
const SHELL_HALF_M := 15.0
# 立管运行时的几何口径：每处两段，两段实例 h 都是 4.945（下段倒装 180°），
# 实测可视包络必须覆盖 0 ~ 2×4.945m，且下段最低点落在承重面 y=0。
const EXPECTED_RISER_RUNS := 4
const RISER_COMPONENT_H := 4.945
# 逐件碰撞策略（2026-09-21 四次修正；业主实机报「花盆和花圃没有阻挡」）：
# 绿化三件登记 blocking ⇒ 运行时（TowerFloorStage3D._apply_rooftop_collision_policy）
# 按**实测可视包络**生成一个 BoxShape3D 代理挡玩家；其余装饰维持 visual_only（0 启用碰撞）。
# 期望数不写死：blocking 件恰好是 greenery 组的全部 20 件（布局源 BLOCKING_SLUGS 三件之和）。
const BLOCKING_SLUGS := ["flowerbox", "plant_large", "plant_small"]
const ROOFTOP_BLOCKING_LAYER := 1   # 与家具/墙体同层；玩家 mask 含该层
const BLOCKING_BOX_TOL := 0.01      # 代理盒与实测包络的允许偏差（m）

func _ready() -> void:
	var failures: Array[String] = []
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	if tower == null:
		push_error("ROOFTOP_DECOR_PROBE_FAIL tower instantiate")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = 100990
	add_child(tower)
	await _settle()
	var stage := _find_rooftop_stage(tower)
	if stage == null:
		failures.append("rooftop stage missing")
	else:
		var root := stage.find_child("FormalRooftopFacilities", false, false) as Node3D
		if root == null:
			failures.append("FormalRooftopFacilities missing")
		else:
			var counts := {}
			var grounded := {}
			var lowest := {}
			var visual_nodes := 0
			var collision_nodes := 0
			var blocking_nodes := 0
			var blocking_slugs_seen := {}
			var riser_runs := {}
			for node in root.get_children():
				var group := str(node.get_meta("layout_group", ""))
				counts[group] = int(counts.get(group, 0)) + 1
				var node_y := float(node.position.y)
				if absf(node_y) <= 0.01:
					grounded[group] = int(grounded.get(group, 0)) + 1
				if node_y < float(lowest.get(group, 1e9)):
					lowest[group] = node_y
				visual_nodes += 1
				collision_nodes += _enabled_collision_shapes(node)
				var slug := str(node.get_meta("component_slug", ""))
				if slug in BLOCKING_SLUGS:
					blocking_nodes += 1
					blocking_slugs_seen[slug] = int(blocking_slugs_seen.get(slug, 0)) + 1
					_check_blocking_proxy(node, failures)
				elif _enabled_collision_shapes(node) != 0:
					# 反向断言：非 blocking 件必须一个启用碰撞都没有（visual_only 语义）。
					failures.append("visual_only instance carries collision: %s (%s)" % [node.name, slug])
				if not node.scale.is_equal_approx(Vector3.ONE):
					failures.append("non-unit scale: %s" % node.name)
				if slug == "hvac_small":
					_check_fan_outward(node, failures)
				elif slug == "pipe_riser":
					var key := Vector2(node.position.x, node.position.z)
					if not riser_runs.has(key):
						riser_runs[key] = []
					riser_runs[key].append(node)
			for group in EXPECTED_GROUP_COUNTS.keys():
				if int(counts.get(group, 0)) != int(EXPECTED_GROUP_COUNTS[group]):
					failures.append("group %s count=%d expected=%d" % [group, int(counts.get(group, 0)), int(EXPECTED_GROUP_COUNTS[group])])
			for group in EXPECTED_GROUNDED.keys():
				if int(grounded.get(group, 0)) != int(EXPECTED_GROUNDED[group]):
					failures.append("landing group %s grounded=%d expected=%d (floating landing decor)" % [group, int(grounded.get(group, 0)), int(EXPECTED_GROUNDED[group])])
				if float(lowest.get(group, 1e9)) < -0.01:
					failures.append("landing group %s sunk to y=%.3f" % [group, float(lowest[group])])
			_check_riser_runs(riser_runs, failures)
			var expected_blocking := int(EXPECTED_GROUP_COUNTS["greenery"])
			if visual_nodes != EXPECTED_INSTANCES:
				failures.append("visual instance count=%d expected=%d" % [visual_nodes, EXPECTED_INSTANCES])
			if blocking_nodes != expected_blocking:
				failures.append("blocking instances=%d expected=%d" % [blocking_nodes, expected_blocking])
			var seen_slugs: Array = blocking_slugs_seen.keys()
			seen_slugs.sort()
			var want_slugs: Array = BLOCKING_SLUGS.duplicate()
			want_slugs.sort()
			if seen_slugs != want_slugs:
				failures.append("blocking slugs=%s expected=%s" % [str(seen_slugs), str(want_slugs)])
			if collision_nodes != expected_blocking:
				failures.append("enabled collision shapes=%d expected=%d (= blocking instances)" % [collision_nodes, expected_blocking])
			print("ROOFTOP_DECOR_PROBE_SAMPLE groups=%s instances=%d grounded=%s risers=%d blocking=%d collisions=%d" % [str(counts), visual_nodes, str(grounded), riser_runs.size(), blocking_nodes, collision_nodes])
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_DECORATED_LAYOUT_RUNTIME_OK instances=%d groups=6 blocking=%d visual_collisions=0" % [EXPECTED_INSTANCES, int(EXPECTED_GROUP_COUNTS["greenery"])])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


## 「风扇朝外」：风扇在 Godot 局部 +Y（Blender 局部 +Z 经 glTF Y-up 转换而来），
## 倾倒 90° 后 basis.y 必须指向该墙外法线（局部 +Z 则是进风格栅，朝下）。
## 外法线由建筑体中心推得（不查表），并顺带核对挂机确实在建筑体外侧。
func _check_fan_outward(node: Node3D, failures: Array[String]) -> void:
	var to_unit := Vector2(node.position.x - SHELL_CENTER_PLANAR.x, node.position.z - SHELL_CENTER_PLANAR.y)
	var outward := Vector2.ZERO
	if absf(to_unit.x) > absf(to_unit.y):
		outward = Vector2(signf(to_unit.x), 0.0)
	else:
		outward = Vector2(0.0, signf(to_unit.y))
	if maxf(absf(to_unit.x), absf(to_unit.y)) < SHELL_HALF_M:
		failures.append("hvac_small %s at %s is not outside the shell" % [node.name, str(to_unit)])
		return
	var outward_3d := Vector3(outward.x, 0.0, outward.y)
	var fan := node.global_transform.basis.y.normalized()
	if fan.dot(outward_3d) < 0.999:
		failures.append("hvac_small %s fan axis=%s not outward=%s (needs 90 deg tip)"
			% [node.name, str(fan.snappedf(0.001)), str(outward_3d)])
	if not is_equal_approx(node.rotation.x, PI * 0.5):
		failures.append("hvac_small %s rotation.x=%.4f expected=%.4f" % [node.name, node.rotation.x, PI * 0.5])


## 立管落地：按**实测可视包络**判（倒装件原点在上端，position.y 判不了）。
## 每处两段的包络必须连成 0 ~ 2×4.945m，最低点落在承重面 y=0。
func _check_riser_runs(runs: Dictionary, failures: Array[String]) -> void:
	if runs.size() != EXPECTED_RISER_RUNS:
		failures.append("riser runs=%d expected=%d" % [runs.size(), EXPECTED_RISER_RUNS])
	for key in runs.keys():
		var nodes: Array = runs[key]
		if nodes.size() != 2:
			failures.append("riser run %s segments=%d expected=2" % [str(key), nodes.size()])
			continue
		var span := _visual_bounds(nodes[0])
		for node in nodes:
			span = span.merge(_visual_bounds(node))
		if absf(span.position.y) > 0.02:
			failures.append("riser run %s bottom y=%.4f expected=0.0 (floating pipe)" % [str(key), span.position.y])
		var top := span.position.y + span.size.y
		if absf(top - 2.0 * RISER_COMPONENT_H) > 0.05:
			failures.append("riser run %s top y=%.4f expected=%.4f" % [str(key), top, 2.0 * RISER_COMPONENT_H])


func _visual_bounds(root: Node) -> AABB:
	var points: Array = []
	_collect_visual_corners(root, points)
	if points.is_empty():
		return AABB()
	var result := AABB(points[0], Vector3.ZERO)
	for point in points:
		result = result.expand(point)
	return result


func _collect_visual_corners(root: Node, points: Array) -> void:
	if root is VisualInstance3D:
		var visual := root as VisualInstance3D
		var local := visual.get_aabb()
		var xform := visual.global_transform
		for i in 8:
			points.append(xform * local.get_endpoint(i))
	for child in root.get_children():
		_collect_visual_corners(child, points)

func _find_rooftop_stage(tower: Node) -> TowerFloorStage3D:
	for node in tower.get_tree().get_nodes_in_group("tower_floor_stage_3d"):
		var stage := node as TowerFloorStage3D
		if stage != null and int(stage.get_meta("floor_number", -1)) == 100:
			return stage
	return null

func _enabled_collision_shapes(root: Node) -> int:
	var count := 0
	if root is CollisionShape3D and not (root as CollisionShape3D).disabled:
		count += 1
	for child in root.get_children():
		count += _enabled_collision_shapes(child)
	return count


## blocking 件必须**恰好一个**挡玩家代理，且盒尺寸 = **实测可视包络**（不许写死）。
## 这里刻意复用运行时的同一个包络函数 TowerGeometry3D.resolve_visual_bounds ——
## 于是本条断言证明的是「运行时确实按实测包络建盒」，而不是「两边都记得同一个魔数」。
## 配合反向对照（把布局源 blocking 改回 visual_only ⇒ 本函数因找不到 BlockingCollision 而红）。
func _check_blocking_proxy(node: Node3D, failures: Array[String]) -> void:
	var shapes := _enabled_collision_shapes(node)
	if shapes != 1:
		failures.append("blocking instance %s has %d enabled collision shapes, expected 1" % [node.name, shapes])
	var body := node.get_node_or_null("BlockingCollision") as StaticBody3D
	if body == null:
		failures.append("blocking instance %s missing BlockingCollision body" % node.name)
		return
	if body.collision_layer != ROOFTOP_BLOCKING_LAYER:
		failures.append("blocking body %s layer=%d expected=%d" % [node.name, body.collision_layer, ROOFTOP_BLOCKING_LAYER])
	if body.collision_mask != 0:
		failures.append("blocking body %s mask=%d expected=0" % [node.name, body.collision_mask])
	if body.process_mode != Node.PROCESS_MODE_ALWAYS:
		failures.append("blocking body %s process_mode=%d expected ALWAYS" % [node.name, body.process_mode])
	var shape_node := body.get_node_or_null("BlockingBox") as CollisionShape3D
	if shape_node == null:
		failures.append("blocking instance %s missing BlockingBox shape" % node.name)
		return
	var box := shape_node.shape as BoxShape3D
	if box == null:
		failures.append("blocking instance %s proxy is not a BoxShape3D" % node.name)
		return
	if box.size.x <= 0.001 or box.size.y <= 0.001 or box.size.z <= 0.001:
		failures.append("blocking instance %s proxy is degenerate: %s" % [node.name, str(box.size)])
	var expect := TowerGeometry3D.resolve_visual_bounds(node)
	if expect.size.x <= 0.001 or expect.size.y <= 0.001 or expect.size.z <= 0.001:
		# 实测包络为空 = 网格压根没加载出来（真正的故障），不能当作「无需比对」放过。
		failures.append("blocking instance %s has empty visual bounds at probe time" % node.name)
		return
	if not _vec3_close(box.size, expect.size, BLOCKING_BOX_TOL):
		failures.append("blocking instance %s box size=%s expected measured %s" % [node.name, str(box.size), str(expect.size)])
	if not _vec3_close(shape_node.position, expect.get_center(), BLOCKING_BOX_TOL):
		failures.append("blocking instance %s box center=%s expected measured %s" % [node.name, str(shape_node.position), str(expect.get_center())])


func _vec3_close(a: Vector3, b: Vector3, tol: float) -> bool:
	return absf(a.x - b.x) <= tol and absf(a.y - b.y) <= tol and absf(a.z - b.z) <= tol

func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
