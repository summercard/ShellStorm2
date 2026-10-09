extends Node

func _ready() -> void:
	var stage := TowerFloorStage3D.new()
	stage.floor_index = 0
	add_child(stage)
	await get_tree().process_frame
	var birds := stage.get_node_or_null("RooftopGroundBirdFlock") as Node3D
	assert(birds != null, "ROOFTOP_GROUND_BIRD_MISSING")
	assert(is_equal_approx(birds.position.x, 27.0), "ROOFTOP_BIRD_X_WRONG")
	assert(is_equal_approx(birds.position.y, 0.0), "ROOFTOP_BIRD_Y_WRONG")
	assert(is_equal_approx(birds.position.z, -27.0), "ROOFTOP_BIRD_Z_WRONG")
	assert(str(birds.get_meta("placement", "")) == "main_tower_100f_rooftop_east_of_bridge", "ROOFTOP_BIRD_PLACEMENT_WRONG")
	print("ROOFTOP_BIRD_RUNTIME_OK position=%s placement=%s" % [str(birds.position), str(birds.get_meta("placement"))])
	get_tree().quit(0)
