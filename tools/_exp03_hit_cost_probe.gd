extends Node3D
## 远征03「打中怪物卡顿」体检。
##
## 业主报单（2026-10-31）：进入远征03 后，子弹打中怪物会卡顿。
## 本探针把「一次命中」拆成各环节逐项计时，并量命中帧相对基线帧的帧时尖峰。
##
## 为什么不能只靠肉眼 / 只靠代码审读：
##   · 命中链路上有 7 个环节（闪白、命中特效、飘字、血条重绘、音效、AABB 现算、AI 状态切换），
##     任何一个"每次都做重活"都会表现成同一句话「打中卡一下」；
##   · 而且"第一次卡"与"每次都卡"是两种完全不同的病（冷启动 vs 每帧新分配）。
## ⇒ 输出必须同时给出 first / p50 / max，三者拉开才说明是冷启动。
##
## 用法（真渲染最关键 —— headless 不跑字体 MSDF 光栅化与材质上传）：
##   godot --path . --scene res://tools/_exp03_hit_cost_probe.tscn
##   godot --path . --headless --scene res://tools/_exp03_hit_cost_probe.tscn
##
## 只读，不改任何资产。

const ENEMY_PREFAB := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
## 远征03 的主力远程怪（正式美术 + 正式 AI 参数）。
const KIND := "egt_bullet_kin"
## 对照：塔楼原生近战怪。两者走同一套命中链路 ⇒ 耗时应当同量级。
const CONTROL_KIND := "melee_chaser"
const ROUNDS := 16
## 帧尖峰采样：每 HIT_EVERY 帧打一发。
const SPIKE_FRAMES := 120
const HIT_EVERY := 6

## 命中帧相对空闲帧的额外耗时。业主报单的那个"卡一下"就是这个数。
## ⚠ 哨兵用 -999，不能用 -1：差值本身可以是**负数**（修好之后就是 ≈0 甚至 -0.01），
##    拿 0 当"没量到"的分界会把已经修好的结果误判成"没跑"（本探针踩过一次）。
var _full_hit_delta := -999.0
var _enemy: Enemy3D
var _part_results: Dictionary = {}
## 判据阈值：命中帧比空闲帧多出 3ms 以上就算「卡」（16.7ms 帧预算的 18%）。
## headless 跑不出这个数（没有 GPU 侧管线重建），所以只在真渲染下执行这条断言。
const FULL_HIT_BUDGET_MS := 3.0
var _verdict_ok := true
var _flash_visual_ok := true
var _luma: Dictionary = {}


func _ready() -> void:
	_build_stage()
	for _i in 4:
		await get_tree().process_frame
	if _enemy == null:
		printerr("HIT_COST_FAILED 造不出怪")
		get_tree().quit(1)
		return
	await _probe_parts(KIND)
	await _probe_parts(CONTROL_KIND)
	await _probe_frame_spikes()
	await _probe_frame_groups()
	await _probe_flash_visual()
	await _report_verdict()
	get_tree().quit(0 if _verdict_ok else 1)


## 收尾判定。
##
## ⚠ 只在**真渲染**下判定命中帧预算：headless 用 dummy 渲染器，材质变体重建根本不发生
## （本项目踩过 —— 同一个 bug 在 headless 里逐项 0.0ms，全绿）。所以 headless 只打印、不判，
## 并明确写出"本次没验到"。
func _report_verdict() -> void:
	var real_render := DisplayServer.get_name() != "headless"
	# 视觉项与 frame 预算无关，headless 下根本没拍图（`_probe_flash_visual` 直接 return），
	# 只有真渲染才判。
	if real_render and not _flash_visual_ok:
		_verdict_ok = false
	if _full_hit_delta <= -999.0:
		print("HIT_COST_SKIP 没量到 full_hit 组")
		_verdict_ok = true
		return
	if not real_render:
		print("HIT_COST_SKIP_HEADLESS 命中帧差值 %.2fms（headless 不建 GPU 管线，此项无效）"
			% _full_hit_delta)
		_verdict_ok = true
		return
	_verdict_ok = _full_hit_delta < FULL_HIT_BUDGET_MS
	print("HIT_COST_%s 命中帧额外耗时 %.2fms（阈值 %.1fms）"
		% ["OK" if _verdict_ok else "FAILED", _full_hit_delta, FULL_HIT_BUDGET_MS])
	if not _verdict_ok:
		printerr(
			"HIT_COST_FAIL 命中帧比空闲帧多 %.2fms。先查有没有在**已渲染过**的材质上翻"
			% _full_hit_delta
			+ " shader 变体属性（emission_enabled / transparency / shading_mode /"
			+ " depth_draw_mode / billboard_mode / no_depth_test / disable_receive_shadows /"
			+ " vertex_color_use_as_albedo）—— 每次翻转要重建 GPU 管线，实测 77~108ms。"
		)


## 场地：一盏平行光 + 相机正对怪。相机必须能看到怪 —— 否则 VFX 与 Label3D 被视锥裁掉，
## 真渲染下测出来的"命中帧"是假的低。
func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, 35, 0)
	light.light_energy = 1.2
	add_child(light)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	ground.mesh = plane
	add_child(ground)

	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.5, 2.6), Vector3(0, 0.95, 0), Vector3.UP)

	_enemy = ENEMY_PREFAB.instantiate() as Enemy3D
	if _enemy == null:
		return
	_enemy.global_position = Vector3.ZERO
	# `enemy_kind` 必须在进树前给：`_ready()` 里就 `apply_profile(enemy_kind)` 了。
	_enemy.set("enemy_kind", KIND)
	add_child(_enemy)


func _probe_parts(kind: String) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_enemy.set("enemy_kind", kind)
	_enemy.call("apply_profile", kind)
	_enemy.max_hp = 1_000_000
	_enemy.current_hp = 1_000_000
	# 冻结 AI：只量命中链路，别把 move_and_slide / 寻路混进来。
	_enemy.set_physics_process(false)
	_enemy.set_process(false)
	for _i in 2:
		await get_tree().process_frame

	print("HIT_KIND %s" % kind)
	var anchor_point := _enemy.global_position + Vector3(0.0, 1.0, 0.55)
	var normal := Vector3(0.0, 0.0, 1.0)
	await _measure("flash_hit", func() -> void: _enemy.avatar.flash_hit())
	await _measure("hit_effect_anchor", func() -> void: _enemy.hit_effect_anchor(anchor_point, normal))
	await _measure("fx_impact_acquire", func() -> void:
		VfxPool.acquire(VfxPool3D.FX01_IMPACT, anchor_point, Color.WHITE, 0.82)
	)
	await _measure("fx_spark_acquire", func() -> void:
		VfxPool.acquire(VfxPool3D.FX01_METAL_SPARK_HIT, anchor_point, Color.WHITE, 0.62)
	)
	await _measure("fx_dmg_number_acquire", func() -> void:
		VfxPool.acquire(VfxPool3D.FX02_DAMAGE_NUMBER, anchor_point + Vector3(0, 1.6, 0),
			Color(1, 0.94, 0.84), 1.0,
			{"text_value": "17", "magnitude": 17, "critical": false})
	)
	await _measure("audio_enemy_hit", func() -> void: AudioManager.play_enemy_hit_sfx())
	await _measure("health_bar_redraw", func() -> void: _enemy.call("_redraw_overhead_health_bar"))
	await _measure("take_projectile_damage", func() -> void:
		_enemy.take_projectile_damage(1, false, normal, [], {}, null, 0.0)
	)


## 把「命中帧多出来的帧时」拆给三个动作，确认到底是哪一件在卡。
## 判据看 **hit p50 - idle p50 的差值**，不看绝对值：窗口模式帧率受 v-sync / 焦点节流影响，
## 绝对值会漂，差值才是"命中这一下额外付了多少"。
func _probe_frame_groups() -> void:
	if _enemy == null:
		return
	# ⚠ `_probe_parts()` 结束时把怪 `set_process(false)` 了（为了让 PART 计时干净）。
	# 这里必须**恢复**：闪白的能量更新就发生在表现层的 `_process` 里，关着它测出来的
	# "不卡了"是假绿 —— 什么都没跑当然不卡。
	_enemy.set_process(true)
	_enemy.set("enemy_kind", KIND)
	_enemy.call("apply_profile", KIND)
	_enemy.max_hp = 1_000_000
	_enemy.current_hp = 1_000_000
	_enemy.set_physics_process(false)
	var anchor := _enemy.global_position + Vector3(0.0, 1.0, 0.55)
	await _spike_group("GROUP baseline(no-op)", func() -> void: pass)
	await _spike_group("GROUP impact_only", func() -> void:
		VfxPool.acquire(VfxPool3D.FX01_IMPACT, anchor, Color.WHITE, 0.82)
	)
	await _spike_group("GROUP spark_only", func() -> void:
		VfxPool.acquire(VfxPool3D.FX01_METAL_SPARK_HIT, anchor, Color.WHITE, 0.62)
	)
	await _spike_group("GROUP dmg_number_only", func() -> void:
		VfxPool.acquire(VfxPool3D.FX02_DAMAGE_NUMBER, anchor + Vector3(0, 1.6, 0),
			Color(1, 0.94, 0.84), 1.0,
			{"text_value": "17", "magnitude": 17, "critical": false})
	)
	await _spike_group("GROUP audio_only", func() -> void: AudioManager.play_enemy_hit_sfx())
	await _spike_group("GROUP flash_only", func() -> void: _enemy.avatar.flash_hit())
	await _spike_group("GROUP take_damage_direct", func() -> void:
		_enemy.take_damage(1, false, Vector3(0, 0, 1), 0.0, false)
	)
	await _spike_group("GROUP full_hit", func() -> void:
		_enemy.take_projectile_damage(1, false, Vector3(0, 0, 1), [], {}, null, 0.0)
	)
	await _probe_material_switch()


## 钉死「闪白」那 37ms 到底是不是**材质变体开关**。
##
## 假说：受击闪白靠 `StandardMaterial3D.emission_enabled = true` 实现，而这个属性在
## Godot 里是 **shader define（USE_EMISSION）**，不是 uniform ⇒ 每次 true/false 翻转
## 都要切 shader 变体、建/换 GPU 管线。受伤瞬间翻上去、0.12s 后翻回来，下一发再翻 ⇒
## **每次受击都重付一次**，与「怪物只要受到伤害就卡一下」逐字吻合。
##
## 反证：只改 uniform（`emission_energy_multiplier`）而不碰 `emission_enabled`，
## 若 delta 消失，则假说成立。
func _probe_material_switch() -> void:
	var target: MeshInstance3D = null
	for node in _enemy.avatar.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			if mi.get_surface_override_material(0) is BaseMaterial3D:
				target = mi
				break
	if target == null:
		print("  MATERIAL_SWITCH skipped（没有可用的 StandardMaterial3D）")
		return
	var mat := target.get_surface_override_material(0) as BaseMaterial3D
	print("  MATERIAL_TARGET %s surfaces=%d mat=%s"
		% [target.name, target.mesh.get_surface_count(), mat.get_class()])
	var toggle := [false]
	await _spike_group("GROUP mat_emission_enabled_toggle", func() -> void:
		toggle[0] = not toggle[0]
		mat.emission_enabled = toggle[0]
	)
	await _spike_group("GROUP mat_energy_only", func() -> void:
		mat.emission_energy_multiplier = 0.6
	)
	# 反证组：闪白但**不翻变体开关**（预先常开 emission，只让能量在 0 与 0.6 之间走）。
	# 这正是修复方案本身，量出来的差值就是能省下的量。
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.45)
	mat.emission_energy_multiplier = 0.0
	var flick := [0.0]
	await _spike_group("GROUP mat_energy_pulse(=fix)", func() -> void:
		flick[0] = 0.6 if flick[0] == 0.0 else 0.0
		mat.emission_energy_multiplier = flick[0]
	)
	mat.emission_enabled = false


func _spike_group(label: String, action: Callable) -> void:
	var hits: Array[float] = []
	var idle: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in SPIKE_FRAMES:
		var will_hit := i % HIT_EVERY == 0
		if will_hit:
			action.call()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		if will_hit:
			hits.append(frame_ms)
		else:
			idle.append(frame_ms)
	var hit_p50 := _percentile(hits, 0.5)
	var idle_p50 := _percentile(idle, 0.5)
	var delta := hit_p50 - idle_p50
	print("  %-26s hit_p50=%6.2f idle_p50=%6.2f delta=%+6.2fms (n=%d/%d)"
		% [label, hit_p50, idle_p50, delta, hits.size(), idle.size()])
	if label.begins_with("GROUP full_hit"):
		_full_hit_delta = delta


## 出图：常态 vs 闪白瞬间。修卡顿不能顺手把闪白改没了，这一项是"没改坏"的证据。
## 用真渲染跑（headless 截不到画面）。
func _probe_flash_visual() -> void:
	if _enemy == null or DisplayServer.get_name() == "headless":
		return
	_enemy.set("enemy_kind", KIND)
	_enemy.call("apply_profile", KIND)
	_enemy.set_process(true)
	_enemy.set_physics_process(false)
	for _i in 3:
		await get_tree().process_frame
	var dir := "res://outputs/expedition03_hit_cost_20261031"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await RenderingServer.frame_post_draw
	_save_shot(dir.path_join("hit_00_idle.png"))
	_enemy.avatar.flash_hit()
	# 手动推一次 0 步长，把闪白定格在**峰值**再截 —— 等自然帧的话两帧后强度已掉到 45%，
	# 出图会读成"闪白很弱"，与实机峰值不是一回事。
	_enemy.avatar._process(0.0)
	await RenderingServer.frame_post_draw
	_save_shot(dir.path_join("hit_01_flash.png"))
	# 0.3s 后应完全回到常态（能量归基线），这张用来确认"闪白会自己收回去"。
	for _i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_shot(dir.path_join("hit_02_after.png"))
	# 逐像素量化：只看怪身那一小块的平均亮度，不靠肉眼判断"闪白还在不在"。
	# 判据是 flash 明显亮于 idle、after 与 idle 同档 —— 只对差值下断言，
	# 不钉绝对值（环境光改动会让绝对值漂）。
	for pair in [["idle", "hit_00_idle.png"], ["flash", "hit_01_flash.png"], ["after", "hit_02_after.png"]]:
		_luma[pair[0]] = _center_luma(dir.path_join(pair[1]))
		print("  FLASH_LUMA %-6s %.4f" % [pair[0], _luma[pair[0]]])
	# 两条断言：闪白必须**真的亮**（否则等于把闪白修没了），且 0.3s 后必须回落到常态
	# （否则等于把自发光常亮，怪会一直发光）。
	# 相对判据，不钉绝对值 —— 换光照会让绝对值漂。
	if float(_luma["flash"]) < float(_luma["idle"]) * 1.15:
		_flash_visual_ok = false
		printerr("HIT_COST_FAIL 闪白不可见（flash %.4f / idle %.4f）—— 覆盖材质可能又和表现层断开"
			% [float(_luma["flash"]), float(_luma["idle"])])
	if absf(float(_luma["after"]) - float(_luma["idle"])) > 0.02:
		_flash_visual_ok = false
		printerr("HIT_COST_FAIL 闪白没有收回常态（after %.4f / idle %.4f）"
			% [float(_luma["after"]), float(_luma["idle"])])


## 画面中心区域（怪身）的平均亮度。忽略透明/背景像素。
func _center_luma(path: String) -> float:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		return -1.0
	var w := image.get_width()
	var h := image.get_height()
	var total := 0.0
	var count := 0
	for y in range(int(h * 0.45), int(h * 0.72), 2):
		for x in range(int(w * 0.42), int(w * 0.58), 2):
			var c := image.get_pixel(x, y)
			# 地面是浅灰 (≈0.82)，怪是深色；只取"明显比地面暗"的像素 = 怪身。
			if c.v < 0.45:
				total += c.v
				count += 1
	return total / float(count) if count > 0 else -1.0


func _save_shot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return
	if image.save_png(path) == OK:
		print("  SHOT ", path)


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * ratio), sorted.size() - 1)]


## 帧尖峰：对比"命中帧"与"普通帧"的实际帧时。真渲染下这一项才代表玩家感受。
func _probe_frame_spikes() -> void:
	if _enemy == null:
		return
	_enemy.set("enemy_kind", KIND)
	_enemy.call("apply_profile", KIND)
	_enemy.max_hp = 1_000_000
	_enemy.current_hp = 1_000_000
	_enemy.set_physics_process(false)
	var normal := Vector3(0.0, 0.0, 1.0)
	var hit_frames: Array[float] = []
	var idle_frames: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in SPIKE_FRAMES:
		var will_hit := i % HIT_EVERY == 0
		if will_hit:
			_enemy.take_projectile_damage(1, false, normal, [], {}, null, 0.0)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		if will_hit:
			hit_frames.append(frame_ms)
		else:
			idle_frames.append(frame_ms)
	_report("FRAME_hit ", hit_frames)
	_report("FRAME_idle", idle_frames)


func _measure(label: String, body: Callable) -> void:
	var samples: Array[float] = []
	var first := 0.0
	for i in ROUNDS:
		var t0 := Time.get_ticks_usec()
		body.call()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if i == 0:
			first = ms
		samples.append(ms)
		if i % 2 == 0:
			await get_tree().process_frame
	_report("PART " + label, samples, first)


func _report(label: String, samples: Array[float], first := -1.0) -> void:
	if samples.is_empty():
		return
	var head := first
	if head < 0.0:
		head = samples[0]
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	var p50: float = sorted[int(float(sorted.size()) * 0.5)]
	var p90: float = sorted[mini(int(float(sorted.size()) * 0.9), sorted.size() - 1)]
	print("  %-26s first=%6.2fms p50=%6.2f avg=%6.2f p90=%6.2f max=%6.2f n=%d"
		% [label, head, p50, total / float(samples.size()), p90, sorted[sorted.size() - 1], sorted.size()])
