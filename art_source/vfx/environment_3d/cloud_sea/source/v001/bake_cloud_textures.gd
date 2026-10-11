extends SceneTree
## Offline authoring only: convert compact R8 volumes to native Godot Texture3D resources.

func _initialize() -> void:
	# Godot 4.6.3 Compatibility's Texture3D readback shifts slices; bake with RenderingDevice.
	if RenderingServer.get_rendering_device() == null:
		push_error("Bake cloud Texture3D resources with --rendering-method forward_plus (real renderer).")
		quit(1)
		return
	var folder := "res://assets/art/vfx/environment_3d/cloud_sea/"
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "source/v001/texture_bake.json"))
	for name in ["keepout", "noise"]:
		var dims: Array = spec[name]["dimensions"]
		var width := int(dims[0])
		var height := int(dims[1])
		var depth := int(dims[2])
		var bytes := FileAccess.get_file_as_bytes(folder + "source/v001/" + name + ".raw")
		var layers: Array[Image] = []
		for layer in range(depth):
			layers.append(Image.create_from_data(width, height, false, Image.FORMAT_R8, bytes.slice(layer * width * height, (layer + 1) * width * height)))
		var texture := ImageTexture3D.new()
		var result := texture.create(Image.FORMAT_R8, width, height, depth, false, layers)
		if result != OK:
			push_error("Cloud texture bake failed: " + name)
			quit(1)
			return
		ResourceSaver.save(texture, folder + "cloud_" + name + ".res", ResourceSaver.FLAG_COMPRESS)
		print("CLOUD_TEXTURE_BAKED ", name, " ", dims)
	quit(0)
