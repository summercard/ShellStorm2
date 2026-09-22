"""记录「朝向口径：手柄与触屏不一致」这条勘察结论，并写进当天索引。

本目录 .md 一律 CRLF（memory/README.md 约定），所以读时归一成 LF、写回时统一 CRLF。
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = (next(p for p in [Path(__file__).resolve().parent, *Path(__file__).resolve().parent.parents] if (p / "project.godot").exists())).parent / ".workbuddy" / "memory" / "2026-09-22"
NOTE = ROOT / "1125_朝向口径_手柄与触屏不一致.md"
INDEX = ROOT / "_INDEX.md"

BODY = """# 朝向口径：手柄与触屏不一致（设计咨询，未改代码）

**时间**：2026-09-22 11:25
**类型**：设计咨询 + 代码勘察（**未改任何代码**）

## 主人问的问题

左摇杆控制移动时同时控制面朝向，右摇杆在动时朝向才优先右摇杆 —— 会不会体验更好？

## 勘察结论（关键）

**触屏已经是这套逻辑，手柄不是。** 主人提的不是新机制，是「把手柄对齐触屏」。

- `src/ui/MobileInput.gd:244 _emit_face_direction()`：右摇杆激活且 `length_squared() > 0.0025` → 用它；
  否则左摇杆同阈值 → 用它；都空 → 归零。文件头第 12 行原文：「合并面朝方向：右摇杆优先，否则用左摇杆」。
- `src/core/GamepadInput.gd:164 _update_aim()`：右摇杆推动 → 平滑更新 `_aim_angle`；
  **回中时直接 `return`，保持最后方向**（文件头第 2 条差异：怕 `Player3D` 收到 ZERO 后退回鼠标射线，
  准星瞬间跳到鼠标位置）。⇒ 手柄实际是「右摇杆 > 保持上次」，**没有第二档**。

## 事实链（改之前必须知道的）

- `aim_direction` 同时是**面朝向 + 弹道方向 + 准星位置**：`Player3D._update_aim_from_mouse()`
  1821-1828 在 `_mobile_face_active` 时整段接管 `aim_direction` / `aim_yaw` / `aim_cursor`。
  ⇒ **改朝向就是改弹道**，不是纯视觉调整。
- 射击是**按住扳机连发**：`_update_combat_input()` 1671，`shoot_pressed_here` 为真即每帧
  `try_fire(aim_direction)`，射速由武器自身节流。
- `_mobile_face_active = aim.length_squared() > 0.05`（`Player3D:439`）。手柄永不发零
  ⇒ 首次推过右摇杆之后该标志永远为真。
  ⚠️ 反向推论：**纯手柄玩家若从没推过右摇杆**，`GamepadInput._aim_valid` 仍为 false
  ⇒ 此时面朝向其实来自**鼠标射线**。

## 建议方案（未实施）

改 `GamepadInput._update_aim()` 为三档：右摇杆推动 → 用它；否则**左摇杆推动（按 move 死区）→ 用它**；
否则**保持上次（绝不发零）**。即与触屏同构，但**保留第 3 档** —— 触屏可以归零是因为触屏无鼠标。

两个必备守卫：
1. 优先级按**死区判定 + 滞回**，否则摇杆漂移会让朝向在两档之间来回切；
2. 第二档也走**现有的 aim 平滑**（`AIM_SMOOTHING_BASE_RATE`），否则战斗中松手会「甩枪」。

建议做成 ESC「操作设置」页里的开关（该页已有死区 / 平滑 / 震动滑条），默认开。

## 风险评估

- **扫射不受影响**：左摇杆拉后 + 右摇杆朝敌按住时，右摇杆仍是最高优先，边退边打照旧成立。
- 唯一真风险是「战斗中松开右摇杆」那一瞬间的转向，靠平滑 + 可选的短暂延迟缓冲化解。

## 未做

没有改动任何代码；等主人确认是否落地、以及是否做成设置项。
"""

ROW = (
    "| 11:25 | [朝向口径：手柄与触屏不一致](1125_朝向口径_手柄与触屏不一致.md) | "
    "**设计咨询 + 代码勘察（未改代码）** | "
    "主人问「左摇杆控移动时同时控朝向、右摇杆动时优先右摇杆，会不会更好」。"
    "**勘察结论：触屏已经是这套逻辑，手柄不是** —— `MobileInput._emit_face_direction()`"
    "（第 244 行）明写「右摇杆优先，否则用左摇杆」；`GamepadInput._update_aim()`（第 164 行）"
    "回中时直接 `return` 保持最后方向，**只有两档、没有第二档**（保留最后方向是为了不触发 "
    "Player3D 的鼠标射线回落，不是玩法选择）⇒ 主人提的不是新机制，是把手柄对齐触屏。"
    "**关键事实链**：`aim_direction` 同时是面朝向 + 弹道方向 + 准星位置 ⇒ 改朝向 = 改弹道；"
    "射击是按住扳机连发；手柄永不发零 ⇒ `_mobile_face_active` 首次推杆后永远为真，"
    "⚠️ 但纯手柄玩家从没推过右摇杆时，朝向其实来自**鼠标射线**。**建议**：改成三档"
    "「右摇杆 → 左摇杆（按死区）→ 保持上次」，加两个守卫（死区+滞回防漂移抖动、第二档走现有 "
    "aim 平滑防松手甩枪），并做成 ESC 操作设置页开关。**扫射不受影响**，唯一真风险是松手瞬间转向。 |"
)


def main() -> int:
    if NOTE.exists():
        print("SKIP 事务文件已存在")
    else:
        NOTE.write_bytes(BODY.replace("\n", "\r\n").encode("utf-8"))
        print("OK 已写 %s" % NOTE.name)

    text = INDEX.read_bytes().replace(b"\r\n", b"\n").decode("utf-8")
    if "1125_朝向口径" in text:
        print("SKIP 索引已含本事务")
        return 0
    # 新行为最新 → 插在表头分隔行之后（不要锚具体某个时间行：
    # 并行会话会继续往顶部加更新的行，锚死某一行迟早插错位置）。
    anchor = "|---|---|---|---|\n"
    if text.count(anchor) != 1:
        print("FAIL 索引表头锚点命中 %d 次" % text.count(anchor))
        return 1
    text = text.replace(anchor, anchor + ROW + "\n", 1)
    INDEX.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
    print("OK 已插入索引行")
    return 0


if __name__ == "__main__":
    sys.exit(main())
