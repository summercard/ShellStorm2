extends Node
## 一次性探针：枚举各层安全房（STAIR_LOBBY）的门朝向组合。
## 纯数据，不实例化场景树里的楼层，只跑 FloorPlanGenerator + 与运行时同源的
## 门方向推导规则，用于确认 v007 单一布局能否通用。
## 只读，不修改任何游戏状态。

const FLOOR_PLAN_GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const FLOOR_HEIGHT := 12.0
const DEEPEST := 78


func _ready() -> void:
	for run_seed in [990095, 12345, 777]:
		print("")
		print("================ run_seed=", run_seed, " ================")
		var prev_exit_side := ""
		for displayed in range(98, DEEPEST - 1, -1):
			var sequence_index := 99 - displayed
			var physical_floor_index := sequence_index + 1
			var stair_side := "east" if sequence_index % 2 == 1 else "west"
			var plan := FLOOR_PLAN_GENERATOR.generate({
				"run_seed": run_seed,
				"floor_number": displayed,
				"floor_index": physical_floor_index,
				"sequence_index": sequence_index,
				"entry_side": stair_side,
				"boss_floor": displayed % 5 == 0,
			})
			var entry := _spec(plan, "entry")
			var hub := _spec(plan, "hub")
			if entry.is_empty() or hub.is_empty():
				print("  ", displayed, "F  缺少 entry/hub")
				continue
			var entry_world := _world(plan, entry)
			var hub_world := _world(plan, hub)
			var front := _direction_between(entry_world, hub_world)
			var stair_door := "east" if displayed == 98 else str(prev_exit_side)
			var door_pair := [front, stair_door]
			door_pair.sort()
			print(
				"  %dF  seq=%d entry_side=%-5s variant=%-11s entry=(%.1f,%.1f) hub=(%.1f,%.1f) front=%-5s stair=%-5s  doors=[%s]"
				% [
					displayed, sequence_index, stair_side,
					str(plan.get("layout_variant", "?")),
					(entry.get("position", Vector2.ZERO) as Vector2).x,
					(entry.get("position", Vector2.ZERO) as Vector2).y,
					(hub.get("position", Vector2.ZERO) as Vector2).x,
					(hub.get("position", Vector2.ZERO) as Vector2).y,
					front, stair_door, ", ".join(door_pair),
				]
			)
			prev_exit_side = str(plan.get("exit_side", "west"))
	get_tree().quit(0)


func _spec(plan: Dictionary, key: String) -> Dictionary:
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		if str(spec.get("key", "")) == key:
			return spec
	return {}


func _world(plan: Dictionary, spec: Dictionary) -> Vector3:
	var planar := spec.get("position", Vector2.ZERO) as Vector2
	return Vector3(planar.x, -FLOOR_HEIGHT * float(int(plan.get("floor_index", 2))), planar.y)


func _direction_between(from: Vector3, to: Vector3) -> String:
	var delta := to - from
	if absf(delta.x) >= absf(delta.z):
		return "east" if delta.x >= 0.0 else "west"
	return "south" if delta.z >= 0.0 else "north"
