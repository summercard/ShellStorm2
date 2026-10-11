extends SceneTree
## Offline authoring only: convert compact R8 volumes to native Godot Texture3D resources.

func _initialize() -> void:
	# Godot 4.6.3 Compatibility's Texture3D readback shifts slices; bake with RenderingDevice.
	if RenderingServer.get_rendering_device() == null:
		push_error("Bake cloud Texture3D resources with --rendering-method forward_plus (real renderer).")
		quit(1)
		return
	var folder := "res://assets/art/vfx/environment_3d/cloud_sea/"
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "source/v002/texture_bake.json"))
	for name in ["keepout", "noise"]:
		var dims: Array = spec[name]["dimensions"]
		var width := int(dims[0])
		var height := int(dims[1])
		var depth := int(dims[2])
		var channels := 3 if name == "noise" else 1
		var format := Image.FORMAT_RGB8 if name == "noise" else Image.FORMAT_R8
		var slice_bytes := width * height * channels
		var bytes := FileAccess.get_file_as_bytes(folder + "source/v002/" + name + ".raw")
		var layers: Array[Image] = []
		for layer in range(depth):
			layers.append(Image.create_from_data(width, height, false, format, bytes.slice(layer * slice_bytes, (layer + 1) * slice_bytes)))
		var texture := ImageTexture3D.new()
		var result := texture.create(format, width, height, depth, false, layers)
		if result != OK:
			push_error("Cloud texture bake failed: " + name)
			quit(1)
			return
		ResourceSaver.save(texture, folder + "cloud_" + name + ".res", ResourceSaver.FLAG_COMPRESS)
		print("CLOUD_TEXTURE_BAKED ", name, " ", dims)
	quit(0)
