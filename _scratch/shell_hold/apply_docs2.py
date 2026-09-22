# -*- coding: utf-8 -*-
"""14.6 §10 版本表补 v002.7 行（CHANGELOG 已在上一步写入）。CRLF 二进制改写。"""
import os
import sys

SPEC = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\14.6_特效系统与制作规范.md"

SPEC_ROW = """| 2026-09-22 | v002.7 | 弹壳**停留时长 +1.5 秒**（业主指定：「弹壳的停留时长加 1.5 秒」）。**口径**：弹壳可见时长即 `VfxShellCasing3D.DEFAULT_LIFETIME`；飞行 / 弹跳 / 滚动三段时长由物理常量与初速度决定、**不随寿命变化** ⇒ 寿命增加部分**全部落在落地静止后的停留**上，故诉求等价于 `DEFAULT_LIFETIME: 3.2 → 4.7`。实测（验收按 `1/60 s` 步进求静止时刻）`t_settle = 1.15 s`、停留 `4.70 − 1.15 = 3.55 s`（v002.2 起为 `2.05 s`）。**验收**：`verify_combat_vfx_toon_v002` 新增 `_check_shell_settled_hold()`（`samples=15 → 16`），三条互补断言（寿命定档值 / 增量 = 上一版 + 1.5 / 实测静止后停留 ≥ 1.5 s），期望值硬编码为外部真源且**刻意不写成派生式**（防自我印证）。**反向对照 RC8**：寿命退回 3.2 ⇒ 精准 3 红后还原复绿；其中「停留 ≥ 1.5 s」在退回时仍成立（`2.05 s`），它是**下限守卫**，「+1.5」由常量与增量两条钉住。**成本核算**：`VfxPool3D` 对 active 无上限（`max_per_kind` 只管 inactive 桶）⇒ 射速 `1.0 ~ 12.0 发/s` × `4.7 s` 最坏同屏约 `56` 枚（上一版约 `38` 枚），每枚 3 件 / 288 三角面 ⇒ 约 `16k` 三角面、约 `170` 次绘制，未做池化改动。AssetID / Prefab / 版本 `v001` / PBR / 尺寸 / 随机化口径 / `floor_y` 契约均未动，账本无需改动 |"""

OLD = "，未随机化时实测仅 `0.0114 m`）|\n\n---\n"
NEW = "，未随机化时实测仅 `0.0114 m`）|\n" + SPEC_ROW + "\n---\n"


def crlf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\n", "\r\n")


data = open(SPEC, "rb").read()
o = crlf(OLD).encode("utf-8")
n = crlf(NEW).encode("utf-8")
found = data.count(o)
if found != 1:
    print("FAIL 14.6 锚点命中 %d 处（期望 1）" % found)
    sys.exit(1)
open(SPEC, "wb").write(data.replace(o, n))
chk = open(SPEC, "rb").read()
print("OK   14.6 v002.7 行  crcrlf=%d lone_lf=%d" % (chk.count(b"\r\r\n"), chk.count(b"\n") - chk.count(b"\r\n")))
