extends Node
## 只读探针：实测入口安全房 v007 的房间包与通用组件在**运行时**的材质状态。
## 目的：判定「材质球丢失」的真实形态 —— 是 surface 材质为 null、albedo 贴图缺失、
## 还是根本没跑色盘 post-import 脚本导致材质退化成 glTF 内嵌默认材质。
## 对照组 = common_components 四件套（已知 import_script 绑定正确）。
## 2026-09-20：包清单改从 `DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS` 动态取 ——
## 原先是第三份硬编码副本（按 17 件抄的，删件后漂移到 17 vs 15）。
## 同批补 `get_tree().quit()`：此前它曾是 `tests/verification/` 里唯一不退出、
## 会把批量回归挂住的探针（autoload 常驻，进程永不结束）。

const ROOM_RUNTIME_ROOT := "res://assets/art/environments/tower_zones/battle/runtime/"
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
const COMPONENT_PATHS: Array[String] = [
	"common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn",
	"common_components/wall_door_5m/wall_door_5m_root_top3d.tscn",
	"common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn",
	"common_components/door_5m/door_5m_root_top3d.tscn",
]

var _totals := {
	"packages": 0, "mesh_instances": 0, "surfaces": 0,
	"surface_material_null": 0, "albedo_null": 0,
	"albedo_palette": 0, "albedo_other": 0, "emissive_multiply": 0,
}


func _ready() -> void:
	print("=== 色盘贴图 ===")
	var palette := load(PALETTE_PATH) as Texture2D
	print("  %s -> %s" % [PALETTE_PATH, "OK %s" % str(palette.get_size()) if palette != null else "缺失"])

	var package_ids: Array[String] = DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS
	print("")
	print("=== 房间包 %d 件（runtime/entry_safe_room/*；真源 DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS）===" % package_ids.size())
	for package_id in package_ids:
		_inspect_scene(
			"%sentry_safe_room/%s/%s_root_top3d.tscn" % [ROOM_RUNTIME_ROOT, package_id, package_id],
			package_id, "package"
		)

	print("")
	print("=== 对照组：通用组件 v006 四件套（import_script 已绑定）===")
	for rel in COMPONENT_PATHS:
		_inspect_scene(ROOM_RUNTIME_ROOT + rel, rel.get_file().get_basename(), "component")

	print("")
	print("=== 汇总 ===")
	for key in _totals.keys():
		print("  %-22s %d" % [key, int(_totals[key])])

	print("")
	print("PROBE_SAFE_ROOM_MATERIALS_DONE")
	await get_tree().process_frame
	get_tree().quit(0)


func _inspect_scene(scene_path: String, label: String, kind: String) -> void:
	if not ResourceLoader.exists(scene_path):
		print("  %-26s <场景缺失> %s" % [label, scene_path])
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		print("  %-26s <加载失败>" % label)
		return
	var root := packed.instantiate() as Node3D
	add_child(root)
	if kind == "package":
		_totals["packages"] = int(_totals["packages"]) + 1

	var meshes: Array = []
	_collect_meshes(root, meshes)
	var lines: Array[String] = []
	for value in meshes:
		var mesh_instance := value as MeshInstance3D
		if mesh_instance.mesh == null:
			lines.append("mesh=null")
			continue
		var overrides := "override=%s" % ("有" if mesh_instance.material_override != null else "无")
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.mesh.surface_get_material(surface_index) as BaseMaterial3D
			_totals["surfaces"] = int(_totals["surfaces"]) + 1
			if material == null:
				_totals["surface_material_null"] = int(_totals["surface_material_null"]) + 1
				lines.append("s%d=材质NULL" % surface_index)
				continue
			var texture := material.albedo_texture
			var texture_label := "无贴图"
			if texture != null:
				if str(texture.resource_path) == PALETTE_PATH:
					texture_label = "色盘"
					_totals["albedo_palette"] = int(_totals["albedo_palette"]) + 1
				else:
					texture_label = str(texture.resource_path).get_file()
					_totals["albedo_other"] = int(_totals["albedo_other"]) + 1
			else:
				_totals["albedo_null"] = int(_totals["albedo_null"]) + 1
			if material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY:
				_totals["emissive_multiply"] = int(_totals["emissive_multiply"]) + 1
			lines.append("s%d=[%s] albedo=%s emis=%s filter=%s" % [
				surface_index,
				str(material.resource_name),
				texture_label,
				_emission_text(material),
				_nearest_text(material),
			])
		lines.append(overrides)
	_totals["mesh_instances"] = int(_totals["mesh_instances"]) + meshes.size()
	print("  %-26s mesh=%d  %s" % [label, meshes.size(), "  ".join(lines)])
	root.queue_free()


func _emission_text(material: BaseMaterial3D) -> String:
	if not material.emission_enabled:
		return "关"
	if material.emission_texture == null:
		return "开/无贴图"
	return "开/%s" % ("色盘" if str(material.emission_texture.resource_path).replace("res://", "res://") == PALETTE_PATH else "其它")


func _nearest_text(material: BaseMaterial3D) -> String:
	return "NEAREST" if material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST else "LINEAR"


func _collect_meshes(root: Node, out: Array) -> void:
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		_collect_meshes(child, out)
