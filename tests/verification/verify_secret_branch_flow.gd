extends Node

## 传送支线（秘密房间）专项验收。
## 设计：docs/v0.1/design/支线秘密房间设计.md §11.1
## 施工：05_技术施工_关卡生成与爬楼.md §5.5
##
## 只断言**已实现**的部分。未实现项在 `_report` 里逐条列出，
## 不写假绿 —— 见文末 `UNIMPLEMENTED` 段。
##
## 断言映射（设计 §11.1 编号）：
##   A1 位点不与主路门洞重合 · A2 位点在房间边界且 lane 不越界 · A3 朝外无遮挡
##   A4 pair 0 恒刷 · A5 pair 1 命中率 ∈ [45%,55%] · A6 同种子房型序列一致
##   A7 存档往返逐字段相等 · A8 子图不进主图记录
##   A9 破板后门口出现交互候选，按 E 才传送到子图落点
##   A10 入口房未清时木板锁死（不掉血、不破）
##   A11 撤离门阈值 = ceil(内容房总数 × 0.4)，锁定态与进度一致，超阈值可解锁
##   A14 破板只拆木板层，门叶留在原地
##   A15 子图末端有回主图的返程门且按 E 可用（否则进了出不来）
##   A16 子图内部靠门与门对接走通（真房型 + 门互指 + 走廊，不许再传送串联）
##   A17 子图撤离房内含 STANDARD 非锁定撤离信标（复用主撤离房同一套）
##   A18 子图每一间都加载了正式美术（共享房壳），不许退回程序化灰盒
##   A19 子图每间固定 5 只强化怪 + 2 只普通怪，首次进房才刷，全灭即标清
##   A20 位点木板不得压在**任何**主路门洞上（运行时实测中心距 ≥ 半个门宽 ×2）
##   A21 木板必须露在墙面之外：从房间内 4m 朝门中心的射线，首个必须命中门本身
##   A22 门前 2.4m 不得被工作台/货架等家具挡住（否则看得见也走不到）
##   A23 门框前表面必须比墙面凸出 ≥ 0.25m —— 3cm 那种「刚好不穿模」在暗房里就是一面平墙
##   A24 房间 TSCN 里手摆的门必须与运行时那扇门重合（差 ≤1cm、朝向点积 ≥0.99）
##   A25 按 E 的落点必须落在**子图房间的平面范围内**（不是房间外几十米的空中）
##   A26 场上不许留「房间 TSCN 带来的摆位锚点门」副本 —— 它没 configure，打它只会碎块飞、木板不动、按 E 无反应
##   A27 子图每一间房**脚下必须实心**（1m 网格向下射线不许有空格）—— 主路的实心来自整层 FloorSupport，子图够不着
##   A28 子图房**壳必须摆正**（美术足迹 = 本间尺寸）—— 不摆正就是「墙偏出 2.5m、门墙开在没门的那面」
##   （A12 跳跃边界、A13 击杀账 —— 未实现，见 UNIMPLEMENTED）

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const LEVEL_ID := "expedition_01"
const STATEMENT_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
## 位点静态期望（与设计 §3.2 表逐值一致）。脚本内置一份旁证，不读产品代码常量。
## `wall` / `lane` 是**房间自己的墙**与沿墙偏移（与 `connection_ports.position_m`
## 同一局部系），业主要求位点固定、角色自由配 —— 入口/出口只由 `role` 决定。
const EXPECTED_SITES := {
	"S1": {"room_id": "room_03", "pair_id": 0, "role": "entry", "wall": "south", "lane": 2.5},
	"S2": {"room_id": "room_06", "pair_id": 0, "role": "exit", "wall": "south", "lane": 2.5},
	"S3": {"room_id": "room_07", "pair_id": 1, "role": "entry", "wall": "north", "lane": 5.0},
	"S4": {"room_id": "room_10", "pair_id": 1, "role": "exit", "wall": "south", "lane": -7.5},
}
## A20：位点木板与任何主路门洞的中心水平距离下限。
## 木板与门洞都是 2.2m 宽，中心距 < 2.2m 即两者重叠 —— 留 0.1m 让浮点有余量。
const SITE_DOOR_MIN_CLEARANCE_M := 2.3
## A21：从房间内往门中心打视线射线的起点（离墙面多深、人眼高度）。
const SITE_RAY_INSET_M := 4.0
const SITE_RAY_EYE_Y_M := 1.4
## A23：门框前表面离墙面的凸出下限（m）。低于它，暗房里看起来就是平墙。
const SITE_MIN_PROTRUSION_M := 0.25
## 子图偏移带（设计 §3.6）：pair 0 从 +1000m 起，pair 1 再 +300m。
const BRANCH_BASE_X := 1000.0
const BRANCH_STRIDE_X := 300.0
const BRANCH_X_TOLERANCE := 400.0
## A28：壳足迹与本间尺寸的允许误差（m）。与 `SecretBranch3D.SHELL_FIT_TOLERANCE_M`
## 同值但**独立写死**（验收不读产品常量，写错才抓得到）。
const SHELL_FIT_TOLERANCE_M := 1.5
## 板体血量公式（设计 §4.1）：HP = 60 + 20 × 已清内容房数。
const DOOR_HP_BASE := 60
const DOOR_HP_PER_CLEARED := 20


func _ready() -> void:
	var failures: Array[String] = []
	var notes: Array[String] = []
	_check_static_sites(failures, notes)
	_check_spawn_rules(failures)
	await _check_runtime(failures, notes)
	_report(failures, notes)


## —— A1 / A2 / A3：静态位点合法性 ——
func _check_static_sites(failures: Array[String], notes: Array[String]) -> void:
	var normalized := LevelPlanLoader.normalize_floor(LEVEL_ID, 0)
	if not (normalized.get("errors", []) as Array).is_empty():
		failures.append("A1 规范化失败：%s" % str(normalized.get("errors", [])))
		return
	var rooms: Dictionary = {}
	for value in normalized.get("rooms", []) as Array:
		var room := value as Dictionary
		# 规范化后的房间用 `key` 标识（`id` 在规范化层不保证存在）。
		rooms[str(room.get("key", ""))] = room

	var found: Dictionary = {}
	for room_id in rooms:
		var room := rooms[room_id] as Dictionary
		var site := room.get("secret_site", {}) as Dictionary
		if site.is_empty():
			continue
		found[str(site.get("site_id", ""))] = {"site": site, "room": room}

	if found.size() != EXPECTED_SITES.size():
		failures.append("A1 位点数量不是 4：%d（%s）" % [found.size(), str(found.keys())])

	for site_id in EXPECTED_SITES:
		var expected := EXPECTED_SITES[site_id] as Dictionary
		if not found.has(site_id):
			failures.append("A1 缺少位点 %s" % site_id)
			continue
		var row := found[site_id] as Dictionary
		var site := row["site"] as Dictionary
		var room := row["room"] as Dictionary
		if int(site.get("pair_id", -1)) != int(expected.get("pair_id", -2)):
			failures.append(
				"A1 位点 %s 的 pair_id 不一致：%d != %d"
				% [site_id, int(site.get("pair_id", -1)), int(expected.get("pair_id", -2))]
			)
		for key in ["role", "wall"]:
			if str(site.get(key, "")) != str(expected.get(key, "")):
				failures.append(
					"A1 位点 %s 的 %s 不一致：%s != %s"
					% [site_id, key, str(site.get(key, "")), str(expected.get(key, ""))]
				)
		if str(room.get("key", "")) != str(expected.get("room_id", "")):
			failures.append(
				"A1 位点 %s 落在错误的房间：%s" % [site_id, str(room.get("key", ""))]
			)

		# A2：位点必须压在房间包围盒边界上，且 `lane` 不得超出墙长。
		var center := room.get("center", Vector2.ZERO) as Vector2
		var size := room.get("size", Vector2.ZERO) as Vector2
		var wall := str(site.get("wall", ""))
		var lane := float(site.get("lane", 0.0))
		var point := center
		match wall:
			"north": point.y = center.y - size.y * 0.5
			"south": point.y = center.y + size.y * 0.5
			"east": point.x = center.x + size.x * 0.5
			"west": point.x = center.x - size.x * 0.5
			_: failures.append("A2 位点 %s 墙面非法：%s" % [site_id, wall])
		# 沿墙偏移：南北墙沿 x、东西墙沿 z —— 与端口 `position_m` 的沿墙分量同口径。
		if wall in ["north", "south"]:
			point.x = center.x + lane
		else:
			point.y = center.y + lane
		var half_along := (size.x if wall in ["north", "south"] else size.y) * 0.5
		if absf(lane) > half_along - SITE_DOOR_MIN_CLEARANCE_M:
			failures.append(
				"A2 位点 %s 的 lane=%+.1f 超出墙长（半长 %.1f，需留出半个门宽）"
				% [site_id, lane, half_along]
			)
		var on_boundary := false
		if wall in ["north", "south"]:
			on_boundary = absf(point.y - (center.y + (size.y * 0.5 if wall == "south" else -size.y * 0.5))) < 0.001
		else:
			on_boundary = absf(point.x - (center.x + (size.x * 0.5 if wall == "east" else -size.x * 0.5))) < 0.001
		if not on_boundary:
			failures.append("A2 位点 %s 不在房间边界上" % site_id)

		# A1：同一面墙上不得有**贴着位点**的端口。
		# 原判据是「该墙面任何端口都不许有」，但一墙多门本来就合法（room_10 运行时
		# 东墙、北墙各有一门），过严会把合法布局判红。真正要守的是「别把木板钉在
		# 门洞上」，所以改成沿墙距离判据 —— 与 A20 的运行时判据同一口径。
		for port_value in room.get("connection_ports", []) as Array:
			var port := port_value as Dictionary
			var local := port.get("position_m", []) as Array
			if local.size() < 2:
				continue
			var port_world := center + Vector2(float(local[0]), float(local[1]))
			var same_wall := false
			if wall in ["north", "south"]:
				same_wall = absf(port_world.y - point.y) < 0.001
			else:
				same_wall = absf(port_world.x - point.x) < 0.001
			if not same_wall:
				continue
			var port_along := port_world.x if wall in ["north", "south"] else port_world.y
			var site_along := point.x if wall in ["north", "south"] else point.y
			var gap := absf(port_along - site_along)
			if gap < SITE_DOOR_MIN_CLEARANCE_M:
				failures.append(
					"A1 位点 %s 与端口 %s 挤在同一处（同墙间距 %.2fm < %.1fm）"
					% [site_id, str(port.get("port_id", "")), gap, SITE_DOOR_MIN_CLEARANCE_M]
				)

		# A3：朝外方向 3m 内不得有其他房间。
		# 三档深度只报一次 —— 撞进同一间房会连续命中 0.5/1.5/3.0 三次，
		# 一条缺陷刷三条红只会淹没真正的其它红项。
		var normal := _wall_normal(wall)
		var a3_hit := false
		for depth in [0.5, 1.5, 3.0]:
			if a3_hit:
				break
			var probe: Vector2 = point + normal * float(depth)
			for other_id in rooms:
				if other_id == str(room.get("key", "")):
					continue
				var other := rooms[other_id] as Dictionary
				var oc := other.get("center", Vector2.ZERO) as Vector2
				var os := other.get("size", Vector2.ZERO) as Vector2
				if absf(probe.x - oc.x) < os.x * 0.5 - 0.001 and absf(probe.y - oc.y) < os.y * 0.5 - 0.001:
					# **不判红**：设计源坐标是重排前的示例版图（`room_10` 设计
					# (50,-45)、实机 (55,-250)，差 200m 量级），静态「朝外撞房」
					# 的结论对运行时没有意义 —— S2 实际装配在 room_06 东墙，
					# 离隔壁 3m 以上，而设计源上它的南邻正好是 room_05。
					# 运行时保证交给 A20（不压主路门洞）与 A21（视线可见）。
					notes.append(
						"A3 位点 %s 在设计源图上朝外落进 %s（实机房位已重排，仅记录）"
						% [site_id, other_id]
					)
					a3_hit = true
					break


func _wall_normal(wall: String) -> Vector2:
	match wall:
		"north": return Vector2(0, -1)
		"south": return Vector2(0, 1)
		"east": return Vector2(1, 0)
		"west": return Vector2(-1, 0)
	return Vector2.ZERO


## —— A4 / A5 / A6：生成规则（纯规则，不需场景） ——
func _check_spawn_rules(failures: Array[String]) -> void:
	var script := load("res://src/world3d/SecretBranch3D.gd")
	if script == null:
		failures.append("A4 SecretBranch3D.gd 无法加载")
		return
	var pair_1_hits := 0
	var total := 1000
	for seed_value in range(total):
		var branch := Node3D.new()
		branch.set_script(script)
		branch.call("configure", Vector3.ZERO, seed_value, [], Callable(self, "_zero"))
		if not bool(branch.call("_pair_spawned", 0)):
			failures.append("A4 种子 %d 下 pair 0 未刷出" % seed_value)
		if bool(branch.call("_pair_spawned", 1)):
			pair_1_hits += 1
		branch.free()

	var ratio := float(pair_1_hits) / float(total)
	if ratio < 0.45 or ratio > 0.55:
		failures.append("A5 pair 1 命中率 %.3f 不在 [0.45,0.55]" % ratio)

	# A6：同一种子两次生成，房数序列必须逐项相同。
	for seed_value in [0, 1, 515151, 77001199]:
		var first := _room_counts(script, seed_value)
		var second := _room_counts(script, seed_value)
		if first != second:
			failures.append("A6 种子 %d 两次生成的房数不一致：%s / %s" % [seed_value, str(first), str(second)])


func _room_counts(script: Script, seed_value: int) -> Array:
	var branch := Node3D.new()
	branch.set_script(script)
	branch.call("configure", Vector3.ZERO, seed_value, [], Callable(self, "_zero"))
	var counts: Array = [
		int(branch.call("_branch_room_count", 0)),
		int(branch.call("_branch_room_count", 1)),
	]
	branch.free()
	return counts


func _zero() -> int:
	return 0


## 注入给 `refresh_entry_locks` / `configure` 的假房间查询：一律视为已清。
func _always_cleared(_room_id: String) -> bool:
	return true


## 注入给「已清内容房数」的假值：远超任何阈值，用于验证解锁路径。
func _huge() -> int:
	return 999


## 从 `secret_branch_encounter_snapshot()` 的逐间行里取指定房间那一行；没有返回空字典。
func _find_encounter_row(rows: Array, room_id: String) -> Dictionary:
	for row_value in rows:
		var row := row_value as Dictionary
		if str(row.get("room_id", "")) == room_id:
			return row
	return {}


## —— 运行时：装配、板体、传送、隔离、存档 ——
func _check_runtime(failures: Array[String], notes: Array[String]) -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		failures.append("运行时 远征场景加载失败")
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		failures.append("运行时 远征场景实例化失败")
		return
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var branch := tower.get_node_or_null("SecretBranches")
	if branch == null:
		failures.append("运行时 未创建 SecretBranches 节点")
		tower.queue_free()
		return

	var snapshot := branch.call("debug_snapshot") as Dictionary
	# A21/A22 必须在**任何破板用例之前**跑：A9/A14 会把 S1 打碎，
	# 木板碰撞层随即关闭，再打射线就什么也命中不了（第一版放在 A20 后面，
	# 结果 A21 对 S1 报「没打到任何东西」）。
	_check_site_visibility(tower, failures, notes)
	# A24：房间 TSCN 里手摆的门必须与运行时那扇门重合。这条不碰碰撞，
	# 放这里只是图省事（同一个 snapshot），顺序无所谓。
	_check_authored_door_parity(tower, failures, notes)
	# A26：房间里那扇「摆位锚点」副本必须已经清掉 —— 场上只许有登记过的门。
	await _check_room_copy_doors(tower, branch, failures, notes)
	# A27/A28：子图房**脚下实心** + **壳摆正**（业主 2026-10-21「装配的房间有问题，会掉落」）。
	await _check_branch_floors(branch, failures, notes)
	await _check_branch_shell_fit(branch, failures, notes)
	var doors: Array = snapshot.get("doors", []) as Array
	# 77001199 下 pair 1 是否刷出由种子决定；至少 pair 0 的两个位点必须在。
	if doors.size() < 2:
		failures.append("运行时 板体数量不足 2：%s" % str(doors))
	for required in ["S1", "S2"]:
		if not (required in doors):
			failures.append("运行时 缺少板体 %s" % required)

	# A8：子图不得进主图记录。
	var main_records: Array = tower._records as Array
	for record_value in main_records:
		var record := record_value as Dictionary
		if str(record.get("id", "")).begins_with("Secret"):
			failures.append("A8 子图房间混入了主图记录：%s" % str(record.get("id", "")))
	for point_value in (snapshot.get("branch_points", {}) as Dictionary).values():
		for point in point_value as Array:
			var p := point as Vector3
			if p.x < BRANCH_BASE_X - BRANCH_X_TOLERANCE:
				failures.append("A8 子图房间没有落在主图外的偏移带：%s" % str(p))

	# 板体血量公式与可破坏性。
	var door_s1 := branch.get_node_or_null("SecretDoor_S1")
	if door_s1 == null:
		failures.append("运行时 找不到 SecretDoor_S1")
	else:
		var cleared := int(tower.call("_count_cleared_content_rooms"))
		var expected_hp := DOOR_HP_BASE + DOOR_HP_PER_CLEARED * cleared
		if int(door_s1.get("max_hp")) != expected_hp:
			failures.append(
				"运行时 S1 板体血量 %d 与公式 %d 不符"
				% [int(door_s1.get("max_hp")), expected_hp]
			)

		# A10：入口板在入口房未清时必须锁着 —— 打上去不掉血、不破。
		# 设计 §5.2：玩家在战斗中冲进支线会把主路怪物留在原地，回来时房态错乱。
		if not bool(door_s1.call("is_locked")):
			failures.append("A10 入口房未清时 S1 木板却是解锁的")
		var hp_before := int(door_s1.get("hp"))
		door_s1.call("take_damage", 9999, false, Vector3.ZERO, 0.0)
		for _frame in range(3):
			await get_tree().physics_frame
		if int(door_s1.get("hp")) != hp_before:
			failures.append(
				"A10 锁定态被打掉血：%d -> %d" % [hp_before, int(door_s1.get("hp"))]
			)
		if bool(door_s1.call("is_broken")):
			failures.append("A10 锁定态被打碎了")

		# 模拟入口房清完：解锁后才能破。
		branch.call("refresh_entry_locks", Callable(self, "_always_cleared"))
		if bool(door_s1.call("is_locked")):
			failures.append("A10 入口房清完后 S1 木板仍未解锁")

		# A9：破板后门口出现交互候选，**按 E** 才被移到子图落点。
		# 旧实现是「踩进 Area3D 就传送」：触发盒为了贴住门洞必然有一半探进房间，
		# 玩家贴着墙走就会被吸走，既不知道发生了什么也没法拒绝。现在断言三件事：
		#   ① 木板还在时不能传送（按 E 什么也不发生）；
		#   ② 破板后门口有候选，且文案是按键文案（圆点下才会显示「(e) …」）；
		#   ③ 真的按下 E 之后玩家落到子图落点。
		if bool(door_s1.call("can_teleport")):
			failures.append("A9 木板未破时就能传送")
		if bool(door_s1.call("is_interaction_dot_visible")):
			failures.append("A9 木板未破时门口就挂了交互圆点（会骗玩家按 E）")
		door_s1.call("take_damage", 9999, false, Vector3.ZERO, 0.0)
		for _frame in range(3):
			await get_tree().physics_frame
		if not bool(door_s1.call("is_broken")):
			failures.append("A9 板体未进入破碎态")
		if not bool(door_s1.call("can_teleport")):
			failures.append("A9 破板后门仍不可传送")
		if not bool(door_s1.call("is_interaction_dot_visible")):
			failures.append("A9 破板后门口没有交互圆点")
		if not door_s1.is_in_group(PlayerInteractionController3D.PROVIDER_GROUP):
			failures.append("A9 门没进交互 provider 组，圆点不会被创建")

		# A14：破板只拆木板层，门叶必须留在原地。
		# 这是 2026-10-18 换资产后的新契约 —— 原实现整块板消失，破完只剩空气，
		# 玩家不知道自己打掉了什么。若有人把门叶一起隐藏，这条会红。
		# 木板层有 0.06+0.10s 的收缩反馈后才 visible=false，碰撞则是立即关闭的；
		# 这里等动画走完再判定终态，否则测的是中间态。
		for _frame in range(20):
			await get_tree().process_frame
		var door_view := door_s1.call("debug_snapshot") as Dictionary
		if not bool(door_view.get("has_door_leaf", false)):
			failures.append("A14 门叶层不存在（资产未挂上，退回了程序化兜底板）")
		elif not bool(door_view.get("door_leaf_visible", false)):
			failures.append("A14 破板后门叶被一起隐藏 —— 玩家看不到被木板封住的那扇门")
		if bool(door_view.get("boards_visible", true)):
			failures.append("A14 破板后木板层仍在显示")
		if int(door_view.get("collision_layer", 1)) != 0:
			failures.append("A14 破板后木板层碰撞未关闭")

		var player := get_tree().get_first_node_in_group("player_3d") as Node3D
		if player == null:
			notes.append("A9 场景内没有 player_3d，按 E 传送未实测")
		else:
			# 站到门口（门节点原点 = 地面、门洞中心）。
			player.set("global_position", (door_s1 as Node3D).global_position)
			for _frame in range(4):
				await get_tree().physics_frame
			var candidate := door_s1.call("get_interaction_candidate", player) as Dictionary
			if candidate.is_empty():
				failures.append("A9 站在门口却没有交互候选（按 E 打不开门）")
			else:
				var prompt := str(candidate.get("prompt", ""))
				if not prompt.begins_with("[E]"):
					failures.append("A9 交互文案不是按键文案，圆点不会显示功能词：%s" % prompt)
				var target := door_s1.call("get_teleport_target") as Vector3
				if not bool(door_s1.call("perform_interaction", player, candidate)):
					failures.append("A9 按 E 未触发传送")
				for _frame in range(8):
					await get_tree().physics_frame
				if player.global_position.distance_to(target) > 2.0:
					failures.append(
						"A9 按 E 后玩家未被移到子图落点：%s -> %s（目标 %s）"
						% [str(door_s1.call("get_interaction_dot_anchor")), str(player.global_position), str(target)]
					)

				# A25：落点必须**真的在子图房间里**。
				#
				# A9 只比「玩家位置 vs 落点」，两边一起被推歪时它照样是绿的 —— 2026-10-19
				# 业主实测「按 E 传送到空房间」正是这种：`_rebase_door()` 把门的手摆位移
				# 也加到了落点上，落点被子图房间外推 39m，人落在房间外的空中往下掉，
				# 眼里就是一间没装配的空房。几何判据比距离阈值可靠：
				# 落点必须落在某一间子图房间的平面范围内，高度不离地。
				var landing := player.global_position
				var landing_room := _room_containing(branch, landing)
				if landing_room.is_empty():
					failures.append(
						"A25 按 E 的落点不在任何子图房间里：%s —— 玩家会落在空处/下坠" % str(landing)
					)
				else:
					notes.append("A25 传送落点落在子图房间内：%s" % landing_room)

		# A11：撤离门阈值 = ceil(内容房总数 × 0.4)，且锁定态与「已清 vs 阈值」一致。
		# A15：子图末端必须有回主图的传送门 —— 出口门板在主图那侧，玩家进了子图
		# 够不到它；只靠出口门就等于「进了出不来」。
		var total := int(tower.call("_count_content_rooms"))
		var expected_threshold := int(ceil(float(total) * 0.4))
		var extraction := branch.call("extraction_snapshot") as Dictionary
		if int(extraction.get("threshold", -1)) != expected_threshold:
			failures.append(
				"A11 撤离门阈值 %d 与 ceil(%d×0.4)=%d 不符"
				% [int(extraction.get("threshold", -1)), total, expected_threshold]
			)
		var rows: Array = extraction.get("rows", []) as Array
		if rows.is_empty():
			failures.append("A11 撤离门未装配（子图应有第二道隐藏门）")
		var cleared_now := int(extraction.get("cleared", -1))
		var should_unlock := cleared_now >= expected_threshold
		for row_value in rows:
			var row := row_value as Dictionary
			if bool(row.get("locked", true)) == should_unlock:
				failures.append(
					"A11 撤离门锁定态与进度不一致：cleared=%d 阈值=%d locked=%s"
					% [cleared_now, expected_threshold, str(row.get("locked", true))]
				)
			if bool(row.get("teleport_ready", false)) and not bool(row.get("broken", false)):
				failures.append("A11 未破板时撤离门已可传送")

		# A11-b：只测状态抓不到阈值逻辑失效 —— 装配时房间还没建完，
		# `_extraction_unlocked()` 会先走 `total <= 0` 的保守降级分支（返回 false），
		# 于是「锁着」这个结论可能压根没经过阈值比较。所以必须**主动驱动行为**：
		# 在进度不足时刷新一次，门必须仍然锁着。把阈值判定改成恒真，这条立刻变红。
		if not should_unlock:
			branch.call("refresh_extraction_locks")
			var guard_rows: Array = (
				branch.call("extraction_snapshot") as Dictionary
			).get("rows", []) as Array
			for row_value in guard_rows:
				var row := row_value as Dictionary
				if not bool(row.get("locked", true)):
					failures.append(
						"A11 进度不足（%d < %d）时刷新却把撤离门解锁了"
						% [cleared_now, expected_threshold]
					)

		# 解锁路径：把「已清数」注入成远超阈值，刷新后必须解锁。
		branch.call(
			"configure", Vector3.ZERO, int(branch.get("_run_seed")),
			tower._records, Callable(self, "_huge"),
			Callable(self, "_always_cleared"), Callable(tower, "_count_content_rooms")
		)
		branch.call("refresh_extraction_locks")
		var unlocked_rows: Array = (branch.call("extraction_snapshot") as Dictionary).get("rows", []) as Array
		for row_value in unlocked_rows:
			var row := row_value as Dictionary
			if bool(row.get("locked", true)):
				failures.append("A11 已清数超过阈值后撤离门仍锁着")

		# A15：子图末端必须有回主图的**常开门**，且按 E 就能用 —— 出口门板在主图那侧，
		# 玩家进了子图够不到它；只靠出口门就等于「进了出不来」。
		# 这扇门刻意没有木板层：已经在子图里了，不该为了出去再打一块 60+ 血的板。
		var return_door := branch.get_node_or_null("SecretDoor_R0")
		if return_door == null:
			failures.append("A15 子图末端没有回主图的返程门")
		else:
			if not bool(return_door.call("can_teleport")):
				failures.append("A15 子图末端返程门不可传送（常开门应是开着的）")
			if not (return_door as Node).is_in_group(
				PlayerInteractionController3D.PROVIDER_GROUP
			):
				failures.append("A15 返程门没进交互 provider 组，按 E 用不了")
			var return_view := return_door.call("debug_snapshot") as Dictionary
			if bool(return_view.get("has_boards", true)):
				failures.append("A15 返程门还带着木板层（回主路不该再打一块板）")
			if (return_door.call("get_teleport_target") as Vector3) == Vector3.ZERO:
				failures.append("A15 返程门没有下发落点")

		# A16：子图内部必须靠**门与门对接**走通（05.2 §3.5.1 / §3.6 第 7 条）。
		# 前两版是「四面实墙的盒子 + 传送门串联」—— 那不是子图的做法，是把
		# 「打爆木板进一条走不通的走廊」伪装成能玩。本断言盯三件事：
		#   ① 子图里不许再出现串联传送门；
		#   ② 每一间都是真 `DungeonRoom3D`（白盒盒子不算房间）；
		#   ③ 相邻两间之间有走廊，且两端的门互相指向对方。
		var points_by_pair: Dictionary = (branch.call("debug_snapshot") as Dictionary).get(
			"branch_points", {}
		) as Dictionary
		var corridors_root := tower.get_node_or_null("GeneratedCorridors")
		for node in branch.get_children():
			if str(node.name).begins_with("Gate_chain_"):
				failures.append("A16 子图仍用传送串联（应为门 + 走廊）：%s" % str(node.name))
		for pair_key in points_by_pair:
			var pair_id := int(pair_key)
			var pair_points: Array = points_by_pair[pair_key] as Array
			var branch_root := branch.get_node_or_null("SecretBranch_%d" % pair_id)
			if branch_root == null:
				failures.append("A16 pair %d 缺子图根节点" % pair_id)
				continue
			var rooms: Array = []
			for child in branch_root.get_children():
				if not (child is DungeonRoom3D):
					continue
				# 撤离房也挂在这个根下（`secret_extraction_<pair>`），但它**不在串联链上** ——
				# 它是隐藏门后的独立单间（设计 §6、R3）。只数链上的 `secret_<pair>_<i>`。
				if not str((child as DungeonRoom3D).room_id).begins_with("secret_%d_" % pair_id):
					continue
				rooms.append(child)
			rooms.sort_custom(func(a, b): return str((a as DungeonRoom3D).room_id) < str((b as DungeonRoom3D).room_id))
			if rooms.size() != pair_points.size():
				failures.append(
					"A16 pair %d 子图真房型 %d 间，应为 %d 间（盒子不算房间）"
					% [pair_id, rooms.size(), pair_points.size()]
				)
				continue
			for index in range(rooms.size() - 1):
				var current := rooms[index] as DungeonRoom3D
				var next := rooms[index + 1] as DungeonRoom3D
				var next_id := str(next.get("room_id"))
				var current_id := str(current.get("room_id"))
				if str(current.door_targets.get("east", "")) != next_id:
					failures.append(
						"A16 pair %d 第 %d 间的东门没指向下一间（%s ≠ %s）"
						% [pair_id, index, str(current.door_targets.get("east", "")), next_id]
					)
				if str(next.door_targets.get("west", "")) != current_id:
					failures.append(
						"A16 pair %d 第 %d 间的西门没指回上一间（%s ≠ %s）"
						% [pair_id, index + 1, str(next.door_targets.get("west", "")), current_id]
					)
				# 门扇必须落在 lane 上：门洞切口（`_build_wall`）与门扇
				# （`_build_door`）读的是同一个 `wall_door_lane_<side>`。
				# 只设一头就是「洞在一边、门扇在另一边」，那条边永远走不过去。
				var lane := float(current.get_meta("wall_door_lane_east", 0.0))
				var east_door := current.get_door_node("east")
				if east_door == null:
					failures.append("A16 pair %d 第 %d 间东墙没有门扇" % [pair_id, index])
				elif absf(east_door.position.z - lane) > 0.01:
					failures.append(
						"A16 pair %d 第 %d 间东门扇 z=%.2f 不在 lane %.2f（门洞与门扇错位）"
						% [pair_id, index, east_door.position.z, lane]
					)
				if corridors_root == null:
					failures.append("A16 找不到 GeneratedCorridors，子图相邻间无走廊")
					continue
				var linked := false
				for corridor in corridors_root.get_children():
					if not (corridor is StaticBody3D):
						continue
					if (
						str(corridor.get_meta("from_room_id", "")) == current_id
						and str(corridor.get_meta("to_room_id", "")) == next_id
					):
						linked = true
						if not (corridor as StaticBody3D).visible:
							failures.append(
								"A16 pair %d 第 %d→%d 间走廊不可见（会被流送判据关掉）"
								% [pair_id, index, index + 1]
							)
						# 走廊中心线必须跟着门位平移，否则门在 lane 上、走道在中轴，
						# 玩家出门就撞墙（05.2 §3.5.2「两侧 lane 决定同一条走廊中心线」）。
						var corridor_lateral := (corridor as StaticBody3D).position.z
						var expected_lateral := current.global_position.z + lane
						if absf(corridor_lateral - expected_lateral) > 0.05:
							failures.append(
								"A16 pair %d 第 %d→%d 间走廊中心线 z=%.2f 与门位 z=%.2f 不重合"
								% [pair_id, index, index + 1, corridor_lateral, expected_lateral]
							)
						break
				if not linked:
					failures.append(
						"A16 pair %d 第 %d→%d 间没有走廊，房间之间走不通"
						% [pair_id, index, index + 1]
					)

		# A17：子图撤离房必须内含一个 `STANDARD`、非锁定的撤离信标（设计 §6.1）。
		# 信标不是新建的一套：走 `Dungeon3D._create_extraction_beacon`，与主撤离房
		# 同一条结算链。漏掉时的表现是「打进撤离房，里面是空房间，没有可撤离的东西」。
		for pair_key in points_by_pair:
			var pair_id := int(pair_key)
			var branch_root := branch.get_node_or_null("SecretBranch_%d" % pair_id)
			if branch_root == null:
				continue
			var extraction_room := branch_root.get_node_or_null(
				"SecretRoom_secret_extraction_%d" % pair_id
			) as DungeonRoom3D
			if extraction_room == null:
				failures.append("A17 pair %d 子图没有撤离房节点" % pair_id)
				continue
			var beacons: Array = []
			for child in extraction_room.get_children():
				if child is ExtractionBeacon3D:
					beacons.append(child)
			if beacons.size() != 1:
				failures.append(
					"A17 pair %d 撤离房信标 %d 个，应为 1 个" % [pair_id, beacons.size()]
				)
				continue
			var beacon := beacons[0] as ExtractionBeacon3D
			var row := beacon.get_snapshot()
			if str(row.get("type", "")) != "STANDARD":
				failures.append(
					"A17 pair %d 撤离信标类型 %s，应为 STANDARD"
					% [pair_id, str(row.get("type", ""))]
				)
			if bool(row.get("locked", true)):
				failures.append("A17 pair %d 撤离信标处于锁定态，应为非锁定" % pair_id)
			if not beacon.is_in_group("extraction_beacon_3d"):
				failures.append("A17 pair %d 撤离信标未进 extraction_beacon_3d 组" % pair_id)

		# A18：子图每一间都必须**真的加载了正式美术**（共享房壳），不许是灰盒。
		# `DungeonRoom3D` 在静态布局缺失时会静默回退程序化壳体 —— 房间能走、门也在，
		# 只有真进游戏才看出来是「一片灰盒子」。这里认 `static_layout_scene_loaded` 标记。
		for pair_key in points_by_pair:
			var pair_id := int(pair_key)
			var branch_root := branch.get_node_or_null("SecretBranch_%d" % pair_id)
			if branch_root == null:
				continue
			for child in branch_root.get_children():
				if not (child is DungeonRoom3D):
					continue
				var room := child as DungeonRoom3D
				if not bool(room.get_meta("static_layout_scene_loaded", false)):
					failures.append(
						"A18 子图房 %s 没加载正式美术（退回程序化灰盒）：%s"
						% [room.room_id, str(room.get_meta("static_layout_scene_path", "<无路径>"))]
					)

		# A19：子图每一间固定刷 **5 只强化怪 + 2 只普通怪**（业主 2026-10-18 定）。
		# 三个口径一起验，缺一条都会让这条承诺变成空话：
		#   ① 没进房之前不刷 —— 否则 42 只怪在空房里干等，且「进房才戒备」的节奏没了；
		#   ② 进房之后恰好 5 强化 + 2 普通 —— 强化怪的默认 15% 升级概率必须被关掉，
		#      不然那 2 只普通怪会随机变成强化怪（数出来就是 6+1）；
		#   ③ 7 只全灭之后房间必须被标清 —— 否则 HUD 永远停在「暗室清剿」，
		#      玩家不知道这间打没打完。
		var encounter_rows: Array = branch.call("room_encounter_snapshot") as Array
		var combat_row: Dictionary = {}
		for row_value in encounter_rows:
			var row := row_value as Dictionary
			# 必须挑**还没进过**的战斗间：A9 已经把玩家送进 pair 0 第一间，
			# 那一间此刻已经在打了（这本身就是「进房才刷」的正向证据，但没法再当对照）。
			if bool(row.get("combat", false)) and not bool(row.get("entered", false)):
				combat_row = row
				break
		if combat_row.is_empty():
			failures.append("A19 找不到尚未进入的战斗间（子图应有 2–3 间战斗房）")
		elif player == null:
			notes.append("A19 场景内没有 player_3d，进房刷怪未实测")
		else:
			var target_room_id := str(combat_row.get("room_id", ""))
			for row_value in tower.call("secret_branch_encounter_snapshot") as Array:
				if str((row_value as Dictionary).get("room_id", "")) == target_room_id:
					failures.append("A19 还没进房就已经刷怪了（应在首次进房时才刷）")
			var room := branch.find_child(
				"SecretRoom_%s" % target_room_id, true, false
			) as DungeonRoom3D
			if room == null:
				failures.append("A19 找不到子图房节点 %s" % target_room_id)
			else:
				player.set("global_position", room.global_position)
				for _frame in range(8):
					await get_tree().physics_frame
				var row := _find_encounter_row(
					tower.call("secret_branch_encounter_snapshot") as Array, target_room_id
				)
				if row.is_empty():
					failures.append("A19 进入子图房 %s 后一个敌人也没刷出来" % target_room_id)
				else:
					var kinds := str(row.get("kinds", []))
					if int(row.get("strong_alive", -1)) != 5:
						failures.append(
							"A19 强化怪 %d 只，应为 5 只（kinds=%s）"
							% [int(row.get("strong_alive", -1)), kinds]
						)
					if int(row.get("plain_alive", -1)) != 2:
						failures.append(
							"A19 普通怪 %d 只，应为 2 只（kinds=%s）"
							% [int(row.get("plain_alive", -1)), kinds]
						)
					# 全灭 → 清房。`take_damage` 走真实击杀信号，与战斗中同一条链。
					# ⚠ 必须遍历**副本**：击杀会在 `_claim_enemy_departure` 里把该节点
					# 从 `_enemy_nodes_by_room[room_id]` 移除，边遍历边删会让数组前移，
					# 结果每隔一只跳过一只（实测 7 只只剩 3 只存活），看上去像「伤害没生效」。
					var nodes: Array = (
						(tower.get("_enemy_nodes_by_room") as Dictionary).get(target_room_id, []) as Array
					).duplicate()
					for value in nodes:
						if is_instance_valid(value) and value is Enemy3D:
							(value as Enemy3D).take_damage(999999)
					for _frame in range(12):
						await get_tree().physics_frame
					var after := _find_encounter_row(
						tower.call("secret_branch_encounter_snapshot") as Array, target_room_id
					)
					if not after.is_empty():
						if int(after.get("strong_alive", 0)) + int(after.get("plain_alive", 0)) > 0:
							failures.append(
								"A19 击杀后仍有存活敌人：强化 %d / 普通 %d"
								% [int(after.get("strong_alive", 0)), int(after.get("plain_alive", 0))]
							)
						if not bool(after.get("cleared", false)):
							failures.append("A19 7 只全灭后房间没有被标清")

		# A7：存档往返逐字段相等。
		var state := branch.call("export_state") as Dictionary
		var door_rows: Array = state.get("doors", []) as Array
		if door_rows.size() != doors.size():
			failures.append("A7 导出的门数量 %d 与实例 %d 不符" % [door_rows.size(), doors.size()])
		for row_value in door_rows:
			var row := row_value as Dictionary
			for required_key in ["site_id", "pair_id", "role", "broken", "locked"]:
				if not row.has(required_key):
					failures.append("A7 存档缺字段 %s：%s" % [required_key, str(row)])
		# 恢复必须是幂等的：对同一实例重放同一份快照，导出结果不得变化。
		# （新建空实例做往返是错的测法 —— 它没有门可恢复，必然为空。）
		branch.call("restore_state", state)
		var again := branch.call("export_state") as Dictionary
		if JSON.stringify(door_rows) != JSON.stringify(again.get("doors", [])):
			failures.append(
				"A7 存档重放后状态漂移：%s -> %s"
				% [JSON.stringify(door_rows), JSON.stringify(again.get("doors", []))]
			)

		# A20：位点木板不得压在**任何**主路门洞上。
		# 静态断言只看得见设计源；运行时房位由生成器重排（远征01 整层转 180°），
		# 只有拿真实门扇节点的世界坐标量，才能保证「这块木板没有把哪条路钉死」。
		_check_site_door_clearance(tower, failures, notes)

	tower.queue_free()
	await get_tree().process_frame


## A20：把每个 `SecretDoor_S*` 木板与所有主路 `Door_*` 门扇逐个量水平距离。
##
## 为什么必须运行时量：设计源只声明「哪面墙、哪条 lane」，最终世界坐标要等
## `FloorPlanGenerator` 重排 + 整层旋转之后才有。S3 曾因此压在
## `room_06 → room_07` 的 `Door_North` 上（实测中心距 0.00m），而静态断言全绿 ——
## 那条主路被 2.2m 木板钉死，玩家不打碎「暗门」就走不到第 7 间。
func _check_site_door_clearance(
	tower: Node, failures: Array[String], notes: Array[String]
) -> void:
	var branch := tower.get_node_or_null("SecretBranches")
	if branch == null:
		return
	var door_positions: Array = []
	_collect_door_positions(tower, door_positions)
	if door_positions.is_empty():
		notes.append("A20 场景内没有任何主路门扇，判据未实测")
		return
	var checked := 0
	for child in branch.get_children():
		var node := child as Node3D
		if node == null or not str(node.name).begins_with("SecretDoor_S"):
			continue
		checked += 1
		var pos := node.global_position
		var nearest := INF
		var nearest_name := ""
		for value in door_positions:
			var row := value as Dictionary
			var other := row.get("pos", Vector3.ZERO) as Vector3
			# 只比水平距离：门槛高度差不算「撞在一起」。
			var gap := Vector2(pos.x - other.x, pos.z - other.z).length()
			if gap < nearest:
				nearest = gap
				nearest_name = str(row.get("name", ""))
		if nearest < SITE_DOOR_MIN_CLEARANCE_M:
			failures.append(
				"A20 %s 压在主路门洞 %s 上（中心距 %.2fm < %.1fm）"
				% [str(node.name), nearest_name, nearest, SITE_DOOR_MIN_CLEARANCE_M]
			)
	if checked == 0:
		notes.append("A20 场上没有主图侧板体（pair 未刷出？），判据未实测")


## A21 / A22：暗门「看不看得见」。
##
## 起因：业主连续两局「打到第 4 间完全找不到支线入口」。实测发现 S1 的木板只向
## 房间凸 0.142m，而 `room_03` 的墙体可视面凸出 0.465m —— 木板整个埋在墙里，
## 玩家看到的是一整面平墙。装配侧（`SecretBranch3D._push_site_out_of_wall`）
## 已按实测墙面外沿把整樘门推到墙外，这里把结果锁死：
##
##   A21 从房间内 4m 处朝门中心打视线射线，第一个命中的必须是这扇门本身；
##   A22 `sites` 里不得有 `blocker`（门前 2.4m 被工作台/货架挡住），
##       也不得有 `covered_by`（整樘门被实心外壳盖住）。
##
## 为什么 A22 还要单独查 `covered_by`：射线只认碰撞体，而墙体/外壳的**碰撞代理盒
## 往往比美术面薄**（有的只在墙平面留一层壳）。`room_06` 东墙上一个 5.15m 的转角
## 壳体把整樘门包在肚子里，A21 的射线一路穿到门、判"可见"，玩家却只看到平墙 ——
## 所以装配侧另外按**可视包围盒**量了一遍，结果走 `covered_by`。
##
## 为什么不用「木板 AABB 在墙面外」这种纯几何判据：墙件不是规则盒子
## （L 形凹口、门垛、装饰带），AABB 会把整面墙的包络算进来，判不准。
## 射线问的是「玩家眼睛走过去，先看到谁」，与真实观感一致。
func _check_site_visibility(
	tower: Node, failures: Array[String], notes: Array[String]
) -> void:
	var branch := tower.get_node_or_null("SecretBranches")
	if branch == null:
		failures.append("A21 找不到 SecretBranches 节点")
		return
	var snapshot := branch.call("debug_snapshot") as Dictionary
	var sites: Array = snapshot.get("sites", []) as Array
	if sites.is_empty():
		failures.append("A21 位点快照为空 —— 装配侧没有暴露 sites，判据无法实测")
		return

	for value in sites:
		var site := value as Dictionary
		if site.has("blocker"):
			failures.append(
				"A22 位点 %s（%s）门前 2.4m 被 %s 挡住，玩家看不到也走不到"
				% [
					str(site.get("site_id", "")), str(site.get("room_id", "")),
					str(site.get("blocker", "")),
				]
			)
		if site.has("covered_by"):
			failures.append(
				"A22 位点 %s（%s）整樘门被 %s 的外壳盖住（凸出 %.2fm）—— 射线能穿过去，但玩家只看到墙"
				% [
					str(site.get("site_id", "")), str(site.get("room_id", "")),
					str(site.get("covered_by", "")), float(site.get("cover_m", 0.0)),
				]
			)
		# A23：凸出量必须大到肉眼可辨。03cm 那种"刚好不穿模"等于齐平，
		# 在塔内夜间光下人眼读作"墙"（业主 2026-10-19 第二次实测）。
		var protrude := float(site.get("protrude_m", 0.0))
		if protrude < SITE_MIN_PROTRUSION_M:
			failures.append(
				"A23 位点 %s（%s）只从墙面凸出 %.3fm（< %.2fm）—— 暗房里看起来就是一面平墙"
				% [
					str(site.get("site_id", "")), str(site.get("room_id", "")),
					protrude, SITE_MIN_PROTRUSION_M,
				]
			)

	var world: World3D = tower.get_world_3d()
	if world == null:
		failures.append("A21 拿不到 World3D，射线判据无法实测")
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var checked := 0
	for value in sites:
		var site := value as Dictionary
		var site_id := str(site.get("site_id", ""))
		var door := branch.get_node_or_null("SecretDoor_%s" % site_id) as Node3D
		if door == null:
			continue
		var position := site.get("position", Vector3.ZERO) as Vector3
		var normal := site.get("normal", Vector3.FORWARD) as Vector3
		if normal == Vector3.ZERO:
			continue
		# 起点在房间内侧：`normal` 朝房间外，所以往里走是 -normal。
		var origin := position - normal * SITE_RAY_INSET_M
		origin.y = SITE_RAY_EYE_Y_M
		var target := position + Vector3(0.0, 1.3, 0.0)
		var query := PhysicsRayQueryParameters3D.create(origin, target)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			failures.append("A21 位点 %s 的视线射线没打到任何东西（门没有碰撞？）" % site_id)
			continue
		var collider := hit.get("collider") as Node
		var is_door := collider == door or (collider != null and door.is_ancestor_of(collider))
		if not is_door:
			var blocker := "?"
			if collider != null and collider.get_parent() != null:
				blocker = str(collider.get_parent().name)
			failures.append(
				"A21 位点 %s 从房间里看过去先撞到 %s —— 木板被挡住，玩家看不见入口"
				% [site_id, blocker]
			)
		checked += 1
	var protrusions: Array[String] = []
	var manuals := 0
	for value in sites:
		var site := value as Dictionary
		var mark := ""
		if bool(site.get("manual_site", false)):
			manuals += 1
			# 手动摆位 + 认不出墙件时凸出量是**估计值**（按装配常量），不是实测。
			mark = "~" if bool(site.get("protrude_estimated", false)) else "*"
		protrusions.append(
			"%s=%.2fm%s" % [
				str(site.get("site_id", "")), float(site.get("protrude_m", 0.0)), mark,
			]
		)
	notes.append(
		"A21/A22/A23 实测 %d 个位点（* = 手摆且实测凸出，~ = 手摆但墙件认不出、按装配常量估）：凸出 %s"
		% [checked, " ".join(protrusions)]
	)


## A25：这个点落在哪一间子图房间里（空串 = 不在任何房里）。
##
## 判据用房间自己的 `get_dimensions()` 平面范围 + 1.5m 高度容差，不看碰撞、
## 不看触发器 —— 落点是否在房内是**几何事实**，不该依赖玩家是否刚好踩到 Area3D。
func _room_containing(branch: Node, point: Vector3) -> String:
	var rows_value: Variant = branch.get("_branch_rooms")
	if not (rows_value is Dictionary):
		return ""
	var rows := rows_value as Dictionary
	for room_id in rows:
		var room := (rows[room_id] as Dictionary).get("room") as DungeonRoom3D
		if room == null or not is_instance_valid(room) or not room.is_inside_tree():
			continue
		var dims: Vector2 = room.call("get_dimensions")
		if absf(point.x - room.global_position.x) > dims.x * 0.5:
			continue
		if absf(point.z - room.global_position.z) > dims.y * 0.5:
			continue
		if absf(point.y - room.global_position.y) > 1.5:
			continue
		return str(room_id)
	return ""


## A26：房间里那扇「摆位锚点门」副本必须已经被清掉。
##
## 为什么要有这条（业主 2026-10-21「打门后有破碎动画，但木板没消失，也不能点 E」）：
##   `SecretBranch3D._create_secret_branches()` 跑在 `_prepare_floor_bundle()` 里 ——
##   那一刻房间**记录**齐了、房间节点和壳体都还没建，接管必然落空，于是自己建一扇；
##   等壳体建好，房间 TSCN 里那扇**没被 `configure()` 过**的副本才冒出来。
##   玩家打中副本时：`_boards` 为 null（木板不消失）、`_has_teleport` 为 false
##   （按 E 无候选），而 `_spawn_board_debris()` 不依赖这两者（碎块照飞）。
##   三个症状一起出现，看着像「破板坏了」，其实是同一处叠了两扇门。
##
## 判据：场上每一扇 `SecretDoor3D` 都必须被 `configure()` 认领（`site_id` 非空）
##   并且在 `_doors` 登记表里。清道夫见 `SecretBranch3D._arm_room_copy_watch()`。
func _check_room_copy_doors(tower: Node, branch: Node, failures: Array, notes: Array) -> void:
	# 先把房间壳体催出来：房间 TSCN 里那扇副本只有在壳体建成之后才存在。
	# 不催就没东西可查 —— 实测不催时场上副本 0 扇，关掉清道夫做反向对照也照样绿，
	# 这条断言等于空过（同 A25 的「套件跑不出真实时序」）。
	var rooms: Dictionary = branch.get("_room_nodes") as Dictionary
	var forced := 0
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		if bool(room.get("_shell_built")):
			continue
		room.call("ensure_shell_built")
		forced += 1
	if forced > 0:
		# 清道夫挂在 `node_added` 上、走 deferred —— 给它两帧把副本摘掉。
		await get_tree().process_frame
		await get_tree().process_frame
	var registered: Array = []
	var doors: Dictionary = branch.get("_doors") as Dictionary
	for site_id in doors:
		registered.append(doors[site_id])
	var total := 0
	var copies: Array[String] = []
	for node in tower.find_children("*", "StaticBody3D", true, false):
		if not (node is SecretDoor3D):
			continue
		total += 1
		var door := node as SecretDoor3D
		var sid := str(door.site_id)
		if sid.is_empty() or not registered.has(door):
			copies.append(
				"%s（site_id=%s）" % [str(tower.get_path_to(door)), sid if not sid.is_empty() else "<空>"]
			)
	if not copies.is_empty():
		failures.append(
			"A26 场上仍有 %d 扇没被装配认领的门副本：%s —— 玩家打它会是「碎块飞了、木板不动、按 E 无反应」"
			% [copies.size(), ", ".join(copies)]
		)
	else:
		notes.append("A26 场上门全部被认领：%d 扇" % total)


## A27：支线每一间房**脚下必须是实的** —— 1 m 网格向下射线不许留空格。
##
## 为什么要有这条（业主 2026-10-21「装配的房间有问题。会掉落。支线的」）：
##   主路房间踩得实，靠的不是房间自带的地砖，而是 `TowerFloorStage3D` 按**整层**铺的
##   `FloorSupport` 大板（实测 room_01 的 440 个俯视采样点里 330 格踩的是它）。
##   子图整条链挂在主图外 +1000 m，够不着那块板；共享房壳只带来美术地砖
##   （`corridor_45x40` 42 块 5 m 砖 = 1050 ㎡，房间 1800 ㎡），于是 66%~78% 的
##   位置脚下是虚空 —— 按 E 进去就一路掉出关卡。
##   修法见 `SecretBranch3D._ensure_floor_support()`（每间铺一块顶面贴 y=0 的承重盒）。
##
## 判据用**射线**而不是「节点在不在」：承重盒存在但位置/厚度写错时节点照样在。
## 每间按 1 m 网格从房心上方 2.2 m 打到地面下 6 m，命中高度必须在地面 ±0.6 m 内
## （打到地面的装饰件也算数，只要不是掉进虚空）。
func _check_branch_floors(branch: Node, failures: Array, notes: Array) -> void:
	var rooms: Dictionary = branch.get("_branch_rooms") as Dictionary
	if rooms.is_empty():
		failures.append("A27 子图房间登记为空，判据无法实测")
		return
	# 壳体/承重盒只有在建完之后才存在；`test_mode` 下没被催建时是空的（同 A26 的坑）。
	var forced := 0
	for room_id in rooms:
		var room := (rooms[room_id] as Dictionary).get("room") as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		if not bool(room.get("_shell_built")):
			room.call("ensure_shell_built")
			forced += 1
	if forced > 0:
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
	var world := get_viewport().world_3d
	if world == null:
		failures.append("A27 拿不到 World3D，射线判据无法实测")
		return
	var space := world.direct_space_state
	var checked := 0
	# 一个分支根下只有**一块** `SecretFloorSupport`（每条子图链一块），里面按房间数放盒。
	# 所以要对「全部承重体」求和，不能拿某一块的子节点数去比房间数。
	var support_bodies := {}
	var bad: Array[String] = []
	for room_id in rooms:
		var room := (rooms[room_id] as Dictionary).get("room") as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		var support := room.get_parent().get_node_or_null("SecretFloorSupport") as StaticBody3D
		if support != null:
			support_bodies[support.get_instance_id()] = support.get_child_count()
		var dims := room.get_dimensions()
		var floor_y := room.global_position.y
		var cols := maxi(1, int(floor(dims.x)))
		var rows := maxi(1, int(floor(dims.y)))
		var holes := 0
		for row in range(rows):
			for col in range(cols):
				var lx := -dims.x * 0.5 + (float(col) + 0.5) * (dims.x / float(cols))
				var lz := -dims.y * 0.5 + (float(row) + 0.5) * (dims.y / float(rows))
				var point := room.global_transform * Vector3(lx, 0.0, lz)
				var query := PhysicsRayQueryParameters3D.create(
					Vector3(point.x, floor_y + 2.2, point.z),
					Vector3(point.x, floor_y - 6.0, point.z)
				)
				query.collide_with_areas = false
				var hit: Dictionary = space.intersect_ray(query)
				if hit.is_empty():
					holes += 1
					continue
				var hit_y := float((hit.get("position", Vector3.ZERO) as Vector3).y)
				if hit_y < floor_y - 0.6:
					holes += 1
		checked += 1
		if holes > 0:
			bad.append("%s 空 %d/%d" % [room_id, holes, cols * rows])
	if checked == 0:
		failures.append("A27 一间子图房都没量到 —— 判据空过")
		return
	var support_shapes := 0
	for key in support_bodies:
		support_shapes += int(support_bodies[key])
	if support_shapes < checked:
		failures.append(
			"A27 承重盒数量不足：%d 块承重盒 vs %d 间房（漏铺的房间会掉出关卡）"
			% [support_shapes, checked]
		)
	if not bad.is_empty():
		failures.append(
			"A27 子图房间脚下有洞：%s —— 玩家按 E 进去会掉出关卡" % ", ".join(bad)
		)
	else:
		notes.append("A27 子图 %d 间房脚下全部实心（承重盒 %d 块）" % [checked, support_shapes])


## A28：支线房间的**壳必须摆正** —— 美术足迹要落在本间尺寸上。
##
## 为什么单独一条（同一天业主「装配的房间有问题」的另一半）：
##   主路房间的壳朝向由「布局实例清单 × 关卡房表」几何配准得出；子图房不在 `_records`
##   里、没有清单 ⇒ 那条路回落到 `template_rotation_deg`，而子图从来没设过 ⇒ 恒 0。
##   于是 `corridor_45x40` 的壳（烘焙 40×45）被原样塞进 45×40 的房间：四面墙整体偏出
##   2.5 m、门墙落在北墙而房间的门在东/西墙（实测墙探针 155/170 打空）。
##   修法见 `SecretBranch3D._shared_shell_alignment_deg()`（按足迹定 0/90，按门侧破平局）。
##
## 判据：房间局部系里**全部网格**的 AABB 必须与本间 `get_dimensions()` 双向吻合
## （容差 1.5 m —— 转错 90° 的候选至少差 4 m，不会混淆）。
func _check_branch_shell_fit(branch: Node, failures: Array, notes: Array) -> void:
	var rooms: Dictionary = branch.get("_branch_rooms") as Dictionary
	if rooms.is_empty():
		failures.append("A28 子图房间登记为空，判据无法实测")
		return
	var checked := 0
	var bad: Array[String] = []
	for room_id in rooms:
		var room := (rooms[room_id] as Dictionary).get("room") as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			continue
		var box := _room_local_visual_box(room)
		if box.size == Vector3.ZERO:
			continue
		checked += 1
		var dims := room.get_dimensions()
		var dx := absf(box.size.x - dims.x)
		var dz := absf(box.size.z - dims.y)
		var applied := float(room.get_meta("shared_shell_alignment_deg", 0.0))
		var root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		var applied_real := rad_to_deg(root.rotation.y) if root != null else 0.0
		if dx > SHELL_FIT_TOLERANCE_M or dz > SHELL_FIT_TOLERANCE_M:
			bad.append(
				"%s 美术 %.1fx%.1f vs 房间 %.1fx%.1f" % [room_id, box.size.x, box.size.z, dims.x, dims.y]
			)
			continue
		# 角度差取「最小有向夹角」：`deg_to_rad`/`rad_to_deg` 往返有 1e-8 级浮点残差，
		# 直接 `fposmod(diff, 360)` 会把它放大成 360.0（第一版就栽在这里，报「差 360°」）。
		var delta_deg := absf(fposmod(applied - applied_real + 180.0, 360.0) - 180.0)
		if applied > 0.5 and delta_deg > 1.0:
			bad.append(
				"%s 声明转 %.1f° 实际壳根 %.1f°（差 %.1f°）" % [
					room_id, applied, applied_real, delta_deg,
				]
			)
	if checked == 0:
		failures.append("A28 一间子图房都没量到 —— 判据空过")
		return
	if not bad.is_empty():
		failures.append("A28 子图房壳没摆正：%s —— 墙/门会错位" % ", ".join(bad))
	else:
		notes.append("A28 子图 %d 间房壳足迹全部与本间尺寸吻合" % checked)


## 房间局部系里全部网格的 AABB（跳过 `editor_preview_only` 子树 —— 那些件运行时不出现）。
func _room_local_visual_box(room: DungeonRoom3D) -> AABB:
	var box := AABB()
	var started := false
	var to_local := room.global_transform.affine_inverse()
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		if _under_preview_only(mesh, room):
			continue
		var part := to_local * (mesh.global_transform * mesh.mesh.get_aabb())
		if not started:
			box = part
			started = true
		else:
			box = box.merge(part)
	return box


func _under_preview_only(node: Node, stop: Node) -> bool:
	var probe: Node = node
	while probe != null and probe != stop:
		if bool(probe.get_meta("editor_preview_only", false)):
			return true
		probe = probe.get_parent()
	return false


## A24：房间 TSCN 里手摆的门 = 运行时那扇门。
##
## 新机制（2026-10-19 业主）让门直接摆进房间 TSCN，编辑器里可看可拖，运行时按它的
## transform 装门。这条断言盯住两边别走散：TSCN 局部 → 世界，必须与 `sites[].position`
## 重合、朝向同向。差 1cm 以上就判红 —— 那意味着业主拖完、游戏里却歪到墙缝外。
func _check_authored_door_parity(tower: Node, failures: Array, notes: Array) -> void:
	var branch := tower.get_node_or_null("SecretBranches")
	if branch == null:
		return
	var snapshot := branch.call("debug_snapshot") as Dictionary
	var sites: Array = snapshot.get("sites", []) as Array
	var checked := 0
	for value in sites:
		var site := value as Dictionary
		if not bool(site.get("manual_site", false)):
			continue
		var room_id := str(site.get("room_id", ""))
		var room := tower.find_child(room_id, true, false) as Node3D
		if room == null:
			continue
		var path := str(room.get("static_layout_scene_path"))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var state := packed.get_state()
		if state == null:
			continue
		var root_local := Transform3D.IDENTITY
		for index in range(state.get_node_property_count(0)):
			if str(state.get_node_property_name(0, index)) == "transform":
				root_local = state.get_node_property_value(0, index) as Transform3D
		var site_id := str(site.get("site_id", ""))
		var wanted_name := "SecretDoor_%s" % site_id
		var door_local: Variant = null
		for index in range(state.get_node_count()):
			if str(state.get_node_name(index)) != wanted_name:
				continue
			door_local = Transform3D.IDENTITY
			for property_index in range(state.get_node_property_count(index)):
				if str(state.get_node_property_name(index, property_index)) == "transform":
					door_local = state.get_node_property_value(index, property_index) as Transform3D
			break
		if door_local == null:
			continue
		var world := room.global_transform * (root_local * (door_local as Transform3D))
		var want := site.get("position", Vector3.ZERO) as Vector3
		var gap := world.origin.distance_to(want)
		var facing := world.basis.z
		facing.y = 0.0
		var want_normal := site.get("normal", Vector3.FORWARD) as Vector3
		var dot := 0.0
		if facing.length() > 0.001 and want_normal.length() > 0.001:
			dot = facing.normalized().dot(want_normal.normalized())
		if gap > 0.01 or dot < 0.99:
			failures.append(
				"A24 位点 %s（%s）TSCN 里手摆的门与运行时门不重合：差 %.3fm，朝向点积 %.3f"
				% [site_id, room_id, gap, dot]
			)
		checked += 1
	if checked > 0:
		notes.append("A24 手摆门与运行时一致：%d 扇" % checked)


func _collect_door_positions(root: Node, out: Array) -> void:
	for child in root.get_children():
		var node := child as Node
		if node == null:
			continue
		if node is Node3D and str(node.name).begins_with("Door_"):
			out.append({
				"name": str(node.name),
				"pos": (node as Node3D).global_position,
			})
		_collect_door_positions(node, out)


func _report(failures: Array[String], notes: Array[String]) -> void:
	for note in notes:
		print("[NOTE] ", note)
	# 未实现项：显式列出，避免「跑绿了」被误读成功能完整。
	print("[UNIMPLEMENTED] A12/B1-B3 跳跃边界运行时断言（当前只有静态数据核对）")
	print("[UNIMPLEMENTED] A13 子图击杀与主图合计的独立账（当前只并入全局击杀数）")
	if failures.is_empty():
		print("SECRET_BRANCH_FLOW_OK 位点=4 槽位固定 门洞不重合 门板可见 落点在房内 门副本=已清 脚下实心 壳已摆正 生成规则=确定 传送=可达 隔离=通过 编成=5强化+2普通 存档=往返一致")
		print("VERIFICATION_SEGMENT_OK")
		get_tree().quit(0)
		return
	for failure in failures:
		printerr("[FAIL] ", failure)
	print("SECRET_BRANCH_FLOW_FAILED count=%d" % failures.size())
	get_tree().quit(1)
