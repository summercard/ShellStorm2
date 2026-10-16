class_name TrainingArmoryBay3D
extends TrainingRack3D
## 军械库货架格：完整沿用 TrainingRack3D 的交互契约（training_rack_3d 分组、
## get_interaction_candidate / perform_interaction / set_interaction_focus），
## 只把表现从「独立展示台」换成军械库货架格 —— 让整片取用区读起来像一间仓库，
## 而不是一排展柜。
##
## 取用不限次数、不消耗、不写存档：每格点一次就把对应枪身或弹药装到玩家身上，
## 离开靶场随场景释放，基地存档里不会留下任何痕迹。

const WEAPON_SCENE_PATH := "res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn"
## 货架格尺寸：一格刚好放下一把枪或一枚弹药模块。
const BAY_WIDTH := 1.9
const BAY_HEIGHT := 2.3
const BAY_DEPTH := 0.78


func _build_visual() -> void:
	var accent_color := Color(0.28, 0.76, 1.0) if category == "gunbody" else Color(1.0, 0.56, 0.18)
	_glow_material = _material(accent_color, 0.18, 0.28, true)
	var frame := _material(Color(0.12, 0.14, 0.15), 0.72, 0.46)
	# 货架格骨架：背板 + 左右立柱 + 底板 + 顶梁 + 顶部灯带 + 底部品类色标
	_add_box("BayBack", Vector3(0, BAY_HEIGHT * 0.5, -BAY_DEPTH * 0.45), Vector3(BAY_WIDTH - 0.1, BAY_HEIGHT, 0.10), frame)
	for x in [-BAY_WIDTH * 0.45, BAY_WIDTH * 0.45]:
		_add_box("BayPost", Vector3(x, BAY_HEIGHT * 0.5, 0.0), Vector3(0.10, BAY_HEIGHT, BAY_DEPTH), frame)
	_add_box("BayShelf", Vector3(0, 0.62, 0.0), Vector3(BAY_WIDTH - 0.1, 0.09, BAY_DEPTH), frame)
	_add_box("BayHeader", Vector3(0, BAY_HEIGHT - 0.06, 0.0), Vector3(BAY_WIDTH - 0.1, 0.10, BAY_DEPTH), frame)
	_add_box("BayGlow", Vector3(0, BAY_HEIGHT - 0.18, -0.16), Vector3(BAY_WIDTH - 0.5, 0.05, 0.06), _glow_material)
	_add_box("BayTag", Vector3(0, 0.70, BAY_DEPTH * 0.42), Vector3(0.5, 0.05, 0.05), _glow_material)
	if category == "gunbody":
		var weapon_scene := load(WEAPON_SCENE_PATH) as PackedScene
		if weapon_scene != null:
			var weapon := weapon_scene.instantiate() as WeaponModel3D
			weapon.display_only = true
			weapon.gun_id = item_id
			weapon.bullet_id = "mod_bullet_standard"
			weapon.position = Vector3(0, 1.18, 0.02)
			weapon.rotation.y = PI * 0.5
			weapon.scale = Vector3.ONE * 0.58
			add_child(weapon)
	else:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.14
		mesh.bottom_radius = 0.14
		mesh.height = 0.52
		mesh.radial_segments = 12
		mesh.material = _glow_material
		var cartridge := MeshInstance3D.new()
		cartridge.name = "BulletModule"
		cartridge.position = Vector3(0, 1.12, 0.02)
		cartridge.rotation_degrees.z = 90.0
		cartridge.mesh = mesh
		add_child(cartridge)
	var shape := BoxShape3D.new()
	shape.size = Vector3(BAY_WIDTH + 0.2, BAY_HEIGHT + 0.2, BAY_DEPTH + 0.4)
	var collision := CollisionShape3D.new()
	collision.position.y = BAY_HEIGHT * 0.5
	collision.shape = shape
	add_child(collision)
	_prompt = Label3D.new()
	_prompt.position = Vector3(0, BAY_HEIGHT + 0.34, 0)
	_prompt.text = "[E] %s" % display_name
	_prompt.font_size = 32
	_prompt.pixel_size = 0.010
	_prompt.modulate = accent_color.lightened(0.18)
	_prompt.outline_size = 7
	_prompt.visible = false
	add_child(_prompt)
