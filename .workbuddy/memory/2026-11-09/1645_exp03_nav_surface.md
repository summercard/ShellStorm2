# 1645 远征03 房间导航面退化成矩形（怪物贴墙走）

## 业主报的现象

远征03 回字/多隔断房间：怪刷在隔断内侧，玩家进来后怪**贴墙走、不朝玩家来**。要求找根因修掉。

## 根因

`DungeonRoom3D._build_runtime_navigation_surface()` 的兜底分支：没有
`furnishing_navigation_polygons` 就建**一块覆盖整个包围盒的四边形**。而这份 meta 的唯一生成入口
`_request_furnishing_navigation_refresh()` 有自锁守卫
`if not has_meta("furnishing_navigation_polygons"): return` —— **必须先有才会生成**。

⇒ 绝大多数房间从开局到拆房都停在矩形上，房内隔墙不在导航图里 ⇒ A* 规划穿墙直线 ⇒
怪撞墙后靠 `move_and_slide` 沿墙滑 = 「贴墙走」。

## 实测（seed 20261109，23 间房，穿墙判据 = 路径段 y=0.7 射线打 layer 1）

| 房间 | 修复前 polys | 修复前穿墙段 | 修复后 polys | 修复后穿墙段 |
|---|---|---|---|---|
| hub_01 / hub_02 (45×40) | 1 | 1198 / 1198 | 4833 / 4835 | 0 |
| boss (50×40) | 1 | 940 | 5569 | 0 |
| boss_foyer | 1 | 143 | 1370 | 0 |
| fireplace_room_inj2 | 1 | 134 | 1621 | 0 |
| n02~n06 / room_01 / exit | 上千 | 0 | 上千 | 0 |

`polys==1` 与「穿墙上千」严格对应；已有网格的房修复前就是 0 —— 这组对照排除了
「网格算法有问题」和「坐标帧错了」。

## 两个被排除的假设（重要，别再查）

- **坐标帧错位**：否。`walkable_navigation_polygons` 与模板 `footprint_polygon_m` 逐点吻合。
- **顶点不共享导致图不连通**：否。按位置去重后穿墙数一点没变。去重仍保留（顶点降到 1/4），
  但它不是本次变量。

⚠ **测量陷阱**：`NavigationServer3D` 的图在加载后要**几十个物理帧**才合并完。只等 2~3 帧时
`map_get_path()` 返回单点，看起来像"图全断" —— 本轮据此误判过一轮（还写了一段错误的因果注释）。
探针固定等 30 物理帧 + `map_force_update()`。

## 改动（`src/world3d/DungeonRoom3D.gd`）

1. `_build_content()` 末尾（家具/设施/易碎件全落位后）触发一次导航面重建 —— 不再用空房信息建矩形。
2. `_request_furnishing_navigation_refresh()` 去掉 `has_meta(...)` 自锁守卫，只留排队去重。
3. `_refresh_furnishing_navigation()` 重建为空时不写空数组（保留矩形兜底，否则那间房连直线兜底都没了）；
   新增 `furnishing_navigation_build_ms` 计时 meta。
4. `_build_runtime_navigation_surface()` 顶点毫米量化去重（数据结构改善，非修复手段）。

## 验收

- 新增 `scripts/probe_expedition03_nav_wallcross.{gd,tscn}`，**会失败的门禁**：
  修复后 `NAV_WALLCROSS_OK` exit 0；`git stash` 掉改动后 `NAV_WALLCROSS_FAIL total_cross_segments=3737` exit 1。
  已确认断言有牙齿（不是恒绿）。
- 单房重建 1.7~22.9 ms（25×25 最小，50×40 Boss 最大）。
- 无 `SCRIPT ERROR` / `Parse Error`。
- `check_documentation_contracts.py` 无本次新增红项。

## 遗留

1. 导航面片数偏高（45×40 约 4800 片，全关约 4 万），下一步做贪心矩形合并压到几十~几百。
2. 房间 region `use_edge_connections = false` ⇒ 跨房寻路断（房内追人不受影响），独立议题。
3. `_ensure_spawn_reach()` 闸门在探针里始终 `gate=false`；修复后 `_spawn_blockers` 才首次有值
   （44~223 条），首次真正启用后要在真实刷怪流程里确认不误报"覆盖率不足"。
4. **未做真实渲染的战斗观感验收**：只证明了导航面不穿墙，怪最终能否顺畅绕隔断走到玩家身边要真机跑一次。

记录：`docs/v0.1/development/2026-11-09_expedition03_room_navigation_surface.md`
