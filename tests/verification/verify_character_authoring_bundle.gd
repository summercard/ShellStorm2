extends Node

const PACKAGE := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v021/"
const OLD := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v008.tscn"

func _ready() -> void:
	var failures: Array[String] = []
	var old: Node3D = load(OLD).instantiate()
	var current: Node3D = load(PACKAGE + "runtime/chr_bunny01_root_v021.tscn").instantiate()
	add_child(old)
	add_child(current)
	old.set_process(false)
	current.set_process(false)
	var old_bounds := bounds(old)
	var new_bounds := bounds(current)
	if old_bounds.position.distance_to(new_bounds.position) > 0.002 or old_bounds.size.distance_to(new_bounds.size) > 0.002:
		failures.append("Rest silhouette changed: %s -> %s" % [old_bounds, new_bounds])
	for child in current.find_children("*", "CollisionObject3D", true, false):
		failures.append("Presentation contains physics: " + str(child.get_path()))
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKAGE + "exports/anim_bunny01_library_v021.json"))
	var required := ["idle", "moving", "dashing", "hurt", "locked", "falling", "landing", "dead", "walking", "armed_walking", "armed_moving", "armed_idle"]
	for state in required:
		if not library.clips.has(state): failures.append("Missing " + state)
		else:
			var clip: Dictionary = library.clips[state]
			if float(clip.duration) <= 0 or clip.frames.size() < 2: failures.append("Invalid clip " + state)
	current.set("_state", "moving")
	var driver := CharacterMotionLibrary3D.new()
	driver.bind(current)
	driver.apply(current, 0.15)
	if driver.active_clip != "moving" or absf(current.foot_l.position.y - current.foot_r.position.y) < 0.001:
		failures.append("Imported moving bones do not animate alternate feet")
	for clip_name in ["idle", "moving", "armed_idle", "armed_moving"]:
		var armed: bool = clip_name.begins_with("armed_")
		current.set("_state", "moving" if "moving" in clip_name else "idle")
		current.set("_weapon_grip_pose_active", armed)
		current.set("_weapon_class", "sidearm")
		var clip_driver := CharacterMotionLibrary3D.new()
		clip_driver.bind(current)
		for frame in range(120):
			clip_driver.apply(current, 1.0 / 60.0)
			if clip_driver.active_clip != clip_name:
				failures.append("Wrong authored clip: " + clip_name)
			for joint: Node3D in [current.visual_root, current.body, current.head, current.bunny_hand_l, current.bunny_hand_r, current.foot_l, current.foot_r]:
				if joint.scale.distance_to(Vector3.ONE) > 0.002:
					failures.append("Base clip deforms mesh: " + clip_name + "/" + joint.name)
			if armed and current.bunny_hand_r.global_position.distance_to(current.weapon_socket.global_position) > 0.001:
				failures.append("Authored hand detached from weapon socket")
	if library.clips.size() != required.size(): failures.append("Unexpected clip count")
	print("CHARACTER_REST_BOUNDS old=", old_bounds, " new=", new_bounds)
	old.queue_free()
	current.queue_free()
	if failures.is_empty():
		print("CHARACTER_AUTHORING_BUNDLE_OK: bounds, no physics, twelve Blender clips, moving and palm-grip playback")
		get_tree().quit()
	else:
		for failure in failures: push_error(failure)
		get_tree().quit(1)

func bounds(avatar: Node3D) -> AABB:
	var low := Vector3(INF,INF,INF)
	var high := Vector3(-INF,-INF,-INF)
	for node in avatar.get_node("VisualRoot/BunnyRig").find_children("*","MeshInstance3D",true,false):
		if not node.is_visible_in_tree(): continue
		var box: AABB = node.global_transform * node.get_aabb()
		low=low.min(box.position)
		high=high.max(box.end)
	return AABB(low,high-low)
