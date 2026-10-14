extends RefCounted
## 方块爆开 / 冲击波的**共享运动学**（无 class_name；由 VfxZombieGooDeath3D / VfxGooHit3D /
## VfxDeathBlast3D 通过 preload 调用）。
##
## 为什么抽出来：FX01-17（胖子僵尸自爆）与 FX01-19（僵尸死亡）与 FX01-20（僵尸命中）
## 三个 Prefab 现在都是「一圈方块炸开 + 地面绿色冲击波」这套语言，若各自抄一遍：
##   · 尺度包络 / 外推包络 / 翻滚角三处公式会开始漂移（改一处漏两处）；
##   · 「同一个视觉语言」这件事就只剩口头约定。三件共用本文件 = 语言是同一条公式。
## 边界：本文件**只有纯函数**，不碰场景树、不持有状态、不出现 `randf()`
## ⇒ 三个 Prefab 各自仍然「Prefab 是唯一出口」（14.6 §1.2），只是共用一支运动学笔。
##
## ⚠ 随机性纪律（同 14.6 §5.5.3）：本文件**逐位可复现** —— 所有「错落」都写成
## 「下标 → 常量」的确定性映射（`(index * k) % count`），不调用任何随机源。
## 被逐帧断言驱动的特效脚本里埋 `randf()` 会让验收与视觉探针全部漂红。

## 方块放射方向：等角分布 + 可调的俯仰错落。
##
## `pitch_center` 是俯仰的中心角（弧度）：
##   · `0.15`（缺省）= 略微抬高（`-0.30 .. +0.60`）—— 这就是 FX01-19 死亡件 v001 的原始形状，
##     保留为缺省是为了让「撤回 / 复刻」时有**唯一**一个能一字不差复原的参数；
##   · `0.0` = 完全对称（`-span/2 .. +span/2`）—— 需要「全向对称」类断言时用这个：
##     抬高会让方向和的垂直分量不再互相抵消，水平面外的对称断言必然假红。
## `pitch_span` 越大越立体（全在同一平面会显得单薄）。
##
## ⚠ 俯仰用 `(index × stride) % count` 取下标：stride 必须与 `count` **互质**，
## 否则残差有重复（`count = 5` 时写死 5 会让五颗方块全取到同一个俯仰）。
static func cube_directions(
	count: int, pitch_span: float = 0.90, phase: float = 0.0, pitch_center: float = 0.15
) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	if count <= 0:
		return dirs
	var span: float = clampf(pitch_span, 0.0, 1.8)
	var stride := _coprime_stride(count)
	for index in count:
		var angle := float(index) / float(count) * TAU + phase
		var pitch: float = (
			pitch_center + span * (float((index * stride) % count) / float(maxi(1, count - 1)) - 0.5)
		)
		dirs.append(
			Vector3(cos(angle) * cos(pitch), sin(pitch), sin(angle) * cos(pitch)).normalized()
		)
	return dirs


## 取一个与 `count` 互质的小步长（用于把 `0..count-1` 打散成确定性的乱序）。
static func _coprime_stride(count: int) -> int:
	for candidate in [3, 5, 7, 11]:
		if count % candidate != 0:
			return candidate
	return 1


## 每个方块的尺寸系数（0.62~1.38）：让一圈方块**大小不一**，不是等大的齿轮。
static func size_ratios(count: int, low: float = 0.62, high: float = 1.38, stride: int = 7) -> Array[float]:
	var ratios: Array[float] = []
	if count <= 0:
		return ratios
	for index in count:
		ratios.append(low + (high - low) * float((index * stride) % count) / float(count))
	return ratios


## 尺度包络：前 `pop_ratio` 段从 `scale_min` 冲到过冲峰值 `scale_peak`，其余时间收到 `scale_end`。
## 这条「很小 → 过冲 → 收缩」是业主说的「需要有大小的变化动画」。
static func burst_scale_mul(
	lt: float, pop_ratio: float, scale_min: float, scale_peak: float, scale_end: float
) -> float:
	var t: float = clampf(lt, 0.0, 1.0)
	var pop: float = clampf(pop_ratio, 0.01, 0.99)
	if t <= pop:
		return lerpf(scale_min, scale_peak, t / pop)
	return lerpf(scale_peak, scale_end, (t - pop) / (1.0 - pop))


## 外推包络：从 `dist_start` 冲到 `dist_end`。`expo` **必须 > 1**
## —— 要让「炸开半径」跑在「方块变大」前面，否则十几个方块会互相插进去、读成一整块固体。
static func burst_reach(lt: float, dist_start: float, dist_end: float, expo: float) -> float:
	var t: float = clampf(lt, 0.0, 1.0)
	return dist_start + (dist_end - dist_start) * (1.0 - pow(1.0 - t, maxf(1.0, expo)))


## 方块翻滚角：纯 `elapsed` 的函数（不依赖 tick 历史 ⇒ 复借与跳帧都逐位可复现）。
## 三个速率显式给出，缺省 `(5, 4, 5)` 就是 FX01-19 死亡件 v001 的原始转速
## （见 `spin_euler` 的来历：抽公共件时不能让既有特效的观感发生任何漂移）。
static func spin_euler(
	direction: Vector3, elapsed: float, rate_a: float = 5.0, rate_b: float = 4.0, rate_c: float = 5.0
) -> Vector3:
	return Vector3(
		direction.z * elapsed * rate_a,
		direction.x * elapsed * rate_b,
		direction.y * elapsed * rate_c
	)


## 冲击波的归一化生长（`ring_pulse_min → 1.0`）：`phase` 是 0~1 的循环相位。
static func shockwave_grow(phase: float, ring_pulse_min: float) -> float:
	return ring_pulse_min + (1.0 - ring_pulse_min) * clampf(phase, 0.0, 1.0)


## 一圈冲击环里「最亮那层」的 alpha（多层共材质 ⇒ 取最大值，避免互相覆盖）。
static func shockwave_alpha(phase: float, peak_alpha: float) -> float:
	return (1.0 - clampf(phase, 0.0, 1.0)) * peak_alpha


## 冲击波的**时间窗包络**：`end_sec` 前 `fade_sec` 段线性收到 0。
##
## ⚠ 没有这一层，冲击波会**永远扫下去**：相位是 `fmod(elapsed/period + i/n, 1)` 的循环，
## 任何时刻都至少有一层处在低相位（= 高 alpha），于是「到点收干净」永远不成立
## （实测：0.66s 时仍有层亮着，验收直接红）。它属于「打击瞬间」那一下，
## 不该跟后面 0.7s 的地面液体停留抢注意力。
static func shockwave_window(elapsed: float, end_sec: float, fade_sec: float) -> float:
	return clampf((end_sec - elapsed) / maxf(0.001, fade_sec), 0.0, 1.0)


## `TorusMesh` 的外缘世界半径 —— 场地/冲击波「顶到规格半径」类断言的唯一换算口径
## （`outer_radius` 是 mesh 自带的，别在调用方各写一个 0.72）。
static func ring_outer_radius(mesh: TorusMesh, scale_x: float) -> float:
	if mesh == null:
		return 0.0
	return mesh.outer_radius * scale_x
