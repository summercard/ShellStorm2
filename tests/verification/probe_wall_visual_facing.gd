extends Node
## 探针：墙体「装饰面朝向」实证。
##
## 三个问题一次答清：
##   ① prefab 的装饰几何到底凸在 **-Z 还是 +Z**？（与声明 forward_axis 是否一致）
##   ② 装饰面法向是否指向**自己所在房间内部**？（远征01 全房逐墙统计）
##   ③ 是否存在**共面重叠**（同一 5m 格子出现两份墙 ⇒ 一份被另一份盖掉）？

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LOADER := preload("res://src/map/LevelPlanLoader.gd")

const LEVEL := "expedition_01"
const SEED := 700000

const PREFABS := [
	["battle 通用墙", "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"],
	["battle 门墙", "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d.tscn"],
	["tower 实墙", "res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"],
	["tower 门墙", "res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn"],
	["L 角件", "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"],
	["纯平面占位", "res://assets/art/props/dungeon_3d/prp_room_wall_segment.tscn"],
]


func _ready() -> void:
	_probe_prefab_geometry()
	_probe_expedition_facing()
	get_tree().quit(0)


## ① 逐个 prefab：收集全部可见 MeshInstance3D，求合并 AABB（相对 prefab 根）。
func _probe_prefab_geometry() -> void:
	print("=== ① prefab 装饰几何实测（相对 prefab 根，单位 m）===")
	for entry in PREFABS:
		var label := str(entry[0])
		var path := str(entry[1])
		if not ResourceLoader.exists(path):
			print("  %-14s !! 文件不存在 %s" % [label, path])
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			print("  %-14s !! 加载失败" % label)
			continue
		var root := packed.instantiate() as Node3D
		add_child(root)
		var meshes: Array = []
		_collect_meshes(root, meshes)
		var declared := Vector3.ZERO
		var has_declared := false
		if root.has_meta("bounds_size_m"):
			declared = root.get_meta("bounds_size_m") as Vector3
			has_declared = true
		var visual_declared := Vector3.ZERO
		if root.has_meta("visual_bounds_size_m"):
			visual_declared = root.get_meta("visual_bounds_size_m") as Vector3
		var merged := AABB()
		var first := true
		var tri_total := 0
		for mesh_value in meshes:
			var mi := mesh_value as MeshInstance3D
			var world_aabb := _world_aabb(mi)
			if first:
				merged = world_aabb
				first = false
			else:
				merged = merged.merge(world_aabb)
			tri_total += mi.mesh.get_faces().size() / 3
		print("  %-14s mesh数=%d 三角=%d" % [label, meshes.size(), tri_total])
		print("      声明 bounds     = %s" % _fmt(declared))
		print("      声明 visual     = %s" % _fmt(visual_declared))
		print("      实测合并 AABB   min=%s max=%s size=%s" % [
			_fmt(merged.position),
			_fmt(merged.position + merged.size),
			_fmt(merged.size),
		])
		var fwd := str(root.get_meta("forward_axis", "?"))
		print("      声明 forward_axis = %s" % fwd)
		# 装饰凸向判定：把 AABB 的 Z 范围与结构厚度（|声明 bounds.z| 的一半）比。
		var half_z := declared.z * 0.5 if declared.z > 0.0 else 0.15
		var neg_extent := -merged.position.z - half_z
		var pos_extent := (merged.position.z + merged.size.z) - half_z
		print("      → -Z 侧超出结构 = %+.4f m ; +Z 侧超出结构 = %+.4f m" % [neg_extent, pos_extent])
		var verdict := "无法判定（对称）"
		if neg_extent > 0.002 or pos_extent > 0.002:
			verdict = "-Z 侧（与 forward_axis=-Z 一致）" if neg_extent > pos_extent else "+Z 侧（★与声明相反★）"
		print("      → 装饰凸向 = %s" % verdict)
		root.queue_free()
		remove_child(root)
	print("")


## ② 远征01：逐墙算装饰面法向，看点向房内还是房外；③ 同时查共面重叠。
func _probe_expedition_facing() -> void:
	var level_plan := LOADER.load_level_plan(LEVEL)
	if level_plan.is_empty():
		print("!! level_plan 加载失败")
		return
	var policy := level_plan.get("generation_policy", {}) as Dictionary
	var templates := LOADER.load_room_templates(LEVEL)
	var normalized := LOADER.normalize_floor(LEVEL, 0)
	var generated := GENERATOR._generate_constrained_floor(
		LEVEL, 0, SEED, normalized, policy, templates
	)
	if generated.is_empty():
		print("!! 生成为空")
		return

	print("=== ② 远征01 装饰面朝向（seed %d）===" % SEED)
	var global_lanes: Dictionary = {}
	var total_in := 0
	var total_out := 0
	var dup_count := 0
	for value in generated.get("rooms", []):
		var room := value as Dictionary
		var key := str(room.get("key", ""))
		if str(room.get("role", "")) == "stair_entry":
			continue
		var instances := room.get("authored_layout_instances", []) as Array
		var room_pos := room.get("position", Vector2.ZERO) as Vector2
		var room_in := 0
		var room_out := 0
		var walls := 0
		for inst_value in instances:
			var inst := inst_value as Dictionary
			var role := str(inst.get("slot_role", ""))
			if role not in ["solid_wall", "door_wall"]:
				continue
			walls += 1
			var rot := deg_to_rad(float(inst.get("rotation_y_deg", 0.0)))
			var pos := inst.get("position", Vector3.ZERO) as Vector3
			# 装饰面法向：prefab 声明 forward_axis=-Z。
			var normal := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, rot)
			var to_center := Vector3.ZERO - pos
			if normal.dot(to_center) > 0.0:
				room_in += 1
			else:
				room_out += 1
			# ③ 共面重叠：全局 (轴, 墙平面坐标, 5m 格号) 是否唯一。
			var side := _direction_of(rot)
			var axis := "x" if side in ["north", "south"] else "z"
			var line := (room_pos.y + pos.z) if axis == "x" else (room_pos.x + pos.x)
			var along := (room_pos.x + pos.x) if axis == "x" else (room_pos.y + pos.z)
			var lane := int(round(along / 5.0))
			var lane_key := "%s|%.3f|%d" % [axis, line, lane]
			if global_lanes.has(lane_key):
				dup_count += 1
				if dup_count <= 12:
					var prev := global_lanes[lane_key] as String
					print("    ★重复 lane %s : 先 %s / 后 %s" % [lane_key, prev, key])
			else:
				global_lanes[lane_key] = key
		total_in += room_in
		total_out += room_out
		print("  %-11s wall=%2d  法向朝内=%2d  朝外=%2d" % [key, walls, room_in, room_out])
	print("")
	print("  合计：朝内 %d / 朝外 %d" % [total_in, total_out])
	print("  全局唯一 5m 墙格数 = %d，重复格数 = %d" % [global_lanes.size(), dup_count])
	if total_out > 0:
		print("  ★ 存在朝外的墙：这些墙的装饰面朝邻房，本房看到结构背面。")
	if dup_count > 0:
		print("  ★ 存在共面重复：同一格出现两份墙，其中一份会被另一份盖掉。")
	else:
		print("  ⇒ 无共面重复：每格恰一份墙，「被邻房背面盖掉」不成立。")


func _direction_of(rot: float) -> String:
	var wrapped := fposmod(rad_to_deg(rot), 360.0)
	if is_zero_approx(wrapped):
		return "south"
	if is_equal_approx(wrapped, 180.0):
		return "north"
	if is_equal_approx(wrapped, 90.0):
		return "east"
	if is_equal_approx(wrapped, 270.0):
		return "west"
	return "?"


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			out.append(mi)
	for child in node.get_children():
		_collect_meshes(child, out)


func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local := mi.get_aabb()
	var xf := mi.global_transform
	var result := AABB()
	var first := true
	for i in range(8):
		var corner := local.position + Vector3(
			local.size.x * float(i & 1),
			local.size.y * float((i >> 1) & 1),
			local.size.z * float((i >> 2) & 1)
		)
		var world := xf * corner
		if first:
			result = AABB(world, Vector3.ZERO)
			first = false
		else:
			result = result.expand(world)
	return result


func _fmt(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
