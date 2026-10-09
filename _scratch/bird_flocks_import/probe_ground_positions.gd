extends Node
## 只读探针：按时间推进，dump 停留鸟群**每只鸟的世界坐标**，
## 用来证明「落地停留全程都在屋面内」（而不是靠肉眼看图猜）。

const OUTLINE := Rect2(-50.0, -35.0, 100.0, 80.0)


func _ready() -> void:
	var stage := TowerFloorStage3D.new()
	stage.configure(0, "rooftop", ["west"], [], false, Rect2())
	add_child(stage)
	await get_tree().process_frame
	var flock := stage.get_node_or_null("RooftopGroundBirdFlock") as Node3D
	if flock == null:
		print("GROUND_FLOCK_MISSING")
		get_tree().quit(1)
		return
	print("ANCHOR local=%s" % str(flock.position))
	var skeleton_root := flock.find_child("鸟群_整体移动缩放控制", true, false) as Node3D
	if skeleton_root == null:
		print("SKELETON_ROOT_MISSING")
		get_tree().quit(1)
		return
	for step in 13:
		var t := float(step) * 2.0
		if step > 0:
			await get_tree().create_timer(2.0).timeout
		var summary: Array[String] = []
		var min_y := INF
		var max_y := -INF
		var outside := 0
		for child in skeleton_root.get_children():
			var bird := child as Node3D
			if bird == null:
				continue
			var world := bird.global_position
			min_y = minf(min_y, world.y)
			max_y = maxf(max_y, world.y)
			if not OUTLINE.has_point(Vector2(world.x, world.z)):
				outside += 1
			summary.append("%s(%.1f,%.1f,%.1f)" % [bird.name.left(3), world.x, world.y, world.z])
		print("T=%5.1f y=[%6.2f,%6.2f] outside_roof=%d %s" % [t, min_y, max_y, outside, " ".join(summary)])
	print("GROUND_POS_DONE")
	get_tree().quit(0)
