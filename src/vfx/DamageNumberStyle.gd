extends RefCounted
## 伤害 / 治疗飘字（FX02-01 / FX02-02）的**字体与样式单一真源**。
##
## 为什么必须有这个文件：字体口径曾散在两处 —— `src/fx/CombatDamageNumber3D.gd`（独立兜底
## 链路）与 `src/vfx/VfxDamageNumber3D.gd`（VfxPool3D 生效链路）各写各的。2026-09-11 池化
## 迁移后实机走的是后者，而后者**从没设过字体**（Label3D 默认内建），于是 2026-08-07 定档的
## 等宽终端字体只活在跑不到的兜底链路里，实机飘字一直是默认字体。两处口径 ⇒ 只能靠人记住，
## 改一处漏一处是必然。
##
## ⇒ 从此字体族 / 字重 / 字号分级 / 描边分级 / 世界像素比**只在本文件声明**，
##    `VfxDamageNumber3D`、`VfxHealNumber3D`、`CombatDamageNumber3D` 三处一律引用。
##
## 业主口径（2026-10-16）：「漫画风格的粗体 + 勾边（描边），大一点」。

## 超粗字重（900 = Black）。对可变字重字体（Helvetica Neue / Noto Sans）才真正生效；
## 对 Impact / Arial Black 这类单字重字体无副作用。
const FONT_WEIGHT := 900
## 多通道 SDF 字形尺寸。飘字会被 `effect_size` 与相机距离放大，必须走高分辨率 MSDF
## 才不会出现马赛克边。
const MSDF_SIZE := 128

## 距离场宽度 —— **描边能不能渲染出来的开关**，不是可调风格参数。
##
## Godot 官方口径（Using Fonts「Font outlines and shadows」+ issue #70211）：
##   「MSDF 字体下 `msdf_pixel_range` 必须 ≥ 描边尺寸的 2 倍，否则描边会被**提前截断**。
##     默认值 16 只够 outline 到 8。」
## 我们当时声明 26 / 30 / 34，**远超 8** ⇒ 描边被截成约 1 px 细丝。
##
## 2026-10-17 实测（`_scratch/probe_outline_calibration*.gd`，近距离定尺拍摄）：
##   range=16 ⇒ 实画 6 px（截断）；range=48 ⇒ 21 px；range=64/80 ⇒ 26 px（足额）。
##   铁证：`outline_size` 取 26 与 116 渲染结果**逐像素完全相同** —— 值根本没被用上。
##
## 换算口径：距离场里 1 纹素 = `font_size / msdf_size` 个字形像素。
##   当前最大需求 = 描边 17 @ 字号 152 ⇒ 17 × 128 / 152 ≈ 14.3 纹素
##   规则要求 range ≥ 2 × 14.3 ≈ 28.6。
##   仍保留 64、不压到 28.6：实测 48 已足额，64 则支持描边到约 38 @ 字号 152，
##   留出余量 —— 未来微调描边不必重新定档，且远离 96 起的精度崩坏点。
## ⚠ 不是越大越好：range 96 起距离场精度不够，实测描边**左右不对称**（一侧整条丢失）。
##   验收里有一条断言专门盯这个不等式（见 `verify_damage_number_style_flow`）。
const MSDF_PIXEL_RANGE := 64

## 世界像素比：字形像素 → 世界米。`字号 × 本值 = 世界字高`。
## 放大档位由业主 2026-10-16 定：「大一点」= 相对迁移后的实机（字号 32 / 像素比 0.010
## ⇒ 字高 0.320 m）涨到普通档 ≈ 0.435 m。
const PIXEL_SIZE := 0.00375

## 字号分级（世界字高 = 字号 × PIXEL_SIZE）：
##   普通 116 → 0.435 m    伤害 < 40
##   重击 134 → 0.503 m    伤害 ≥ 40
##   暴击 152 → 0.570 m    仅暴击
const NORMAL_FONT_SIZE := 116
const HEAVY_FONT_SIZE := 134
const CRITICAL_FONT_SIZE := 152
## 重击阈值：与颜色分级共用同一个数，改这里就要同步改颜色分级。
const HEAVY_AMOUNT_THRESHOLD := 40

## 描边（勾边）尺寸，单位同字号（字形像素）。漫画风要的是"勾线"而不是"糊边"，
## 按字高的 ~11% 给：普通 13 / 116 ≈ 11.2%  重击 15 / 134 ≈ 11.2%  暴击 17 / 152 ≈ 11.2%。
##
## 定档沿革：
##   2026-10-16 首版按 ~22% 给（26 / 30 / 34）—— 但那时 `msdf_pixel_range` 还是默认 16，
##     描边整个被截断到 8 像素上限，**22% 这个值根本没被渲染出来过**。
##   2026-10-17 修好 range（见 `MSDF_PIXEL_RANGE`）后描边第一次足额渲染，
##     业主看实机反馈「太粗了，缩小一半」⇒ 22% → 11%（就是现在这组值）。
##
## ⚠ 历史坑：本节曾写「第一版给到 19% 实测只剩 2~3 px，所以抬到 22%」——
##   那个「只剩 2~3 px」是 `msdf_pixel_range` 太小造成的**截断**，不是比例不够。
##   19% → 22% 那一步在视觉上什么都没改变（两版都被截到同一个 8 像素上限）。
##
## 屏幕描边宽 ≈ 描边像素 ×（屏幕字形高 / 字号）；改这一节前先确认 range 还够。
const NORMAL_OUTLINE_SIZE := 13
const HEAVY_OUTLINE_SIZE := 15
const CRITICAL_OUTLINE_SIZE := 17

## 勾边颜色：近黑（不是纯黑，纯黑在深色场景里像"挖空"）。压在红/橙/金填充下形成漫画勾线。
const OUTLINE_COLOR := Color(0.02, 0.02, 0.03, 1.0)


## 漫画风超粗字形链。Godot 的 `SystemFont` 按顺序取系统里第一个存在的字体，
## 找不到就继续往下 ⇒ 这条链要同时覆盖 Windows / macOS / Android / Linux：
##   Impact / Arial Black / Haettenschweiler / Franklin Gothic Heavy → Windows 自带超粗体
##   sans-serif-black → Android 系统别名（Noto Sans Black）
##   Helvetica Neue → macOS（配 FONT_WEIGHT 取 Black 字重）
##   DejaVu Sans Bold / Liberation Sans → Linux 兜底
## 链尾必须留一个泛型族名，否则全部落空时 Godot 会退回自身内建字体（那正是本次要修的问题）。
##
## ⚠ 只能是函数、不能是 `const`：Godot 4 不接受 `PackedStringArray([...])` 作为常量表达式
## （`Assigned value for constant isn't a constant expression`），裸数组字面量赋给
## PackedStringArray 类型的 const 同样过不了解析期。
static func font_families() -> PackedStringArray:
	return PackedStringArray([
		"Impact",
		"Arial Black",
		"Haettenschweiler",
		"Franklin Gothic Heavy",
		"sans-serif-black",
		"Helvetica Neue",
		"DejaVu Sans Bold",
		"Liberation Sans",
		"Noto Sans",
		"sans-serif",
	])


## 生成粗体字形。每条链路都必须经这里拿字体，禁止自行 `SystemFont.new()`。
##
## ⚠ `msdf_pixel_range` 必须在这里设：它是「描边能否渲染」的隐形契约，
##   而契约的另一半（`*_OUTLINE_SIZE`）在本文件上方 —— 两边只有靠这条赋值 + 验收里
##   那条不等式断言绑在一起。漏了这行，描边会静默退回 1 px 细丝，**不报任何错**。
static func make_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = font_families()
	font.font_weight = FONT_WEIGHT
	font.multichannel_signed_distance_field = true
	font.msdf_size = MSDF_SIZE
	font.msdf_pixel_range = MSDF_PIXEL_RANGE
	return font


static func font_size_for(amount: int, critical: bool) -> int:
	if critical:
		return CRITICAL_FONT_SIZE
	if amount >= HEAVY_AMOUNT_THRESHOLD:
		return HEAVY_FONT_SIZE
	return NORMAL_FONT_SIZE


static func outline_size_for(amount: int, critical: bool) -> int:
	if critical:
		return CRITICAL_OUTLINE_SIZE
	if amount >= HEAVY_AMOUNT_THRESHOLD:
		return HEAVY_OUTLINE_SIZE
	return NORMAL_OUTLINE_SIZE


## 该档位的世界字高（米）。给验收读数用，避免验收自己拿字号乘像素比又乘错。
static func world_glyph_height_for(amount: int, critical: bool) -> float:
	return float(font_size_for(amount, critical)) * PIXEL_SIZE


const DAMAGE_LIFETIME := 0.56
const DAMAGE_RISE := 0.90
const DAMAGE_FADE_IN := 0.04
const NORMAL_COLOR := Color("fff1d5")
const CRITICAL_COLOR := Color("ffd34e")
static func damage_color(critical: bool, element := "") -> Color:
	if critical:
		return CRITICAL_COLOR
	match element:
		"fire": return Color("ff783d")
		"ice": return Color("8ee5ff")
		"poison": return Color("8de85b")
		"lightning": return Color("c2faff")
	return NORMAL_COLOR
