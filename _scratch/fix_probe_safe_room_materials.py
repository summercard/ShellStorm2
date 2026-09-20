# -*- coding: utf-8 -*-
"""修 probe_safe_room_materials.gd 两个自造缺陷（CRLF 字节级）：
1) 删掉第三份硬编码包清单（17 件抄本，删件后漂移）→ 改从 DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS 取；
2) 补 get_tree().quit() —— 它曾是全 tests/verification/ 里唯一不退出、把批处理挂住的探针。
"""
import sys

P = ("tests/verification/probe_safe_room_materials.gd")

OLD_HEADER = (
    "## 对照组 = common_components 四件套（已知 import_script 绑定正确）。\n"
)
NEW_HEADER = (
    "## 对照组 = common_components 四件套（已知 import_script 绑定正确）。\n"
    "## 2026-09-20：包清单改从 `DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS` 动态取 ——\n"
    "## 原先是第三份硬编码副本（按 17 件抄的，删件后漂移到 17 vs 15）。\n"
    "## 同批补 `get_tree().quit()`：此前它曾是 `tests/verification/` 里唯一不退出、\n"
    "## 会把批量回归挂住的探针（autoload 常驻，进程永不结束）。\n"
)

OLD_CONST = (
    'const PACKAGE_IDS: Array[String] = [\n'
    '\t"floor_base",\n'
    '\t"overhead_services",\n'
    '\t"debris_papers",\n'
    '\t"central_terminal_island",\n'
    '\t"north_server_00",\n'
    '\t"north_server_01",\n'
    '\t"north_server_02",\n'
    '\t"north_server_03",\n'
    '\t"north_server_04",\n'
    '\t"north_server_05",\n'
    '\t"north_broken_core",\n'
    '\t"north_nexus_sign",\n'
    '\t"west_glass_office",\n'
    '\t"east_repair_bay",\n'
    '\t"east_robot_arm",\n'
    '\t"office_planter",\n'
    '\t"maintenance_chair",\n'
    ']\n'
)

OLD_LOOP = (
    '\tprint("")\n'
    '\tprint("=== 房间包 17 件（runtime/entry_safe_room/*）===")\n'
    '\tfor package_id in PACKAGE_IDS:\n'
)
NEW_LOOP = (
    '\tvar package_ids: Array[String] = DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS\n'
    '\tprint("")\n'
    '\tprint("=== 房间包 %d 件（runtime/entry_safe_room/*；真源 DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS）===" % package_ids.size())\n'
    '\tfor package_id in package_ids:\n'
)

OLD_TAIL = (
    '\tprint("")\n'
    '\tprint("PROBE_SAFE_ROOM_MATERIALS_DONE")\n'
)
NEW_TAIL = (
    '\tprint("")\n'
    '\tprint("PROBE_SAFE_ROOM_MATERIALS_DONE")\n'
    '\tawait get_tree().process_frame\n'
    '\tget_tree().quit(0)\n'
)

PAIRS = [(OLD_HEADER, NEW_HEADER, "文件头说明"),
         (OLD_CONST, "", "删除硬编码包清单"),
         (OLD_LOOP, NEW_LOOP, "包循环改为动态取"),
         (OLD_TAIL, NEW_TAIL, "补退出")]


def main():
    with open(P, "rb") as fh:
        data = fh.read()
    eol = b"\r\n" if data.count(b"\r\n") > 0 else b"\n"
    for old, new, label in PAIRS:
        ob = old.encode("utf-8").replace(b"\n", eol)
        nb = new.encode("utf-8").replace(b"\n", eol)
        n = data.count(ob)
        if n != 1:
            print("!! %s 命中 %d 次" % (label, n))
            return 1
        data = data.replace(ob, nb)
        print("OK %s" % label)
    with open(P, "wb") as fh:
        fh.write(data)
    print("PATCHED %s" % P)
    return 0


if __name__ == "__main__":
    sys.exit(main())
