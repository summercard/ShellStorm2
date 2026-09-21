class_name BarkCatalog
extends RefCounted
## 短句目录：**角色短句**（走头顶气泡 SpeechBubble3D）与**系统提示**（走屏幕底栏 DialogueUI）
## 的内容来源。
##
## 为什么用目录脚本而不是硬编码在逻辑里：
##   与 MusicCatalog / EliteContentCatalog / BossContentCatalog 同规格，是本工程既有的
##   "内容目录"写法。台词取值集中在**一处**，逻辑侧只认 bark_id，不出现台字面量，
##   后续迁入内容数据库时只替换本文件的取数实现，调用方不动。
##
## 迁移标记：本文件当前是内容表的代码投影，尚未与 xlsx 对表。

const BARK_LAMP_ON := "lamp_on"
const BARK_LAMP_OFF := "lamp_off"
## 系统 / 画外音提示（走屏幕底栏 DialogueUI，不走角色气泡）。
const SYSTEM_BASE_WELCOME := "system_base_welcome"

const BARKS := {
	BARK_LAMP_ON: [
		"灯亮了。这层还有电。",
		"还有电。有电就说明有东西在运转。",
		"谁还在给这座塔供电？",
	],
	BARK_LAMP_OFF: [
		"关了。省点电。",
		"黑暗里，我得靠手电了。",
	],
	SYSTEM_BASE_WELCOME: [
		"欢迎回到基地。",
	],
}


static func has_bark(bark_id: String) -> bool:
	var lines: Array = BARKS.get(bark_id, [])
	return not lines.is_empty()


static func get_lines(bark_id: String) -> Array:
	return (BARKS.get(bark_id, []) as Array).duplicate()


static func get_line_count(bark_id: String) -> int:
	return (BARKS.get(bark_id, []) as Array).size()


## 确定性取句：给验收用，避免随机导致断言不稳定。
static func pick_at(bark_id: String, index: int) -> String:
	var lines: Array = BARKS.get(bark_id, [])
	if lines.is_empty():
		return ""
	return str(lines[posmod(index, lines.size())])


## 随机取句；exclude_index 用于避免连续两次说同一句。
static func pick_random(bark_id: String, rng: RandomNumberGenerator, exclude_index := -1) -> Dictionary:
	var lines: Array = BARKS.get(bark_id, [])
	if lines.is_empty():
		return {"text": "", "index": -1}
	var index := 0
	if lines.size() > 1 and exclude_index >= 0:
		var candidates: Array[int] = []
		for i in range(lines.size()):
			if i != exclude_index:
				candidates.append(i)
		index = candidates[rng.randi_range(0, candidates.size() - 1)]
	else:
		index = rng.randi_range(0, lines.size() - 1)
	return {"text": str(lines[index]), "index": index}
