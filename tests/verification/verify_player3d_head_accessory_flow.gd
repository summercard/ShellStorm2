extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const Persistence = preload("res://src/player3d/customization/AvatarCustomizationPersistence.gd")
const VARIANT_ID := "chibi_anime"
const TEST_SAVE_PATH := "user://player3d_head_accessory_persistence_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_save_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	var original_force_failure: bool = BaseManager.force_save_failure_for_test
	_prepare_test_profile()
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	player.camera.current = false
	await get_tree().process_frame

	var head_options := player.get_avatar_customization_options().get("head", []) as Array
	_check(VARIANT_ID in head_options, "衣柜没有注册二次元头部选项", failures)
	var avatar := player.avatar
	var head_joint := avatar.get_node("VisualRoot/BunnyRig/HeadJoint") as Node3D
	var base_head := head_joint.get_node("Model") as Node3D
	var bunny_ears := head_joint.get_node("Wearables/HatBunnyEars") as Node3D
	var accessory := head_joint.get_node("HeadAccessoryChibiAnime") as Node3D
	_check(accessory.position.is_zero_approx(), "二次元头部没有落在HeadJoint原点", failures)
	_check(accessory.rotation.is_zero_approx(), "二次元头部运行时存在隐藏旋转补偿", failures)
	_check(accessory.scale.is_equal_approx(Vector3.ONE), "二次元头部包装根缩放不是1", failures)
	_check(accessory.get_parent() == head_joint, "二次元头部没有直接挂在HeadJoint", failures)
	_check(str(accessory.get_meta("godot_forward", "")) == "-Z", "二次元头部正面契约不是Godot -Z", failures)
	_check(
		str(accessory.get_meta("source_collection", ""))
		== "头部配件/二次元头部配件_中文管理/01_制作组件_可编辑",
		"二次元头部没有记录正式角色Blend中的制作集合",
		failures
	)

	player.set_avatar_customization("hat", "hard_hat")
	player.set_avatar_customization("glasses", "dual_goggles")
	_check(player.set_avatar_customization("head", VARIANT_ID), "二次元头部无法通过正式换装API启用", failures)
	await get_tree().process_frame
	_check(accessory.visible, "选择二次元头部后新模型不可见", failures)
	_check(not base_head.visible, "选择二次元头部后原Bunny头仍可见", failures)
	_check(not bunny_ears.visible, "选择二次元头部后原Bunny耳朵仍可见", failures)
	_check(
		not (head_joint.get_node("Wearables/HatHardHat") as Node3D).visible,
		"二次元头部启用时旧帽子仍与模型穿插",
		failures
	)
	_check(
		not (head_joint.get_node("Wearables/GlassesDualGoggles") as Node3D).visible,
		"二次元头部启用时旧眼镜仍与模型穿插",
		failures
	)
	_check(player.set_avatar_customization("hat", "bunny_ears"), "兔耳帽无法在二次元头部下启用", failures)
	await get_tree().process_frame
	_check(
		(head_joint.get_node("Wearables/HatBunnyEars") as Node3D).visible,
		"二次元头部启用时独立兔耳帽被错误隐藏",
		failures
	)
	_check(player.set_avatar_customization("hat", "hard_hat"), "无法恢复工程安全帽测试状态", failures)

	var meshes := accessory.find_children("*", "MeshInstance3D", true, false)
	_check(not meshes.is_empty(), "二次元头部场景没有实际Mesh", failures)
	_check(accessory.find_children("*", "CollisionObject3D", true, false).is_empty(), "头部配件错误携带玩法碰撞", failures)
	_check(accessory.find_children("*", "CollisionShape3D", true, false).is_empty(), "头部配件错误携带碰撞形状", failures)
	var actual_min := Vector3(INF, INF, INF)
	var actual_max := Vector3(-INF, -INF, -INF)
	var has_base_color_texture := false
	for value in meshes:
		var mesh_instance := value as MeshInstance3D
		var bounds := mesh_instance.get_aabb()
		for x in [bounds.position.x, bounds.end.x]:
			for y in [bounds.position.y, bounds.end.y]:
				for z in [bounds.position.z, bounds.end.z]:
					var head_local_point := head_joint.to_local(
						mesh_instance.to_global(Vector3(x, y, z))
					)
					actual_min = actual_min.min(head_local_point)
					actual_max = actual_max.max(head_local_point)
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				has_base_color_texture = true
	_check(has_base_color_texture, "二次元头部BaseColor贴图没有进入Godot材质", failures)
	var expected_min := accessory.get_meta("authored_bounds_min_m", Vector3.ZERO) as Vector3
	var expected_max := accessory.get_meta("authored_bounds_max_m", Vector3.ZERO) as Vector3
	_check(
		actual_min.is_equal_approx(expected_min),
		"二次元头部局部包围盒下界与正式Blend输出不一致：actual=%s expected=%s"
		% [actual_min, expected_min],
		failures
	)
	_check(
		actual_max.is_equal_approx(expected_max),
		"二次元头部局部包围盒上界与正式Blend输出不一致：actual=%s expected=%s"
		% [actual_max, expected_max],
		failures
	)
	_verify_restart_persistence(player, failures)

	_check(player.set_avatar_customization("head", "plated_amber"), "无法从二次元头部切回原头部", failures)
	await get_tree().process_frame
	_check(not accessory.visible, "切回原头部后二次元模型仍可见", failures)
	_check(base_head.visible, "切回原头部后Bunny头没有恢复", failures)
	_check((head_joint.get_node("Wearables/HatHardHat") as Node3D).visible, "切回原头部后原帽子选择没有恢复", failures)
	_check((head_joint.get_node("Wearables/GlassesDualGoggles") as Node3D).visible, "切回原头部后原眼镜选择没有恢复", failures)

	player.queue_free()
	await get_tree().process_frame
	_restore_profile_state(original_save_path, original_data, original_force_failure)
	if failures.is_empty():
		print("PLAYER3D_HEAD_ACCESSORY_FLOW_OK: Blender anchor, textured GLB, wardrobe model swap and restart persistence pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _prepare_test_profile() -> void:
	_cleanup_test_profile()
	BaseManager.save_path = TEST_SAVE_PATH
	BaseManager.force_save_failure_for_test = false
	BaseManager.data = BaseData.new()


func _verify_restart_persistence(player: Player3D, failures: Array[String]) -> void:
	_check(Persistence.persist_from_player(player), "二次元头部选择没有写入基地档案", failures)
	BaseManager.data = BaseData.new()
	BaseManager.load_base()
	_check(
		str(BaseManager.data.avatar_customization.get("head", "")) == VARIANT_ID,
		"模拟重启后基地档案没有保留二次元头部",
		failures
	)
	var restored_player := PLAYER_SCENE.instantiate() as Player3D
	add_child(restored_player)
	restored_player.set_physics_process(false)
	restored_player.camera.current = false
	Persistence.apply_saved_to_player(restored_player)
	_check(
		str(restored_player.get_avatar_customization().get("head", "")) == VARIANT_ID,
		"模拟重启后新角色没有应用已保存的二次元头部",
		failures
	)
	var restored_accessory := restored_player.avatar.get_node(
		"VisualRoot/BunnyRig/HeadJoint/HeadAccessoryChibiAnime"
	) as Node3D
	_check(restored_accessory.visible, "模拟重启后二次元头部模型不可见", failures)
	restored_player.free()


func _restore_profile_state(
	original_save_path: String,
	original_data: BaseData,
	original_force_failure: bool
) -> void:
	BaseManager.save_path = original_save_path
	BaseManager.data = original_data
	BaseManager.force_save_failure_for_test = original_force_failure
	_cleanup_test_profile()


func _cleanup_test_profile() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = TEST_SAVE_PATH + str(suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
