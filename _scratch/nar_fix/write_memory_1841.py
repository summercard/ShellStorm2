# -*- coding: utf-8 -*-
"""写 2026-09-22/1841 事务 + 索引行 + playbooks 追加段。幂等、CRLF 纯净。"""

import os
import sys

ROOT = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(ROOT, "2026-09-22")
TXN = os.path.join(DAY, "1841_角色头顶气泡不再投影.md")
IDX = os.path.join(DAY, "_INDEX.md")
PB = os.path.join(ROOT, "MEMORY-playbooks.md")

BODY = """# 角色头顶气泡不再投影（元凶是底板 MeshInstance3D）

- 时间：2026-09-22 18:41
- 触发：主人「角色头上的对话框会投射投影，这个要去掉」
- 涉及：`src/ui/bubble/SpeechBubble3D.gd`、`tests/verification/verify_speech_bubble_3d.gd`

## 根因（实测，不是猜）

`_scratch/nar_fix/probe_default_shadow.gd` 直接问引擎默认值：

```
DEFAULT_SHADOW Label3D=0 MeshInstance3D=1   (OFF=0, ON=1)
```

- **`MeshInstance3D.cast_shadow` 默认 ON** ⇒ 气泡底板（程序化圆角矩形）在世界里投出一个方块影子。
- **`Label3D.cast_shadow` 默认就是 OFF** ⇒ 文字本来就不投影。

所以「角色头顶的对话框有投影」= **只有底板**这一件。修法：`_build_nodes()` 里给 `_panel` 一行

```gdscript
_panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
```

## 顺手扫了同类 3D UI（结论：不用改）

全仓 `MeshInstance3D.new()` / `Label3D.new()` 的 UI 类节点里，**「飘字 / 敌人名字 / 掉落标签 / 撤离提示 / NPC 名字」
全是 `Label3D`** —— 默认不投影，本来就没问题。
真正的 Mesh-UI 只有气泡底板，以及若干**本该投影**的东西
（`EnemyAvatar3D._tell_ring` 显式 ON、地面掉落物的道具模型、墙上灯开关面板）——都不动。

## ⛔ 一条被我自己制造出来的「死断言」

第一版顺手也给 `Label3D` 写了 `cast_shadow = OFF`，并配了一条断言
「Label3D 仍在投影（文字会在地上留下影子）」。**反向对照时它没变红** ——
因为 Label3D 默认就是 OFF，那行是冗余代码，那条断言**永远不会失败**（假绿）。
已把行与断言一起删掉，只留底板那条（它**实测能咬住**：摘掉那行 ⇒ 恰 1 条红）。
教训：**加断言时必须反向对照一次**，否则你不知道它是「在守」还是「在装样子」。

## 验收

- `verify_speech_bubble_3d`：60 → **61 项**全绿（只加了 1 条，能失败的那条）。
- **反向对照**：摘掉 `_panel.cast_shadow` 那行 ⇒ `exit=1`、**恰好 1 条红**
  （「底板仍在投影（头顶的对话框会在地面/墙上留下影子）」）；还原后 61 项全绿、逐字节干净。
- 交叉 `verify_opening_script_runtime` **105 项**仍绿（气泡的主要消费者）。
"""

PB_ANCHOR = "### 开场演出 · 交互与武装口径（2026-09-22）\n"
PB_ADD = """### 3D UI 的投影：先看节点类型，再决定要不要关（2026-09-22）

- **默认值实测**（`_scratch/nar_fix/probe_default_shadow.gd`）：
  `Label3D.cast_shadow = 0 = OFF`；`MeshInstance3D.cast_shadow = 1 = ON`。
  ⇒ **`Label3D` 天生不投影**，「飘字 / 敌人名字 / 掉落标签 / 撤离提示」这类根本不用管；
  **真正会投影的是自绘 Mesh 的 UI**（例：气泡底板 `SpeechBubble3D._panel` 投出一个方块影子）。
- 修法一行：`node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`（全仓惯用写法）。
- ⛔ **别顺手给 Label3D 也写一条「不许投影」的断言** —— 它默认就是 OFF，那条断言**永远为绿**。
  加任何 UI 断言都**必须反向对照一次**（摘掉那行 ⇒ 要变红），否则你分不清它是「在守」还是「在装样子」。
- 全仓「本该投影」、不要动的：`EnemyAvatar3D._tell_ring`（显式 ON 的告知环）、
  地面掉落物的道具模型、墙上灯开关面板。

"""

ROW = (
    "| 18:41 | [角色头顶气泡不再投影（元凶是底板 MeshInstance3D）](1841_角色头顶气泡不再投影.md) | "
    "**实际改动（生产代码 + 验收）** | 主人「头上的对话框会投射投影」→ 实测默认值："
    "`MeshInstance3D.cast_shadow` 默认 **ON**（底板在投影）、`Label3D` 默认 **OFF**（文字本来就不投）。"
    "给 `_panel` 关投影；气泡验收 60→**61 项**，反向对照恰 1 条红。"
    "⚠️ 顺手给 Label3D 写的断言**永不失败**（假绿），已删 |\n"
)


def main() -> int:
    os.makedirs(DAY, exist_ok=True)

    if os.path.exists(TXN):
        print("txn exists, skip")
    else:
        data = BODY.replace("\n", "\r\n").encode("utf-8")
        assert data.count(b"\r") == data.count(b"\n")
        open(TXN, "wb").write(data)
        print("txn written")

    raw = open(IDX, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n")
    t = raw.decode("utf-8").replace("\r\n", "\n")
    if "1841_角色头顶气泡不再投影" in t:
        print("index row exists, skip")
    else:
        t = t.rstrip("\n") + "\n" + ROW
        data = t.replace("\n", "\r\n").encode("utf-8")
        assert data.count(b"\r") == data.count(b"\n") and b"\r\r" not in data
        open(IDX, "wb").write(data)
        print("index row appended")

    raw = open(PB, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n")
    t = raw.decode("utf-8").replace("\r\n", "\n")
    if "3D UI 的投影：先看节点类型" in t:
        print("playbooks exists, skip")
    else:
        n = t.count(PB_ANCHOR)
        assert n == 1, "playbooks 锚点命中 %d" % n
        t = t.replace(PB_ANCHOR, PB_ADD + PB_ANCHOR)
        data = t.replace("\n", "\r\n").encode("utf-8")
        assert data.count(b"\r") == data.count(b"\n") and b"\r\r" not in data
        open(PB, "wb").write(data)
        print("playbooks section added")

    for path in (TXN, IDX, PB):
        raw = open(path, "rb").read()
        print("%s CR=%d LF=%d" % (os.path.basename(path), raw.count(b"\r"), raw.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
