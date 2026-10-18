extends Node
## 一次性诊断：保险盘 2 格能否收下一把步枪（4×2）。
## 用于判断 verify_weapon_instance_fate_ownership_flow 第 87 行越界是既有问题还是本次回归。


func _ready() -> void:
	var registry := ItemRegistry.get_instance()
	for item_id in ["weapon_shotgun", "weapon_starter_rifle", "weapon_pistol"]:
		var item := registry.get_item(item_id)
		var ensured := WeaponInstance.ensure_weapon_item(item)
		var insurance := InsuranceModule.new(2)
		var ok := insurance.insure_item_direct(ensured)
		print("%-22s grid=%s insure=%s occupied=%d" % [
			item_id, str(ensured.get("grid_size", [])), str(ok),
			insurance.get_occupied_slots().size(),
		])
	get_tree().quit(0)
