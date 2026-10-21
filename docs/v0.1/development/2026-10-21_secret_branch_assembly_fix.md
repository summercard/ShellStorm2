# 2026-10-21 支线房间「会掉落」+ 壳装歪：承重地板与壳朝向

业主：「我可以进去了，但是装配的房间有问题。会掉落。支线的。然后 08 号房间的装配也有问题。检查一下。」

两条现象背后是**同一个前提被漏掉了**：主路房间的「脚下实心」与「壳摆正」都不是房间自己保证的，
而是主路上游那两条链给的。子图整条链挂在主图外 +1000 m、且不在 `_records` 里，两条链都够不着。

---

## 1. 症状与量化

探针 `probe_room_assembly_health`：对每一间已建好的房，1 m 网格向下打射线（从地面 +2.2 m 打到 −6 m，
命中高度必须在地面 ±0.6 m 内），数「打不到任何东西」的格。

| 房间 | 共享房壳 | 修前地板空洞 | 修前墙探针打空 |
|---|---|---|---|
| `secret_0_0` | `corridor_45x40` | **1193 / 1800（66.3%）** | 155 / 170 |
| `secret_1_1` | `bridge_60x50` | **1408 / 1800（78.2%）** | 130 / 180 |
| `secret_1_2` | `corridor_45x40` | **1193 / 1800（66.3%）** | 158 / 170 |
| `secret_0_1` | `office_60x70` | 0 | 16 / 140 |
| `secret_1_0` | `office_60x70` | 0 | 18 / 140 |
| 主路 room_01 / room_03 / room_08 | — | 0 | 50 / 10 / 40 |

为什么 `office` 壳没事、`corridor`/`bridge` 壳掉得厉害：**地砖覆盖率**不同。
`office_60x70` 30×40 = 1200 ㎡，48 块 5 m 砖 = 1200 ㎡（满铺）；`corridor_45x40` 45×40 = 1800 ㎡，
42 块 = 1050 ㎡（58%）；`bridge_60x50` 更少。

## 2. 根因一：主路脚下实心来自整层 `FloorSupport`，子图够不着

`_print_floor_sources`（`probe_room_shell_diff`）把 room_01 的 440 个俯视采样点按「命中物来源」归类：

```
  打空 0 / 440
    330 格  ← Blocks/Expedition/Expedition2/FloorSupport   (y+0.00)
    102 格  ← AuthoredLayoutArtRoot                        (y+0.00)
      8 格  ← AuthoredLayoutArtRoot                        (y+1.0~2.2)
```

**主路 75% 的脚下实心由 `TowerFloorStage3D._build_support()` 铺的大板提供**，美术地砖只补剩下的部分。
子图挂在 +1000 m（`BRANCH_ORIGIN_X_M`），那块板按 `_floor_world_rect()` 只铺主图范围 ⇒ 子图虚空。

## 3. 根因二：子图壳的朝向回落到 0，整间房转置

`DungeonRoom3D._static_layout_alignment_delta_deg()` 有两条路：

1. 有「布局实例清单」（`authored_layout_instances`）⇒ 拿清单与关卡房表做几何配准。主路 12 间走这条。
2. 清单为空 ⇒ 回落到 `get_meta("template_rotation_deg")`。主路房由 `TowerDescent3D` 从房表注入；
   **子图房是 `SecretBranch3D` 手建的，从来没设过 ⇒ 恒 0。**

于是 `corridor_45x40` 的壳（烘焙 40×45）被原样塞进 45×40 的房间：
四面墙整体偏出 2.5 m、**烘焙门墙落在北墙而房间的门在东/西墙**（`secret_0_0` 实测墙探针 158/170 打空）。
`bridge_60x50` 更糟：壳烘焙 30×60、房间是转置姿态 60×30，直接量到 60.2×60.3。

## 4. 修法

### 4.1 承重地板 `SecretBranch3D._ensure_floor_support()`

每条子图链一个 `SecretFloorSupport`（`StaticBody3D`），每间房一个 `BoxShape3D`，
**顶面贴 y = 0**（盒心下移半个厚度）。口径与主路 `FloorSupport` 逐项对齐：

- 层 1 / 掩码 0；
- `PROCESS_MODE_ALWAYS`（承重板不能随流送窗口退出物理空间）；
- 厚度 0.30（= `TowerFloorStage3D.FLOOR_THICKNESS`）。

桥房 12 m 下沉坑同样被封在下面 —— **与主路一致**（主路 `FloorSupport` 也不给坑开洞），
且坑按设计是「下层不可达、纯装饰」，掉进去反而卡死。

### 4.2 壳朝向 `SecretBranch3D._shared_shell_alignment_deg()`

两条判据，都能量：

1. **足迹**：把壳实例化一次（不建门、不跑物理），逐件 `MeshInstance3D` 沿父链乘到壳原点取 AABB
   （跳过 `editor_preview_only` 子树），得到美术足迹；四个候选角里只留「与房间 `size` 吻合（±1.5 m）」的。
2. **门侧**（破平局，90° 与 270° 足迹相同）：壳里烘焙的门墙朝向写在
   `snapshot_tower_wall_door_offset_<side>`，把它按候选角转过去，落在本间真的要开门的边上的越多越好。

算完在 `ensure_shell_built()` **之前**写进 `template_rotation_deg`（`_align_static_layout_to_room()`
按它转壳，门洞与门扇是它之后才建的 —— 晚一步就是「墙转过去了、门还按旧方位开」）。

实测结果：`corridor` 壳 270°/90°、`bridge` 壳 90°、`office`/`extraction` 壳 0°；
足迹误差全部 ≤ 0.6 m，墙探针打空从 155 降到 55（主路 room_01 是 50）。

## 5. 验收

- 断言 **26 → 28**：
  - **A27** 子图每一间房脚下必须实心（1 m 网格射线不许有空格）+ 承重盒数量 ≥ 房间数；
  - **A28** 子图房壳必须摆正（美术足迹 = 本间尺寸；声明转角 = 壳根实际转角）。
- 反向对照两组，均精准变红：
  - 拆掉 `_ensure_floor_support()` ⇒ `A27 承重盒 0 块 vs 7 间房` +
    `A27 脚下有洞：secret_0_1 空 508/1800, secret_0_2 空 750/1800, secret_1_0 空 750/1800`；
  - 让 `_shared_shell_alignment_deg()` 返回 0 ⇒ `A28 secret_0_1 美术 60.2×60.3 vs 房间 60.0×30.0` 等 3 间报红。
- 成功行：
  `SECRET_BRANCH_FLOW_OK 位点=4 槽位固定 门洞不重合 门板可见 落点在房内 门副本=已清 脚下实心 壳已摆正 生成规则=确定 传送=可达 隔离=通过 编成=5强化+2普通 存档=往返一致`

## 6. 坑

- **A28 第一版报「差 360°」**：`deg_to_rad` → `rad_to_deg` 往返有 1e-8 级残差，
  `fposmod(90 − 90.0000001, 360)` 直接变成 359.999999。角度差必须取**最小有向夹角**
  （`absf(fposmod(d + 180, 360) − 180)`）。
- **A27 第一版比错了分母**：一个分支根下只有**一块** `SecretFloorSupport`，
  子节点是「每间房一个盒」；第一版拿某一块的子节点数去比「房间总数」，于是 7 间房报「3 块承重盒」。
- **量足迹不能算上隐藏件**：`_build_shell` 会把 `editor_preview_only` 子树置 `visible = false`，
  进树后量到 `office` 壳 40.3、离树量到 41.1（差一件预览件）⇒ 容差取 1.5（转错 90° 的候选至少差 4 m）。
- 代价：每种模板的壳会**多实例化一次**（离树，只为量足迹，缓存在 `_shell_footprints`）。

## 7. 遗留

- 08 号房间的「装配问题」尚未定位（见 §8）。
- 主路 `FloorSupport` 同样把 `room_05` 桥房的 12 m 坑封住（玩家踩的是不可见承重板）——
  属既有行为，本轮没动。
- 子图房仍不在 `_records` 里，`_records` 驱动的流送/小地图/拓扑校验都看不到它们（设计如此）。

## 8. 08 号房间的实测数据（尚未定论）

在业主当前存档态（整层旋转 180°）下：

- 地板：**0/1800 洞**；壳足迹 45.6×40.5 vs 房间 45×40（吻合）；壳根已转 −90°；
- 墙探针打空 40/170（south 25 + west 15），**同房型的 room_01 是 50/170** —— 两者同一量级，
  说明是 `corridor_45x40 l_turn` 的 L 型轮廓本身（不是缺墙）；
- 美术件：room_08 是 room_01 的**180° 镜像**，比 room_01 少 13 件道具
  （3 件 `north_server`、`broken_core`、5 台 `service_cart`、2 组 `server_gallery`、1 台 `console`、1 个 `crate`），
  但两边的 `layout_instance_total` 都写 123、`room_type_component_count` 都写 47 —— **清单与实际件数对不上**，
  这条是唯一还没解释的硬数据。
