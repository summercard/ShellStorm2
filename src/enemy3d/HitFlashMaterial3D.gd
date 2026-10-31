class_name HitFlashMaterial3D
extends RefCounted
## 受击闪白的材质口径 —— **只改 uniform，不翻 shader 变体开关**。
##
## ## 为什么必须这样（2026-10-31 实测）
##
## 闪白最初写成 `material.emission_enabled = _flash_time > 0.0`，视觉上没问题，
## 但 `emission_enabled` 在 Godot 里**不是 uniform，是 shader define（USE_EMISSION）**：
## 翻它等于切 shader 变体、重建 GPU 管线。而闪白的形状正是「受击翻上去、0.12s 后翻回来」，
## 下一发再翻 ⇒ **每打中一下就卡一下**。
##
## 实测（RTX 3060 / Forward+ / `--disable-vsync`，见 `tools/_exp03_hit_cost_probe.gd`）：
##
## | 动作 | 命中帧帧时 | 相对基线 |
## |---|---|---|
## | 什么都不做 | 16.66 ms | — |
## | 只翻 `emission_enabled` | **115.21 ms** | **+98.55 ms** |
## | 只改 `emission_energy_multiplier` | 16.66 ms | −0.01 ms |
## | 只改能量（= 本方案的形状） | 16.67 ms | +0.01 ms |
##
## ⇒ 出厂就把 `emission_enabled` 打开、能量置 0（等于不亮），闪白只把能量推上去再收回。
##   画面逐位等价（energy = 0 时 emission 对最终颜色贡献为 0），代价从 ~98 ms 降到 ~0。
##
## ## ⚠ 必须留住原模型的基线能量
##
## 正式 GLB 里有本来就该常亮的件（眼球、指示灯、屏幕）。无条件写 0 会把它们一起灭掉 ——
## 那是「修卡顿顺手改坏美术」，比卡顿更难查。所以 `prepare()` 逐材质记下原始的
## `emission` 颜色与 `emission_energy_multiplier`，闪白期间是**叠加**而不是覆盖。
##
## ## 用法（三份 formal_visual 一致）
##
## ```gdscript
## var _flash_baseline: Array = []
##
## func _ready() -> void:
##     ...收集 _materials...
##     _flash_baseline = HitFlashMaterial3D.prepare(_materials)
##
## func _process(delta: float) -> void:
##     _flash_time = maxf(0.0, _flash_time - delta)
##     HitFlashMaterial3D.apply(_materials, _flash_baseline, _flash_time / FLASH_DURATION)
## ```

## 材质管线 keeper（用 preload，理由同 `EnemyAvatar3D.PipelineKeeper`）。
const Keeper := preload("res://src/enemy3d/MaterialPipelineKeeper.gd")

## 闪白本色（暖橙）。三个怪共用同一个值，最早写在各自脚本里，现在收敛到一处。
const FLASH_COLOR := Color(1.0, 0.65, 0.45)
## 闪白峰值能量。与 `FLASH_COLOR` 一起决定"打得进肉里"的观感强度。
const FLASH_PEAK_ENERGY := 0.60


## 把一批材质的自发光**打开并归零**，返回逐材质的基线（闪白叠加用）。
##
## 只接受 `StandardMaterial3D`；自定义 shader 材质原样跳过（它们没有
## `emission_enabled` 这个开关，本来也不会被我们翻动）。
static func prepare(materials: Array) -> Array:
	var baseline: Array = []
	for entry in materials:
		var material := entry as StandardMaterial3D
		if material == null:
			continue
		# 记基线必须在 `emission_enabled = true` **之前**读能量 —— 顺序反了就把
		# "原本不发光"记成"原本就这样亮"，闪白结束回不去。
		var base_color: Color = material.emission
		var base_energy: float = material.emission_energy_multiplier if material.emission_enabled else 0.0
		material.emission_enabled = true
		material.emission = base_color
		material.emission_energy_multiplier = base_energy
		# ⚠ 必须在**翻完自发光开关之后**再登记：签名里含 `emission_enabled`，
		# 先登记再翻等于登记了一个已经作废的签名，而真正在用的那个变体没人留，
		# 于是每只怪回收后又要重编译（实测正式 GLB 怪每只仍 105~118ms，就是这么来的）。
		Keeper.pin(material)
		baseline.append({
			"material": material,
			"color": base_color,
			"energy": base_energy,
			# 上次写进去的能量值：闪白结束后 intensity 恒为 0，
			# 有了它就能跳过重复写入，不让材质每帧被判 dirty。
			"written": base_energy,
		})
	return baseline


## 按闪白强度（0~1）刷新自发光。0 = 完全回到基线（不一定是不亮）。
static func apply(_materials: Array, baseline: Array, intensity: float) -> void:
	var strength := clampf(intensity, 0.0, 1.0)
	for entry in baseline:
		var record := entry as Dictionary
		var material := record["material"] as StandardMaterial3D
		if material == null:
			continue
		var base_energy: float = record["energy"]
		# 闪白亮时把颜色推向暖橙，收尾时还原该材质原本的 emission 色。
		material.emission = FLASH_COLOR if strength > 0.0 else (record["color"] as Color)
		var target := base_energy + FLASH_PEAK_ENERGY * strength
		if is_equal_approx(target, float(record["written"])):
			continue
		record["written"] = target
		material.emission_energy_multiplier = target


## 一次性把材料还原到出厂状态（换装 / 池化复用时调用，避免把闪白残留带过去）。
static func restore(baseline: Array) -> void:
	apply([], baseline, 0.0)
