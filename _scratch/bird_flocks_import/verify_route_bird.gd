extends Node
const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"
func _ready() -> void:
	var scene := load(ROUTE) as PackedScene
	assert(scene != null, "ROUTE_LOAD_FAILED")
	var route := scene.instantiate() as Node3D
	add_child(route)
	await get_tree().process_frame
	var birds := route.get_node_or_null("FlybyBirdFlock") as Node3D
	assert(birds != null, "ROUTE_FLYBY_MISSING")
	print("ROUTE_BIRD_OBSERVED position=%s meta=%s" % [str(birds.position), str(birds.get_meta("placement", ""))])
	assert(is_equal_approx(birds.position.x, 18.0), "ROUTE_FLYBY_X_WRONG")
	assert(is_equal_approx(birds.position.y, 6.0), "ROUTE_FLYBY_Y_WRONG")
	assert(is_equal_approx(birds.position.z, -108.0), "ROUTE_FLYBY_Z_WRONG")
	assert(str(birds.get_meta("placement", "")) == "above_tower_02_between_bridge_mid_section", "ROUTE_PLACEMENT_META_WRONG")
	print("ROUTE_BIRD_RUNTIME_OK position=%s placement=%s" % [str(birds.position), str(birds.get_meta("placement"))])
	get_tree().quit(0)
