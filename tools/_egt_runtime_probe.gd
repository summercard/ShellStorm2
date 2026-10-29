extends Node
## 远征03 复刻怪运行时探针（2026-10-29）。
##
## 与 `_egt_monster_probe` 的分工：
##   · 那个验**数据**（数值、别名、规格键）—— 不需要游戏世界；
##   · 这个验**真实链路** —— 真的进远征03的战斗房，看刷出来的是不是 `egt_*`。
## 两者都不能省：数据对了但没接进刷怪池，等于纸上完成。
##
## 用法：godot --headless --path . --scene res://tools/_egt_runtime_probe.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const SEED_VALUE := 77003244

var failures: Array[String] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _ready() -> void:
	var tower := SCENE.instantiate() as TowerDescent3D
	if tower == null:
		print("EGT_RUNTIME_PROBE_FAIL 场景不是 TowerDescent3D")
		get_tree().quit(1)
		return
	tower.test_mode = true
	tower.run_seed_override = SEED_VALUE
	add_child(tower)
	for _frame in 12:
		await get_tree().process_frame

	# 走到第一间会刷怪的房间。远征03 的房间是运行时按 flow 生成的，
	# room_id 不固定，所以这里动态找，不写死。
	# ⚠ 必须跳过 BOSS 房：BOSS 走 `BossContentCatalog` 的专属链，不产出普通怪，
	# 第一版探针就因为撞上首间 `boss` 房而误判「一只怪都没有」。
	var target: DungeonRoom3D = null
	for room in tower._rooms:
		var candidate := room as DungeonRoom3D
		if candidate == null:
			continue
		if str(candidate.room_type) not in Dungeon3D.HOSTILE_ROOM_TYPES:
			continue
		if str(candidate.room_type) == "BOSS":
			continue
		# 必须挑**真有编成**的房间。注入房（fireplace / secret）的 content_type 会被
		# 内容洗牌随机成 COMBAT/TRAP 等敌对型，但它们的 node_id 不在 `spawn_roster.by_node` 里、
		# 房间又小，本关对它们没有编成 —— 选中它就是「合法空房」，会误判成刷怪链路坏了
		# （2026-10-29 实测：探针挑中 fireplace_room_inj2，0 只怪）。
		if (candidate.spawn_placements as Array).is_empty():
			continue
		target = candidate
		break
	if target == null:
		# 打全部房间的类型，别靠猜 —— 「一间敌对房都没有」可能是生成失败、
		# 也可能是房间类型全空（内容洗牌没跑），两者的修法完全不同。
		var dump: Array[String] = []
		for room in tower._rooms:
			var r := room as DungeonRoom3D
			if r != null:
				dump.append("%s=%s" % [r.room_id, str(r.room_type)])
		print("EGT_RUNTIME_PROBE_ROOMS n=%d %s" % [dump.size(), ", ".join(dump)])
	_check(target != null, "远征03 生成后没有任何敌对房（刷怪链路没跑起来？）")
	if target == null:
		_finish()
		return

	tower.player.global_position = target.global_position + Vector3(0.0, 0.5, 0.0)
	tower.force_enter_room_for_test(target.room_id)
	# ⚠️ flow 关卡（远征03 走的就是这条）**故意把刷怪推到落门之后**：
	# 走进来 → 门落（`FLOW_ROOM_SEAL_DELAY_S`）→ 静默（`FLOW_ROOM_SPAWN_PAUSE_S`）→ 出怪。
	# 第一版探针只等 10 帧，读到的是"门已关、怪还没出"的中间态，于是误判成"一只怪都没有"。
	# 这里按**时间**等（不是帧数），并把两段常量都带上，改常量时这条等待会自动跟上。
	# 两次采样：先看「刚落门那一下」刷出了什么，再看「延迟出怪 / 分裂 / 补刷」之后。
	# 只有对比才能分清「编成里混了原生怪」和「后来某个机制生成的」——
	# 单次采样看到 melee_chaser×2 时，两种原因在日志里长得一模一样。
	await get_tree().create_timer(TowerDescent3D.FLOW_ROOM_SEAL_DELAY_S + 0.05).timeout
	for _frame in 6:
		await get_tree().process_frame
	_dump_kinds(tower, target, "T0(=刚落门)")

	await get_tree().create_timer(
		TowerDescent3D.FLOW_ROOM_SPAWN_PAUSE_S + 1.2
	).timeout
	for _frame in 10:
		await get_tree().process_frame
	_dump_kinds(tower, target, "T1(=+1.7s)")

	var roster: Dictionary = {}
	var total := 0
	for value in tower._enemy_nodes_by_room.get(target.room_id, []):
		var enemy := value as Enemy3D
		if enemy == null or enemy.ai_state == "dead":
			continue
		total += 1
		var kind := str(enemy.enemy_kind)
		var cfg_type := str((enemy.enemy_data as Dictionary).get("enemy_type", "<无>"))
		if cfg_type != kind:
			print("KIND_MISMATCH 运行时=%s 配置=%s hp=%d" % [kind, cfg_type, enemy.max_hp])
		# 名字里带「僵尸/菌猪」的就是原生怪，不是 EGT 复刻怪 —— 直接打出来定位来源。
		if not kind.begins_with("egt_"):
			print(
				"ALIEN_ENEMY kind=%s cfg=%s name=%s ai=%s pos=%s"
				% [kind, cfg_type, str((enemy.enemy_data as Dictionary).get("name", "")),
					str((enemy.enemy_data as Dictionary).get("ai_type", "")), str(enemy.global_position)]
			)
		roster[kind] = int(roster.get(kind, 0)) + 1
		# 每一只都必须能查到 profile（否则是 `melee_chaser` 兜底，表现与数值全错）
		_check(Enemy3D.PROFILES.has(kind), "刷出的 %s 在 PROFILES 里没有行" % kind)
		_check(
			enemy.max_hp > 0 and enemy.move_speed > 0.05,
			"%s 的数值异常：hp=%d speed=%.2f" % [kind, enemy.max_hp, enemy.move_speed]
		)

	# 把本房编成逐盒展开打出来，与实际刷出的对照 —— 这是定位「数量对但种类错」的唯一方式。
	for placement_value in target.spawn_placements:
		var placement := placement_value as Dictionary
		var box_id := str(placement.get("box", ""))
		var box := SpawnBoxCatalog.load_box(box_id)
		var parts: Array[String] = []
		for spawn_value in (box.get("spawns", []) as Array):
			var spawn := spawn_value as Dictionary
			# `load_box()` 已把 `count` 规范成 `count_min` / `count_max`，
			# 读 `count` 恒得 0 —— 第一版就这么写的，打印出来全是 ×0。
			parts.append("%s×%s~%s(d%s)" % [
				str(spawn.get("type", "")),
				str(spawn.get("count_min", 0)),
				str(spawn.get("count_max", 0)),
				str(spawn.get("delay_sec", 0)),
			])
		print("  BOX %-26s %s" % [box_id, ", ".join(parts)])
	_check(total > 0, "进入战斗房后一只怪都没有")
	# 一只都没刷出来时，把三个「合法空房」的早退条件打出来 —— 否则只能靠猜。
	if total == 0:
		print(
			"EGT_RUNTIME_PROBE_DIAG spawn_boxes_only=%s peaceful=%s trigger=%s placements=%d"
			% [
				str(target.spawn_boxes_only),
				str(target.authored_layout_peaceful),
				str(tower._room_has_encounter_trigger(target)),
				(target.spawn_placements as Array).size() if target.spawn_placements != null else -1,
			]
		)
	var egt_count := 0
	for kind in roster.keys():
		if str(kind).begins_with("egt_"):
			egt_count += int(roster[kind])
	_check(
		egt_count > 0,
		"刷出的 %d 只里没有一只是 egt_*（enemy_pool 没生效？刷出：%s）" % [total, str(roster.keys())]
	)
	# 池子没生效时，把关卡规则的装载状态与池子实际内容打出来。
	if egt_count == 0:
		var rules: Dictionary = tower._monster_rules
		print(
			"EGT_RUNTIME_PROBE_POOL rules_keys=%s pool=%s theme=%s"
			% [
				str(rules.keys()),
				str((rules.get("enemy_pool", []) as Array).size()),
				str(tower.gameplay_theme != null),
			]
		)

	print(
		"EGT_RUNTIME_PROBE_DETAIL room=%s type=%s total=%d egt=%d roster=%s"
		% [target.room_id, str(target.room_type), total, egt_count, str(roster)]
	)
	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("EGT_RUNTIME_PROBE_OK 远征03 真实进房刷怪：全部为已注册怪种，且 egt_* 已进入刷怪池")
		get_tree().quit(0)
		return
	print("EGT_RUNTIME_PROBE_FAIL count=%d" % failures.size())
	for message in failures:
		print("  - %s" % message)
	get_tree().quit(1)


## 打印某房当前所有存活怪的 kind 分布。
##
## 为什么需要它：单次采样看到 `melee_chaser×2` 时，「编成里混进原生怪」与
## 「延迟出怪 / 分裂 / 补刷后来生成的」两种原因在日志里**长得一模一样**。
## 两次采样（落门瞬间 vs +1.7s）对比才能分开 —— 2026-10-29 就是靠这个定位的。
func _dump_kinds(tower, room, tag: String) -> void:
	var bag := {}
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var e := value as Enemy3D
		if e == null or e.ai_state == "dead":
			continue
		var k := str(e.enemy_kind)
		bag[k] = int(bag.get(k, 0)) + 1
	# 延迟出怪是「已预约、未实例化」：不计入 `_enemy_nodes_by_room`，
	# 只算存活节点会误判成「编成少出了几只」。把在途数一并打出来才对得上账。
	var pending_list: Variant = tower._pending_delayed_spawns.get(room.room_id, null)
	var pending := 0 if pending_list == null else (pending_list as Array).size()
	# 波次账面 vs 实际实例化：两者相等 ⇒ 少出发生在「开波之前」（编成/落点）；
	# 账面更大 ⇒ 是 `_spawn_enemy_batch` 逐条跳过（配置为空 / 落点不够）。
	var wave_total := int(tower._room_wave_totals.get(room.room_id, -1))
	var alive_n := int(tower._alive_by_room.get(room.room_id, -1))
	print(
		"  SAMPLE %s room=%s 存活=%s 延迟在途=%d 波次总数=%d 存活账=%d"
		% [tag, str(room.room_id), str(bag), pending, wave_total, alive_n]
	)
