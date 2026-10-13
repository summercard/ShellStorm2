extends Node
## 只读探查：远征关卡02 实机装配到底装了什么。
##
## 用途：主人反馈「开阳台→room_01 的门后刷出一堆墙、排列糟、还有很多空阻挡」。
##       本探针把 26 个房间的记录、静态布局接管状态、Mesh 归类、layer=1 碰撞体
##       全部清点一遍，并按「碰撞盒内有没有可见 Mesh」判定**空阻挡**。
##
## 跑法：
##   "<godot_console>" --headless --path "<project>" --scene res://tests/verification/probe_expedition02_assembly.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
const TARGETS: Array[String] = ["start", "room_01", "room_02"]


func _ready() -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		printerr("[exp02] 关卡场景加载失败")
		get_tree().quit(1)
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout

	print("=== 关卡事实 ===")
	print("  is_expedition=%s  level_id=%s  run_id=%s" % [
		str(tower.is_expedition()), tower.get_expedition_level_id(), tower.get_expedition_run_id()])

	var records: Array = tower.get_generation_snapshot().get("records", [])
	print("  记录数=%d" % records.size())

	print()
	print("=== 全部房间记录（含静态布局接管状态） ===")
	for rv in records:
		var rec: Dictionary = rv
		var p := rec.get("position", Vector3.ZERO) as Vector3
		var d := rec.get("custom_dimensions", Vector2.ZERO) as Vector2
		print("  %-14s type=%-12s pos=(%7.2f,%6.2f,%7.2f) dims=(%5.1f,%5.1f) rot=%6.1f" % [
			str(rec.get("id", "")), str(rec.get("type", "")),
			p.x, p.y, p.z, d.x, d.y, float(rec.get("rotation_deg", 0.0))])
		print("      static_layout_scene_path = %s" % str(rec.get("static_layout_scene_path", "<无字段>")))
		print("      authored_layout_shell     = %s" % str(rec.get("authored_layout_shell", "<无字段>")))
		print("      tower_module_shell        = %s" % str(rec.get("tower_module_shell", "<无字段>")))
		print("      spawn_boxes_only          = %s" % str(rec.get("spawn_boxes_only", "<无字段>")))

	var room_by_id: Dictionary = tower.get("_room_by_id")
	print()
	print("  运行时房间字典键(%d)：%s" % [room_by_id.size(), str(room_by_id.keys())])

	for target in TARGETS:
		await _inspect_room(tower, room_by_id, target)

	await _inspect_corridors(tower)

	print()
	print("EXP02_ASSEMBLY_DONE")
	get_tree().quit(0)


func _inspect_corridors(tower: TowerDescent3D) -> void:
	print()
	print("############ 房间之间的连接件（_corridor_by_edge）############")
	var corridors: Dictionary = tower.get("_corridor_by_edge")
	print("  连接件总数=%d" % corridors.size())
	var edges: Array = corridors.keys()
	edges.sort()
	for edge_value in edges:
		var connector := corridors.get(edge_value) as Node3D
		if connector == null:
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var to_id := str(connector.get_meta("to_room_id", ""))
		var start_pos := connector.get_meta("start_door_position", Vector3.ZERO) as Vector3
		var end_pos := connector.get_meta("end_door_position", Vector3.ZERO) as Vector3
		var length := start_pos.distance_to(end_pos)
		var mesh_total := 0
		var prefix: Dictionary = {}
		for mv in connector.find_children("*", "MeshInstance3D", true, false):
			var mi := mv as MeshInstance3D
			if mi == null:
				continue
			mesh_total += 1
			var n := String(mi.name)
			var base := n
			while base.length() > 0 and base[base.length() - 1] >= "0" and base[base.length() - 1] <= "9":
				base = base.substr(0, base.length() - 1)
			while base.ends_with("_"):
				base = base.substr(0, base.length() - 1)
			prefix[base] = int(prefix.get(base, 0)) + 1
		var colliders := 0
		var shapes := 0
		var empty_shapes := 0
		# ⚠️ MultiMeshInstance3D **不是** MeshInstance3D 的子类，find_children("*","MeshInstance3D")
		#    数不到它。塔楼地板/实墙正是走 MultiMesh 路径 ⇒ 漏数会得到「Mesh=0」的假结论。
		var mm_nodes := 0
		var mm_instances := 0
		var mesh_boxes: Array[AABB] = []
		for mv2 in connector.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := mv2 as MultiMeshInstance3D
			if mmi == null or mmi.multimesh == null:
				continue
			mm_nodes += 1
			mm_instances += mmi.multimesh.instance_count
			mesh_boxes.append(_world_aabb_mm(mmi))
		for cv in connector.find_children("*", "CollisionObject3D", true, false):
			var co := cv as CollisionObject3D
			if co == null or co.collision_layer != 1:
				continue
			colliders += 1
			for sv in co.find_children("*", "CollisionShape3D", true, false):
				var cs := sv as CollisionShape3D
				if cs == null or not (cs.shape is BoxShape3D):
					continue
				shapes += 1
				var box := _shape_world_aabb(cs, cs.shape as BoxShape3D)
				var inner := AABB(box.position + box.size * 0.075, box.size * 0.85)
				var hit := false
				for mb in mesh_boxes:
					if inner.intersects(mb):
						hit = true
						break
				if not hit:
					empty_shapes += 1
		print("  --- %s ---" % edge_value)
		print("      门起=%s 门止=%s  门间距离=%.2fm" % [str(start_pos), str(end_pos), length])
		print("      module_count=%s wall_module_count=%s floor_module_count=%s" % [
			str(connector.get_meta("module_count", "-")),
			str(connector.get_meta("wall_module_count", "-")),
			str(connector.get_meta("floor_module_count", "-"))])
		print("      MeshInstance3D=%d  MultiMeshInstance3D=%d(mm实例合计=%d)" % [
			mesh_total, mm_nodes, mm_instances])
		print("      layer1实体=%d shape=%d 空阻挡(不计MultiMesh)=%d" % [
			colliders, shapes, empty_shapes])
		if not prefix.is_empty():
			print("      Mesh 归类：%s" % str(prefix))
		print("      children=%d  visible=%s" % [connector.get_child_count(), str(connector.visible)])
		for child in connector.get_children():
			var cn := child as Node3D
			var extra := ""
			if cn != null:
				extra = " gpos=(%.1f,%.1f,%.1f)" % [cn.global_position.x, cn.global_position.y, cn.global_position.z]
				if child is MultiMeshInstance3D:
					var mmi := child as MultiMeshInstance3D
					extra += " instances=%d" % (mmi.multimesh.instance_count if mmi.multimesh != null else -1)
			print("        子：%-34s %s%s" % [String(child.name), child.get_class(), extra])



func _inspect_room(tower: TowerDescent3D, room_by_id: Dictionary, target: String) -> void:
	var room := room_by_id.get(target) as DungeonRoom3D
	if room == null:
		print()
		print("### %s —— 不在房间字典里" % target)
		return
	# 用后门把玩家真放进房间（只改标记会被 hibernate 释放）
	tower.force_enter_room_for_test(target)
	var p := tower.get("player") as Node3D
	if p != null:
		p.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	var cb := tower as Node
	if cb.has_method("_on_room_entered"):
		cb.call("_on_room_entered", room)
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	room.ensure_shell_built()
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame

	print()
	print("### %s  room_id=%s type=%s" % [target, room.room_id, room.room_type])
	print("  global_position=%s dims=%s rot_y=%.1f°" % [
		str(room.global_position), str(room.get_dimensions()), rad_to_deg(room.rotation.y)])
	print("  meta static_layout_scene_path = %s" % str(room.get_meta("static_layout_scene_path", "<无>")))
	print("  meta static_layout_scene_loaded = %s" % str(room.get_meta("static_layout_scene_loaded", "<无>")))
	print("  meta authored_layout_shell = %s" % str(room.get_meta("authored_layout_shell", "<无>")))
	print("  doors=%s" % str(room.doors))

	# ---- 1) 直接子节点（看有没有同时挂了两套美术根） ----
	print("  --- 直接子节点 ---")
	for child in room.get_children():
		var n3 := child as Node3D
		var vis := ""
		if n3 != null:
			var mi_count := 0
			for mv in n3.find_children("*", "MeshInstance3D", true, false):
				mi_count += 1
			vis = " meshes=%d" % mi_count
		print("      %-34s %s%s" % [String(child.name), child.get_class(), vis])

	# ---- 2) Mesh 按名字前缀归类（去尾号） ----
	prefix_count = {}
	_mesh_prefixes(room)
	print("  --- Mesh 按前缀归类（共 %d 个 MeshInstance3D） ---" % _mesh_total)
	var keys: Array = prefix_count.keys()
	keys.sort_custom(func(a, b): return int(prefix_count[b]) > int(prefix_count[a]))
	for k in keys:
		print("      %5d  %s" % [int(prefix_count[k]), str(k)])

	# ---- 3) layer=1 碰撞体 + 空阻挡判定 ----
	print("  --- layer=1 碰撞体与空阻挡判定 ---")
	var mesh_boxes: Array[AABB] = []
	for mv in room.find_children("*", "MeshInstance3D", true, false):
		var mi := mv as MeshInstance3D
		if mi != null and mi.mesh != null and mi.is_visible_in_tree():
			mesh_boxes.append(_world_aabb(mi))
	var bodies := 0
	var empty_boxes := 0
	var by_group: Dictionary = {}
	for cv in room.find_children("*", "CollisionObject3D", true, false):
		var co := cv as CollisionObject3D
		if co == null or co.collision_layer != 1:
			continue
		bodies += 1
		var aid := ""
		var cur: Node = co
		var owner_name := String(co.name)
		while cur != null:
			if not str(cur.get_meta("asset_id", "")).is_empty():
				aid = str(cur.get_meta("asset_id", ""))
				break
			cur = cur.get_parent()
		var total := 0
		var empty := 0
		for sv in co.find_children("*", "CollisionShape3D", true, false):
			var cs := sv as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			total += 1
			var bx := cs.shape as BoxShape3D
			var box := _shape_world_aabb(cs, bx)
			# 缩小 15% 再判，避免"擦边贴到隔壁件"被算成非空
			var inner := AABB(box.position + box.size * 0.075, box.size * 0.85)
			var hit := false
			for mb in mesh_boxes:
				if inner.intersects(mb):
					hit = true
					break
			if not hit:
				empty += 1
				empty_boxes += 1
		var gkey := owner_name if aid.is_empty() else "%s(%s)" % [owner_name, aid]
		if not by_group.has(gkey):
			by_group[gkey] = [0, 0, 0]
		var g: Array = by_group[gkey]
		g[0] = int(g[0]) + 1
		g[1] = int(g[1]) + total
		g[2] = int(g[2]) + empty
	print("      layer=1 实体数=%d  CollisionShape3D 合计=%d  其中空阻挡=%d" % [
		bodies, _count_shapes(room), empty_boxes])
	var gk: Array = by_group.keys()
	for k in gk:
		var g2: Array = by_group[k]
		print("        %-58s 实体=%d shape=%d 空阻挡=%d" % [str(k), int(g2[0]), int(g2[1]), int(g2[2])])

	# ---- 4) 有没有程序化塔楼模块（远征不该出现） ----
	print("  --- 疑似程序化/塔楼件（远征里不该出现） ---")
	var suspicious := 0
	for mv2 in room.find_children("*", "MeshInstance3D", true, false):
		var mi2 := mv2 as MeshInstance3D
		if mi2 == null:
			continue
		var low := String(mi2.name).to_lower()
		if (
			"env_tower" in low or "boxmesh" in low or "prp_tower" in low
			or "arrow" in low or "corner_l" in low
		):
			print("      %-46s %s" % [String(mi2.name), str(_world_aabb(mi2).size)])
			suspicious += 1
	if suspicious == 0:
		print("      <无>")


var prefix_count: Dictionary = {}
var _mesh_total := 0


func _mesh_prefixes(root: Node) -> void:
	for mv in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mv as MeshInstance3D
		if mi == null:
			continue
		_mesh_total += 1
		var n := String(mi.name)
		# 去掉尾部数字与 _001 之类的序号
		var base := n
		while base.length() > 0 and base[base.length() - 1] >= "0" and base[base.length() - 1] <= "9":
			base = base.substr(0, base.length() - 1)
		while base.ends_with("_"):
			base = base.substr(0, base.length() - 1)
		prefix_count[base] = int(prefix_count.get(base, 0)) + 1


func _count_shapes(root: Node) -> int:
	var n := 0
	for sv in root.find_children("*", "CollisionShape3D", true, false):
		if sv is CollisionShape3D:
			n += 1
	return n


func _shape_world_aabb(cs: CollisionShape3D, bx: BoxShape3D) -> AABB:
	var xf := cs.global_transform
	var p := bx.size * -0.5
	var s := bx.size
	var mn := xf * p
	var mx := mn
	for i in range(8):
		var c := p + Vector3(
			s.x if (i & 1) else 0.0,
			s.y if (i & 2) else 0.0,
			s.z if (i & 4) else 0.0)
		var wp := xf * c
		mn = Vector3(minf(mn.x, wp.x), minf(mn.y, wp.y), minf(mn.z, wp.z))
		mx = Vector3(maxf(mx.x, wp.x), maxf(mx.y, wp.y), maxf(mx.z, wp.z))
	return AABB(mn, mx - mn)


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var a := mi.get_aabb()
	var xf := mi.global_transform
	var p := a.position
	var s := a.size
	var mn := xf * p
	var mx := mn
	for i in range(8):
		var c := p + Vector3(
			s.x if (i & 1) else 0.0,
			s.y if (i & 2) else 0.0,
			s.z if (i & 4) else 0.0)
		var wp := xf * c
		mn = Vector3(minf(mn.x, wp.x), minf(mn.y, wp.y), minf(mn.z, wp.z))
		mx = Vector3(maxf(mx.x, wp.x), maxf(mx.y, wp.y), maxf(mx.z, wp.z))
	return AABB(mn, mx - mn)


## MultiMeshInstance3D 的包络：用 mesh 的 AABB 乘上各实例变换，取并集。
## 无头模式下 `get_instance_transform()` 回读不可信（全零），所以这里只把
## **实例数**当事实，包络退化为「mesh AABB × 节点变换」——足以判断"这里有东西"。
func _world_aabb_mm(mmi: MultiMeshInstance3D) -> AABB:
	if mmi.multimesh == null or mmi.multimesh.mesh == null:
		return AABB()
	var a := mmi.multimesh.mesh.get_aabb()
	var xf := mmi.global_transform
	var p := a.position
	var s := a.size
	var mn := xf * p
	var mx := mn
	for i in range(8):
		var c := p + Vector3(
			s.x if (i & 1) else 0.0,
			s.y if (i & 2) else 0.0,
			s.z if (i & 4) else 0.0)
		var wp := xf * c
		mn = Vector3(minf(mn.x, wp.x), minf(mn.y, wp.y), minf(mn.z, wp.z))
		mx = Vector3(maxf(mx.x, wp.x), maxf(mx.y, wp.y), maxf(mx.z, wp.z))
	return AABB(mn, mx - mn)
