extends Node
## Owns transient camera feedback only. World camera owners compose look_offset
## before their existing constraints; standalone Player3D scenes use the same state.

const LOOK_DEAD_ZONE := 0.18 # fraction of half the shorter viewport dimension
const LOOK_FULL_DISTANCE := 0.90
const LOOK_MAX_M := 1.25
const LOOK_RESPONSE := 7.5
const SHAKE_DURATION := 0.24

var look_offset := Vector3.ZERO
var world_pose_managed := false
var suspended := false
var _player: Player3D
var _base_pose: Transform3D
var _shake_remaining := 0.0
var _shake_amplitude := 0.0
var _shake_clock := 0.0


func configure(player: Player3D) -> void:
	_player = player
	_base_pose = player.camera.transform
	process_physics_priority = 100


func request_hit(damage: int, maximum: int) -> void:
	if damage <= 0:
		return
	var severity := clampf(float(damage) / float(maxi(maximum, 1)), 0.0, 1.0)
	_shake_amplitude = maxf(_shake_amplitude, lerpf(0.065, 0.11, severity))
	_shake_remaining = SHAKE_DURATION
	_shake_clock = 0.0


func advance_look(delta: float, screen_delta: Vector2, viewport_size: Vector2,
		right: Vector3, up: Vector3, enabled: bool) -> void:
	var target := Vector3.ZERO
	var half_short_side := minf(viewport_size.x, viewport_size.y) * 0.5
	if enabled and half_short_side > 1.0 and screen_delta.is_finite():
		var distance := screen_delta.length() / half_short_side
		var weight := smoothstep(LOOK_DEAD_ZONE, LOOK_FULL_DISTANCE, distance)
		var direction := right * screen_delta.x - up * screen_delta.y
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			target = direction.normalized() * LOOK_MAX_M * weight
	look_offset = look_offset.lerp(target, 1.0 - exp(-LOOK_RESPONSE * maxf(delta, 0.0)))
	if look_offset.length_squared() < 0.0000001:
		look_offset = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _player == null or _player.camera == null:
		return
	var camera := _player.camera
	# Projection for aim/look never includes the cosmetic hit shake.
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	var viewport := _player.get_viewport()
	var rect := viewport.get_visible_rect()
	var pointer := viewport.get_mouse_position()
	var enabled := (camera.current and not suspended and not _player.input_locked
		and _player.current_hp > 0 and _player.uses_pointer_camera_aim()
		and rect.has_point(pointer) and DisplayServer.window_is_focused())
	var body_screen := camera.unproject_position(_player.global_position + Vector3.UP * 0.6)
	advance_look(delta, pointer - body_screen, rect.size,
		camera.global_basis.x, camera.global_basis.y, enabled)
	if not world_pose_managed and not suspended:
		camera.transform = _base_pose
		camera.global_position += look_offset
	if suspended or not camera.current:
		_shake_remaining = 0.0
		_shake_amplitude = 0.0
		return
	_shake_remaining = maxf(0.0, _shake_remaining - delta)
	_shake_clock += delta
	var envelope := pow(_shake_remaining / SHAKE_DURATION, 2.0)
	# Two deterministic frequencies give a sharp impact with a quick, soft tail.
	camera.h_offset = (cos(_shake_clock * 139.0) * 0.72
		+ cos(_shake_clock * 211.0) * 0.28) * _shake_amplitude * envelope
	camera.v_offset = sin(_shake_clock * 173.0 + 0.7) * _shake_amplitude * envelope * 0.72
	if _shake_remaining <= 0.0:
		_shake_amplitude = 0.0


func reset() -> void:
	look_offset = Vector3.ZERO
	_shake_remaining = 0.0
	_shake_amplitude = 0.0
	if _player != null and _player.camera != null:
		_player.camera.h_offset = 0.0
		_player.camera.v_offset = 0.0
