extends Node
## 怪物启动过程（0.30–0.60s：转身 → 吼叫 → 头顶图标 → 攻击）专项验收。
##
## 外部真源：
##   - 设计原文 docs/v0.1/06A_怪物AI系统完整设计_评审稿.md §6.1.1–§6.1.4
##   - 公式常量 src/enemy3d/MonsterStartupProfile.gd
##   - 表现资产 assets/art/vfx/combat_3d/vfx_monster_roar_icon_root_top3d.tscn
##     （特效账本 FX01-16 VFX-MONSTER-ROAR-ICON-3D）
##
## 覆盖：① 文档数字 ↔ 代码常量逐条一致；② 时长窗口闭区间与两端可达；
##       ③ 吼叫段不短于下限；④ 转身+吼叫 == 总时长（不丢帧）；
##       ⑤ 图标尺寸按体型等比且被钳制；⑥ 图标偏移公式；⑦ 图标生命周期合成；
##       ⑧ Prefab 可加载 + Sprite3D 契约（billboard / 无深度测试 / alpha 裁切）；
##       ⑨ 贴图真实带 alpha（不是不透明底）；⑩ 弹出曲线数值；
##       ⑪ 体型缩放不被弹出动画覆盖（回归：曾把 _base_scale 乘丢）；
##       ⑫ 纯视觉无碰撞体；⑬ dismiss 幂等且提前退场。
## 只构建 mesh/material，不读 viewport 纹理 ⇒ 可安全 headless 运行。
## 判据：`MONSTER_STARTUP_ROAR_OK` 行 + ERROR 计数（不看裸退出码）。

const ROAR_SCENE: PackedScene = preload(
	"res://assets/art/vfx/combat_3d/vfx_monster_roar_icon_root_top3d.tscn"
)
const ICON_TEXTURE_PATH := "res://assets/art/vfx/textures/vfx_monster_roar_icon_atlas_v001.png"
const ENEMY_SCENE: PackedScene = preload(
	"res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn"
)
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")

## 接线用例：真人尺寸的怪（1.0 体型，非 Boss），启动过程必须真的把它按住。
const WIRING_KIND := "melee_chaser"
const WIRING_BOSS_KIND := "boss"
## 驱动步长。与 `Enemy3D._physics_process` 的真实节拍同量级，便于直接比较秒数。
const WIRING_STEP := 1.0 / 60.0
## 驱动帧数上限：0.60s 启动 + 余量，防止用例死循环。
const WIRING_MAX_STEPS := 180
## 启动过程内允许的最大水平位移（米）。制动 + 不推进，应该是零；
## 留一点余量给 `move_and_slide` 的贴地/分离微调。
const WIRING_DRIFT_TOLERANCE_M := 0.05

## 设计文档里写死的数字。故意在这里硬编码一遍：改了代码常量就会在这里红。
const DOC_T_STARTUP_MIN := 0.30
const DOC_T_STARTUP_MAX := 0.60
const DOC_T_ROAR_MIN := 0.16
const DOC_YAW_RATE := 520.0
const DOC_JITTER_MAX := 0.18
const DOC_ICON_BAR_RATIO := 0.42
## 图标底边到血条顶边的间隙，按图标边长比例给（不是固定米数）。
## 2026-10-14 换感叹号后固定 0.12m 会贴住血条（感叹号圆点落在方框底部），故改比例。
const DOC_ICON_GAP_RATIO := 0.30
## 间隙相对图标边长必须**不小于**这个值：调小比例会被这条抓住。
const MIN_ICON_GAP_RATIO := 0.25
const DOC_ICON_EDGE_MIN := 0.45
const DOC_ICON_EDGE_MAX := 1.20
const DOC_ICON_TAIL := 0.25
const DOC_ICON_FADE := 0.18
const DOC_REARM_AFTER := 3.0

## 弹出曲线（VFX 侧；业主 2026-10-14「改成感叹号 + 要有弹出停顿一下的动画」）。
## 四段：① 弹出 0.70→1.15（t=0.10）② 回稳 →1.00（t=0.18）③ **停顿**（真静止）④ 淡出。
const DOC_POP_START := 0.70
const DOC_POP_PEAK := 1.15
const DOC_POP_PEAK_AT := 0.10
const DOC_POP_SETTLE_AT := 0.18

const EXPECTED_PIXEL_SIZE := 0.005
const EXPECTED_TEXTURE_EDGE := 256

## 设计文档 §6.1.4 的体型尺寸表（血条宽 × 比值 → 图标边长 / 相对槽根偏移）。
## 改任一项（含文档表格里的数字）都会红 —— 前两列是输入，后两列是文档里印出来的结果。
const DOC_SIZE_TABLE := [
	{"kind": "exploder", "bar_w": 1.15, "bar_h": 0.14, "edge": 0.483, "offset": 0.456},
	{"kind": "melee_chaser", "bar_w": 1.38, "bar_h": 0.15, "edge": 0.5796, "offset": 0.539},
	{"kind": "ranged_caster", "bar_w": 1.38, "bar_h": 0.15, "edge": 0.5796, "offset": 0.539},
	{"kind": "ambusher", "bar_w": 1.38, "bar_h": 0.15, "edge": 0.5796, "offset": 0.539},
	{"kind": "shielded", "bar_w": 1.55, "bar_h": 0.17, "edge": 0.651, "offset": 0.606},
	{"kind": "summoner", "bar_w": 1.55, "bar_h": 0.17, "edge": 0.651, "offset": 0.606},
	{"kind": "fat_zombie03", "bar_w": 1.80, "bar_h": 0.18, "edge": 0.756, "offset": 0.695},
	{"kind": "boss", "bar_w": 2.65, "bar_h": 0.24, "edge": 1.113, "offset": 1.010},
]
## 首只唯一精英「背枪的裂口爬虫」的头顶条宽 2.05m（06 文档 §5.5）。
const DOC_ELITE_BAR_W := 2.05
const DOC_ELITE_BAR_H := 0.20

const EPS := 0.0005
## 防假绿哨兵：断言样本下限。
const EXPECTED_MIN_SAMPLES := 80

var _failures: Array[String] = []
var _samples := 0


func _ready() -> void:
	_check_doc_contract()
	_check_pop_doc_contract()
	_check_duration_band()
	_check_duration_decomposition()
	_check_turn_rate()
	_check_icon_size_table()
	_check_icon_offset()
	_check_lifecycle_composition()
	_check_rearm_and_gating()
	_check_prefab_contract()
	_check_texture_alpha()
	_check_pop_curve()
	_check_base_scale_preserved()
	_check_collision_free()
	_check_dismiss()
	await _check_wiring()
	await _check_wiring_end_to_end()
	_purge_transients()
	_expect(_samples >= EXPECTED_MIN_SAMPLES, "样本数 %d 低于下限 %d（疑似用例被跳过）" % [_samples, EXPECTED_MIN_SAMPLES])
	_report()


# ① 文档数字 ↔ 代码常量逐条一致。
func _check_doc_contract() -> void:
	var pairs := [
		["T_STARTUP_MIN", MonsterStartupProfile.T_STARTUP_MIN, DOC_T_STARTUP_MIN],
		["T_STARTUP_MAX", MonsterStartupProfile.T_STARTUP_MAX, DOC_T_STARTUP_MAX],
		["T_ROAR_MIN", MonsterStartupProfile.T_ROAR_MIN, DOC_T_ROAR_MIN],
		["YAW_RATE_DEG_PER_SEC", MonsterStartupProfile.YAW_RATE_DEG_PER_SEC, DOC_YAW_RATE],
		["STARTUP_JITTER_MAX", MonsterStartupProfile.STARTUP_JITTER_MAX, DOC_JITTER_MAX],
		["ICON_BAR_RATIO", MonsterStartupProfile.ICON_BAR_RATIO, DOC_ICON_BAR_RATIO],
		["ICON_EDGE_MIN_M", MonsterStartupProfile.ICON_EDGE_MIN_M, DOC_ICON_EDGE_MIN],
		["ICON_EDGE_MAX_M", MonsterStartupProfile.ICON_EDGE_MAX_M, DOC_ICON_EDGE_MAX],
		["ICON_BAR_GAP_RATIO", MonsterStartupProfile.ICON_BAR_GAP_RATIO, DOC_ICON_GAP_RATIO],
		["ICON_TAIL_SECONDS", MonsterStartupProfile.ICON_TAIL_SECONDS, DOC_ICON_TAIL],
		["ICON_FADE_SECONDS", MonsterStartupProfile.ICON_FADE_SECONDS, DOC_ICON_FADE],
		["REARM_AFTER_SECONDS", MonsterStartupProfile.REARM_AFTER_SECONDS, DOC_REARM_AFTER],
	]
	for pair in pairs:
		_samples += 1
		var name := String(pair[0])
		var actual: float = float(pair[1])
		var expected: float = float(pair[2])
		_expect(
			absf(actual - expected) <= EPS,
			"文档常量漂移：%s 文档为 %.4f，代码为 %.4f" % [name, expected, actual]
		)


# ② 时长窗口闭区间 + 两端可达。
func _check_duration_band() -> void:
	var lo := 999.0
	var hi := -1.0
	for yaw in [0.0, 15.0, 45.0, 90.0, 135.0, 180.0]:
		for jitter in [0.0, 0.05, 0.09, 0.18]:
			_samples += 1
			var t := MonsterStartupProfile.startup_seconds(yaw, jitter)
			lo = minf(lo, t)
			hi = maxf(hi, t)
			_expect(
				t >= DOC_T_STARTUP_MIN - EPS and t <= DOC_T_STARTUP_MAX + EPS,
				"启动时长越界：yaw=%.0f jitter=%.2f → %.4fs，应在 [%.2f, %.2f]" % [yaw, jitter, t, DOC_T_STARTUP_MIN, DOC_T_STARTUP_MAX]
			)
	_expect(absf(lo - DOC_T_STARTUP_MIN) <= EPS, "启动时长下界不可达：实得最小 %.4fs，文档 %.2fs" % [lo, DOC_T_STARTUP_MIN])
	_expect(absf(hi - DOC_T_STARTUP_MAX) <= EPS, "启动时长上界不可达：实得最大 %.4fs，文档 %.2fs" % [hi, DOC_T_STARTUP_MAX])


# ③ 吼叫段不短于下限；④ 转身 + 吼叫 == 总时长。
func _check_duration_decomposition() -> void:
	# 负向自测：359° 在几何上是「朝左差 1°」，不是「转身 359°」。
	# 不做归一化会用 359/520 = 0.69s 去转一个只要 0.002s 的角度，转身段直接顶穿启动窗口
	# —— 这条曾是真实缺陷，必须留一条断言钉住。
	var norm_cases := [
		{"raw": 359.0, "want": -1.0},
		{"raw": 361.0, "want": 1.0},
		# ±180° 是最短转向的歧义边界（左右一样远），约定统一取 -180；
		# 下游只用 absf()，符号不影响转身段时长，但约定必须唯一，否则断言无从写。
		{"raw": 180.0, "want": -180.0},
		{"raw": -180.0, "want": -180.0},
		{"raw": 359.9, "want": -0.1},
		{"raw": -359.0, "want": 1.0},
		{"raw": 540.0, "want": -180.0},
	]
	for case in norm_cases:
		_samples += 1
		var got := MonsterStartupProfile.normalize_delta_yaw(float(case["raw"]))
		_expect(
			absf(got - float(case["want"])) <= EPS,
			"转角归一化错误：%.0f° → %.2f°，应为 %.2f°" % [float(case["raw"]), got, float(case["want"])]
		)
	# 归一化后最大转角 180° ⇒ 转身段恒 ≤ 180/520 ≈ 0.346s，绝不可能超过启动窗口上限。
	_samples += 1
	_expect(
		MonsterStartupProfile.turn_seconds(359.0) <= MonsterStartupProfile.turn_seconds(180.0) + EPS,
		"359° 的转身段 %.4fs 超过 180° 的 %.4fs（归一化失效）" % [
			MonsterStartupProfile.turn_seconds(359.0), MonsterStartupProfile.turn_seconds(180.0)
		]
	)
	for yaw in [0.0, 5.0, 30.0, 90.0, 180.0, 359.0, -350.0, 725.0]:
		for jitter in [0.0, 0.09, 0.18]:
			_samples += 1
			var total := MonsterStartupProfile.startup_seconds(yaw, jitter)
			var turn := MonsterStartupProfile.turn_seconds(yaw)
			var roar := MonsterStartupProfile.roar_seconds(yaw, jitter)
			_expect(
				roar >= DOC_T_ROAR_MIN - EPS,
				"吼叫段 %.4fs 短于下限 %.2fs（yaw=%.0f jitter=%.2f）" % [roar, DOC_T_ROAR_MIN, yaw, jitter]
			)
			_expect(
				absf(turn + roar - total) <= EPS,
				"段时长不合：转身 %.4f + 吼叫 %.4f ≠ 总时长 %.4f（yaw=%.0f）" % [turn, roar, total, yaw]
			)
			_expect(
				turn >= -EPS and turn <= DOC_T_STARTUP_MAX + EPS,
				"转身段 %.4fs 不合理（yaw=%.0f）" % [turn, yaw]
			)


# ⑤ 转身速率：窗口被钳制时必须提高转速，且不低于基准。
func _check_turn_rate() -> void:
	for yaw in [0.0, 45.0, 90.0, 180.0]:
		for jitter in [0.0, 0.18]:
			_samples += 1
			var rate := MonsterStartupProfile.turn_rate_deg_per_sec(yaw, jitter)
			_expect(
				rate >= DOC_YAW_RATE - EPS,
				"转身速率 %.1f°/s 低于基准 %.1f°/s（yaw=%.0f jitter=%.2f）" % [rate, DOC_YAW_RATE, yaw, jitter]
			)
			# 用该速率把 yaw 转完，实际占用时间不得超过允许的转身窗口
			if float(yaw) > 0.0:
				var used: float = float(yaw) / rate
				var allowed: float = (
					MonsterStartupProfile.TURN_SHARE_MAX
					* MonsterStartupProfile.startup_seconds(float(yaw), float(jitter))
				)
				_expect(
					used <= allowed + EPS,
					"按 %.1f°/s 转头 %.0f° 需 %.4fs，超过允许窗口 %.4fs" % [rate, yaw, used, allowed]
				)


# ⑥ 图标尺寸按体型等比，且与文档尺寸表逐项一致。
func _check_icon_size_table() -> void:
	var prev_edge := -1.0
	for row in DOC_SIZE_TABLE:
		_samples += 1
		var bar_w := float(row["bar_w"])
		var kind := String(row["kind"])
		# 体型来源必须是 Enemy3D 的真表，不是第二份拷贝
		var live: Vector2 = Enemy3D.HEALTH_BAR_SIZE_BY_KIND.get(kind, Vector2(-1, -1))
		_expect(
			absf(live.x - bar_w) <= EPS and absf(live.y - float(row["bar_h"])) <= EPS,
			"%s 的头顶条尺寸漂移：Enemy3D 为 %s，文档为 (%.2f, %.2f)" % [kind, str(live), bar_w, float(row["bar_h"])]
		)
		var edge := MonsterStartupProfile.icon_edge_m(bar_w)
		_expect(
			absf(edge - float(row["edge"])) <= EPS,
			"%s 图标边长 %.4fm 与文档 %.4fm 不符" % [kind, edge, float(row["edge"])]
		)
		_expect(
			edge >= DOC_ICON_EDGE_MIN - EPS and edge <= DOC_ICON_EDGE_MAX + EPS,
			"%s 图标边长 %.4fm 越出钳制区间 [%.2f, %.2f]" % [kind, edge, DOC_ICON_EDGE_MIN, DOC_ICON_EDGE_MAX]
		)
		# 同体型怪（melee/ranged/ambusher 同为 1.38 条宽）边长必须相等，不得随枚举顺序乱变
		_expect(edge >= prev_edge, "%s 图标边长 %.4fm 随体型下降（前一行 %.4fm）" % [kind, edge, prev_edge])
		prev_edge = edge
	# 精英头顶条（2.05m）也必须落在钳制区间内
	_samples += 1
	var elite_edge := MonsterStartupProfile.icon_edge_m(DOC_ELITE_BAR_W)
	_expect(
		absf(elite_edge - 0.861) <= EPS,
		"精英（条宽 %.2fm）图标边长 %.4fm 与文档 0.8610m 不符" % [DOC_ELITE_BAR_W, elite_edge]
	)
	# 极端值必须被钳制，不能无界放大/缩小
	_samples += 1
	_expect(
		absf(MonsterStartupProfile.icon_edge_m(0.01) - DOC_ICON_EDGE_MIN) <= EPS
			and absf(MonsterStartupProfile.icon_edge_m(99.0) - DOC_ICON_EDGE_MAX) <= EPS,
		"图标边长未被钳制：极小体型 → %.4f，极大体型 → %.4f" % [
			MonsterStartupProfile.icon_edge_m(0.01), MonsterStartupProfile.icon_edge_m(99.0)
		]
	)


# ⑦ 图标垂直偏移：坐在血条正上方，不遮血条；间隙按比例且够大。
func _check_icon_offset() -> void:
	for row in DOC_SIZE_TABLE:
		_samples += 1
		var bar_w := float(row["bar_w"])
		var bar_h := float(row["bar_h"])
		var edge := MonsterStartupProfile.icon_edge_m(bar_w)
		var offset := MonsterStartupProfile.icon_offset_y_m(bar_w, bar_h)
		var expected := bar_h * 0.5 + DOC_ICON_GAP_RATIO * edge + edge * 0.5
		_expect(
			absf(offset - expected) <= EPS,
			"%s 图标偏移 %.4fm 与公式 %.4fm 不符" % [String(row["kind"]), offset, expected]
		)
		# 文档表格里印出来的那一列数字，逐格核对（防止只改公式没改文档）。
		_samples += 1
		_expect(
			absf(offset - float(row["offset"])) <= 0.0006,
			"%s 偏移代码为 %.4fm，但文档 §6.1.4 表格印的是 %.4fm" % [String(row["kind"]), offset, float(row["offset"])]
		)
		# 图标底边必须严格高于血条顶边（否则会盖住血条）
		var icon_bottom := offset - edge * 0.5
		var bar_top := bar_h * 0.5
		_expect(
			icon_bottom >= bar_top + MIN_ICON_GAP_RATIO * edge - EPS,
			"%s 图标底边 %.4fm 与血条顶边 %.4fm 的间隙仅 %.4fm，小于 %.2f×图标边长 %.4fm"
			% [
				String(row["kind"]), icon_bottom, bar_top, icon_bottom - bar_top,
				MIN_ICON_GAP_RATIO, edge,
			]
		)
		# 间隙必须**按图标等比**：gap / edge 恒定 ⇒ 任何体型观感一致。
		_samples += 1
		var gap := icon_bottom - bar_top
		_expect(
			absf(gap / edge - DOC_ICON_GAP_RATIO) <= EPS,
			"%s 的 间隙/图标 = %.4f，应恒为 %.2f（否则换贴图就会把间距吃掉）"
			% [String(row["kind"]), gap / edge, DOC_ICON_GAP_RATIO]
		)
	# 单体型（1.38 条宽）的实测值，钉住具体数字便于对照预览图。
	_samples += 1
	_expect(
		absf(MonsterStartupProfile.icon_offset_y_m(1.38, 0.15) - 0.5390) <= EPS,
		"小僵尸档偏移 %.4fm，应为 0.5390m" % MonsterStartupProfile.icon_offset_y_m(1.38, 0.15)
	)


# ⑧ 图标生命周期 = 吼叫段 + 尾巴 + 淡出。
func _check_lifecycle_composition() -> void:
	for yaw in [0.0, 90.0, 180.0]:
		for jitter in [0.0, 0.18]:
			_samples += 1
			var roar := MonsterStartupProfile.roar_seconds(yaw, jitter)
			var hold := MonsterStartupProfile.icon_hold_seconds(yaw, jitter)
			var life := MonsterStartupProfile.icon_lifetime_seconds(yaw, jitter)
			_expect(
				absf(hold - (roar + DOC_ICON_TAIL)) <= EPS,
				"图标保持段 %.4fs ≠ 吼叫 %.4fs + 尾巴 %.2fs（yaw=%.0f）" % [hold, roar, DOC_ICON_TAIL, yaw]
			)
			_expect(
				absf(life - (hold + DOC_ICON_FADE)) <= EPS,
				"图标 lifetime %.4fs ≠ 保持 %.4fs + 淡出 %.2fs（yaw=%.0f）" % [life, hold, DOC_ICON_FADE, yaw]
			)
			_expect(life > 0.0 and life < 2.0, "图标 lifetime %.4fs 不合理（yaw=%.0f）" % [life, yaw])


# ⑨ 重播周期与种类门禁。
func _check_rearm_and_gating() -> void:
	_samples += 1
	_expect(MonsterStartupProfile.REARM_AFTER_SECONDS >= 0.0, "重播静默窗口为负")
	for kind in ["melee_chaser", "ranged_caster", "summoner", "exploder", "ambusher", "fat_zombie03"]:
		_samples += 1
		_expect(MonsterStartupProfile.plays_startup(kind), "%s 应播放启动过程" % kind)
	_samples += 1
	_expect(not MonsterStartupProfile.plays_startup("boss"), "Boss 有独立激活流程，不得重复播启动过程")


# ⑩ Prefab + Sprite3D 契约。
func _check_prefab_contract() -> void:
	_samples += 1
	var effect := _instantiate()
	if effect == null:
		return
	add_child(effect)
	effect.activate(Vector3(1.0, 2.0, 3.0), Color.WHITE, 0.5796, {})
	var sprite := effect.get_node_or_null("RoarIconSprite") as Sprite3D
	_samples += 1
	if sprite == null:
		_fail("Prefab 内找不到 Sprite3D 子节点 RoarIconSprite")
		effect.free()
		return
	_expect(sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "图标 Sprite3D 未开启 billboard（不会朝向摄像机）")
	_expect(sprite.no_depth_test, "图标 Sprite3D 未关闭深度测试（会被怪物身体挡住）")
	_expect(absf(sprite.pixel_size - EXPECTED_PIXEL_SIZE) <= 0.000001, "pixel_size=%.4f，应为 %.3f（与头顶血条同口径）" % [sprite.pixel_size, EXPECTED_PIXEL_SIZE])
	_expect(sprite.texture != null, "图标 Sprite3D 未挂贴图")
	_expect(
		absf(effect.get_icon_edge_m() - 0.5796) <= EPS,
		"传入 0.5796m 后 get_icon_edge_m()=%.4f" % effect.get_icon_edge_m()
	)
	# 位置跟随：activate 的世界坐标应落到节点上（无 follow 挂点时）
	_expect(
		effect.global_position.distance_to(Vector3(1.0, 2.0, 3.0)) <= EPS,
		"无 follow 挂点时图标未落在传入世界坐标，实为 %s" % str(effect.global_position)
	)
	effect.free()


# ⑪ 贴图必须真实带 alpha（透明底），不是不透明色块。
func _check_texture_alpha() -> void:
	_samples += 1
	var tex := load(ICON_TEXTURE_PATH) as Texture2D
	if tex == null:
		_fail("图标贴图加载失败：%s" % ICON_TEXTURE_PATH)
		return
	var img := tex.get_image()
	_samples += 1
	if img == null:
		_fail("图标贴图无法取到 Image")
		return
	_expect(
		img.get_width() == EXPECTED_TEXTURE_EDGE and img.get_height() == EXPECTED_TEXTURE_EDGE,
		"图标贴图尺寸 %dx%d，应为 %d²" % [img.get_width(), img.get_height(), EXPECTED_TEXTURE_EDGE]
	)
	# 四角必须透明（安全边距），中心必须不透明
	var corners := [
		Vector2i(0, 0),
		Vector2i(img.get_width() - 1, 0),
		Vector2i(0, img.get_height() - 1),
		Vector2i(img.get_width() - 1, img.get_height() - 1),
	]
	for c in corners:
		_samples += 1
		_expect(
			img.get_pixelv(c).a < 0.2,
			"贴图角点 %s alpha=%.3f，安全边距不成立（疑似不透明底色）" % [str(c), img.get_pixelv(c).a]
		)
	_samples += 1
	var center_alpha := img.get_pixelv(Vector2i(img.get_width() / 2, img.get_height() / 2 + 20)).a
	_expect(center_alpha > 0.5, "贴图中心 alpha=%.3f，图标主体不可见" % center_alpha)
	# 必须存在大量半透明/透明像素（真透明底），且存在足量不透明像素（图形真的在）
	var transparent := 0
	var opaque := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var a := img.get_pixel(x, y).a
			if a < 0.2:
				transparent += 1
			elif a > 0.8:
				opaque += 1
	_samples += 1
	_expect(transparent > 200, "透明像素仅 %d 个，疑似不透明底" % transparent)
	_expect(opaque > 200, "不透明像素仅 %d 个，图标图形过小或缺失" % opaque)


# ⑫ 弹出 → 回稳 → **停顿** 四段曲线；③ 必须是真静止（业主 2026-10-14：要「停顿一下」）。
func _check_pop_curve() -> void:
	_samples += 1
	var effect := _instantiate()
	if effect == null:
		return
	add_child(effect)
	effect.activate(Vector3.ZERO, Color.WHITE, 0.5796, {"hold_seconds": 0.55, "fade_seconds": 0.18})
	var sprite := effect.get_node_or_null("RoarIconSprite") as Sprite3D
	if sprite == null:
		_fail("弹出曲线用例：找不到 Sprite3D")
		effect.free()
		return
	var base: float = 0.5796 / (float(EXPECTED_TEXTURE_EDGE) * EXPECTED_PIXEL_SIZE)

	# ① 弹出段（含过冲峰值）与 ② 回稳段端点。
	var samples := [
		{"t": 0.0, "mult": DOC_POP_START},
		{"t": DOC_POP_PEAK_AT, "mult": DOC_POP_PEAK},
		{"t": DOC_POP_SETTLE_AT, "mult": 1.00},
	]
	for entry in samples:
		_samples += 1
		effect._on_tick(float(entry["t"]), effect.lifetime)
		var want: float = base * float(entry["mult"])
		_expect(
			absf(sprite.scale.x - want) <= 0.002,
			"弹出曲线 t=%.2f 时 scale=%.4f，应为 %.4f（基准 %.4f × %.2f）"
			% [float(entry["t"]), sprite.scale.x, want, base, float(entry["mult"])]
		)

	# ① 过冲必须**真的弹出去过**（峰值 > 1.0），否则「弹」读不出来。
	_samples += 1
	_expect(
		DOC_POP_PEAK > 1.0,
		"过冲峰值 %.3f 不大于 1.0，视觉上不会有「弹」的感觉" % DOC_POP_PEAK
	)

	# ③ 停顿段：整段扫一遍，scale 与 alpha 必须**严格**不变。
	# 这是本次需求的正面判据 —— 只要有人在停顿段里塞缓动或脉动，这里立刻红。
	var still_sec: float = effect.get_hold_still_seconds()
	_samples += 1
	_expect(
		still_sec > 0.0,
		"停顿段时长为 %.4fs —— 保持段（%.2fs）太短，被「弹出+回稳」吃光了"
		% [still_sec, effect.hold_seconds]
	)
	var probes := [
		DOC_POP_SETTLE_AT,
		DOC_POP_SETTLE_AT + 0.02,
		(DOC_POP_SETTLE_AT + effect.hold_seconds) * 0.5,
		effect.hold_seconds - 0.01,
	]
	for t in probes:
		var tt: float = maxf(float(t), DOC_POP_SETTLE_AT)
		if tt > effect.hold_seconds:
			continue
		_samples += 1
		effect._on_tick(tt, effect.lifetime)
		_expect(
			absf(sprite.scale.x - base) <= 0.0005,
			"停顿段 t=%.4f 时 scale=%.5f ≠ 基准 %.5f —— 停顿段不是真静止"
			% [tt, sprite.scale.x, base]
		)
		_samples += 1
		_expect(
			sprite.modulate.a >= 0.999,
			"停顿段 t=%.4f 时 alpha=%.4f < 1.0 —— 停顿段不该已经开始淡出" % [tt, sprite.modulate.a]
		)

	# ④ 淡出只在 hold 之后发生：hold 之前 alpha 必须还是满的。
	_samples += 1
	effect._on_tick(effect.hold_seconds * 0.99, effect.lifetime)
	_expect(
		sprite.modulate.a >= 0.999,
		"保持段末尾 alpha=%.4f，淡出提前了" % sprite.modulate.a
	)
	effect.free()


# ⑫b VFX 侧文档契约：弹出/停顿的数值也必须与文档一致。
func _check_pop_doc_contract() -> void:
	var pairs := [
		["POP_START_SCALE", VfxMonsterRoarIcon3D.POP_START_SCALE, DOC_POP_START],
		["POP_PEAK_SCALE", VfxMonsterRoarIcon3D.POP_PEAK_SCALE, DOC_POP_PEAK],
		["POP_PEAK_AT", VfxMonsterRoarIcon3D.POP_PEAK_AT, DOC_POP_PEAK_AT],
		["POP_SETTLE_AT", VfxMonsterRoarIcon3D.POP_SETTLE_AT, DOC_POP_SETTLE_AT],
	]
	for pair in pairs:
		_samples += 1
		var name := String(pair[0])
		var actual: float = float(pair[1])
		var expected: float = float(pair[2])
		_expect(
			absf(actual - expected) <= EPS,
			"弹出曲线常量漂移：%s 文档为 %.4f，代码为 %.4f" % [name, expected, actual]
		)


# ⑬ 回归：体型缩放不得被弹出动画覆盖（曾把基准缩放乘丢）。
func _check_base_scale_preserved() -> void:
	for edge in [0.45, 0.5796, 0.756, 1.113, 1.20]:
		_samples += 1
		var effect := _instantiate()
		if effect == null:
			return
		add_child(effect)
		effect.activate(Vector3.ZERO, Color.WHITE, edge, {"hold_seconds": 0.55, "fade_seconds": 0.18})
		var sprite := effect.get_node_or_null("RoarIconSprite") as Sprite3D
		if sprite == null:
			_fail("基准缩放用例：找不到 Sprite3D")
			effect.free()
			continue
		effect._on_tick(0.40, effect.lifetime)  # 弹出已结束、仍在保持段
		var want: float = float(edge) / (float(EXPECTED_TEXTURE_EDGE) * EXPECTED_PIXEL_SIZE)
		_expect(
			absf(sprite.scale.x - want) <= 0.002,
			"传入边长 %.4fm：弹出结束后 scale=%.4f，应为 %.4f（体型缩放被弹出动画覆盖）" % [float(edge), sprite.scale.x, want]
		)
		# 关卡额外缩放：Enemy3D.scale 变化时传入边长确实变小时，sprite 缩放必须线性跟随。
		# 注意下限钳制是设计的一部分 —— 小于 ICON_EDGE_MIN_M 的请求会被抬回下限，
		# 所以期望值必须按同一条钳制规则算，不能拿原始 half 当期望。
		var half: float = float(edge) * 0.5
		effect.activate(Vector3.ZERO, Color.WHITE, half, {"hold_seconds": 0.55, "fade_seconds": 0.18})
		effect._on_tick(0.40, effect.lifetime)
		var clamped_half: float = clampf(half, DOC_ICON_EDGE_MIN, DOC_ICON_EDGE_MAX)
		var want_half: float = clamped_half / (float(EXPECTED_TEXTURE_EDGE) * EXPECTED_PIXEL_SIZE)
		_expect(
			absf(effect.get_icon_edge_m() - clamped_half) <= EPS,
			"请求边长 %.4fm 时 get_icon_edge_m()=%.4f，应为钳制后的 %.4f" % [half, effect.get_icon_edge_m(), clamped_half]
		)
		_expect(
			absf(sprite.scale.x - want_half) <= 0.002,
			"边长 %.4fm 时 scale=%.4f，应为 %.4f（尺寸参数非线性，疑似基准缩放未随 re-activate 更新）" % [clamped_half, sprite.scale.x, want_half]
		)
		_expect(
			absf(sprite.scale.x - want_half) <= 0.002,
			"边长 %.4fm 时 scale=%.4f，应为 %.4f（尺寸参数非线性）" % [half, sprite.scale.x, want_half]
		)
		effect.free()


# ⑭ 纯视觉：不得含碰撞体。
func _check_collision_free() -> void:
	_samples += 1
	var effect := _instantiate()
	if effect == null:
		return
	add_child(effect)
	effect.activate(Vector3.ZERO, Color.WHITE, 0.5796, {})
	var nodes := 0
	var stack: Array = [effect]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		nodes += 1
		if node is CollisionObject3D or node is CollisionShape3D or node is Area3D:
			_fail("头顶图标 Prefab 含碰撞体节点：%s" % node.get_class())
		for child in node.get_children():
			stack.append(child)
	_expect(nodes >= 2, "图标 Prefab 节点数仅 %d，疑似空壳" % nodes)
	effect.free()


# ⑮ dismiss 幂等且提前退场。
func _check_dismiss() -> void:
	_samples += 1
	var effect := _instantiate()
	if effect == null:
		return
	add_child(effect)
	effect.activate(Vector3.ZERO, Color.WHITE, 0.5796, {"hold_seconds": 0.55, "fade_seconds": 0.18})
	var early := [0]
	effect.roar_icon_dismissed.connect(func(was_early: bool) -> void: early[0] += 1 if was_early else 0)
	effect.dismiss()
	_samples += 1
	_expect(early[0] == 1, "dismiss() 未发出提前退场信号，收到 %d 次" % early[0])
	effect.dismiss()
	_samples += 1
	_expect(early[0] == 1, "dismiss() 不幂等：第二次又发了信号（共 %d 次）" % early[0])
	_samples += 1
	_expect(effect.lifetime > 0.0, "dismiss 后 lifetime 被破坏")
	if is_instance_valid(effect):
		effect.free()


# ⑯ 接线：确认目标后，怪物必须**真的**在 alert 停住 ≥0.30s 才进 chase。
#
# 背景：本条是业主回报「怪物还是直接冲过来」的直接回归。只验公式与 Prefab 是不够的 ——
# `Enemy3D._physics_process` 里那句「alert 超过 alert_duration 就转 chase」会把启动过程
# 直接跨过去，公式再对也没用。所以这里跑真实 Enemy3D，断言状态与位移。
#
# 驱动方式：拿真场景里的 Enemy3D，关掉它自己的 `_physics_process`（那会去问 MonsterAIManager
# 要决策、把目标清掉），改由本用例在**真实物理帧**里复刻该函数在 alert 分支前做的两件事：
# `_state_time += delta` 与 `_tick_monster_startup(...)`。物理帧保证 `move_and_slide` 合法。
func _check_wiring() -> void:
	# ① 大转角（目标在正后方 180°）⇒ 该走最长那一档。
	await _wiring_case(Vector3(0.0, 0.0, 8.0), 0.0, "目标在正后方 180°")
	# ② 已正对目标（0°）⇒ 转身段为 0，总时长被下限兜住，仍不得低于 0.30s。
	await _wiring_case(Vector3(0.0, 0.0, 8.0), PI, "已正对目标 0°")
	# ③ Boss 豁免：有自己的激活流程，不得叠加通用启动过程。
	await _wiring_boss_exempt()
	# ④ 打断收口：alert 期间死亡/硬直必须撤掉图标（「已死还在吼」是假信息）。
	await _wiring_interrupt()
	# ⑤ 源码级回归钉：那句无条件转 chase 必须已经被启动过程门禁取代。
	_wiring_source_guard()


## 跑一个启动用例：`target_offset` 是目标相对怪的位置，`enemy_yaw` 是怪的初始朝向。
func _wiring_case(target_offset: Vector3, enemy_yaw: float, label: String) -> void:
	var enemy := _spawn_enemy(WIRING_KIND, Vector3.ZERO)
	if enemy == null:
		return
	enemy.rotation.y = enemy_yaw
	var target := _spawn_fake_target(target_offset)
	# 让怪自己的 AI 帧不参与：它每帧都会向 MonsterAIManager 要决策并覆写 `_target`。
	enemy.set_physics_process(false)
	enemy._position_overhead_health_bar()

	var to_target := target.global_position - enemy.global_position
	_samples += 1
	_expect(enemy.ai_state == "idle", "%s：起始状态应为 idle，实为 %s" % [label, enemy.ai_state])

	var began: bool = enemy._begin_monster_startup(to_target)
	_samples += 1
	_expect(began, "%s：`_begin_monster_startup` 拒绝了启动，怪物会直接冲过来" % label)
	if not began:
		_cleanup(enemy, target)
		return

	# 复刻 `_physics_process` 在 alert 分支之前做的事：先推进 `_state_time`。
	if enemy.ai_state == "idle":
		enemy.transition_to("alert")

	var total: float = enemy._startup_total
	var turn_sec: float = enemy._startup_turn_sec
	_samples += 1
	_expect(
		total >= DOC_T_STARTUP_MIN - EPS and total <= DOC_T_STARTUP_MAX + EPS,
		"%s：启动总时长 %.4fs 越出 [%.2f, %.2f]" % [label, total, DOC_T_STARTUP_MIN, DOC_T_STARTUP_MAX]
	)

	var start_pos := enemy.global_position
	var elapsed := 0.0
	var chase_before_total := false
	var gate_leaked := false
	var icon_seen := false
	var icon_seen_at := -1.0
	var icon_class_ok := true
	var icon_size_ok := true
	var icon_offset_ok := true
	var alert_duration: float = enemy._ai_param(
		"alert_duration_sec", float(Enemy3D.PROFILES[WIRING_KIND].get("alert", 0.28))
	)
	var steps := 0
	while steps < WIRING_MAX_STEPS:
		steps += 1
		# 复刻 `_physics_process` 在该分支前做的唯一一件事，然后调用**同一个**门禁函数
		# —— 不是复刻它的逻辑，而是直接调它。这样门禁一旦被绕过，本用例必然红。
		enemy._state_time += WIRING_STEP
		elapsed += WIRING_STEP
		var blocked: bool = enemy._tick_alert_state(to_target, WIRING_STEP, alert_duration)
		if elapsed < total - WIRING_STEP and not blocked and enemy.ai_state == "chase":
			gate_leaked = true
		# 图标存在性：正走在段 B 时，头顶必须挂着 FX01-16 的实例。
		var icon := enemy.get_node_or_null("OverheadHealthBar/VfxMonsterRoarIcon3D")
		if icon != null:
			if not icon_seen:
				icon_seen = true
				icon_seen_at = elapsed
				icon_class_ok = icon is VfxMonsterRoarIcon3D
				# 尺寸必须等于该体型算出来的边长（这里是精确等式，不是范围）
				var bar_w: float = enemy._overhead_health_size.x
				var want_edge := MonsterStartupProfile.icon_edge_m(bar_w)
				icon_size_ok = absf((icon as VfxMonsterRoarIcon3D).get_icon_edge_m() - want_edge) <= EPS
				var want_offset := MonsterStartupProfile.icon_offset_y_m(
					bar_w, enemy._overhead_health_size.y
				)
				icon_offset_ok = absf((icon as Node3D).position.y - want_offset) <= 0.002
		if enemy.ai_state == "chase":
			if elapsed < total - EPS:
				chase_before_total = true
			break
		await get_tree().physics_frame

	_samples += 1
	_expect(
		not gate_leaked,
		"%s：启动过程没走完，`_tick_alert_state` 就放行了（返回 false）—— 这正是「直接冲过来」的回归" % label
	)

	_samples += 1
	_expect(
		not chase_before_total,
		"%s：在启动过程走完（%.4fs）之前就进了 chase —— 这正是「直接冲过来」的回归" % [label, total]
	)
	_samples += 1
	_expect(
		enemy.ai_state == "chase",
		"%s：%d 帧后仍未进入 chase（状态 %s），启动过程卡住了" % [label, steps, enemy.ai_state]
	)
	_samples += 1
	_expect(
		elapsed >= DOC_T_STARTUP_MIN - EPS,
		"%s：从进入到放行只用了 %.4fs，短于 %.2fs 下限" % [label, elapsed, DOC_T_STARTUP_MIN]
	)
	# 位移：启动过程全程制动，不该朝玩家推进。
	var drift := Vector2(enemy.global_position.x - start_pos.x, enemy.global_position.z - start_pos.z).length()
	_samples += 1
	_expect(
		drift <= WIRING_DRIFT_TOLERANCE_M,
		"%s：启动过程内水平位移 %.4fm，超过容差 %.2fm（怪物边走边吼 = 没有可反应窗口）"
		% [label, drift, WIRING_DRIFT_TOLERANCE_M]
	)
	# 图标：必须在段 B 起吼（≥ 转身段），且类/尺寸/偏移都对。
	_samples += 1
	_expect(icon_seen, "%s：整个启动过程都没出现头顶吼叫图标" % label)
	_samples += 1
	_expect(icon_class_ok, "%s：头顶挂的节点不是 VfxMonsterRoarIcon3D（可能是空壳）" % label)
	_samples += 1
	_expect(icon_size_ok, "%s：图标世界边长与「血条宽 × 0.42」公式不符" % label)
	_samples += 1
	_expect(icon_offset_ok, "%s：图标相对血条槽根的偏移与公式不符" % label)
	_samples += 1
	_expect(
		icon_seen_at >= turn_sec - EPS,
		"%s：图标在 %.4fs 就出现，早于转身段结束（%.4fs）—— 应当先转过来再吼"
		% [label, icon_seen_at, turn_sec]
	)
	_cleanup(enemy, target)


## ③ Boss 不得播放通用启动过程。
func _wiring_boss_exempt() -> void:
	var boss := _spawn_enemy(WIRING_BOSS_KIND, Vector3.ZERO)
	if boss == null:
		return
	var target := _spawn_fake_target(Vector3(0.0, 0.0, 8.0))
	boss.set_physics_process(false)
	_samples += 1
	_expect(
		not boss._begin_monster_startup(target.global_position - boss.global_position),
		"Boss 不应进入通用启动过程（它有自己的激活流程）"
	)
	_samples += 1
	_expect(not boss._startup_active, "Boss 的启动过程被置为 active")
	_cleanup(boss, target)


## ④ 打断收口：alert 中途转硬直/死亡必须撤掉图标。
func _wiring_interrupt() -> void:
	for interrupt_state in ["stagger", "dead"]:
		var enemy := _spawn_enemy(WIRING_KIND, Vector3.ZERO)
		if enemy == null:
			return
		enemy.rotation.y = PI
		var target := _spawn_fake_target(Vector3(0.0, 0.0, 8.0))
		enemy.set_physics_process(false)
		enemy._position_overhead_health_bar()
		var to_target := target.global_position - enemy.global_position
		if not enemy._begin_monster_startup(to_target):
			_fail("打断用例：启动过程未开始")
			_cleanup(enemy, target)
			continue
		if enemy.ai_state == "idle":
			enemy.transition_to("alert")
		# 推到段 B，确保图标已经挂上
		var interrupt_alert_duration: float = enemy._ai_param(
			"alert_duration_sec", float(Enemy3D.PROFILES[WIRING_KIND].get("alert", 0.28))
		)
		var guard := 0
		while guard < WIRING_MAX_STEPS:
			guard += 1
			enemy._state_time += WIRING_STEP
			enemy._tick_alert_state(to_target, WIRING_STEP, interrupt_alert_duration)
			if enemy._roar_icon_fired:
				break
			if enemy.ai_state != "alert":
				break
			await get_tree().physics_frame
		_samples += 1
		_expect(enemy._roar_icon_fired, "打断用例：%s 前图标没来得及出现，用例无效" % interrupt_state)
		var icon_before := enemy.get_node_or_null("OverheadHealthBar/VfxMonsterRoarIcon3D")
		_samples += 1
		_expect(icon_before != null, "打断用例：%s 前头顶没有图标" % interrupt_state)

		enemy.transition_to(interrupt_state, "wiring_interrupt_test")
		_samples += 1
		_expect(
			not enemy._startup_active,
			"转入 %s 后启动过程仍在计时（应当在 transition_to 里被收掉）" % interrupt_state
		)
		_samples += 1
		_expect(
			enemy._roar_icon == null,
			"转入 %s 后实例引用没清空（潜在悬挂引用）" % interrupt_state
		)
		# 图标节点必须已经退场：dismiss → _retire → queue_free（下一帧生效或已不可见）
		var icon_after := enemy.get_node_or_null("OverheadHealthBar/VfxMonsterRoarIcon3D")
		_samples += 1
		_expect(
			icon_after == null or not (icon_after as Node3D).visible,
			"转入 %s 后头顶图标仍在显示 —— 就是「已死还在吼」的假信息" % interrupt_state
		)
		_cleanup(enemy, target)


## ⑤ 源码级回归钉：alert 分支必须由启动过程门禁，不能退回无条件转 chase。
##
## 读源码做断言在本仓有先例（弹壳「脚本内无任何物理 API」就是源码级静态门禁）。
## 这条钉的是**接线本身**：公式对、Prefab 对，但状态机把它跨过去，玩家一样看不到效果。
func _wiring_source_guard() -> void:
	var path := "res://src/enemy3d/Enemy3D.gd"
	var text := FileAccess.get_file_as_string(path)
	_samples += 1
	if text.is_empty():
		_fail("源码回归钉：读不到 %s" % path)
		return
	_samples += 1
	_expect(
		not text.contains('if ai_state == "alert" and _state_time > alert_duration:'),
		"源码回归钉：`alert 超时直接转 chase` 的无条件分支又回来了 —— 启动过程会被完全跨过"
	)
	_samples += 1
	_expect(
		text.contains("_tick_alert_state(to_target, delta, alert_duration)"),
		"源码回归钉：`_physics_process` 没有走 `_tick_alert_state` —— 门禁被绕开了"
	)
	_samples += 1
	_expect(
		text.contains("_tick_monster_startup("),
		"源码回归钉：`_tick_alert_state` 里没有调用 `_tick_monster_startup` —— 启动过程没接上"
	)
	_samples += 1
	_expect(
		text.contains("_begin_monster_startup(to_target)"),
		"源码回归钉：确认目标后没有调用 `_begin_monster_startup` —— 启动过程不会被触发"
	)
	_samples += 1
	_expect(
		text.contains("_cancel_monster_startup()"),
		"源码回归钉：`transition_to` 里没有中断收口 —— 会出现「已死还在吼」"
	)


# ⑰ 端到端：真 AI + 真 `_physics_process` + 真玩家，验证「玩家实际会看到什么」。
#
# 前面 ⑯ 是白盒（直接调门禁函数），本条是黑盒：不碰任何私有函数，只让引擎按真实节拍跑，
# 然后断言「怪从警觉到进入追击花了多久」和「这段时间里它有没有贴上来」。
# 这两条合起来正是业主原话里的现象：怪物不能「直接冲过来」。
func _check_wiring_end_to_end() -> void:
	var player := PLAYER_SCENE.instantiate() as Player3D
	if player == null:
		_fail("端到端用例：Player3D 实例化失败，无法验证真实观感")
		return
	player.start_with_weapon = false
	# 怪 forward = -Z，玩家放正前方 7m（< engage 13.5m，必然触发警觉）。
	player.position = Vector3(0.0, 0.0, -7.0)
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)

	_add_ground()

	var enemy := _spawn_enemy(WIRING_KIND, Vector3.ZERO)
	if enemy == null:
		player.queue_free()
		return
	enemy.rotation.y = 0.0

	var start_gap := enemy.global_position.distance_to(player.global_position)
	var t := 0.0
	var alert_started_at := -1.0
	var chase_at := -1.0
	var min_gap_in_alert := start_gap
	var saw_icon := false
	var frames := 0
	# 上限 3 秒：0.60s 启动 + 追击足够进 telegraph。
	while frames < 180:
		frames += 1
		await get_tree().physics_frame
		t += WIRING_STEP
		if enemy.ai_state == "alert":
			if alert_started_at < 0.0:
				alert_started_at = t
			# 警觉窗口内观测到的最近距离 —— 直接量「有没有贴上来」。
			min_gap_in_alert = minf(
				min_gap_in_alert, enemy.global_position.distance_to(player.global_position)
			)
		if enemy.get_node_or_null("OverheadHealthBar/VfxMonsterRoarIcon3D") != null:
			saw_icon = true
		if enemy.ai_state == "chase":
			chase_at = t
			break

	_samples += 1
	_expect(alert_started_at >= 0.0, "端到端：怪始终没进入 alert，AI 没认出玩家（距离 %.2fm）" % start_gap)
	if alert_started_at < 0.0:
		_cleanup_e2e(enemy, player)
		return
	_samples += 1
	_expect(chase_at >= 0.0, "端到端：3 秒内没进入 chase，卡在 %s" % enemy.ai_state)
	if chase_at < 0.0:
		_cleanup_e2e(enemy, player)
		return

	# ① 从警觉到放行的时长。
	# 阈值**不扣物理帧余量** —— 扣了就没意义：接线前的基线 alert_duration 是 0.28s，
	# 与下限 0.30s 只差一帧（0.0167s），一扣就分不出来了（实测负向对照会假绿）。
	var hold_time := chase_at - alert_started_at
	_samples += 1
	_expect(
		hold_time >= DOC_T_STARTUP_MIN - 0.001,
		"端到端：从警觉到追击只用了 %.4fs，短于 %.2fs —— 玩家看到的就是「直接冲过来」"
		% [hold_time, DOC_T_STARTUP_MIN]
	)
	_samples += 1
	_expect(
		hold_time <= DOC_T_STARTUP_MAX + 4.0 * WIRING_STEP,
		"端到端：警觉到追击拖了 %.4fs，超过窗口上限 %.2fs 太多" % [hold_time, DOC_T_STARTUP_MAX]
	)
	# ② 启动窗口内不许贴上来（0.5m 容差给物理分离推挤与贴地）。
	var closed := start_gap - min_gap_in_alert
	_samples += 1
	_expect(
		closed <= 0.5,
		"端到端：启动窗口内向玩家推进了 %.4fm（%.2f → %.2f）—— 可反应窗口不成立"
		% [closed, start_gap, min_gap_in_alert]
	)
	# ③ 真跑起来时头顶图标必须真的出现过。
	_samples += 1
	_expect(saw_icon, "端到端：真实运行中头顶吼叫图标从未出现")
	print(
		"[e2e] 警觉→追击 = %.4fs（窗口 [%.2f, %.2f]）；警觉期内最近距离 %.4fm（起始 %.2f，推进 %.4fm）；图标出现=%s"
		% [hold_time, DOC_T_STARTUP_MIN, DOC_T_STARTUP_MAX, min_gap_in_alert, start_gap, closed, saw_icon]
	)
	_cleanup_e2e(enemy, player)


func _cleanup_e2e(enemy: Node, player: Node) -> void:
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()


## 端到端要跑重力与 `move_and_slide`，脚下必须有承重面，否则怪会掉出可行走层被判死。
func _add_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "E2EGround"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.5, 0.0)
	# 与世界静态几何同层（Enemy3D 的 collision_mask = 1）。
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)


func _spawn_enemy(kind: String, position: Vector3) -> Enemy3D:
	var node := ENEMY_SCENE.instantiate()
	var enemy := node as Enemy3D
	# 硬门禁：脚本编译失败时 `as Enemy3D` 会静默给 null，后面的断言会全部「无效通过」。
	# 本仓当前有别的会话在改 Dungeon3D/MonsterAIManager，脚本链随时可能编译不过 ——
	# 那种情况下必须**红**，不能假装绿。
	_samples += 1
	if enemy == null:
		_fail(
			"无法实例化 Enemy3D（脚本链编译失败）—— 本用例的其余断言全部无效，"
			+ "请先修 `src/enemy3d/Enemy3D.gd` 的依赖（常见来源：Dungeon3D / MonsterAIManager 解析失败）"
		)
		if node != null:
			node.free()
		return null
	enemy.enemy_kind = kind
	enemy.room_id = "wiring_test_room"
	enemy.enemy_data = {"spawn_index": 0, "floor": 1}
	enemy.position = position
	add_child(enemy)
	return enemy


## 假目标：只要能提供 `current_hp` 与 `global_position` 就够（启动过程只读这两个）。
func _spawn_fake_target(position: Vector3) -> Node3D:
	var target := Node3D.new()
	target.name = "FakeTarget"
	target.position = position
	target.set_script(_fake_target_script())
	add_child(target)
	return target


func _fake_target_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar current_hp := 100\n"
	script.reload()
	return script


func _cleanup(enemy: Node, target: Node) -> void:
	if is_instance_valid(enemy):
		enemy.queue_free()
	if is_instance_valid(target):
		target.queue_free()


func _instantiate() -> Node3D:
	_samples += 1
	if ROAR_SCENE == null:
		_fail("吼叫图标 Prefab 加载失败：vfx_monster_roar_icon_root_top3d.tscn")
		return null
	var node := ROAR_SCENE.instantiate()
	if node == null:
		_fail("吼叫图标 Prefab instantiate 返回 null")
		return null
	return node as Node3D


func _purge_transients() -> void:
	for child in get_children():
		child.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("MONSTER_STARTUP_ROAR_OK: startup band / doc contract / icon size / prefab / texture pass (samples=%d)" % _samples)
	else:
		for failure in _failures:
			push_error(failure)
		print("MONSTER_STARTUP_ROAR_FAIL: %d failures (samples=%d)" % [_failures.size(), _samples])
	get_tree().quit(0 if _failures.is_empty() else 1)
