# -*- coding: utf-8 -*-
"""回写「弹壳停留时长再缩短 1 秒」（CHANGELOG 顶部新节 + 14.6 §10 v002.8 行）。CRLF 二进制改写。"""
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
CHANGELOG = ROOT + r"\docs\v0.1\development\CHANGELOG.md"
SPEC = ROOT + r"\docs\v0.1\14.6_特效系统与制作规范.md"

FAILS = []


def crlf(t: str) -> str:
    return t.replace("\r\n", "\n").replace("\n", "\r\n")


def patch(path, old, new, label):
    data = open(path, "rb").read()
    o = crlf(old).encode("utf-8")
    n = crlf(new).encode("utf-8")
    found = data.count(o)
    if found != 1:
        print("FAIL %-28s 命中 %d 处（期望 1）" % (label, found))
        FAILS.append(label)
        return
    open(path, "wb").write(data.replace(o, n))
    chk = open(path, "rb").read()
    print("OK   %-28s crcrlf=%d lone_lf=%d" % (label, chk.count(b"\r\r\r\n".replace(b"\r\r\r", b"\r\r")), chk.count(b"\n") - chk.count(b"\r\n")))


SECTION = """## 2026-09-22｜弹壳停留时长再缩短 1 秒（4.7s → 3.7s）

**动机（业主指定）**：「弹壳的停留时长（再）缩短 1 秒。」—— 在上一版「+1.5 秒」的基础上回调 1 秒。

**口径**：弹壳可见时长 = `VfxShellCasing3D.DEFAULT_LIFETIME`；飞行 / 弹跳 / 滚动三段时长由物理常量与初速度决定、**不随寿命变化** ⇒ 寿命增减的部分**全部落在「落地静止后的停留」上**，故「缩短 1 秒」等价于 `DEFAULT_LIFETIME: 4.7 → 3.7`（累计：`3.2 →（+1.5）4.7 →（−1.0）3.7`）。实测（验收按 `1/60 s` 步进求静止时刻）：`t_settle = 1.15 s`、停留 `3.70 − 1.15 = 2.55 s`（上一版 `3.55 s`）。

**改动（单点）**：
- `src/vfx/VfxShellCasing3D.gd`：`DEFAULT_LIFETIME := 4.7 → 3.7`（注释块补两轮定档沿革与新的成本对照）。
- `tests/verification/verify_combat_vfx_toon_v002.gd`：`_check_shell_settled_hold()` 的常量组按「上一版 / 本轮缩短量 / 定档值」重排为 `EXPECTED_SHELL_LIFETIME_PREVIOUS := 4.7` / `EXPECTED_SHELL_DWELL_SHORTEN := 1.0` / `EXPECTED_SHELL_LIFETIME := 3.7`，并把原先被当作「增量」使用的那个数**独立成 `EXPECTED_SHELL_HOLD_FLOOR := 1.5`**（观感下限）。`samples=16` 不变。

**断言结构（本轮的重要修正）**：上一版把「停留 ≥ 1.5 s」这条行为断言写在了「增量」常量的前提上 —— 数值上恰好相等，但语义是错的（增量是 ±N 的**需求量**，下限是**可感知门槛**，两者碰巧都是 1.5）。本轮把两者拆成独立常量，并在注释里写明各自守什么：
- ① `lifetime == 3.7` —— 定档值（外部真源）；
- ② `4.7 − lifetime == 1.0` —— **本轮缩短量**（业主诉求本身；换方向时减号语义要同步翻）；
- ③ `lifetime − t_settle ≥ 1.5` —— **下限守卫**，守「飞行段被调长、把停留吃光」这类隐形退化；
- ④ `MAX_SECONDS` 内必须测到静止时刻（哨兵）。

**反向对照（两组，都精准变红后还原，`grep -rn "REVERSE-CONTROL" src/ tests/` 为空）**：
- **RC9**：`DEFAULT_LIFETIME` 退回 `4.7` ⇒ **精准 3 红**（`寿命不是定档值 3.70：4.700`、`实例寿命未按 DEFAULT_LIFETIME 初始化：4.700`、`停留缩短量不是 1.0s：上一版 4.70 − 寿命 4.70 = 0.00`），其余全绿、`EXIT=1`；还原后 `EXIT=0`。
- **RC9b（证明 ③ 是活的守卫，不是摆设）**：把 `ROLL_DAMPING: 3.4 → 0.2` 让飞行段吃满寿命 ⇒ ③ 精确命中 `弹壳落地静止后停留只有 1.23s（观感下限 1.5s）：t_settle=2.47 lifetime=3.70`。**这一步是必要的**：只跑 RC9 时 ③ 仍绿（`3.55 ≥ 1.5`），无法证明它被测到过。

**成本（随寿命同步下降，未做池化改动）**：`VfxPool3D` 对 active 实例**无上限**（`max_per_kind` 只管 inactive 回收桶）⇒ 射速 `1.0 ~ 12.0 发/s`（`BlueprintRegistry` 全体枪械）× `3.7 s` ⇒ 最坏同屏约 `44` 枚（v002.7 的 `4.7 s` 下约 `56` 枚、v002.2 的 `3.2 s` 下约 `38` 枚）。每枚 `3` 个 `MeshInstance3D`、`288` 三角面 ⇒ 约 `13k` 三角面、约 `130` 次绘制。

**未变更**：AssetID `VFX-SHELL-CASING-3D`、Prefab 路径与版本 `v001`、PBR 定档（`0.8 / 0.6`）、尺寸基准（`0.8`）、抛壳随机化幅度、`floor_y` 契约与「不接物理引擎」口径、探针四机位取景均未动 ⇒ **账本无需改动**。

**验证**：`verify_combat_vfx_toon_v002` → `COMBAT_VFX_TOON_V002_OK (samples=16)`（`EXIT=0`、0 ERROR，抽样 `lifetime=3.70 settle_at=1.15 hold=2.55`）；`verify_vfx_pool_lifecycle` → `VFX_POOL_LIFECYCLE_OK`；真渲染探针 → `SHELL_CASING_VISUAL_OK captured=4 skipped_headless=0`（散布判据 `off_line_residual=0.3393`，四机位全部重出图）。
"""

SPEC_ROW = """| 2026-09-22 | v002.8 | 弹壳**停留时长再缩短 1 秒**（业主指定：「弹壳的停留时长（再）缩短 1 秒」）—— 在 v002.7「+1.5 秒」基础上回调。**口径**同 v002.7：可见时长即 `DEFAULT_LIFETIME`，三段飞行不随寿命变化 ⇒ 诉求等价于 `4.7 → 3.7`（累计 `3.2 →（+1.5）4.7 →（−1.0）3.7`）。实测 `t_settle = 1.15 s`、停留 `2.55 s`（v002.7 为 `3.55 s`）。**验收结构修正**：v002.7 把行为断言「停留 ≥ 1.5 s」写在「增量」常量上（数值巧合、语义错位），本轮拆为独立常量 `EXPECTED_SHELL_HOLD_FLOOR := 1.5`，并在注释里写明四条断言各自守什么：① 定档值 ② 本轮缩短量 `4.7 − lifetime == 1.0`（换方向时减号语义要同步翻）③ 下限守卫 ④ 静止时刻哨兵。**反向对照两组**：RC9 寿命退回 4.7 ⇒ 精准 3 红（其余全绿）；**RC9b** 把 `ROLL_DAMPING: 3.4 → 0.2` 让飞行段吃满寿命 ⇒ ③ 精确命中 `停留只有 1.23s（观感下限 1.5s）` —— 只跑 RC9 时 ③ 仍绿，**必须靠 RC9b 才能证明这条守卫是活的**。**成本**：`12.0 发/s × 3.7 s ≈ 44` 枚同屏（v002.7 约 56 枚），约 `13k` 三角面 / 约 `130` 次绘制。AssetID / Prefab / 版本 `v001` / PBR / 尺寸 / 随机化口径 / `floor_y` 契约均未动，账本无需改动 |"""

# CHANGELOG 顶部锚点：文档头 + 当前第一条小节标题（并发会话会往顶部插新节 ⇒ 不写死旧标题）。
CHANGELOG_ANCHOR = "# 游戏设计文档 v0.1 变更记录\n\n## 2026-09-22｜右摇杆瞄准手感重做：瞄准辅助 + 响应曲线（业主选「2+1」）\n"

patch(
    CHANGELOG,
    CHANGELOG_ANCHOR,
    "# 游戏设计文档 v0.1 变更记录\n\n" + SECTION + "\n<br>\n"
    + "## 2026-09-22｜右摇杆瞄准手感重做：瞄准辅助 + 响应曲线（业主选「2+1」）\n",
    "CHANGELOG 顶部新节",
)

# 14.6 版本表末行紧接分隔线（**无空行**）—— 锚点按实际行尾取。
patch(
    SPEC,
    "，未做池化改动。AssetID / Prefab / 版本 `v001` / PBR / 尺寸 / 随机化口径 / `floor_y` 契约均未动，账本无需改动 |\n---\n",
    "，未做池化改动。AssetID / Prefab / 版本 `v001` / PBR / 尺寸 / 随机化口径 / `floor_y` 契约均未动，账本无需改动 |\n"
    + SPEC_ROW + "\n---\n",
    "14.6 §10 v002.8 行",
)

sys.exit(1 if FAILS else 0)
