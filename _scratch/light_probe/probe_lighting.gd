extends Node
## 临时探针：对照办公室/桥房房型组件与既有通用件的运行时材质受光契约。
## 判据：shading_mode / emission / metallic / roughness / 法线 / GI 模式 / 阴影。

const TARGETS := [
	["EXP office wall_t615_5m", "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/office_room/wall_t615_5m/wall_t615_5m_root_top3d.tscn"],
	["EXP office door_wall", "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/office_room/door_wall/door_wall_root_top3d.tscn"],
	["EXP office floor_tile_5m", "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/office_room/floor_tile_5m/floor_tile_5m_root_top3d.tscn"],
	["EXP bridge wall_x780", "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/bridge_room/wall_x780/wall_x780_root_top3d.tscn"],
	["EXP bridge tile_upper", "res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/bridge_room/tile_upper/tile_upper_root_top3d.tscn"],
	["BATTLE wall_standard_5m", "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"],
	["BATTLE floor_tile_c01", "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn"],
]

const SHADING_NAMES := ["unshaded", "per_pixel", "per_vertex"]


func _ready() -> void:
	for entry in TARGETS:
		_dump(str(entry[0]), str(entry[1]))
	print("PROBE_LIGHTING_DONE")
	get_tree().quit(0)


func _dump(label: String, path: String) -> void:
	print("---- %s ----" % label)
	if not ResourceLoader.exists(path):
		print("  MISSING %s" % path)
		return
	var packed := load(path) as PackedScene
	var root := packed.instantiate() as Node3D
	if root == null:
		print("  NOT Node3D")
		return
	print("  root=%s class=%s" % [root.name, root.get_class()])
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	print("  mesh_count=%d" % meshes.size())
	for mesh_value in meshes:
		var mesh_instance := mesh_value as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		print("  node=%s gi_mode=%d cast_shadow=%d visible=%s" % [
			mesh_instance.name,
			int(mesh_instance.gi_mode),
			int(mesh_instance.cast_shadow),
			str(mesh_instance.visible),
		])
		for surface in range(mesh.get_surface_count()):
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			var arrays := mesh.surface_get_arrays(surface)
			var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var normal_count := 0
			if arrays[Mesh.ARRAY_NORMAL] != null:
				normal_count = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).size()
			var color_count := 0
			if arrays[Mesh.ARRAY_COLOR] != null:
				color_count = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size()
			if material == null:
				print("  [%s s%d] material=null v=%d n=%d c=%d" % [
					mesh_instance.name, surface, vertex_count, normal_count, color_count
				])
				continue
			var shading := int(material.shading_mode)
			print(
				"  [%s s%d] mat=%s shading=%s emission_on=%s emission=%s energy=%.2f op=%d metallic=%.2f rough=%.2f albedo=%s vcolor_as_albedo=%s v=%d n=%d c=%d"
				% [
					mesh_instance.name,
					surface,
					material.resource_name,
					SHADING_NAMES[shading] if shading < SHADING_NAMES.size() else str(shading),
					str(material.emission_enabled),
					str(material.emission),
					material.emission_energy_multiplier,
					int(material.emission_operator),
					material.metallic,
					material.roughness,
					str(material.albedo_texture.resource_path) if material.albedo_texture != null else "none",
					str(material.vertex_color_use_as_albedo),
					vertex_count,
					normal_count,
					color_count,
				]
			)
	root.free()
