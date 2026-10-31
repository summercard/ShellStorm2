class_name VfxTeleport3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## FX01-34 / FX01-35 · 瞬移「消失 / 出现」配对特效（程序几何 · v001）
##
## ## 为什么需要它
## 远征03 里有两类怪会**凭空换位**：
##   · `egt_hollowpoint`（空尖弹）定时 blink、`egt_gunjurer`（枪法师）出手后 blink
##     —— `_blink_to_random()` 直接改 `global_position`，**中间没有任何轨迹**；
##   · `egt_keybullet_kin` / `egt_chance_kin`（逃跑型）与 `egt_gripmaster`（抓握大师）
##     走 `_vanish()` 直接 `_die()` —— 也是原地蒸发。
## 两处修之前都只有一个 `avatar.flash_hit()` 闪白，玩家读到的是「模型抖了一下，
## 然后它就没了 / 它就出现在别处了」。业主 2026-10-31：「怪物突然消失出现很奇怪」。
##
## ## 一件还是两件
## 做成**两个 AssetID、同一个脚本**（`mode` 导出开关），不合并成一件：
##   ① 账本按 AssetID 一行一件，两件在账上要能分别查用量；
##   ② 池化按 asset_id 分桶，合成一件会让"消失"与"出现"抢同一批实例；
##   ③ 两者的**时间曲线方向相反**（收拢 vs 炸开），参数没法共用。
##
## ## 视觉口径（自拟，成本优先）
## 只用地上的**水平能量环** + 中心亮芯 + 7 根竖直能量丝，不引贴图、不引 Blender 产物、
## 不挂灯 —— 它在夜间塔内也是 unshaded 自发光，不依赖场景光照（同 FX01-02 口径）。
##   · OUT（消失）：环从 1.35 倍**向内收拢**到 0.15，竖丝**向上抽离**并变短
##     ⇒ 读作"被吸走"；0.22 s。
##   · IN（出现）：环从 0.15 **向外炸开**到 1.50，亮芯弹一下，竖丝向上冒出
##     ⇒ 读作"凭空生成"；0.26 s。
## 两件都**不跟随**挂点、**无碰撞**、**不投影**（`cast_shadow` 全关）。
##
## ## 契约
## 尺寸沿用基类 `effect_size`（1.0 ≈ 直径 1.4 m 的环，覆盖一只标准怪）。
## 颜色取调用方传入的单位色 —— `Enemy3D._spawn_effect_at()` 传的是该怪种配色，
## 于是紫的空尖弹是紫环、枪法师是浅紫环，玩家能顺带读出"是谁闪的"。

const ToonVfx = preload("res://src/vfx/ToonVfxGeometry.gd")

const ASSET_OUT := "VFX-TELEPORT-OUT-3D"
const ASSET_IN := "VFX-TELEPORT-IN-3D"

## 竖直能量丝的条数。7 是质数 ⇒ 绕一圈不会有两条正好对穿、看得出"每根都在动"。
const _STREAK_COUNT := 7
## 环收拢 / 炸开的半径倍率端点（乘 effect_size）。
const _RING_MIN := 0.15
const _RING_MAX := 1.5

## `out` = 消失（收拢离开）；`in` = 出现（炸开抵达）。
@export_enum("out", "in") var mode: String = "out"

var _ring: MeshInstance3D
var _core: MeshInstance3D
var _streaks: Array[MeshInstance3D] = []
var _mat_ring: StandardMaterial3D
var _mat_core: StandardMaterial3D
var _mat_streak: StandardMaterial3D
## 每根竖丝的绕 Y 角度与相位错峰（错峰让它们不是"整板一起动"）。
var _streak_angle: Array[float] = []
var _streak_phase: Array[float] = []


func _on_configure(_context: Dictionary) -> void:
	# 时长在 activate 之后才确定，这里只负责让池化复借时状态干净。
	pass


func _on_activate(_world_pos: Vector3, color: Color, size: float, _context: Dictionary) -> void:
	lifetime = 0.22 if mode == "out" else 0.26
	if color.a < 0.001:
		color = Color(0.62, 0.42, 1.0, 1.0)
	if _ring == null:
		_build()
	_apply_color(color)
	# 复借时上一发可能停在中途 ⇒ 所有节点回到起点，再由 `_on_tick(0)` 摆位。
	for node in _streaks:
		node.position = Vector3.ZERO
	_ring.scale = Vector3.ONE * size
	_core.scale = Vector3.ONE
	# 朝向：传送特效是地面对称的，只需要去掉父级可能残留的旋转。
	global_rotation = Vector3.ZERO
	_on_tick(0.0, lifetime)


func _build() -> void:
	# —— 水平能量环（躺在地上：TorusMesh 的轴就是 +Y，不额外转）——
	_ring = MeshInstance3D.new()
	_ring.name = "TeleportRing"
	_ring.mesh = ToonVfx.ring_mesh()
	_mat_ring = ToonVfx.toon_material(Color(0.62, 0.42, 1.0, 1.0), 1.6)
	_ring.material_override = _mat_ring
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	# —— 中心亮芯 ——
	_core = MeshInstance3D.new()
	_core.name = "TeleportCore"
	_core.mesh = ToonVfx.core_mesh()
	_mat_core = ToonVfx.toon_material(Color(0.92, 0.86, 1.0, 1.0), 2.2)
	_core.material_override = _mat_core
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)

	# —— 竖直能量丝（streak 长轴本地 +Z ⇒ 绕 X 转 -90° 变成竖直）——
	_mat_streak = ToonVfx.toon_material(Color(0.72, 0.56, 1.0, 1.0), 1.8)
	for i in _STREAK_COUNT:
		var ang := float(i) / float(_STREAK_COUNT) * TAU
		_streak_angle.append(ang)
		_streak_phase.append(fmod(float(i) * 0.037, 0.18))
		var st := MeshInstance3D.new()
		st.name = "Streak%d" % i
		st.mesh = ToonVfx.streak_mesh()
		st.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
		st.material_override = _mat_streak
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(st)
		_streaks.append(st)


func _apply_color(color: Color) -> void:
	_mat_ring.albedo_color = color
	_mat_ring.emission = color
	_mat_streak.albedo_color = color.lightened(0.18)
	_mat_streak.emission = color.lightened(0.18)
	# 亮芯保持近白，只带一点色相 —— 全上色会糊成一团，读不出"那里有个点"。
	var white := color.lightened(0.72)
	white.a = 1.0
	_mat_core.albedo_color = white
	_mat_core.emission = white


func _on_tick(elapsed: float, total: float) -> void:
	var t: float = clampf(elapsed / maxf(0.001, total), 0.0, 1.0)
	var sz := effect_size
	# 环：OUT 由大收小、IN 由小炸开。收/放都走 ease-out，中段位移快、尾段变慢。
	var ease_out := 1.0 - pow(1.0 - t, 2.0)
	var ring_radius := 0.0
	if mode == "out":
		ring_radius = lerpf(_RING_MAX, _RING_MIN, ease_out)
		_mat_ring.albedo_color.a = clampf(1.0 - t * 0.85, 0.0, 1.0)
	else:
		ring_radius = lerpf(_RING_MIN, _RING_MAX, ease_out)
		_mat_ring.albedo_color.a = clampf((1.0 - t) * 1.15, 0.0, 1.0)
	# ring_mesh 基准外径 0.72 m ⇒ 除以它以让「半径倍率」就是米级口径。
	_ring.scale = Vector3.ONE * (ring_radius / 0.72) * sz

	# 亮芯：OUT 一路缩没；IN 在 35% 处弹到最大再收。
	var core_scale := 0.0
	if mode == "out":
		core_scale = (1.0 - t) * 0.85
	else:
		core_scale = sin(clampf(t / 0.7, 0.0, 1.0) * PI) * 1.05 + (1.0 - t) * 0.25
	_core.scale = Vector3.ONE * maxf(0.01, core_scale) * sz
	_mat_core.albedo_color.a = clampf(1.0 - t * t, 0.0, 1.0)

	# 竖丝：OUT 从地面向上抽离（被吸走），IN 从中心向上冒出（凭空生出）。
	for i in _streaks.size():
		var lt: float = clampf((t - _streak_phase[i]) / maxf(0.001, 1.0 - _streak_phase[i]), 0.0, 1.0)
		var ang := _streak_angle[i]
		var radius := (0.30 + lt * 0.14) * sz
		var lift := 0.0
		var length := 0.0
		if mode == "out":
			lift = 0.10 + lt * 1.05
			length = (0.62 - lt * 0.42) * sz
		else:
			lift = 0.08 + (1.0 - lt) * 0.55
			length = (0.20 + lt * 0.55) * sz
		_streaks[i].position = Vector3(cos(ang) * radius, lift * sz, sin(ang) * radius)
		# streak_mesh 基准长 1.0 m 且长轴本地 Z ⇒ 转 -90° 后本地 Y 就是世界竖直。
		_streaks[i].scale = Vector3.ONE * sz
		_streaks[i].scale.y = maxf(0.01, length)
	_mat_streak.albedo_color.a = clampf(1.0 - t * 1.05, 0.0, 1.0)


## 门禁 / 巡检用的只读快照（不写盘）。
func get_presentation_snapshot() -> Dictionary:
	return {
		"asset_id": get_meta("asset_id", ASSET_OUT if mode == "out" else ASSET_IN),
		"asset_version": get_meta("asset_version", "v001"),
		"mode": mode,
		"node_count": get_child_count(),
		"streak_count": _streaks.size(),
		"has_light": false,
		"lifetime": lifetime,
		"casts_shadow": _ring.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _ring else true,
	}
