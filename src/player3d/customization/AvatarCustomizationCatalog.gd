class_name AvatarCustomizationCatalog
extends RefCounted
## 衣柜界面使用的展示目录。实际合法值仍由 PlayerAvatar3D 统一校验，
## 这里仅提供分类顺序、中文名称与方格预览色，不复制玩法状态。

const SLOT_ORDER: Array[String] = ["body", "head", "hand", "feet", "hat", "glasses"]

const SLOT_LABELS := {
	"body": "身体",
	"head": "头部",
	"hand": "手部",
	"feet": "脚部",
	"hat": "帽子",
	"glasses": "眼镜",
}

const VARIANT_LABELS := {
	"bunny_white": "月白",
	"cat_orange": "暖橙",
	"suit_olive": "橄榄作业服",
	"suit_sand": "沙岩作业服",
	"suit_cobalt": "钴蓝作业服",
	"sensor_olive": "橄榄感应头",
	"visor_cyan": "青蓝面罩",
	"plated_amber": "琥珀护面",
	"chibi_anime": "二次元女仆头",
	"grip_olive": "橄榄手套",
	"safety_orange": "安全橙手套",
	"gauntlet_teal": "青绿护手",
	"boot_sand": "沙岩靴",
	"boot_cobalt": "钴蓝靴",
	"boot_teal": "青绿靴",
	"none": "不佩戴",
	"bunny_ears": "兔耳帽",
	"field_cap": "基地软帽",
	"hard_hat": "工程安全帽",
	"sealed_hood": "密封兜帽",
	"mono_lens": "单目镜",
	"dual_goggles": "双目护镜",
	"wide_visor": "宽幅面罩",
}

const VARIANT_COLORS := {
	"bunny_white": Color(0.90, 0.94, 0.98),
	"cat_orange": Color(0.96, 0.48, 0.10),
	"suit_olive": Color(0.46, 0.49, 0.31),
	"suit_sand": Color(0.66, 0.50, 0.30),
	"suit_cobalt": Color(0.20, 0.42, 0.56),
	"sensor_olive": Color(0.56, 0.56, 0.30),
	"visor_cyan": Color(0.22, 0.52, 0.56),
	"plated_amber": Color(0.62, 0.39, 0.16),
	"chibi_anime": Color(0.16, 0.15, 0.18),
	"grip_olive": Color(0.56, 0.51, 0.27),
	"safety_orange": Color(0.78, 0.29, 0.09),
	"gauntlet_teal": Color(0.10, 0.52, 0.50),
	"boot_sand": Color(0.54, 0.36, 0.19),
	"boot_cobalt": Color(0.13, 0.30, 0.44),
	"boot_teal": Color(0.07, 0.39, 0.38),
	"none": Color(0.12, 0.16, 0.20),
	"bunny_ears": Color(0.92, 0.94, 0.98),
	"field_cap": Color(0.12, 0.20, 0.22),
	"hard_hat": Color(0.92, 0.53, 0.08),
	"sealed_hood": Color(0.13, 0.18, 0.26),
	"mono_lens": Color(0.20, 0.90, 1.0),
	"dual_goggles": Color(0.74, 0.22, 0.92),
	"wide_visor": Color(0.18, 0.68, 0.88),
}


static func get_slot_label(slot_id: String) -> String:
	return str(SLOT_LABELS.get(slot_id, slot_id))


static func get_variant_label(variant_id: String) -> String:
	return str(VARIANT_LABELS.get(variant_id, variant_id))


static func get_variant_color(variant_id: String) -> Color:
	return VARIANT_COLORS.get(variant_id, Color(0.24, 0.34, 0.42)) as Color


static func get_options(slot_id: String) -> Array[String]:
	var result: Array[String] = []
	for value in PlayerAvatar3D.CUSTOMIZATION_OPTIONS.get(slot_id, []):
		result.append(str(value))
	return result


static func validate_catalog() -> Array[String]:
	var failures: Array[String] = []
	for slot_id in SLOT_ORDER:
		var options := get_options(slot_id)
		if options.size() < 3:
			failures.append("%s fewer than three wardrobe options" % slot_id)
		for variant_id in options:
			if not PlayerAvatar3D.has_customization_variant(slot_id, variant_id):
				failures.append("invalid %s variant: %s" % [slot_id, variant_id])
	return failures
