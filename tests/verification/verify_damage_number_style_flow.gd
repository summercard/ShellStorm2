extends Node
## FX02-01 / FX02-02 伤害与治疗飘字的**字体、样式、力度与随机化**专项验收。
##
## 为什么单独建一个：`verify_3d_enemy_behavior_flow` 原来的字体断言是直接
## `new CombatDamageNumber3D` —— 那是条**跑不到的兜底链路**，实机走的是
## `VfxPool3D` → `VfxDamageNumber3D`，于是改坏实机字体不会变红（结构性假绿）。
## 本专项一律从池里取**实机生效实例**读真值。
##
## 期望值**全部硬编码在本文件**，不引用被测常量（`DamageNumberStyle.*`）—— 引用被测常量会让
## 「常量被改成什么、期望就跟着变成什么」，断言恒绿。硬编码之外另加一条「常量钉子」把常量本身
## 也钉住（vfx skill §6.9）。

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const StyleScript := preload("res://src/vfx/DamageNumberStyle.gd")

# ---- 硬编码期望值（外部真源，互不派生）----
const EXPECTED_FONT_FAMILIES: Array[String] = [
	"Impact", "Arial Black", "Haettenschweiler", "Franklin Gothic Heavy",
	"sans-serif-black", "Helvetica Neue", "DejaVu Sans Bold", "Liberation Sans",
	"Noto Sans", "sans-serif",
]
const EXPECTED_FONT_WEIGHT := 900
const EXPECTED_MSDF_SIZE := 128
## MSDF 距离场宽度。**这是描边能不能渲染出来的开关**：Godot 下 MSDF 描边的可达上限
## ≈ `msdf_pixel_range / 2`，默认 16 只够描边到 8；当时声明 26/30/34 ⇒ 被截成 1px 细丝。
## 2026-10-17 近距离定尺实测：range=16 → 6px；48 → 21px；64/80 → 26px（足额）。
## 同日描边减半为 13/15/17（业主「太粗了，缩小一半」）后，64 仍是足额且带余量的取值。
const EXPECTED_MSDF_PIXEL_RANGE := 64
## 上限同样是实测来的：range 96 起距离场精度不够，出现**左右不对称**（一侧描边整条丢失）。
## 不是为了"省"而设的护栏，是「别为了保险往上加」的反向对照结论。
const EXPECTED_MSDF_PIXEL_RANGE_MAX := 80
const EXPECTED_PIXEL_SIZE := 0.00375
const EXPECTED_NORMAL_FONT_SIZE := 116
const EXPECTED_HEAVY_FONT_SIZE := 134
const EXPECTED_CRITICAL_FONT_SIZE := 152
const EXPECTED_NORMAL_OUTLINE := 13
const EXPECTED_HEAVY_OUTLINE := 15
const EXPECTED_CRITICAL_OUTLINE := 17
const EXPECTED_HEAVY_THRESHOLD := 40
## 世界字高 = 字号 × 像素比：116 × 0.00375 = 0.435 m。
const EXPECTED_NORMAL_GLYPH_HEIGHT := 0.435
## 迁移后实机的字高（字号 32 × 像素比 0.010）。业主「大一点」= 至少要超过它。
const PREVIOUS_SHIPPED_GLYPH_HEIGHT := 0.320
## 力度：随机化之前特效里的固定上升距离（米）。
const EXPECTED_BASE_RISE := 0.90
## 弹出缩放的随机下界（调用方 Enemy3D 的 DMG_NUM_POP_SCALE.x）。
const EXPECTED_POP_SCALE_FLOOR := 1.28
## 弹出收束时长（秒）：出生到这个时刻为止是"过冲回收"，之后才开始整体缓缩。
const EXPECTED_POP_SETTLE_TIME := 0.14
## 出生点抖动的随机上界（调用方 DMG_NUM_SPAWN_JITTER.x）。
const EXPECTED_SPAWN_JITTER_MAX := 0.16
## 出生点锚定用例的出生位置。取非原点、且三个分量都远大于抖动幅度，
## 这样「被池原点吸走」这类退化一眼可辨（对照项断言它不能塌到原点附近）。
const EXPECTED_SPAWN_ANCHOR := Vector3(3.0, 5.0, 7.0)

## 走真实调用方路径的抽样发数。
const SAMPLES := 24
## 随机极差下限。均匀分布下、抽 24 发而极差不足理论值一半的概率 ≈ 2×0.5²⁴ ≈ 1e-7，
## 所以这些阈值不会假红；但能抓住「随机被填成固定值」这类回归。
const EXPECTED_MIN_SPAWN_SPREAD := 0.16
const EXPECTED_MIN_RISE_SPREAD := 0.22
const EXPECTED_MIN_DRIFT_SPREAD := 0.22

var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool == null:
		push_error("damage number style verification needs the VfxPool3D autoload")
		get_tree().quit(1)
		return
	pool.clear_all()

	_verify_style_constants()
	_verify_spawn_anchor(pool)
	_verify_damage_number_style(pool)
	_verify_heal_number_style(pool)
	_verify_rise_and_pop(pool)
	_verify_determinism(pool)
	await _verify_caller_randomization(pool)

	if _failures.is_empty():
		print("DAMAGE_NUMBER_STYLE_FLOW_OK: comic-style heavy font, graded size/outline that the MSDF pixel range can actually carry, enlarged glyph height, punchy rise with pop overshoot, caller-side randomization and per-context determinism all pass")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error(failure)
	get_tree().quit(1)


## 常量钉子：把被测常量本身钉在外部真源上。没有这一段，上面那些硬编码期望只能证明
## 「实例上的值对不对」，证明不了「常量有没有被顺手改掉」。
func _verify_style_constants() -> void:
	_expect(int(StyleScript.FONT_WEIGHT) == EXPECTED_FONT_WEIGHT, "DamageNumberStyle.FONT_WEIGHT drifted")
	_expect(int(StyleScript.MSDF_SIZE) == EXPECTED_MSDF_SIZE, "DamageNumberStyle.MSDF_SIZE drifted")
	_expect(int(StyleScript.MSDF_PIXEL_RANGE) == EXPECTED_MSDF_PIXEL_RANGE, "DamageNumberStyle.MSDF_PIXEL_RANGE drifted")
	# ★ 隐形契约断言：距离场宽度必须够承载声明的最大描边，否则描边会静默退回 1px 细丝
	#   —— 不报错、不变红、只是"看不清"，正是最难发现的那类回归。
	#   需求 = 2 × max(描边 × msdf_size / 字号)；口径来自 Godot issue #70211。
	var required_range: float = _required_msdf_pixel_range()
	_expect(
		float(StyleScript.MSDF_PIXEL_RANGE) >= required_range,
		"MSDF_PIXEL_RANGE=%d is too small for the declared outlines (needs >= %.1f): MSDF truncates outlines to about range/2, so the comic outline would silently degrade into a hairline" % [
			int(StyleScript.MSDF_PIXEL_RANGE), required_range
		]
	)
	_expect(
		int(StyleScript.MSDF_PIXEL_RANGE) <= EXPECTED_MSDF_PIXEL_RANGE_MAX,
		"MSDF_PIXEL_RANGE=%d is past the measured safe ceiling %d: at 96 the distance field loses precision and the outline goes asymmetric (one side disappears)" % [
			int(StyleScript.MSDF_PIXEL_RANGE), EXPECTED_MSDF_PIXEL_RANGE_MAX
		]
	)
	_expect(absf(float(StyleScript.PIXEL_SIZE) - EXPECTED_PIXEL_SIZE) < 0.0000001, "DamageNumberStyle.PIXEL_SIZE drifted")
	_expect(int(StyleScript.NORMAL_FONT_SIZE) == EXPECTED_NORMAL_FONT_SIZE, "DamageNumberStyle.NORMAL_FONT_SIZE drifted")
	_expect(int(StyleScript.HEAVY_FONT_SIZE) == EXPECTED_HEAVY_FONT_SIZE, "DamageNumberStyle.HEAVY_FONT_SIZE drifted")
	_expect(int(StyleScript.CRITICAL_FONT_SIZE) == EXPECTED_CRITICAL_FONT_SIZE, "DamageNumberStyle.CRITICAL_FONT_SIZE drifted")
	_expect(int(StyleScript.NORMAL_OUTLINE_SIZE) == EXPECTED_NORMAL_OUTLINE, "DamageNumberStyle.NORMAL_OUTLINE_SIZE drifted")
	_expect(int(StyleScript.HEAVY_OUTLINE_SIZE) == EXPECTED_HEAVY_OUTLINE, "DamageNumberStyle.HEAVY_OUTLINE_SIZE drifted")
	_expect(int(StyleScript.CRITICAL_OUTLINE_SIZE) == EXPECTED_CRITICAL_OUTLINE, "DamageNumberStyle.CRITICAL_OUTLINE_SIZE drifted")
	_expect(int(StyleScript.HEAVY_AMOUNT_THRESHOLD) == EXPECTED_HEAVY_THRESHOLD, "DamageNumberStyle.HEAVY_AMOUNT_THRESHOLD drifted")
	var families: PackedStringArray = StyleScript.font_families()
	_expect(
		families == PackedStringArray(EXPECTED_FONT_FAMILIES),
		"DamageNumberStyle.font_families() drifted: %s" % str(families)
	)


## 出生点锚定：飘字必须从**出生点**升起。
##
## 这条补的是一个历史黑洞：2026-09-11 池化迁移起，`_on_tick` 用**赋值**（`position.y = ...`）
## 而不是叠加来写位置，出生坐标在第一帧就被清零 —— 实测实机所有飘字都跑到世界原点上方
## 不到 1 米处，与怪物所在楼层毫无关系（98F 时相差上千米）。2026-10-16 实测确认并修复。
func _verify_spawn_anchor(pool: VfxPool3D) -> void:
	for asset_id in [VfxPool3D.FX02_DAMAGE_NUMBER, VfxPool3D.FX02_HEAL_NUMBER]:
		var effect := pool.acquire(asset_id, EXPECTED_SPAWN_ANCHOR, Color("ff4444"), 1.0, {
			"text_value": "25", "magnitude": 25, "critical": false,
			"spawn_offset": Vector3.ZERO, "rise_scale": 1.0,
			"drift": Vector3.ZERO, "pop_scale": 1.0, "duration_scale": 1.0,
		})
		_expect(
			effect.global_position.is_equal_approx(EXPECTED_SPAWN_ANCHOR),
			"[%s] is not born at the requested position: %s" % [asset_id, str(effect.global_position)]
		)
		effect.call("_on_tick", 0.0, effect.lifetime)
		_expect(
			effect.global_position.is_equal_approx(EXPECTED_SPAWN_ANCHOR),
			"[%s] leaves its spawn anchor at t=0: %s" % [asset_id, str(effect.global_position)]
		)
		var expected_top_y: float = EXPECTED_SPAWN_ANCHOR.y + EXPECTED_BASE_RISE
		effect.call("_on_tick", effect.lifetime, effect.lifetime)
		var top: Vector3 = effect.global_position
		_expect(
			absf(top.x - EXPECTED_SPAWN_ANCHOR.x) < 0.001 and absf(top.z - EXPECTED_SPAWN_ANCHOR.z) < 0.001,
			"[%s] drifts off the spawn anchor horizontally while drift is zero: %s" % [asset_id, str(top)]
		)
		_expect(
			absf(top.y - expected_top_y) < 0.001,
			"[%s] ends at y=%.3f, expected spawn y %.1f + rise %.2f" % [asset_id, top.y, EXPECTED_SPAWN_ANCHOR.y, EXPECTED_BASE_RISE]
		)
		# 反向对照的对照项：绝不能塌回池原点附近 —— 那正是修复前的表现。
		_expect(
			top.length() > 8.0,
			"[%s] collapsed back toward the pool origin instead of rising from its spawn point: %s" % [asset_id, str(top)]
		)
		print("PROBE|spawn_anchor|%s|born=%s|top=%s" % [asset_id, str(EXPECTED_SPAWN_ANCHOR), str(top)])
		pool.retire(asset_id, effect)


func _verify_damage_number_style(pool: VfxPool3D) -> void:
	var cases := [
		{"amount": 12, "critical": false, "font": EXPECTED_NORMAL_FONT_SIZE, "outline": EXPECTED_NORMAL_OUTLINE, "tag": "normal"},
		{"amount": 40, "critical": false, "font": EXPECTED_HEAVY_FONT_SIZE, "outline": EXPECTED_HEAVY_OUTLINE, "tag": "heavy"},
		{"amount": 48, "critical": true, "font": EXPECTED_CRITICAL_FONT_SIZE, "outline": EXPECTED_CRITICAL_OUTLINE, "tag": "critical"},
	]
	for case in cases:
		var tag: String = str(case["tag"])
		var effect := pool.acquire(
			VfxPool3D.FX02_DAMAGE_NUMBER, Vector3(5.0, 2.0, 5.0), Color("ff4444"), 1.0,
			{"text_value": str(int(case["amount"])), "magnitude": int(case["amount"]), "critical": bool(case["critical"])}
		)
		var label := effect.get_node_or_null("DamageLabel") as Label3D
		if label == null:
			_expect(false, "damage number [%s] has no DamageLabel under the pooled prefab" % tag)
			continue
		_expect(label.font is SystemFont, "damage number [%s] is not using a SystemFont" % tag)
		if label.font is SystemFont:
			var system_font := label.font as SystemFont
			_expect(
				system_font.font_names == PackedStringArray(EXPECTED_FONT_FAMILIES),
				"damage number [%s] font family chain drifted: %s" % [tag, str(system_font.font_names)]
			)
			_expect(
				system_font.font_weight == EXPECTED_FONT_WEIGHT,
				"damage number [%s] font weight is %d, expected %d" % [tag, system_font.font_weight, EXPECTED_FONT_WEIGHT]
			)
			_expect(
				system_font.multichannel_signed_distance_field,
				"damage number [%s] dropped MSDF (glyphs will blur when scaled)" % tag
			)
			_expect(
				system_font.msdf_size == EXPECTED_MSDF_SIZE,
				"damage number [%s] msdf_size is %d, expected %d" % [tag, system_font.msdf_size, EXPECTED_MSDF_SIZE]
			)
			# 实机实例上的距离场宽度也要对 —— 光有常量钉子证明不了"常量被真的用上了"
			# （历史上 `outline_size` 就是常量对、实例也设了，但被 range 截断）。
			_expect(
				system_font.msdf_pixel_range == EXPECTED_MSDF_PIXEL_RANGE,
				"damage number [%s] msdf_pixel_range is %d, expected %d (the outline would be truncated)" % [
					tag, system_font.msdf_pixel_range, EXPECTED_MSDF_PIXEL_RANGE
				]
			)
			# 该档位自己的描边需求也要被 range 覆盖。
			var grade_need: float = float(label.outline_size) * float(EXPECTED_MSDF_SIZE) / float(label.font_size) * 2.0
			_expect(
				float(system_font.msdf_pixel_range) >= grade_need,
				"damage number [%s] msdf_pixel_range=%d cannot carry outline_size=%d at font_size=%d (needs >= %.1f)" % [
					tag, system_font.msdf_pixel_range, label.outline_size, label.font_size, grade_need
				]
			)
		_expect(
			label.font_size == int(case["font"]),
			"damage number [%s] font_size is %d, expected %d" % [tag, label.font_size, int(case["font"])]
		)
		_expect(
			label.outline_size == int(case["outline"]),
			"damage number [%s] outline_size is %d, expected %d" % [tag, label.outline_size, int(case["outline"])]
		)
		_expect(
			absf(label.pixel_size - EXPECTED_PIXEL_SIZE) < 0.0000001,
			"damage number [%s] pixel_size drifted to %.5f" % [tag, label.pixel_size]
		)
		# 勾边必须是近黑：漫画风靠它把粗体字从彩色背景里"切"出来。
		_expect(label.outline_modulate.r < 0.1 and label.outline_modulate.g < 0.1 and label.outline_modulate.b < 0.1,
			"damage number [%s] outline color is not near-black: %s" % [tag, str(label.outline_modulate)])
		# 世界字高必须真的比迁移后实机更大 —— 「大一点」是本轮诉求本身。
		var glyph_height: float = float(label.font_size) * label.pixel_size
		if tag == "normal":
			_expect(
				absf(glyph_height - EXPECTED_NORMAL_GLYPH_HEIGHT) < 0.001,
				"damage number [%s] world glyph height is %.3f m, expected %.3f m" % [tag, glyph_height, EXPECTED_NORMAL_GLYPH_HEIGHT]
			)
		else:
			_expect(
				glyph_height > EXPECTED_NORMAL_GLYPH_HEIGHT,
				"damage number [%s] is not larger than the normal tier: %.3f m" % [tag, glyph_height]
			)
		_expect(
			glyph_height > PREVIOUS_SHIPPED_GLYPH_HEIGHT,
			"damage number [%s] is not larger than the pre-change shipped size (%.3f m): %.3f m" % [
				tag, PREVIOUS_SHIPPED_GLYPH_HEIGHT, glyph_height
			]
		)
		var previous_ratio: float = glyph_height / PREVIOUS_SHIPPED_GLYPH_HEIGHT
		print("PROBE|damage_number[%s]|font_size=%d|outline=%d|pixel=%.5f|glyph_height=%.3fm|vs_shipped=%.2fx" % [
			tag, label.font_size, label.outline_size, label.pixel_size, glyph_height, previous_ratio
		])
		pool.retire(VfxPool3D.FX02_DAMAGE_NUMBER, effect)


func _verify_heal_number_style(pool: VfxPool3D) -> void:
	# 治疗飘字必须与伤害飘字**同源**（同字体、同字号档、同勾边）—— 否则同屏会出现两种字形，
	# 这正是"字体口径散在多处"的原始病症。
	var effect := pool.acquire(
		VfxPool3D.FX02_HEAL_NUMBER, Vector3(5.0, 2.0, 5.0), Color(0.4, 1.0, 0.55), 1.0,
		{"text_value": "+12", "magnitude": 12, "critical": false}
	)
	var label := effect.get_node_or_null("HealLabel") as Label3D
	if label == null:
		_expect(false, "heal number has no HealLabel under the pooled prefab")
		return
	_expect(label.font is SystemFont, "heal number is not using a SystemFont")
	if label.font is SystemFont:
		_expect(
			(label.font as SystemFont).font_names == PackedStringArray(EXPECTED_FONT_FAMILIES),
			"heal number font family chain drifted from the damage-number truth source"
		)
	_expect(
		label.font_size == EXPECTED_NORMAL_FONT_SIZE,
		"heal number font_size is %d, expected the shared normal tier %d" % [label.font_size, EXPECTED_NORMAL_FONT_SIZE]
	)
	_expect(
		label.outline_size == EXPECTED_NORMAL_OUTLINE,
		"heal number outline_size is %d, expected the shared normal tier %d" % [label.outline_size, EXPECTED_NORMAL_OUTLINE]
	)
	_expect(label.text.begins_with("+"), "heal number text [%s] lost its '+' prefix" % label.text)
	_expect(label.modulate.g > label.modulate.r, "heal number is not green (g=%.2f r=%.2f)" % [label.modulate.g, label.modulate.r])
	pool.retire(VfxPool3D.FX02_HEAL_NUMBER, effect)


## 力度：手动步进到寿命末尾，位移必须精确等于「基线上升距离 × rise_scale」；
## 出生瞬间字形必须是弹出尺寸（>1.0），并在弹出收束后落到 1.0。
func _verify_rise_and_pop(pool: VfxPool3D) -> void:
	var rise_scale := 1.2
	var pop_scale := 1.4
	# 出生点取非原点，且位置读数一律用「相对出生点的偏移」——否则断言语义会随
	# `_on_tick` 写绝对坐标还是写偏移而漂移（2026-10-16 出生点事故正是踩了这个）。
	var spawn := Vector3(5.0, 2.0, 5.0)
	var effect := pool.acquire(
		VfxPool3D.FX02_DAMAGE_NUMBER, spawn, Color("ff4444"), 1.0,
		{
			"text_value": "25", "magnitude": 25, "critical": false,
			"rise_scale": rise_scale, "pop_scale": pop_scale,
			"spawn_offset": Vector3.ZERO, "drift": Vector3.ZERO,
			"duration_scale": 1.0,
		}
	)
	var label := effect.get_node_or_null("DamageLabel") as Label3D
	if label == null:
		_expect(false, "rise/pop check cannot read the pooled DamageLabel")
		return
	_expect(
		absf(label.scale.x - pop_scale) < 0.001,
		"damage number does not start at the pop overshoot: scale.x=%.3f expected %.3f" % [label.scale.x, pop_scale]
	)
	var mid_t: float = 0.5 * effect.lifetime
	effect.call("_on_tick", mid_t, effect.lifetime)
	var mid_y: float = effect.position.y - spawn.y
	effect.call("_on_tick", effect.lifetime, effect.lifetime)
	var end_y: float = effect.position.y - spawn.y
	var expected_rise: float = EXPECTED_BASE_RISE * rise_scale
	_expect(
		absf(end_y - expected_rise) < 0.01,
		"damage number end rise is %.3f m, expected %.3f m (base %.2f x scale %.2f)" % [
			end_y, expected_rise, EXPECTED_BASE_RISE, rise_scale
		]
	)
	# 反向对照的对照项：上升**不能**停在旧基线上（0.60 是本轮之前的固定值）。
	_expect(
		end_y > 0.60 + 0.01,
		"damage number end rise collapsed back to the pre-change 0.60 m baseline"
	)
	# 力度感 = 曲线前段陡：半程位移必须显著超过线性半程（ease-out cubic 下 ≈ 87.5%）。
	var linear_mid: float = expected_rise * 0.5
	_expect(
		mid_y > linear_mid * 1.3,
		"damage number rise curve is not punchy: half-life displacement %.3f m vs linear %.3f m" % [mid_y, linear_mid]
	)
	# 弹出收束：t = POP_SETTLE_TIME 这一刻字形必须正好回到 1.0（缓缩从这一刻起算）。
	effect.call("_on_tick", EXPECTED_POP_SETTLE_TIME, effect.lifetime)
	_expect(
		absf(label.scale.x - 1.0) < 0.001,
		"damage number pop overshoot never settles to 1.0: scale.x=%.3f at t=%.2f" % [label.scale.x, EXPECTED_POP_SETTLE_TIME]
	)
	print("PROBE|force|end_rise=%.3fm|expected=%.3fm|mid_rise=%.3fm|linear_mid=%.3fm|pop_start=%.2f" % [
		end_y, expected_rise, mid_y, linear_mid, pop_scale
	])
	pool.retire(VfxPool3D.FX02_DAMAGE_NUMBER, effect)


## 确定性：同一 context 两次借出，各项真值必须逐位相同。
## 这一段是随机化的对照项 —— 否则「飞得很散」也可能只是快照读取噪声。
func _verify_determinism(pool: VfxPool3D) -> void:
	var context := {
		"text_value": "25", "magnitude": 25, "critical": false,
		"spawn_offset": Vector3(0.1, 0.02, -0.1), "rise_scale": 1.1,
		"drift": Vector3(0.2, 0.0, -0.2), "pop_scale": 1.35, "duration_scale": 1.05,
	}
	var first := pool.acquire(VfxPool3D.FX02_DAMAGE_NUMBER, Vector3(5.0, 2.0, 5.0), Color("ff4444"), 1.0, context)
	first.call("_on_tick", 0.35, first.lifetime)
	var first_snapshot := _snapshot(first)
	var second := pool.acquire(VfxPool3D.FX02_DAMAGE_NUMBER, Vector3(5.0, 2.0, 5.0), Color("ff4444"), 1.0, context)
	second.call("_on_tick", 0.35, second.lifetime)
	var second_snapshot := _snapshot(second)
	_expect(
		first_snapshot == second_snapshot,
		"damage number is not byte-reproducible for an identical context:\n  %s\n  %s" % [first_snapshot, second_snapshot]
	)
	pool.retire(VfxPool3D.FX02_DAMAGE_NUMBER, first)
	pool.retire(VfxPool3D.FX02_DAMAGE_NUMBER, second)


## 随机化：走**真实调用方**路径（`Enemy3D._spawn_damage_number`）连打 SAMPLES 发，
## 统计出生点 / 上升倍率 / 漂移的极差。别在验收里另抄一套随机口径 —— 那只证明
## 「验收会摆散布」，证明不了实机飘字真散了（skill §5.5.4 同源纪律）。
func _verify_caller_randomization(pool: VfxPool3D) -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = "melee_chaser"
	enemy.position = Vector3(0.0, 0.0, 0.0)
	enemy.set_physics_process(false)
	add_child(enemy)
	await get_tree().process_frame

	var spawn_positions: Array[Vector3] = []
	var rise_distances: Array[float] = []
	var drift_xs: Array[float] = []

	for index in range(SAMPLES):
		pool.clear_kind(VfxPool3D.FX02_DAMAGE_NUMBER)
		enemy.call("_spawn_damage_number", 25, false)
		var bucket: Array = pool._active.get(VfxPool3D.FX02_DAMAGE_NUMBER, [])
		if bucket.is_empty():
			_expect(false, "caller-spawned damage number never reached the pool (sample %d)" % index)
			enemy.queue_free()
			return
		var effect := bucket.back() as VfxEffectBase3D
		spawn_positions.append(effect.global_position)
		rise_distances.append(_float_of(effect.get("_rise_distance")))
		drift_xs.append(_vector_of(effect.get("_drift")).x)

	_expect(spawn_positions.size() == SAMPLES, "randomization sampling only produced %d of %d effects" % [spawn_positions.size(), SAMPLES])
	if spawn_positions.is_empty():
		enemy.queue_free()
		return

	var spawn_spread := _spread_x(spawn_positions)
	var rise_spread := _spread(rise_distances)
	var drift_spread := _spread(drift_xs)
	_expect(
		spawn_spread >= EXPECTED_MIN_SPAWN_SPREAD,
		"damage number spawn points are still a single point: spread=%.4f m over %d shots" % [spawn_spread, SAMPLES]
	)
	_expect(
		rise_spread >= EXPECTED_MIN_RISE_SPREAD,
		"damage number rise distance is not randomized: spread=%.4f m over %d shots" % [rise_spread, SAMPLES]
	)
	_expect(
		drift_spread >= EXPECTED_MIN_DRIFT_SPREAD,
		"damage number horizontal drift is not randomized: spread=%.4f m over %d shots" % [drift_spread, SAMPLES]
	)
	# 上身散布必须留在"一团"的量级，不能大到把数字甩出屏幕：单发偏移不会超过抖动上界。
	var max_offset: float = 0.0
	var anchor: Vector3 = spawn_positions[0]
	for position in spawn_positions:
		max_offset = maxf(max_offset, absf(position.x - anchor.x))
	_expect(
		max_offset <= EXPECTED_SPAWN_JITTER_MAX * 2.0 + 0.0001,
		"damage number spawn jitter exceeds its declared bound: max_x_offset=%.4f m" % max_offset
	)
	print("PROBE|randomization|shots=%d|spawn_spread=%.4fm|rise_spread=%.4fm|drift_spread=%.4fm|max_offset=%.4fm" % [
		SAMPLES, spawn_spread, rise_spread, drift_spread, max_offset
	])
	enemy.queue_free()


func _snapshot(effect: VfxEffectBase3D) -> String:
	var label := effect.get_node_or_null("DamageLabel") as Label3D
	var drift := _vector_of(effect.get("_drift"))
	var glyph_scale: float = label.scale.x if label != null else -1.0
	var glyph_transparency: float = label.transparency if label != null else -1.0
	return "pos=(%.5f,%.5f,%.5f) lifetime=%.5f rise=%.5f drift=(%.5f,%.5f,%.5f) scale=%.5f transparency=%.5f" % [
		effect.position.x, effect.position.y, effect.position.z,
		effect.lifetime,
		_float_of(effect.get("_rise_distance")),
		drift.x, drift.y, drift.z,
		glyph_scale,
		glyph_transparency,
	]


## MSDF 描边对距离场宽度的需求。口径（Godot issue #70211 + Using Fonts 文档）：
##   可达描边 ≈ `msdf_pixel_range / 2`；距离场 1 纹素 = `font_size / msdf_size` 个字形像素。
##   ⇒ 需求 range = 2 × max(描边 × msdf_size / 字号)。
## 一律用**本文件硬编码的期望值**算，不读被测常量 —— 否则「常量改小、需求跟着变小」，
## 断言又会变成自印证。
func _required_msdf_pixel_range() -> float:
	var worst_texels: float = 0.0
	var grades := [
		[EXPECTED_NORMAL_OUTLINE, EXPECTED_NORMAL_FONT_SIZE],
		[EXPECTED_HEAVY_OUTLINE, EXPECTED_HEAVY_FONT_SIZE],
		[EXPECTED_CRITICAL_OUTLINE, EXPECTED_CRITICAL_FONT_SIZE],
	]
	for grade in grades:
		var outline_px: float = float(grade[0])
		var font_px: float = float(grade[1])
		worst_texels = maxf(worst_texels, outline_px * float(EXPECTED_MSDF_SIZE) / font_px)
	return 2.0 * worst_texels


## Variant → 值类型的显式收敛。本仓开「警告即错误」，把 Variant 直接参与算术 /
## 类型化赋值是高风险动作（`Cannot infer the type`），一律走这两个出口。
func _float_of(value: Variant) -> float:
	if value is float or value is int:
		return float(value)
	return 0.0


func _vector_of(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	return Vector3.ZERO


func _spread(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var lowest: float = values[0]
	var highest: float = values[0]
	for value in values:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return highest - lowest


func _spread_x(positions: Array[Vector3]) -> float:
	var xs: Array[float] = []
	for position in positions:
		xs.append(position.x)
	return _spread(xs)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
