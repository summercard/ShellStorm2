extends SceneTree
## Run with isolated APPDATA/LOCALAPPDATA. Uses the authored level and actual door interactions.

const ROOM_LAYOUT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_09_static_layout.tscn"
const AUTHORED_DOOR_NODES := {
	"CyberSpaceBlueBox": {
		"preset": "res://assets/art/vfx/environment_3d/cyber_space/runtime/vfx_env_cyber_space_blue_root_top3d.tscn",
		"center": Vector3(0.6565552, 1.1202135, -16.882553),
		"size": Vector3(10, 19.693068, 10),
		"shader": "scene_cyber_space.gdshader",
	},
	"VoidErosionBox": {
		"preset": "res://assets/art/vfx/environment_3d/void_erosion/runtime/vfx_env_void_erosion_root_top3d.tscn",
		"center": Vector3(0.43335724, 3.3648272, -21.06951),
		"size": Vector3(4.2714515, 6, 10),
		"shader": "scene_void_erosion.gdshader",
	},
}
var failures := 0
var checks := 0
var evidence_dir := ""

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("EXP99 FAIL: ", message)
	return ok

func _physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _wait_for_choice_or_end(event: Node, dialogue: Node, require_choices: bool) -> bool:
	for _i in range(780):
		await physics_frame
		if not require_choices and not bool(event.call("get_snapshot").interaction_active):
			return true
		if require_choices and bool(event.call("has_dialogue_choices")):
			return true
		if bool(dialogue.call("is_active")):
			dialogue.call("advance")
	return false

func _north_wall_receivers(art: Node, box: Node3D, shader_name: String) -> int:
	var count := 0
	var box_size := box.get("box_size") as Vector3
	var bounds := AABB(-box_size * 0.5, box_size)
	for wall in art.get_children():
		if wall.get_meta("tower_wall_direction", "") != "north":
			continue
		for value in wall.find_children("*", "MeshInstance3D", true, false):
			var mesh := value as MeshInstance3D
			if mesh.mesh == null or mesh.has_meta("_shader_volume_coating") or not mesh.is_visible_in_tree():
				continue
			var to_box := box.global_transform.affine_inverse() * mesh.global_transform
			var overlap := (to_box * mesh.get_aabb()).intersection(bounds)
			if overlap.size.x <= 0.0 or overlap.size.y <= 0.0:
				continue
			for coating in mesh.get_children(true):
				if not coating is MeshInstance3D or not coating.has_meta("_shader_volume_coating") or not coating.is_visible_in_tree():
					continue
				var material := coating.material_override as ShaderMaterial
				if material != null and material.shader != null and material.shader.resource_path.get_file() == shader_name:
					count += 1
					break
	return count

func _capture_evidence(label: String) -> void:
	if evidence_dir.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty() and image.save_png(evidence_dir.path_join(label + ".png")) == OK, "rendered evidence: " + label)

func _run() -> void:
	evidence_dir = OS.get_environment("SS2_BRANCH_EVIDENCE_DIR")
	var isolated := OS.get_environment("APPDATA").path_join("Godot").simplify_path().replace("\\", "/").to_lower()
	if not check(OS.get_user_data_dir().simplify_path().replace("\\", "/").to_lower().begins_with(isolated + "/"), "isolated save path: " + OS.get_user_data_dir()):
		quit(1)
		return
	var scene := load("res://scenes/ExpeditionLevel99_3D.tscn") as PackedScene
	var level := scene.instantiate()
	level.set("test_mode", true)
	level.set("run_seed_override", 91533)
	root.add_child(level)
	await _physics_frames(6)
	var branch := level.get_node_or_null("SecretBranches")
	if not check(branch != null, "SecretBranches exists"):
		quit(1)
		return
	var state: Dictionary = branch.call("debug_snapshot")
	var rooms := branch.get("_branch_rooms") as Dictionary
	check(state.pair_count == 1 and rooms.size() == 1 and rooms.has("test_room_09"), "one fixed test branch and one room")
	check(state.doors.size() == 2 and state.doors.has("EXP99_TEST_ROOM_ENTRY") and state.doors.has("E0"), "entry and same-route return only; no Boss bypass")
	var row := rooms.get("test_room_09", {}) as Dictionary
	var room := row.get("room") as Node3D
	var player := level.get("player") as CharacterBody3D
	var doors := branch.get("_doors") as Dictionary
	var entry := doors.get("EXP99_TEST_ROOM_ENTRY") as Node3D
	var return_door := doors.get("E0") as Node3D
	if not check(room != null and player != null and entry != null and return_door != null, "live room, player, entry and return nodes"):
		quit(1)
		return
	var art := room.get_node_or_null("AuthoredLayoutArtRoot")
	check(art != null and art.scene_file_path == ROOM_LAYOUT and room.get_meta("static_layout_scene_loaded", false), "direct load of official room_09 TSCN as full shell")
	for name: String in AUTHORED_DOOR_NODES:
		var spec: Dictionary = AUTHORED_DOOR_NODES[name]
		var box := art.find_child(name, true, false) as Node3D if art != null else null
		if not check(box != null, "authored door object exists: " + name):
			continue
		var local := room.global_transform.affine_inverse() * box.global_transform
		print("EXP99_AUTHORED_DOOR ", name, " center=", local.origin, " size=", box.get("box_size"), " preset=", box.scene_file_path)
		check(box.scene_file_path == spec["preset"] and local.origin.is_equal_approx(spec["center"]) and (box.get("box_size") as Vector3).is_equal_approx(spec["size"]), "original authored object, transform and box size: " + name)
	player.global_position = entry.global_position - entry.global_basis.z * 1.4 + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	await _physics_frames(4)
	var candidate: Dictionary = entry.call("get_interaction_candidate", player)
	check(not candidate.is_empty() and bool(entry.call("perform_interaction", player, candidate)), "use real door interaction without clearing room_01")
	await _physics_frames(22)
	check(level.call("get_current_room_id") == "test_room_09" and player.is_on_floor(), "teleport puts player on the actual office floor")
	var event := room.get_node_or_null("ChannelManagerEncounter")
	check(event != null and event.call("get_snapshot").npc_state == "sleep", "channel manager spawns asleep")
	check(not row.combat and not (level.get("_spawned_rooms") as Dictionary).has("test_room_09"), "no branch enemies in the presentation test room")
	if event != null:
		var actor := event.get_node("ChannelManagerNPC") as Node3D
		player.global_position = actor.global_position + Vector3(0, 0.05, 2.2)
		var talk: Dictionary = event.call("get_interaction_candidate", player)
		check(not talk.is_empty() and event.call("perform_interaction", player, talk), "talk through the regular interaction provider")
		check(bool(player.get("input_locked")) and bool(player.get("aim_locked")), "locks input as soon as the NPC is activated")
		var locked_at := Vector2(player.global_position.x, player.global_position.z)
		Input.action_press("move_right")
		await _physics_frames(12)
		Input.action_release("move_right")
		check(Vector2(player.global_position.x, player.global_position.z).distance_to(locked_at) < 0.03, "movement input cannot move the player during activation")
		var dialogue := root.get_node("DialogueUI")
		if check(await _wait_for_choice_or_end(event, dialogue, true), "first conversation reaches the payment option"):
			check(bool(player.get("input_locked")) and bool(event.call("dialogue_needs_cursor")), "choices still lock movement and allow cursor interaction")
			level.call("set_scripted_input_hold", true, false, "test_other_owner")
			(event.get("_leave_button") as Button).pressed.emit()
			check(bool(player.get("input_locked")) and not bool(event.call("has_dialogue_choices")), "leaving removes only this encounter's input hold")
			level.call("set_scripted_input_hold", false, false, "test_other_owner")
			check(not bool(player.get("input_locked")), "leaving restores movement when no other owner holds it")
			check(bool(event.call("perform_interaction", player, talk)), "can start a second conversation")
			check(await _wait_for_choice_or_end(event, dialogue, true), "repeat dialogue shows choices")
			check(bool(level.call("try_close_modal_for_pause")) and not bool(player.get("input_locked")), "closing the dialogue returns movement")
			check(bool(event.call("perform_interaction", player, talk)), "can talk again after closing")
			if check(await _wait_for_choice_or_end(event, dialogue, true), "payment choice after reopening"):
				var game := root.get_node("GameManager")
				game.call("add_currency", 1200 - int(game.get("currency")))
				(event.get("_pay_button") as Button).pressed.emit()
				dialogue.call("close")
				check(int(game.get("currency")) == 1200 and not bool(player.get("input_locked")) and not bool(event.call("get_snapshot").paid), "aborting before the aperture opens releases only this hold and refunds the unfinished purchase")
				check(bool(event.call("perform_interaction", player, talk)) and await _wait_for_choice_or_end(event, dialogue, true), "can retry after an interrupted purchase")
				(event.get("_pay_button") as Button).pressed.emit()
				check(int(game.get("currency")) == 200 and bool(player.get("input_locked")), "payment debits 1000 and does not release input")
				var saw_opening := false
				var held_through_opening := true
				var beam_was_north := false
				var paid_portal := event.get_node("ChannelManagerPortal")
				var npc_runtime := event.get_node("ChannelManagerNPC")
				for _i in range(780):
					await physics_frame
					if not bool(event.call("get_snapshot").interaction_active):
						break
					held_through_opening = held_through_opening and bool(player.get("input_locked"))
					if not str(paid_portal.get("result")).is_empty() and not bool(paid_portal.call("is_open")):
						saw_opening = true
					var beam := npc_runtime.get("_beam") as MeshInstance3D
					if beam != null and beam.visible:
						beam_was_north = beam_was_north or beam.global_basis.z.normalized().z < -0.7
					if bool(dialogue.call("is_active")):
						dialogue.call("advance")
				check(saw_opening and held_through_opening and beam_was_north, "input stays held through reel, north beam release and wall opening")
				check(event.call("get_snapshot").portal_open and not bool(event.call("has_dialogue_choices")) and not bool(player.get("input_locked")) and not bool(player.get("aim_locked")), "finished portal closes dialogue and returns control automatically")
				check(not (level.get("_resolved_event_rooms") as Dictionary).has("test_room_09"), "test purchase does not settle a main-route event")
		var portal := event.get_node("ChannelManagerPortal")
		var render_camera: Camera3D
		if not evidence_dir.is_empty():
			render_camera = Camera3D.new()
			room.add_child(render_camera)
			render_camera.look_at_from_position(room.to_global(Vector3(0, 6.3, -9.0)), room.to_global(Vector3(0.43, 3.36, -21.07)))
			render_camera.fov = 59.0
			render_camera.make_current()
			portal.call("configure_room", room)
			await _capture_evidence("00_north_wall_off")
		for result: String in ["监听", "中继"]:
			portal.call("open", result)
			portal.call("_process", 1.5)
			await process_frame
			for name: String in AUTHORED_DOOR_NODES:
				var spec: Dictionary = AUTHORED_DOOR_NODES[name]
				var selected := art.find_child(name, true, false) as Node3D
				await process_frame
				var receivers := _north_wall_receivers(art, selected, str(spec["shader"]))
				print("EXP99_NORTH_WALL ", result, " object=", name, " receivers=", receivers)
				check(portal.call("is_open") and bool(selected.get("enabled")) and is_equal_approx(float(selected.get("progress")), 1.0) and receivers > 0, "authored north-wall door object receives its original shader: " + name)
			await _capture_evidence("01_north_wall_void" if result == "监听" else "02_north_wall_blue")
		if is_instance_valid(render_camera):
			render_camera.queue_free()
	player.global_position = return_door.global_position - return_door.global_basis.z * 1.2 + Vector3.UP * 0.05
	player.velocity = Vector3.ZERO
	await _physics_frames(3)
	var back: Dictionary = return_door.call("get_interaction_candidate", player)
	check(not back.is_empty() and bool(return_door.call("perform_interaction", player, back)), "return door can be used")
	await _physics_frames(22)
	check(level.call("get_current_room_id") == "room_01" and player.is_on_floor(), "return lands in room_01, not the Boss route")
	level.queue_free()
	await process_frame
	print("EXPEDITION99_CHANNEL_MANAGER_BRANCH_TESTS ", checks, " checks; ", failures, " failures")
	quit(0 if failures == 0 else 1)
