extends Node
## 地板贴图密度体检：量「一块 5m 地砖里，贴图重复了几次」。
##
## 业主报单：「砖块密度好像不是 5X5 的，这个也太细了」。
## 要回答的是**两个完全不同的东西**，必须分开量：
##
##   ① 地砖**摆放**间距 —— `_floor_grid()` 按 5m 格心摆，25×25 房 = 25 块。
##      这条由烘焙日志 `cells=5x5 tiles=25` 直接可证，与贴图无关。
##   ② 一块地砖**内部**的贴图重复次数 —— 由 UV 范围与材质 `uv1_scale` 决定。
##      业主看到的「细格子」如果是这一项，就得改 UV 或 uv1_scale，而不是改摆放。
##
## 本探针量 ②：读网格 UV 的 (min,max) 范围 × 材质 uv1_scale，得出贴图在一个 5m 面
## 上重复了几次。`1.0` = 一张贴图刚好铺满 5m；`10.0` = 一张贴图被缩成 0.5m。
##
## 只读。

const FLOORS := {
	"stone": "res://assets/art/environments/tower_zones/expedition/components/common_components/manor_floor_stone/env_manor_floor_stone_visual_top3d.glb",
	"wood": "res://assets/art/environments/tower_zones/expedition/components/common_components/manor_floor_wood/env_manor_floor_wood_visual_top3d.glb",
	"bath": "res://assets/art/environments/tower_zones/expedition/components/common_components/manor_floor_bath/env_manor_floor_bath_visual_top3d.glb",
}


func _ready() -> void:
	for key in FLOORS.keys():
		_report(str(key), str(FLOORS[key]))
	get_tree().quit(0)


func _report(label: String, path: String) -> void:
	print("=== %s ===" % label)
	if not ResourceLoader.exists(path):
		print("  缺文件 %s" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("  加载失败")
		return
	var root := packed.instantiate() as Node3D
	add_child(root)
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	print("  MeshInstance3D 数量 = %d" % meshes.size())
	for index in range(meshes.size()):
		var mi := meshes[index] as MeshInstance3D
		var mesh := mi.mesh
		if mesh == null:
			continue
		var aabb := mesh.get_aabb()
		print("  [%d] %-28s aabb size=(%.3f, %.3f, %.3f)  surface=%d"
			% [index, str(mi.name), aabb.size.x, aabb.size.y, aabb.size.z,
				mesh.get_surface_count()])
		for s in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(s)
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var uv_range := ""
			if uvs is PackedVector2Array and (uvs as PackedVector2Array).size() > 0:
				var u_min := 1e9
				var u_max := -1e9
				var v_min := 1e9
				var v_max := -1e9
				for uv in uvs as PackedVector2Array:
					u_min = minf(u_min, uv.x); u_max = maxf(u_max, uv.x)
					v_min = minf(v_min, uv.y); v_max = maxf(v_max, uv.y)
				uv_range = "u=[%.4f..%.4f] v=[%.4f..%.4f] 跨度=(%.4f, %.4f)" % [
					u_min, u_max, v_min, v_max, u_max - u_min, v_max - v_min]
			else:
				uv_range = "无 UV"
			print("       surface %d: %s" % [s, uv_range])
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				var tex := bm.albedo_texture
				print("       材质 %s  uv1_scale=%s  uv1_offset=%s"
					% [bm.resource_name if not bm.resource_name.is_empty() else "(未命名)",
						str(bm.uv1_scale), str(bm.uv1_offset)])
				if tex != null:
					print("       贴图 %s  %dx%d  过滤=%d（0=Nearest 1=Linear …）"
						% [tex.resource_path.get_file(), tex.get_width(), tex.get_height(),
							int(bm.texture_filter)])
				else:
					print("       贴图 无（纯色）  albedo=%s" % str(bm.albedo_color))
			else:
				print("       材质 %s" % str(mat))
	root.queue_free()
