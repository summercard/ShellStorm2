class_name VfxMonsterRoarIcon3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-16 / VFX-MONSTER-ROAR-ICON-3D 怪物启动吼叫头顶图标
##
## 用途：怪物从 `idle / patrol` 进入攻击前的「启动过程」，转向玩家之后头顶弹出的
## 一次性吼叫提示（见 docs/v0.1/06A_怪物AI系统完整设计_评审稿.md §6.1.1）。
## 本特效只承担**表现**：它不决定什么时候吼叫、不认识 Enemy3D、不改任何玩法数值。
##
## 与头顶血条同族的摆放口径（Enemy3D._position_overhead_health_bar 的兄弟）：
##   - 单实例常驻挂载在怪物头顶锚点下方，随怪物出生创建、随怪物销毁释放；
##     不进 VfxPool3D（每怪一个 Sprite3D，与头顶血条同量级，池化反而增加峰值）。
##   - 尺寸不是固定值：调用方按体型传入世界边长（米），见 §6.1.4 尺寸公式。
##
## 时间线（t 自 activate 起算，见 §6.1.2）。四段，**第二段是刻意的「停顿」**：
##
##   ① 弹出  [0, POP_PEAK_AT)        0.70 → 1.15（过冲），ease-out，最快
##   ② 回稳  [POP_PEAK_AT, POP_SETTLE_AT)   1.15 → 1.00
##   ③ 停顿  [POP_SETTLE_AT, hold_seconds)  **完全静止**在 1.00 / 满不透明
##   ④ 淡出  [hold_seconds, lifetime)
##
## ③ 是业主明确要的「弹出停顿一下」：不是慢慢收，而是**彻底停住**再消失，
## 让玩家有明确的读取时间。它是真静止（scale 与 alpha 全程不变），由验收钉住 ——
## 一旦有人在停顿段里加了缓动或脉动，`verify_monster_startup_roar` 会红。
##
## lifetime = hold_seconds + fade_seconds
##
## 提前退场：怪物在启动过程中被击杀、硬直或房间停用时，调用方必须调 `dismiss()`，
## 不允许让图标跟着尸体继续显示 —— 那是「已死还在吼」的假信息。

signal roar_icon_popped
signal roar_icon_dismissed(was_early: bool)

## 纹理原生边长 = 256px × pixel_size；缩放分母用它换算「世界边长 → sprite scale」。
const TEXTURE_EDGE_PX := 256.0
const PIXEL_SIZE := 0.005

## ① 弹出段起点与过冲峰值。1.15 是刻意的明显过冲 —— 「弹」要弹得出来。
const POP_START_SCALE := 0.70
const POP_PEAK_SCALE := 1.15
## ①/② 的分界：过冲峰值时刻。
const POP_PEAK_AT := 0.10
## ② 的结束 = ③ 停顿段的开始。
const POP_SETTLE_AT := 0.18

const DEFAULT_HOLD_SECONDS := 0.55
const DEFAULT_FADE_SECONDS := 0.18

## 图标世界边长下限/上限（米）。下限保证小怪也读得出，上限防止 Boss 尺寸失控。
const ICON_EDGE_MIN_M := 0.45
const ICON_EDGE_MAX_M := 1.20

@export var hold_seconds: float = DEFAULT_HOLD_SECONDS
@export var fade_seconds: float = DEFAULT_FADE_SECONDS

var _sprite: Sprite3D
var _texture: Texture2D
var _edge_m: float = 0.58
## 由目标世界边长算出的基准缩放；弹出动画在它之上再乘时间曲线，两者互不覆盖。
var _base_scale: float = 1.0
var _dismissed: bool = false


func _on_configure(context: Dictionary) -> void:
	hold_seconds = maxf(0.05, float(context.get("hold_seconds", DEFAULT_HOLD_SECONDS)))
	fade_seconds = maxf(0.0, float(context.get("fade_seconds", DEFAULT_FADE_SECONDS)))
	lifetime = hold_seconds + fade_seconds
	_ensure_sprite()


func _on_activate(_world_pos: Vector3, _color: Color, size: float, _context: Dictionary) -> void:
	_dismissed = false
	_ensure_sprite()
	_edge_m = clampf(size if size > 0.0 else 0.58, ICON_EDGE_MIN_M, ICON_EDGE_MAX_M)
	# 纹理原生世界边长 = 256 × 0.005 = 1.28m；把它缩到目标边长。
	_base_scale = _edge_m / (TEXTURE_EDGE_PX * PIXEL_SIZE)
	_set_pop_scale(POP_START_SCALE)
	_apply_alpha(1.0)
	roar_icon_popped.emit()


func _on_tick(elapsed: float, _total: float) -> void:
	_set_pop_scale(_pop_curve(elapsed))
	if fade_seconds > 0.0 and elapsed > hold_seconds:
		_apply_alpha(1.0 - (elapsed - hold_seconds) / fade_seconds)


func _on_lifetime_expired() -> void:
	roar_icon_dismissed.emit(false)


## 提前退场（死亡 / 硬直 / 房间停用 / 目标失效）。幂等：重复调用只生效一次。
func dismiss() -> void:
	if _dismissed or not _active:
		return
	_dismissed = true
	_apply_alpha(0.0)
	roar_icon_dismissed.emit(true)
	_retire()


## 当前图标世界边长（米），供运行探针与验收断言读取。
func get_icon_edge_m() -> float:
	return _edge_m


## ③ 停顿段的时长（秒）。= 保持段减去前面「弹出 + 回稳」占掉的时间。
## 单独给一个函数，是为了让验收能直接断言「停顿确实存在且够长」，
## 而不是在测试里重算一遍 `hold_seconds - POP_SETTLE_AT`（算错就一起错）。
func get_hold_still_seconds() -> float:
	return maxf(0.0, hold_seconds - POP_SETTLE_AT)


## 该时刻是否处于 ③ 停顿段（此段内 scale 与 alpha 必须严格不变）。
func is_in_still_hold(elapsed: float) -> bool:
	return elapsed >= POP_SETTLE_AT and elapsed <= hold_seconds


## 弹出曲线：① 0.70 → 1.15（过冲）→ ② 1.00 → ③ 恒 1.00（停顿）。
func _pop_curve(elapsed: float) -> float:
	if elapsed <= POP_PEAK_AT:
		return lerpf(
			POP_START_SCALE,
			POP_PEAK_SCALE,
			_ease_out_quad(elapsed / POP_PEAK_AT)
		)
	if elapsed <= POP_SETTLE_AT:
		return lerpf(
			POP_PEAK_SCALE,
			1.0,
			_ease_out_quad((elapsed - POP_PEAK_AT) / (POP_SETTLE_AT - POP_PEAK_AT))
		)
	# ③ 停顿段：严格 1.00，不做任何后续缓动或脉动。
	return 1.0


func _ensure_sprite() -> void:
	if _sprite != null and is_instance_valid(_sprite):
		return
	if _texture == null:
		_texture = load("res://assets/art/vfx/textures/vfx_monster_roar_icon_atlas_v001.png")
	_sprite = Sprite3D.new()
	_sprite.name = "RoarIconSprite"
	_sprite.texture = _texture
	_sprite.pixel_size = PIXEL_SIZE
	# 与头顶血条同一口径：billboard 永久朝向摄像机、不参与深度测试（不被怪物身体挡住）
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.no_depth_test = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.15
	add_child(_sprite)


func _set_pop_scale(multiplier: float) -> void:
	if _sprite != null:
		_sprite.scale = Vector3.ONE * (_base_scale * multiplier)


func _apply_alpha(alpha: float) -> void:
	if _sprite != null:
		_sprite.modulate = Color(1, 1, 1, clampf(alpha, 0.0, 1.0))


func _ease_out_quad(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - c) * (1.0 - c)
