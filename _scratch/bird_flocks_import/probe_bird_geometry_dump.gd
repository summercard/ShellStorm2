extends Node
## 只读探针：dump 跨塔吊桥 / 塔2 / 天台 / 两套鸟群的**运行时世界坐标**，
## 用来确定「塔2上方 + 吊桥中间」和「100F 天台北侧东面」的真实落点。

const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"


func _ready() -> void:
	var route_ps := load(ROUTE) as PackedScene
	var route := route_ps.instantiate() as Node3D
	add_child(route)
	await get_tree().process_frame
	print("ROUTE_ROT=%s" % str(route.rotation_degrees))
	for name in ["Tower2", "Tower3", "Bridge", "FlybyBirdFlock"]:
		var node := route.get_node_or_null(name) as Node3D
		if node == null:
			print("ROUTE %s MISSING" % name)
			continue
		print("ROUTE %s local=%s global=%s" % [name, str(node.position), str(node.global_position)])
	var bridge := route.get_node_or_null("Bridge") as Node3D
	if bridge != null:
		for child in bridge.get_children():
			var c := child as Node3D
			print("  BRIDGE %s local=%s global=%s" % [c.name, str(c.position), str(c.global_position)])
	var guard := route.get_node_or_null("Collision") as Node3D
	if guard != null:
		for child in guard.get_children():
			var c := child as Node3D
			print("  GUARD %s global=%s" % [c.name, str(c.global_position)])
	route.queue_free()
	await get_tree().process_frame

	var tower_ps := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := tower_ps.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	var player := tower.get("player") as Node3D
	if player != null:
		print("PLAYER spawn global=%s" % str(player.global_position))
	var rooftop := tower.get_node_or_null("Blocks/Rooftop") as Node3D
	if rooftop != null:
		print("BLOCK Rooftop global=%s" % str(rooftop.global_position))
	var mounted_route := tower.get_node_or_null("Blocks/Rooftop/CrossTowerRoute") as Node3D
	if mounted_route != null:
		print("MOUNTED_ROUTE global=%s" % str(mounted_route.global_position))
		var mf := mounted_route.get_node_or_null("FlybyBirdFlock") as Node3D
		if mf != null:
			print("MOUNTED_FLYBY local=%s global=%s visible=%s" % [str(mf.position), str(mf.global_position), str(mf.is_visible_in_tree())])
	for node in tower.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script()
		if script != null and str(script.resource_path).ends_with("TowerFloorStage3D.gd") and int(node.get("floor_index")) == 0:
			print("ROOFTOP_STAGE global=%s" % str((node as Node3D).global_position))
			var gb := node.get_node_or_null("RooftopGroundBirdFlock") as Node3D
			if gb != null:
				print("ROOFTOP_GROUND_BIRDS local=%s global=%s visible=%s" % [str(gb.position), str(gb.global_position), str(gb.is_visible_in_tree())])
			break
	print("DUMP_DONE")
	get_tree().quit(0)
