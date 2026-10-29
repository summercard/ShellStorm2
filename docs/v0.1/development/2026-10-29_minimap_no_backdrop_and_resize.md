# 右上角小地图：去掉半透明底 + 缩到业主红框大小

日期：2026-10-29
触发：业主指令「右上角的小地图，不要后面的半透明底，然后整体缩小到红框的大小」（附实机截图并画出红框）
性质：**视觉形态微调 + 尺寸重定**。不改关卡拓扑、不存档、不改玩法规则、不改 EGT 三条渲染契约。

---

## 1. 指令拆解

业主这句话包含两个独立意图，缺一不可：

| 意图 | 落点 | 边界 |
|---|---|---|
| ① 去掉小地图**后面的半透明底** | `DungeonMinimap3D._draw()` 角落态那一层 `draw_rect(..., FRAME_BG, true)` | **只改角落态**。M 键全屏大地图的背板与双层边框必须保留 |
| ② 整体**缩小到红框的大小** | 角落盒尺寸 458×346 → **382×265** 设计 px，并挪到红框位置 | 尺寸由业主截图上的红框反推，不是拍脑袋 |

> **易混点**：半透明底有两处 —— 角落态的 `FRAME_BG` 与全屏态 `_draw_full_map_backdrop()`。
> 两者共用 `FRAME_BG`/`FRAME_COLOR` 常量。**常量保留**，只删角落态那一行 `draw_rect`。
> 业主只说了"右上角的小地图"，M 键大地图不在范围内。

## 2. 半透明底到底是谁

先做了定位，确认不是别的 Panel：

- 逐列扫亮度，发现 `x=908→909` 亮度从 102.7 掉到 69.7 —— 这正是 `FRAME_BG`
  （`Color(0.0, 0.02, 0.04, 0.34)`）叠在场景上的效果。
- 底板可见区 x 909.2..1271.6、y 37.2..310，正好等于控件矩形内缩 2px
  （`draw_rect(Rect2(Vector2(2,2), size - Vector2(4,4)), ...)`）。
- 结论：就是 `DungeonMinimap3D` 自己画的，不是 HUD 里的别的面板。

## 3. 红框 → 设计尺寸的换算

**先验证截图坐标系 = canvas 坐标系（1:1）**。这一步不做，后面的换算全是猜的。

- 项目 viewport = 1280×720，`stretch/mode = "canvas_items"`、`aspect = "expand"`；
  业主截图本身就是 1280×720。
- 反推验证：按旧锚点 `-466` 算，控件左缘应落在 `1280 - 466×0.80 = 907.2`；
  截图中实测背板左缘正是 `x≈908`。**1:1 成立**，截图像素可直接当 canvas 像素用。

红框包围盒（限右上角区域统计，避开左上角 HP 血条的红色污染）：

| 边 | 截图/canvas px |
|---|---|
| 左 | x = 962 |
| 右 | x = 1267 |
| 上 | y = 40 |
| 下 | y = 251 |

⇒ 红框 = **306 × 212 canvas px**。

再按 `HUD_UI_SCALE = 0.80` 换算回设计 px：

```
宽 306 / 0.8 = 382.5  →  取 382
高 212 / 0.8 = 265    →  取 265
```

定位（设计 px）：

```
右缘距屏幕右 1280-1267 = 13 canvas px → offset_right = -13/0.8 ≈ -16
上缘 40 canvas px                        → offset_top  =  40/0.8 = 50
```

⇒ 新锚点 `_anchor_control(minimap, 1.0, 0.0, 1.0, 0.0, -398, 50, -16, 315)`。

**运行时实测**（一次性探针读 `get_global_rect()`，非像素反推）：
`x 961.6..1267.2  y 40.0..252.0  size 305.6×212.0` —— 与红框误差 ≤0.4px。

## 4. 改了什么

| 文件 | 改动 |
|---|---|
| `src/ui/DungeonMinimap3D.gd` | `_draw()` 删掉角落态的 `draw_rect(..., FRAME_BG, true)`；`FRAME_BG`/`FRAME_COLOR` 常量保留（全屏态在用）；`_content_map_rect()`、`_map_scale()` 的注释更新为新尺寸 |
| `src/world3d/Dungeon3D.gd` | 锚点 `-466,44,-8,390` → `-398,50,-16,315`；设计盒注释由 458×346 改为 382×265 并写明红框来源 |
| `tests/verification/verify_reference_hud_fate_visual.gd` | 精确断言 `Vector2(382,265) × HUD_UI_SCALE`；顺手修掉文案里遗留的 "458×374"（实际一直是 346） |
| `tools/_minimap_render.gd` | `REAL_PANEL` 同步为 382×265×0.80 |
| `tools/_minimap_selfcheck.gd` | `REAL_SIZE` 同步为 305.6×212.0；修掉注释里的 "366×299 = 458×374" 错字 |
| `docs/v0.1/design/UI与UX全局设计及全界面清单.md` | UI-14 条目改写（不再是"小圆盘/默认隐藏"，写明无背板与新尺寸）；§3.2 层级表 `z_index=105` 行同步 |
| `docs/v0.1/05_技术施工_关卡生成与爬楼.md` | §10 补"局部态无背板"与"角落盒 382×265"两条契约；修正 `MAP_MAX_SIZE` 表述（该常量代码里已不存在） |

## 5. 缩小后各楼层是否溢出

新的内容区 = `size - CORNER_MARGIN - 6` ⇒ **289.6 × 198**。按各关卡 floor bounds 实算：

| 关卡 / 层 | bounds (m) | 每米像素 | 实绘 (px) | 备注 |
|---|---|---|---|---|
| 99 / floor_00 | 105×155 | 1.277 | 134.1×198.0 | 正好贴满高度 |
| battle_level01 / floor_98 | 235×195 | 1.015 | 238.6×198.0 | |
| expedition_01 / floor_00 | 250×215 | 0.921 | 230.2×198.0 | |
| expedition_02 / floor_00 | 80×160 | 1.238 | 99.0×198.0 | |
| **expedition_03 / floor_00** | 235×130 | **1.232** | 289.6×160.2 | 业主截图那一层 |

全部 **≥0.6 硬下限** ⇒ 不触发 `maxf(0.6, …)` 的强行放大，也不溢出面板。
expedition_03 的缩放从 1.491 降到 1.232，**地图整体缩小约 17%**，与业主"整体缩小"的意图一致。

## 6. 验证记录

| 项 | 方式 | 退出码 | 结果 |
|---|---|---|---|
| 几何自检 | `godot --headless --script res://tools/_minimap_selfcheck.gd` | 0 | `MINIMAP SELFCHECK OK`；panel=(305.6, 212.0)、ppm=2.317、drawn=(289.6, 139.008)，未溢出 |
| HUD 视觉探针 | 窗口化跑 `verify_reference_hud_fate_visual.tscn`（属 `visual_scenes`，需真实渲染器） | 0 | `REFERENCE_HUD_FATE_VISUAL_OK` —— 含本次新增的 382×265 精确断言 |
| 小地图流程探针 | headless 跑 `verify_tactical_inventory_minimap_flow.tscn` | 1 | **存量红，与本次无关**，见 §7 |
| 开发期出图 | 窗口化跑 `tools/_minimap_render.gd` | 0 | `egt_minimap_corner.png` 确认无背板、房间块浮在背景上 |
| 实机出图 | 远征关卡03（业主截图那一关）整层揭示后截图 | 0 | `egt_minimap_expedition03.png` —— 无背板、位置与红框一致 |
| 尺寸实测 | 一次性探针读 `get_global_rect()` | 0 | x 961.6..1267.2、y 40.0..252.0、305.6×212.0 |

### 预期故障与未执行项（不计入成功总数）

- **`check_expedition03_room_layouts.py` 预检红**（`rt_corridor_45x40_l_turn_static_layout.tscn` /
  `rt_corridor_45x40_u_turn_static_layout.tscn` 端口数 4 < 需要 5）。
  这会拦掉 `run_verification_suite.sh` 的**全部**场景（预检在跑场景之前）。
  本次**未触及任何走廊文件**，该失败在 HEAD 状态下即存在，属 2026-10-28 存量红
  （上一轮开发记录 §7 遗留项 5 已记）。因此两个探针是**绕过套件预检单独跑的**。
- **`verify_tactical_inventory_minimap_flow` 的 23 项失败**全部是库存/背包拖拽
  （`Real quick-to-insurance drag signal was rejected` 等），无一条涉及小地图。
  用 `git stash` 对比基线：**基线 23 项、改动后 23 项，`diff` 完全一致** ⇒ 本次改动零新增失败。
- `verify_tactical_inventory_minimap_visual`（出图用）同样报交互失败，原因同上，**但截图已正常产出**，
  本轮用它作为视觉证据。
- 未跑 `core`/`full` 全量套件（被上述预检红拦住）。

## 7. 顺带记录（未改，仅登记）

- 右上角**世界时间 HUD**（`TowerDescent3D` 的 `WorldDateTimeHUD`，canvas x 1046.4..1265.6、y 38.4..78.4）
  与小地图矩形**存在压盖**。这是**既有情况** —— 旧小地图（x 907.2..1273.6、y 35.2..312）压得更狠。
  本次缩小后重叠范围反而变小了（右缘 1267.2 < 旧 1273.6，左缘 961.6 > 旧 907.2）。
  业主没提这件事，本轮**不动**；若后续要解决，方向是把时间读数上移或把小地图再降一点。
- 楼层标签（`高塔外层 · LIVE`，canvas y 9.6..30.4）与新小地图（y 40 起）**不重叠**，无需处理。

## 8. 本轮修正记录（写下来，防止后人重踩）

| 问题 | 现象 | 修法 |
|---|---|---|
| 截图 ≠ canvas 比例 | 直接拿截图像素当 canvas 像素会整体错位 | 先用控件左缘反推验证 1:1（907.2 == 1280-466×0.8），再换算 |
| 红框检测被 HP 血条污染 | 初筛得到 `x 24..1267 y 40..669` 的巨框 | 统计区域限制在 `x > 700` 的右上角 |
| 底板误判成别的 Panel | 以为是屏幕右侧一块大方块 | 逐列扫亮度找亮度骤降点，锁定 `FRAME_BG` 的 0.34 alpha |
| `--script` 模式读不到 autoload | `Identifier not found: BaseManager / AudioManager` | `--script` 下 autoload 在 `_initialize()` **之后**才注入；改用 `--scene` 跑探针 |
| 临时探针残留 `.uid` | `git status` 多出未跟踪文件 | 一并删除；本次所有临时脚本都已清理 |
| Windows 下直接 `open()` 写中文路径文档 | `OSError: [Errno 22] Invalid argument` | 写临时文件再 `os.replace()` 原子替换 |
