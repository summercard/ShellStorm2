extends Node3D
## 「怪物生成」帧时代价体检（真渲染）。
##
## ## 起因
##
## 2026-10-31 查受击卡顿时顺线发现：刷怪那一帧的 `apply_profile()` 里有两次
## **同步读盘 + 管线编译**，而它们都会随「上一只同类怪被回收」重新付一遍：
##
## | 项 | 每只都付 | 原因 |
## |---|---:|---|
## | `load(正式模型 .tscn)` | 100~118 ms | Godot 资源缓存是**弱引用**，最后一只同类怪回收后没人持有 PackedScene |
## | 同变体材质首次入树 | 每变体 ~100 ms | 管线缓存挂在使用中的材质上，材质随怪一起销毁 |
##
## 症状是**每次刷怪都顿 100~300 ms**，一屋子 10 只就是 1~3 秒；而 headless 里
## 同一段只要 2 ms（不编译管线、不走 GPU），所以任何无渲染验收都看不见它。
##
## 现在两项都有对策（`EnemyAvatar3D._cached_scene()` + `MaterialPipelineKeeper`），
## 本探针盯的就是**同类第二次生成必须便宜**这个不变量。
##
## 用法：godot --path . --scene res://tools/_enemy_spawn_cost_probe.tscn --disable-vsync
## 只读。

const PREFAB := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
## 首见某怪种要付一次「读盘 + 变体编译」，这是**允许**的一次性成本；
## 判据只盯**同种第二次**。
const REPEAT_BUDGET_MS := 20.0
## 每个怪种生成几次（第 1 次冷、第 2 次必须热）。
const ROUNDS := 3
const KINDS := [
	"summoner",
	"shielded",
	"exploder",
	"melee_chaser",
	"ranged_caster",
	"fat_zombie03",
]

var _failures: Array[String] = []


func _ready() -> void:
	_build_stage()
	for _i in 5:
		await get_tree().process_frame
	for kind in KINDS:
		await _measure_kind(kind)
	print("SPAWN_COST_%s failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("SPAWN_COST_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.12, 0.12, 0.14)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment = environment
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 2.0, 7.0), Vector3(0, 1.0, 0), Vector3.UP)


func _measure_kind(kind: String) -> void:
	var times: Array[float] = []
	for i in ROUNDS:
		# 让 GPU 追平再测：不然后面的同步调用会阻塞在"上一帧还没画完"上，
		# 量到的是 GPU 积压而不是这次调用本身的代价。
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
		var enemy := PREFAB.instantiate() as Enemy3D
		enemy.set("enemy_kind", kind)
		var start := Time.get_ticks_usec()
		add_child(enemy)
		times.append(float(Time.get_ticks_usec() - start) / 1000.0)
		await get_tree().process_frame
		enemy.free()
		await get_tree().process_frame
	var text := ""
	for value in times:
		text += "%.1f " % value
	print("  SPAWN %-14s %s" % [kind, text])
	# 第 2 次起都必须便宜。只判"有第 2 次"即可 —— 第 1 次是冷启动，允许贵。
	for index in range(1, times.size()):
		if times[index] > REPEAT_BUDGET_MS:
			_failures.append(
				"%s 第 %d 次生成仍要 %.1fms（阈值 %.0fms）—— 读盘或材质变体缓存没留住"
				% [kind, index + 1, times[index], REPEAT_BUDGET_MS]
			)
			break
