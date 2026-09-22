# -*- coding: utf-8 -*-
# 事务「命运卡界面手柄不能操控」文档与记忆落位。
# 纪律：读时归一 LF 便于匹配、写回统一 CRLF；共享文件只做点级插入，绝不整体覆写。
import pathlib

PROJ = pathlib.Path("I:/工作项目/shellstrom2/ShellStorm2")
MEM = pathlib.Path("I:/工作项目/shellstrom2/.workbuddy/memory")


def read_norm(path: pathlib.Path) -> str:
    return path.read_bytes().decode("utf-8").replace("\r\n", "\n")


def write_crlf(path: pathlib.Path, text: str) -> None:
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def patch(path: pathlib.Path, old: str, new: str) -> None:
    text = read_norm(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit("PATCH-FAIL %s anchor count=%d for %r" % (path.name, count, old[:70]))
    write_crlf(path, text.replace(old, new))
    print("patched", path.name)


# ---------------------------------------------------------------- CHANGELOG
changelog = PROJ / "docs/v0.1/development/CHANGELOG.md"
entry = """## 2026-09-22｜命运卡三选一界面接上手柄操控（默认焦点 + 环绕导航 + ui_cancel 放弃 + 同帧撞名修复）

**动机（业主指定）**：「命运卡片出现的那个界面，手柄不能操控。」

**根因**：命运卡三选一是 `Dungeon3D._build_door_fate_overlay()` **代码构造**的覆盖层，不在 `UiMenuFocus.ensure_focus` 覆盖的那批静态场景菜单里 ⇒ 从未 `grab_focus()`。而 Godot 4 的 `ui_left/right/up/down`（十字键/左摇杆）与 `ui_accept`（A 键）**都必须先有 gui focus owner 才会被派发** ⇒ 键鼠可用（鼠标点击不依赖焦点）、**手柄完全不能操控**。同批还有两处缺口：① 卡片按钮在翻转动画期间 `disabled = true`（防翻面前误点），禁用按钮不可聚焦、`UiMenuFocus.is_focusable` 也会排除它 ⇒ 焦点只能等翻转结束后再抓；② 放弃走的是**硬比 `KEY_ESCAPE`**，手柄 B（`ui_cancel`）到不了该分支。

**改动**（`src/world3d/Dungeon3D.gd` 6 处）：
- 新增 `_maybe_focus_fate_card()`：在 `_finish_reference_tarot_flip()` 解除 `disabled` 的那一刻抓默认焦点（三张卡翻转带 stagger，第一张最早解锁 ⇒ 焦点落在第一张卡）；**只在当前无焦点持有者时抓**，不抢玩家已用鼠标/手柄选中的卡。
- 新增 `_configure_fate_card_focus_navigation()`：显式指定三张卡的左右邻居并**首尾环绕**（逆位卡是整张旋转 180° 的实体卡面，自动 neighbor 推导依赖可见矩形方位、旋转后可能失准；自动推导也不做环绕，按到头就没反应）；上下接到同一组环绕，避免焦点被扔出弹窗。
- `_build_door_fate_overlay()`：收集三张卡按钮，交给上面的导航配置。
- `_unhandled_input()`：命运卡放弃改走 `event.is_action_pressed("ui_cancel")`（键盘 ESC 与手柄 B 共用）—— 与 0808 把 M/1/2/3/4 从硬比 keycode 改成 action 是同一类修正。
- `_close_door_fate_overlay()`：**先摘除再 `queue_free()`**（本轮检修出的第二个真实缺陷）。`queue_free()` 要到帧末才真正释放节点；同一帧内再次打开弹窗（连续两次命运卡流程 / 验收用例）时，新节点会与仍挂在树上的旧节点**撞名**、被引擎静默改名为 `DoorFateOverlay3D2`，此后所有按名查询（探针/验收里的 `HUD/DoorFateOverlay3D`）永远找不到这个弹窗。

**保持边界**：翻转动画、卡面美术、`tarot_face_ready` / `tarot_orientation` 元数据、三选一结算与满格转货币逻辑逐值不变；只在动画收尾补焦点、补邻居、换取消入口。

**验证**：
- `verify_dual_weapon_quick_map_fate_flow` 新增**手柄可操控契约**：等三张卡翻转完成后断言「弹窗节点存在 / 有 focus owner / focus owner 在弹窗内 / focus owner 是三张卡之一 / 卡有左右邻居」，再合成 `InputEventAction("ui_cancel")` 断言能放弃；复跑 `DUAL_WEAPON_QUICK_MAP_FATE_OK` exit=0。
- **反向对照 4 组**（`_scratch/fate_focus/negctl_fate_focus.py`，行级替换后逐行还原）：`no_focus` ⇒ 3 红、`no_neighbor` ⇒ 2 红、`hardcoded_esc` ⇒ 2 红、`no_detach` ⇒ 3 红，各自精准命中，`ALL_VARIANTS_HIT_EXPECTED`。
- 回归 `verify_gamepad_input_flow` `GAMEPAD_INPUT_FLOW_OK` exit=0。
- `verify_reference_hud_fate_visual` 在 `--headless` 下 4 条 `Could not capture` 红 —— **既有 headless 限制**（无渲染目标，该用例本就须带窗口跑），无新增断言失败。

**未变更**：未改命运卡内容 / 概率 / 结算，未改任何资产 / 账本 / 设计源；未提交（工作区混并行会话在制品）。

"""
patch(
    changelog,
    "# 游戏设计文档 v0.1 变更记录\n\n## 2026-09-22｜远征关卡01 Boss竞技场白模",
    "# 游戏设计文档 v0.1 变更记录\n\n" + entry + "## 2026-09-22｜远征关卡01 Boss竞技场白模",
)

# ---------------------------------------------------------------- MEMORY.md
memory = MEM / "MEMORY.md"
patch(
    memory,
    "- 覆盖菜单必须默认焦点（UiMenuFocus.ensure_focus），优先关闭/跳过，动态节点查找owned=false。\n",
    "- 覆盖菜单必须默认焦点（UiMenuFocus.ensure_focus），优先关闭/跳过，动态节点查找owned=false。**代码构造**的覆盖层（如命运卡三选一 `Dungeon3D._build_door_fate_overlay`）不在这批静态菜单里，须自己在动画收尾 `disabled=false` 之后 `grab_focus()`（禁用按钮/`UiMenuFocus.is_focusable` 排除禁用按钮）；取消入口走 `ui_cancel` action，别硬比 keycode。同帧重开覆盖层要**先 remove_child 再 queue_free**，否则旧节点本帧仍在树上、新节点撞名被引擎静默改名（`…3D2`），按名查询全失效。\n",
)

# ---------------------------------------------------------------- 事务文件
txn_name = "1854_命运卡界面手柄不能操控.md"
txn = MEM / "2026-09-22" / txn_name
txn_text = """# 命运卡三选一界面手柄不能操控

日期：2026-09-22 18:54
类型：Bug 修复（根因 + 代码 + 验收补强 + 反向对照）

## 现象

业主：「命运卡片出现的那个界面，手柄不能操控。」键鼠（鼠标点击）正常。

## 根因

命运卡三选一是 `Dungeon3D._build_door_fate_overlay()` **代码构造**的覆盖层，**不在**
`UiMenuFocus.ensure_focus` 覆盖的那批静态场景菜单里 ⇒ 从未 `grab_focus()`。
Godot 4 的 `ui_left/right/up/down`（十字键/左摇杆）与 `ui_accept`（A 键）**都必须先有
gui focus owner 才会被派发**；鼠标点击不依赖焦点，所以键鼠下完全看不见这个缺口。

连带两处：

1. 卡片按钮在翻转动画期间 `disabled = true`（防翻面前误点）。禁用按钮**不可聚焦**，
   `UiMenuFocus.is_focusable` 也会排除禁用按钮 ⇒ 焦点只能等翻转结束、`disabled=false` 之后再抓。
2. 放弃走的是**硬比 `KEY_ESCAPE`**，手柄 B（`ui_cancel`）到不了该分支 —— 与 0808 把
   M/1/2/3/4 从硬比 keycode 改成 `InputMap` action 是同一类修正。

## 改动（`src/world3d/Dungeon3D.gd` 6 处）

1. 新增 `_maybe_focus_fate_card(button)`：在 `_finish_reference_tarot_flip()` 解除 `disabled`
   的那一刻抓默认焦点。三张卡翻转带 stagger，第一张最早解锁 ⇒ 焦点落在第一张卡。
   **只在 `viewport.gui_get_focus_owner() == null` 时抓**，不抢玩家已选中的卡。
2. 新增 `_configure_fate_card_focus_navigation(buttons)`：显式写三张卡的
   `focus_neighbor_left/right/top/bottom` 并**首尾环绕**。理由：逆位卡是整张旋转 180° 的
   实体卡面，自动 neighbor 推导依赖可见矩形方位、旋转后可能失准；自动推导也不做环绕
   （按到头无反应）。上下接同一组环绕，避免焦点被扔出弹窗。
3. `_build_door_fate_overlay()`：把三张卡按钮收集进 `card_buttons`，调 (2)。
4. `_finish_reference_tarot_flip()`：末尾调 (1)。
5. `_unhandled_input()`：放弃改走 `event.is_action_pressed("ui_cancel")`。
6. `_close_door_fate_overlay()`：**先 `remove_child` 再 `queue_free()`** —— 附带修出的第二个
   真实缺陷。`queue_free()` 要到帧末才真正释放节点；同一帧内再次打开弹窗（连续两次命运卡
   流程 / 验收用例）时，新节点与仍挂在树上的旧节点**撞名**、被引擎静默改名为
   `DoorFateOverlay3D2`，此后所有按名查询（`HUD/DoorFateOverlay3D`）永远找不到弹窗。

## 验收

`tests/verification/verify_dual_weapon_quick_map_fate_flow.gd` 新增**手柄可操控契约**：

- 辅助 `_wait_fate_cards_flipped()` / `_fate_cards_flipped()`：按**真实时间**轮询（`create_timer`）
  等三张卡翻面完成。不用固定帧数 —— headless 下 process 帧不做垂直同步，固定帧数可能只累积
  极短的真实 delta，tween 走不完（会假红）。
- 断言：弹窗节点存在 / 有 focus owner / focus owner 在弹窗内 /
  focus owner 名以 `FateChoiceCard_` 开头 / 焦点卡有左右邻居。
- 合成 `InputEventAction("ui_cancel")` + `Input.parse_input_event` + `flush_buffered_events`
  断言能放弃（同时盯住「硬比 KEY_ESCAPE」回归）。

结果：`DUAL_WEAPON_QUICK_MAP_FATE_OK` exit=0。

## 反向对照（4 组，`_scratch/fate_focus/negctl_fate_focus.py`）

行级替换打回缺陷态 → 跑 → 逐行还原：

| 变体 | 命中 | 红项 |
|---|---|---|
| `no_focus` | 3 红 | 无 focus owner / focus owner 在弹窗外 / 不是三张卡之一 |
| `no_neighbor` | 2 红 | 卡无左邻居 / 无右邻居 |
| `hardcoded_esc` | 2 红 | ui_cancel 未放弃 / 无法重开 |
| `no_detach` | 3 红 | 卡片未在 6000ms 内翻完 / 弹窗节点缺失 / focus owner 在弹窗外 |

还原校验 `old_present=1 new_left=0` ×4 ⇒ `ALL_VARIANTS_HIT_EXPECTED`。

## 回归

- `verify_gamepad_input_flow`：`GAMEPAD_INPUT_FLOW_OK` exit=0。
- `verify_reference_hud_fate_visual`：`--headless` 下 4 条 `Could not capture` 红 ——
  **既有 headless 限制**（无渲染目标，该用例本就须带窗口跑），无新增断言失败。

## 未变更 / 未提交

未改命运卡内容 / 概率 / 结算，未改任何资产 / 账本 / 设计源。
`Dungeon3D.gd` 工作树里混有其它会话的在制品（`reward_plan` 透传、`_spawn_loot_items` spread、
`_room_produces_room_key`），**未触碰**。未提交。

## 坑

- 同帧 `queue_free()` 撞名：引擎**静默**改名、不报错，只有按名查询失效后才暴露。
- headless 可验焦点所有者存在，**不能**验 GUI 按钮输入派发 —— 但 `_unhandled_input` 走真实
  输入链，故 `ui_cancel` 可用合成 action 在 headless 验；按钮 `pressed` 须窗口实测。
- 固定帧数等动画在 headless 不可靠，按真实时间轮询。
"""
write_crlf(txn, txn_text)
print("wrote", txn.name)

# ---------------------------------------------------------------- _INDEX.md
index = MEM / "2026-09-22" / "_INDEX.md"
row = (
    "| 18:54 | [命运卡三选一界面手柄不能操控](1854_命运卡界面手柄不能操控.md) | "
    "**Bug 修复（根因 + 代码 + 验收补强 + 反向对照）** | "
    "业主「命运卡片出现的那个界面，手柄不能操控」。**根因**：命运卡三选一是 `Dungeon3D._build_door_fate_overlay()` "
    "**代码构造**的覆盖层，不在 `UiMenuFocus.ensure_focus` 那批静态菜单里 ⇒ 从未 `grab_focus()`；而 Godot 4 的 "
    "`ui_left/right` 与 `ui_accept` **都要先有 gui focus owner 才派发** ⇒ 键鼠正常（鼠标点击不依赖焦点）、手柄全不能动。"
    "连带两处：① 卡片翻转期间 `disabled=true`，禁用按钮不可聚焦 ⇒ 焦点只能等翻转结束后抓；② 放弃**硬比 `KEY_ESCAPE`**，"
    "手柄 B 到不了。**改动**（`Dungeon3D.gd` 6 处）：新增 `_maybe_focus_fate_card()`（在 `_finish_reference_tarot_flip` "
    "解除 disabled 时抓、只在无焦点持有者时抓）+ `_configure_fate_card_focus_navigation()`（显式左右邻居**首尾环绕**，"
    "因逆位卡整张旋转 180° 自动推导可能失准、且自动推导不环绕）+ 放弃改走 `ui_cancel` action + "
    "`_close_door_fate_overlay` **先 remove_child 再 queue_free**（修出第二个真实缺陷：同帧重开撞名、新节点被引擎**静默**改名 "
    "`DoorFateOverlay3D2`、按名查询全失效）。**保持边界**：翻转动画/卡面/元数据/结算逐值不变。**验收**："
    "`verify_dual_weapon_quick_map_fate_flow` 增手柄契约（等翻转完成 → 有 focus owner / 在弹窗内 / 是三张卡之一 / 有左右邻居 + "
    "合成 `InputEventAction(\"ui_cancel\")` 断言能放弃），`DUAL_WEAPON_QUICK_MAP_FATE_OK` exit=0；**反向对照 4 组**"
    "（`no_focus`⇒3 红 / `no_neighbor`⇒2 红 / `hardcoded_esc`⇒2 红 / `no_detach`⇒3 红）逐行还原 "
    "`ALL_VARIANTS_HIT_EXPECTED`；回归 `verify_gamepad_input_flow` exit=0。⚠️ 坑：固定帧数等动画在 headless 不可靠"
    "（无垂直同步、delta 极短）须按真实时间轮询；`verify_reference_hud_fate_visual` 在 headless 的 4 条 `Could not capture` "
    "是**既有**渲染限制。**未改命运卡内容/资产/账本/设计源；未提交**（`Dungeon3D.gd` 工作树混并行会话在制品，未触碰）。 |\n"
)
patch(
    index,
    "|---|---|---|---|\n",
    "|---|---|---|---|\n" + row,
)
print("ALL_DOCS_APPLIED")
