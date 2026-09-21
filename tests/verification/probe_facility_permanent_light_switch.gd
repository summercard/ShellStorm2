extends Node
## 探针：99F基地顶灯与墙面开关的「壳体级常驻」实测（业主 2026-09-21 指定）。
##
## 背景：FACILITY 的 FacilityCeilingLight_Main 与 RoomLightSwitch3D 原先挂在
## RuntimeDetail 下，随进出房间销毁重建（出现流程）。现改为随壳体一次性
## 建好、DATA_ONLY 卸载细节时不回收。本探针验证三件事：
##   A) 顶灯与开关是房间根的直接子节点，不在 RuntimeDetail 下（反向对照：
##      普通房型的开关必须仍在 RuntimeDetail 下）；
##   B) DATA_ONLY 卸载细节后，灯与开关实例不销毁、仍可交互；
##   C) 重新 ACTIVE 重建细节后，开关实例不变、灯状态连续。
##
## 运行：
##   godot --headless --path . res://tests/verification/probe_facility_permanent_light_switch.tscn

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const STREAM_DATA_ONLY := 0
const STREAM_ACTIVE := 2
const GRID_UNIT_M := 5.0
const BASE_TRANSIT_CENTER := Vector2(-7.5, 2.2)  # 东墙天台通行口：沿墙中心 / 净宽


func _switch_on_side(
	switches: Array[RoomLightSwitch3D], side: String
) -> RoomLightSwitch3D:
	var marker := "%s_entry_" % side
	for light_switch in switches:
		if str(light_switch.get_meta("facility_entry_direction", "")).begins_with(marker):
			return light_switch
	return null


## 该侧门洞中心沿墙坐标（房间局部 z）。优先用墙体拼装写入的 meta，
## 与 _place_facility_light_switch 读取的是同一口径。
func _door_along(facility: DungeonRoom3D, side: String) -> float:
	var key := "tower_wall_door_offset_%s" % side
	if facility.has_meta(key):
		return float(facility.get_meta(key))
	var door := facility.get_door_node(side)
	return door.position.z if door != null else -GRID_UNIT_M * 0.5

var _failures: Array[String] = []


func _ready() -> void:
	var tower := (load(TOWER_SCENE) as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	tower.force_enter_room_for_test("facility")
	var facility := (tower.get("_room_by_id") as Dictionary)["facility"] as DungeonRoom3D
	_check(facility != null, "样本哨兵：facility 房间存在")
	if facility == null:
		_finish()
		return
	facility.ensure_shell_built()
	facility.ensure_detail_built()
	await _settle()

	var switch_node := facility.find_child("RoomLightSwitch3D", true, false) as RoomLightSwitch3D
	var main_light := facility.find_child("FacilityCeilingLight_Main", true, false) as WastelandLight3D
	_check(switch_node != null, "样本哨兵：基地开关存在")
	_check(main_light != null, "样本哨兵：基地中央顶灯存在")
	if switch_node == null or main_light == null:
		_finish()
		return
	_check(switch_node.get_parent() == facility, "开关直挂房间根（不在 RuntimeDetail 下）")
	_check(main_light.get_parent() == facility, "顶灯直挂房间根（不在 RuntimeDetail 下）")
	_check(switch_node.is_light_on(), "进场初始灯亮（starts_on）")

	# 几何诊断：东西墙门洞与开关落位（业主 2026-09-21 要求东墙复制一个开关）
	var dims := facility.get_dimensions()
	print("  GEO dims=%s" % str(dims))
	for side in ["west", "east"]:
		var door := facility.get_door_node(side)
		var meta_key := "tower_wall_door_offset_%s" % side
		print(
			"  GEO door[%s] local=%s offset_meta=%s"
			% [
				side,
				str(door.position) if door != null else "<无门>",
				str(facility.get_meta(meta_key, "<无 meta>")),
			]
		)
	print("  GEO transit east opening center=%s" % str(BASE_TRANSIT_CENTER))
	var switches: Array[RoomLightSwitch3D] = []
	for value in facility.find_children("RoomLightSwitch3D*", "RoomLightSwitch3D", true, false):
		var sw := value as RoomLightSwitch3D
		switches.append(sw)
		print(
			"  GEO switch %s local=%s rot_y=%.4f dir=%s"
			% [
				sw.name, str(sw.position), sw.rotation.y,
				str(sw.get_meta("facility_entry_direction", "<无>")),
			]
		)
	_check(switches.size() == 2, "基地开关成对：数量=%d 期望=2" % switches.size())

	# 业主口径：两个开关离各自门洞的距离必须相同（门洞边缘 5/3 m、门洞中心 4.167 m）
	var expected_third := GRID_UNIT_M / 3.0
	var expected_half := GRID_UNIT_M * 0.5
	var west_switch := _switch_on_side(switches, "west")
	var east_switch := _switch_on_side(switches, "east")
	_check(west_switch != null and east_switch != null, "东西墙各有一个开关")
	if west_switch != null and east_switch != null:
		var west_door_z := _door_along(facility, "west")
		var east_door_z := _door_along(facility, "east")
		# 西墙在门洞北侧，东墙在门洞南侧 ⇒ 都是「离门洞边缘 +5/3 m」
		var west_edge_gap := (west_door_z - expected_half) - west_switch.position.z
		var east_edge_gap := east_switch.position.z - (east_door_z + expected_half)
		print(
			"  GEO 西墙开关离门洞边缘=%.4f 东墙开关离门洞边缘=%.4f 期望=%.4f"
			% [west_edge_gap, east_edge_gap, expected_third]
		)
		_check(
			absf(west_edge_gap - expected_third) < 0.001
			and absf(east_edge_gap - expected_third) < 0.001,
			"两开关离门洞边缘距离相同且=5/3m"
		)
		_check(
			west_switch.position.z < 0.0 and east_switch.position.z > 0.0,
			"西墙开关在门洞北侧、东墙开关在门洞南侧"
		)
		_check(
			absf(west_switch.position.x + east_switch.position.x) < 0.001
			and absf(
				(west_switch.position.z - west_door_z)
				+ (east_switch.position.z - east_door_z)
			) < 0.001,
			"两开关关于门洞中心线镜像（x 互为相反数、沿墙偏移互为相反数）"
		)
		_check(
			west_switch.get_meta("facility_entry_direction", "")
			!= east_switch.get_meta("facility_entry_direction", ""),
			"两开关的来源标记可区分（非同一落位复制）"
		)
		_check(
			int(east_switch.get_snapshot().linked_switch_count) == 1
			and int(west_switch.get_snapshot().linked_switch_count) == 1,
			"两开关互为并联（linked_switch_count 各为1）"
		)

		# 端到端可达性：新开关如果埋进设施或墙里，玩家站过去必然拿不到交互候选。
		# 这也顺带证明东墙 z=+5/3 段没有被美术设施占掉。
		var paired: Array[RoomLightSwitch3D] = [west_switch, east_switch]
		for probe_switch in paired:
			var inward: Vector3 = -probe_switch.global_transform.basis.z  # 面板正面朝房间内
			# 先退到交互范围外再走进去：Area3D 只在状态变化时发 body_entered，
			# 直接瞬移到范围内（玩家原本就在别处）也可能因时序拿不到候选。
			tower.player.global_position = probe_switch.global_position + inward * 6.0
			await _wait_physics(3)
			tower.player.global_position = (
				probe_switch.global_position + inward * 1.1 + Vector3(0.0, 0.05, 0.0)
			)
			await _wait_physics(4)
			var candidate: Dictionary = probe_switch.get_interaction_candidate(tower.player)
			_check(
				bool(candidate.get("available", false)),
				"%s 玩家靠近时提供交互候选（未被设施/墙体阻挡）" % probe_switch.name
			)
			_check(
				str(candidate.get("prompt", "")).contains("中央灯"),
				"%s 提示指向同一盏中央灯" % probe_switch.name
			)

	# 反向对照：普通房型（STAIR_LOBBY）开关仍应挂在 RuntimeDetail（出现流程）下
	var lobby := _find_first_room_by_type(tower, "STAIR_LOBBY")
	_check(lobby != null, "反向对照样本存在（STAIR_LOBBY）")
	if lobby != null:
		lobby.ensure_shell_built()
		lobby.ensure_detail_built()
		await _settle()
		var lobby_switch := lobby.find_child("RoomLightSwitch3D", true, false) as RoomLightSwitch3D
		_check(
			lobby_switch != null
			and lobby_switch.get_parent() != null
			and lobby_switch.get_parent() != lobby,
			"反向对照：普通房型开关仍在 RuntimeDetail 下"
		)

	var switch_instance_id := switch_node.get_instance_id()
	var light_instance_id := main_light.get_instance_id()
	var east_instance_id := east_switch.get_instance_id() if east_switch != null else 0

	# B) 开关灭灯 → 卸载细节（DATA_ONLY）→ 常驻节点必须存活且可用
	switch_node.set_light_on(false)
	_check(not switch_node.is_light_on(), "手动关灯生效")
	facility.set_stream_state(STREAM_DATA_ONLY)
	await _settle()
	_check(
		is_instance_valid(switch_node) and switch_node.get_parent() == facility,
		"DATA_ONLY 后开关实例存活且仍是房间根子节点"
	)
	_check(
		is_instance_valid(main_light) and main_light.get_parent() == facility,
		"DATA_ONLY 后顶灯实例存活且仍是房间根子节点"
	)
	if east_switch != null:
		_check(
			is_instance_valid(east_switch) and east_switch.get_parent() == facility,
			"DATA_ONLY 后东墙开关实例同样存活（成对常驻）"
		)
	switch_node.set_light_on(true)
	_check(switch_node.is_light_on(), "DATA_ONLY 期间开关仍可控制灯")

	# C) 重新激活 → 细节重建，常驻实例不变、状态连续
	facility.set_stream_state(STREAM_ACTIVE)
	await _settle()
	_check(
		switch_node.get_instance_id() == switch_instance_id,
		"重建细节后开关实例不变（未走出现流程重建）"
	)
	if east_switch != null and east_instance_id != 0:
		_check(
			east_switch.get_instance_id() == east_instance_id,
			"重建细节后东墙开关实例不变"
		)
	_check(
		main_light.get_instance_id() == light_instance_id,
		"重建细节后顶灯实例不变"
	)
	_check(switch_node.is_light_on(), "重建细节后灯状态连续（保持开）")

	# D) 并联互锁：一端播启动序列时，另一端必须拒绝切换且提示文字跟随
	if east_switch != null:
		switch_node.set_light_on(false)
		east_switch.set_light_on(false)
		await _settle()
		switch_node.toggle_light()
		_check(bool(switch_node.get_snapshot().transitioning), "西墙开关进入启动序列")
		_check(
			not bool(east_switch.get_snapshot().transitioning),
			"东墙开关自身未发起序列（transitioning 仍为假）"
		)
		var east_prompt := east_switch.find_child(
			"InteractLabel", true, false
		) as Label3D
		_check(
			east_prompt != null and east_prompt.text == "灯光启动中…",
			"东墙开关提示跟随对端显示「灯光启动中…」"
		)
		var before_on := east_switch.is_light_on()
		var accepted := east_switch.toggle_light()
		_check(not accepted, "并联互锁：序列期间东墙开关拒绝切换")
		_check(
			east_switch.is_light_on() == before_on,
			"被拒的切换没有改变灯状态"
		)
		await get_tree().create_timer(5.4).timeout
		_check(
			not bool(switch_node.get_snapshot().transitioning)
			and not bool(east_switch.get_snapshot().transitioning),
			"启动序列收尾后两开关均归位"
		)
		_check(
			switch_node.is_light_on() and east_switch.is_light_on(),
			"序列结束后两开关读到同一盏灯的一致状态"
		)
	_finish()


func _find_first_room_by_type(tower: TowerDescent3D, type_id: String) -> DungeonRoom3D:
	var room_by_id: Dictionary = tower.get("_room_by_id")
	for key in room_by_id:
		var room := room_by_id[key] as DungeonRoom3D
		if room != null and room.room_type == type_id:
			return room
	return null


func _settle() -> void:
	for frame in range(3):
		await get_tree().process_frame


func _wait_physics(frame_count: int) -> void:
	for _frame in range(frame_count):
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  PROBE_OK   %s" % label)
	else:
		printerr("  PROBE_FAIL %s" % label)
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("PROBE_FACILITY_PERMANENT_LIGHT_SWITCH_OK")
		get_tree().quit(0)
	else:
		printerr(
			"PROBE_FACILITY_PERMANENT_LIGHT_SWITCH_FAILED 失败项=%d" % _failures.size()
		)
		get_tree().quit(1)
