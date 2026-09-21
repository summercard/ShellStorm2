extends Node3D


func _ready() -> void:
	var rows := [[90.0, 0.0], [90.0, 90.0], [90.0, -90.0], [-90.0, 0.0]]
	for a in rows:
		var tip: float = deg_to_rad(float(a[0]))
		var yaw: float = deg_to_rad(float(a[1]))
		var b := Basis.from_euler(Vector3(tip, yaw, 0.0), EULER_ORDER_YXZ)
		print(
			"G_ORDER tip=%s yaw=%s  +X->%s  +Y->%s  +Z->%s"
			% [a[0], a[1], _r(b.x), _r(b.y), _r(b.z)]
		)
	get_tree().quit()


func _r(v: Vector3) -> String:
	return "(%.4f,%.4f,%.4f)" % [v.x, v.y, v.z]
