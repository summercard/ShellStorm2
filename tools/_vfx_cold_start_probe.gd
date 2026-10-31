extends Node3D
## 「特效冷启动」体检：第一次借出某个特效要付多少，第二次呢。
##
## ## 为什么要单列这一项
##
## 2026-10-31 定位受击卡顿时发现：命中的**第一次** `VFX-IMPACT-3D` 借出要 **64 ms**，
## 之后每发只要 **0.39 ms**。拆开看（`activate` 里 `_build()` 那一段）：
##
## ```
## instantiate 0.04ms / add_child 0.01ms / activate 64.36ms / 首帧渲染 14.68ms
## 摆在相机背后（必被视锥剔除、根本不绘制）⇒ activate 仍 64.65ms，第二次 0.37ms
## 单独 new 一个同款 StandardMaterial3D ⇒ 0.03ms
## ```
##
## ⇒ 贵的是「节点带材质**实例化进渲染场景**」这一下，既不是 `new` 材质、也不是"画"。
## 它每局只发生一次，所以"平均帧时"看不见，但玩家感受得到：进关卡后打出的第一枪会顿。
##
## 本探针把这段差价量出来，并验证 `VfxPool3D.prewarm()` 能把队列排空、不残留。
##
## 用法：
##   godot --path . --scene res://tools/_vfx_cold_start_probe.tscn --disable-vsync
## 只读。

## 会被"第一次打中 / 第一次开火 / 第一次打死"用到的那些。顺序即优先级。
## 必须与 `VfxPool3D.COMBAT_PREWARM` 一致 —— 探针量的是列表里这批，不预热的是同一批。
const KIND_TO_WARM := [
	"VFX-IMPACT-3D",
	"VFX-METAL-SPARK-HIT-3D",
	"VFX-GOO-HIT-3D",
	"VFX-DAMAGE-NUMBER-3D",
	"VFX-MUZZLE-FLASH-3D",
	"VFX-SHELL-CASING-3D",
	"VFX-MELEE-SLASH-3D",
	"VFX-MELEE-IMPACT-3D",
	"VFX-ZOMBIE-GOO-DEATH-3D",
	"VFX-EXPLOSION-3D",
	"VFX-DEATH-BLAST-3D",
]
## 预热尺寸：亚像素。1.5 m 处约 0.8 mm，任何分辨率下都不到一个像素。
const PREWARM_SIZE := 0.0008
## 冷启动超过这个数就算"会顿一下"（4 帧 @60fps）。
const COLD_BUDGET_MS := 33.0

var _failures: Array[String] = []


func _ready() -> void:
	_build_stage()
	for _i in 5:
		await get_tree().process_frame
	# 同一个进程只能"冷"一次，所以两种口径用命令行切换，跑两遍对比：
	#   godot --path . --scene res://tools/_vfx_cold_start_probe.tscn --disable-vsync
	#   godot --path . --scene res://tools/_vfx_cold_start_probe.tscn --disable-vsync -- --prewarm
	if "--prewarm" in OS.get_cmdline_user_args():
		await _prewarm_then_measure()
	else:
		await _measure_cold_starts()
	print("VFX_COLD_%s failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("VFX_COLD_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


## `--prewarm` 口径：先执行真实预热，再量同一批特效的"第一次借出"。
## 与默认口径（不预热）对照，两者之差就是 `prewarm()` 帮玩家省下的量。
func _prewarm_then_measure() -> void:
	print("VFX_COLD 预热后再首次借出")
	await _measure_prewarm()
	var total := 0.0
	for asset_id in KIND_TO_WARM:
		var start := Time.get_ticks_usec()
		VfxPool.acquire(StringName(asset_id), Vector3(0, 1.2, 0), Color.WHITE, 0.35)
		var spent := float(Time.get_ticks_usec() - start) / 1000.0
		total += spent
		print("  %-28s first=%7.2fms" % [asset_id, spent])
		await get_tree().process_frame
	print("  PREWARMED_TOTAL %.2fms（%d 种）" % [total, KIND_TO_WARM.size()])
	# 预热过的这一批，第一次就该接近 0；还有几十毫秒说明预热没真进场景树。
	if total > COLD_BUDGET_MS:
		_failures.append(
			"预热后首次借出仍要 %.1fms（阈值 %.0fms）—— prewarm 没真正把节点送进场景树"
			% [total, COLD_BUDGET_MS]
		)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.12, 0.14)
	env.environment = environment
	add_child(env)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.6, 3.0), Vector3(0, 1.2, 0), Vector3.UP)


## 逐个借一次，记"首次"耗时；每借完等一帧让它真画出来。
func _measure_cold_starts() -> void:
	print("VFX_COLD 首次借出（真渲染，含首次绘制）")
	var total := 0.0
	for asset_id in KIND_TO_WARM:
		var start := Time.get_ticks_usec()
		VfxPool.acquire(StringName(asset_id), Vector3(0, 1.2, 0), Color.WHITE, 0.35)
		var spent := float(Time.get_ticks_usec() - start) / 1000.0
		total += spent
		print("  %-28s first=%7.2fms" % [asset_id, spent])
		# 必须等真画一帧：管线是**绘制时**编译的，不是 `acquire()` 返回时。
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	print("  COLD_TOTAL %.2fms（%d 种）" % [total, KIND_TO_WARM.size()])
	# 第二次应当接近 0 —— 若这里也贵，说明不是冷启动而是每发都重编译（另一类 bug）。
	var again := 0.0
	for asset_id in KIND_TO_WARM:
		var start := Time.get_ticks_usec()
		VfxPool.acquire(StringName(asset_id), Vector3(0, 1.2, 0), Color.WHITE, 0.35)
		again += float(Time.get_ticks_usec() - start) / 1000.0
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	print("  WARM_TOTAL %.2fms（同批第二次）" % again)
	if again > total * 0.35 and total > 5.0:
		_failures.append(
			"第二次借出仍花 %.1fms（首次 %.1fms）—— 不是冷启动，是每发都在重编译" % [again, total]
		)


## 验证 `prewarm()`：队列能排空、预热件会自行退池、不残留。
##
## 注意顺序：本函数在 `_measure_cold_starts()` 之后跑，那些管线**已经**编译过了，
## 所以这里量不出"预热省了多少"—— 省多少的证据是上面那张首次/第二次对照表
## （121.8 ms → 2.8 ms）。这一节只验**接口与生命周期**：别卡在队列里、别长期占池位。
func _measure_prewarm() -> void:
	if not VfxPool.has_method("prewarm"):
		_failures.append("VfxPool3D 没有 prewarm() —— 冷启动差价仍会落进第一枪")
		return
	if not VfxPool.has_method("has_pending_prewarm"):
		_failures.append("VfxPool3D 没有 has_pending_prewarm() —— 加载页无法判断能否开圈")
		return
	var first := StringName(KIND_TO_WARM[0])
	var before := VfxPool.active_count(first)
	VfxPool.prewarm(KIND_TO_WARM)
	var frames := 0
	while VfxPool.has_pending_prewarm() and frames < KIND_TO_WARM.size() * 4:
		await get_tree().process_frame
		frames += 1
	print("  PREWARM 队列排空用了 %d 帧（%d 种，逐帧一个）" % [frames, KIND_TO_WARM.size()])
	if VfxPool.has_pending_prewarm():
		_failures.append("预热队列没排空（%d 帧后仍有残留）" % frames)
		return
	# 预热件按各自 lifetime 自动退池；等最长的那个过完。
	for _i in 60:
		await get_tree().process_frame
	var after := VfxPool.active_count(first)
	print("  PREWARM 退池后 active %d -> %d" % [before, after])
	if after > before:
		_failures.append("预热件没有退池：active %d -> %d（会长期占着池位）" % [before, after])
