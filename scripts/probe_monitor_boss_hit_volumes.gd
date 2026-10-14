extends Node3D
## 显示器 Boss「动画受击体积」盒子的**可复算探针**。
##
## 用途：把 `MonitorBossPresentation.HIT_VOLUMES` 里那 8 个骨局部盒子重新算一遍，
## 直接打印成可以贴回源码的常量文本。改动 `monitor_motion.json` / GLB 之后跑一次，
## 对比输出即可知道盒子是否还贴得住模型。
##
## 算法：把模型顶点按「最大权重骨」分流 ——
##   · 单骨且权重恰为 1.0 的顶点是**刚性**的，其在骨局部空间的位置不随动画变，一次算完；
##   · 其余（混合权重，或单骨但权重未归一 —— 蒙皮会按权重缩放它）必须在**每一帧**采样。
## 逐剪辑逐帧（30 Hz，共 911 帧）求并集，最后每根轴外扩 3 cm。
##
## 为什么要外扩：盒子若**恰好**等于实测 AABB，表面顶点就落在边界上，
## 浮点舍入会把它们判到盒外（实测残余 1.85%）。外扩后残余归零，且 3 cm 在 2.7 m 高的屏幕上不可见。
##
## 跑法：
##   godot --headless --path . --scene res://scripts/probe_monitor_boss_hit_volumes.tscn
## 输出：`res://outputs/_probe/monitor_boss_hit_volumes.json` 与终端上的常量文本。
const ENEMY := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const OUT := "res://outputs/_probe/monitor_boss_hit_volumes.json"
const MARGIN_M := 0.03

var presenter: MonitorBossPresentation


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var injector := MonsterInjector.new()
	var config: Dictionary = injector._generate_boss(1, 0, {"boss_content_id": "boss_monitor002", "floor_number": 0})
	var enemy: Enemy3D = ENEMY.instantiate()
	add_child(enemy)
	enemy.configure_from_enemy_data(config)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	await get_tree().physics_frame
	presenter = enemy.avatar._formal_boss_root as MonitorBossPresentation
	var rig := presenter.skeleton
	var spec := MonitorBossPresentation.get_hit_volume_spec()

	# 骨名双向映射（Godot 会把重名骨改名，如 monitor_spin ⇒ monitor_spin_2）
	var authored_index: Dictionary = {}
	var skeleton_to_authored: Dictionary = {}
	for entry in spec:
		var authored := str(entry["bone"])
		var index := presenter.hit_volume_bone_index(authored)
		assert(index >= 0, "受击盒引用了不存在的骨：" + authored)
		authored_index[authored] = index
		skeleton_to_authored[rig.get_bone_name(index)] = authored

	var buckets: Dictionary = {}
	for entry in spec:
		buckets[str(entry["bone"])] = {"rigid": [], "blended": []}
	var vertex_total := 0
	for node in presenter.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		var bind_to_bone: Array = []
		for i in range(mesh.skin.get_bind_count()):
			var bone := mesh.skin.get_bind_bone(i)
			if bone < 0:
				bone = rig.find_bone(mesh.skin.get_bind_name(i))
			bind_to_bone.append(bone)
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var stride := int(bones.size() / maxi(1, vertices.size()))
			for vi in range(vertices.size()):
				vertex_total += 1
				var entry_bones: Array = []
				var entry_weights: Array = []
				var dominant := -1
				var dominant_weight := -1.0
				for slot in range(stride):
					var bind := bones[vi * stride + slot]
					var weight := weights[vi * stride + slot]
					if bind >= bind_to_bone.size() or weight <= 0.0 or int(bind_to_bone[bind]) < 0:
						continue
					entry_bones.append(int(bind_to_bone[bind]))
					entry_weights.append(weight)
					if weight > dominant_weight:
						dominant_weight = weight
						dominant = int(bind_to_bone[bind])
				if dominant < 0:
					continue
				var dominant_name := rig.get_bone_name(dominant)
				if not skeleton_to_authored.has(dominant_name):
					continue
				var record := {"pos": vertices[vi], "bones": entry_bones, "weights": entry_weights}
				var is_rigid := entry_bones.size() == 1 and absf(float(entry_weights[0]) - 1.0) < 0.0001
				var bucket: Dictionary = buckets[str(skeleton_to_authored[dominant_name])]
				if is_rigid:
					(bucket["rigid"] as Array).append(record)
				else:
					(bucket["blended"] as Array).append(record)

	var rest_inv: Array[Transform3D] = []
	for i in range(rig.get_bone_count()):
		rest_inv.append(rig.get_bone_global_rest(i).affine_inverse())

	var accumulators: Dictionary = {}
	for entry in spec:
		accumulators[str(entry["bone"])] = {"min": [INF, INF, INF], "max": [-INF, -INF, -INF]}

	# 刚性顶点：绑定空间位置一次算完
	for entry in spec:
		var authored := str(entry["bone"])
		var bone := int(authored_index[authored])
		var acc: Dictionary = accumulators[authored]
		for value in buckets[authored]["rigid"]:
			var record: Dictionary = value
			_extend(acc, rest_inv[bone] * (record["pos"] as Vector3))

	# 混合权重顶点：逐剪辑逐帧
	var frames_sampled := 0
	for clip_value in presenter.motion.clips.keys():
		var clip := str(clip_value)
		var frame_count := int(float(presenter.motion.clips[clip].duration) * 30.0)
		for frame in range(frame_count + 1):
			presenter.sync_context({"action_id": clip, "time": float(frame) / 30.0}, false)
			frames_sampled += 1
			var poses: Array[Transform3D] = []
			var inverses: Array[Transform3D] = []
			for i in range(rig.get_bone_count()):
				var pose: Transform3D = rig.get_bone_global_pose(i)
				poses.append(pose)
				inverses.append(pose.affine_inverse())
			for entry in spec:
				var authored := str(entry["bone"])
				var bone := int(authored_index[authored])
				var acc: Dictionary = accumulators[authored]
				var inverse: Transform3D = inverses[bone]
				for value in buckets[authored]["blended"]:
					var record: Dictionary = value
					var point := Vector3.ZERO
					var record_bones: Array = record["bones"]
					var record_weights: Array = record["weights"]
					for slot in range(record_bones.size()):
						var b := int(record_bones[slot])
						point += (poses[b] * rest_inv[b] * (record["pos"] as Vector3)) * float(record_weights[slot])
					_extend(acc, inverse * point)

	var boxes: Dictionary = {}
	var lines: Array = []
	for entry in spec:
		var authored := str(entry["bone"])
		var acc: Dictionary = accumulators[authored]
		var low: Array = acc["min"]
		var high: Array = acc["max"]
		var center := Vector3((low[0] + high[0]) * 0.5, (low[1] + high[1]) * 0.5, (low[2] + high[2]) * 0.5)
		var size := Vector3(high[0] - low[0] + MARGIN_M, high[1] - low[1] + MARGIN_M, high[2] - low[2] + MARGIN_M)
		boxes[authored] = {
			"center": [center.x, center.y, center.z],
			"size": [size.x, size.y, size.z],
			"rigid_vertices": (buckets[authored]["rigid"] as Array).size(),
			"blended_vertices": (buckets[authored]["blended"] as Array).size(),
		}
		lines.append('\t{"bone": "%s", "center": Vector3(%s, %s, %s), "size": Vector3(%s, %s, %s)},' % [
			authored, _num(center.x), _num(center.y), _num(center.z), _num(size.x), _num(size.y), _num(size.z),
		])

	DirAccess.make_dir_recursive_absolute("res://outputs/_probe")
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"frames_sampled": frames_sampled,
		"margin_m": MARGIN_M,
		"vertex_total": vertex_total,
		"boxes": boxes,
	}, "\t"))
	file.close()
	print("MONITOR_HIT_VOLUMES_PROBE frames=", frames_sampled, " verts=", vertex_total)
	print("const HIT_VOLUMES := [")
	for line in lines:
		print(line)
	print("]")
	print("MONITOR_HIT_VOLUMES_PROBE_DONE -> ", OUT)
	get_tree().quit(0)


func _extend(acc: Dictionary, point: Vector3) -> void:
	var low: Array = acc["min"]
	var high: Array = acc["max"]
	acc["min"] = [minf(low[0], point.x), minf(low[1], point.y), minf(low[2], point.z)]
	acc["max"] = [maxf(high[0], point.x), maxf(high[1], point.y), maxf(high[2], point.z)]


func _num(value: float) -> String:
	if absf(value) < 0.00005:
		return "0.0"
	var text := "%.4f" % value
	text = text.rstrip("0").rstrip(".")
	return text if text.contains(".") else text + ".0"
