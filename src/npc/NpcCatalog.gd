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

# —— 剧情节拍（一次性迎宾） ——
#
# 与 `lines` 的分工：`lines` 是**随时可聊**的循环台词；`story_beats` 是**只播一次**的
# 剧情节点，由游戏事实触发（见 `NpcStoryBeatService`）。两者不共用进度：
# 节拍播完不改变循环台词的句序，玩家之后按 E 仍然从「你回来了」开始。
#
# 判定与落盘都不在本文件（内容目录只管"说什么、靠什么事实成立"）：
#   - 需要的事实 → `requires_*` 字段，由 `NpcStoryBeatService` 逐条求值；
#   - 是否已经播过 → `NpcStoryBeatService` 写 `BaseManager` 的跨局节拍历史。
const BEAT_ELITE_ARMS_TAKER_FIRST_SEEN := "elite_arms_taker_first_seen"

## npc_id → { beat_id → 节拍定义 }
##
## 节拍定义字段：
##   `requires_elite_encountered`：必须已经**确认遭遇过**这只精英（`EliteRosterService`
##       的 `encounter_count > 0`）。不是"预约过"——预约只代表这局抽到了它。
##   `archive_facility_id`：台词里指路的设施稳定 ID。登记它是为了让验收能断言
##       "NPC 让你去看的那个终端真的存在、真的在二楼"，而不是一句无法核对的话。
##   `lines`：连续台词，**按顺序轮播**，每句一个气泡。合并不成一整块，理由见下：
##
## 为什么是轮播而不是合成一大段：气泡挂高 3.40m 是按**两行**（世界高 1.21m）定的口径
## （业主三轮调出来的，见 `NpcCharacter3D.HEAD_TOP_HEIGHT` 一带的注释）。40 个字的整句
## 在 `wrap_width_px 560`（≈11 汉字/行）下会排成 4 行、世界高 1.81m，顶边顶到画面上缘
## 被裁掉（2026-11-04 真实渲染实测）。拆成两句各 20 字 ⇒ 各两行，挂高口径不变，
## 观感仍是"迎上来一口气说两句"。
const STORY_BEATS := {
	NPC_BASE99_GREEN: {
		BEAT_ELITE_ARMS_TAKER_FIRST_SEEN: {
			"requires_elite_encountered": "elite_arms_taker",
			"archive_facility_id": "monster_archive",
			"lines": [
				"你遇到收租人啦？有没有被夺走东西呀？",
				"你可以去二楼的档案室里看看它的信息哦。",
			],
		},
	},
}

# —— 战败归航救援台词（2026-11-08 业主原话） ——
#
# 为什么不放进 `STORY_BEATS`：`STORY_BEATS` 的语义是「跨存档只播一次」，
# 而这段是**每次战败归航都要播**。放进去会被 `_session_played` 与
# `npc_beat:` 历史压住，第二次战败就变成哑巴。
#
# 内容仍然只存在本文件：演出方（`Base99Rescue3D`）不写任何台词字面量。
# 拆句口径见 `NpcCharacter3D.BUBBLE_WRAP_PX`：两句各占一个气泡，
# 第二句较长，由演出方临时放宽换行宽度让它仍是两行（不抬高气泡、不改字号）。
const RESCUE_LINES := {
	NPC_BASE99_GREEN: [
		"啧啧，太危险了，看我把你捞回来了。",
		"感谢我吧，我还帮你捞回了点东西，下次去可要小心了。",
	],
}

## 连败专属台词：键 = 连续战败次数。
##
## 业主 2026-11-08：「对话可以多做几套」，并给了三档语气：
##   2 次 —— 开始拿你打趣；3 次 —— 已经无话可说；其余次数走随机池。
##
## 放在这里而不是写进 `Base99Rescue3D`：台词只有一处来源（与 `STORY_BEATS` 同规格），
## 演出方只认「第几次」这个整数，换文案不动代码。
const RESCUE_STREAK_LINES := {
	2: [
		"看见那只僵尸了吗？接下来换你咬它了！",
		"但是你首先得先长上牙齿，啧啧。",
	],
	3: [
		"…………，你……",
	],
}

## 其余次数的随机池（业主原话三条）。1 次与 4 次以上都从这里抽一句，
## 不至于让玩家第 5 次死亡还听同一句。
const RESCUE_POOL_LINES := [
	"别泄气，这点小问题难不住你。",
	"世上无难事，只要肯攀登，以前一个很伟大的人说的。",
	"这次还不错，零件一个没少。",
]


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


# —— 剧情节拍 ——

## 该 NPC 的全部节拍 ID。顺序即定义顺序（同一 NPC 多个节拍时按书写次序求值）。
static func get_story_beat_ids(npc_id: String) -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in (STORY_BEATS.get(npc_id, {}) as Dictionary).keys():
		ids.append(str(key))
	return ids


## 单条节拍定义（副本）。不存在时返回空字典，不抛错 —— 节拍缺失只该"少说一句"。
static func get_story_beat(npc_id: String, beat_id: String) -> Dictionary:
	var beats := STORY_BEATS.get(npc_id, {}) as Dictionary
	return (beats.get(beat_id, {}) as Dictionary).duplicate(true)


## 节拍台词：**按顺序**返回每句（每句一个气泡，由实体依次播）。
## 需要"整段当作一个字符串"的调用方（日志、剧情文本、验收比对）用 `get_story_beat_full_text()`。
static func get_story_beat_lines(npc_id: String, beat_id: String) -> Array[String]:
	var lines: Array[String] = []
	for line: Variant in (get_story_beat(npc_id, beat_id).get("lines", []) as Array):
		var text := str(line).strip_edges()
		if not text.is_empty():
			lines.append(text)
	return lines


## 节拍全文（逐句首尾相接）。用于日志、剧情文本与"台词是否被悄悄改过"的比对。
static func get_story_beat_full_text(npc_id: String, beat_id: String) -> String:
	return "".join(get_story_beat_lines(npc_id, beat_id))


## 兼容旧调用：等于全文。
static func get_story_beat_text(npc_id: String, beat_id: String) -> String:
	return get_story_beat_full_text(npc_id, beat_id)


static func get_story_beat_requirement(npc_id: String, beat_id: String) -> String:
	return str(get_story_beat(npc_id, beat_id).get("requires_elite_encountered", ""))


static func get_story_beat_archive_facility(npc_id: String, beat_id: String) -> String:
	return str(get_story_beat(npc_id, beat_id).get("archive_facility_id", ""))


# —— 战败归航救援台词 ——

## 该 NPC 的战败救援台词（逐句，每句一个气泡）。没登记 ⇒ 空数组（演出方跳过演出）。
static func get_rescue_lines(npc_id: String) -> Array[String]:
	var lines: Array[String] = []
	for line: Variant in (RESCUE_LINES.get(npc_id, []) as Array):
		var text := str(line).strip_edges()
		if not text.is_empty():
			lines.append(text)
	return lines


## 救援台词全文（逐句首尾相接）。用于日志与"台词被悄悄改过"的比对。
static func get_rescue_full_text(npc_id: String) -> String:
	return "".join(get_rescue_lines(npc_id))


## 按**连续战败次数**挑这段演出额外要说的话（0 句=不说 / 1–2 句=追加在固定两句之后）。
##
## `pick_index >= 0` 时从随机池确定性取第几条（验收用）；缺省 -1 = 真随机。
## 随机池只在本函数里取，实体与演出方都不掷骰 —— 与 `BarkCatalog.pick_random` 同口径。
static func get_rescue_streak_lines(
	npc_id: String, streak: int, pick_index := -1
) -> Array[String]:
	var lines: Array[String] = []
	var streak_value := maxi(0, streak)
	var fixed := RESCUE_STREAK_LINES.get(streak_value, []) as Array
	if not fixed.is_empty():
		for line: Variant in fixed:
			var text := str(line).strip_edges()
			if not text.is_empty():
				lines.append(text)
		return lines
	# 1 次与 4 次以上共用一个池子：不把"没专门写过"的档位变成沉默。
	var pool := get_rescue_pool_lines(npc_id)
	if pool.is_empty():
		return lines
	var index := pick_index if pick_index >= 0 else randi() % pool.size()
	lines.append(pool[posmod(index, pool.size())])
	return lines


## 随机池原文（逐条，供验收比对与调试）。空数组 = 该 NPC 没有随机池。
static func get_rescue_pool_lines(_npc_id: String) -> Array[String]:
	var lines: Array[String] = []
	for line: Variant in RESCUE_POOL_LINES:
		var text := str(line).strip_edges()
		if not text.is_empty():
			lines.append(text)
	return lines
