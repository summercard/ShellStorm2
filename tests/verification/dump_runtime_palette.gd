extends SceneTree

func _init() -> void:
	var texture := load("res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png") as Texture2D
	assert(texture != null)
	var image := texture.get_image()
	assert(image != null)
	assert(not image.has_mipmaps(), "shared palette must not contain mipmaps")
	print("RUNTIME_PALETTE size=",image.get_size()," format=",image.get_format()," mipmaps=",image.has_mipmaps())
	var err := image.save_png("/tmp/base99_runtime_palette.png")
	assert(err == OK)
	quit()
