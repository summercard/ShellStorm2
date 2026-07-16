extends Node
func _ready():
	await get_tree().create_timer(0.5).timeout
	var img = get_viewport().get_texture().get_image()
	img.save_png("/tmp/player_with_components.png")
	print("[SCREENSHOT] saved")
	get_tree().quit()
