extends Node3D
## 「生成代价取决于上一批还在不在」—— 对象池该不该做的判据。
##
## ## 为什么单独做这一项（2026-10-31）
##
## 修完材质 keeper / 场景缓存之后，还剩「某怪种第一次 460 ms」这一档。要判断该往哪个方向
## 投入，先得把代价拆成三档，看它到底挂在哪：
##
## | 场景 | 每只 |
## |---|---:|
## | 该怪种**本局第一次** | **~464 ms** |
## | 同族后续，上一批仍存活 | **~1.5 ms** |
## | 上一批**全部销毁**后再刷同族 | **~1.8 ms** |
##
## ⇒ 代价几乎全部集中在「本局第一次」，**不在**「生成逻辑」、也**不在**「池化能省的部分」。
## 结论直接决定方向：该做的是**把每怪种的一次性冷启动挪到加载期**，
## 而**敌人对象池的收益有限**（1.8 → 1.5 ms，不值得承担状态泄漏的风险）。
##
## 本探针是**报表不是门禁**：三档都是既知事实，判红没有意义。
##
## 用法：godot --path . --scene res://tools/_enemy_lifetime_cost_probe.tscn --disable-vsync
## 只读。

const PREFAB := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const KIND := "egt_bullet_kin"
const BATCH := 6

var _living: Array[Enemy3D] = []


func _ready() -> void:
	_build_stage()
	for _i in 5:
		await get_tree().process_frame

	print("LIFETIME 冷启动（该怪种第一次）")
	var first := await _spawn_one(Vector3(0, 0, -1))
	print("  first=%.1fms" % first)
	await get_tree().process_frame

	print("LIFETIME 同族追加，上一批仍存活")
	var hot_total := 0.0
	for i in BATCH:
		hot_total += await _spawn_one(Vector3(float(i) * 1.2 - 3.0, 0, 0.5))
	print("  hot avg=%.2fms（%d 只）" % [hot_total / float(BATCH + 1), BATCH + 1])

	print("LIFETIME 全部销毁后重刷")
	for enemy in _living:
		enemy.queue_free()
	_living.clear()
	for _i in 8:
		await get_tree().process_frame
	var cold_total := 0.0
	for i in BATCH:
		cold_total += await _spawn_one(Vector3(float(i) * 1.2 - 3.0, 0, 1.5))
	print("  cold avg=%.1fms（%d 只）" % [cold_total / float(BATCH), BATCH])
	print("LIFETIME 结论：一次性冷启动 %.0fms，之后 %.1fms/只；池化只能再省 %.1fms —— 收益不在池化"
		% [first, hot_total / float(BATCH + 1),
		   maxf(0.0, cold_total / float(BATCH) - hot_total / float(BATCH + 1))])
	print("LIFETIME_PROBE_DONE")
	get_tree().quit(0)


func _spawn_one(position: Vector3) -> float:
	await RenderingServer.frame_post_draw
	var enemy := PREFAB.instantiate() as Enemy3D
	enemy.set("enemy_kind", KIND)
	enemy.position = position
	var start := Time.get_ticks_usec()
	add_child(enemy)
	var spent := float(Time.get_ticks_usec() - start) / 1000.0
	_living.append(enemy)
	await get_tree().process_frame
	return spent


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
	add_child(light)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 2.0, 7.0), Vector3(0, 1.0, 0), Vector3.UP)
