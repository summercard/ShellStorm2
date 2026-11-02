class_name NpcCatalog
extends RefCounted
## 基地 NPC 内容目录：**NPC 的稳定 ID → 名称 / 身份 / 皮肤 / 台词**。
##
## 为什么是目录脚本而不是把内容写进 `NpcCharacter3D`：
##   与 `BarkCatalog` / `MusicCatalog` 同规格 —— 台词与身份集中在一处，实体只认
##   `npc_id`，逻辑侧不出现任何台词字面量；后续迁入内容数据库时只替换本文件取数，
##   场景与实体不动。**当前尚未与 xlsx 对表**。
##
## 皮肤口径：NPC 复用玩家 bunny01 几何，**不新增美术资产**。绿皮的颜色**来自衣柜**
## （`suit_green` 苔绿作业服），这里只登记变体 ID；运行期由 `material_override`
## 统一覆盖所有本体网格（见 `NpcCharacter3D._apply_skin`）。

## 99F 基地常驻 NPC（2026-11-02 主人要求：用主角模型换全绿皮肤，会自己移动、可对话）。
const NPC_BASE99_GREEN := "npc_base99_green"

## 皮肤来源：**衣柜里的作业服变体**，不是这里另存的一份颜色。
##
## 2026-11-02 主人要求「绿色直接从可以更换的衣柜里去找，可以直接用的」。所以：
##   - 绿皮取 `AvatarCustomizationCatalog.VARIANT_COLORS["suit_green"]`，
##     而那个变体同时是 `PlayerAvatar3D.CUSTOMIZATION_OPTIONS["body"]` 的合法值 ⇒
##     玩家在衣柜里选「苔绿作业服」就是同一个绿，NPC 与玩家共用一个色源。
##   - 本文件**不再保存 albedo**，只保存变体 ID。改颜色只改衣柜一处。
const SKIN_VARIANT_BODY := "suit_green"

## 自发光强度：**恒为 0**（2026-11-02 业主口径）。
##
## 曾经为兜夜景可读性开到 0.30，实机表现是整只泛荧光 —— 业主原话
## 「为什么是自发光的绿色？荧光感太强了」。可读性改用"场景光照 + 衣柜绿本身的明度"
## 解决：白天正常、夜里偏暗但仍是干净的绿，不再有发光轮廓。
##
## 字段保留（不是死值）：将来若要给某条 NPC 做"辐射变异体"之类的发光皮肤，
## 只改那条定义的 `skin_emission`，`_apply_skin` 里的分支现成可用。
const SKIN_EMISSION := 0.0

const DEFINITIONS := {
	NPC_BASE99_GREEN: {
		"display_name": "绿苔",
		"role": "99F 基地看守",
		"skin_variant": SKIN_VARIANT_BODY,
		"skin_emission": SKIN_EMISSION,
		"lines": [
			"你回来了。这层的灯我一直盯着，没灭过。",
			"中央那座全息台能选远征路线。挑一条，别空手回来。",
			"枪械工坊在西侧。缺零件就去吵醒那台老机器。",
			"我？我就在这儿走来走去。总比站着生锈好。",
		],
	},
}


static func has_npc(npc_id: String) -> bool:
	return DEFINITIONS.has(npc_id)


static func get_definition(npc_id: String) -> Dictionary:
	return (DEFINITIONS.get(npc_id, {}) as Dictionary).duplicate(true)


static func get_display_name(npc_id: String) -> String:
	return str((DEFINITIONS.get(npc_id, {}) as Dictionary).get("display_name", npc_id))


static func get_role(npc_id: String) -> String:
	return str((DEFINITIONS.get(npc_id, {}) as Dictionary).get("role", ""))


## 皮肤色：**转调衣柜目录**，不在本文件存值。
## 取不到时返回 `Color.MAGENTA`（醒目失败色）而不是悄悄用衣柜的兜底灰蓝 ——
## 衣柜变体被改名/删除时，宁可画面上看见紫色，也不要让人以为"NPC 就该是这个颜色"。
static func get_skin_albedo(npc_id: String) -> Color:
	var variant := get_skin_variant(npc_id)
	if variant.is_empty() or not PlayerAvatar3D.has_customization_variant("body", variant):
		push_warning("[NpcCatalog] NPC『%s』的皮肤变体『%s』不在衣柜里。" % [npc_id, variant])
		return Color.MAGENTA
	return AvatarCustomizationCatalog.get_variant_color(variant)


static func get_skin_variant(npc_id: String) -> String:
	return str((DEFINITIONS.get(npc_id, {}) as Dictionary).get("skin_variant", ""))


static func get_skin_emission(npc_id: String) -> float:
	return float((DEFINITIONS.get(npc_id, {}) as Dictionary).get("skin_emission", SKIN_EMISSION))


## 台词集合。返回值是副本，调用方改它不会污染目录。
static func get_lines(npc_id: String) -> Array[String]:
	var lines: Array[String] = []
	for line: Variant in (DEFINITIONS.get(npc_id, {}) as Dictionary).get("lines", []) as Array:
		lines.append(str(line))
	return lines


static func get_line_count(npc_id: String) -> int:
	return ((DEFINITIONS.get(npc_id, {}) as Dictionary).get("lines", []) as Array).size()


## 确定性取句（验收与非随机对话推进都用它）：越界时按环回取，负数从末尾起算。
static func get_line(npc_id: String, index: int) -> String:
	var lines := get_lines(npc_id)
	if lines.is_empty():
		return ""
	return lines[posmod(index, lines.size())]


static func get_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in DEFINITIONS.keys():
		ids.append(str(key))
	return ids
