class_name BaseEnergyService
extends RefCounted
## 基地能源纯数据规则。恢复速度以游戏小时计，因而暂停、加速、存档恢复
## 都和权威世界时钟保持一致，不读设备墙钟，也不制造离线收益。

const REGEN_PER_GAME_HOUR := 4.0
const HP_FULL_RESTORE_ENERGY := 25.0
const FLASHLIGHT_FULL_RESTORE_ENERGY := 25.0


static func sync_to_game_time(data: BaseData, elapsed_game_seconds: float) -> float:
	if data == null:
		return 0.0
	var now := maxf(0.0, elapsed_game_seconds)
	data.base_energy_capacity = maxf(1.0, data.base_energy_capacity)
	data.base_energy_current = clampf(
		data.base_energy_current, 0.0, data.base_energy_capacity
	)
	# 新档从满电开始；第一次看见大于0的世界时间时只建立基准，不补离线收益。
	# 若玩家已在起始时刻消费过能源，last=0 是合法基准，必须从0开始计算恢复。
	if (
		data.base_energy_last_synced_game_seconds <= 0.0
		and data.base_energy_current >= data.base_energy_capacity - 0.0001
	):
		data.base_energy_last_synced_game_seconds = now
		return 0.0
	if now <= data.base_energy_last_synced_game_seconds:
		data.base_energy_last_synced_game_seconds = now
		return 0.0
	var elapsed_hours := (now - data.base_energy_last_synced_game_seconds) / 3600.0
	var restored := minf(
		data.base_energy_capacity - data.base_energy_current,
		elapsed_hours * REGEN_PER_GAME_HOUR
	)
	data.base_energy_current += maxf(0.0, restored)
	data.base_energy_last_synced_game_seconds = now
	return maxf(0.0, restored)


static func get_snapshot(data: BaseData, elapsed_game_seconds: float) -> Dictionary:
	if data == null:
		return {
			"current": 0.0,
			"capacity": 100.0,
			"ratio": 0.0,
			"regen_per_game_hour": REGEN_PER_GAME_HOUR,
			"available": false,
		}
	sync_to_game_time(data, elapsed_game_seconds)
	var missing := maxf(0.0, data.base_energy_capacity - data.base_energy_current)
	return {
		"current": data.base_energy_current,
		"capacity": data.base_energy_capacity,
		"ratio": data.base_energy_current / maxf(1.0, data.base_energy_capacity),
		"regen_per_game_hour": REGEN_PER_GAME_HOUR,
		"game_hours_to_full": missing / REGEN_PER_GAME_HOUR,
		"last_synced_game_seconds": data.base_energy_last_synced_game_seconds,
		"available": true,
	}


static func plan_recovery(
	current_hp: int,
	max_hp: int,
	flashlight_charge_ratio: float,
	energy_available: float
) -> Dictionary:
	var safe_max_hp := maxi(1, max_hp)
	var missing_hp := maxi(0, safe_max_hp - maxi(0, current_hp))
	var missing_hp_ratio := float(missing_hp) / float(safe_max_hp)
	var missing_charge := 1.0 - clampf(flashlight_charge_ratio, 0.0, 1.0)
	var exact_cost := (
		missing_hp_ratio * HP_FULL_RESTORE_ENERGY
		+ missing_charge * FLASHLIGHT_FULL_RESTORE_ENERGY
	)
	var cost := int(ceil(exact_cost)) if exact_cost > 0.0001 else 0
	return {
		"needed": cost > 0,
		"cost": cost,
		"affordable": cost > 0 and energy_available + 0.0001 >= float(cost),
		"missing_hp": missing_hp,
		"missing_hp_ratio": missing_hp_ratio,
		"missing_flashlight_ratio": missing_charge,
		"target_hp": safe_max_hp,
		"target_flashlight_ratio": 1.0,
	}
