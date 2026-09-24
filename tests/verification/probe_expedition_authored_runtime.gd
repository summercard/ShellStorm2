extends Node
## 临时探针：远征01 运行时装配取证（第 4 环通用壳体组件）。
## ① 逐房：authored 壳体是否成立、实例计数、未解析件、门墙/委派侧；
## ② 物理：逐房四向射线，门洞必须可穿（不撞墙）、非门侧必须撞墙；
## ③ 成本：塔楼子树节点总数（地砖是逐件实例化 ⇒ 这是性能信号的直接读数）。
## 用完即删。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SIDE_DIRS := {
	"north": Vector3(0, 0, -1),
	"south": Vector3(0, 0, 1),
	"west": Vector3(-1, 0, 0),
	"east": Vector3(1, 0, 0),
}
const SIDES: Array[String] = ["north", "south", "west", "east"]

var failures: Array[String] = []


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame

	var conflicts := tower.get("_floor_layout_plan_conflicts") as Array
	print("=== 层规划冲突（%d）===" % conflicts.size())
	for value in conflicts:
		print("  ! %s" % str(value))

	print("")
	print("=== 逐房授权壳体 ===")
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	var authored_rooms := 0
	var unresolved_total := 0
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room == null:
			continue
		var shell := bool(room.get_meta("authored_layout_shell", false))
		var total := int(room.get_meta("layout_instance_total", -1))
		var unresolved := room.get_meta("authored_layout_unresolved_instances", []) as Array
		var delegated := room.get_meta("authored_layout_delegated_door_sides", []) as Array
		var door_walls := room.get_meta("authored_layout_door_wall_sides", []) as Array
		var wall_sides := room.get_meta("authored_layout_wall_sides", []) as Array
		unresolved_total += unresolved.size()
		if shell:
			authored_rooms += 1
		print("  %-11s authored=%-5s total=%-5d C=%s W=%s DW=%s DL=%s doors=%s" % [
			room.room_id, str(shell), total,
			str(room.get_meta("authored_layout_corner_count", "-")),
			str(wall_sides), str(door_walls), str(delegated), str(room.doors),
		])
		if shell and not unresolved.is_empty():
			_fail("%s 有 %d 件未解析：%s" % [room.room_id, unresolved.size(), str(unresolved)])

	print("")
	print("=== 物理：四向 20m 射线（门侧应可穿到邻房，非门侧应撞墙）===")
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room == null:
			continue
		var center := room.global_position
		var origin := center + Vector3(0, 1.5, 0)
		var line := "  %-11s" % room.room_id
		for side in SIDES:
			var hit := _cast(origin, origin + (SIDE_DIRS[side] as Vector3) * 20.0)
			var distance := -1.0
			if not hit.is_empty():
				distance = (hit["position"] as Vector3).distance_to(origin)
			line += "  %s=%s" % [
				side.substr(0, 1).to_upper(),
				("%.1fm" % distance) if distance >= 0.0 else "×",
			]
		print(line)

	var node_total := _count_nodes(tower)
	print("")
	print("=== 成本 ===")
	print("塔楼子树节点总数 = %d" % node_total)
	print("authored 房 = %d / 13   未解析件合计 = %d" % [authored_rooms, unresolved_total])

	if failures.is_empty():
		print("\nPROBE_OK")
		get_tree().quit(0)
	else:
		print("\nPROBE_FAIL count=%d" % failures.size())
		for line in failures.slice(0, 20):
			print("  !! %s" % line)
		get_tree().quit(1)


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)


func _fail(message: String) -> void:
	failures.append(message)
