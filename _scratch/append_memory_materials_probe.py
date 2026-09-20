# -*- coding: utf-8 -*-
"""补记：probe_safe_room_materials 两个自造缺陷的修复（CRLF，追加式）。"""
import sys

DAILY = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-20.md"

ADD = """
### 追加：顺手修掉 `probe_safe_room_materials.gd` 两个自造缺陷

做上面那轮回归时，批处理在 `probe_safe_room_materials` 卡了 20 分钟不动。查明两个问题（都是本会话上一轮我自己造的）：

1. **它是 `tests/verification/` 里唯一不调用 `get_tree().quit()` 的探针** ⇒ autoload（`GameTimeManager._process`）常驻，
   进程永不结束。它会打 `PROBE_SAFE_ROOM_MATERIALS_DONE`（结果其实是好的），但批处理永远等不到下一行。
   同批补 `await get_tree().process_frame` + `get_tree().quit(0)`，照抄姊妹探针
   `probe_safe_room_facility_collision.gd` 的收尾写法。
2. **它硬编码了第三份房间包清单**（`const PACKAGE_IDS`，17 件、含已移除的 `central_terminal_island` /
   `west_glass_office`），删件后漂移成 17 vs 15。改为运行时取 `DungeonRoom3D.SAFE_ROOM_PACKAGE_IDS`
   （唯一真源），打印标签也改成 `%d` 动态推导。
   ⚠️ 于是「房间包清单」目前有 **3 个消费点**：`DungeonRoom3D.gd`（真源）· `probe_safe_room_v007_integration.gd`（副本）·
   本探针（**已改回引用真源**）。增删包时前两处要同批改。

修后复验：`exit 0 / ERROR 0 / PROBE_SAFE_ROOM_MATERIALS_DONE`，标签 `房间包 15 件`，
汇总 `packages=15 surfaces=88 surface_material_null=0 albedo_null=0 albedo_palette=88 emissive_multiply=88`。
（`albedo_palette` 由 96 降到 88 = 少了被移除那两件的 8 个面，符合预期。）
"""


def main():
    with open(DAILY, "rb") as fh:
        data = fh.read()
    eol = b"\r\n" if data.count(b"\r\n") > 0 else b"\n"
    if not data.endswith(eol):
        data += eol
    data += ADD.encode("utf-8").replace(b"\n", eol)
    with open(DAILY, "wb") as fh:
        fh.write(data)
    print("APPENDED %s" % DAILY)
    return 0


if __name__ == "__main__":
    sys.exit(main())
