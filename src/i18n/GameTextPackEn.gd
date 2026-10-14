class_name GameTextPackEn
extends RefCounted

## 武器构建链路本地化 — 英文预留包（2026-10-14 建立）
##
## 状态：**预留位，未实装**（meta.ready = false ⇒ 不进入玩家的语言选择，只占结构）。
## 语义：本包条目留空时，查表回退到默认语言包 zh_CN；节点/内容名回退到内部英文 ID。
## 启用步骤（日后）：
##   1. 把 meta.ready 改成 true；
##   2. 按 zh_CN 包同名的键，逐条补 "ui/node_type/slot/stat/rarity/location/node/tag" 文案。
## 不填任何一个键也不会让 UI 变空白 —— 回退链会兜住。

const DATA := {
	"meta": {"label": "EN", "ready": false, "code": "en"},
	"ui": {},
	"node_type": {},
	"slot": {},
	"stat": {},
	"stat_value": {},
	"rarity": {},
	"location": {},
	"node": {},
	"node_prefix": {},
	"tag": {},
	"tag_prefix": {},
}
