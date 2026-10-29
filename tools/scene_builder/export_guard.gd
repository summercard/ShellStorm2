@tool
extends EditorExportPlugin

func _get_name() -> String:
	return "ShellStormSceneBuilderExportGuard"

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://addons/shellstorm_scene_builder/") or path.begins_with("res://tools/scene_builder/"):
		skip()
