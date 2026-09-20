# -*- coding: utf-8 -*-
"""给《安全房运行时内容清单》补两段：连带修复记录 + 外部复用点（CRLF 字节级）。"""
import sys

DOC = ("docs/v0.1/development/2026-09-17_安全房运行时内容清单.md")

ANCHOR_LOG = (">   省略则该节点在实例化时静默消失（引擎只报一条 `has vanished` 警告），碰撞等于没加。\n")

ADD_LOG = (
    "> - 2026-09-20：修复被上一条**连带打红**的 `verify_battle_wall_floor_facility_kit`。\n"
    ">   `wall_floor_facility_kit_root_top3d.tscn` 复用 `north_server_00` / `north_server_01` 当墙边装饰，\n"
    ">   设施带上内嵌碰撞后，kit 里那两个实例的 `collision_shape_count` 从 0 变 1，撞破了该场景\n"
    ">   「设施必须为 0」的写死断言。kit 的声明与断言一并改为「声明值 == 实际启用形数」的一致性检查，\n"
    ">   kit 版本 `v001` → `v002`。\n"
    ">   ⚠️ 该场景失败时日志前半段是 8 条 `ERROR`（其实是断言提前 return、`root.free()` 没执行而连带泄漏的\n"
    ">   资源），**别把这些 ERROR 当噪声放过** —— 真正的失败标记是 `FACILITY_*`。\n"
)

ANCHOR_REUSE = "  （新增包不同步表态即红）。\n"

ADD_REUSE = (
    "\n"
    "**外部复用点（改房间包会牵连，必须连带跑）**：\n"
    "`assets/art/environments/tower_zones/battle/runtime/wall_floor_facility_kit/wall_floor_facility_kit_root_top3d.tscn`\n"
    "把 `north_server_00` / `north_server_01` / `central_terminal_island` 三件当墙边装饰实例化。\n"
    "前两件带上内嵌碰撞后，kit 实例跟着带 —— 所以 kit 的自检**不能**写死「设施 `collision_shape_count == 0`」，\n"
    "只能断言「声明 == 实际」。改动任一房间包后，必须连带跑\n"
    "`tests/verification/verify_battle_wall_floor_facility_kit.tscn`。\n"
)


def main():
    with open(DOC, "rb") as fh:
        data = fh.read()
    eol = b"\r\n" if data.count(b"\r\n") > 0 else b"\n"
    for anchor, add, label in ((ANCHOR_LOG, ADD_LOG, "变更记录"),
                               (ANCHOR_REUSE, ADD_REUSE, "外部复用点")):
        ab = anchor.encode("utf-8").replace(b"\n", eol)
        nb = (anchor + add).encode("utf-8").replace(b"\n", eol)
        n = data.count(ab)
        if n != 1:
            print("!! %s 锚点命中 %d 次" % (label, n))
            return 1
        data = data.replace(ab, nb)
        print("OK 插入 %s" % label)
    with open(DOC, "wb") as fh:
        fh.write(data)
    print("DOC PATCHED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
