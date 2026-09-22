# -*- coding: utf-8 -*-
"""写 2026-09-22/1352 事务 + 索引行。幂等、CRLF 纯净。"""

import sys

ROOT = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-22"
TXN = ROOT + r"\1352_98F和平区钥匙产出闸口.md"
IDX = ROOT + r"\_INDEX.md"

BODY = """# 98F 和平区仍掉「房间钥匙」——产出闸口没自检

- 时间：2026-09-22 13:52
- 触发：主人截图「你看还有房间钥匙」（98F 地上躺着一颗 `房间钥匙`）
- 涉及：`src/world3d/Dungeon3D.gd`、`tests/verification/verify_opening_script_runtime.gd`、`docs/v0.1/08_技术施工_剧情触发.md`

## 症状与归属

上一场（1152）刚把「门要不要钥匙」修好（`_door_policy_towards()`），
门确实不消耗钥匙了，**但地上的钥匙道具还在刷**。这不是同一个缺口：
前者管**开门判定**，后者管**道具产出**。

## 根因

钥匙的唯一产出闸口是 `Dungeon3D._ensure_room_key_reward()`，它有**三个调用方**：

| 调用方 | 是否带语义 |
|---|---|
| `_mark_room_cleared(room, spawn_key)` | 带（和平区传 `false`）|
| `_on_room_entered()` 的**重进已探索房间**分支（L1956）| **不带，且无条件调** |
| `_repair_room_progress` 兜底路径 | 通过 `_mark_room_cleared` |

而闸口自己**只查** `room.cleared` / 房型白名单 / `_spawned_key_rooms`，
**不判断「本房的门要不要钥匙」**，也**不看调用方的 `spawn_key` 形参**。

于是：

```text
和平区首次进房  →  _spawn_room_enemies()  →  _mark_room_cleared(room, false)   ← 不发钥匙 ✓
玩家回头再进同一间 →  _on_room_entered() 重进分支 → _ensure_room_key_reward(room)
                     cleared == true，room_type == COMBAT（不在排除表里）  →  掉一把 ✗
```

反向对照实测：98F **四房各掉 1 颗、全层 4 颗**，与人报截图逐项吻合。

## 修复

新增 `_room_produces_room_key(room) -> bool` 并放进闸口守卫（**自检，不信调用方形参**）：

- `room.authored_layout_peaceful` → `false`（和平区直接不产出）；
- 否则：该房**任一**方向声明的 `door_policies[dir].requires_key == true` 才算产出；
- `door_policies` 为空（理论上不会）→ 允许，等价旧行为。

非和平区**逐值不变**（战斗房门策略本来就全 true）。

## 顺带咬住的可见面

`RoomDoor3D.set_access_policy()` 会 `_refresh_prompt()`，而提示语由 `requires_key` 决定
（真时显示 `[E] 使用房间钥匙`）。真机 F 段新增断言：四房各门节点 `not door.requires_key`
且提示语不含「钥匙」——实测 `[E] 开启通道`。**策略与提示语同源，不会各说各话。**

## 验收

- `verify_opening_script_runtime` **68 → 86 项**，全绿：
  H 段按人报那条路复现（已清房 + 无条件调用），断言每间房重进后地上 0 颗、全层 0 颗、
  外加源码级守卫（闸口函数体必须含 `_room_produces_room_key(`）。
- **反向对照**：摘掉闸口那一行 → `failures=6`（四房各 1 条 + 全层计数 + 源码守卫），
  实测全层 4 颗钥匙，**人报症状原样复现**；装回后 86 项全绿、无残留备份。
- 交叉 `verify_narrative_timeline` **105 项**仍绿。
- 行尾：`Dungeon3D.gd` / 探针 / 文档 全部 CR=LF。

## 值得记住的

1. **「某区域不发某物」要写在产出闸口里自证**，不能靠调用方传形参 ——
   同一闸口的其它调用方**不带**那个语义（这里就是重进房那条）。
2. `door_policies` 一路双落（门节点判定 + 门提示语），改门策略时两处同时生效，别只查一处。
"""

ROW = (
    "| 13:52 | [98F 和平区仍掉「房间钥匙」——产出闸口没自检]"
    "(1352_98F和平区钥匙产出闸口.md) | **实际改动（生产代码 + 真机验收）** | "
    "主人截图「还有房间钥匙」→ 上轮只修了「门要不要钥匙」，没修「钥匙要不要产出」："
    "闸口 `_ensure_room_key_reward()` 不判断本房门策略，而 `_on_room_entered()` 的**重进房**分支"
    "**无条件**调它 ⇒ 和平区清房不发钥匙，回头再进就掉一把（四房各 1 颗）。"
    "新增 `_room_produces_room_key()` 自检；真机 68→**86 项**，反向对照 `failures=6` 原样复现 |\n"
)


def read_crlf(path: str) -> str:
    raw = open(path, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        raise SystemExit("REFUSE %s: 行尾不纯" % path)
    return raw.decode("utf-8").replace("\r\n", "\n")


def write_crlf(path: str, text: str) -> None:
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        raise SystemExit("REFUSE write %s: 行尾异常" % path)
    open(path, "wb").write(data)


def main() -> int:
    import os

    os.makedirs(ROOT, exist_ok=True)

    if os.path.exists(TXN):
        print("txn exists, skip")
    else:
        write_crlf(TXN, BODY)
        print("txn written")

    idx = read_crlf(IDX)
    if "1352_98F和平区钥匙产出闸口.md" in idx:
        print("index row exists, skip")
    else:
        idx = idx.rstrip("\n") + "\n" + ROW
        write_crlf(IDX, idx)
        print("index row appended")

    for path in (TXN, IDX):
        raw = open(path, "rb").read()
        print("%s CR=%d LF=%d" % (os.path.basename(path), raw.count(b"\r"), raw.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
