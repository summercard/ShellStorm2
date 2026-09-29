extends SceneTree
## 临时探针：静态场景坐标系与生成器产出的对应关系。
## 目标：确认静态场景烘的是「哪个朝向下的房间局部坐标」，据此定出整体旋转量。

const GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const LEVEL := "expedition_01"
const STATIC_DIR := (
	"res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/"
)


func _basis_names(basis: Basis) -> String:
	var parts: Array[String] = []
	for axis in [basis.x, basis.y, basis.z]:
		parts.append("(%.2f,%.2f,%.2f)" % [axis.x, axis.y, axis.z])
	return " ".join(parts)


func _initialize() -> void:
	for run_seed in [1, 7, 12345]:
		var plan: Dictionary = GENERATOR.generate_from_level_plan(LEVEL, 0, run_seed)
		if plan.is_empty():
			print("seed %d -> 生成失败" % run_seed)
			continue
		for value in plan.get("rooms", []):
			var room := value as Dictionary
			if str(room.get("key", "")) != "room_01":
				continue
			var pos := room.get("position", Vector2.ZERO) as Vector2
			var dim := room.get("dimensions", Vector2.ZERO) as Vector2
			var insts := room.get("authored_layout_instances", []) as Array
			print("--- seed %d  room_01  pos=(%.2f,%.2f) rot=%.0f dims=(%.1f,%.1f) 实例=%d" % [
				run_seed, pos.x, pos.y, float(room.get("rotation_deg", 0.0)), dim.x, dim.y,
				insts.size(),
			])
			var shown := 0
			for item in insts:
				var inst := item as Dictionary
				if str(inst.get("slot_role", "")) != "solid_wall" and str(inst.get("slot_role", "")) != "door_wall":
					continue
				if shown >= 4:
					break
				var v := inst.get("position", Vector3.ZERO) as Vector3
				print("      %s  %s  pos=(%.2f,%.2f,%.2f)" % [
					str(inst.get("slot_role", "")), str(inst.get("name", "")),
					v.x, v.y, v.z,
				])
				shown += 1

	var packed := load(STATIC_DIR + "f00_room_01_static_layout.tscn") as PackedScene
	if packed == null:
		print("静态场景加载失败")
		quit(1)
		return
	var node := packed.instantiate() as Node3D
	print("\n=== 静态场景 f00_room_01 ===")
	print("根 transform origin=", node.transform.origin, " basis=", _basis_names(node.transform.basis))
	print("meta room_id=", str(node.get_meta("room_id", "-")),
		" instance_total=", int(node.get_meta("layout_instance_total", -1)))
	var shown_walls := 0
	var child_total := 0
	for child in node.get_children():
		if not (child is Node3D):
			continue
		child_total += 1
		var c3 := child as Node3D
		var tag := str(c3.get_meta("authored_slot_role", c3.get_meta("slot_role", "-")))
		if shown_walls < 5 and (tag == "solid_wall" or tag == "door_wall"):
			print("   %-12s %-28s pos=(%.2f,%.2f,%.2f) basis=%s" % [
				tag, c3.name, c3.position.x, c3.position.y, c3.position.z,
				_basis_names(c3.transform.basis),
			])
			shown_walls += 1
	print("   Node3D 直接子节点 =", child_total)
	var port_root := node.find_child("ConnectionPorts", true, false) as Node3D
	if port_root != null:
		for c in port_root.get_children():
			print("   port %s  pos=%s  outward=%s  target=%s" % [
				str(c.get_meta("port_id", "?")),
				str(c.get_meta("position_m", c.position)),
				str(c.get_meta("outward", "?")),
				str(c.get_meta("target_room_id", "")),
			])
	else:
		print("   没有 ConnectionPorts 容器")
	node.free()
	print("\nPROBE_DONE")
	quit(0)
