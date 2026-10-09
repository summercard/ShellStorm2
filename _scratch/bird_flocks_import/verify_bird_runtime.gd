extends Node

const FLYBY := "res://assets/art/vfx/environment_3d/bird_flocks/runtime/flyby/vfx_env_birds_flyby_root_top3d.tscn"
const GROUND := "res://assets/art/vfx/environment_3d/bird_flocks/runtime/ground/vfx_env_birds_ground_root_top3d.tscn"
const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"

func _ready() -> void:
	var fly_scene := load(FLYBY) as PackedScene
	var ground_scene := load(GROUND) as PackedScene
	assert(fly_scene != null, "FLYBY_SCENE_LOAD_FAILED")
	assert(ground_scene != null, "GROUND_SCENE_LOAD_FAILED")
	var fly := fly_scene.instantiate() as Node3D
	var ground := ground_scene.instantiate() as Node3D
	add_child(fly)
	add_child(ground)
	await get_tree().process_frame
	_check_flock(fly, "VFX-ENV-BIRDS-FLYBY-3D", 12.0)
	_check_flock(ground, "VFX-ENV-BIRDS-GROUND-3D", 24.0)
	print("BIRD_RUNTIME_OK flyby=7 ground=7 collision=0")
	get_tree().quit(0)

func _check_flock(root: Node3D, asset_id: String, duration: float) -> void:
	assert(str(root.get_meta("asset_id", "")) == asset_id, asset_id + "_ASSET_ID_WRONG")
	var animation_players := root.find_children("*", "AnimationPlayer", true, false)
	assert(animation_players.size() > 0, asset_id + "_ANIMATION_PLAYER_MISSING")
	var total_meshes := root.find_children("*", "MeshInstance3D", true, false).size()
	assert(total_meshes == 7, asset_id + "_MESH_COUNT_WRONG")
	var collisions := root.find_children("*", "CollisionObject3D", true, false).size() + root.find_children("*", "CollisionShape3D", true, false).size()
	assert(collisions == 0, asset_id + "_COLLISION_PRESENT")
	for player_node in animation_players:
		var player := player_node as AnimationPlayer
		var playable := false
		for name in player.get_animation_list():
			if name != "RESET":
				playable = true
				var animation := player.get_animation(name)
				assert(animation != null, asset_id + "_ANIMATION_NULL")
				assert(animation.length > duration - 0.5 and animation.length < duration + 0.5, asset_id + "_DURATION_WRONG")
				break
		assert(playable, asset_id + "_NO_PLAYABLE_ANIMATION")
