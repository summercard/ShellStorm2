# -*- coding: utf-8 -*-
"""弹壳停留时长 +1.5s（业主 2026-09-22）——CRLF 安全的二进制替换。

纪律：已含 CRLF 的文件**绝不**用文本模式重写（会产生 CRCRLF 0d0d0a，
既让 git diff 报整文件改写，又让 GDScript 报 parser error）。
本脚本一律 rb 读 / wb 写，替换串在 LF 文本上拼好后统一转 CRLF。
"""
import os
import sys

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SHELL_GD = os.path.join(ROOT, "src", "vfx", "VfxShellCasing3D.gd")
VERIFY_GD = os.path.join(ROOT, "tests", "verification", "verify_combat_vfx_toon_v002.gd")

FAILS = []


def crlf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\n", "\r\n")


def patch(path: str, old: str, new: str, label: str, expect: int = 1) -> None:
    data = open(path, "rb").read()
    o = crlf(old).encode("utf-8")
    n = crlf(new).encode("utf-8")
    found = data.count(o)
    if found != expect:
        FAILS.append("%s: 命中 %d 处（期望 %d）" % (label, found, expect))
        print("FAIL %-42s found=%d expect=%d" % (label, found, expect))
        return
    data = data.replace(o, n)
    open(path, "wb").write(data)
    chk = open(path, "rb").read()
    crcrlf = chk.count(b"\r\r\n")
    lf = chk.count(b"\n")
    cr = chk.count(b"\r\n")
    status = "OK" if crcrlf == 0 and lf == cr else "WARN"
    if status == "WARN":
        FAILS.append("%s: 行尾异常 crcrlf=%d lone_lf=%d" % (label, crcrlf, lf - cr))
    print("%s   %-42s lines=%d crlf=%d crcrlf=%d lone=%d"
          % (status, label, lf, cr, crcrlf, lf - cr))


# ---------------------------------------------------------------- (A) 特效脚本
OLD_LIFETIME = """## 弹壳视觉寿命：弹出 + 弹跳 + 滚动 + 静止的总预算。
const DEFAULT_LIFETIME := 3.2
"""

NEW_LIFETIME = """## 弹壳视觉寿命：弹出 + 弹跳 + 滚动 + 静止的总预算。
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

# ------------------------------------------------- (B1) 验收 · 常量区（外部真源）
OLD_CONST = """const EXPECTED_SHELL_INITIAL_TILT_DEG := 45.0
## 连发抽样发数。24 发是「能稳定量出散布、又不拖慢验收」的折中：
"""

NEW_CONST = """const EXPECTED_SHELL_INITIAL_TILT_DEG := 45.0
## —— 弹壳停留时长（业主 2026-09-22 追加：「弹壳的停留时长加 1.5 秒」）——
## 口径：寿命 = 飞行 + 弹跳 + 滚动 + **落地后的停留**；前三段由物理常量与初速度决定、
## 不随寿命变化 ⇒ 「停留 +1.5s」= 寿命 3.2 → 4.7。
## ⚠️ 三个数**刻意各自硬编码、不写成派生式**（4.7 = 3.2 + 1.5）：若写成
##    `PREVIOUS + DELTA`，改坏一处会让三处一起跟随，自我印证就抓不到了。
const EXPECTED_SHELL_LIFETIME_PREVIOUS := 3.2
const EXPECTED_SHELL_SETTLED_HOLD_DELTA := 1.5
const EXPECTED_SHELL_LIFETIME := 4.7
## 连发抽样发数。24 发是「能稳定量出散布、又不拖慢验收」的折中：
"""

# ------------------------------------------------- (B2) 验收 · 调用点
OLD_CALL = """	_check_shell_simulation_only()
	_check_shell_nonzero_floor()
"""

NEW_CALL = """	_check_shell_simulation_only()
	_check_shell_nonzero_floor()
	_check_shell_settled_hold()
"""

# ------------------------------------------------- (B3) 验收 · 新增用例
OLD_FUNC = """	deep.free()


## 尺寸定档（业主 2026-09-22：缩到原基准的 80%）—— 视觉缩放与贴地半径必须同步落到几何上。
"""

NEW_FUNC = """	deep.free()


## 停留时长定档（业主 2026-09-22 追加：「弹壳的停留时长加 1.5 秒」）。
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
func _check_shell_settled_hold() -> void:
	const STEP := 1.0 / 60.0
	const MAX_SECONDS := 12.0
	var shell := SHELL_SCENE.instantiate() as VfxShellCasing3D
	if shell == null:
		_failures.append("弹壳 Prefab 根节点不是 VfxShellCasing3D（停留时长用例）")
		return
	add_child(shell)
	# 初速度取抛壳随机化的中心值（= 上一版固定值）⇒ 落地过程与实机一致，可复现。
	shell.activate(Vector3(0.0, 1.2, 0.0), Color(0.92, 0.56, 0.16), EXPECTED_SHELL_SIZE, {
		"velocity": Vector3(
			EXPECTED_SHELL_EJECT_RIGHT_SPEED,
			EXPECTED_SHELL_EJECT_UP_SPEED,
			0.0
		),
		"floor_y": 0.0,
	})
	_samples += 1
	var settle_elapsed := -1.0
	var elapsed := 0.0
	while elapsed < MAX_SECONDS:
		elapsed += STEP
		shell.call("_on_tick", elapsed, shell.lifetime)
		if bool(shell.call("get_presentation_snapshot").get("settled", false)):
			settle_elapsed = elapsed
			break
	# 防假绿哨兵：没测到静止时刻，③ 会退化成「拿 -1.0 参与比较」，必须先把它挡下。
	_expect(settle_elapsed > 0.0,
		"弹壳在 %.1fs 内未进入静止，停留时长无法核算（哨兵）" % MAX_SECONDS)
	var lifetime := float(VfxShellCasing3D.DEFAULT_LIFETIME)
	var hold: float = lifetime - settle_elapsed
	print("[vfx_toon_v002] shell settled_hold lifetime=%.2f settle_at=%.2f hold=%.2f"
		% [lifetime, settle_elapsed, hold])
	# ① 寿命定档（外部真源）。
	_expect(absf(lifetime - EXPECTED_SHELL_LIFETIME) < 0.0001,
		"弹壳寿命不是定档值 %.2f：%.3f" % [EXPECTED_SHELL_LIFETIME, lifetime])
	_expect(absf(shell.lifetime - EXPECTED_SHELL_LIFETIME) < 0.0001,
		"弹壳实例寿命未按 DEFAULT_LIFETIME 初始化：%.3f（检查 _ready）" % shell.lifetime)
	# ② 增量 = 上一版 + 1.5s（业主诉求本身）。
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
	shell.free()


## 尺寸定档（业主 2026-09-22：缩到原基准的 80%）—— 视觉缩放与贴地半径必须同步落到几何上。
"""

patch(SHELL_GD, OLD_LIFETIME, NEW_LIFETIME, "A 特效脚本 DEFAULT_LIFETIME")
patch(VERIFY_GD, OLD_CONST, NEW_CONST, "B1 验收常量区")
patch(VERIFY_GD, OLD_CALL, NEW_CALL, "B2 验收调用点")
patch(VERIFY_GD, OLD_FUNC, NEW_FUNC, "B3 验收新增用例")

if FAILS:
    print("\n".join(["FAILS:"] + FAILS))
    sys.exit(1)
print("ALL PATCHES APPLIED")
