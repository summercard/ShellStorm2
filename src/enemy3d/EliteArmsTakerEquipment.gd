class_name EliteArmsTakerEquipment
extends RefCounted
## 收租人跨遭遇夺械装备控制器。
##
## Enemy3D 只负责在后续接入点创建/驱动本控制器；本类不改变本关夺取流程。
## 输入必须是档案端已经筛选过的「下一次非本关遭遇」WeaponInstance item，最多保留两件。

const MAX_WEAPONS := 2
const PLAYER_TARGET_GROUP := "player_3d"
const PLAYER_PROJECTILE_MASK := 1
const ENEMY_TARGET_GROUP := "enemy_3d"
const ENEMY_PROJECTILE_MASK := 4
const WEAPON_INSTANCE_SCRIPT := preload("res://src/weapons/WeaponInstance.gd")

var owner_enemy: Node3D
var _entries: Array[Dictionary] = []
var _configured_items: Array[Dictionary] = []
var _last_target: Node3D
var _mount_names := ["WeaponMountLeft", "WeaponMountRight"]


func _init(enemy: Node3D) -> void:
	owner_enemy = enemy


## `equipped_weapons` 来自档案端已筛选的 eligible WeaponInstance 实例/物品字典。
## 这里不把枪映射成技能，也不重掷枪身、弹种、模块或命运。
func configure(equipped_weapons: Array) -> void:
	_clear_entries()
	_configured_items.clear()
	for raw_weapon in equipped_weapons:
		if _entries.size() >= MAX_WEAPONS:
			break
		var item := _normalize_weapon_item(raw_weapon)
		if item.is_empty():
			continue
		var instance: WeaponInstance = WEAPON_INSTANCE_SCRIPT.from_item(item)
		if instance == null:
			continue
		var runtime_tree := instance.build_runtime_tree()
		if runtime_tree == null or runtime_tree.get_root() == null:
			continue
		var entry := _build_entry(item, instance, runtime_tree, _entries.size())
		_entries.append(entry)
		_configured_items.append(item.duplicate(true))
	_ensure_weapon_models()


func tick(delta: float, target: Node3D) -> void:
	if delta <= 0.0:
		return
	_last_target = target if is_instance_valid(target) else null
	_ensure_weapon_models()
	_update_firing_context()
	if _entries.is_empty() or not is_instance_valid(_last_target):
		return
	if _target_is_dead(_last_target):
		return
	for entry in _entries:
		var weapon := entry.get("weapon") as WeaponModel3D
		if not is_instance_valid(weapon):
			continue
		var mount := entry.get("mount") as Node3D
		var origin := mount.global_position if is_instance_valid(mount) else owner_enemy.global_position
		var direction := (_last_target.global_position + Vector3.UP * 0.72 - origin).normalized()
		if direction.length_squared() <= 0.0001:
			continue
		weapon.look_at(origin + direction, Vector3.UP)
		if weapon.is_charge_active():
			weapon.try_fire(direction, owner_enemy)
			var charge_snapshot := weapon.get_snapshot()
			if float(charge_snapshot.get("charge_ratio", 0.0)) >= 0.999:
				weapon.release_charge()
		else:
			weapon.try_fire(direction, owner_enemy)
		_sync_entry(entry)


func export_state() -> Dictionary:
	var weapons: Array[Dictionary] = []
	for entry in _entries:
		_sync_entry(entry)
		var weapon := entry.get("weapon") as WeaponModel3D
		var instance: WeaponInstance = entry.get("instance") as WeaponInstance
		var item := instance.to_item_dictionary() if instance != null else (entry.get("item", {}) as Dictionary).duplicate(true)
		var runtime := weapon.get_runtime_state() if is_instance_valid(weapon) else {}
		item["current_ammo"] = int(runtime.get("current_ammo", item.get("current_ammo", -1)))
		var presentation := weapon.get_snapshot() if is_instance_valid(weapon) else {}
		weapons.append({
			"slot": int(entry.get("slot", weapons.size())),
			"weapon_item": item,
			"reserve_ammo": maxi(0, int(entry.get("reserve_ammo", 0))),
			"runtime": runtime.duplicate(true),
			"presentation": presentation.duplicate(true),
		})
	return {
		"schema": 1,
		"weapon_count": weapons.size(),
		"weapons": weapons,
		"target_group": _target_group_for(_last_target),
		"last_target_instance_id": _last_target.get_instance_id() if is_instance_valid(_last_target) else 0,
	}


func import_state(state: Dictionary) -> bool:
	var saved_weapons: Variant = state.get("weapons", [])
	if not saved_weapons is Array:
		return false
	var items: Array = []
	for raw_saved in saved_weapons as Array:
		var saved: Variant = raw_saved
		if saved is Dictionary:
			var saved_item: Variant = (saved as Dictionary).get("weapon_item", {})
			if saved_item is Dictionary and not (saved_item as Dictionary).is_empty():
				items.append((saved_item as Dictionary).duplicate(true))
	configure(items)
	for index in mini(_entries.size(), (saved_weapons as Array).size()):
		var saved: Variant = (saved_weapons as Array)[index]
		if not saved is Dictionary:
			continue
		var entry := _entries[index]
		entry["reserve_ammo"] = maxi(0, int((saved as Dictionary).get("reserve_ammo", 0)))
		var weapon := entry.get("weapon") as WeaponModel3D
		if is_instance_valid(weapon):
			weapon.restore_runtime_state((saved as Dictionary).get("runtime", {}) as Dictionary)
		_sync_entry(entry)
	return _entries.size() == items.size()


func get_presentation_snapshot() -> Dictionary:
	var weapons: Array[Dictionary] = []
	for entry in _entries:
		var weapon := entry.get("weapon") as WeaponModel3D
		var snapshot := weapon.get_snapshot() if is_instance_valid(weapon) else {}
		snapshot["slot"] = int(entry.get("slot", weapons.size()))
		snapshot["reserve_ammo"] = maxi(0, int(entry.get("reserve_ammo", 0)))
		snapshot["mount_name"] = str((entry.get("mount") as Node).name) if is_instance_valid(entry.get("mount")) else ""
		weapons.append(snapshot)
	var visual_snapshot := {}
	var visual := _resolve_visual_root()
	if is_instance_valid(visual) and visual.has_method("get_weapon_presentation_snapshot"):
		visual_snapshot = visual.call("get_weapon_presentation_snapshot") as Dictionary
	return {
		"schema": 1,
		"weapon_count": weapons.size(),
		"weapons": weapons,
		"visual": visual_snapshot,
		"target_group": _target_group_for(_last_target),
	}


func presentation_snapshot() -> Dictionary:
	return get_presentation_snapshot()


func get_weapon_count() -> int:
	return _entries.size()


func _build_entry(item: Dictionary, instance: WeaponInstance, tree: WeaponAssemblyTree, slot: int) -> Dictionary:
	var reserve := _resolve_initial_reserve(item)
	if reserve < 0:
		reserve = 0
	return {
		"slot": slot,
		"item": item.duplicate(true),
		"instance": instance,
		"tree": tree,
		"weapon": null,
		"mount": null,
		"reserve_ammo": reserve,
	}


func _update_firing_context() -> void:
	var target_group := PLAYER_TARGET_GROUP
	var projectile_mask := PLAYER_PROJECTILE_MASK
	if is_instance_valid(_last_target) and _last_target.is_in_group(ENEMY_TARGET_GROUP):
		target_group = ENEMY_TARGET_GROUP
		projectile_mask = ENEMY_PROJECTILE_MASK
	for entry in _entries:
		var weapon := entry.get("weapon") as WeaponModel3D
		if is_instance_valid(weapon):
			weapon.configure_firing_context(true, target_group, projectile_mask)


func _ensure_weapon_models() -> void:
	var mounts := _resolve_mounts()
	for index in _entries.size():
		var entry := _entries[index]
		var mount := mounts[index] if index < mounts.size() else null
		entry["mount"] = mount
		if not is_instance_valid(mount):
			continue
		var weapon := entry.get("weapon") as WeaponModel3D
		if is_instance_valid(weapon):
			continue
		var tree := entry.get("tree") as WeaponAssemblyTree
		if tree == null:
			continue
		weapon = WeaponModel3D.new()
		weapon.name = "ArmsTakerStolenWeapon%d" % (index + 1)
		weapon.gun_id = ""
		weapon.render_layers = 1
		weapon.configure_firing_context(true, PLAYER_TARGET_GROUP, PLAYER_PROJECTILE_MASK)
		mount.add_child(weapon)
		weapon.set_reload_ammo_provider(Callable(self, "_provide_reload_ammo").bind(index))
		weapon.configure_from_tree(tree)
		var instance: WeaponInstance = entry.get("instance") as WeaponInstance
		if instance != null:
			weapon.set_meta("weapon_instance_id", instance.weapon_instance_id)
			weapon.set_meta("fate_slot_used", instance.fate_upgrades.size())
		entry["weapon"] = weapon
		_sync_entry(entry)


func _resolve_mounts() -> Array[Node3D]:
	var result: Array[Node3D] = []
	var visual := _resolve_visual_root()
	if not is_instance_valid(visual):
		return result
	if visual.has_method("get_weapon_mount_points"):
		var provided: Variant = visual.call("get_weapon_mount_points")
		if provided is Array:
			for point in provided as Array:
				if point is Node3D and is_instance_valid(point):
					result.append(point as Node3D)
	if result.size() >= MAX_WEAPONS:
		return result.slice(0, MAX_WEAPONS)
	result.clear()
	for mount_name in _mount_names:
		var mount := visual.get_node_or_null(mount_name) as Node3D
		if mount != null:
			result.append(mount)
	return result


func _resolve_visual_root() -> Node3D:
	if not is_instance_valid(owner_enemy):
		return null
	var avatar := owner_enemy.get_node_or_null("Avatar")
	if avatar != null and avatar.has_method("get_animated_elite_root"):
		var visual: Variant = avatar.call("get_animated_elite_root")
		return visual as Node3D if visual is Node3D else null
	return null


func _provide_reload_ammo(requested: int, slot: int) -> int:
	if slot < 0 or slot >= _entries.size():
		return 0
	var entry := _entries[slot]
	var reserve := maxi(0, int(entry.get("reserve_ammo", 0)))
	if requested <= 0:
		return 1 if reserve > 0 else 0
	var loaded := mini(reserve, requested)
	entry["reserve_ammo"] = reserve - loaded
	return loaded


func _sync_entry(entry: Dictionary) -> void:
	var weapon := entry.get("weapon") as WeaponModel3D
	var instance: WeaponInstance = entry.get("instance") as WeaponInstance
	if not is_instance_valid(weapon) or instance == null:
		return
	instance.current_ammo = weapon.current_ammo
	entry["item"] = instance.to_item_dictionary()


func _clear_entries() -> void:
	for entry in _entries:
		var weapon := entry.get("weapon") as WeaponModel3D
		if is_instance_valid(weapon):
			weapon.set_reload_ammo_provider(Callable())
			weapon.clear_weapon()
			weapon.queue_free()
		var tree := entry.get("tree") as WeaponAssemblyTree
		if is_instance_valid(tree):
			tree.clear_assembly(false)
			tree.free()
	_entries.clear()


func dispose() -> void:
	_clear_entries()
	_configured_items.clear()
	_last_target = null
	owner_enemy = null


func _normalize_weapon_item(raw_weapon: Variant) -> Dictionary:
	if raw_weapon is WeaponInstance:
		return (raw_weapon as WeaponInstance).to_item_dictionary()
	if raw_weapon is Dictionary:
		var item := (raw_weapon as Dictionary).duplicate(true)
		return WEAPON_INSTANCE_SCRIPT.ensure_weapon_item(item)
	return {}


func _resolve_initial_reserve(item: Dictionary) -> int:
	for key in ["reserve_ammo", "ammo_reserve", "spare_ammo"]:
		if item.has(key):
			return maxi(0, int(item.get(key, 0)))
	var nested := item.get("weapon_instance", {}) as Dictionary
	for key in ["reserve_ammo", "ammo_reserve", "spare_ammo"]:
		if nested.has(key):
			return maxi(0, int(nested.get(key, 0)))
	return 0


func _target_group_for(target: Node3D) -> String:
	return ENEMY_TARGET_GROUP if is_instance_valid(target) and target.is_in_group(ENEMY_TARGET_GROUP) else PLAYER_TARGET_GROUP


func get_target_projectile_context(target: Node3D) -> Dictionary:
	if is_instance_valid(target) and target.is_in_group(ENEMY_TARGET_GROUP):
		return {"target_group": ENEMY_TARGET_GROUP, "projectile_collision_mask": ENEMY_PROJECTILE_MASK}
	return {"target_group": PLAYER_TARGET_GROUP, "projectile_collision_mask": PLAYER_PROJECTILE_MASK}


func _target_is_dead(target: Node3D) -> bool:
	if target.has_method("is_dead"):
		return bool(target.call("is_dead"))
	var hp: Variant = target.get("current_hp")
	return hp != null and float(hp) <= 0.0
