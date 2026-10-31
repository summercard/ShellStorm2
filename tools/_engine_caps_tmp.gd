extends Node
func _ready() -> void:
	var keys := ProjectSettings.get_property_list()
	var hits: Array[String] = []
	for entry in keys:
		var name := str(entry.get("name", ""))
		var lower := name.to_lower()
		if lower.contains("shader") or lower.contains("pipeline") or lower.contains("pso") or lower.contains("ubershader"):
			hits.append(name)
	print("CAPS_ENGINE ", Engine.get_version_info().get("string", "?"))
	print("CAPS_RENDER ", RenderingServer.get_current_rendering_method(), " / ", RenderingServer.get_current_rendering_driver_name())
	print("CAPS_SETTINGS ", hits.size())
	for h in hits:
		print("  CAPS_KEY ", h, " = ", str(ProjectSettings.get_setting(h, "<unset>")))
	# 材质相关能力
	print("CAPS_HAS_INSTANCE_PARAM ", Node3D.new().has_method("set_instance_shader_parameter"))
	get_tree().quit(0)
