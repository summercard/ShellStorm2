# 远征01 组件面数现状（2026-11-15）

## 口径与取证方式

本节两个数必须分开看，混用会得出相反结论：

| 量 | 含义 | 取法 |
|---|---|---|
| **唯一 GLB 面数** | 磁盘/显存常驻几何量。同件被摆放 N 次，网格资源仍只一份 | 解析 303 个 GLB 的 JSON chunk，按场景节点展开求和 |
| **运行时全树面数** | 每帧提交给 GPU 的三角数。同一件 ×N 实例就乘 N | `tools/_exp01_tri_scene_probe.tscn` 真实加载 `ExpeditionLevel01_3D.tscn`，遍历全部 `MeshInstance3D` 累加面与可见面 |

静态口径（逐房 TSCN 按实例加权）只用于定位「哪间房的哪个组件重」，与运行时口径差 <5%，两者互为校验。

工具留在工程内：
- `_scratch/exp01_tri_report2.py` —— 静态逐房 / 逐资产加权
- `_scratch/tri_uniq.py` —— 唯一 GLB 面数、LOD 探测
- `tools/_exp01_tri_scene_probe.{gd,tscn}` —— 运行时真实加载量

## 结论

1. **唯一几何 99.5 万面，运行时 591 万面 —— 实例放大 5.94 倍。**
2. **地砖一项吃掉 23% 的面与 54% 的网格实例。** `floor_tile_r01_c02` 单块 3028 面 / 24 个 mesh，
   240+242 块铺满全场：136 万面、12 288 个 `MeshInstance3D`。一块 4.94 m 的平地在 3028 面
   （≈122 面/㎡）是明显的过度细分 —— 其中 `地砖_R01_C02_附着细节_主体` 一块就 1974 面。
3. **Boss 房单独占 126.7 万面（21.4%）**，其中 `matrix_bay_5m` 摆了 84 份 × 6132 面 = 51.5 万面。
4. **`tower_descent_3d` 的墙体系列没有走过 v034 那轮优化**：`env_tower_wall_solid_5m` 5319 面 ×79、
   `env_tower_corner_l_5m` 10638 面 ×28、`env_tower_wall_door_5m` 15734 面 ×12，合计 90.7 万面（15.3%）。
   同一关的远征自有件（`wall_t970_5m` 848 面、`door_wall` 844 面）已经是优化后水平，二者相差 5～6 倍。
5. **全部资产 0 LOD，全工程 0 个 `OccluderInstance3D`。** 几何只受逐 mesh 视锥剔除保护；
   `PlayerVision3D` 的剔除只作用于 `enemy_3d` / `ground_loot_3d` / `service_station_3d` 等
   玩法目标组，不隐藏房间美术。

## 每房（运行时实测，含支线子图共 17 间）

| 房间 | 流状态 | 网格 | 面 | 可见面 |
|---|---|---|---:|---:|
| room_01 | DATA_ONLY | 2291 | 179 943 | 179 743 |
| room_02 | DATA_ONLY | 1159 | 338 349 | 338 149 |
| room_03 | DATA_ONLY | 1342 | 405 495 | 405 259 |
| room_04 | DATA_ONLY | 2379 | 247 059 | 246 859 |
| room_05 | DATA_ONLY | 1495 | 512 507 | 512 307 |
| room_06 | DATA_ONLY | 1155 | 337 713 | 337 477 |
| room_07 | DATA_ONLY | 659 | 162 338 | 162 102 |
| room_08 | DATA_ONLY | 2120 | 182 431 | 182 231 |
| room_09 | DATA_ONLY | 1321 | 271 509 | 271 309 |
| room_10 | DATA_ONLY | 1162 | 349 047 | 348 811 |
| boss | DATA_ONLY | 1038 | 1 266 618 | 1 266 618 |
| extraction | DATA_ONLY | 665 | 162 731 | 160 843 |
| start | ACTIVE | 287 | 184 908 | 171 234 |
| secret_0_0 | SHELL_READY | 1339 | 403 652 | 403 452 |
| secret_0_1 | SHELL_READY | 1494 | 539 056 | 538 856 |
| secret_0_2 | SHELL_READY | 2288 | 190 521 | 190 321 |
| secret_extraction_0 | SHELL_READY | 668 | 178 688 | 176 800 |
| **合计** | | **22 862** | **5 912 565** | **5 892 371** |

「可见面 / 总面」几乎 1:1：`DATA_ONLY` 只卸载 `RuntimeDetail`，布局壳体（墙、地砖、房型陈设）
常驻可见。所以 17 间房的美术同时在场，靠视锥剔除挡。

## 面数去向（静态加权，13 主路房 450.8 万）

| 类别 | 面 | 占比 |
|---|---:|---:|
| 房型陈设 | 1 846 371 | 41% |
| 地砖 / 楼板 | 1 358 708 | 30% |
| 墙面 / 门洞 / 角件 | 1 080 475 | 24% |
| 天花 / 管线 / 灯具 | 145 212 | 3% |

## 最重的 10 件（累计面，含实例）

| 累计面 | 实例 | 单件 | 网格/件 | 资产 |
|---:|---:|---:|---:|---|
| 732 776 | 242 | 3028 | 24 | `battle/.../floor_tile_r01_c02` |
| 625 920 | 240 | 2608 | 27 | `battle/.../floor_tile_r01_c01` |
| 515 088 | 84 | 6132 | 2 | `boss_room_02/matrix_bay_5m` |
| 420 201 | 79 | 5319 | 1 | `tower_descent_3d/env_tower_wall_solid_5m` |
| 297 864 | 28 | 10 638 | 1 | `tower_descent_3d/env_tower_corner_l_5m` |
| 261 248 | 16 | 16 328 | 2 | `office_room/work_cluster` |
| 188 808 | 12 | 15 734 | 1 | `tower_descent_3d/env_tower_wall_door_5m` |
| 101 760 | 24 | 4240 | 1 | `boss_room_02/deck_armor_5m` |
| 86 400 | 100 | 864 | 1 | `boss_room_02/underframe_beam_5m` |
| 60 480 | 10 | 6048 | 1 | `boss_room_02/stair_flight_5m` |

## 可动的三处（按收益/风险排序）

1. **地砖降到「底板 + 法线贴图」量级。** 现有 3028 面里 1974 面是 `附着细节`。按 v034 口径
   （`T_after <= T_before/5`）压到 ≤600 面，482 块省约 107 万面（占全关 18%）、
   同时每块 mesh 数从 24 降到个位数，网格实例从 1.2 万降到 2 千以内 —— **收益主要在 draw call，不在三角**。
2. **`tower_descent_3d` 墙/角/门墙走一遍 v034。** 5319 / 10 638 / 15 734 面对 5 m 构件属未优化档，
   按同族已优化件（844～848 面）的量级压，79+28+12 个实例可省 60～70 万面。
3. **Boss `matrix_bay_5m` 只摆必需段。** 84 份共 51.5 万面；该件自带 2894 面自发光副网格，
   若把 84 份里重复的「后方」段合批或改单面片，可省 20～30 万面。

三条都动结构（改 GLB 与原碰撞/UV 契约），需按资产批次流程走优化包 + 账本登记 + 真实渲染复核，
不在本轮实施。

## 复现

```bash
~/.workbuddy/binaries/python/envs/default/Scripts/python.exe _scratch/exp01_tri_report2.py
~/.workbuddy/binaries/python/envs/default/Scripts/python.exe _scratch/tri_uniq.py
rm -rf /i/ss2_probe_appdata/tri && mkdir -p /i/ss2_probe_appdata/tri
APPDATA=I:/ss2_probe_appdata/tri LOCALAPPDATA=I:/ss2_probe_appdata/tri \
  /c/Users/zhuangmenghong/bin/godot --headless --path . res://tools/_exp01_tri_scene_probe.tscn
```
