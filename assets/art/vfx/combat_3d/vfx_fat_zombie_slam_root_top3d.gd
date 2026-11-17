class_name VfxFatZombieSlam3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## ENM-NORMAL-FAT-ZOMBIE21 的视觉砸地反馈。
## 由表现适配器消费 Enemy3D 状态后在源 F78 借出；不拥有伤害、碰撞或命中结算。
## DustSprite / RippleSprite 均为透明 Sprite3D，不创建球体、环体或其它模型几何。

const DEFAULT_LIFETIME := 0.78
const DUST_RISE_SEC := 0.24
const RIPPLE_END_SEC := 0.72
const DUST_START_SCALE := 0.78
const DUST_END_SCALE := 1.42
## v006 预览的可见外扩约 0.64m；正式范围 >= 2x，目标外径 2.80m。
const RIPPLE_START_RADIUS_M := 0.18
const RIPPLE_END_RADIUS_M := 1.40
const RIPPLE_START_ALPHA := 0.86
const RIPPLE_END_ALPHA := 0.0

@onready var _dust: Sprite3D = $DustSprite
@onready var _ripple: Sprite3D = $RippleSprite
@onready var _flame: Sprite3D = $FlameSprite

var _dust_material: StandardMaterial3D
var _ripple_material: StandardMaterial3D
var _flame_material: StandardMaterial3D
var _floor_y := 0.0

func _ready() -> void:
	_dust_material = _dust.material_override as StandardMaterial3D
	_ripple_material = _ripple.material_override as StandardMaterial3D
	_flame_material = _flame.material_override as StandardMaterial3D
	assert(_dust_material != null and _ripple_material != null and _flame_material != null, "Fat zombie slam materials missing")
	_dust_material = _dust_material.duplicate() as StandardMaterial3D
	_ripple_material = _ripple_material.duplicate() as StandardMaterial3D
	_flame_material = _flame_material.duplicate() as StandardMaterial3D
	_dust.material_override = _dust_material
	_ripple.material_override = _ripple_material
	_flame.material_override = _flame_material
	_dust.visible = false
	_ripple.visible = false
	_flame.visible = false

func _on_activate(world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	lifetime = DEFAULT_LIFETIME
	_floor_y = float(context.get("floor_y", world_pos.y))
	global_position = Vector3(world_pos.x, _floor_y + 0.012, world_pos.z)
	_dust.position = Vector3(0.0, 0.025, 0.0)
	_ripple.position = Vector3(0.0, 0.006, 0.0)
	_flame.position = Vector3(0.0, 0.045, 0.0)
	_dust.scale = Vector3.ONE * size * DUST_START_SCALE
	_ripple.scale = Vector3.ONE * size * RIPPLE_START_RADIUS_M
	_flame.scale = Vector3.ONE * size * 0.68
	_dust_material.albedo_color = Color(0.50, 0.43, 0.34, 0.82)
	_ripple_material.albedo_color = Color(0.66, 0.78, 0.42, RIPPLE_START_ALPHA)
	_flame_material.albedo_color = Color(1.0, 0.38, 0.08, 0.94)
	_flame_material.emission = Color(1.0, 0.12, 0.01, 1.0)
	_flame.visible = true
	_dust.visible = true
	_ripple.visible = true
	_on_tick(0.0, lifetime)

func _on_tick(elapsed: float, _total: float) -> void:
	var dust_t: float = clampf(elapsed / DUST_RISE_SEC, 0.0, 1.0)
	var dust_smooth: float = dust_t * dust_t * (3.0 - 2.0 * dust_t)
	_dust.position.y = 0.025 + 0.18 * dust_smooth
	_dust.scale = Vector3.ONE * effect_size * lerpf(DUST_START_SCALE, DUST_END_SCALE, dust_smooth)
	_dust_material.albedo_color.a = (1.0 - dust_t) * 0.82
	var flame_t: float = clampf(elapsed / 0.22, 0.0, 1.0)
	var flame_smooth: float = flame_t * flame_t * (3.0 - 2.0 * flame_t)
	_flame.position.y = 0.045 + 0.08 * flame_smooth
	_flame.scale = Vector3.ONE * effect_size * lerpf(0.68, 0.90, flame_smooth)
	_flame_material.albedo_color.a = (1.0 - flame_t) * 0.94
	var ripple_t: float = clampf(elapsed / RIPPLE_END_SEC, 0.0, 1.0)
	var ripple_smooth: float = ripple_t * ripple_t * (3.0 - 2.0 * ripple_t)
	var radius: float = lerpf(RIPPLE_START_RADIUS_M, RIPPLE_END_RADIUS_M, ripple_smooth)
	_ripple.scale = Vector3.ONE * effect_size * radius
	_ripple_material.albedo_color.a = lerpf(RIPPLE_START_ALPHA, RIPPLE_END_ALPHA, ripple_smooth)

func _on_lifetime_expired() -> void:
	_dust.visible = false
	_ripple.visible = false
	_flame.visible = false
	_dust_material.albedo_color.a = 0.0
	_ripple_material.albedo_color.a = 0.0
	_flame_material.albedo_color.a = 0.0

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
		"representation": "Sprite3D transparent PNG"
	}
