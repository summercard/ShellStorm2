# -*- coding: utf-8 -*-
"""回写弹壳停留时长 +1.5s 的文档（CHANGELOG + 14.6 §10 版本表）。CRLF 二进制改写。"""
import os
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
CHANGELOG = os.path.join(ROOT, "docs", "v0.1", "development", "CHANGELOG.md")
SPEC = os.path.join(ROOT, "docs", "v0.1", "14.6_特效系统与制作规范.md")


def crlf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\n", "\r\n")


def patch(path: str, old: str, new: str, label: str) -> bool:
    data = open(path, "rb").read()
    o = crlf(old).encode("utf-8")
    n = crlf(new).encode("utf-8")
    found = data.count(o)
    if found != 1:
        print("FAIL %s 命中 %d 处（期望 1）" % (label, found))
        return False
    open(path, "wb").write(data.replace(o, n))
    chk = open(path, "rb").read()
    print("OK   %-24s crcrlf=%d lone_lf=%d" % (label, chk.count(b"\r\r\r\n".replace(b"\r\r\r", b"\r\r")) , chk.count(b"\n") - chk.count(b"\r\n")))
    return True


SECTION = """## 2026-09-22｜弹壳停留时长 +1.5 秒（3.2s → 4.7s）

**动机（业主指定）**：「弹壳的停留时长加 1.5 秒。」

**口径**：弹壳可见时长 = `VfxShellCasing3D.DEFAULT_LIFETIME`。其中飞行 / 弹跳 / 滚动三段的时长由物理常量与初速度决定、**不随寿命变化** ⇒ 寿命增加的部分**全部落在「落地静止后的停留」上**，故本诉求等价于「寿命 `3.2 → 4.7`」。实测（验收按 `1/60 s` 步进求静止时刻）：`t_settle = 1.15 s`、停留 `4.70 − 1.15 = 3.55 s`（上一版 `3.20 − 1.15 = 2.05 s`）。

**改动（单点）**：
- `src/vfx/VfxShellCasing3D.gd`：`DEFAULT_LIFETIME := 3.2 → 4.7`。
- `tests/verification/verify_combat_vfx_toon_v002.gd`：新增 `_check_shell_settled_hold()`（`samples=15 → 16`）与三个外部真源常量 `EXPECTED_SHELL_LIFETIME_PREVIOUS := 3.2` / `EXPECTED_SHELL_SETTLED_HOLD_DELTA := 1.5` / `EXPECTED_SHELL_LIFETIME := 4.7`（**刻意各自硬编码、不写成派生式** `3.2 + 1.5` —— 派生式会让改坏一处时三处一起跟随，断言自我印证）。

**三条互补断言**：① 寿命 = 定档值（外部真源硬编码，不引用被测常量）；② 增量 = 上一版 `3.2` + `1.5`（**业主诉求本身**的常量级钉子）；③ 行为级 —— 实测静止时刻后剩余停留 `≥ 1.5 s`（挡住「有人把初速度调大到飞行段吃掉这 1.5 s」这类隐形退化：那时 ①② 仍绿、只有 ③ 会红）。用例强制使用**新实例**（主用例那枚已被推进到 `1.94 s` 且早已 `SETTLED`，复用会让 `t_settle` 恒取第一个步长而失效），并带「未测到静止时刻」的防假绿哨兵。

**反向对照 RC8**：`DEFAULT_LIFETIME` 退回 `3.2` ⇒ **精准 3 红**（`弹壳寿命不是定档值 4.70：3.200`、`弹壳实例寿命未按 DEFAULT_LIFETIME 初始化：3.200（检查 _ready）`、`弹壳停留增量不是 1.5s：寿命 3.20 − 上一版 3.20 = 0.00`），其余断言全绿、`EXIT=1`；还原后 `EXIT=0` 复绿。**如实说明**：③ 在退回 `3.2` 时仍为真（`hold = 2.05 ≥ 1.5`）—— 它是**下限守卫**，「+1.5」这条诉求由 ①② 钉住，不是 ③。

**成本（如实核算，未做池化改动）**：`VfxPool3D` 对 **active 实例无上限**（`max_per_kind = 32` 只管 **inactive 回收桶**，见 `VfxPool3D.retire()`）⇒ 拉长寿命直接抬高同屏存活弹壳数：射速 `1.0 ~ 12.0 发/s`（`BlueprintRegistry` 全体枪械）× `4.7 s` ⇒ 最坏同屏约 `56` 枚（上一版约 `38` 枚，`+47%`）。每枚 `3` 个 `MeshInstance3D`、`288` 三角面（圆柱 `48` + 圆环 `192` + 球 `48`）⇒ 约 `16k` 三角面、约 `170` 次绘制，远低于预算。

**未变更**：AssetID `VFX-SHELL-CASING-3D`、Prefab 路径与根节点版本 `v001`、PBR 定档（`0.8 / 0.6`）、尺寸基准（`0.8`）、抛壳随机化幅度、`floor_y` 契约与「不接物理引擎」口径均未动 ⇒ **账本无需改动**。真渲染探针四个机位沿用不动（其步进按**绝对秒数**驱动、寿命经 `shell.lifetime` 动态读取，寿命变化不影响取景与判据）。
"""

SPEC_ROW = """| 2026-09-22 | v002.7 | 弹壳**停留时长 +1.5 秒**（业主指定：「弹壳的停留时长加 1.5 秒」）。**口径**：弹壳可见时长即 `VfxShellCasing3D.DEFAULT_LIFETIME`；飞行 / 弹跳 / 滚动三段时长由物理常量与初速度决定、**不随寿命变化** ⇒ 寿命增加部分**全部落在落地静止后的停留**上，故诉求等价于 `DEFAULT_LIFETIME: 3.2 → 4.7`。实测（验收按 `1/60 s` 步进求静止时刻）`t_settle = 1.15 s`、停留 `4.70 − 1.15 = 3.55 s`（v002.2 起为 `2.05 s`）。**验收**：`verify_combat_vfx_toon_v002` 新增 `_check_shell_settled_hold()`（`samples=15 → 16`），三条互补断言（寿命定档值 / 增量 = 上一版 + 1.5 / 实测静止后停留 ≥ 1.5 s），期望值硬编码为外部真源且**刻意不写成派生式**（防自我印证）。**反向对照 RC8**：寿命退回 3.2 ⇒ 精准 3 红后还原复绿；其中「停留 ≥ 1.5 s」在退回时仍成立（`2.05 s`），它是**下限守卫**，「+1.5」由常量与增量两条钉住。**成本核算**：`VfxPool3D` 对 active 无上限（`max_per_kind` 只管 inactive 桶）⇒ 射速 `1.0 ~ 12.0 发/s` × `4.7 s` 最坏同屏约 `56` 枚（上一版约 `38` 枚），每枚 3 件 / 288 三角面 ⇒ 约 `16k` 三角面、约 `170` 次绘制，未做池化改动。AssetID / Prefab / 版本 `v001` / PBR / 尺寸 / 随机化口径 / `floor_y` 契约均未动，账本无需改动 |
"""

ok = True

ok &= patch(
    CHANGELOG,
    "# 游戏设计文档 v0.1 变更记录\n\n## 2026-09-22｜保底武装配套备弹 60 发 → 300 发\n",
    "# 游戏设计文档 v0.1 变更记录\n\n" + SECTION + "\n<br>\n## 2026-09-22｜保底武装配套备弹 60 发 → 300 发\n",
    "CHANGELOG 顶部新节",
)

ok &= patch(
    SPEC,
    "（未随机化时实测仅 `0.0114 m`）|\n\n---\n",
    "（未随机化时实测仅 `0.0114 m`）|\n" + SPEC_ROW + "\n---\n",
    "14.6 §10 v002.7 行",
)

sys.exit(0 if ok else 1)
