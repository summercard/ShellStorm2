extends Node

signal game_save_reset_completed(result: Dictionary)

const SAVE_PATH := "user://base_save.json"
const FacilityCatalog = preload("res://src/base/BaseFacilityCatalog.gd")
const FacilityService = preload("res://src/base/BaseFacilityService.gd")
const EnergyService = preload("res://src/base/BaseEnergyService.gd")
const SaveService = preload("res://src/base/ProfileSaveService.gd")
const ShopService = preload("res://src/base/BaseShopService.gd")
const BASE_LOADOUT_CAPACITY := 12
const BASE_VAULT_CAPACITY := 20
const RUNTIME_SAVE_DEBOUNCE_SECONDS := 0.45

var data: BaseData
var save_path: String = SAVE_PATH
var force_save_failure_for_test := false
var _runtime_checkpoint_provider: WeakRef
var _runtime_checkpoint_timer: Timer
var _runtime_checkpoint_dirty := false
var _pending_runtime_reason := ""

func _ready() -> void:
	_runtime_checkpoint_timer = Timer.new()
	_runtime_checkpoint_timer.name = "RuntimeCheckpointDebounce"
	_runtime_checkpoint_timer.one_shot = true
	_runtime_checkpoint_timer.timeout.connect(_on_runtime_checkpoint_timer_timeout)
	add_child(_runtime_checkpoint_timer)
	load_base()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST]:
		flush_runtime_checkpoint("application_boundary")

func load_base() -> void:
	var json: Variant = AtomicJsonStore.load_dictionary(
		save_path, Callable(self, "_is_supported_save_candidate")
	)
	if json is Dictionary:
		var unpacked := SaveService.unpack(json as Dictionary)
		if not bool(unpacked.get("success", false)):
			push_error("[BaseManager] Save envelope validation failed")
			data = BaseData.new()
			return
		var payload := unpacked.get("payload", {}) as Dictionary
		var save_version := str(payload.get("save_version", "legacy"))
		if save_version != BaseData.SAVE_VERSION:
			push_warning("[BaseManager] Loading compatible save version %s" % save_version)
		data = BaseData.from_dict(payload)
		data.save_revision = maxi(data.save_revision, int(unpacked.get("revision", 0)))
		data.last_saved_at_unix = maxi(data.last_saved_at_unix, int(unpacked.get("saved_at_unix", 0)))
		if data.last_save_reason.is_empty():
			data.last_save_reason = str(unpacked.get("reason", ""))
		_migrate_owned_item_instances()
		var insurance_return_migrated := _migrate_legacy_insurance_returns()
		var flashlight_migrated := _migrate_flashlight_module_unlocks()
		if bool(unpacked.get("legacy", false)) or flashlight_migrated or insurance_return_migrated:
			save_base("migrate_legacy_profile")
		return
	data = BaseData.new()


func _is_supported_save_candidate(candidate: Dictionary) -> bool:
	var unpacked := SaveService.unpack(candidate)
	return bool(unpacked.get("success", false))

func _ensure_data() -> void:
	if data == null:
		load_base()

func save_base(reason: String = "base_mutation") -> bool:
	_ensure_data()
	# 多个 Godot 实例（编辑器、游戏窗口、无头验收）可能共享同一 user:// 档案。
	# 旧实例不能把较低 revision 的内存镜像覆盖到已经更新的正式档。
	var disk_revision := _read_disk_revision()
	if disk_revision > data.save_revision:
		push_error(
			"[BaseManager] Refusing stale save: memory revision %d < disk revision %d (%s)"
			% [data.save_revision, disk_revision, reason]
		)
		load_base()
		return false
	var old_revision := data.save_revision
	var old_time := data.last_saved_at_unix
	var old_reason := data.last_save_reason
	data.save_revision = old_revision + 1
	data.last_saved_at_unix = int(Time.get_unix_time_from_system())
	data.last_save_reason = reason if not reason.is_empty() else "base_mutation"
	var payload := data._to_dict()
	var envelope := SaveService.build_envelope(payload, data.save_revision, data.last_save_reason)
	if not force_save_failure_for_test and AtomicJsonStore.save_dictionary(save_path, envelope):
		var persisted: Variant = AtomicJsonStore.load_dictionary(
			save_path, Callable(self, "_is_supported_save_candidate")
		)
		if persisted is Dictionary:
			var unpacked := SaveService.unpack(persisted as Dictionary)
			if (
				bool(unpacked.get("success", false))
				and int(unpacked.get("revision", -1)) == data.save_revision
			):
				return true
		push_error("[BaseManager] Save write completed but read-back validation failed")
	data.save_revision = old_revision
	data.last_saved_at_unix = old_time
	data.last_save_reason = old_reason
	return false


func _read_disk_revision() -> int:
	var stored: Variant = AtomicJsonStore.load_dictionary(
		save_path, Callable(self, "_is_supported_save_candidate")
	)
	if not stored is Dictionary:
		return -1
	var unpacked := SaveService.unpack(stored as Dictionary)
	return int(unpacked.get("revision", -1)) if bool(unpacked.get("success", false)) else -1


## 复位长期档和当前行动的唯一入口。先写入并回读一份合法的全新封套，
## 成功后才清掉旧 `.bak`；同时断开运行态快照提供者，避免旧场景卸载时
## 把刚清空的档案再次覆盖。画面设置使用独立 cfg，不属于本操作。
func reset_game_save() -> Dictionary:
	_ensure_data()
	var previous_data := data
	# “复位”清空的是档案内容，不是并发写保护使用的修订序列。若直接用
	# BaseData.new() 的 revision=0，save_base() 会把它判为旧实例回写并拒绝，
	# 导致任何已经保存过两次以上的正式档都无法通过ESC复位。
	var reset_revision_baseline := maxi(previous_data.save_revision, _read_disk_revision())
	var previous_provider := _runtime_checkpoint_provider
	var previous_dirty := _runtime_checkpoint_dirty
	var previous_reason := _pending_runtime_reason
	var previous_timer_time_left: float = (
		_runtime_checkpoint_timer.time_left
		if _runtime_checkpoint_timer != null else 0.0
	)
	if _runtime_checkpoint_timer != null:
		_runtime_checkpoint_timer.stop()
	_runtime_checkpoint_provider = null
	_runtime_checkpoint_dirty = false
	_pending_runtime_reason = ""
	data = BaseData.new()
	data.save_revision = reset_revision_baseline
	if not save_base("game_save_reset"):
		data = previous_data
		_runtime_checkpoint_provider = previous_provider
		_runtime_checkpoint_dirty = previous_dirty
		_pending_runtime_reason = previous_reason
		if previous_dirty and _runtime_checkpoint_timer != null:
			_runtime_checkpoint_timer.start(maxf(0.01, previous_timer_time_left))
		return {
			"success": false,
			"reason": "新存档写入或回读校验失败，原存档未复位",
			"save_path": save_path,
		}
	var backup_cleared := _remove_save_artifact(save_path + ".bak")
	var temp_cleared := _remove_save_artifact(save_path + ".tmp")
	var result: Dictionary = {
		"success": true,
		"reason": "游戏存档已复位",
		"save_path": save_path,
		"backup_cleared": backup_cleared,
		"temp_cleared": temp_cleared,
		"profile_schema": BaseData.SAVE_VERSION,
		"graphics_settings_preserved": true,
	}
	if not backup_cleared or not temp_cleared:
		push_warning("[BaseManager] Fresh profile is valid but stale save artifacts could not be removed")
	game_save_reset_completed.emit(result.duplicate(true))
	return result


func _remove_save_artifact(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func set_active_run_checkpoint(snapshot: Dictionary, reason: String) -> bool:
	_ensure_data()
	if snapshot.is_empty() or not bool(snapshot.get("valid", false)):
		return false
	if str(snapshot.get("checkpoint_id", snapshot.get("layout_id", ""))).is_empty():
		return false
	var previous := data.active_run_snapshot.duplicate(true)
	data.active_run_snapshot = snapshot.duplicate(true)
	if save_base("active_run_checkpoint:%s" % reason):
		return true
	data.active_run_snapshot = previous
	return false


func get_active_run_checkpoint() -> Dictionary:
	_ensure_data()
	return data.active_run_snapshot.duplicate(true)


## 高频运行时信号只更新内存镜像；统一防抖计时器/应用边界再把完整快照落盘。
## 这样 HUD、恢复查询立即一致，同时避免手电每扣 2% 都同步写磁盘。
func patch_active_run_checkpoint(fields: Dictionary) -> bool:
	_ensure_data()
	if data.active_run_snapshot.is_empty() or fields.is_empty():
		return false
	for key in fields.keys():
		data.active_run_snapshot[key] = fields[key]
	return true


func clear_active_run_checkpoint(reason: String = "run_finished") -> bool:
	_ensure_data()
	var previous := data.active_run_snapshot.duplicate(true)
	data.active_run_snapshot.clear()
	if save_base("active_run_clear:%s" % reason):
		return true
	data.active_run_snapshot = previous
	return false


## 注册当前承载玩家背包和装备的场景。只保存 WeakRef，避免自动加载单例延长场景寿命。
func register_runtime_checkpoint_provider(provider: Node) -> void:
	if provider == null:
		return
	if _runtime_checkpoint_timer != null:
		_runtime_checkpoint_timer.stop()
	_runtime_checkpoint_dirty = false
	_pending_runtime_reason = ""
	_runtime_checkpoint_provider = weakref(provider)


func unregister_runtime_checkpoint_provider(provider: Node, flush_before_unregister := true) -> void:
	var current := _get_runtime_checkpoint_provider()
	if current != provider:
		return
	if flush_before_unregister:
		flush_runtime_checkpoint("scene_unload")
	_runtime_checkpoint_provider = null
	_runtime_checkpoint_dirty = false
	_pending_runtime_reason = ""
	if _runtime_checkpoint_timer != null:
		_runtime_checkpoint_timer.stop()


## 普通物品变化只标脏并重启短计时器；计时结束时才抓取一次完整快照并落盘。
func queue_runtime_checkpoint(reason: String = "runtime_changed", delay_seconds := RUNTIME_SAVE_DEBOUNCE_SECONDS) -> void:
	if _get_runtime_checkpoint_provider() == null:
		return
	_runtime_checkpoint_dirty = true
	_pending_runtime_reason = reason
	if _runtime_checkpoint_timer == null:
		flush_runtime_checkpoint(reason)
		return
	_runtime_checkpoint_timer.start(maxf(0.01, delay_seconds))


## 房门、暂停、退出等关键边界同步重新抓取，确保位置、格位和弹药都是最新值。
func flush_runtime_checkpoint(reason: String = "runtime_flush") -> bool:
	if _runtime_checkpoint_timer != null:
		_runtime_checkpoint_timer.stop()
	var snapshot := _capture_runtime_checkpoint()
	if snapshot.is_empty():
		return false
	var saved := set_active_run_checkpoint(snapshot, reason)
	_runtime_checkpoint_dirty = not saved
	if saved:
		_pending_runtime_reason = ""
	return saved


func _on_runtime_checkpoint_timer_timeout() -> void:
	flush_runtime_checkpoint(
		_pending_runtime_reason if not _pending_runtime_reason.is_empty() else "runtime_changed"
	)


func _capture_runtime_checkpoint() -> Dictionary:
	var provider := _get_runtime_checkpoint_provider()
	if provider == null or not provider.has_method("build_runtime_save_snapshot"):
		return {}
	var value: Variant = provider.call("build_runtime_save_snapshot")
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _get_runtime_checkpoint_provider() -> Node:
	if _runtime_checkpoint_provider == null:
		return null
	var provider: Variant = _runtime_checkpoint_provider.get_ref()
	return provider as Node if provider is Node and is_instance_valid(provider) else null


## — 手电筒模块持久化 —
const FLASHLIGHT_MODULE_IDS := ["basic", "advanced", "efficient"]

func set_equipped_flashlight_module(module_id: String) -> bool:
	_ensure_data()
	if module_id not in FLASHLIGHT_MODULE_IDS:
		return false
	if not is_flashlight_module_unlocked(module_id):
		return false
	var previous := data.equipped_flashlight_module_id
	data.equipped_flashlight_module_id = module_id
	if save_base("flashlight_module_equip:%s" % module_id):
		return true
	data.equipped_flashlight_module_id = previous
	return false


func get_equipped_flashlight_module_id() -> String:
	_ensure_data()
	return data.equipped_flashlight_module_id


func is_flashlight_module_unlocked(module_id: String) -> bool:
	_ensure_data()
	match module_id:
		"basic":
			return true
		"advanced":
			return data.blueprint_attachment_tier >= 1 or "advanced" in data.unlocked_flashlight_modules
		"efficient":
			return "efficient" in data.unlocked_flashlight_modules
	return false


## 稀有模块实体在基地确认安装后转为永久解锁，不再要求把原物品留在保险柜。
func unlock_flashlight_module(module_id: String) -> bool:
	_ensure_data()
	if module_id not in FLASHLIGHT_MODULE_IDS:
		return false
	if module_id == "basic" or module_id in data.unlocked_flashlight_modules:
		return true
	data.unlocked_flashlight_modules.append(module_id)
	if save_base("flashlight_module_unlock:%s" % module_id):
		return true
	data.unlocked_flashlight_modules.erase(module_id)
	return false


func _migrate_flashlight_module_unlocks() -> bool:
	_ensure_data()
	var migrated := false
	for collection in [data.vault_items, data.pending_loadout_items]:
		for item in collection:
			if not (item is Dictionary):
				continue
			var module_id := str((item as Dictionary).get("module_id", ""))
			if module_id.is_empty() and str((item as Dictionary).get("id", "")) == "item_flashlight_efficient":
				module_id = "efficient"
			if module_id == "efficient" and module_id not in data.unlocked_flashlight_modules:
				data.unlocked_flashlight_modules.append(module_id)
				migrated = true
	return migrated


func get_facility_definitions() -> Array[Dictionary]:
	return FacilityCatalog.all_definitions()


func get_facility_snapshot(facility_id: String) -> Dictionary:
	_ensure_data()
	return FacilityService.get_snapshot(facility_id, data)


func get_facility_snapshots() -> Array[Dictionary]:
	_ensure_data()
	return FacilityService.get_all_snapshots(data)


## — 权威世界时钟 / 基地能源 —

func get_world_time_elapsed_game_seconds() -> float:
	_ensure_data()
	return maxf(0.0, data.world_time_elapsed_game_seconds)


func set_world_time_elapsed_game_seconds(value: float, persist := false) -> bool:
	_ensure_data()
	data.world_time_elapsed_game_seconds = maxf(0.0, value)
	if persist:
		return save_base("world_time_update")
	return true


func sync_base_energy_to_game_time(
	elapsed_game_seconds: float = -1.0,
	persist := false
) -> Dictionary:
	_ensure_data()
	var now := elapsed_game_seconds
	if now < 0.0:
		now = data.world_time_elapsed_game_seconds
	var restored := EnergyService.sync_to_game_time(data, now)
	if persist and restored > 0.0001:
		save_base("base_energy_regeneration")
	var snapshot := EnergyService.get_snapshot(data, now)
	snapshot["restored"] = restored
	return snapshot


func get_base_energy_snapshot(elapsed_game_seconds: float = -1.0) -> Dictionary:
	_ensure_data()
	var now := elapsed_game_seconds
	if now < 0.0:
		now = data.world_time_elapsed_game_seconds
	return EnergyService.get_snapshot(data, now)


func get_recovery_facility_snapshot(player: Node) -> Dictionary:
	_ensure_data()
	var energy := get_base_energy_snapshot()
	var result := {
		"available": false,
		"reason": "未找到角色",
		"energy": energy,
		"plan": {},
	}
	if player == null or not is_instance_valid(player):
		return result
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null or not flashlight.has_method("get_charge_ratio"):
		result["reason"] = "手电恢复接口缺失"
		return result
	var current_hp := int(player.get("current_hp"))
	var max_hp := int(player.get("max_hp"))
	var plan := EnergyService.plan_recovery(
		current_hp,
		max_hp,
		float(flashlight.call("get_charge_ratio")),
		float(energy.get("current", 0.0))
	)
	result["plan"] = plan
	result["current_hp"] = current_hp
	result["max_hp"] = max_hp
	result["flashlight_charge_ratio"] = float(flashlight.call("get_charge_ratio"))
	result["available"] = (
		current_hp > 0
		and bool(plan.get("needed", false))
		and bool(plan.get("affordable", false))
	)
	if current_hp <= 0:
		result["reason"] = "倒地状态不能使用恢复设施"
	elif not bool(plan.get("needed", false)):
		result["reason"] = "生命与手电均已充满"
	elif not bool(plan.get("affordable", false)):
		result["reason"] = "基地电量不足，需要 %d" % int(plan.get("cost", 0))
	else:
		result["reason"] = "可恢复"
	return result


func consume_base_energy(amount: float, reason := "base_energy_consume") -> bool:
	_ensure_data()
	if amount <= 0.0:
		return false
	sync_base_energy_to_game_time(data.world_time_elapsed_game_seconds, false)
	if data.base_energy_current + 0.0001 < amount:
		return false
	var previous := data.base_energy_current
	data.base_energy_current = maxf(0.0, data.base_energy_current - amount)
	if save_base(reason):
		return true
	data.base_energy_current = previous
	return false


func add_base_energy(amount: float, reason := "base_energy_restore") -> bool:
	_ensure_data()
	if amount <= 0.0 or data.base_energy_current >= data.base_energy_capacity:
		return false
	var previous := data.base_energy_current
	data.base_energy_current = minf(
		data.base_energy_capacity, data.base_energy_current + amount
	)
	if save_base(reason):
		return true
	data.base_energy_current = previous
	return false


## 恢复事务以 Prefab 功能入口为单位：先校验玩家/手电，随后原子保存能源，
## 保存成功后才修改运行态 HP 与手电，避免存档失败时白扣或白送能源。
func recover_player_state_at_facility(player: Node) -> Dictionary:
	_ensure_data()
	if player == null or not is_instance_valid(player):
		return {"success": false, "reason": "未找到角色"}
	if not player.has_method("heal"):
		return {"success": false, "reason": "角色恢复接口缺失"}
	var flashlight := player.get_node_or_null("PlayerFlashlight3D")
	if flashlight == null or not flashlight.has_method("get_charge_ratio"):
		return {"success": false, "reason": "手电恢复接口缺失"}
	var current_hp := int(player.get("current_hp"))
	var max_hp := int(player.get("max_hp"))
	if current_hp <= 0:
		return {"success": false, "reason": "倒地状态不能使用恢复设施"}
	sync_base_energy_to_game_time(data.world_time_elapsed_game_seconds, false)
	var plan := EnergyService.plan_recovery(
		current_hp,
		max_hp,
		float(flashlight.call("get_charge_ratio")),
		data.base_energy_current
	)
	if not bool(plan.get("needed", false)):
		return {"success": false, "reason": "生命与手电均已充满", "plan": plan}
	if not bool(plan.get("affordable", false)):
		return {
			"success": false,
			"reason": "基地电量不足，需要 %d" % int(plan.get("cost", 0)),
			"plan": plan,
		}
	var cost := float(plan.get("cost", 0))
	var previous := data.base_energy_current
	data.base_energy_current = maxf(0.0, data.base_energy_current - cost)
	if not save_base("base_recovery_facility"):
		data.base_energy_current = previous
		return {"success": false, "reason": "存档失败，基地电量未扣除", "plan": plan}
	player.call("heal", int(plan.get("missing_hp", 0)))
	if flashlight.has_method("restore_charge"):
		flashlight.call("restore_charge", float(plan.get("missing_flashlight_ratio", 0.0)))
	return {
		"success": true,
		"energy_spent": int(cost),
		"energy_remaining": data.base_energy_current,
		"hp_restored": int(plan.get("missing_hp", 0)),
		"flashlight_restored_ratio": float(plan.get("missing_flashlight_ratio", 0.0)),
		"plan": plan,
	}


func upgrade_facility(facility_id: String) -> Dictionary:
	_ensure_data()
	var definition: Dictionary = FacilityCatalog.get_definition(facility_id)
	if definition.is_empty():
		return {"success": false, "reason": "未知设施"}
	var building_type := int(definition.get("legacy_building_type", -1))
	if building_type < 0:
		return {"success": false, "reason": "该设施没有等级升级"}
	var cost := get_upgrade_cost(building_type)
	var result: Dictionary = FacilityService.apply_upgrade(facility_id, data, cost)
	if not bool(result.get("success", false)):
		return result
	if save_base():
		return result
	FacilityService.rollback_upgrade(result, data)
	return {"success": false, "reason": "存档失败，资源与等级已回滚"}

func record_run(success: bool, kills: int) -> void:
	data.record_run(success, kills)
	save_base()


func is_tutorial_completed() -> bool:
	_ensure_data()
	return data.tutorial_completed


func should_start_on_rooftop() -> bool:
	return not is_tutorial_completed()


func mark_tutorial_completed() -> bool:
	_ensure_data()
	if data.tutorial_completed:
		return true
	data.tutorial_completed = true
	if save_base("tutorial_completed_on_99f_entry"):
		return true
	data.tutorial_completed = false
	return false

func unlock_building(type: int) -> bool:
	match type:
		0: data.workshop_unlocked = true
		1: data.greenhouse_unlocked = true
		2: data.scrapyard_unlocked = true
		3: data.divination_unlocked = true
		4: data.vault_unlocked = true
		5: data.blackmarket_unlocked = true
		6: data.archive_unlocked = true
	save_base()
	return true

func upgrade_building(type: int) -> bool:
	match type:
		0: data.workshop_level += 1
		1: data.greenhouse_level += 1
		2: data.scrapyard_level += 1
		3: data.divination_level += 1
		4: data.vault_level += 1
		5: data.blackmarket_level += 1
		6: data.archive_level += 1
	save_base()
	return true

func is_unlocked(type: int) -> bool:
	match type:
		0: return data.workshop_unlocked
		1: return data.greenhouse_unlocked
		2: return data.scrapyard_unlocked
		3: return data.divination_unlocked
		4: return data.vault_unlocked
		5: return data.blackmarket_unlocked
		6: return data.archive_unlocked
	return false

func get_level(type: int) -> int:
	match type:
		0: return data.workshop_level
		1: return data.greenhouse_level
		2: return data.scrapyard_level
		3: return data.divination_level
		4: return data.vault_level
		5: return data.blackmarket_level
		6: return data.archive_level
	return 0

# Building unlock costs (in extraction value points)
const UNLOCK_COSTS := {
	0: 100,  # workshop
	1: 80,   # greenhouse
	2: 60,   # scrapyard
	3: 120,  # divination
	4: 150,  # vault
	5: 90,   # blackmarket
	6: 110   # archive
}

# Building upgrade costs per level
const UPGRADE_BASE_COST := {
	0: 50,   # workshop
	1: 40,   # greenhouse
	2: 30,   # scrapyard
	3: 60,   # divination
	4: 75,   # vault
	5: 45,   # blackmarket
	6: 55    # archive
}

func get_unlock_cost(type: int) -> int:
	return UNLOCK_COSTS.get(type, 999)

func get_upgrade_cost(type: int) -> int:
	var base: int = UPGRADE_BASE_COST.get(type, 0)
	return base * (get_level(type) + 1)

func update_long_term_progress(progress_type: String, value: float) -> void:
	match progress_type:
		"blueprint": data.blueprint_progress = clamp(value, 0.0, 1.0)
		"bullet": data.bullet_variant_progress = clamp(value, 0.0, 1.0)
		"boss": data.boss_defeated = true
		"zero_load": data.zero_load_extraction = true
		"five_tier": data.five_tier_weapon_made = true
	save_base()

func get_stats() -> Dictionary:
	return {
		"total_runs": data.total_runs,
		"successful_extractions": data.successful_extractions,
		"total_kills": data.total_kills,
		"extraction_rate": float(data.successful_extractions) / max(1, data.total_runs)
	}

## — 命运卡片局前选择 —
var pending_fate_card: Dictionary = {}

func set_pending_fate_card(card_data: Dictionary) -> void:
	pending_fate_card = card_data
	data.pending_fate_card = card_data
	save_base()

func get_pending_fate_card() -> Dictionary:
	return data.pending_fate_card

func clear_pending_fate_card() -> void:
	pending_fate_card = {}
	data.pending_fate_card = {}
	save_base()

## — 蓝图系统 —
func get_blueprint_tier(category_id: String) -> int:
	_ensure_data()
	match category_id:
		"gunbody": return data.blueprint_gunbody_tier
		"bullet": return data.blueprint_bullet_tier
		"attachment": return data.blueprint_attachment_tier
	return 0

func set_blueprint_tier(category_id: String, tier: int) -> void:
	_ensure_data()
	match category_id:
		"gunbody": data.blueprint_gunbody_tier = tier
		"bullet": data.blueprint_bullet_tier = tier
		"attachment": data.blueprint_attachment_tier = tier
	save_base()

## — 资源点数系统 —
func get_extraction_points() -> int:
	return data.extraction_points

func add_extraction_points(amount: int) -> void:
	data.extraction_points += amount
	save_base()

func spend_extraction_points(amount: int) -> bool:
	if data.extraction_points < amount:
		return false
	data.extraction_points -= amount
	save_base()
	return true

## — 保险柜物品持久化 —
func get_vault_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data.vault_items:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result

func set_vault_items(items: Array[Dictionary]) -> void:
	data.vault_items = []
	for item in items:
		data.vault_items.append(ShopService.ensure_item_instance(item))
	save_base()

func add_vault_item(item: Dictionary) -> bool:
	var previous := data.vault_items.duplicate(true)
	var result := _try_add_owned_item(data.vault_items, item, _get_vault_capacity())
	if not bool(result.get("success", false)):
		return false
	data.vault_items = result.get("items", []) as Array
	if save_base("vault_add"):
		return true
	data.vault_items = previous
	return false

func remove_vault_item(index: int) -> bool:
	if index < 0 or index >= data.vault_items.size():
		return false
	data.vault_items.remove_at(index)
	save_base()
	return true

func _get_vault_capacity() -> int:
	# 长期保险柜基础容量为20格，设施等级继续提供增量扩展。
	return BASE_VAULT_CAPACITY + data.vault_level

func get_vault_capacity() -> int:
	return _get_vault_capacity()

func get_vault_free_slots() -> int:
	return max(0, _get_vault_capacity() - data.vault_items.size())


## — 基地自动贩卖机 —
func get_base_shop_goods() -> Array[Dictionary]:
	return ShopService.get_goods()


func purchase_base_shop_item(item_id: String, transaction_id: String = "", target_owner: String = "loadout") -> Dictionary:
	_ensure_data()
	var effective_transaction_id := transaction_id
	if effective_transaction_id.is_empty():
		effective_transaction_id = ShopService.generate_transaction_id("buy")
	if ShopService.has_completed(data.completed_transaction_ids, effective_transaction_id):
		return {"success": true, "duplicate": true, "transaction_id": effective_transaction_id}
	var definition := ItemRegistry.get_instance().get_item(item_id)
	if definition.is_empty() or not bool(definition.get("base_shop_enabled", false)):
		return {"success": false, "reason": "商品未在基地货架上"}
	var price := int(definition.get("base_buy_price", 0))
	if price <= 0:
		return {"success": false, "reason": "商品购买价配置无效"}
	if data.extraction_points < price:
		return {"success": false, "reason": "魂不足"}
	if target_owner not in ["loadout", "vault"]:
		return {"success": false, "reason": "购买目标无效"}

	var purchased := ShopService.make_item_instance(definition, effective_transaction_id)
	var target_items: Array = data.pending_loadout_items if target_owner == "loadout" else data.vault_items
	var target_capacity := BASE_LOADOUT_CAPACITY if target_owner == "loadout" else _get_vault_capacity()
	var add_result := _try_add_owned_item(target_items, purchased, target_capacity)
	if not bool(add_result.get("success", false)):
		return {"success": false, "reason": str(add_result.get("reason", "目标空间不足"))}
	var old_points := data.extraction_points
	var old_target := target_items.duplicate(true)
	data.extraction_points -= price
	if target_owner == "loadout":
		data.pending_loadout_items = add_result.get("items", []) as Array
	else:
		data.vault_items = add_result.get("items", []) as Array
	ShopService.append_completed(data.completed_transaction_ids, effective_transaction_id)
	if save_base("shop_buy:%s" % item_id):
		return {
			"success": true,
			"transaction_id": effective_transaction_id,
			"price": price,
			"item": purchased.duplicate(true),
			"target_owner": target_owner,
			"slot_index": int(add_result.get("slot_index", -1)),
			"merged": bool(add_result.get("merged", false)),
		}
	data.extraction_points = old_points
	if target_owner == "loadout":
		data.pending_loadout_items = old_target
	else:
		data.vault_items = old_target
	data.completed_transaction_ids.erase(effective_transaction_id)
	return {"success": false, "reason": "存档失败，购买已回滚"}


func sell_base_shop_item(item_instance_id: String, transaction_id: String = "", source_owner: String = "vault") -> Dictionary:
	_ensure_data()
	var effective_transaction_id := transaction_id
	if effective_transaction_id.is_empty():
		effective_transaction_id = ShopService.generate_transaction_id("sell")
	if ShopService.has_completed(data.completed_transaction_ids, effective_transaction_id):
		return {"success": true, "duplicate": true, "transaction_id": effective_transaction_id}
	if source_owner not in ["loadout", "vault"]:
		return {"success": false, "reason": "出售来源无效"}
	var source_items: Array = data.pending_loadout_items if source_owner == "loadout" else data.vault_items
	var index := ShopService.find_vault_item_index(source_items, item_instance_id)
	if index < 0:
		return {"success": false, "reason": "%s中不存在该物品实例" % ("随身背包" if source_owner == "loadout" else "保险柜")}
	var sold := (source_items[index] as Dictionary).duplicate(true)
	var sell_price := ShopService.get_sell_price(sold) * maxi(1, int(sold.get("count", 1)))
	if sell_price <= 0:
		return {"success": false, "reason": "该物品不在自动贩卖机收购清单"}

	var old_points := data.extraction_points
	var old_source := source_items.duplicate(true)
	source_items.remove_at(index)
	if source_owner == "loadout":
		data.pending_loadout_items = source_items
	else:
		data.vault_items = source_items
	data.extraction_points += sell_price
	ShopService.append_completed(data.completed_transaction_ids, effective_transaction_id)
	if save_base("shop_sell:%s" % str(sold.get("id", "unknown"))):
		return {
			"success": true,
			"transaction_id": effective_transaction_id,
			"value": sell_price,
			"sold_item": sold,
		}
	data.extraction_points = old_points
	if source_owner == "loadout":
		data.pending_loadout_items = old_source
	else:
		data.vault_items = old_source
	data.completed_transaction_ids.erase(effective_transaction_id)
	return {"success": false, "reason": "存档失败，出售已回滚"}

func get_pending_loadout_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data.pending_loadout_items:
		if item is Dictionary:
			result.append(item.duplicate(true))
	return result

func get_pending_loadout_capacity() -> int:
	return BASE_LOADOUT_CAPACITY

func get_pending_loadout_free_slots() -> int:
	return maxi(0, BASE_LOADOUT_CAPACITY - data.pending_loadout_items.size())

func transfer_base_storage_item(source_owner: String, source_index: int, target_owner: String) -> Dictionary:
	_ensure_data()
	if source_owner == target_owner or source_owner not in ["vault", "loadout"] or target_owner not in ["vault", "loadout"]:
		return {"success": false, "reason": "请选择另一侧作为目标"}
	var source: Array = data.vault_items if source_owner == "vault" else data.pending_loadout_items
	var target: Array = data.vault_items if target_owner == "vault" else data.pending_loadout_items
	if source_index < 0 or source_index >= source.size() or not source[source_index] is Dictionary:
		return {"success": false, "reason": "来源格已变化，请重试"}
	var moved := (source[source_index] as Dictionary).duplicate(true)
	var target_capacity := _get_vault_capacity() if target_owner == "vault" else BASE_LOADOUT_CAPACITY
	var add_result := _try_add_owned_item(target, moved, target_capacity)
	if not bool(add_result.get("success", false)):
		return add_result
	var old_vault := data.vault_items.duplicate(true)
	var old_loadout := data.pending_loadout_items.duplicate(true)
	source.remove_at(source_index)
	if source_owner == "vault":
		data.vault_items = source
		data.pending_loadout_items = add_result.get("items", []) as Array
	else:
		data.pending_loadout_items = source
		data.vault_items = add_result.get("items", []) as Array
	if save_base("storage_transfer:%s_to_%s" % [source_owner, target_owner]):
		return {
			"success": true,
			"item": moved,
			"source_owner": source_owner,
			"target_owner": target_owner,
			"slot_index": int(add_result.get("slot_index", -1)),
			"merged": bool(add_result.get("merged", false)),
		}
	data.vault_items = old_vault
	data.pending_loadout_items = old_loadout
	return {"success": false, "reason": "存档失败，转移已回滚"}

func transfer_runtime_inventory_item(source_owner: String, source_index: int, inventory: InventoryModule) -> Dictionary:
	_ensure_data()
	if inventory == null or source_owner not in ["vault", "inventory"]:
		return {"success": false, "reason": "当前背包未连接"}
	var old_vault := data.vault_items.duplicate(true)
	var old_inventory := inventory.get_slots_snapshot()
	var moved: Dictionary
	var merged := false
	if source_owner == "inventory":
		var slot_data := inventory.get_slot(source_index)
		if slot_data.is_empty():
			return {"success": false, "reason": "I键背包中的来源格已变化"}
		moved = (slot_data.get("item", {}) as Dictionary).duplicate(true)
		moved["count"] = int(slot_data.get("count", 1))
		var add_result := _try_add_owned_item(data.vault_items, moved, _get_vault_capacity())
		if not bool(add_result.get("success", false)):
			return add_result
		if not inventory.remove_from_slot(source_index, int(moved.get("count", 1))):
			return {"success": false, "reason": "I键背包物品已变化，请重试"}
		data.vault_items = add_result.get("items", []) as Array
		merged = bool(add_result.get("merged", false))
	else:
		if source_index < 0 or source_index >= data.vault_items.size() or not data.vault_items[source_index] is Dictionary:
			return {"success": false, "reason": "保险柜来源格已变化"}
		moved = (data.vault_items[source_index] as Dictionary).duplicate(true)
		var requested := maxi(1, int(moved.get("count", 1)))
		if inventory.add_item(moved, requested) != requested:
			inventory.restore_slots_snapshot(old_inventory)
			return {"success": false, "reason": "当前I键背包空间不足"}
		data.vault_items.remove_at(source_index)
	if save_base("storage_transfer:%s_to_%s" % [source_owner, "vault" if source_owner == "inventory" else "inventory"]):
		return {"success": true, "item": moved, "source_owner": source_owner, "merged": merged}
	data.vault_items = old_vault
	inventory.restore_slots_snapshot(old_inventory)
	return {"success": false, "reason": "存档失败，I键背包与保险柜已同时回滚"}

func purchase_base_shop_item_to_inventory(item_id: String, inventory: InventoryModule, transaction_id: String = "") -> Dictionary:
	_ensure_data()
	if inventory == null:
		return {"success": false, "reason": "当前I键背包未连接"}
	var effective_transaction_id := transaction_id if not transaction_id.is_empty() else ShopService.generate_transaction_id("buy")
	if ShopService.has_completed(data.completed_transaction_ids, effective_transaction_id):
		return {"success": true, "duplicate": true, "transaction_id": effective_transaction_id}
	var definition := ItemRegistry.get_instance().get_item(item_id)
	if definition.is_empty() or not bool(definition.get("base_shop_enabled", false)):
		return {"success": false, "reason": "商品未在基地货架上"}
	var price := int(definition.get("base_buy_price", 0))
	if price <= 0 or data.extraction_points < price:
		return {"success": false, "reason": "魂不足" if price > 0 else "商品购买价配置无效"}
	var purchased := ShopService.make_item_instance(definition, effective_transaction_id)
	var old_inventory := inventory.get_slots_snapshot()
	if inventory.add_item(purchased, 1) != 1:
		inventory.restore_slots_snapshot(old_inventory)
		return {"success": false, "reason": "当前I键背包空间不足"}
	var old_points := data.extraction_points
	data.extraction_points -= price
	ShopService.append_completed(data.completed_transaction_ids, effective_transaction_id)
	if save_base("shop_buy_runtime:%s" % item_id):
		return {"success": true, "transaction_id": effective_transaction_id, "price": price, "item": purchased, "target_owner": "inventory"}
	data.extraction_points = old_points
	data.completed_transaction_ids.erase(effective_transaction_id)
	inventory.restore_slots_snapshot(old_inventory)
	return {"success": false, "reason": "存档失败，购买已回滚"}

func sell_runtime_inventory_item(inventory: InventoryModule, slot_index: int, transaction_id: String = "") -> Dictionary:
	_ensure_data()
	if inventory == null:
		return {"success": false, "reason": "当前I键背包未连接"}
	var effective_transaction_id := transaction_id if not transaction_id.is_empty() else ShopService.generate_transaction_id("sell")
	if ShopService.has_completed(data.completed_transaction_ids, effective_transaction_id):
		return {"success": true, "duplicate": true, "transaction_id": effective_transaction_id}
	var slot_data := inventory.get_slot(slot_index)
	if slot_data.is_empty():
		return {"success": false, "reason": "I键背包中的物品已变化"}
	var sold := (slot_data.get("item", {}) as Dictionary).duplicate(true)
	var count := maxi(1, int(slot_data.get("count", 1)))
	sold["count"] = count
	var sell_value := ShopService.get_sell_price(sold) * count
	if sell_value <= 0:
		return {"success": false, "reason": "该物品不在自动贩卖机收购清单"}
	var old_inventory := inventory.get_slots_snapshot()
	if not inventory.remove_from_slot(slot_index, count):
		return {"success": false, "reason": "I键背包中的物品已变化"}
	var old_points := data.extraction_points
	data.extraction_points += sell_value
	ShopService.append_completed(data.completed_transaction_ids, effective_transaction_id)
	if save_base("shop_sell_runtime:%s" % str(sold.get("id", "unknown"))):
		return {"success": true, "transaction_id": effective_transaction_id, "value": sell_value, "sold_item": sold}
	data.extraction_points = old_points
	data.completed_transaction_ids.erase(effective_transaction_id)
	inventory.restore_slots_snapshot(old_inventory)
	return {"success": false, "reason": "存档失败，出售已回滚"}

func stage_vault_item_for_loadout(vault_index: int) -> bool:
	return bool(transfer_base_storage_item("vault", vault_index, "loadout").get("success", false))

func remove_pending_loadout_item(loadout_index: int) -> bool:
	return bool(transfer_base_storage_item("loadout", loadout_index, "vault").get("success", false))

func _try_add_owned_item(items: Array, incoming: Dictionary, capacity: int) -> Dictionary:
	var updated := items.duplicate(true)
	var normalized := ShopService.ensure_item_instance(incoming)
	var incoming_item_instance := str(normalized.get("item_instance_id", ""))
	var incoming_weapon_instance := str(normalized.get("weapon_instance_id", ""))
	for raw_existing in updated:
		if not raw_existing is Dictionary:
			continue
		var owned_existing := raw_existing as Dictionary
		if not incoming_item_instance.is_empty() and str(owned_existing.get("item_instance_id", "")) == incoming_item_instance:
			return {"success": false, "reason": "目标中已存在同一物品实例"}
		if not incoming_weapon_instance.is_empty() and str(owned_existing.get("weapon_instance_id", "")) == incoming_weapon_instance:
			return {"success": false, "reason": "目标中已存在同一枪械实例"}
	var remaining := maxi(1, int(normalized.get("count", 1)))
	var stack_max := maxi(1, int(normalized.get("stack_max", 1)))
	var content_id := str(normalized.get("id", normalized.get("weapon_content_id", "")))
	var first_slot := -1
	var merged := false
	if stack_max > 1 and not content_id.is_empty():
		for index in updated.size():
			if not updated[index] is Dictionary:
				continue
			var existing := updated[index] as Dictionary
			if str(existing.get("id", existing.get("weapon_content_id", ""))) != content_id:
				continue
			var existing_count := maxi(1, int(existing.get("count", 1)))
			var room := maxi(0, maxi(1, int(existing.get("stack_max", stack_max))) - existing_count)
			if room <= 0:
				continue
			var amount := mini(room, remaining)
			existing["count"] = existing_count + amount
			updated[index] = existing
			remaining -= amount
			first_slot = index if first_slot < 0 else first_slot
			merged = true
			if remaining <= 0:
				break
	while remaining > 0:
		if updated.size() >= capacity:
			return {"success": false, "reason": "%s空间不足" % ("随身背包" if capacity == BASE_LOADOUT_CAPACITY else "保险柜")}
		var stack := normalized.duplicate(true)
		stack["count"] = mini(stack_max, remaining)
		if first_slot >= 0:
			stack.erase("item_instance_id")
			stack.erase("weapon_instance_id")
			stack = ShopService.ensure_item_instance(stack)
		updated.append(stack)
		if first_slot < 0:
			first_slot = updated.size() - 1
		remaining -= int(stack.get("count", 1))
	return {"success": true, "items": updated, "slot_index": first_slot, "merged": merged}

func clear_pending_loadout() -> void:
	var not_restored: Array = []
	for item in data.pending_loadout_items:
		if item is Dictionary and data.vault_items.size() < _get_vault_capacity():
			data.vault_items.append((item as Dictionary).duplicate(true))
		elif item is Dictionary:
			not_restored.append((item as Dictionary).duplicate(true))
	data.pending_loadout_items = not_restored
	save_base()

func consume_pending_loadout() -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for staged in data.pending_loadout_items:
		if not (staged is Dictionary):
			continue
		consumed.append((staged as Dictionary).duplicate(true))
	data.pending_loadout_items.clear()
	save_base()
	return consumed

func _find_matching_vault_item(target: Dictionary) -> int:
	var target_instance_id := str(target.get("weapon_instance_id", ""))
	var target_id: String = target.get("id", "")
	if not target_instance_id.is_empty():
		for i in data.vault_items.size():
			var candidate: Dictionary = data.vault_items[i]
			if str(candidate.get("weapon_instance_id", "")) == target_instance_id:
				return i
		return -1
	for i in data.vault_items.size():
		var item: Dictionary = data.vault_items[i]
		if target_id != "" and item.get("id", "") == target_id:
			return i
		if item == target:
			return i
	return -1


func sell_vault_weapon(weapon_instance_id: String) -> Dictionary:
	if weapon_instance_id.is_empty():
		return {"success": false, "reason": "缺少枪械实例ID"}
	var result := sell_base_shop_item(
		weapon_instance_id, ShopService.generate_transaction_id("vault_sell")
	)
	if bool(result.get("success", false)):
		result["weapon_instance_id"] = weapon_instance_id
	return result


func _migrate_owned_item_instances() -> void:
	if data == null:
		return
	for collection_name in ["vault_items", "pending_loadout_items", "extraction_loot"]:
		var source: Array = data.get(collection_name)
		var migrated: Array = []
		for raw_item in source:
			if raw_item is Dictionary:
				migrated.append(ShopService.ensure_item_instance(raw_item as Dictionary))
		data.set(collection_name, migrated)


## 1.7曾把死亡保险物写进只有独立BaseMenu才显示的撤离待领取栏。
## 99F实际会重载TowerDescent3D，因此把带旧标记的条目迁回专用原槽快照，
## 让已有玩家存档中的“消失物品”也能在下次进入基地时恢复。
func _migrate_legacy_insurance_returns() -> bool:
	if data == null:
		return false
	var migrated := false
	var retained_loot: Array = []
	for raw_item in data.extraction_loot:
		if not raw_item is Dictionary:
			continue
		var item := (raw_item as Dictionary).duplicate(true)
		if not bool(item.get("returned_by_insurance", false)):
			retained_loot.append(item)
			continue
		var slot_index := int(item.get("insurance_slot", data.pending_insurance_slots.size()))
		var count := maxi(1, int(item.get("count", 1)))
		item.erase("returned_by_insurance")
		item.erase("insurance_slot")
		item.erase("count")
		data.pending_insurance_slots.append({
			"item": item,
			"count": count,
			"insurance_slot": slot_index,
		})
		migrated = true
	if migrated:
		data.extraction_loot = retained_loot
	return migrated

## — 撤离战利品管理（返回大厅后待存入仓库）—
func get_extraction_loot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in data.extraction_loot:
		if item is Dictionary:
			result.append(item.duplicate(true))
	return result

func store_insurance_return_items(entries: Array, transaction_id: String = "") -> Dictionary:
	_ensure_data()
	var effective_transaction_id := transaction_id if not transaction_id.is_empty() else ShopService.generate_transaction_id("insurance_return")
	if ShopService.has_completed(data.completed_transaction_ids, effective_transaction_id):
		return {"success": true, "duplicate": true, "transaction_id": effective_transaction_id}
	var old_pending := data.pending_insurance_slots.duplicate(true)
	var returned := 0
	for raw_entry in entries:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var item := (entry.get("item", entry) as Dictionary).duplicate(true)
		if item.is_empty():
			continue
		var count := maxi(1, int(entry.get("count", item.get("count", 1))))
		item.erase("count")
		var identity := _owned_item_identity(item)
		if not identity.is_empty() and _insurance_return_contains_identity(identity):
			continue
		data.pending_insurance_slots.append({
			"item": ShopService.ensure_item_instance(item),
			"count": count,
			"insurance_slot": maxi(0, int(entry.get("insurance_slot", returned))),
			"insured_at": int(entry.get("insured_at", Time.get_unix_time_from_system())),
		})
		returned += 1
	if returned <= 0 and not entries.is_empty():
		data.pending_insurance_slots = old_pending
		return {"success": false, "reason": "保险返还物无法写入基地保险格中转集合"}
	ShopService.append_completed(data.completed_transaction_ids, effective_transaction_id)
	if save_base("insurance_return"):
		return {"success": true, "returned_count": returned, "transaction_id": effective_transaction_id}
	data.pending_insurance_slots = old_pending
	data.completed_transaction_ids.erase(effective_transaction_id)
	return {"success": false, "reason": "存档失败，保险返还已回滚"}


func get_pending_insurance_slots() -> Array[Dictionary]:
	_ensure_data()
	# 兼容本次修复前已在内存中生成、尚未重新load_base的1.7数据。
	if _migrate_legacy_insurance_returns():
		save_base("migrate_runtime_insurance_return")
	var result: Array[Dictionary] = []
	for entry in data.pending_insurance_slots:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


## 将死亡中转物与99F基地运行态检查点在同一次原子写盘中交接。
## 成功前不清中转集合，避免场景切换/断电窗口造成保险物永久丢失。
func commit_pending_insurance_to_runtime(snapshot: Dictionary) -> bool:
	_ensure_data()
	if data.pending_insurance_slots.is_empty():
		return true
	if snapshot.is_empty() or not bool(snapshot.get("valid", false)):
		return false
	var old_pending := data.pending_insurance_slots.duplicate(true)
	var old_checkpoint := data.active_run_snapshot.duplicate(true)
	data.pending_insurance_slots.clear()
	data.active_run_snapshot = snapshot.duplicate(true)
	if save_base("death_insurance_restored_to_99f"):
		return true
	data.pending_insurance_slots = old_pending
	data.active_run_snapshot = old_checkpoint
	return false


func _owned_item_identity(item: Dictionary) -> String:
	var weapon_id := str(item.get("weapon_instance_id", ""))
	if not weapon_id.is_empty():
		return "weapon:" + weapon_id
	var item_id := str(item.get("item_instance_id", ""))
	if not item_id.is_empty():
		return "item:" + item_id
	return ""


func _insurance_return_contains_identity(identity: String) -> bool:
	for raw_entry in data.pending_insurance_slots:
		if not raw_entry is Dictionary:
			continue
		var entry := raw_entry as Dictionary
		var item := entry.get("item", entry) as Dictionary
		if _owned_item_identity(item) == identity:
			return true
	return false

func add_extraction_loot(item: Dictionary, count: int = 1) -> void:
	var new_item := ShopService.ensure_item_instance(item)
	var instance_id := str(new_item.get("weapon_instance_id", ""))
	if not instance_id.is_empty():
		for existing in data.extraction_loot:
			if existing is Dictionary and str(existing.get("weapon_instance_id", "")) == instance_id:
				return
	new_item["count"] = count
	data.extraction_loot.append(new_item)
	save_base()

func add_extraction_loot_items(items: Array[Dictionary]) -> void:
	for item in items:
		if item is Dictionary:
			add_extraction_loot(item, item.get("count", 1))
	save_base()

func get_extraction_loot_count() -> int:
	return data.extraction_loot.size()

func deposit_extraction_loot_item(index: int) -> bool:
	if index < 0 or index >= data.extraction_loot.size():
		return false
	var item: Dictionary = data.extraction_loot[index]
	if item.is_empty():
		data.extraction_loot.remove_at(index)
		save_base()
		return false
	if add_vault_item(item):
		data.extraction_loot.remove_at(index)
		save_base()
		return true
	return false

func deposit_all_extraction_loot() -> int:
	var deposited := 0
	# 逐个存入，溢出处理
	var overflow_count := 0
	for item in data.extraction_loot:
		if item is Dictionary and not item.is_empty():
			if add_vault_item(item):
				deposited += 1
			else:
				overflow_count += 1
	# 溢出转换为资源点数
	if overflow_count > 0:
		add_extraction_points(overflow_count * 5)
	data.extraction_loot.clear()
	save_base()
	return deposited

func discard_extraction_loot_item(index: int) -> void:
	if index < 0 or index >= data.extraction_loot.size():
		return
	data.extraction_loot.remove_at(index)
	save_base()

func clear_extraction_loot() -> void:
	data.extraction_loot.clear()
	save_base()
