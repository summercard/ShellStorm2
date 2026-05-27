extends Node


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_bullet_trail(failures)
	_finish(failures)


func _verify_bullet_trail(failures: Array[String]) -> void:
	var bullet_scene: PackedScene = load("res://scenes/Bullet.tscn") as PackedScene
	if bullet_scene == null:
		failures.append("Bullet scene does not load")
		return
	var bullet := bullet_scene.instantiate()
	add_child(bullet)
	if not bullet.has_method("fire"):
		failures.append("Bullet has no fire method")
		bullet.queue_free()
		return
	bullet.call("fire", Vector2(300, 200), Vector2.RIGHT, 650.0, 8, false)
	for i in 4:
		await get_tree().process_frame
	var trail := bullet.get("_trail_line") as Line2D
	if trail == null:
		failures.append("Bullet did not create a Line2D trail")
	else:
		for point in trail.points:
			if absf(point.x) > 160.0 or absf(point.y) > 24.0:
				failures.append("Bullet trail uses world-space or rotated points instead of local tail points")
				break
	bullet.queue_free()


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("BULLET_TRAIL_OK: bullet trail stays in local tail space")
		get_tree().quit(0)
	else:
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)
