# -*- coding: utf-8 -*-
"""08 文档：验收项数 52 → 86，并追加 §13.6（98F 和平区不产出钥匙）。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"

A_ROW = (
    "| \u9a8c\u6536\uff08\u771f\u673a \u00b7 \u5f00\u573a\uff09 | `tests/verification/verify_opening_script_runtime.{gd,tscn}` | "
    "**52 \u9879**\u68c0\u67e5\u3002\u771f `TowerDescent3D` + \u771f `MainEntryScreen3D`\uff0c"
    "\u76ef\u56db\u4e2a\u771f\u673a\u7f3a\u9677\uff08\u00a713.5\uff09+ \u771f\u673a\u51e0\u4f55\u6bb5\uff1a"
    "E\uff08\u7b2c\u4e8c\u6bb5\u623f\u95f4\u76f8\u5bf9\u4f4d\u7f6e\u89e6\u53d1\u5668\uff09/ "
    "F\uff0898F \u548c\u5e73\u533a\u95e8\u7b56\u7565\u5168\u653e\u884c + \u5f00\u95e8\u8def\u5f84\u6e90\u7801\u5b88\u536b\uff09/ "
    "G\uff08\u5f00\u5c40\u7b2c\u4e00\u95f4\u623f\u706f\u9ed8\u8ba4\u5f00 + \u7b2c\u4e8c\u6bb5\u5237\u602a\u70b9\u5728\u623f\u5185\uff09 |"
)

B_ROW = (
    "| \u5f52\u5c55\uff08\u771f\u673a \u00b7 \u5f00\u573a\uff09 | `tests/verification/verify_opening_script_runtime.{gd,tscn}` | "
    "**86 \u9879**\u68c0\u67e5\u3002\u771f `TowerDescent3D` + \u771f `MainEntryScreen3D`\uff0c"
    "\u76ef\u56db\u4e2a\u771f\u673a\u7f3a\u9677\uff08\u00a713.5\uff09+ \u771f\u673a\u51e0\u4f55\u6bb5\uff1a"
    "E\uff08\u7b2c\u4e8c\u6bb5\u623f\u95f4\u76f8\u5bf9\u4f4d\u7f6e\u89e6\u53d1\u5668\uff09/ "
    "F\uff0898F \u548c\u5e73\u533a\u95e8\u7b56\u7565\u5168\u653e\u884c + \u5f00\u95e8\u8def\u5f84\u6e90\u7801\u5b88\u536b + \u95e8\u8282\u70b9\u7b56\u7565\u4e0e\u63d0\u793a\u8bed\uff09/ "
    "G\uff08\u5f00\u5c40\u7b2c\u4e00\u95f4\u623f\u706f\u9ed8\u8ba4\u5f00 + \u7b2c\u4e8c\u6bb5\u5237\u602a\u70b9\u5728\u623f\u5185\uff09/ "
    "H\uff0898F \u548c\u5e73\u533a\u4e0d\u4ea7\u51fa\u623f\u95f4\u94a5\u5319\uff09 |"
)

SECT = """
### 13.6 98F 和平区的「钥匙」生存面修正（2026-09-22）

§13.5 修的是剧情；这一节修的是同一片区域（98F 区块00）的**玩法生存面**两处人报。

| # | 人报症状 | 根因 | 修复 |
|---|---|---|---|
| 1 | 「98 层每个房间都有钥匙」——门明明不消耗钥匙 | `_try_open_room_door()` 读的是 `_door_policy_for_edge()`（硬编码 `requires_clear/requires_key/triggers_fate` 全 `true`），**完全没读** `DungeonRoom3D.door_policies` 里那份由 `authored_layout_peaceful` 算出的放行策略 ⇒ 「门只做普通开关」是空承诺，且**运行时零报错** | 新增 `_door_policy_towards(room_id, target_room_id)`：用 `room.door_targets` 把目标房反查回门方向 → 优先读房间声明，缺失才回落旧函数（**非和平区逐值不变**） |
| 2 | 门不要钥匙了，**地上还躺着一颗「房间钥匙」** | 钥匙闸口 `_ensure_room_key_reward()` 只查 `room.cleared` / 房型 / 已发过，**不判断「本房的门要不要钥匙」**，也不看调用方给的 `spawn_key` 形参。而 `_on_room_entered()` 的**重进已探索房间**分支（`L1956`）是**无条件**调它的 ⇒ 和平区首次进房走 `_mark_room_cleared(room, false)`（不发钥匙），玩家**回头再进同一间**就掉一把 | 新增 `_room_produces_room_key(room)` 并放进闸口守卫：`authored_layout_peaceful` 直接 false；否则只要该房**任一**方向的声明策略 `requires_key == true` 就算产出。**闸口自检、不信调用方形参** |

<span style="color:#791F1F">**两点值得记住：**</span>

1. **和平区的"不发"必须写在唯一的产出闸口上。** 把 `spawn_key = false` 交给调用方传参是靠不住的 ——
   同一个闸口还有别的调用方（重进房、修进度兜底），它们**不带**这个语义。判据要能自证。
2. **反向对照实测**：把闸口那一行摘掉 → 98F 四房**各掉 1 颗、全层 4 颗**，
   与人报截图逐项吻合（`failures=6`：四间房各 1 条 + 全层计数 + 源码守卫）。
   装回后 `verify_opening_script_runtime` **86 项全绿**、`_scratch` 无残留。

**顺带验证的可见面**（F 段新增）：门**节点**上也确实落到了放行策略 ——
实测四房各门提示语是 `[E] 开启通道`，不是 `[E] 使用房间钥匙`。
（`RoomDoor3D.set_access_policy()` 会 `_refresh_prompt()`，所以策略与提示语同源，不会各说各话。）

<span style="color:#1565C0">**一句话**：这不是剧情问题，是「区域声明」与「产出闸口」之间的一条**没接上的线** ——
和 §13.5 的四个缺陷同类：**全部零报错，只有人报才会发现。**</span>
"""


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    changed = False
    if "13.6 98F 和平区" in text:
        print("§13.6 already present")
    else:
        text = text.rstrip("\n") + "\n" + SECT
        changed = True

    if "**86 项**检查" in text:
        print("row already updated")
    else:
        if text.count(A_ROW) != 1:
            print("ABORT: 验收行锚点命中 %d" % text.count(A_ROW))
            return 3
        text = text.replace(A_ROW, B_ROW)
        changed = True

    if not changed:
        print("NO CHANGE")
        return 0

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
