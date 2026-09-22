# -*- coding: utf-8 -*-
"""新游戏开场：收回玩家的枪 + 把那把枪放到办公室东门内侧右手边。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\TowerDescent3D.gd"

CONST_ANCHOR = "const NEW_GAME_OPENING_SPAWN_OFFSET := Vector3(0.0, 0.05, 0.0)\n"
CONST_ADD = '''
## —— 新游戏开场的武装口径（2026-09-22 主人要求）——
## 玩家**开局身上没有枪**，但**保底备弹照给**（300 发由 `GUARANTEED_LOADOUT_AMMO_ROUNDS`
## 独立发放，与「有没有枪」无关，所以收回武器碰不到它）。他原本那把枪**放在地上**，
## 就在办公室东门内侧靠右手边 —— 起身走过去捡起来，正好是自己该有的那把。
##
## 落点是**房间局部系**偏移（房间节点原点 = 房中心，见 `DungeonRoom3D` 的 ±dimensions/2 约定）。
## 2026-09-22 真机实测：办公室局部尺寸 (15, 20)、东门在局部 **(7.5, 0, -2.5)**，
## 所以本值 = 「离门 2.2m、出门方向（+x）的右手侧 1.8m」（朝 +x 时右手 = +z）。
## ⚠️ 剧本 `nar_tower_opening_01_wake` 里 `actor.face` 的 `to_point_offset` 必须是**同一个值**
## （「对着枪说」得朝它转）；真机验收有**等值断言**，改一处漏一处会变红。
const NEW_GAME_OPENING_DROP_OFFSET := Vector3(5.3, 0.05, -0.7)
'''

CALL_ANCHOR = (
    "\tplayer.global_position = room.global_position + NEW_GAME_OPENING_SPAWN_OFFSET\n"
    "\tplayer.velocity = Vector3.ZERO\n"
    "\t_current_room_id = \"\"\n"
    "\t_on_room_entered(room)\n"
    "\treturn true\n"
)
CALL_NEW = (
    "\tplayer.global_position = room.global_position + NEW_GAME_OPENING_SPAWN_OFFSET\n"
    "\tplayer.velocity = Vector3.ZERO\n"
    "\t_current_room_id = \"\"\n"
    "\t_on_room_entered(room)\n"
    "\t_reset_new_game_opening_loadout(room)\n"
    "\treturn true\n"
)

FUNCS_ANCHOR = "func _process(delta: float) -> void:\n"
FUNCS = '''## 新游戏开场的武装口径：**收回玩家的枪 → 把那把枪放到地上**。
## 为什么是「收回」而不是改 `Player3D.start_with_weapon` 的默认值：
## 那条 export 同时服务天台出生 / 死亡返城 / 死亡返城直升等路径，那些路径仍然要白送枪；
## 而且 `Player3D._ready()`（子节点先于塔楼 `_ready()`）早就把枪装好了，
## 到了开场落位这一步只剩「收回来」这一条路。
## ⚠️ 收回用的是 `clear_all_equipped_weapons()` 的**返回值**（= 玩家那一把的原样实例，
## 含已装的命运改造），不是重新造一把 —— 主人要的是「他原本那把枪」躺在地上。
func _reset_new_game_opening_loadout(room: DungeonRoom3D) -> void:
	if player == null or not player.has_method("clear_all_equipped_weapons"):
		push_warning("[TowerDescent3D] 开场收回武器失败：玩家没有 clear_all_equipped_weapons()")
		return
	var removed: Array = player.call("clear_all_equipped_weapons")
	if removed.is_empty():
		# 不静默：地上没枪 = 开场演到「对着枪说」却无枪可指，必须留痕。
		push_warning("[TowerDescent3D] 开场玩家身上本来就没有枪，地上那把不会生成。")
		return
	var items: Array[Dictionary] = []
	for value in removed:
		if value is Dictionary:
			items.append(value as Dictionary)
	_drop_new_game_opening_weapon(room, items)


func _drop_new_game_opening_weapon(room: DungeonRoom3D, items: Array[Dictionary]) -> void:
	if room == null or not is_instance_valid(room) or items.is_empty():
		return
	var requested := room.to_global(NEW_GAME_OPENING_DROP_OFFSET)
	# 与钥匙/补给同一套贴地口径：拿不到地面就退回房中心，绝不把枪埋进地板里。
	_spawn_loot_items(
		room,
		items,
		_find_supported_spawn_position(requested, room.global_position)
	)


'''

DOC_OLD = "## 把玩家放进 98F 主人的办公室，并走一次完整的「进入房间」事务\n"
DOC_NEW = (
    "## 把玩家放进 98F 主人的办公室，并走一次完整的「进入房间」事务\n"
    "## 落位后立刻按开场口径重武装：收回身上的枪并把那把枪放到地上（见\n"
    "## `_reset_new_game_opening_loadout`）。\n"
)


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "NEW_GAME_OPENING_DROP_OFFSET" in text:
        print("ALREADY PATCHED")
        return 0

    for anchor, label in ((CONST_ANCHOR, "const"), (CALL_ANCHOR, "call"), (FUNCS_ANCHOR, "funcs"), (DOC_OLD, "doc")):
        n = text.count(anchor)
        if n != 1:
            print("ABORT %s: 锚点命中 %d" % (label, n))
            return 3

    text = text.replace(CONST_ANCHOR, CONST_ANCHOR + CONST_ADD)
    text = text.replace(CALL_ANCHOR, CALL_NEW)
    # 新函数插在 _process 之前（紧跟在 _place_player_at_new_game_opening 之后）。
    text = text.replace(FUNCS_ANCHOR, FUNCS + FUNCS_ANCHOR)
    text = text.replace(DOC_OLD, DOC_NEW)

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
