extends Node

const OLD_VISUALS := [
	"res://assets/art/environments/open_world/components/tower_02/floor_00/env_tower_02_floor_00_visual_top3d.glb",
	"res://assets/art/environments/open_world/components/tower_02/crane_00_slew_cab/env_tower_02_crane_00_slew_cab_visual_top3d.glb",
	"res://assets/art/environments/open_world/components/tower_02/roof_warning/env_tower_02_roof_warning_visual_top3d.glb",
]
const TARGET := "res://assets/art/environments/open_world/components/skyline_08/floor_06/env_skyline_08_floor_06_visual_top3d.glb"

func _ready() -> void:
	var roles: Dictionary = {}
	for path: String in OLD_VISUALS:
		var packed := load(path) as PackedScene
		print("OLD ", path, " loaded=", packed != null)
		if packed == null:
			continue
		var instance := packed.instantiate()
		for value in instance.find_children("*", "MeshInstance3D", true, false):
			var mi := value as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var material := mi.get_active_material(i)
				print("OLD_MAT path=", value.get_path(), " surface=", i, " name=", material.resource_name if material else "<null>", " res=", material.resource_path if material else "<null>")
				if material != null:
					roles[material.resource_name] = material
		instance.free()
	print("ROLES=", roles.keys())
	var target_packed := load(TARGET) as PackedScene
	if target_packed == null:
		print("TARGET load failed")
		get_tree().quit(1)
		return
	var target := target_packed.instantiate()
	add_child(target)
	await get_tree().process_frame
	for value in target.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		var names: Array = mi.get_meta("existing_material_roles", [])
		print("TARGET path=", value.get_path(), " surfaces=", mi.mesh.get_surface_count(), " names=", names)
		for i in mi.mesh.get_surface_count():
			var material := mi.get_active_material(i)
			print("TARGET_MAT path=", value.get_path(), " surface=", i, " name=", material.resource_name if material else "<null>", " res=", material.resource_path if material else "<null>")
	get_tree().quit(0)
