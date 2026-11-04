class_name VfxBulletElectric3D
extends VfxEffectBase3D

const VISUAL_SIZE_MULTIPLIER := 2.0
const PROJECTILE_LIGHT_ENERGY := 0.85
const BODY_LIGHT_ENERGY := 1.05
const PROJECTILE_LIGHT_RANGE := 2.6
const BODY_LIGHT_RANGE := 3.0

@onready var _arcs: Array[Node3D] = [$Arc0, $Arc1, $Arc2]
@onready var _light: OmniLight3D = $ElectricLight
var _projectile := false

func _on_configure(context: Dictionary) -> void:
	_projectile = bool(context.get("projectile", false))
	# A projectile owns its visual lifetime. The player's root timer owns the body effect.
	lifetime = 60.0 if _projectile else maxf(0.05, float(context.get("duration", 1.0))) + 0.10

func _on_activate(_position: Vector3, _color: Color, _size: float, _context: Dictionary) -> void:
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:
	var size := effect_size * VISUAL_SIZE_MULTIPLIER
	_light.position = Vector3.ZERO if _projectile else Vector3.UP * 0.73 * effect_size
	_light.omni_range = (PROJECTILE_LIGHT_RANGE if _projectile else BODY_LIGHT_RANGE) * effect_size
	_light.light_energy = (PROJECTILE_LIGHT_ENERGY if _projectile else BODY_LIGHT_ENERGY) * (0.90 + 0.10 * sin(elapsed * 28.0))
	_light.visible = true
	for index in _arcs.size():
		var arc := _arcs[index]
		var pulse := 0.88 + 0.12 * sin(elapsed * 36.0 + index * 2.1)
		arc.visible = index == 0 or sin(elapsed * 25.0 + index * 2.0) > -0.45
		if _projectile:
			arc.position = Vector3.ZERO
			arc.rotation = Vector3(0.0, 0.0, elapsed * 12.0 + index * 1.8)
			arc.scale = Vector3.ONE * size * pulse
		else:
			var angle := elapsed * 7.0 + TAU * float(index) / 3.0
			arc.position = Vector3(sin(angle) * 0.43 * size, 0.73 * effect_size, cos(angle) * 0.43 * size)
			arc.rotation = Vector3(1.22 + 0.13 * sin(angle * 2.0), angle, 0.15)
			arc.scale = Vector3(2.4, 2.4, 2.9) * size * pulse

func deactivate() -> void:
	# Keep this child allocated for the next projectile-pool checkout.
	_active = false
	_on_lifetime_expired()
	hide()
	set_process(false)

func _on_lifetime_expired() -> void:
	_light.light_energy = 0.0
	_light.visible = false

func activate(world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	set_process(true)
	super.activate(world_position, color, size, context)
