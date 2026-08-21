extends Node

const PLAYER := preload("res://scenes/Player3D.tscn")
const WEAPON_MODEL := preload("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn")
const OUTPUT := "res://outputs/verification/player3d_weapon_grip.png"
const SIDEARM_CLOSEUP_OUTPUT := "res://outputs/verification/player3d_sidearm_idle_closeup.png"
const RIGHT_HAND_RIG_OUTPUT := "res://outputs/verification/player3d_right_hand_grip_rig.png"
const SIDEARM_MUZZLE_ALIGNMENT_OUTPUT := "res://outputs/verification/player3d_sidearm_muzzle_aim_alignment.png"
const BACK_SOCKETS_OUTPUT := "res://outputs/verification/player3d_back_weapon_sockets.png"
const BACK_SOCKETS_TOP_OUTPUT := "res://outputs/verification/player3d_back_weapon_sockets_top.png"
const DUAL_NO_BACKPACK_OUTPUT := "res://outputs/verification/player3d_dual_back_weapons_no_backpack.png"
const DUAL_NO_BACKPACK_TOP_OUTPUT := "res://outputs/verification/player3d_dual_back_weapons_no_backpack_top.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var stage := Node3D.new()
	add_child(stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("1c3039")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9dce4")
	environment.ambient_light_energy = 1.3
	world_environment.environment = environment
	stage.add_child(world_environment)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.0, 5.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("34505a")
	floor_material.roughness = 0.86
	plane.material = floor_material
	floor.mesh = plane
	stage.add_child(floor)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -32, 0)
	key.light_energy = 1.5
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.4, 3.4, -3.8)
	fill.omni_range = 9.0
	fill.light_energy = 5.0
	stage.add_child(fill)

	var sidearm_player := PLAYER.instantiate() as Player3D
	sidearm_player.position.x = -0.72
	stage.add_child(sidearm_player)
	sidearm_player.set_process(false)
	sidearm_player.set_physics_process(false)
	sidearm_player.avatar.set_process(false)
	sidearm_player.get_node("Camera3D").current = false
	var rifle_player := PLAYER.instantiate() as Player3D
	rifle_player.position.x = 0.72
	stage.add_child(rifle_player)
	rifle_player.set_process(false)
	rifle_player.set_physics_process(false)
	rifle_player.avatar.set_process(false)
	rifle_player.get_node("Camera3D").current = false
	await get_tree().process_frame
	await get_tree().process_frame
	for player in [sidearm_player, rifle_player]:
		player.aim_direction = Vector3(0, 0, -1)
		player.aim_yaw = 0.0
		player.avatar.visual_root.rotation.y = 0.0
		player.get_node("AimCursor").visible = false
	if not rifle_player.equip_weapon("bp_rifle", "mod_bullet_standard"):
		push_error("Cannot equip rifle for Bunny v006 two-hand preview")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	for _index in range(3):
		sidearm_player.avatar.call("_process", 0.10)
		rifle_player.avatar.call("_process", 0.10)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.25, -5.6)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.72, -0.12), Vector3.UP)
	camera.fov = 28.0
	camera.current = true
	stage.add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	for node in get_tree().root.find_children("*", "Control", true, false):
		(node as Control).visible = false
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUTPUT) != OK:
		push_error("Cannot save Bunny v006 weapon grip preview")
		get_tree().quit(1)
		return
	# Close three-quarter proof for the menu/idle camera: face, right GripSocket hand,
	# and forward free left hand must remain readable in the same frame.
	rifle_player.visible = false
	sidearm_player.position.x = 0.0
	camera.position = Vector3(1.65, 1.55, -3.8)
	camera.look_at_from_position(camera.position, Vector3(0.05, 0.58, -0.24), Vector3.UP)
	camera.fov = 24.0
	await get_tree().process_frame
	var sidearm_closeup := get_viewport().get_texture().get_image()
	if sidearm_closeup == null or sidearm_closeup.is_empty() or sidearm_closeup.save_png(SIDEARM_CLOSEUP_OUTPUT) != OK:
		push_error("Cannot save Bunny sidearm idle close-up")
		get_tree().quit(1)
		return

	# Strict side-view rig proof. The yellow line is the rigid-node bone link;
	# green marks HandJointR/palm-sphere center and cyan marks the weapon GripSocket.
	# The two markers are concentric when the authored pivot contract is correct.
	var rig_overlay := Node3D.new()
	rig_overlay.name = "RightHandRigProof"
	stage.add_child(rig_overlay)
	var hand_joint_r := sidearm_player.avatar.get_node("VisualRoot/BunnyRig/HandRoot/HandJointR") as Node3D
	var hand_model_r := hand_joint_r.get_node("Model") as Node3D
	var body_joint := sidearm_player.avatar.get_node("VisualRoot/BunnyRig/BodyJoint") as Node3D
	var actual_grip_socket := sidearm_player.weapon.find_child("GripSocket", true, false) as Node3D
	var palm_center := hand_model_r.to_global(PlayerAvatar3D.RIGHT_HAND_SPHERE_CENTER_LOCAL)
	var hand_joint_position := hand_joint_r.global_position
	var grip_position := actual_grip_socket.global_position if actual_grip_socket != null else sidearm_player.avatar.weapon_socket.global_position
	_add_debug_bone(rig_overlay, body_joint.global_position + Vector3(0.0, 0.08, 0.0), hand_joint_position, Color("ffd447"), 0.010)
	_add_debug_sphere(rig_overlay, hand_joint_position, Color("78ff68"), 0.038)
	_add_debug_torus(rig_overlay, grip_position, Color("38ddff"), 0.052)
	var label := Label3D.new()
	label.text = "RIG PROOF: HandJointR = Palm Center = GripSocket\nOffset %.2f mm / %.2f mm" % [
		palm_center.distance_to(hand_joint_position) * 1000.0,
		palm_center.distance_to(grip_position) * 1000.0,
	]
	label.position = hand_joint_position + Vector3(0.0, 0.42, -0.20)
	label.font_size = 34
	label.outline_size = 6
	label.pixel_size = 0.00065
	label.modulate = Color.WHITE
	label.outline_modulate = Color("10212a")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	rig_overlay.add_child(label)
	camera.position = Vector3(2.55, 1.28, -0.18)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.56, -0.24), Vector3.UP)
	camera.fov = 24.0
	await get_tree().process_frame
	await get_tree().process_frame
	var rig_image := get_viewport().get_texture().get_image()
	if rig_image == null or rig_image.is_empty() or rig_image.save_png(RIGHT_HAND_RIG_OUTPUT) != OK:
		push_error("Cannot save Bunny right-hand bone/model rig proof")
		get_tree().quit(1)
		return
	rig_overlay.queue_free()
	await get_tree().process_frame

	# Shooting proof from the strict side: cyan is the visible MuzzleSocket -Z axis,
	# red is the real projectile aim_direction. The lines are separated vertically
	# by 18 mm only so both remain readable; their reported angular delta must be zero.
	sidearm_player.call("_on_weapon_shot_fired", 1)
	sidearm_player.call("_tick_action_overlays", 0.04)
	sidearm_player.avatar.call("_process", 0.04)
	sidearm_player.weapon.set("_recoil", 0.09)
	sidearm_player.weapon.call("_process", 0.001)
	var muzzle_overlay := Node3D.new()
	muzzle_overlay.name = "SidearmMuzzleAlignmentProof"
	stage.add_child(muzzle_overlay)
	var muzzle_socket := sidearm_player.weapon.find_child("MuzzleSocket", true, false) as Node3D
	var muzzle_forward := (-muzzle_socket.global_basis.z).normalized()
	var projectile_direction := sidearm_player.aim_direction.normalized()
	var proof_length := 1.55
	_add_debug_bone(
		muzzle_overlay,
		muzzle_socket.global_position,
		muzzle_socket.global_position + muzzle_forward * proof_length,
		Color("38ddff"),
		0.010
	)
	var projectile_line_origin := muzzle_socket.global_position + Vector3(0.0, 0.018, 0.0)
	_add_debug_bone(
		muzzle_overlay,
		projectile_line_origin,
		projectile_line_origin + projectile_direction * proof_length,
		Color("ff4b47"),
		0.007
	)
	var angle_label := Label3D.new()
	angle_label.text = "MUZZLE -Z / PROJECTILE AIM\nANGLE %.3f deg" % rad_to_deg(muzzle_forward.angle_to(projectile_direction))
	angle_label.position = muzzle_socket.global_position + Vector3(0.0, 0.33, -0.55)
	angle_label.font_size = 34
	angle_label.outline_size = 6
	angle_label.pixel_size = 0.00065
	angle_label.modulate = Color.WHITE
	angle_label.outline_modulate = Color("10212a")
	angle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	angle_label.no_depth_test = true
	muzzle_overlay.add_child(angle_label)
	camera.position = Vector3(2.55, 1.24, -0.52)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.54, -0.68), Vector3.UP)
	camera.fov = 27.0
	await get_tree().process_frame
	await get_tree().process_frame
	var muzzle_alignment_image := get_viewport().get_texture().get_image()
	if (
		muzzle_alignment_image == null
		or muzzle_alignment_image.is_empty()
		or muzzle_alignment_image.save_png(SIDEARM_MUZZLE_ALIGNMENT_OUTPUT) != OK
	):
		push_error("Cannot save Bunny sidearm muzzle/aim alignment proof")
		get_tree().quit(1)
		return
	muzzle_overlay.queue_free()
	sidearm_player.call("_clear_action_overlays")
	sidearm_player.weapon.set("_recoil", 0.0)
	sidearm_player.weapon.call("_process", 0.10)
	sidearm_player.avatar.call("_process", 0.10)
	await get_tree().process_frame
	sidearm_player.position.x = -0.72
	rifle_player.visible = true
	camera.fov = 28.0

	# Back-socket presentation: active primary leaves secondary on the avatar-right
	# socket; active secondary leaves primary on the avatar-left socket. Both gun
	# models use local -Z as muzzle-forward, rotated by the socket to world-down.
	var shotgun_item := WeaponInstance.ensure_weapon_item(
		ItemRegistry.get_instance().get_item("weapon_shotgun")
	)
	var charge_item := WeaponInstance.ensure_weapon_item(
		ItemRegistry.get_instance().get_item("weapon_charge")
	)
	if (
		not bool(sidearm_player.equip_weapon_item_to_slot(shotgun_item, 1).get("success", false))
		or not bool(rifle_player.equip_weapon_item_to_slot(charge_item, 1).get("success", false))
		or not bool(rifle_player.switch_weapon_slot(1).get("success", false))
	):
		push_error("Cannot prepare main/secondary back-socket preview")
		get_tree().quit(1)
		return
	var largest_backpack := ItemRegistry.get_instance().get_item("equipment_backpack_8")
	if (
		not bool(sidearm_player.equip_backpack_item(largest_backpack).get("success", false))
		or not bool(rifle_player.equip_backpack_item(largest_backpack).get("success", false))
	):
		push_error("Cannot prepare independent backpack/weapon socket clearance preview")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	camera.position = Vector3(0.0, 2.25, 5.6)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.72, 0.12), Vector3.UP)
	await get_tree().process_frame
	var back_image := get_viewport().get_texture().get_image()
	if back_image == null or back_image.is_empty() or back_image.save_png(BACK_SOCKETS_OUTPUT) != OK:
		push_error("Cannot save Bunny main/secondary back-socket preview")
		get_tree().quit(1)
		return
	camera.position = Vector3(0.0, 5.8, 1.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.70, 0.12), Vector3(0.0, 0.0, -1.0))
	await get_tree().process_frame
	var top_image := get_viewport().get_texture().get_image()
	if top_image == null or top_image.is_empty() or top_image.save_png(BACK_SOCKETS_TOP_OUTPUT) != OK:
		push_error("Cannot save Bunny top-down back-socket preview")
		get_tree().quit(1)
		return

	# Art-only comparison: show both independent weapon sockets on one character
	# with no backpack. Runtime still keeps one weapon active and one stowed.
	sidearm_player.unequip_backpack_item()
	sidearm_player.position.x = 0.0
	rifle_player.visible = false
	if sidearm_player.weapon != null:
		sidearm_player.weapon.visible = false
	var primary_preview := WEAPON_MODEL.instantiate() as WeaponModel3D
	var primary_item := WeaponInstance.ensure_weapon_item(
		ItemRegistry.get_instance().get_item("weapon_rifle")
	)
	primary_preview.name = "DualBackPrimaryPreview"
	primary_preview.display_only = true
	primary_preview.render_layers = 2
	primary_preview.set_meta("weapon_item_data", primary_item)
	sidearm_player.avatar.get_stowed_weapon_socket(0).add_child(primary_preview)
	primary_preview.position = Vector3.ZERO
	primary_preview.rotation = Vector3.ZERO
	primary_preview.scale = Vector3.ONE * 0.52
	await get_tree().process_frame
	await get_tree().process_frame
	camera.position = Vector3(0.0, 2.25, 5.6)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.72, 0.12), Vector3.UP)
	await get_tree().process_frame
	var dual_back_image := get_viewport().get_texture().get_image()
	if dual_back_image == null or dual_back_image.is_empty() or dual_back_image.save_png(DUAL_NO_BACKPACK_OUTPUT) != OK:
		push_error("Cannot save Bunny dual back-weapons preview without backpack")
		get_tree().quit(1)
		return
	camera.position = Vector3(0.0, 5.8, 1.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.70, 0.12), Vector3(0.0, 0.0, -1.0))
	await get_tree().process_frame
	var dual_top_image := get_viewport().get_texture().get_image()
	if dual_top_image == null or dual_top_image.is_empty() or dual_top_image.save_png(DUAL_NO_BACKPACK_TOP_OUTPUT) != OK:
		push_error("Cannot save Bunny top-down dual back-weapons preview without backpack")
		get_tree().quit(1)
		return
	print("BUNNY_V006_WEAPON_GRIP_VISUAL_OK: held grip, muzzle/aim alignment, right-hand rig proof, sidearm idle close-up, backpack clearance, and no-backpack dual vertical sockets saved")
	get_tree().quit(0)


func _debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _add_debug_sphere(parent: Node3D, position: Vector3, color: Color, radius: float) -> void:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.material = _debug_material(color)
	marker.mesh = sphere
	marker.position = position
	parent.add_child(marker)


func _add_debug_torus(parent: Node3D, position: Vector3, color: Color, outer_radius: float) -> void:
	var marker := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = outer_radius * 0.76
	torus.outer_radius = outer_radius
	torus.material = _debug_material(color)
	marker.mesh = torus
	marker.position = position
	marker.rotation_degrees.z = 90.0
	parent.add_child(marker)


func _add_debug_bone(parent: Node3D, from: Vector3, to: Vector3, color: Color, radius: float) -> void:
	var direction := to - from
	if direction.length_squared() <= 0.000001:
		return
	var bone := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = direction.length()
	cylinder.material = _debug_material(color)
	bone.mesh = cylinder
	bone.position = (from + to) * 0.5
	var y_axis := direction.normalized()
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() <= 0.000001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	bone.basis = Basis(x_axis, y_axis, z_axis)
	parent.add_child(bone)
