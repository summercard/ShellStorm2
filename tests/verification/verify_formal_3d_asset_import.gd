extends Node

const WEAPON_ASSETS := {
	"water_tank_blaster": "res://assets/art/weapons/weapon_3d/runtime/water_tank_blaster/wpn_water_tank_blaster_root_top3d_v001.tscn",
	"megaphone_cannon": "res://assets/art/weapons/weapon_3d/runtime/megaphone_cannon/wpn_megaphone_cannon_root_top3d_v001.tscn",
	"guitar_blaster": "res://assets/art/weapons/weapon_3d/runtime/guitar_blaster/wpn_guitar_blaster_root_top3d_v001.tscn",
	"spatula_rifle": "res://assets/art/weapons/weapon_3d/runtime/spatula_rifle/wpn_spatula_rifle_root_top3d_v001.tscn",
	"frying_pan_cannon": "res://assets/art/weapons/weapon_3d/runtime/frying_pan_cannon/wpn_frying_pan_cannon_root_top3d_v001.tscn",
	"toaster_launcher": "res://assets/art/weapons/weapon_3d/runtime/toaster_launcher/wpn_toaster_launcher_root_top3d_v001.tscn",
	"scope_cannon": "res://assets/art/weapons/weapon_3d/runtime/scope_cannon/wpn_scope_cannon_root_top3d_v001.tscn",
	"popcorn_blaster": "res://assets/art/weapons/weapon_3d/runtime/popcorn_blaster/wpn_popcorn_blaster_root_top3d_v001.tscn",
	"gumball_cannon": "res://assets/art/weapons/weapon_3d/runtime/gumball_cannon/wpn_gumball_cannon_root_top3d_v001.tscn",
	"double_barrel_cannon": "res://assets/art/weapons/weapon_3d/runtime/double_barrel_cannon/wpn_double_barrel_cannon_root_top3d_v001.tscn",
	"soda_straw_blaster": "res://assets/art/weapons/weapon_3d/runtime/soda_straw_blaster/wpn_soda_straw_blaster_root_top3d_v001.tscn",
	"crocodile_cannon": "res://assets/art/weapons/weapon_3d/runtime/crocodile_cannon/wpn_crocodile_cannon_root_top3d_v001.tscn",
	"candy_sniper": "res://assets/art/weapons/weapon_3d/runtime/candy_sniper/wpn_candy_sniper_root_top3d_v001.tscn",
	"camera_blaster": "res://assets/art/weapons/weapon_3d/runtime/camera_blaster/wpn_camera_blaster_root_top3d_v001.tscn",
	"tissue_box_cannon": "res://assets/art/weapons/weapon_3d/runtime/tissue_box_cannon/wpn_tissue_box_cannon_root_top3d_v001.tscn",
	"broom_rifle": "res://assets/art/weapons/weapon_3d/runtime/broom_rifle/wpn_broom_rifle_root_top3d_v001.tscn",
	"fan_blaster": "res://assets/art/weapons/weapon_3d/runtime/fan_blaster/wpn_fan_blaster_root_top3d_v001.tscn",
	"hair_dryer": "res://assets/art/weapons/weapon_3d/runtime/hair_dryer/wpn_hair_dryer_root_top3d_v001.tscn",
}

const FACILITY_ASSETS := {
	"locker_station": "res://assets/art/props/base_world_3d/runtime/locker_station/prp_base_locker_station_root_top3d_v001.tscn",
	"weapon_workshop": "res://assets/art/props/base_world_3d/runtime/weapon_workshop/prp_base_weapon_workshop_root_top3d_v001.tscn",
	"retro_tv_station": "res://assets/art/props/base_world_3d/runtime/retro_tv_station/prp_base_retro_tv_station_root_top3d_v001.tscn",
	"mission_operations": "res://assets/art/props/base_world_3d/runtime/mission_operations/prp_base_mission_operations_root_top3d_v001.tscn",
	"vending_machine": "res://assets/art/props/base_world_3d/runtime/vending_machine/prp_base_vending_machine_root_top3d_v002.tscn",
}

const DECOR_ASSETS := {
	"workshop_stool": "res://assets/art/props/base_world_3d/runtime/workshop_stool/prp_base_workshop_stool_root_top3d_v001.tscn",
	"mission_command_chair": "res://assets/art/props/base_world_3d/runtime/mission_command_chair/prp_base_mission_command_chair_root_top3d_v001.tscn",
}

const REQUIRED_WEAPON_SOCKETS := [
	"GripSocket", "SupportHandSocket", "MuzzleSocket", "MuzzleAttachmentSocket",
	"ScopeSocket", "MagazineSocket", "StockSocket", "TacticalSocket", "MutatorSocket",
	"GroundPivot", "IconPivot",
]


func _ready() -> void:
	var failures: Array[String] = []
	_verify_weapons(failures)
	_verify_facilities(failures)
	_verify_decor_props(failures)
	_verify_runtime_mapping(failures)
	if failures.is_empty():
		print("[PASS] 正式3D资产导入：5设施/2独立座椅/18枪的场景、材质预算、比例与节点契约均通过")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_weapons(failures: Array[String]) -> void:
	for slug in WEAPON_ASSETS:
		var path := str(WEAPON_ASSETS[slug])
		var scene := load(path) as PackedScene
		_check(scene != null, "%s 独立武器场景不能加载" % slug, failures)
		if scene == null:
			continue
		var asset := scene.instantiate() as Node3D
		add_child(asset)
		_check(asset.get_node_or_null("VisualRoot") != null, "%s 缺少VisualRoot" % slug, failures)
		for socket_name in REQUIRED_WEAPON_SOCKETS:
			_check(asset.get_node_or_null(socket_name) is Marker3D, "%s 缺少统一挂点%s" % [slug, socket_name], failures)
		var grip := asset.get_node_or_null("GripSocket") as Marker3D
		var muzzle := asset.get_node_or_null("MuzzleSocket") as Marker3D
		if grip != null:
			_check(grip.position.is_equal_approx(Vector3.ZERO), "%s Grip不是根原点" % slug, failures)
		if muzzle != null:
			_check(muzzle.position.z < -0.35 and absf(muzzle.position.x) < 0.02, "%s 枪口未统一指向local -Z" % slug, failures)
		var materials := {}
		_collect_materials(asset, materials)
		_check(materials.size() <= 3, "%s 材质数量超过3：%s" % [slug, materials.keys()], failures)
		var bounds := _visual_bounds(asset)
		_check(bounds.size.z >= 1.15 and bounds.size.z <= 2.10, "%s 枪械长度比例异常：%.3fm" % [slug, bounds.size.z], failures)
		asset.queue_free()


func _verify_facilities(failures: Array[String]) -> void:
	for slug in FACILITY_ASSETS:
		var scene := load(str(FACILITY_ASSETS[slug])) as PackedScene
		_check(scene != null, "%s 独立设施场景不能加载" % slug, failures)
		if scene == null:
			continue
		var asset := scene.instantiate() as BaseFacility3D
		add_child(asset)
		_check(asset.get_node_or_null("Visual/ImportedModel") != null, "%s 缺少正式导入模型" % slug, failures)
		if slug in ["weapon_workshop", "mission_operations"]:
			_check(not _contains_seat_name(asset), "%s 的设施模型仍然夹带椅子/凳子" % slug, failures)
		_check(asset.get_node_or_null("InteractionShape") is CollisionShape3D, "%s 缺少交互碰撞" % slug, failures)
		_check(asset.get_node_or_null("StaticBody3D/CollisionShape3D") is CollisionShape3D, "%s 缺少实体碰撞" % slug, failures)
		var materials := {}
		_collect_materials(asset, materials)
		_check(materials.size() <= 4, "%s 材质数量超过4：%s" % [slug, materials.keys()], failures)
		var bounds := _visual_bounds(asset)
		if slug == "locker_station":
			_check(absf(bounds.size.x - 5.0) <= 0.06, "%s 未达到5米宽模数：%.3fm" % [slug, bounds.size.x], failures)
			_check(absf(bounds.size.y - 3.901) <= 0.06, "%s 等比例高度异常：%.3fm" % [slug, bounds.size.y], failures)
		elif slug == "retro_tv_station":
			_check(absf(bounds.size.x - 4.985) <= 0.06, "%s 未达到5米宽模数：%.3fm" % [slug, bounds.size.x], failures)
			_check(absf(bounds.size.y - 4.820) <= 0.06, "%s 等比例高度异常：%.3fm" % [slug, bounds.size.y], failures)
		else:
			_check(bounds.size.y >= 3.2 and bounds.size.y <= 3.7, "%s 设施按上一版80%%调整后高度异常：%.3fm" % [slug, bounds.size.y], failures)
		asset.queue_free()


func _verify_decor_props(failures: Array[String]) -> void:
	for slug in DECOR_ASSETS:
		var scene := load(str(DECOR_ASSETS[slug])) as PackedScene
		_check(scene != null, "%s 独立座椅场景不能加载" % slug, failures)
		if scene == null:
			continue
		var asset := scene.instantiate() as Node3D
		add_child(asset)
		_check(str(asset.get_meta("asset_category", "")) == "decor_prop", "%s 未登记为独立装饰资产" % slug, failures)
		_check(asset.get_node_or_null("ImportedModel") != null, "%s 缺少独立导入模型" % slug, failures)
		var materials := {}
		_collect_materials(asset, materials)
		_check(materials.size() <= 4, "%s 材质数量超过4：%s" % [slug, materials.keys()], failures)
		var bounds := _visual_bounds(asset)
		_check(bounds.size.y >= 0.75 and bounds.size.y <= 1.45, "%s 座椅高度异常：%.3fm" % [slug, bounds.size.y], failures)
		asset.queue_free()


func _contains_seat_name(root: Node) -> bool:
	var lowered := str(root.name).to_lower()
	if "chair" in lowered or "stool" in lowered or "椅" in lowered or "凳" in lowered:
		return true
	for child in root.get_children():
		if _contains_seat_name(child):
			return true
	return false


func _verify_runtime_mapping(failures: Array[String]) -> void:
	var expected := {
		"bp_pistol": "hair_dryer", "bp_shotgun": "double_barrel_cannon",
		"bp_rifle": "broom_rifle", "bp_machinegun": "water_tank_blaster",
		"bp_sniper": "candy_sniper", "bp_launcher": "toaster_launcher",
		"bp_charge": "gumball_cannon",
	}
	for gun_id in expected:
		var model := WeaponModel3D.new()
		add_child(model)
		_check(model.configure(str(gun_id), "mod_bullet_standard"), "%s 不能配置正式模型" % gun_id, failures)
		var imported := _find_logic_asset(model, str(gun_id))
		_check(imported != null, "%s 未映射到独立正式枪械资产" % gun_id, failures)
		model.queue_free()


func _find_logic_asset(root: Node, logic_id: String) -> Node:
	if str(root.get_meta("logic_id", "")) == logic_id:
		return root
	for child in root.get_children():
		var result := _find_logic_asset(child, logic_id)
		if result != null:
			return result
	return null


func _collect_materials(root: Node, materials: Dictionary) -> void:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.mesh.surface_get_material(surface)
				if material != null:
					materials[material.resource_name] = true
	for child in root.get_children():
		_collect_materials(child, materials)


func _visual_bounds(root: Node) -> AABB:
	var initialized := false
	var result := AABB()
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var local_bounds := mesh_instance.transform * mesh_instance.get_aabb()
		if not initialized:
			result = local_bounds
			initialized = true
		else:
			result = result.merge(local_bounds)
	return result


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
