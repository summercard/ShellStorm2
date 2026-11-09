# 远征03 房间导航面退化成整块矩形（怪物贴墙走、不朝玩家来）

日期：2026-11-09。FeatureID：`ENEMY-AI`。按业主原话执行：**找根因、修根因，不打补丁**。

## 现象

业主截图：远征03 一间带内隔墙的大房间（回字/多隔断形态）。怪物刷在隔断内侧，
玩家从另一侧进来后，怪物**贴着墙面走**，不朝玩家推进。

## 根因

导航面（`RuntimeDetail/RuntimeNavigationRegion3D` 的 `NavigationMesh`）**只是一块覆盖整个
房间包围盒的四边形**，房内的隔墙/结构（`LayoutCollision`）完全不在导航图上。A* 认为墙不存在，
规划出穿墙直线；怪物按这条路径推进，物理上撞墙后只能靠 `move_and_slide` 沿墙面滑动 ——
「贴着墙走」正是这个退化路径的唯一可见后果。

这条路径是 `_build_runtime_navigation_surface()` 的**兜底分支**：

```
有 furnishing_navigation_polygons  → 按 0.5 m 网格（家具/墙感知）建面
否则                               → inset 1.45 的单块矩形
```

而「有 `furnishing_navigation_polygons`」在修复前几乎不可能成立，因为唯一的生成入口
`_request_furnishing_navigation_refresh()` 的守卫是：

```gdscript
if not has_meta("furnishing_navigation_polygons") or _furnishing_navigation_refresh_queued:
    return
```

即**必须先有这份 meta 才会去生成这份 meta**。它只由 `RoomPerimeterFurnishing`
（`perimeter_bay_layout` 美术壳）预置，或由道具状态变化顺手撞上。结果是：绝大多数房间
从开局到拆房都停在矩形兜底上。

### 实测（`scripts/probe_expedition03_nav_wallcross.gd`，seed 20261109，23 间房）

判据：房间内每 4 m 取采样点，两两 `NavigationServer3D.map_get_path()`，再对每一段在
y = 0.7（腰高，避开地板）打 layer 1 射线；命中即「路径穿墙」。命中 `HitReceiver`（敌人
受击体，也是 layer 1）的段落已排除。

| 房间 | 修复前 polygon 数 | 修复前穿墙段 | 修复后 polygon 数 | 修复后穿墙段 |
| --- | --- | --- | --- | --- |
| `hub_02` (45×40) | 1 | **1198** | 4835 | 0 |
| `hub_01` (45×40) | 1 | **1198** | 4833 | 0 |
| `boss` (50×40) | 1 | **940** | 5569 | 0 |
| `boss_foyer` (25×25) | 1 | 143 | 1370 | 0 |
| `fireplace_room_inj2` (25×25) | 1 | 134 | 1621 | 0 |
| `n07` (25×25) | 1 | 124 | 1586 | 0 |
| `n02`~`n06` / `room_01` / `exit` | 上百~上千 | 0 | 上千 | 0 |

`polys == 1` 与「穿墙上千段」严格一一对应；已经有网格面的房（`n02`~`n06`、`room_01`）
在修复前就是 0 —— 这组对照排除了「0.5 m 网格本身有问题」和「坐标帧错了」两种假设。

另外两个被排除的假设（留档，避免以后重复查）：

- **坐标帧错位**：不是。`walkable_navigation_polygons` 与模板 `footprint_polygon_m`
  逐点吻合（模板坐标减半个房间尺寸），`map_get_closest_point()` 对内岛采样点的返回偏差为 0。
- **多边形顶点不共享导致图不连通**：不是。把逐片顶点改成按位置去重后，穿墙数**一点没变**。
  去重仍保留（顶点数降到约 1/4，邻接关系由数据本身表达），但它在本次问题里不是变量。

⚠ 测量陷阱：`NavigationServer3D` 的图在场景加载后需要**几十个物理帧**才合并完成。
只等 2~3 帧时 `map_get_path()` 会返回单点，看起来像"图全断"，会把人引向完全错误的结论
（本轮就误判过一轮）。探针固定等 30 个物理帧 + `map_force_update()` 再测。

## 改动

`src/world3d/DungeonRoom3D.gd`：

1. `_build_content()` 末尾（家具/设施/易碎件全部落位之后）调用
   `_request_furnishing_navigation_refresh()` —— 导航面从此在**真实碰撞体就位后**重算，
   而不是在函数第一行用空房信息建一块矩形。
2. `_request_furnishing_navigation_refresh()` 去掉 `has_meta("furnishing_navigation_polygons")`
   这道自锁守卫，只保留排队去重。`_refresh_furnishing_navigation()` 本身已有
   `is_inside_tree() and _detail_built` 保护，不会在建房中途跑。
3. `_refresh_furnishing_navigation()` 在重建结果为空（一件阻塞体都没有：空房 / 屋顶）时
   **不写空数组**，保留矩形兜底 —— 否则会建出一块没有任何多边形的导航面，那间房的怪
   连直线兜底都没有。同时记 `furnishing_navigation_build_ms`（单次重建耗时，进房卡顿的直接成本）。
4. `_build_runtime_navigation_surface()` 的网格顶点按毫米量化去重并共享索引（见上「被排除的假设」，
   属数据结构改善，不是本 bug 的修复手段）。

矩形兜底分支保留，但从此只在「没有可用网格」时出现，不再是有隔断房间的默认形态。

## 验证

| 项目 | 命令 | 结果 |
| --- | --- | --- |
| 导航穿墙回归 | `godot --headless --path . --scene res://scripts/probe_expedition03_nav_wallcross.tscn` | 修复后 `NAV_WALLCROSS_OK`，exit 0；修复前（同一探针、同一 seed）`NAV_WALLCROSS_FAIL total_cross_segments=3737`，exit 1 |
| 断言有牙齿 | `git stash` 掉 `DungeonRoom3D.gd` 后重跑上面那条 | 确认**会失败**（不是恒绿），恢复后复跑通过 |
| 段落脚本错误 | 同上，日志过滤 `SCRIPT ERROR` / `Parse Error` | 0 条 |
| 单房重建耗时 | 探针读 `furnishing_navigation_build_ms` | 1.7 ~ 22.9 ms/房（25×25 最小，50×40 Boss 最大） |
| 文档契约 | `python scripts/check_documentation_contracts.py` | 无本次引入的新红项（既有 broken link 与 `verify_chest_appear_fx_prompt` 未注册属别处遗留；`openpyxl` 缺失为环境问题） |

未执行：**真实渲染下的战斗观感验收**（怪是否顺畅绕隔断追人）。本次只证明了导航面不再穿墙，
"怪物最终会走到玩家身边"要在真机跑一遍房间战确认，本记录不替代那一步。

## 遗留

1. **导航面多边形数量偏高**：45×40 房间约 4800 片 0.5 m 四边形，全关 23 间房合计约 4 万片。
   构建耗时已量（≤23 ms/房），但 `NavigationServer3D` 的合并与查询成本未单独测。
   下一步做贪心矩形合并（同一行同高的相邻格合并成一条矩形），可把片数压到几十~几百，
   构建与寻路成本一起降；合并后仍是凸多边形，语义不变。
2. **`use_edge_connections = false`**：房间 region 之间不建立边连接。房内追人不受影响，
   但「跨房间寻路」（例如追击逃到门外的玩家、跨房支援）会断。本轮未动，属独立议题。
3. **`_ensure_spawn_reach()` 的闸门**在探针里始终 `gate=false`（探针不触发刷怪入口），
   修复后 `_spawn_blockers` 才第一次有值（44~223 条）。闸门首次真正启用后是否会把某些房
   判成「覆盖率不足」并打警告，需要在真实刷怪流程里再确认一次。
