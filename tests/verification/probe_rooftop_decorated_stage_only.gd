extends Node

# 只装配 TowerFloorStage3D（不起整座塔）的天台装饰重放探针。
# 装饰实例 120 件；其中绿化三件（花箱 / 大盆栽 / 小盆栽）登记 blocking
# ⇒ 运行时按实测可视包络各生成 **一个** BoxShape3D 代理挡玩家（业主 2026-09-21
# 「花盆和花圃没有阻挡」）。其余 100 件维持 visual_only（启用碰撞必须为 0）。
const EXPECTED_INSTANCES := 120
# = 布局源 BLOCKING_SLUGS 三件之和：flowerbox 8 + plant_large 6 + plant_small 6。
const EXPECTED_BLOCKING := 20
const BLOCKING_SLUGS := ["flowerbox", "plant_large", "plant_small"]
const ROOFTOP_BLOCKING_LAYER := 1

func _ready() -> void:
	var stage := TowerFloorStage3D.new()
	# 2026-09-22：configure() 第 7 参「立面让位侧」已随天台立面环整圈删除而作废。
	stage.configure(0, "rooftop", ["west"], [], false, Rect2())
	add_child(stage)
	await get_tree().process_frame
	var root := stage.find_child("FormalRooftopFacilities", false, false) as Node3D
	var failures: Array[String] = []
	if root == null:
		failures.append("FormalRooftopFacilities missing")
	else:
		if root.get_child_count() != EXPECTED_INSTANCES:
			failures.append("instance_count=%d expected=%d" % [root.get_child_count(), EXPECTED_INSTANCES])
		var blocking_hits := 0
		var collisions := 0
		for node in root.get_children():
			var shapes := _enabled_collision_shapes(node)
			collisions += shapes
			var slug := str(node.get_meta("component_slug", ""))
			if slug in BLOCKING_SLUGS:
				blocking_hits += 1
				if shapes != 1:
					failures.append("blocking %s enabled shapes=%d expected=1" % [node.name, shapes])
				var body := node.get_node_or_null("BlockingCollision") as StaticBody3D
				if body == null:
					failures.append("blocking %s missing BlockingCollision" % node.name)
				elif body.collision_layer != ROOFTOP_BLOCKING_LAYER:
					failures.append("blocking %s layer=%d expected=%d" % [node.name, body.collision_layer, ROOFTOP_BLOCKING_LAYER])
			elif shapes != 0:
				# 反向断言：visual_only 件不得带启用碰撞。
				failures.append("visual_only %s carries %d enabled collision shapes" % [node.name, shapes])
		if blocking_hits != EXPECTED_BLOCKING:
			failures.append("blocking instances=%d expected=%d" % [blocking_hits, EXPECTED_BLOCKING])
		if collisions != EXPECTED_BLOCKING:
			failures.append("enabled_collision_shapes=%d expected=%d (= blocking instances)" % [collisions, EXPECTED_BLOCKING])
		print("ROOFTOP_DECOR_STAGE_SAMPLE instances=%d blocking=%d collisions=%d" % [root.get_child_count(), blocking_hits, collisions])
	stage.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_DECORATED_STAGE_ONLY_OK instances=%d blocking=%d visual_collisions=0" % [EXPECTED_INSTANCES, EXPECTED_BLOCKING])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)

func _enabled_collision_shapes(root: Node) -> int:
	var count := 0
	if root is CollisionShape3D and not (root as CollisionShape3D).disabled:
		count += 1
	for child in root.get_children():
		count += _enabled_collision_shapes(child)
	return count
