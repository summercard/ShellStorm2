class_name VfxPlayerAimBeam3D
extends VfxEffectBase3D
## Persistent presentation only. Player3D owns visibility and supplies the clipped span.

@export_range(3.0, 5.0, 0.1) var length_m := 4.0
@export_range(0.025, 0.20, 0.005) var width_m := 0.105


var _span_m := 0.0
@onready var _ribbon: MeshInstance3D = $Ribbon


func _ready() -> void:
	# Follow the final socket transform, including motion applied outside physics.
	set_process(false)
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready() and visible:
		_sync_ribbon()


func set_span(span_m: float) -> void:
	if span_m <= 0.01:
		hide()
		return
	if not visible or not is_equal_approx(_span_m, span_m):
		_span_m = span_m
		_sync_ribbon()
		show()


func _sync_ribbon() -> void:
	var pose := global_transform
	var forward := -pose.basis.z.normalized()
	var across := forward.cross(Vector3.UP)
	if across.length_squared() < 0.0001:
		across = forward.cross(Vector3.RIGHT)
	across = across.normalized()
	# Strip the inherited scale, including the gun's squash/stretch during recoil.
	_ribbon.global_transform = Transform3D(
		Basis(across * width_m, forward * _span_m, across.cross(forward)),
		pose.origin + forward * (_span_m * 0.5)
	)
