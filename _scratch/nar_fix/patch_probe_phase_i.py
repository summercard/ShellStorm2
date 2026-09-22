# -*- coding: utf-8 -*-
"""真机探针：删掉临时诊断 + 新增 I 段（开场武装口径）。"""

import re
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

READY_OLD = "\tawait _phase_h_no_room_key_in_peaceful()\n\t_report()\n"
READY_NEW = "\tawait _phase_h_no_room_key_in_peaceful()\n\t_phase_i_opening_loadout()\n\t_report()\n"

REPORT_ANCHOR = "func _report() -> void:\n"

PHASE_I = '''## 开场武装口径（2026-09-22 主人要求）：**身上没有枪、备弹照给、他原本那把枪躺在地上**。
## 三条都必须真机验 —— 它们全都「零报错就能是错的」：
## 收回武器的调用点漏了、地上那把枪指错房间、剧本里的目标点与落位常量各写各的，
## 运行时都只会安静地演成另一个样子。
func _phase_i_opening_loadout() -> void:
\tvar rooms: Variant = _tower.get("_room_by_id")
\tif not (rooms is Dictionary):
\t\t_check(false, "拿不到塔楼房间表（开场武装校验无法进行）")
\t\treturn
\tvar table := rooms as Dictionary
\tvar office := table.get(OPENING_ROOM_ID) as DungeonRoom3D
\t_check(office != null, "有办公室房 %s" % OPENING_ROOM_ID)
\tif office == null:
\t\treturn

\t# ① 身上没有枪
\tvar equipped: Variant = _player.call("get_equipped_weapon_item")
\tvar equipped_empty := equipped is Dictionary and (equipped as Dictionary).is_empty()
\t_check(
\t\tequipped_empty,
\t\t"开场玩家身上没有枪（实际 %s）" % ("空" if equipped_empty else str(equipped)),
\t)

\t# ② 备弹照给（与「有没有枪」无关的那份保底）
\tvar expected_ammo := int(_tower.call("get_guaranteed_loadout_ammo_rounds"))
\tvar actual_ammo := int(_tower.call("_get_reserve_ammo_count"))
\t_check(
\t\tactual_ammo >= expected_ammo,
\t\t"开场保底备弹 >= %d 发（实际 %d）" % [expected_ammo, actual_ammo],
\t)
\t_note("I 保底备弹要求 %d 发 / 实际 %d 发" % [expected_ammo, actual_ammo])

\t# ③ 地上那把枪：在办公室里、靠近东门
\tvar drops: Array = []
\tfor value in get_tree().get_nodes_in_group("ground_loot_3d"):
\t\tvar node := value as Node3D
\t\tif node != null and office.is_ancestor_of(node):
\t\t\tdrops.append(node)
\t_check(drops.size() == 1, "办公室地上正好一件掉落物（实际 %d）" % drops.size())
\tvar door := office.get_door_node("east")
\t_check(door != null, "办公室有东门（通往 floor_01_main_02）")
\tif drops.size() >= 1 and door != null:
\t\tvar gun := drops[0] as Node3D
\t\tvar gun_data: Variant = gun.get("item_data")
\t\tvar gun_type := (
\t\t\tstr((gun_data as Dictionary).get("type", "")) if gun_data is Dictionary else "?"
\t\t)
\t\t_check(gun_type == "weapon", "地上那件是武器（实际 type=%s）" % gun_type)
\t\t_check(
\t\t\toffice.contains_world_position(gun.global_position),
\t\t\t"那把枪落在办公室内部（world=%.1f, %.1f, %.1f）"
\t\t\t% [gun.global_position.x, gun.global_position.y, gun.global_position.z],
\t\t)
\t\tvar to_door := door.global_position - gun.global_position
\t\tto_door.y = 0.0
\t\t_check(
\t\t\tto_door.length() <= 3.0,
\t\t\t"那把枪离东门 <= 3m（实际 %.2fm）" % to_door.length(),
\t\t)
\t\t_note(
\t\t\t"I 地上那把枪 = (%.1f, %.1f, %.1f)，离东门 %.2fm"
\t\t\t% [gun.global_position.x, gun.global_position.y, gun.global_position.z, to_door.length()]
\t\t)

\t# ④ 剧本与常量必须同值（剧本是 JSON、常量在 GDScript，两处写死就必须互相咬住）
\tvar consts: Dictionary = _tower.get_script().get_script_constant_map()
\tvar drop_offset: Variant = consts.get("NEW_GAME_OPENING_DROP_OFFSET", null)
\t_check(drop_offset is Vector3, "塔楼声明了 NEW_GAME_OPENING_DROP_OFFSET（落位常量）")
\tvar wake := NarrativeScript3D.load_from_id(WAKE_ID)
\t_check(wake != null, "剧本 01 可加载（nar_tower_opening_01_wake）")
\tif wake != null:
\t\tvar face_cue: Dictionary = {}
\t\tvar gift_say := ""
\t\tvar gift_at := -1.0
\t\tvar end_at := -1.0
\t\tfor cue in wake.cues:
\t\t\tvar verb := str(cue.get("do", ""))
\t\t\tif verb == "actor.face" and str(cue.get("to_point_room", "")) == OPENING_ROOM_ID:
\t\t\t\tface_cue = cue
\t\t\telif verb == "actor.say" and str(cue.get("text", "")).contains("主人留下的礼物"):
\t\t\t\tgift_say = str(cue.get("text", ""))
\t\t\t\tgift_at = float(cue.get("at", -1.0))
\t\t\telif verb == "flow.end":
\t\t\t\tend_at = float(cue.get("at", -1.0))
\t\t_check(not face_cue.is_empty(), "剧本 01 有「朝办公室里的枪转过去」的 actor.face")
\t\t_check(
\t\t\tgift_say.contains("主人留下的礼物"),
\t\t\t"剧本 01 有「那是主人留下的礼物。。」这句台词",
\t\t)
\t\t_check(
\t\t\tend_at > gift_at >= 0.0,
\t\t\t"剧本 01 是「说完那句才解锁」（台词 %.1fs / flow.end %.1fs）" % [gift_at, end_at],
\t\t)
\t\tif not face_cue.is_empty() and drop_offset is Vector3:
\t\t\tvar raw_off: Variant = face_cue.get("to_point_offset", null)
\t\t\tvar matched := false
\t\t\tvar from_script := Vector3.ZERO
\t\t\tif raw_off is Array and (raw_off as Array).size() == 3:
\t\t\t\tvar arr: Array = raw_off
\t\t\t\tfrom_script = Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
\t\t\t\tmatched = from_script.is_equal_approx(drop_offset as Vector3)
\t\t\t_check(
\t\t\t\tmatched,
\t\t\t\t"剧本 01 的 to_point_offset 与塔楼落位常量同值（剧本 %s / 常量 %s）"
\t\t\t\t% [str(from_script), str(drop_offset)],
\t\t\t)

\t# ⑤ 剧本 02 的台词与系统提示
\tvar zombies := NarrativeScript3D.load_from_id(ZOMBIES_ID)
\t_check(zombies != null, "剧本 02 可加载（nar_tower_opening_02_zombies）")
\tif zombies != null:
\t\tvar hint := ""
\t\tvar line := ""
\t\tfor cue in zombies.cues:
\t\t\tvar verb := str(cue.get("do", ""))
\t\t\tif verb == "ui.hint":
\t\t\t\thint = str(cue.get("text", ""))
\t\t\telif verb == "actor.say":
\t\t\t\tline = str(cue.get("text", ""))
\t\t_check(
\t\t\tline.contains("黑暗中是什么东西"),
\t\t\t"剧本 02 台词是「黑暗中是什么东西！」（实际「%s」）" % line,
\t\t)
\t\t_check(
\t\t\thint.contains("手电") and hint.contains("F"),
\t\t\t"剧本 02 有「按F开启手电」的系统提示（实际「%s」）" % hint,
\t\t)


'''

DIAG_PATTERN = re.compile(r"\t# \[TEMP-DIAG-OFFICE-DOOR\][\s\S]*?\n(?=\tvar meeting := )")


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    changed = False

    # 1) 删掉临时诊断块
    if "[TEMP-DIAG-OFFICE-DOOR]" in text:
        text, n = DIAG_PATTERN.subn("", text)
        if n != 1:
            print("ABORT: 诊断块匹配 %d 次" % n)
            return 3
        changed = True
        print("temp diag removed")

    # 2) 新段
    if "_phase_i_opening_loadout" not in text:
        if text.count(READY_OLD) != 1 or text.count(REPORT_ANCHOR) != 1:
            print("ABORT: ready/report 锚点异常")
            return 4
        text = text.replace(READY_OLD, READY_NEW)
        text = text.replace(REPORT_ANCHOR, PHASE_I + REPORT_ANCHOR)
        changed = True
        print("phase I added")

    if not changed:
        print("NO CHANGE")
        return 0

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 5
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
