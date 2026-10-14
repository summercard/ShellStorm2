extends Node3D
## 真渲染预览：小僵尸 / 警察僵尸死亡「绿色方块爆开」（FX01-19 VFX-ZOMBIE-GOO-DEATH-3D）。
##
## 按时间轴把特效手动步进到若干时刻，逐帧抓「游戏原生帧」存 PNG，供业主亲眼看节奏：
##   0.00 爆开（爆炸粒子 + 飞溅粒子 + GooLight 峰值）
##   0.06/0.14 爆炸粒子过冲与收缩、飞溅粒子在飞
##   0.24 爆炸粒子收干净；飞溅粒子陆续落地
##   0.34 飞溅粒子落地压扁；地面液体开始出现
##   0.50 / 0.85 地面液体**四块同时停留**窗口内的两帧（两者必须逐位相同 ⇒ 停留真的静止）
##   1.15 下沉中
##   1.34 收干净
## 只做「看」，不含任何断言；断言在 verify_zombie_goo_death_vfx。
##
## 四块液体的停留窗口各自错峰 0.025s：puddle0 是 [0.370, 0.870]、puddle3 是 [0.445, 0.945]
## ⇒ **四块同时静止**的公共窗口是 [0.445, 0.870]，上面那两帧就取在它里面。

const GOO_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_zombie_goo_death_root_top3d.tscn")
const OUTPUT_DIR := "res://outputs/zombie_goo_death"
const LIFETIME := 1.35
const FLOOR_Y := 0.0
const SPAWN_LIFT := 0.65
const STEPS: Array[float] = [0.0, 0.06, 0.14, 0.24, 0.34, 0.50, 0.85, 1.15, 1.34]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	get_window().size = Vector2i(960, 600)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.78)
	env.ambient_light_energy = 0.85
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)

	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.2, 12)
	shape.shape = box
	ground.add_child(shape)
	var ground_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = box.size
	ground_mesh.mesh = plane
	ground_mesh.material_override = _floor_material()
	ground.add_child(ground_mesh)
	ground.position.y = FLOOR_Y - 0.1
	add_child(ground)

	var camera := Camera3D.new()
	camera.position = Vector3(2.9, 2.0, -3.5)
	camera.fov = 52.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.45, 0.0))
	camera.current = true

	# 参考标尺：一根 1.86m 高的中性立柱，让「粒子多大」有可读的尺度参照
	var ruler := MeshInstance3D.new()
	var ruler_mesh := BoxMesh.new()
	ruler_mesh.size = Vector3(0.12, 1.857, 0.12)
	ruler.mesh = ruler_mesh
	ruler.position = Vector3(-1.1, 1.857 * 0.5, 0.9)
	ruler.material_override = _ruler_material()
	add_child(ruler)

	var fx := GOO_SCENE.instantiate() as VfxEffectBase3D
	if fx == null:
		push_error("goo death prefab failed to instantiate")
		get_tree().quit(1)
		return
	add_child(fx)
	# 手动步进：关掉基类 _process，逐帧只按下面这张时间表推进
	fx.set_process(false)
	fx.activate(
		Vector3(0.0, FLOOR_Y + SPAWN_LIFT, 0.0),
		Color(0.58, 0.19, 0.12),
		1.0,
		{"floor_y": FLOOR_Y}
	)
	await get_tree().process_frame

	for index in STEPS.size():
		var elapsed: float = STEPS[index]
		fx.call("_on_tick", elapsed, LIFETIME)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/frame_%02d_t%0.2f.png" % [OUTPUT_DIR, index, elapsed])
		print("saved frame %d at t=%.2f" % [index, elapsed])

	print("PREVIEW_ZOMBIE_GOO_DEATH_DONE")
	get_tree().quit(0)


func _floor_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.21, 0.23)
	material.roughness = 0.95
	return material


func _ruler_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.76, 0.66)
	material.roughness = 0.8
	return material
