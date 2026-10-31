# 右上角小地图：撤掉点击热区，只保留键 M

日期：2026-10-31
触发：业主指令「鼠标点击右上热区，会把小地图打开（快捷键 M）→ 热区去掉，保留快捷键 M」（附实机截图，绿框标出右上角）
性质：**输入/交互契约收窄**。不改渲染、不改尺寸、不改关卡拓扑、不改存档、不改玩法规则。

---

## 1. 热区是谁

`Dungeon3D._build_reference_hud()` 里对 `$HUD/DungeonMinimap3D` 做了三件事，合起来就是那块热区：

| 代码 | 作用 |
|---|---|
| `minimap.mouse_filter = Control.MOUSE_FILTER_STOP` | 吃掉整个 382×265 设计盒内的鼠标/触屏事件（不再往下传） |
| `minimap.tooltip_text = "点击打开/关闭全层地图 [键 M]"` | 悬停出提示，截图里那句 `点击打开/关闭全层地图 [键 M]` 就是它 |
| `minimap.gui_input.connect(_on_radar_gui_input.bind(minimap))` | 左键按下 ⇒ `_toggle_full_map()` + `_flash_action_key(panel)` + `set_input_as_handled()` |

节点本身没有多余子控件（`DungeonMinimap3D` 全靠 `_draw()` 画），所以热区范围 = 控件矩形，没有第二处需要清理。

## 2. 改了什么

| 文件 | 改动 |
|---|---|
| `src/world3d/Dungeon3D.gd` | 删掉上面三行（含注释），改为只留 `minimap.visible = true` 与一段口径说明；顺带删除已无引用的 `_on_radar_gui_input()` |
| `docs/v0.1/design/UI与UX全局设计及全界面清单.md` | UI-14 补一条「交互（2026-10-31 业主裁定）」：局部态纯展示、不接管鼠标、只保留键 M |

**为什么不用 `MOUSE_FILTER_PASS` 而是直接让 `IGNORE` 生效**：`DungeonMinimap3D._ready()` 本身就把 `mouse_filter` 设成 `MOUSE_FILTER_IGNORE`（`set_full_map_mode()` 里也是），这三行是唯一的覆写点。删掉即回到类默认值，不必在 HUD 里再写一遍 —— 少一处能不同步的状态。

## 3. 键 M 为什么不受影响

`_unhandled_input()` 里 `event.is_action_pressed("toggle_floor_map")` 是**独立通路**，与 `gui_input` 无关。原先点热区只是「多一条等效入口」，去掉后 M 键/手柄绑定（`GamepadInput` 运行时补的十字键）照旧。

**反向收益**：`MOUSE_FILTER_STOP` 原来还顺带拦住了右上角的射击/交互点击。改为穿透后，右上角区域可以正常开枪 —— 这是撤热区的必然结果，也符合业主"误触就弹全图"的抱怨方向。

## 4. 验证记录

| 项 | 方式 | 结果 |
|---|---|---|
| 引用清理 | 全仓 `grep _on_radar_gui_input`（`.gd` / `.tscn`） | 0 命中，无悬挂连接 |
| 探针契约 | `grep mouse_filter` across `tests/`、`tools/` | 无任何探针断言小地图的 `mouse_filter` / `tooltip_text`；`verify_tactical_inventory_minimap_flow` 只是 `set_current_room` 等数据接口，不受影响 |
| 场景挂载 | `scenes/TowerDescent3D.tscn` / `Dungeon3D.tscn` 的 `DungeonMinimap3D` 节点 | 未序列化 `mouse_filter`，全部由脚本驱动 ⇒ 无场景侧残留 |
| 键 M 通路 | 代码审读 `_unhandled_input` → `_toggle_full_map()` | 未改动，仍走 `toggle_floor_map` action |
| 运行时 | 未跑（本机找不到引擎可执行文件，且本次为纯删行的输入契约收窄） | **待实机确认**：右上角点击无反应、M 键仍开合全图 |

### 预期故障与未执行项

- 未跑 `check_documentation_contracts.py` 与 `run_verification_suite.sh`：后者长期被 `check_expedition03_room_layouts.py` 走廊端口预检拦住（存量红），本次未触及任何走廊/关卡文件。
- 未做真实渲染截图验证（改动不影响 `_draw()`）。

## 5. 顺带记录（未改，仅登记）

- 同一段 HUD 构建里还有另一处同类点击热区：`player_panel`（左上头像/血条）→ 点击 = `I`/`Tab` 开背包，`tooltip_text = "点击打开/关闭背包 [键 I / Tab]"`。本次**业主只点了小地图**，那处保留原样；若后续也要收窄，改法完全相同。
