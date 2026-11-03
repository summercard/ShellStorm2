class_name ReactiveLamp3D
extends ReactiveProp3D

const FIRE = preload("res://src/world3d/LampFirePatch3D.gd")
const WARM_LIGHT := Color(1.0, 0.64, 0.28)
@export var fire_radius := 1.25
@export var fire_damage := 10
var fire_expires_at := 0.0
var _fire: LampFirePatch3D

func _ready() -> void:
	super._ready()
	# Only the glowing shade receives this local material override; brass stays intact.
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface) as StandardMaterial3D
			if source == null or not source.emission_enabled:
				continue
			var warm := source.duplicate() as StandardMaterial3D
			warm.albedo_color = Color(1.0, 0.78, 0.46)
			warm.emission = Color(1.0, 0.55, 0.18)
			mesh.set_surface_override_material(surface, warm)

func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO, _knockback := 0.0) -> void:
	if amount > 0 and state not in ["burning", "spent"]:
		_explode(true)

func _on_drop_landed() -> void:
	_explode(true)

func _explode(play_burst: bool) -> void:
	if state in ["burning", "spent"]:
		return
	_drop_active = false
	current_hp = 0
	_visual.visible = false
	_body.set_deferred("collision_layer", 0)
	_disable_attached_lights()
	set_physics_process(false)
	state = "burning"
	if play_burst:
		fire_expires_at = Time.get_unix_time_from_system() + FIRE.BURN_SECONDS
	if fire_expires_at > Time.get_unix_time_from_system():
		_fire = FIRE.new() as LampFirePatch3D
		_fire.radius = fire_radius
		_fire.damage = fire_damage
		_fire.expires_at = fire_expires_at
		# Keep the patch on the real walking surface, including nonzero tower floors.
		var point := global_position
		point.y = _floor_y_at(point, supporting_furniture._body.get_rid() if is_instance_valid(supporting_furniture) else _body.get_rid())
		_fire.position = to_local(point)
		add_child(_fire)
		_fire.top_level = true
		_fire.global_transform = Transform3D(Basis.IDENTITY, point)
		_fire.extinguished.connect(_on_extinguished)
		if play_burst:
			_fire.burst()
	else:
		state = "spent"
	if play_burst:
		state_changed.emit(self)

func _on_extinguished() -> void:
	state = "spent"
	_fire = null
	state_changed.emit(self)

func export_prop_state() -> Dictionary:
	var result := super.export_prop_state()
	result["fire_expires_at"] = fire_expires_at
	return result

func restore_prop_state(data: Dictionary) -> void:
	var wanted := str(data.get("state", "intact"))
	if wanted in ["burning", "spent"]:
		fire_expires_at = float(data.get("fire_expires_at", 0.0))
		_restore_pose(data)
		if state not in ["burning", "spent"]:
			_explode(false)
		return
	super.restore_prop_state(data)
