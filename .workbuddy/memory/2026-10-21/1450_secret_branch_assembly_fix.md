# 14:50 支线房间「会掉落」+ 壳装歪：承重地板与壳朝向

业主：「我可以进去了，但是装配的房间有问题。会掉落。支线的。然后 08 号房间的装配也有问题。检查一下。」

## 结论：不是「房间建坏了」，是**两条上游保障子图够不着**

| 保障 | 主路谁给的 | 子图为什么没有 |
|---|---|---|
| 脚下实心 | `TowerFloorStage3D._build_support()` 的整层 `FloorSupport` 大板（room_01 实测 **330/440 采样点踩它**，只有 102 格踩美术地砖） | 子图挂主图外 +1000 m（`BRANCH_ORIGIN_X_M`），那块板按 `_floor_world_rect()` 只铺主图 |
| 壳摆正 | `DungeonRoom3D._static_layout_alignment_delta_deg()` 拿「布局实例清单 × 关卡房表」几何配准 | 子图房不在 `_records` 里、没清单 ⇒ 回落到 `template_rotation_deg`，而手建的房从没设过 ⇒ **恒 0** |

量化（1 m 网格向下射线，`probe_room_assembly_health`）：`corridor_45x40` 壳的房间脚下 **66.3%**
（1193/1800）是虚空，`bridge_60x50` 壳 **78.2%**；`office_60x70` 壳 0 —— 差别只在地砖覆盖率
（30×40=1200㎡ ↔ 48 块 5 m 砖满铺；45×40=1800㎡ ↔ 42 块只 58%）。

## 修法

1. `SecretBranch3D._ensure_floor_support()`：每条子图链一块 `SecretFloorSupport`
   （`StaticBody3D`），每间房一个 `BoxShape3D`，**顶面贴 y=0**；层 1 / 掩码 0 /
   `PROCESS_MODE_ALWAYS` / 厚度 0.30 —— 每项都对齐主路 `FloorSupport`。
2. `SecretBranch3D._shared_shell_alignment_deg()`：离树实例化一次壳量**美术足迹**
   （跳过 `editor_preview_only`），只留与本间 `size` 吻合（±1.5 m）的候选角；
   90°/270° 足迹相同时按壳里 `snapshot_tower_wall_door_offset_<side>` 的**烘焙门墙朝向**破平局。
   在 `ensure_shell_built()` **之前**写进 `template_rotation_deg`（门洞/门扇是它之后建的）。

实测转角：`corridor` 壳 270°/90°、`bridge` 壳 90°、`office`/`extraction` 0°；
墙探针打空 155 → 55（主路 room_01 是 50）。

## 验收

断言 **26 → 28**：A27（脚下实心 + 承重盒数 ≥ 房间数）、A28（壳足迹 = 本间尺寸 + 声明角 = 壳根实际角）。
两组反向对照精准变红：拆承重板 ⇒ `secret_0_1 空 508/1800`；壳不摆正 ⇒ `secret_0_1 美术 60.2×60.3 vs 房间 60.0×30.0`。
成功行里新增「脚下实心 壳已摆正」两段。

## 坑（都踩过）

- 角度差必须取**最小有向夹角**：`deg_to_rad→rad_to_deg` 的 1e-8 残差让 `fposmod(diff,360)` 变成 360.0，报「差 360°」。
- 一个分支根下只有**一块**承重体，子节点是「每间房一个盒」；拿子节点数去比房间总数会报「3 块 vs 7 间」。
- 量足迹不能算隐藏件（`editor_preview_only`）：office 壳进树 40.3 / 离树 41.1 ⇒ 容差取 1.5（转错 90° 至少差 4 m）。

## 08 号房间：数据都正常，但未定论

业主存档态（整层 180°）下实测：地板 **0/1800 洞**、壳足迹 45.6×40.5 vs 45×40 ✓、壳根已转 −90°、
墙探针 40/170（同房型 room_01 是 50/170，同量级 ⇒ L 型轮廓本身）。
唯一异常：room_08 是 room_01 的 180° 镜像，**比 room_01 少 13 件道具**（3×`north_server`、`broken_core`、
5×`service_cart`、2×`server_gallery`、1×`console`、1×`crate`），但两边 `layout_instance_total` 都写 123。
⇒ 已向业主确认「具体是哪样不对」，等回话再动。

## 遗留

- `verify_full_3d_game_flow` 在本工作树里报「Player eight-state whitelist」与「node budget 3313 > 2780」，
  `verify_3d_only_project_structure` 报「Main scene is not the formal 3D entry（StartupLoadingScreen）」——
  全部与本轮改动无关（改的是远征支线，不动塔楼主流程与 `project.godot`），属**既有**红项。
- 主路 `FloorSupport` 同样把 room_05 桥房 12 m 坑封住（玩家踩不可见承重板），既有行为未动。
