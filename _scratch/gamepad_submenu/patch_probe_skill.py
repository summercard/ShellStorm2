"""给 skill `godot-runtime-probe` 补第十一条关键陷阱：headless 下 GUI 输入派发不工作。

来源：2026-09-22 修「手柄在设施子界面失灵」时实测。
skill 正本在 ~/.workbuddy/skills（A），改完必须按 skill-mirror-sync 的替代流程同步到 B/C/D。
本机不要跑 `--sync`（Safe-Delete 守卫会拦 rmtree，留下被删空的目录）。
"""
from __future__ import annotations

import sys
from pathlib import Path

TARGET = (
    Path.home() / ".workbuddy" / "skills" / "godot-runtime-probe" / "SKILL.md"
)

ANCHOR_INDEX = "## 已知噪音（不影响结论）\n"

ANCHOR_USAGE = (
    "**铁律：主人说\"看游戏内的\"时，禁止用 Blender headless 或读 `.blend` / `.glb` 源文件作答。** "
    "一律跑 Godot headless 探针。\n"
)
ADD_USAGE = (
    "\n> ⚠️ **headless 只对「结构 / 数值 / 坐标」类结论有效。** 一切与**输入派发**有关的结论"
    "（焦点有没有建立、按键有没有触发按钮、方向键有没有挪焦点）**都不能用 headless 下结论** —— "
    "见文末「第十一条关键陷阱」。焦点锚点可以 headless 断言，但「按下去有没有反应」必须带窗口跑。\n"
)

SECTION = '''
## 第十一条关键陷阱：`--headless` 下 **GUI 输入派发不工作**（2026-09-22 实测）

与第五条的 `MultiMesh` 回读是同一类问题，但更隐蔽 —— 它**只污染「输入类」结论**，
而且会让你误判成「我的 UI 接线写错了」。

- headless 下 `Control.grab_focus()` **有效**：`get_viewport().gui_get_focus_owner()` 正常返回被聚焦的控件。
  ⇒ 「**焦点锚点**」（菜单打开后有没有焦点持有者、焦点落在哪个控件）**可以 headless 断言，这条可信**。
- 但 headless 下**合成输入事件永远走不到控件的 `pressed`**（GUI 输入派发循环不被驱动）。
  实测六种注入方式全部无效：`Input.parse_input_event()` + `Input.flush_buffered_events()`、
  `Viewport.push_input()`、`InputEventAction("ui_accept")`、`InputEventJoypadButton(JOY_BUTTON_A)`、
  物理回车 key —— 同一份代码**去掉 `--headless`** 后全部命中。

**规矩**：

| 要验的东西 | 怎么验 |
|---|---|
| 焦点锚点（有没有焦点持有者、在哪个控件） | headless 跑 + **反向对照**（把 `grab_focus()` 停掉，断言必须变红） |
| 确认键是否触发按钮 / 方向键是否挪焦点 | **必须带窗口跑**（去掉 `--headless`），别在 headless 里追，追不出来 |

反向对照的开关写法很好用：把 `grab_focus()` 那一行换成注释、备份原文件，
红一次 / 绿一次，就能证明断言真的会失败，而不是「本来就没跑到」。

### 附：`ui_accept` / `ui_cancel` 绑的是 `physical_keycode`，导航键绑 `keycode`

`project.godot` 的 `[input]` 段里两套键位用的是**不同字段**：
`ui_up/down/left/right` → **`keycode`**；`ui_accept` / `ui_cancel` → **`physical_keycode`**。
所以合成 `InputEventKey` **要按目标 action 选字段**，不是「两个都填更保险」——
实测两个字段同时填时 `is_action("ui_up") == false`（`physical` 那一半不匹配 `keycode` 绑定）。

实测对照（裸 `Control + Button`，`focus_mode = FOCUS_ALL` 且已 `grab_focus()`）：

| 注入方式 | `pressed` 命中 |
|---|---|
| `InputEventAction("ui_accept")` | 1 |
| `InputEventKey(physical_keycode = KEY_ENTER)` | 1 |
| `InputEventKey(keycode = KEY_ENTER)` | **0** |
| `InputEventJoypadButton(JOY_BUTTON_A)` | 1 |
| `Viewport.push_input(物理 Enter)` | 1 |
| `Viewport.push_input(InputEventAction("ui_accept"))` | 1 |

⇒ 引擎机制本身没问题。**GUI 类问题先查「有没有焦点持有者」，再查事件形状**，
最后才怀疑自己的接线 —— 顺序反了会白查半天。

'''

def main() -> int:
    raw = TARGET.read_bytes()
    text = raw.replace(b"\r\n", b"\n").decode("utf-8")
    if "第十一条关键陷阱" in text:
        print("SKIP 已含第十一条")
        return 0

    if text.count(ANCHOR_INDEX) != 1:
        print("FAIL 索引锚点命中 %d 次" % text.count(ANCHOR_INDEX))
        return 1
    text = text.replace(ANCHOR_INDEX, SECTION.lstrip("\n") + ANCHOR_INDEX, 1)

    if text.count(ANCHOR_USAGE) != 1:
        print("FAIL 何时用锚点命中 %d 次" % text.count(ANCHOR_USAGE))
        return 1
    text = text.replace(ANCHOR_USAGE, ANCHOR_USAGE + ADD_USAGE, 1)

    TARGET.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
    print("OK 已写入 %s" % TARGET)
    return 0


if __name__ == "__main__":
    sys.exit(main())
