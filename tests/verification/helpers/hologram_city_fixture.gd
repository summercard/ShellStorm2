extends RefCounted
## Headless structure fixture. Input/visual checks use verify_expedition_hologram_city.
static func create(parent: Node) -> Dictionary:
	var host := Node3D.new()
	parent.add_child(host)
	var platform := load("res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/hologram_terminal_platform/hologram_terminal_platform_root_top3d.tscn").instantiate() as BaseFacility3D
	host.add_child(platform)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(5, 8, 5)
	camera.look_at(Vector3(5, 1.85, -1.72))
	camera.make_current()
	var menu := load("res://scenes/RogueMapSelectMenu.tscn").instantiate() as RogueMapSelectMenu
	menu.set_facility(platform)
	host.add_child(menu)
	return {"host": host, "menu": menu, "camera": camera}
