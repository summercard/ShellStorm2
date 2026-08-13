class_name DeathSettlementModule
extends RefCounted
## 死亡结算模块 — 负责死亡掉落计算
## 规则：局内临时组合全丢，背包未保险资源部分丢，保险格物品必定保留

signal death_settlement_processed(loot: Array[Dictionary], insurance_saved: Array[Dictionary])
signal death_settlement_started()

var _loss_ratio: float = 0.5  # 背包未保险资源掉落比例

func _init() -> void:
	pass

## 设置掉落比例
func set_loss_ratio(ratio: float) -> void:
	_loss_ratio = clamp(ratio, 0.0, 1.0)

## 获取掉落比例
func get_loss_ratio() -> float:
	return _loss_ratio

## 处理玩家死亡结算
## 流程：
## 1. 标记所有局内临时装备（WeaponAssemblyTree）全部丢失
## 2. 背包中未保险的资源按比例掉落
## 3. 保险格物品必定保留（不触发掉落）
## 4. 带入装备不永久丢失（只扣耐久，如果有耐久系统）
##
## 参数：
##   inventory: InventoryModule 背包引用
##   insurance: InsuranceModule 保险格引用
##   insurance_exempt_ids: 保险格中的物品ID列表（已经保险的，跳过掉落）
##
## 返回：
##   Dictionary {
##     "dropped": Array[Dictionary] 掉落的物品,
##     "insurance_saved": Array[Dictionary] 保险保住的物品,
##     "total_lost": int 掉落物品数量
##   }
func process_death_settlement(inventory: InventoryModule, insurance: InsuranceModule, insurance_exempt_ids: Array[String] = []) -> Dictionary:
	death_settlement_started.emit()
	
	var dropped: Array[Dictionary] = []
	var insurance_saved: Array[Dictionary] = []
	
	# Step 1: 处理保险格（保险的物品必定保留）
	if insurance != null:
		var insured_items: Array[Dictionary] = insurance.get_all_insured_items()
		for insured in insured_items:
			insurance_saved.append(insured)
	
	# Step 2: 处理背包未保险物品（随机掉落部分）
	if inventory != null:
		var insured_ids := insurance_exempt_ids.duplicate()
		# 保险格物品ID也豁免
		if insurance != null:
			for insured in insurance.get_all_insured_items():
				var ins_id: String = insured.get("id", "")
				if not ins_id.is_empty():
					insured_ids.append(ins_id)
		
		# 调用 inventory.drop_random_items 进行掉落
		dropped = inventory.drop_random_items(_loss_ratio, insured_ids)
	
	var result := {
		"dropped": dropped,
		"insurance_saved": insurance_saved,
		"total_lost": dropped.size()
	}
	
	death_settlement_processed.emit(dropped, insurance_saved)
	return result

## 处理撤离成功结算
## 撤离成功后：背包所有物品安全带出，保险格物品也带出
## 返回带出的物品总数
func process_extraction_settlement(
	inventory: InventoryModule, insurance: InsuranceModule, quick_inventory: InventoryModule = null
) -> int:
	var extracted_count: int = 0
	
	if inventory != null:
		extracted_count += inventory.get_used_slots()
	
	if insurance != null:
		extracted_count += insurance.get_used_slots()

	if quick_inventory != null:
		extracted_count += quick_inventory.get_used_slots()
	
	return extracted_count

## 获取死亡掉落描述文本
func get_death_summary_text(result: Dictionary) -> String:
	var lines: Array[String] = []
	var dropped: Array[Dictionary] = result.get("dropped", [])
	var saved: Array[Dictionary] = result.get("insurance_saved", [])
	var total_lost: int = result.get("total_lost", 0)
	
	lines.append("=== 死亡结算 ===")
	lines.append("保险保住: %d 件" % saved.size())
	lines.append("战利品损失: %d 件" % total_lost)
	
	if not dropped.is_empty():
		var item_names: Array[String] = []
		for d in dropped:
			item_names.append(d.get("item", {}).get("id", "?"))
		lines.append("掉落物品: %s" % ", ".join(item_names))
	
	if not saved.is_empty():
		var saved_names: Array[String] = []
		for s in saved:
			saved_names.append(s.get("id", "?"))
		lines.append("保险保护: %s" % ", ".join(saved_names))
	
	return "\n".join(lines)

## 调试状态
func debug_status() -> String:
	return "DeathSettlementModule loss_ratio=%.0f%%" % [_loss_ratio * 100]
