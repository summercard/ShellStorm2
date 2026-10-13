extends Node
## 探针：Boss房02「可行走地面」实测对照 —— 碰撞面顶高 vs 可见网格顶高（都在房间局部 y）。
##
## 背景：业主反馈「楼梯从下往上走被台阶高度卡住」「两边走道到台子也卡人」。
## 要换成一体地面碰撞，先得有两组实测数：
##   ① 现在**碰撞**把脚垫在多高 —— 向下射线，起止点卡在目标带内（**不能从天上射**：
##      会先命中壳体顶盖，实测撞出 coll=36.4 的假数）；
##   ② 现在**看得见**的甲板 / 格栅 / 踏步面在多高 —— 对走面组件（白名单 slug）逐三角
##      竖直求交（AABB 法对斜坡无效，斜坡段 AABB 顶 = 整段最高点）。
##
## 输出：`SURF <段> x=.. z=.. coll=.. vis=.. dz=(coll-vis)  hit=<碰撞体名> visfrom=<slug>`
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_walksurf'
##   "<godot-console>" --headless --path "<project>" \
##     --scene res://scripts/probe_boss_room02_walk_surface.tscn

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel99_3D.tscn")
## 只在「走面」组件里找可见面，避免把塔体 / 缆束 / 管道算进来。
const WALK_SLUGS: Array[String] = [
	"deck_armor_5m", "deck_emblem_5m", "bridge_deck_5m", "bridge_threshold",
	"stair_flight_5m", "stair_landing_5m",
]
## 楼梯踏步鼻线（实测吻合）：平台面 0 → 高台面 11.965。
const STAIR_BASE_Z := -10.0
const STAIR_TOP_Z := 40.0
const STAIR_TOP_Y := 11.965

var _root: Window
var _room: DungeonRoom3D
var _buckets: Dictionary = {}
var _surface_slug := ""


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	var tower: TowerDescent3D = EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20260919
	_root.add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_room = tower._room_by_id["boss"]
	_room.ensure_shell_built()
	_room.ensure_detail_built()
	await get_tree().process_frame
	await get_tree().physics_frame

	print("TRIANGLES ", _build_buckets(_room))
	var space := _root.get_world_3d().direct_space_state

	# ── A. 平台 → 东桥 连接剖面（x 0.5 m 一档，横跨三个 z 档）─────────────
	for z in [-24.0, -22.5, -21.0]:
		print("--- junction_east z=%.1f ---" % z)
		var x := 10.0
		while x <= 20.001:
			_row(space, "junction_east", x, z, 0.0)
			x += 0.5
	# ── B. 桥宽剖面（沿 z 扫，看桥面与边缘护栏的关系）─────────────────────
	for x in [-20.0, -22.5]:
		print("--- bridge_width x=%.1f ---" % x)
		var z := -25.0
		while z <= -19.999:
			_row(space, "bridge_width", x, z, 0.0)
			z += 0.5
	# ── C. 楼梯全程剖面（0.5 m 一档，覆盖 10 段接缝）────────────────────
	print("--- stair ---")
	var zs := STAIR_BASE_Z - 2.0
	while zs <= STAIR_TOP_Z + 2.001:
		_row(space, "stair", 0.0, zs, stair_hint(zs))
		zs += 0.5
	# ── D. 高台 ─────────────────────────────────────────────────────────
	print("--- landing ---")
	var zl := 38.0
	while zl <= 50.001:
		_row(space, "landing", 0.0, zl, 12.0)
		zl += 1.0
	print("WALKSURF_PROBE_DONE")
	get_tree().quit(0)


func stair_hint(z: float) -> float:
	var t := clampf((z - STAIR_BASE_Z) / (STAIR_TOP_Z - STAIR_BASE_Z), 0.0, 1.0)
	return t * STAIR_TOP_Y


func _row(space: PhysicsDirectSpaceState3D, seg: String, x: float, z: float, hint: float) -> void:
	var from := _room.to_global(Vector3(x, hint + 3.0, z))
	var to := _room.to_global(Vector3(x, hint - 3.0, z))
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF))
	var coll := NAN
	var who := ""
	if not hit.is_empty():
		coll = (hit.position as Vector3).y - _room.global_position.y
		who = str((hit.collider as Node).name)
	var vis := _surface_y(_room.to_global(Vector3(x, 0.0, z)))
	if not is_nan(vis):
		vis -= _room.global_position.y
	print("SURF %-14s x=%7.2f z=%7.2f coll=%s vis=%s dz=%s  hit=%-30s visfrom=%s" % [
		seg, x, z, _f(coll), _f(vis),
		_f(coll - vis) if not (is_nan(coll) or is_nan(vis)) else "n/a",
		who, _surface_slug,
	])


func _build_buckets(room: DungeonRoom3D) -> int:
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art_root == null:
		push_error("找不到 AuthoredLayoutArtRoot")
		return 0
	var total := 0
	var stack: Array = [art_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var slug := ""
		var probe: Node = node
		while probe != null:
			if probe.has_meta("component_slug"):
				slug = str(probe.get_meta("component_slug"))
				break
			probe = probe.get_parent()
		if node is MeshInstance3D and slug in WALK_SLUGS:
			var tris := _mesh_triangles(node as MeshInstance3D, slug)
			if not tris.is_empty():
				if not _buckets.has(slug):
					_buckets[slug] = []
				(_buckets[slug] as Array).append_array(tris)
				total += tris.size()
		for child in node.get_children():
			stack.append(child)
	return total


func _mesh_triangles(mesh_instance: MeshInstance3D, slug: String) -> Array:
	var mesh := mesh_instance.mesh
	var out: Array = []
	if mesh == null:
		return out
	var xform: Transform3D = mesh_instance.global_transform
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(0, verts.size() - 2, 3):
				out.append([xform * verts[i], xform * verts[i + 1], xform * verts[i + 2], slug])
		else:
			for i in range(0, indices.size() - 2, 3):
				out.append([
					xform * verts[indices[i]], xform * verts[indices[i + 1]],
					xform * verts[indices[i + 2]], slug,
				])
	return out


## 竖直向上求「最高可见面」（世界 y）；来源 slug 写进 _surface_slug。
func _surface_y(world: Vector3) -> float:
	var best := NAN
	_surface_slug = ""
	for slug in _buckets.keys():
		for tri in _buckets[slug]:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(den) < 1e-9:
				continue
			var l0 := ((b.z - c.z) * (world.x - c.x) + (c.x - b.x) * (world.z - c.z)) / den
			var l1 := ((c.z - a.z) * (world.x - c.x) + (a.x - c.x) * (world.z - c.z)) / den
			var l2 := 1.0 - l0 - l1
			if l0 < -1e-6 or l1 < -1e-6 or l2 < -1e-6:
				continue
			var y := l0 * a.y + l1 * b.y + l2 * c.y
			if is_nan(best) or y > best:
				best = y
				_surface_slug = str(tri[3])
	return best


func _f(value: float) -> String:
	if is_nan(value):
		return "  none"
	return "%7.4f" % value
