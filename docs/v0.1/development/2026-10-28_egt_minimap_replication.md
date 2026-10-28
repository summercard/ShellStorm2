# 右上角小地图改为「挺进地牢式」固定版图

日期：2026-10-28
触发：业主指令「和挺进地牢一致的地图，大小也要和信息也要一致」
性质：**显示形态替换**。不改关卡拓扑、不存档、不改玩法规则。

---

## 1. 指令与前置判断

| 时间 | 指令 | 结果 |
|---|---|---|
| 2026-09-28 | 右上角圆形雷达不再显示 | `minimap.visible = false`，代码保留 |
| 2026-10-28 | **不要恢复雷达；要的是和挺进地牢一致的地图** | 本文：换成 EGT 式固定版图 |

这两条不冲突：退役的是**圆形雷达**（玩家居中、地图反向平移、圆外裁掉），
恢复的是**矩形拼图版图**（固定缩放、右上贴边、房间钉在绝对坐标）。
所以 `2026-09-28` 的决定没有被推翻，被替换的是它当时唯一可选的那个形态。

> **口径提醒**：`README §1.1` 那段「只有 M 键全层地图」的表述已作废，同日改定。

## 2. 依据

反编译/实机资料整理见 [参考页](../reference/挺进地牢/minimap实现方式.md)，
可交互样张见 [minimap样张.html](../reference/挺进地牢/minimap样张.html)。

三条硬结论：

1. **位图拼图**：原作每间房一张小地图贴图，按世界坐标贴到固定缩放的平面上。
2. **固定缩放**：控制台变量 `s_map_view_scale` / `s_map_view_scale_big` 是两个全局常量，
   不随探索进度自适应；玩家改过的缩放跨层保留（`v1.0.6` 修的就是"每层重置"）。
3. **地图不动**：房间出现在绝对坐标，玩家只是其中一个点。

## 3. 实现落点

| 文件 | 改动 |
|---|---|
| `src/ui/DungeonMinimap3D.gd` | **重写渲染层**：删除圆形雷达、玩家居中、圆周裁剪；新增矩形拼图、固定缩放、房型图标、问号、绿色清理标记 |
| `src/world3d/Dungeon3D.gd` | `minimap.visible = true`；锚点改 `-466,44,-8,418`；15Hz 喂 `set_in_combat`；`_mark_room_cleared` 喂 `mark_room_cleared`；倒计时环 `z_index = 120` |
| `tests/verification/verify_tactical_inventory_minimap_flow.gd` | 两条方向相反的断言整体反转 + 新增固定缩放判据 |
| `tests/verification/verify_reference_hud_fate_visual.gd` | 「正方形且 ≤225px」改为 EGT 尺寸区间 + 三条渲染契约 |
| `tests/verification/verify_tower_descent_flow.gd` | `projection_mode` 改 `current_floor_tile_grid`，`holographic_scan` 反向断言 |

### 3.1 改动后的关键常量

```gdscript
ROOM_PX_PER_M  = 3.0                       # 25m 房 ≈ 75px（原作同档约 5% 屏宽）
MAP_MAX_SIZE   = Vector2(430, 360)          # 满层上限，超出则整层等比缩一次
CORNER_MARGIN  = Vector2(10, 8)             # 距控件右上角
WALL_PX        = 2.0                        # 房间描边
DOOR_GAP_PX    = 8.0                        # 门洞
DOOR_TICK_PX   = 3.0                        # 门两侧角标
```

### 3.2 与原作的两处**刻意偏差**（写清楚，避免后人以为抄全了）

| 偏差 | 原作 | 本工程 | 原因 |
|---|---|---|---|
| 缩放自适应 | 完全固定 | `min(3.0, 430/层宽, 360/层高)` | 我们单层跨度比原作大（远征01 是 6 间 25m 横排 = 200m），纯固定会吃掉半个屏幕。**夹紧值只按全层包围盒算一次，探索过程中不变** —— 保住了"探索不重缩放"这条本质 |
| 敌人红点 | 角落图**不画**敌人 | 保留红点 | 玩法信息不该倒退；红点与房型图标不在同一层语义 |

另有一处**已知重叠**（**已解决**）：原右上角倒计时环（`y 100..208`）与扩大的地图区域必叠。
当时的临时处理是环 `z_index = 120` 压在地图之上。**2026-10-28 业主裁定：环挪到画面左下方**
（锚点 `(0,1,0,1)`，设计值 `(40,-148)..(148,-40)`），两者分居两侧，结构上不再重叠。
若显示模式取 `NON_COMBAT`（原作默认），
战斗中地图隐藏、重叠消失。**待业主裁定是否把环挪到地图下方。**

## 4. 显示模式

代码已实现三档（对齐原作 `OPTIONS_MINIMAPSTYLE`）：

```gdscript
enum DisplayMode { ALWAYS, NON_COMBAT, NEVER }
```

- `ALWAYS` —— 一直显示，**当前默认**
- `NON_COMBAT` —— 战斗中隐藏，清房后自动恢复（原作默认档）
- `NEVER` —— 完全不画

判定口径：当前房还有活怪 = 战斗中，取数口与红点同一处（`_get_minimap_enemy_positions()`）。

**未完成**：设置界面里还没有这三档的入口。`set_display_mode()` 已就位，缺的是 UI 那一跳。

## 5. 信息层

房型 → 图标映射（`_icon_kind_for_type`）：

| 房型 | 图标 |
|---|---|
| `BOSS` | 金色骷髅 |
| `ELITE` | 橙色菱形 |
| `STORAGE` / `SCAVENGE` / `TREASURE` | 宝箱 |
| `SHOP` / `MERCHANT` | 蓝圆招牌 |
| `EVENT` | 紫色三角 |
| `UPGRADE` | 金色菱形 |
| `TRAP` | 橙色警示三角 |
| `EXTRACTION` | 撤离门 |
| `STAIRS_*` / `BASEMENT` / `ELEVATOR` | 阶梯 |
| `SAFE` / `START` / `ENTRANCE` | 圆环 |
| `COMBAT` | 无图标（与作同：普通战斗房只有房间块） |

已清理房间另外叠一个**绿色弹夹标记**（原作"已清 + 可传送"的图形），
状态唯一真源是 `DungeonRoom3D.cleared`，在 `_mark_room_cleared` 里喂进来。

## 6. 验收

### 6.1 开发期自检工具（保留）

两个脚本留在 `tools/`，都带 `_` 前缀标明是开发期工具、不进验收套件：

```bash
# 几何契约自检：真实面板尺寸下断言"不溢出 / 不随玩家移动 / 缩放恒定"
godot --headless --path . --script res://tools/_minimap_selfcheck.gd

# 真实渲染出图（SubViewport，非 headless）
godot --path . --script res://tools/_minimap_render.gd
# → outputs/verification/egt_minimap_corner.png / _full.png
```

> **为什么不用窗口直接截图**：2026-10-28 实测 `DisplayServer.window_set_size()`
> 之后仍然只渲染 210×174，图被裁掉一大半。`SubViewport` 才是可靠路径。

### 6.2 套件运行结果

| 项 | 结果 |
|---|---|
| `run_verification_suite.sh core` | **exit 1，未跑到场景**：preflight 的 `check_expedition03_room_layouts.py` 报 `rt_corridor_45x40_l/u_turn` 端口 4 < 需要 5。**这是 expedition03 的存量问题，与本次改动无关**（本次没碰 corridor 壳体） |
| `verify_tactical_inventory_minimap_flow` | exit 1。**小地图断言 0 失败**；25 条失败全部来自背包拖拽 / 血条 / 6 列布局等其它用例（存量红） |
| `verify_reference_hud_fate_visual`（真实渲染） | **exit 0**。小地图三条断言全通过 |
| `verify_tower_descent_flow` | exit 0，但日志首行即 `TOWER_DESCENT_FLOW_MIGRATED`，**场景短路、断言未执行** ⇒ 记为**未执行**，不算通过 |
| 非预期脚本错误 | `Parameter "material" is null` 若干，属既有噪声（HUD 投影材质），非本次引入 |
| 未执行项 | `verify_tower_descent_flow` 的 minimap 断言（场景已迁移）；`core` 全量场景（preflight 拦截） |

### 6.3 出图结论

`outputs/verification/egt_minimap_corner.png`（真机面板 366×277）：

- 满层 125×60m 自动夹到 `ppm = 2.803`，实绘 350×168，**不溢出面板**
- 房间是"填充 + 1px 描边 + 门洞断开 + 门侧角标"，走廊是 2px 细线
- 已清房有绿色弹夹标记，未探索邻接房是洋红问号，玩家是白色三角+青色描边
- 地图**不随玩家移动**（同场景两次取样，`room_01` 屏幕中心不变）

`egt_minimap_full.png`（M 键全图）：同一套渲染 + 房型名标注，按内容区等比铺满。

## 7. 存量待办

1. 设置界面接入三档显示模式。
2. ~~倒计时环与地图的布局冲突待裁定~~ **已裁定并落地（2026-10-28）**：环挪到左下角。
3. 原作 `path_density`（走廊画成点线、疏密可调）未做 —— 我们现在是实线。
4. 原作 TAB 全屏地图的图例区、可悬停图标未做。
5. `check_expedition03_room_layouts.py` 的端口数失败是存量红，拦掉了 `core` 全量套件；
   它不属本次范围，但没有它就没法跑全量回归。

---

## 8. 本轮修正记录（写下来，防止后人重踩）

| 问题 | 现象 | 修法 |
|---|---|---|
| `MAP_MAX_SIZE` 写死 430×360 | 面板经 `HUD_UI_SCALE` 只有 366 宽，满层会溢出 | 改成按**面板实测尺寸**夹紧，常量只表示设计密度 |
| 角落盒过高 | 楼层"宽而扁"，374 高在底部留一条空黑 | 收到 346 高；贴顶而非纵向居中（两种都出图对比过） |
| 图标小到看不清 | 问号 3px 散成点 | 改 5×7 像素点阵 |
| 商店图标像字母 i | "圆+竖线"被读成 i | 改"柜台+招牌"两段矩形 |
| 首版断言给了宽区间 | 300..420 差 0.8px 误判一次 | 改为按设计盒 `458×346 × 0.80` **精确**断言（±2px） |

