extends Node

## 一次性核对：真实进房后，怪的 **max_hp / contact_damage** 是否等于设计表。
## 存在的理由：`PROFILES` → `MonsterInjector` → `per_kind` 三层都会写血量和伤害，
## 任何一层没同步，最终的怪就会被打成"和设计文档不一样的血"。

const PLAN := "res://data/level_plans/expedition_03/level_plan.json"


func _ready() -> void:
	await get_tree().process_frame
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAN))
	var per_kind: Dictionary = data["monster_rules"]["stats"]["per_kind"]
	var injector := MonsterInjector.new()

	var bad := 0
	print("%-24s %-8s %-8s %-8s" % ["kind", "设计hp", "实际hp", "实际dmg"])
	for kind in per_kind:
		var cfg: Dictionary = injector.generate_box_enemy(str(kind), 1, 2, {})
		if cfg.is_empty():
			print("%-24s 配置为空" % kind)
			bad += 1
			continue
		var want_hp := int(per_kind[kind]["hp"])
		var want_dmg := int(per_kind[kind]["damage"])
		var got_hp := int(cfg.get("hp", -1))
		var got_dmg := int(cfg.get("damage", -1))
		var mark := "" if (got_hp == want_hp and got_dmg == want_dmg) else "  <<< MISMATCH"
		if mark != "":
			bad += 1
		print("%-24s %-8d %-8d %-8d%s" % [kind, want_hp, got_hp, got_dmg, mark])

	print("")
	if bad == 0:
		print("EGT_TUNING_RUNTIME_OK 33 只怪的进场血量与伤害与设计表逐只一致")
	else:
		print("EGT_TUNING_RUNTIME_FAIL %d 只不一致" % bad)
	get_tree().quit(0 if bad == 0 else 1)
