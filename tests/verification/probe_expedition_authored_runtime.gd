extends Node
## 临时探针：远征01 运行时装配取证（第 4 环通用壳体组件 + 第 5 环 Boss 专属件）。
## ① 逐房：authored 壳体是否成立、实例计数、未解析件、门墙/委派侧；
##    并核对新不变量 `door_wall_sides ∪ delegated_door_sides == doors`；
## ② Boss 房：6 件专属件是否全落地、**悬空高度是否保住**（主屏 3.805 / 北墙标识 7.4461）；
## ③ 物理：逐房四向射线，门洞必须可穿（不撞墙）、非门侧必须撞墙；
## ④ 成本：塔楼子树节点总数（地砖是逐件实例化 ⇒ 这是性能信号的直接读数）。
## 用完即删。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const EXPECTED_EXCLUSIVE_COUNT := 6
## 摆位源 position_m 里 bz 是高度；这两件是明确的悬空件，用来证明 y 没被归零。
const SUSPENDED_HEIGHTS := {
	"EXCL_MAIN_FAULT_SCREEN": 3.805,
	"EXCL_NORTH_WALL_TYPOGRAPHY": 7.4461,
}
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
	var boss_room: DungeonRoom3D = null
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room == null:
			continue
		var shell := bool(room.get_meta("authored_layout_shell", false))
		var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		var total := -1
		if art_root != null:
			total = int(art_root.get_meta("layout_instance_total", -1))
		var unresolved := room.get_meta("authored_layout_unresolved_instances", []) as Array
		var delegated := room.get_meta("authored_layout_delegated_door_sides", []) as Array
		var door_walls := room.get_meta("authored_layout_door_wall_sides", []) as Array
		var wall_sides := room.get_meta("authored_layout_wall_sides", []) as Array
		var exclusive := int(room.get_meta("authored_layout_exclusive_count", 0))
		unresolved_total += unresolved.size()
		if shell:
			authored_rooms += 1
		if room.room_id == "boss":
			boss_room = room
		print("  %-11s authored=%-5s total=%-5d C=%s W=%s DW=%s DL=%s E=%d doors=%s" % [
			room.room_id, str(shell), total,
			str(room.get_meta("authored_layout_corner_count", "-")),
			str(wall_sides), str(door_walls), str(delegated), exclusive, str(room.doors),
		])
		if shell and not unresolved.is_empty():
			_fail("%s 有 %d 件未解析：%s" % [room.room_id, unresolved.size(), str(unresolved)])
		if not shell:
			continue
		# 不变量：每扇门要么本房有门墙承接，要么委派给邻房 —— 两集合的并必须覆盖 doors。
		var covered: Array[String] = []
		for side_value in door_walls:
			covered.append(str(side_value))
		for side_value in delegated:
			var side := str(side_value)
			if side not in covered:
				covered.append(side)
		var missing: Array[String] = []
		for side in room.doors:
			if str(side) not in covered:
				missing.append(str(side))
		if not missing.is_empty():
			_fail(
				"%s 门向 %s 里有 %s 既无本房门墙也未委派（门洞没人承接）"
				% [room.room_id, str(room.doors), str(missing)]
			)

	print("")
	print("=== Boss 房专属件（第 5 环）===")
	if boss_room == null:
		_fail("找不到 Boss 房节点")
	else:
		var art_root := boss_room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		var spawned := 0
		if art_root != null:
			for value in art_root.find_children("*", "Node3D", true, false):
				var module := value as Node3D
				if str(module.get_meta("authored_slot_role", "")) != "exclusive_component":
					continue
				spawned += 1
				var want: Variant = SUSPENDED_HEIGHTS.get(module.name, null)
				var mark := ""
				if want != null:
					mark = "  ← 悬空件，期望底面 y=%.3f" % float(want)
					if absf(module.position.y - float(want)) > 0.01:
						_fail(
							"%s 的悬空高度 = %.3f，期望 %.3f（y 被归零了）"
							% [module.name, module.position.y, float(want)]
						)
				print("  %-28s y=%-8.3f pos=%s%s" % [
					module.name, module.position.y, str(module.position), mark
				])
		print("  专属件落地数 = %d / %d" % [spawned, EXPECTED_EXCLUSIVE_COUNT])
		if spawned != EXPECTED_EXCLUSIVE_COUNT:
			_fail("Boss 房专属件数 = %d，期望 %d" % [spawned, EXPECTED_EXCLUSIVE_COUNT])

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
