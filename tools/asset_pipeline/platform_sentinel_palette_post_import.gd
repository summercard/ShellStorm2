@tool
extends EditorScenePostImport

const ROLES := {
	"01_精工金属_紫色骨架": preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/machined_metal.tres"),
	"02_细腻哑光_青绿大面": preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/matte.tres"),
	"03_清漆反光_紫粉点缀": preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/clearcoat.tres"),
	"04_柔和自发光_UI灯光": preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/soft_emission.tres"),
	"05_平台拼接显示屏": preload("res://assets/art/enemies/bosses/enm_boss_platform_sentinel/runtime/materials/display.tres"),
}

func _post_import(scene: Node) -> Object:
	for value in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (value as MeshInstance3D).mesh
		for surface in range(mesh.get_surface_count()):
			var original := mesh.surface_get_material(surface)
			if original == null or not ROLES.has(str(original.resource_name)):
				push_error("Unclassified Platform Sentinel material on %s" % value.name)
				continue
			mesh.surface_set_material(surface, ROLES[str(original.resource_name)])
	return scene
