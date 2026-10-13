extends Node
## 只读探查：塔楼 98F「楼梯入口大厅」(STAIR_LOBBY) 里到底摆了哪些几何件。
##
## 用途：主人在实机截图里看到画面下半部有一条横向的带子/凸块，怀疑是"不该有的墙"。
##       本探针把该房间内**全部** MeshInstance3D 的世界 AABB + 材质色 dump 出来，
##       用来判断那条带子是墙体、地板、封顶，还是摄像机代理板。
##
## 跑法：
##   "<godot_console>" --headless --path "<project>" --scene res://tests/verification/probe_stair_lobby_band.tscn

const ROOM_SCENE := "res://scenes/TowerDescent3D.tscn"
## 目标层（98层 = floor_index 2）；探针按 floor_index 选房间
const TARGET_FLOOR_INDEX := 2


func _ready() -> void:
	var scene := load(ROOM_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(95)
	await get_tree().process_frame
	await get_tree().physics_frame

	var room_by_id: Dictionary = tower.get("_room_by_id")
	var records: Array = tower.get_generation_snapshot().get("records", [])

	var target: DungeonRoom3D = null
	print("=== 所有 STAIR_LOBBY ===")
	for rv in records:
		var rec: Dictionary = rv
		var id := str(rec.get("id", ""))
		var room := room_by_id.get(id) as DungeonRoom3D
		if room == null or room.room_type != "STAIR_LOBBY":
			continue
		var fi := int(round(-room.global_position.y / TowerGeometry3D.FLOOR_HEIGHT_M))
		print("  %-22s pos=%s floor_index=%d dims=%s rot_y=%.3f" % [
			id, str(room.global_position), fi, str(room.get_dimensions()), room.rotation.y])
		if fi == TARGET_FLOOR_INDEX:
			target = room

	if target == null:
		printerr("[probe] 没找到 floor_index=%d 的 STAIR_LOBBY" % TARGET_FLOOR_INDEX)
		print("STAIR_LOBBY_BAND_DONE")
		get_tree().quit(1)
		return

	# 建壳：只改流送状态不挪玩家会被 hibernate 掉，这里显式补一次
	target.ensure_shell_built()
	await get_tree().process_frame
	await get_tree().physics_frame

	var rp := target.global_position
	var dims := target.get_dimensions()
	print()
	print("=== TARGET %s ===" % target.room_id)
	print("  global_position=%s dimensions=%s rot_y=%.4f" % [str(rp), str(dims), target.rotation.y])
	print("  doors=%s" % str(target.doors))

	# ---- 1) 全部 MeshInstance3D ----
	print()
	print("=== 全部 MeshInstance3D（世界 AABB） ===")
	var meshes: Array = target.find_children("*", "MeshInstance3D", true, false)
	print("  合计 %d 个" % meshes.size())
	for mv in meshes:
		var mi := mv as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab := _world_aabb(mi)
		if ab.size.x < 0.4 and ab.size.z < 0.4:
			continue  # 小装饰件略过，避免刷屏
		print("  %-46s pos=(%7.2f,%6.2f,%7.2f) size=(%6.2f,%6.2f,%6.2f) y=[%6.2f..%6.2f] mat=%s" % [
			String(mi.name),
			ab.position.x, ab.position.y, ab.position.z,
			ab.size.x, ab.size.y, ab.size.z,
			ab.position.y, ab.end.y,
			_mat_desc(mi),
		])

	# ---- 2) 带 asset_id 的模块（墙 / 门墙 / 地板 / 封顶）----
	print()
	print("=== 带 meta.asset_id 的模块 ===")
	for nv in target.find_children("*", "Node3D", true, false):
		var node := nv as Node3D
		if node == null:
			continue
		var aid := str(node.get_meta("asset_id", ""))
		if aid.is_empty():
			continue
		var inner := node.find_children("*", "MeshInstance3D", true, false)
		var ab2 := AABB()
		var has := false
		for iv in inner:
			var mi2 := iv as MeshInstance3D
			if mi2 == null or mi2.mesh == null:
				continue
			var b := _world_aabb(mi2)
			ab2 = b if not has else ab2.merge(b)
			has = true
		print("  %-40s aid=%-32s gpos=(%7.2f,%6.2f,%7.2f) size=%s" % [
			String(node.name), aid, node.global_position.x, node.global_position.y,
			node.global_position.z, str(ab2.size) if has else "<no mesh>"])

	# ---- 3) 碰撞体（挡人 vs 摄像机代理）----
	print()
	print("=== 碰撞体（collision_layer / shape 尺寸） ===")
	for cv in target.find_children("*", "CollisionObject3D", true, false):
		var co := cv as CollisionObject3D
		if co == null:
			continue
		var metas: Array[String] = []
		for meta_name in ["camera_stair_slab", "camera_ceiling_occluder", "camera_lower_wall"]:
			if co.has_meta(meta_name):
				metas.append(meta_name)
		var shapes := co.find_children("*", "CollisionShape3D", true, false)
		var desc := ""
		for sv in shapes:
			var cs := sv as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			if cs.shape is BoxShape3D:
				var bx := cs.shape as BoxShape3D
				desc += " box=%s@%s" % [str(bx.size), str(cs.global_position)]
			else:
				desc += " %s" % cs.shape.get_class()
		print("  %-42s layer=%d mask=%d meta=%s%s" % [
			String(co.name), co.collision_layer, co.collision_mask,
			str(metas) if not metas.is_empty() else "-", desc])

	# ---- 4) 名字里带 stair / step / slab / occluder 的全部节点 ----
	print()
	print("=== 名字含 stair/step/slab/occluder/landing 的节点 ===")
	for nv2 in target.find_children("*", "Node3D", true, false):
		var n2 := nv2 as Node3D
		if n2 == null:
			continue
		var low := String(n2.name).to_lower()
		if not (
			"stair" in low or "step" in low or "slab" in low
			or "occluder" in low or "landing" in low or "flight" in low
		):
			continue
		print("  %-52s class=%s gpos=(%7.2f,%6.2f,%7.2f)" % [
			String(target.get_path_to(n2)), n2.get_class(),
			n2.global_position.x, n2.global_position.y, n2.global_position.z])

	print()
	print("STAIR_LOBBY_BAND_DONE")
	get_tree().quit(0)


func _mat_desc(mi: MeshInstance3D) -> String:
	var mat := mi.material_override
	if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		mat = mi.mesh.surface_get_material(0)
	if mat == null:
		return "<none>"
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		return "%s albedo=%s" % [sm.get_class(), str(sm.albedo_color)]
	return mat.get_class()


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
