extends Node
## 临时探针：远征01 关卡怪物掉落表里的通用弹药发数（2026-09-27 数值调整验证）。
## 只读 L1 数据 + 纯逻辑解析奖励，不加载场景、不写存档。
## 判据：三种已配置怪的备弹加成必须落在 30–50。

const _MONSTER_DROP_TABLE := preload("res://src/rewards/MonsterDropTable.gd")
const _RUNTIME_COORDINATOR := preload("res://src/rewards/RuntimeRewardCoordinator.gd")
const _SINK := preload("res://src/rewards/RewardSink.gd")

const LEVEL_PLAN := "res://source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json"
const MONSTERS := ["melee_chaser", "ranged_caster", "exploder"]
const SAMPLES := 120


func _ready() -> void:
	var file := FileAccess.open(LEVEL_PLAN, FileAccess.READ)
	if file == null:
		push_error("无法读取 %s" % LEVEL_PLAN)
		get_tree().quit(1)
		return
	var level_plan := JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	var table := level_plan.get("monster_drop_table", {}) as Dictionary
	var compiled := _MONSTER_DROP_TABLE.compile("expedition_01", table)
	print("compile_ok=%s rows=%d monsters=%d errors=%s" % [
		str(compiled.get("ok", false)),
		int(compiled.get("row_count", 0)),
		int(compiled.get("monster_count", 0)),
		str(compiled.get("errors", [])),
	])
	var failures: Array[String] = []
	var coordinator := _RUNTIME_COORDINATOR.new()
	coordinator.configure(77001199)
	var configured := coordinator.configure_level_drop_table("expedition_01", table)
	if not bool(configured.get("ok", false)):
		failures.append("关卡掉落表装载失败：%s" % str(configured.get("errors", [])))
	for monster_id in MONSTERS:
		var low := 1 << 30
		var high := -1
		var ammo_hits := 0
		for index in SAMPLES:
			var report := coordinator.resolve_kill({}, {
				"enemy_type": monster_id, "floor": 1, "loot_table": "loot_floor_1_2",
			}, "ammo_probe:%s:%d" % [monster_id, index])
			for value in _SINK.materialize_ground_items(report.get("grants", [])):
				var item := value as Dictionary
				if str(item.get("id", "")) != "item_ammo_pack":
					continue
				ammo_hits += 1
				low = mini(low, int(item.get("count", 0)))
				high = maxi(high, int(item.get("count", 0)))
		print("AMMO %s hits=%d min=%s max=%s" % [
			monster_id, ammo_hits, str(low), str(high),
		])
		if ammo_hits <= 0:
			failures.append("%s 在 %d 次击杀里一次备弹都没掉" % [monster_id, SAMPLES])
			continue
		if low < 30 or high > 50:
			failures.append("%s 备弹发数越界：min=%d max=%d（应为 30–50）" % [monster_id, low, high])
	if failures.is_empty():
		print("AMMO_RANGE_PROBE_OK: 远征01 关卡表三种怪的备弹加成全部落在 30–50")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
