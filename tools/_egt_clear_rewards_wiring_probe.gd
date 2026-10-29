extends Node
## 一次性接线检查：确认 `clear_rewards` 真的从 level_plan 一路走到
## **房间记录**（`FloorPlanGenerator.generate_from_level_plan` → 每间房的 `reward_plan`）。
##
## 为什么单独查这一步：`_clear_reward_spec_for()` 编译正确、`resolve_clear()` 也解得开，
## 但两者之间还隔着"生成器有没有把它写进房间"这一跳。那跳断了的表现是
## 「探针全绿、游戏里清房什么都不掉」—— 本工程已经踩过一次同形状的坑
## （`spawn_boxes_only` 只写楼层顶层、房间记录里没有，于是回退公式刷怪）。

const LEVEL_ID := "expedition_03"


func _ready() -> void:
	var failures: Array[String] = []
	for seed_value in range(1, 5):
		var floor_source := FloorPlanGenerator.generate_from_level_plan(LEVEL_ID, 0, seed_value)
		if floor_source.is_empty():
			failures.append("seed %d 生成失败" % seed_value)
			continue
		var rooms := floor_source.get("rooms", []) as Array
		var with_clear := 0
		var peaceful_with_clear: Array[String] = []
		for value in rooms:
			var room := value as Dictionary
			var plan := room.get("reward_plan", {}) as Dictionary
			if not plan.has("clear"):
				continue
			with_clear += 1
			# 和平区不应有清房结算（走廊 / 入口 / 撤离 / 商店 / 宝箱）。
			if bool(room.get("authored_layout_peaceful", false)):
				peaceful_with_clear.append(str(room.get("room_id", "?")))
		print("seed %d：%d 间房，其中 %d 间带清房结算" % [seed_value, rooms.size(), with_clear])
		if with_clear <= 0:
			failures.append("seed %d 没有任何房间带 reward_plan.clear（注入没生效）" % seed_value)
		if not peaceful_with_clear.is_empty():
			failures.append("seed %d 的和平区被配了清房结算：%s"
				% [seed_value, str(peaceful_with_clear)])

	if failures.is_empty():
		print("EGT_CLEAR_REWARDS_WIRING_OK `clear_rewards` 已写入房间记录，和平区未被误配")
	else:
		print("EGT_CLEAR_REWARDS_WIRING_FAIL：")
		for line in failures:
			print("  - ", line)
	get_tree().quit(0)
