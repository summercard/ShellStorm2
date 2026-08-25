extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const WARDROBE_SCENE: PackedScene = preload("res://scenes/ui/WardrobeMenu3D.tscn")
const TEST_SAVE_PATH := "user://wardrobe_preview_fill_probe.json"


func _ready() -> void:
	var failures: Array[String] = []
	var original_save_path: String = BaseManager.save_path
	var original_data: BaseData = BaseManager.data
	var original_force_failure: bool = BaseManager.force_save_failure_for_test
	_prepare_test_profile()

	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	var gameplay_hud := CanvasLayer.new()
	gameplay_hud.name = "HUD"
	add_child(gameplay_hud)
	player.set_physics_process(false)
	player.camera.current = false
	var original_player_position := player.global_position
	var wardrobe := WARDROBE_SCENE.instantiate() as WardrobeMenu3D
	wardrobe.set_player(player)
	add_child(wardrobe)
	await get_tree().process_frame

	var snapshot := wardrobe.get_wardrobe_snapshot()
	_check(not gameplay_hud.visible, "衣柜开启时主HUD没有隐藏", failures)
	_check(bool(snapshot.get("gameplay_hud_hidden", false)), "衣柜快照没有记录主HUD隐藏状态", failures)
	_check(bool(snapshot.get("category_buttons_on_left", false)), "衣柜分类按钮没有整合到左栏", failures)
	_check(not bool(snapshot.get("duplicate_right_categories", true)), "衣柜右栏仍有重复分类按钮", failures)
	_check(bool(snapshot.get("uses_3d_variant_icons", false)), "衣柜配件没有使用背包同源3D预览", failures)
	_check(float(snapshot.get("right_panel_width", 999.0)) <= 400.0, "衣柜右栏仍然过宽", failures)
	_check(player.global_position.is_equal_approx(original_player_position), "打开衣柜时角色世界坐标被移动", failures)
	_check(player.camera.top_level, "衣柜展示相机没有脱离角色局部变换", failures)
	var horizontal_camera_direction := player.camera.global_position - player.global_position
	horizontal_camera_direction.y = 0.0
	horizontal_camera_direction = horizontal_camera_direction.normalized()
	_check(
		player.avatar.visual_root.global_basis.z.normalized().dot(horizontal_camera_direction) < -0.98,
		"衣柜预览角色没有固定面对镜头 dot=%.3f front=%s camera=%s" % [
			player.avatar.visual_root.global_basis.z.normalized().dot(horizontal_camera_direction),
			str((-player.avatar.visual_root.global_basis.z).normalized()),
			str(horizontal_camera_direction),
		],
		failures
	)
	_check(bool(snapshot.get("preview_fill_active", false)), "衣柜开启时没有创建专属补光", failures)
	_check(bool(snapshot.get("preview_fill_visible", false)), "衣柜专属补光不可见", failures)
	_check(float(snapshot.get("preview_fill_energy", 0.0)) >= 6.5, "衣柜专属补光强度不足", failures)
	_check(
		float(snapshot.get("preview_fill_distance_to_target", INF)) <= 3.0,
		"衣柜专属补光离角色过远",
		failures
	)
	_check(
		float(snapshot.get("preview_fill_aim_alignment", 0.0)) >= 0.999,
		"衣柜专属补光没有对准角色",
		failures
	)
	_check(bool(snapshot.get("preview_fill_player_only", false)), "衣柜补光没有隔离到角色渲染层", failures)
	_check(not bool(snapshot.get("preview_fill_shadow_enabled", true)), "衣柜补光不应产生阴影", failures)
	_check(bool(snapshot.get("preview_face_fill_active", false)), "衣柜没有创建独立面部补光", failures)
	_check(bool(snapshot.get("preview_face_fill_visible", false)), "衣柜面部补光不可见", failures)
	_check(float(snapshot.get("preview_face_fill_energy", 0.0)) >= 1.5, "衣柜面部补光强度不足", failures)
	_check(bool(snapshot.get("preview_face_fill_player_only", false)), "衣柜面部补光没有隔离到角色层", failures)
	_check(bool(snapshot.get("presentation_facing_south", false)), "衣柜角色没有固定面向南方", failures)
	_check(bool(snapshot.get("camera_on_south_side", false)), "衣柜摄像机没有固定在角色南侧", failures)

	wardrobe.request_close()
	_check(gameplay_hud.visible, "关闭衣柜后主HUD没有恢复", failures)
	_check(
		not bool(wardrobe.get_wardrobe_snapshot().get("preview_fill_active", true)),
		"关闭衣柜后专属补光没有立即移除",
		failures
	)
	_check(
		not bool(wardrobe.get_wardrobe_snapshot().get("preview_face_fill_active", true)),
		"关闭衣柜后面部补光没有立即移除",
		failures
	)
	player.queue_free()
	gameplay_hud.queue_free()
	await get_tree().process_frame
	_restore_profile_state(original_save_path, original_data, original_force_failure)

	if failures.is_empty():
		print("WARDROBE_PREVIEW_FILL_FLOW_OK: dedicated player-only fill is active only during wardrobe preview")
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
