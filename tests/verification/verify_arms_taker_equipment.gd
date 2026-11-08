extends Node
## 收租人双悬浮枪械专项验证：验证资源挂点、控制器 API、武器快照和敌对弹丸适配。

const EQUIPMENT_SCRIPT := preload("res://src/enemy3d/EliteArmsTakerEquipment.gd")
const VISUAL_SCENE: PackedScene = preload("res://assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/enm_elite_arms_taker_root_top3d.tscn")
const WEAPON_SCRIPT := preload("res://src/combat3d/WeaponModel3D.gd")
const PROJECTILE_SCRIPT := preload("res://src/combat3d/Projectile3D.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(EQUIPMENT_SCRIPT != null, "装备控制器脚本可加载")
	_check(VISUAL_SCENE != null, "收租人正式视觉场景可加载")
	_check(WEAPON_SCRIPT != null, "WeaponModel3D 可加载")
	_check(PROJECTILE_SCRIPT != null, "Projectile3D 可加载")

	var visual := VISUAL_SCENE.instantiate() as Node3D
	_check(visual != null, "收租人视觉根可实例化")
	if visual != null:
		add_child(visual)
		await get_tree().process_frame
		_check(visual.get_node_or_null("WeaponMountLeft") is Marker3D, "存在明确左侧 Marker3D 挂点")
		_check(visual.get_node_or_null("WeaponMountRight") is Marker3D, "存在明确右侧 Marker3D 挂点")
		_check(visual.has_method("get_weapon_mount_points"), "视觉层提供挂点接口")
		var mounts: Array = visual.call("get_weapon_mount_points")
		_check(mounts.size() == 2, "挂点接口固定返回两个挂点")
		_check(visual.has_method("get_weapon_presentation_snapshot"), "视觉层提供装备表现快照")
		var visual_snapshot: Dictionary = visual.call("get_weapon_presentation_snapshot")
		_check(str(visual_snapshot.get("mount_contract", "")) == "two_explicit_marker3d", "视觉快照声明双 Marker3D 合约")
		visual.queue_free()
		await get_tree().process_frame

	var equipment := EQUIPMENT_SCRIPT.new(null)
	_check(equipment != null, "控制器可由 new(self) 形态构造")
	var pistol_item := ItemRegistry.get_instance().get_item("weapon_pistol")
	pistol_item["bullet_module_id"] = "mod_bullet_standard"
	pistol_item["current_ammo"] = 2
	pistol_item["reserve_ammo"] = 3
	_check(equipment.has_method("configure"), "控制器提供 configure(equipped_weapons)")
	_check(equipment.has_method("tick"), "控制器提供 tick(delta,target)")
	_check(equipment.has_method("export_state"), "控制器提供 export_state")
	_check(equipment.has_method("import_state"), "控制器提供 import_state")
	_check(equipment.has_method("get_presentation_snapshot"), "控制器提供 presentation snapshot")
	if equipment != null:
		equipment.configure([pistol_item, pistol_item])
		_check(int(equipment.call("get_weapon_count")) == 2, "已筛选武器最多挂载两件且双挂点均可用")
		var loaded_state: Dictionary = equipment.call("export_state")
		_check(int(loaded_state.get("weapon_count", -1)) == 2, "双枪导出保留两件实例")
		_check(bool(equipment.call("import_state", loaded_state)), "双枪装备状态可往返恢复")
		equipment.configure([])
		var state: Dictionary = equipment.call("export_state")
		_check(int(state.get("weapon_count", -1)) == 0, "空配置不生成虚拟枪械")
		_check(bool(equipment.call("import_state", state)), "空装备状态可往返恢复")
		equipment.call("dispose")
		await get_tree().process_frame

	var weapon := WEAPON_SCRIPT.new()
	weapon.configure_firing_context(true, "player_3d", 1)
	var runtime_state: Dictionary = weapon.get_runtime_state()
	_check(bool(weapon.get("_firing_hostile")), "武器友军层适配可切换为 hostile")
	_check(str(weapon.get("_firing_target_group")) == "player_3d", "武器目标组可切换到玩家")
	_check(int(weapon.get("_firing_projectile_collision_mask")) == 1, "武器弹丸碰撞层可切换到玩家层")
	_check(runtime_state.has("current_ammo"), "武器运行态快照保留弹匣弹药")
	weapon.free()

	var projectile := PROJECTILE_SCRIPT.new()
	projectile.configure({"hostile": true, "target_group": "player_3d", "projectile_collision_mask": 1})
	_check(bool(projectile.hostile), "弹丸继承 hostile")
	_check(projectile.target_group == "player_3d", "弹丸继承玩家目标组")
	_check(projectile.projectile_collision_mask == 1, "弹丸继承玩家碰撞层")
	projectile.free()

	if _failures.is_empty():
		print("ARMS_TAKER_EQUIPMENT_VERIFY_PASS")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("ARMS_TAKER_EQUIPMENT_VERIFY_FAIL count=%d" % _failures.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS %s" % message)
	else:
		_failures.append(message)
