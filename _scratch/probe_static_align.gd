extends SceneTree
## 临时探针：静态场景 ↔ 本局清单的对齐诊断。
## 输出每个房间的「清单条目数 / 场景实例数 / 同名配对率 / 需施加的旋转」，以及
## 场景里查无此项的清单条目（= 烘焙时未生成的那些槽位）。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LEVEL := "expedition_01"
const DIR := (
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/"
)


func _initialize() -> void:
	for run_seed in [1, 7, 12345]:
		var plan: Dictionary = GENERATOR.generate_from_level_plan(LEVEL, 0, run_seed)
		if plan.is_empty():
			print("seed %d 生成失败" % run_seed)
			continue
		print("===== run_seed %d" % run_seed)
		for value in plan.get("rooms", []):
			var room := value as Dictionary
			var rid := str(room.get("key", ""))
			var path := DIR + "f00_%s_static_layout.tscn" % rid
			if not ResourceLoader.exists(path):
				print("  %-11s 无静态场景" % rid)
				continue
			var packed := load(path) as PackedScene
			var node := packed.instantiate() as Node3D
			var insts := room.get("authored_layout_instances", []) as Array
			var by_name := {}
			for child in node.get_children():
				if child is Node3D:
					by_name[str(child.name)] = child
			var votes := {}
			var matched := 0
			var missing_door_roles := 0
			for item in insts:
				var inst := item as Dictionary
				var inst_name := str(inst.get("name", ""))
				if inst_name.is_empty() or not by_name.has(inst_name):
					if str(inst.get("slot_role", "")) in ["door_wall", "solid_wall"]:
						missing_door_roles += 1
					continue
				matched += 1
				var local_position := inst.get("position", Vector3.ZERO) as Vector3
				var scene_position := (by_name[inst_name] as Node3D).position
				if Vector2(local_position.x, local_position.z).length() < 1.0:
					continue
				if Vector2(scene_position.x, scene_position.z).length() < 1.0:
					continue
				var raw := rad_to_deg(
					atan2(scene_position.z, scene_position.x)
					- atan2(local_position.z, local_position.x)
				)
				var bucket := int(round(wrapf(raw, -180.0, 180.0) / 90.0)) * 90
				votes[bucket] = int(votes.get(bucket, 0)) + 1
			var best := 0
			var best_count := 0
			for bucket in votes:
				if int(votes[bucket]) > best_count:
					best_count = int(votes[bucket])
					best = int(bucket)
			var door_nodes: Array[String] = []
			for child in node.get_children():
				if not (child is Node3D):
					continue
				var c3 := child as Node3D
				if c3.scene_file_path.contains("wall_door"):
					door_nodes.append("%s@(%.2f,%.2f)" % [c3.name, c3.position.x, c3.position.z])
			print("  %-11s 清单=%3d 场景=%3d 配对=%3d 缺槽=%2d delta=%4d 票=%s 门墙件=%s" % [
				rid, insts.size(), node.get_child_count(), matched, missing_door_roles,
				best, str(votes), str(door_nodes),
			])
			node.free()
	quit(0)
