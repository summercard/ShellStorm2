# -*- coding: utf-8 -*-
"""弹壳停留时长再缩短 1 秒（业主 2026-09-22 第二轮）——4.7 → 3.7。CRLF 安全二进制替换。

纪律：已含 CRLF 的文件绝不用文本模式重写（会产出 CRCRLF 0d0d0a）。一律 rb 读 / wb 写。
"""
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SHELL_GD = ROOT + r"\src\vfx\VfxShellCasing3D.gd"
VERIFY_GD = ROOT + r"\tests\verification\verify_combat_vfx_toon_v002.gd"

FAILS = []


def crlf(t: str) -> str:
    return t.replace("\r\n", "\n").replace("\n", "\r\n")


def patch(path, old, new, label, expect=1):
    data = open(path, "rb").read()
    o = crlf(old).encode("utf-8")
    n = crlf(new).encode("utf-8")
    found = data.count(o)
    if found != expect:
        FAILS.append("%s: 命中 %d 处（期望 %d）" % (label, found, expect))
        print("FAIL %-38s found=%d expect=%d" % (label, found, expect))
        return
    open(path, "wb").write(data.replace(o, n))
    chk = open(path, "rb").read()
    print("OK   %-38s lines=%d crcrlf=%d lone=%d"
          % (label, chk.count(b"\n"), chk.count(b"\r\r\n"), chk.count(b"\n") - chk.count(b"\r\n")))


# ------------------------------------------------------------ (A) 特效脚本常量块
OLD_A = """## 弹壳视觉寿命：弹出 + 弹跳 + 滚动 + 静止的总预算。
## 业主 2026-09-22 追加定档：「弹壳的停留时长加 1.5 秒」⇒ 3.2 + 1.5 = **4.7**。
## 口径：飞行 / 弹跳 / 滚动三段的时长由物理常量与初速度决定，**不随寿命变化**
## ⇒ 寿命增加的部分全部落在「落地静止后的停留」上，停留时长同步 +1.5s
## （验收 `_check_shell_settled_hold()` 实测静止时刻，断言 `lifetime - t_settle ≥ 1.5`）。
## ⚠️ 本值同时就是「弹壳在地上的可见时长」—— 业主观感口径就是它，别在别处再塞一份。
## 成本提示：`VfxPool3D` 对 active 实例**无上限**（`max_per_kind` 只管 inactive 回收桶），
## 故拉长寿命 = 提高同屏存活弹壳数：射速 1.0 ~ 12.0 发/s × 4.7s ⇒ 最坏同屏 ≈ 56 枚
## （每枚 3 个 MeshInstance3D、288 三角面 ⇒ 约 16k 三角面 / 约 170 次绘制），仍在预算内。
## 若后续再加寿命，请先按此式复核同屏成本。
const DEFAULT_LIFETIME := 4.7
"""

NEW_A = """## 弹壳视觉寿命：弹出 + 弹跳 + 滚动 + 静止的总预算。
## 业主 2026-09-22 两轮定档：
##   「弹壳的停留时长加 1.5 秒」   ⇒ 3.2 + 1.5 = 4.7
##   「弹壳的停留时长再缩短 1 秒」 ⇒ 4.7 − 1.0 = **3.7**
## 口径：飞行 / 弹跳 / 滚动三段的时长由物理常量与初速度决定，**不随寿命变化**
## ⇒ 寿命增减的部分**全部落在「落地静止后的停留」上**，所以业主说的「加/缩短 N 秒」
##    直接落成本常量 ±N，不需要另建「停留参数」（见验收 `_check_shell_settled_hold()`：
##    它实测静止时刻 `t_settle`，断言 `lifetime − t_settle ≥ 观感下限 1.5s`）。
## ⚠️ 本值同时就是「弹壳在地上的可见时长」—— 业主观感口径就是它，别在别处再塞一份。
## 成本提示：`VfxPool3D` 对 active 实例**无上限**（`max_per_kind` 只管 inactive 回收桶），
## 故寿命直接决定同屏存活弹壳数：射速 1.0 ~ 12.0 发/s × 3.7s ⇒ 最坏同屏 ≈ 44 枚
## （每枚 3 个 MeshInstance3D、288 三角面 ⇒ 约 13k 三角面 / 约 130 次绘制），仍在预算内。
## 若后续再改寿命，请先按此式复核同屏成本
## （对照：4.7s 时 ≈ 56 枚 / 约 16k 面 / 约 170 次绘制；3.2s 时 ≈ 38 枚）。
const DEFAULT_LIFETIME := 3.7
"""

# ------------------------------------------------------------ (B) 验收常量区
OLD_B = """## —— 弹壳停留时长（业主 2026-09-22 追加：「弹壳的停留时长加 1.5 秒」）——
## 口径：寿命 = 飞行 + 弹跳 + 滚动 + **落地后的停留**；前三段由物理常量与初速度决定、
## 不随寿命变化 ⇒ 「停留 +1.5s」= 寿命 3.2 → 4.7。
## ⚠️ 三个数**刻意各自硬编码、不写成派生式**（4.7 = 3.2 + 1.5）：若写成
##    `PREVIOUS + DELTA`，改坏一处会让三处一起跟随，自我印证就抓不到了。
const EXPECTED_SHELL_LIFETIME_PREVIOUS := 3.2
const EXPECTED_SHELL_SETTLED_HOLD_DELTA := 1.5
const EXPECTED_SHELL_LIFETIME := 4.7
"""

NEW_B = """## —— 弹壳停留时长（业主 2026-09-22 两轮定档）——
## v002.7「停留 +1.5 秒」：3.2 → 4.7；v002.8「停留再缩短 1 秒」：4.7 → 3.7。
## 口径：寿命 = 飞行 + 弹跳 + 滚动 + **落地后的停留**；前三段由物理常量与初速度决定、
## 不随寿命变化 ⇒ 加/缩短寿命就是加/缩短停留。
## ⚠️ 四个数**刻意各自硬编码、不写成派生式**（3.7 = 4.7 − 1.0）：若写成
##    `PREVIOUS − SHORTEN`，改坏一处会让全部一起跟随，自我印证就抓不到了。
const EXPECTED_SHELL_LIFETIME_PREVIOUS := 4.7
const EXPECTED_SHELL_DWELL_SHORTEN := 1.0
const EXPECTED_SHELL_LIFETIME := 3.7
## 停留**观感下限**（独立于上面三档数值）：弹壳躺在地上至少要被看清这么久。
## v002.7 定这个口径时即取 1.5s，本轮沿用；专供 ③ 使用。
## ⛔ 它不是「增量」—— 别拿它去钉「加了几秒 / 缩短了几秒」，那是 ② 的职责（见 ③ 注释）。
const EXPECTED_SHELL_HOLD_FLOOR := 1.5
"""

# ------------------------------------------------------------ (C) 验收用例 docstring
OLD_C = """## 停留时长定档（业主 2026-09-22 追加：「弹壳的停留时长加 1.5 秒」）。
##
## 口径：弹壳「在地上的停留」= `lifetime − 落地静止时刻`。飞行 / 弹跳 / 滚动三段的时长
## 由物理常量与初速度决定，**不随寿命变化** ⇒ 加寿命就是加停留，业主的「+1.5 秒」
## 据此落成 `VfxShellCasing3D.DEFAULT_LIFETIME: 3.2 → 4.7`。
##
## 三条断言互补：
##   ① 寿命 = 定档值（外部真源硬编码，不引用被测常量 ⇒ 改坏常量才抓得到）；
##   ② 增量 = 上一版 3.2 + 1.5（**业主诉求本身**，常量级钉子）；
##   ③ 行为级：实测静止时刻后剩余停留 ≥ 1.5s —— 挡住「有人把初速度调大到飞行段
##      吃掉这 1.5s」这类隐形退化（那时 ①② 仍绿，只有 ③ 会红）。
## ⚠️ 必须用**新实例**：主用例那枚已被推进到 1.94s 且早已 SETTLED，
##    复用它时 t_settle 会取到第一个步长（恒真），③ 就废了。
"""

NEW_C = """## 停留时长定档（业主 2026-09-22 两轮：「停留加 1.5 秒」→「停留再缩短 1 秒」）。
##
## 口径：弹壳「在地上的停留」= `lifetime − 落地静止时刻`。飞行 / 弹跳 / 滚动三段的时长
## 由物理常量与初速度决定，**不随寿命变化** ⇒ 加/缩短寿命就是加/缩短停留。
## 两轮落成 `VfxShellCasing3D.DEFAULT_LIFETIME`：`3.2 →（+1.5）4.7 →（−1.0）**3.7**`。
##
## 四条断言互补（**各自守不同的东西，别混为一谈**）：
##   ① 寿命 = 定档值（外部真源硬编码，不引用被测常量 ⇒ 改坏常量才抓得到）；
##   ② 本轮增量 = 上一版 4.7 − 1.0（**业主诉求本身**，常量级钉子）。
##      换方向（加 ↔ 缩短）时这条的减号语义要同步翻，别只改数字；
##   ③ 行为级：实测静止时刻后剩余停留 ≥ **观测下限 1.5s**。⛔ 它是**下限守卫**、
##      不是增量钉子 —— 寿命 3.7 / 4.7 下都成立，守的是「飞行段被调长、把停留吃光」
##      这类隐形退化（那时 ①② 仍绿，只有 ③ 会红）。v002.7 曾把「增量」当它的前提，
##      本轮已把两者拆开（各自独立的常量）；
##   ④ 哨兵：MAX_SECONDS 内必须测到静止时刻，否则 ③ 会拿 -1.0 参与比较而恒真。
##
## ⚠️ 必须用**新实例**：主用例那枚已被推进到 1.94s 且早已 SETTLED，
##    复用它时 t_settle 会取到第一个步长（恒真），③ 就废了。
##
## 成本核对（**寿命每变一次都要照做**，式子见 `VfxShellCasing3D.DEFAULT_LIFETIME` 注释）：
## 射速 1.0 ~ 12.0 发/s × 3.7s ⇒ 最坏同屏 ≈ 44 枚（v002.7 的 4.7s 下为 ≈ 56 枚）。
"""

# ------------------------------------------------------------ (D) 断言 ② ③
OLD_D = """	# ② 增量 = 上一版 + 1.5s（业主诉求本身）。
	_expect(absf(lifetime - EXPECTED_SHELL_LIFETIME_PREVIOUS - EXPECTED_SHELL_SETTLED_HOLD_DELTA) < 0.0001,
		"弹壳停留增量不是 %.1fs：寿命 %.2f − 上一版 %.2f = %.2f"
		% [
			EXPECTED_SHELL_SETTLED_HOLD_DELTA,
			lifetime,
			EXPECTED_SHELL_LIFETIME_PREVIOUS,
			lifetime - EXPECTED_SHELL_LIFETIME_PREVIOUS,
		])
	# ③ 行为级：静止后真的还能停留 ≥ 1.5s。
	_expect(hold >= EXPECTED_SHELL_SETTLED_HOLD_DELTA,
		"弹壳落地静止后停留只有 %.2fs（要求 ≥ %.1fs）：t_settle=%.2f lifetime=%.2f"
		% [hold, EXPECTED_SHELL_SETTLED_HOLD_DELTA, settle_elapsed, lifetime])
"""

NEW_D = """	# ② 本轮缩短量 = 上一版 4.7 − 1.0s（业主诉求本身，常量级钉子）。
	_expect(absf(EXPECTED_SHELL_LIFETIME_PREVIOUS - lifetime - EXPECTED_SHELL_DWELL_SHORTEN) < 0.0001,
		"弹壳停留缩短量不是 %.1fs：上一版 %.2f − 寿命 %.2f = %.2f"
		% [
			EXPECTED_SHELL_DWELL_SHORTEN,
			EXPECTED_SHELL_LIFETIME_PREVIOUS,
			lifetime,
			EXPECTED_SHELL_LIFETIME_PREVIOUS - lifetime,
		])
	# ③ 行为级：静止后真的还能停留 ≥ 观感下限（**下限守卫**，不是增量钉子 —— 见函数头）。
	_expect(hold >= EXPECTED_SHELL_HOLD_FLOOR,
		"弹壳落地静止后停留只有 %.2fs（观感下限 %.1fs）：t_settle=%.2f lifetime=%.2f"
		% [hold, EXPECTED_SHELL_HOLD_FLOOR, settle_elapsed, lifetime])
"""

patch(SHELL_GD, OLD_A, NEW_A, "A 特效脚本 DEFAULT_LIFETIME")
patch(VERIFY_GD, OLD_B, NEW_B, "B 验收常量区")
patch(VERIFY_GD, OLD_C, NEW_C, "C 用例 docstring")
patch(VERIFY_GD, OLD_D, NEW_D, "D 断言 ② ③")

if FAILS:
    print("\n".join(["FAILS:"] + FAILS))
    sys.exit(1)
print("ALL PATCHES APPLIED")
