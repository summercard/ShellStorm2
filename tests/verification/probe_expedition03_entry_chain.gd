extends Node
## 端到端：从「选关」一路真的走进远征03，并在落地后核对楼层装配结果。
##
## 这条链有四跳，任何一跳断了，玩家看到的现象都是「点不进去」：
##   选关（`select_expedition_level`）→ 读取界面 → `TowerDescent3D` 装配 → 玩家落地。
## 前一轮只验了第一跳，所以「牌面写点击进入、按下去没反应」照样能被漏过去。
##
## 判据只用玩家能感知的东西：当前场景是不是远征03、房间建没建出来、玩家有没有
## 卡在空中或墙体里。不检查内部字段的"应该值"，那类断言绿了也可能是坏图。

const LOADING_PATH := "res://scenes/ExpeditionLoadingScreen.tscn"
const LEVEL_ID := "expedition_03"
const MIN_ROOMS := 10

var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RuntimePerformanceManager.set_verification_frame_budget_override(60)
	call_deferred("_run")

func _run() -> void:
	var tree := get_tree()
	# 自身必须活过 change_scene：把 current_scene 摘掉，本节点留在 root 下。
	tree.current_scene = null
	GameEntryFlow.request_gameplay_entry(GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT)
	_check(GameDesignConfig.select_expedition_level(LEVEL_ID),
		"select_expedition_level(%s) 被拒绝" % LEVEL_ID)
	_check(GameDesignConfig.peek_pending_expedition_level_id() == LEVEL_ID,
		"待进入关卡 id 不是 %s" % LEVEL_ID)

	tree.change_scene_to_file(LOADING_PATH)
	await tree.scene_changed
	var screen := tree.current_scene as ExpeditionLoadingScreen
	_check(screen != null, "没有经过读取界面")

	# 读取界面在装配完成时才切场景；上限 90s，超时如实报。
	var deadline := Time.get_ticks_msec() + 90000
	var tower: TowerDescent3D = null
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		var current := tree.current_scene
		if current is TowerDescent3D:
			tower = current as TowerDescent3D
			break
	_check(tower != null, "读取界面没有切到关卡场景（停留在 %s）" % str(tree.current_scene))
	if tower == null:
		_finish()
		return

	_check(tower.is_expedition(), "目标不是远征地图")
	_check(tower.get_expedition_level_id() == LEVEL_ID,
		"进场关卡 id 是 %s，不是 %s" % [tower.get_expedition_level_id(), LEVEL_ID])

	# 装配是分帧推进的：等房间数量稳定下来再统计，否则会数到一半就下结论。
	var rooms := 0
	var stable := 0
	var previous := -1
	var settle_deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < settle_deadline:
		await tree.process_frame
		rooms = tower._room_by_id.size()
		if rooms == previous and rooms >= MIN_ROOMS:
			stable += 1
			if stable >= 30:
				break
		else:
			stable = 0
		previous = rooms
	print("ENTRY03_CHAIN rooms=%d" % rooms)
	_check(rooms >= MIN_ROOMS, "只建出 %d 间房（下限 %d）" % [rooms, MIN_ROOMS])

	# 房间数量稳定 ≠ 可以落地判定：装配期碰撞体还在分批启用，
	# 此时打射线会得到"脚下没地面"的假红。等读取页自己宣布装配完成。
	var ready_deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < ready_deadline:
		if bool(tower.get_meta("loading_scene_ready", false)):
			break
		await tree.process_frame
	print("ENTRY03_CHAIN ready=%s" % str(tower.get_meta("loading_scene_ready", false)))
	# 再让物理跑几帧，碰撞体启用与玩家落地稳定下来。
	for i in range(20):
		await tree.physics_frame

	var player := tower.player
	_check(player != null, "关卡里没有玩家")
	if player != null:
		_check(is_instance_valid(player) and player.is_inside_tree(), "玩家不在场景树里")
		# 落地判据：脚下有地面（射线打得到），且没有掉到世界之下。
		var from := player.global_position + Vector3.UP * 1.0
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
		query.exclude = [player.get_rid()] if player is CollisionObject3D else []
		var hit := tower.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "玩家脚下没有地面（卡在空中或掉出地图）")
		print("ENTRY03_CHAIN player=%s ground_hit=%s" % [
			str(player.global_position), str(not hit.is_empty())])

	var entry_room := tower._room_by_id.get("start") as DungeonRoom3D
	_check(entry_room != null, "缺少入口安全房 start")
	print("ENTRY03_CHAIN entry_room=%s" % str(entry_room != null))
	if entry_room != null:
		print("ENTRY03_CHAIN room_pos=%s dims=%s player_pos=%s" % [
			str(entry_room.global_position), str(entry_room.get_dimensions()),
			str(player.global_position) if player != null else "-"])
		print("ENTRY03_CHAIN ready_meta=%s current_room=%s" % [
			str(tower.get_meta("loading_scene_ready", false)),
			str(tower.get("_current_room_id"))])
		print("ENTRY03_CHAIN collision_children=%d" % entry_room.find_children("*", "CollisionShape3D", true, false).size())
	_finish()

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("ENTRY03_CHAIN_OK")
	else:
		for message in _failures:
			print("ENTRY03_CHAIN_FAIL: %s" % message)
		print("ENTRY03_CHAIN_FAILED count=%d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
