# -*- coding: utf-8 -*-
"""① `_spawn_loot_items` 加「不散布」开关（默认仍散布，其他调用方一字不变）；
② 开场那把枪用不散布落位 —— 否则它会偏 0.7m，而剧本 `actor.face` 指的是常量点；
③ 真机探针的备弹断言改成「无枪也能入包」+ 源码守卫（探针是 test_mode，自动发放被挡住）。
"""

import sys

D3 = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\Dungeon3D.gd"
TD = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\TowerDescent3D.gd"
PR = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

SIG_OLD = (
    "func _spawn_loot_items(\n"
    "\troom: DungeonRoom3D,\n"
    "\titems: Array[Dictionary],\n"
    "\tworld_position: Vector3,\n"
    "\tpickup_grace_seconds: float = 0.0\n"
    ") -> void:\n"
)
SIG_NEW = (
    "## `spread`：是否按「第几件」做确定性散布（多件掉落才需要，避免叠在一起）。\n"
    "## 单件、且落点要被别处（如剧本的朝向目标点）精确引用时传 `false` ——\n"
    "## 实测散布在 index=0 时是 `(cos0.45, 0, sin0.45) * 0.7` ≈ 偏 0.70m，\n"
    "## 会让「指那个常量点」与「枪实际在哪」对不上（2026-09-22 开场那把枪）。\n"
    "func _spawn_loot_items(\n"
    "\troom: DungeonRoom3D,\n"
    "\titems: Array[Dictionary],\n"
    "\tworld_position: Vector3,\n"
    "\tpickup_grace_seconds: float = 0.0,\n"
    "\tspread := true\n"
    ") -> void:\n"
)

BODY_OLD = (
    "\t\tvar angle := float(index) * 2.1 + 0.45\n"
    "\t\tvar requested_position := (\n"
    "\t\t\tworld_position\n"
    "\t\t\t+ Vector3(cos(angle), 0.0, sin(angle)) * (0.7 + index * 0.18)\n"
    "\t\t)\n"
)
BODY_NEW = (
    "\t\tvar requested_position := world_position\n"
    "\t\tif spread:\n"
    "\t\t\tvar angle := float(index) * 2.1 + 0.45\n"
    "\t\t\trequested_position += Vector3(cos(angle), 0.0, sin(angle)) * (0.7 + index * 0.18)\n"
)

TD_OLD = (
    "\t_spawn_loot_items(\n"
    "\t\troom,\n"
    "\t\titems,\n"
    "\t\t_find_supported_spawn_position(requested, room.global_position)\n"
    "\t)\n"
)
TD_NEW = (
    "\t# `spread = false`：剧本 `actor.face` 的目标点就是这个常量，枪必须**精确**落在它上面\n"
    "\t# （默认散布会让 index=0 那件偏约 0.70m ⇒ 转身时会指偏）。\n"
    "\t_spawn_loot_items(\n"
    "\t\troom,\n"
    "\t\titems,\n"
    "\t\t_find_supported_spawn_position(requested, room.global_position),\n"
    "\t\t0.0,\n"
    "\t\tfalse\n"
    "\t)\n"
)

AMMO_OLD = (
    "\t# ② 备弹照给（与「有没有枪」无关的那份保底）\n"
    "\tvar expected_ammo := int(_tower.call(\"get_guaranteed_loadout_ammo_rounds\"))\n"
    "\tvar actual_ammo := int(_tower.call(\"_get_reserve_ammo_count\"))\n"
    "\t_check(\n"
    "\t\tactual_ammo >= expected_ammo,\n"
    "\t\t\"开场保底备弹 >= %d 发（实际 %d）\" % [expected_ammo, actual_ammo],\n"
    "\t)\n"
    "\t_note(\"I 保底备弹要求 %d 发 / 实际 %d 发\" % [expected_ammo, actual_ammo])\n"
)
AMMO_NEW = (
    "\t# ② 备弹照给。⚠️ 探针是 `test_mode`，真机那条自动发放（`if not test_mode:`）被挡住，\n"
    "\t# 所以这里**显式调一次**发放函数：要验的是「**把枪收回之后**备弹照样能进包」这条关系\n"
    "\t# —— 保底备弹与「有没有枪」必须解耦，否则玩家就变成「有 300 发、但打不出去」。\n"
    "\tvar expected_ammo := int(_tower.call(\"get_guaranteed_loadout_ammo_rounds\"))\n"
    "\tvar ammo_before := int(_tower.call(\"_get_reserve_ammo_count\"))\n"
    "\tvar ammo_added := int(_tower.call(\"_grant_guaranteed_loadout_ammo\"))\n"
    "\tvar ammo_after := int(_tower.call(\"_get_reserve_ammo_count\"))\n"
    "\t_check(\n"
    "\t\tammo_added == expected_ammo and ammo_after == ammo_before + ammo_added,\n"
    "\t\t\"无枪状态下保底备弹 %d 发真的入包（入包 %d 发：%d → %d）\"\n"
    "\t\t% [expected_ammo, ammo_added, ammo_before, ammo_after],\n"
    "\t)\n"
    "\t_note(\"I 保底备弹 = %d 发（显式发放后 %d → %d）\" % [expected_ammo, ammo_before, ammo_after])\n"
    "\t# 源码守卫：这条发放的**唯一**条件必须是「非 test_mode」，不能被「有没有枪」挟持。\n"
    "\tvar d3_source := FileAccess.get_file_as_string(\"res://src/world3d/Dungeon3D.gd\")\n"
    "\t_check(\n"
    "\t\td3_source.contains(\"if not test_mode:\\n\\t\\t_grant_guaranteed_loadout_ammo()\"),\n"
    "\t\t\"保底备弹的发放条件只有『非 test_mode』，与有没有枪无关\",\n"
    "\t)\n"
)


def patch(path: str, subs, label: str) -> None:
    raw = open(path, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE %s: 行尾不纯" % path)
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for old, new, tag in subs:
        if new in text:
            print("%s/%s already" % (label, tag))
            continue
        n = text.count(old)
        if n != 1:
            raise SystemExit("ABORT %s/%s: 锚点命中 %d" % (label, tag, n))
        text = text.replace(old, new)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write %s" % path)
    open(path, "wb").write(data)
    print("%s OK CR=%d LF=%d" % (label, data.count(b"\r"), data.count(b"\n")))


def main() -> int:
    patch(D3, [(SIG_OLD, SIG_NEW, "sig"), (BODY_OLD, BODY_NEW, "body")], "Dungeon3D")
    patch(TD, [(TD_OLD, TD_NEW, "drop")], "TowerDescent3D")
    patch(PR, [(AMMO_OLD, AMMO_NEW, "ammo")], "probe")
    return 0


if __name__ == "__main__":
    sys.exit(main())
