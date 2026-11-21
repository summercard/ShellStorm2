class_name VfxFatZombieSlam3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## 由胖子表现适配器在源 F78 播放；Enemy3D 持有伤害。保留原贴地波纹。

const DEFAULT_LIFETIME := 0.78
const RIPPLE_END_SEC := 0.72
const RIPPLE_START_RADIUS_M := 0.18
const RIPPLE_END_RADIUS_M := 1.40
const RIPPLE_START_ALPHA := 0.86

@onready var _ripple: Sprite3D = $RippleSprite
@onready var _dust: Node3D = $LibraryDust
@onready var _flame: Node3D = $LibraryFlame
var _ripple_material: StandardMaterial3D

func _enter_tree() -> void:
	LibraryVfxAdapter3D.prepare_visual($LibraryDust, false)
	LibraryVfxAdapter3D.prepare_visual($LibraryFlame, false)

func _ready() -> void:
	_ripple_material = _ripple.material_override.duplicate() as StandardMaterial3D
	_ripple.material_override = _ripple_material
	_ripple.hide()

func _on_activate(world_pos: Vector3, _color: Color, size: float, context: Dictionary) -> void:
	lifetime = DEFAULT_LIFETIME
	global_position = Vector3(world_pos.x, float(context.get("floor_y", world_pos.y)) + 0.012, world_pos.z)
	_ripple.show()
	LibraryVfxAdapter3D.play_visual(_dust, size * 0.72, 7801)
	LibraryVfxAdapter3D.play_visual(_flame, size * 0.64, 7802)
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:
	var ripple_t := smoothstep(0.0, RIPPLE_END_SEC, elapsed)
	_ripple.scale = Vector3.ONE * effect_size * lerpf(RIPPLE_START_RADIUS_M, RIPPLE_END_RADIUS_M, ripple_t)
	_ripple_material.albedo_color.a = RIPPLE_START_ALPHA * (1.0 - ripple_t)

func _on_lifetime_expired() -> void:
	LibraryVfxAdapter3D.stop_visual(_dust)
	LibraryVfxAdapter3D.stop_visual(_flame)
	_ripple.hide()
	_ripple_material.albedo_color.a = 0.0

func get_presentation_snapshot() -> Dictionary:
	return {
		"asset_id": "VFX-FAT-ZOMBIE-SLAM-3D",
		"source_frame": 78,
		"source_fps": 60,
		"radius_formula": "r(t)=r0+(r1-r0)*smoothstep(0,t_end,t)",
		"radius_start_m": RIPPLE_START_RADIUS_M,
		"radius_end_m": RIPPLE_END_RADIUS_M,
		"diameter_end_m": RIPPLE_END_RADIUS_M * 2.0,
		"alpha_formula": "alpha(t)=alpha0*(1-smoothstep(0,t_end,t))",
		"damage_owner": "Enemy3D",
		"representation": "Library dust and flame + Sprite3D ripple",
	}
