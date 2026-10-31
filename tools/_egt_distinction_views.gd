extends Node
## 标识件摆位目视验收：正 / 侧 / 背 / 3-4 四个正交视角，各出一张，**不做任何旋转**。
##
## 图鉴工具（`_egt_roster_portrait`）为了让附肢入画把怪转了 202°，那样的图
## 没法判断"护目镜有没有贴在脸上"—— 得用不带旋转的正交视图。
##
## 用法：godot --path . --scene res://tools/_egt_distinction_views.tscn
## 产物：outputs/expedition03_distinction_views/<kind>_<view>.png

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const INJECTOR := preload("res://src/map/MonsterInjector.gd")
const OUT_DIR := "res://outputs/expedition03_distinction_views"

## 抽样覆盖三种模型 + 两种程序化外壳，避免只验一类。
const KINDS: Array[String] = [
	"egt_bullet_kin", "egt_hollowpoint", "egt_veteran_shotgun", "egt_blobulon",
	"egt_blobulin", "egt_gun_nut", "egt_chain_gunner", "egt_pinhead",
	"egt_king_bullat", "egt_gunsinger", "egt_bookllet", "egt_keybullet_kin",
]
## 0 = 正面（相机在 −Z，模型朝 −Z）、90 = 右侧、180 = 背面、225 = 3/4、
## 270 = **俯视 45°**（玩法视角）。
##
## 270 这一档不是凑数：水平环（头巾 / 光环 / 尖冠）从水平视角看**永远是线**，
## 只凭正/侧/背三视会误判成"环没做出来"。玩家实际是俯视看怪，
## 所以俯视档才是这几种形状的真正判据。
const VIEWS := [0, 90, 180, 225, 270]
const VIEW_W := 420
const VIEW_H := 460
const ORTHO_SIZE := 3.4
const SETTLE_FRAMES := 6

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _current: Enemy3D
var _index := 0
var _view_index := 0
var _frames := 0
var _pending := false
var _injector: MonsterInjector


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_injector = INJECTOR.new()
	_vp = SubViewport.new()
	_vp.size = Vector2i(VIEW_W, VIEW_H)
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	add_child(_vp)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.10, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.60, 0.70)
	environment.ambient_light_energy = 0.9
	env.environment = environment
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-28, -34, 0)
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-10, 158, 0)
	_vp.add_child(fill)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ORTHO_SIZE
	_cam.current = true
	_vp.add_child(_cam)
	_build(0)


func _build(index: int) -> void:
	if is_instance_valid(_world):
		_world.queue_free()
	_world = Node3D.new()
	_vp.add_child(_world)
	var kind := KINDS[index]
	_current = ENEMY_SCENE.instantiate() as Enemy3D
	var data := _injector.generate_box_enemy(kind, 1, 1)
	_world.add_child(_current)
	_current.configure_from_enemy_data(data)
	_current.position = Vector3.ZERO
	# 冻住：只看出厂姿态，不要 AI 走位。
	_current.set_physics_process(false)
	_current.set_process(false)
	var bar := _current.get_node_or_null("OverheadHealthBar") as Node3D
	if bar != null:
		bar.visible = false
	# 相机对准模型高度的中点（用顶点实高，不用碰撞柱）。
	var height := 1.8
	var avatar: Node3D = _current.avatar
	var formal: Node3D = avatar.get("_formal_normal_root")
	if formal != null:
		var measured: Dictionary = _measure(formal)
		if measured.has("height"):
			height = float(measured["height"])
	height *= float(_current.scale.y)
	_cam.position = Vector3(0.0, height * 0.55, 0.0)
	_pending = true
	_frames = 0


func _measure(host: Node3D) -> Dictionary:
	var min_y := INF
	var max_y := -INF
	var inv := host.global_transform.affine_inverse()
	for node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.visible or mesh.mesh == null:
			continue
		var xf := inv * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p := xf * v
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)
	return {"height": max_y - min_y} if max_y > min_y else {}


func _process(_delta: float) -> void:
	if _index >= KINDS.size() or not _pending:
		return
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	_frames = 0
	var kind := KINDS[_index]
	var view: int = VIEWS[_view_index]
	# 相机绕 Y 轴转：view=0 时在 −Z 侧（正对模型的脸）。
	var yaw := deg_to_rad(float(view))
	var radius := 14.0
	var height := _cam.position.y
	if view == 270:
		# 俯视 45°：抬高相机、缩短水平距离，视线压向模型腰线。
		_cam.position = Vector3(0.0, height + radius * 0.80, radius * 0.64)
		_cam.look_at(Vector3(0.0, height, 0.0), Vector3.UP)
	else:
		_cam.position = Vector3(-sin(yaw) * radius, height, -cos(yaw) * radius)
		_cam.look_at(Vector3(0.0, height, 0.0), Vector3.UP)
	_pending = false
	# 摆好相机后等一帧再截，否则拿到的是上一帧的图。
	await get_tree().process_frame
	await get_tree().process_frame
	var img := _vp.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s_v%03d.png" % [OUT_DIR, kind, view])
	img.save_png(path)
	print("DISTINCTION_VIEW %s" % path)
	_view_index += 1
	if _view_index >= VIEWS.size():
		_view_index = 0
		_index += 1
		if _index >= KINDS.size():
			print("DISTINCTION_VIEWS_DONE count=%d" % KINDS.size())
			get_tree().quit(0)
			return
		_build(_index)
	else:
		_pending = true
