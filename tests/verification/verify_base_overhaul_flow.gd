extends Node
## 5米基地结构、物理楼层权威、时间/能源、换装与脱困的组合回归。

const TimeDomain = preload("res://src/core/WorldTimeDomain.gd")
const EnergyService = preload("res://src/base/BaseEnergyService.gd")
const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")
const AvatarCatalog = preload("res://src/player3d/customization/AvatarCustomizationCatalog.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	_verify_time_energy_and_persistence(failures)
	await _verify_structural_prefabs(failures)
	await _verify_tower_location_and_ui(failures)
	_finish(failures)


func _verify_time_energy_and_persistence(failures: Array[String]) -> void:
	var start := TimeDomain.get_snapshot(0.0)
	_expect(str(start.get("display_text", "")) == "2075-01-01  17:00", "世界时间起点错误", failures)
	var next_day := TimeDomain.get_snapshot(TimeDomain.elapsed_from_real_seconds(1200.0))
	_expect(str(next_day.get("display_text", "")) == "2075-01-02  17:00", "20现实分钟没有推进一个游戏日", failures)
	var noon := TimeDomain.get_solar_snapshot(12.0)
	_expect(is_equal_approx(float(noon.get("energy", 0.0)), 1.0), "太阳峰值亮度不是1", failures)

	var data := BaseData.new()
	data.base_energy_current = 50.0
	data.base_energy_last_synced_game_seconds = 0.0
	var restored := EnergyService.sync_to_game_time(data, 3600.0)
	_expect(is_equal_approx(restored, 4.0) and is_equal_approx(data.base_energy_current, 54.0), "基地能源未按游戏小时恢复", failures)
	data.avatar_customization = {"body": "suit_cobalt", "hat": "hard_hat"}
	var round_trip := BaseData.from_dict(data._to_dict())
	_expect(str(round_trip.avatar_customization.get("body", "")) == "suit_cobalt", "换装没有进入BaseData存档", failures)
	_expect(FacilityCatalog.has_facility("base_recovery") and FacilityCatalog.has_facility("avatar_wardrobe"), "恢复舱或衣柜未进入设施目录", failures)
	_expect(AvatarCatalog.validate_catalog().is_empty(), "换装分类没有做到每类至少3款", failures)


func _verify_structural_prefabs(failures: Array[String]) -> void:
	var specs := [
		["res://assets/art/environments/base_facility_3d/runtime/env_base99_mezzanine_20x10_z5/env_base99_mezzanine_20x10_z5_root_top3d_v002.tscn", "ENV-BASE99-MEZZANINE-20X10-Z5", 5.0, 3],
		["res://assets/art/environments/base_facility_3d/runtime/env_base99_stair_l_z5/env_base99_stair_l_z5_root_top3d_v002.tscn", "ENV-BASE99-STAIR-L-Z5", 5.0, 6],
		["res://assets/art/environments/base_facility_3d/runtime/env_base99_stair_exterior_h4/env_base99_stair_exterior_h4_root_top3d_v002.tscn", "ENV-BASE99-STAIR-EXTERIOR-H4", 4.0, 2],
	]
	for spec in specs:
		var packed := load(str(spec[0])) as PackedScene
		var module := packed.instantiate() as Node3D
		add_child(module)
		await get_tree().process_frame
		_expect(str(module.get_meta("asset_id", "")) == str(spec[1]), "结构资产ID错误：%s" % spec[1], failures)
		_expect(is_equal_approx(float(module.get("target_walkable_height_m")), float(spec[2])), "结构目标高度错误：%s" % spec[1], failures)
		var guard_count := 0
		var walkable_count := 0
		for body in module.find_children("*", "StaticBody3D", true, false):
			if bool(body.get_meta("base99_guard_collision", false)):
				guard_count += 1
			if bool(body.get_meta("base99_walkable_collision", false)):
				walkable_count += 1
		_expect(guard_count >= int(spec[3]), "栏杆连续阻挡不足：%s" % spec[1], failures)
		_expect(walkable_count >= 1, "缺少简化连续行走面：%s" % spec[1], failures)
		if str(spec[1]) == "ENV-BASE99-STAIR-EXTERIOR-H4":
			var ramp_shape := module.get_node_or_null("WalkableCollision/ExteriorStairRamp/ExteriorStairRampShape") as CollisionShape3D
			var ramp_box := ramp_shape.shape as BoxShape3D if ramp_shape != null else null
			_expect(ramp_box != null and ramp_box.size.z > 9.0, "H4外梯碰撞没有覆盖8.515米完整视觉包络", failures)
		module.queue_free()
		await get_tree().process_frame


func _verify_tower_location_and_ui(failures: Array[String]) -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 20750101
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_expect(tower.get_facility_count() == 10, "99层美术布局不是10个设施", failures)
	var full_scale_facilities := [
		"mission_operations", "weapon_workshop", "vault", "fate_collection", "base_vending",
	]
	var found_full_scale: Array[String] = []
	for facility_value in tower.get("_facility_nodes") as Array:
		var base_facility := facility_value as BaseFacility3D
		if base_facility == null or base_facility.facility_id not in full_scale_facilities:
			continue
		found_full_scale.append(base_facility.facility_id)
		var size_contract := base_facility.get_size_contract_snapshot()
		_expect(is_equal_approx(base_facility.base_size_multiplier, 1.0), "%s仍叠加旧0.7设施倍率" % base_facility.facility_id, failures)
		_expect((size_contract.get("root_scale", Vector3.ZERO) as Vector3).is_equal_approx(Vector3.ONE), "%s美术根缩放没有恢复为1" % base_facility.facility_id, failures)
	_expect(found_full_scale.size() == full_scale_facilities.size(), "五件正式设施没有全部进入1倍尺寸验收", failures)
	_expect(tower.get_node_or_null("HUD/ReferenceCombatHUD/WorldDateTimeHUD") != null, "雷达下方缺少日期时间HUD", failures)
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间缺失", failures)
	if facility != null:
		tower.player.global_position = facility.global_position + Vector3(0.0, 5.05, 0.0)
		tower.call("_refresh_physical_location_authority", true)
		var upper := tower.get_physical_location_snapshot()
		_expect(int(upper.get("floor_number", 0)) == 100, "基地阁楼没有按物理高度判定为100层", failures)
		_expect(bool(upper.get("inside_base_safe_volume", false)) and not bool(upper.get("on_facility_ground_level", true)), "上层基地安全区或设施隔层规则错误", failures)
		_expect(tower.can_return_player_to_base_center(), "基地上层脱困按钮不可用", failures)
		var returned := tower.return_player_to_base_center_from_pause()
		_expect(bool(returned.get("success", false)), "基地脱困没有回到默认出生点", failures)
		var lower := tower.get_physical_location_snapshot()
		_expect(int(lower.get("floor_number", 0)) == 99 and str(lower.get("room_id", "")) == "facility", "落回基地后楼层/房间没有同步为99层", failures)

	var entry_scene := load("res://scenes/ui/MainEntryScreen3D.tscn") as PackedScene
	var entry := entry_scene.instantiate() as MainEntryScreen3D
	entry.auto_present_when_player_found = false
	tower.add_child(entry)
	await get_tree().process_frame
	_expect(entry.present(tower.player), "主页面没有使用实时角色与玩法摄像机", failures)
	var entry_snapshot := entry.get_entry_snapshot()
	_expect(bool(entry_snapshot.get("seamless_scene_change", false)) and bool(entry_snapshot.get("uses_live_player", false)), "主页面不是无缝实时角色方案", failures)
	entry.skip_to_gameplay()
	entry.queue_free()

	var wardrobe_scene := load("res://scenes/ui/WardrobeMenu3D.tscn") as PackedScene
	var wardrobe := wardrobe_scene.instantiate() as WardrobeMenu3D
	wardrobe.set_player(tower.player)
	tower.add_child(wardrobe)
	await get_tree().process_frame
	var wardrobe_snapshot := wardrobe.get_wardrobe_snapshot()
	_expect(bool(wardrobe_snapshot.get("square_item_cells", false)), "衣柜物品框不是方形契约", failures)
	_expect((wardrobe_snapshot.get("slot_order", []) as Array).size() == 6, "衣柜不是6个部件分类", failures)
	wardrobe.request_close()
	tower.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BASE_OVERHAUL_FLOW_OK: height5 structures, guards, physical floors, time, energy, recovery, wardrobe, seamless entry and unstuck contracts pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("BASE_OVERHAUL_FLOW_FAIL: %s" % failure)
	get_tree().quit(1)
