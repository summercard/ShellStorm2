# 远征关卡02 · 通用组件库 v015

低矮（3m）墙体系 + 通高（11.9m）件 + 封顶/地板/地砖。为远征关卡02「破败旅馆」新开的通用组件库。共 8 件。

## 为什么要有这一版

战局通用组件库（`ENV-BATTLE-COMMON-WALL-STANDARD-5M`）是 **11.9 m 高**的墙，而远征02
的长廊 / 客房 / T 字横廊 / 支廊**全部是 3 m 净高**（用户 2026-10-12 裁定：
「下面的层级不会有挑高层，都是 3 米高的房间和走廊」）。高度对不上，**不能复用**。

同时本版补上**封顶件** —— 按 `06 §7.3.1` 封顶件硬契约，顶盖必须带 `layer=1` 碰撞，
否则「房间不受太阳照射」不成立。

## 组件清单

| slug | AssetID | 结构尺寸（Blender XYZ, m） | 占位尺寸 | 三角面 | 在役件数 | 用途 |
|---|---|---|---|---|---|---|
| `wall_standard_5m_h3` | `ENV-EXPEDITION-COMMON-WALL-STANDARD-5M-H3` | 5.000 × 0.300 × **3.000** | 同左 | 12 | 195 | 3m 实墙，一槽一件 |
| `wall_door_5m_h3` | `ENV-EXPEDITION-COMMON-WALL-DOOR-5M-H3` | 5.000 × 0.300 × 3.000（门洞 2.2 × 2.5）| 同左 | 36 | 26 | 3m 门墙，左右门垛 + 门楣（楣高 0.20） |
| `wall_standard_5m_h12` | `ENV-EXPEDITION-COMMON-WALL-STANDARD-5M-H12` | 5.000 × 0.300 × **11.900** | 同左 | 12 | 16 | 通高实墙（= 项目基线），只挑高前厅用 |
| `wall_door_5m_h12` | `ENV-EXPEDITION-COMMON-WALL-DOOR-5M-H12` | 5.000 × 0.300 × 11.900（门楣 9.100）| 同左 | 36 | 1 | 通高门墙 |
| `wall_collapse_5m_h12` | `ENV-EXPEDITION-COMMON-WALL-COLLAPSE-5M-H12` | 可视 5.000 × 0.300 × 9.100 | **5.000 × 0.300 × 11.900** | 12 | 1 | 坍塌门洞，占满一整格 |
| `ceiling_deck_5m` | `ENV-EXPEDITION-COMMON-CEILING-DECK-5M` | 5.000 × 5.000 × 0.260 | 同左 | 12 | **270** | **封顶模块（含遮光碰撞）** |
| `floor_base_5m` | `ENV-EXPEDITION-COMMON-FLOOR-BASE-5M` | 5.000 × 5.000 × 0.260 | 同左 | 12 | 297 | 地板底层模块 |
| `floor_tile_5m` | `ENV-EXPEDITION-COMMON-FLOOR-TILE-5M` | 4.940 × 4.940 × 0.040 | 同左 | 12 | 297 | 通用地砖（5m 格内可替换面砖） |

原点契约一律 **底面中心**；Godot 正面方向 **-Z**（墙长沿 X、墙厚沿 Z），与战局通用组件同口径。
坐标口径与白盒 `build_expedition02_whitebox_v001.py` **逐值一致**，房间 TSCN 才能直接消费。

## 路径

```text
原始库（不得改写）
  art_source/environments/tower_zones/expedition/source/common_components/v015/
    expedition_common_components_source_v015.blend

独立优化派生（持久保留，GLB 只从这里导出）
  …/v015/export/v015/expedition_common_components_source_v015_optimized.blend

组件清单
  …/v015/component_packages_v015/<slug>/asset_manifest.json
  …/v015/component_catalog_v015.json

运行 GLB（稳定路径，不带版本号）
  assets/art/environments/tower_zones/expedition/components/common_components/<slug>/<slug>_visual_top3d.glb

运行包装（稳定路径，不带版本号）
  assets/art/environments/tower_zones/expedition/runtime/common_components/<slug>/<slug>_root_top3d.tscn

验收图
  …/v015/qa/expedition_common_components_v015_验收图.png
```

## 生成与验证脚本

| 脚本 | 作用 |
|---|---|
| `scripts/blender/build_expedition_common_components_v015.py` | 建库 → 另存优化派生 → 从优化文件导出 GLB → 写清单。含源保护断言 |
| `scripts/build_expedition_common_component_prefabs_v015.py` | 写包装 TSCN + 打色盘导入契约 + **封顶遮光契约断言** |
| `scripts/verify_expedition_common_components_v015.gd` | Godot 侧独立加载验证 |
| `scripts/blender/render_expedition_common_components_v015.py` | 验收图（资产墙） |
| `scripts/register_expedition02_common_components_ledger.py` | 登记进场景分账本 |

## 优化与源保护（02b「全组件优化与独立另存门禁」）

全部 5 件都执行了：`delete_loose` → `dissolve_degenerate(1e-5)` → `normals_make_consistent(outside)`
→ `remove_doubles(1e-5)` → `triangulate` → `assign_palette_uv`。

**减面率 R = 0，这是本类的正确结果、不是跳过优化**：纯轴对齐方块几何，无重复面、无零面积面、
无冗余细分 ⇒ 清理零处理量；三角化把 N 个四边形变成 2N 个三角形，面数**增加**但那是导出格式要求。
`triangles_before` 口径按 02b 要求取「四边形数 × 2」，**未**拿 polygon 数直接当 triangle 数
（第一版这么写过，会算出 −100% 这种假减面率）。

源保护：`source_sha256_before == source_sha256_after` 断言通过；`source_path != optimized_path`；
优化文件存在且可重开；GLB 明确从优化文件导出。

## 封顶遮光契约

`ceiling_deck_5m` 的包装场景里，`CollisionBody.collision_layer = 1`，碰撞盒 `BoxShape3D(5, 0.26, 5)`
盖满整个槽。这是本件成立「封顶 = 不受日照」的硬条件。

消费方是 `src/enemy3d/EnemyIllumination3D._evaluate_sunlight`：它**不读画面、不读材质**，
只从怪物身体采样点沿主太阳方向打一条 `occlusion_mask = 1` 的物理射线。
**能投阴影 ≠ 能挡住这条射线** —— 所以「封顶天花板画面上有影、僵尸照样晒太阳」的根因
永远是「这件顶盖的 prefab 里没有碰撞体」，而它**不报错**。

项目里既有这道契约的实现在 `scripts/generate_expedition_room_type_prefabs.py::assert_top_cover_contract`，
但它只扫 `room_type_components` 目录，**本件在 `common_components`，漏在它的网外**。
故在 `build_expedition_common_component_prefabs_v015.py` 里补了同口径的对等断言（三条）：

1. 顶盖件必须在 prefab 里内嵌 `collision_layer = 1` 的碰撞体；
2. 碰撞盒必须盖满整个 5×5 槽；
3. 顶盖不得写 `wall_kind`（水平顶盖不是墙，不该进墙/门槽 lane 台账）。

**反向对照实测**（证明断言有牙）：人为把 `collision_layer` 改成 0 ⇒ 报
「顶盖件缺 layer=1 碰撞体 —— 封顶会漏光」；把碰撞盒缩成 5×0.26×2.5 ⇒ 报「未覆盖整个 slot」。

## 摄像机遮挡契约

**这一类标记必须写在 `CollisionBody` 上，不能写在根节点。** 射线返回的 `collider`
是 `CollisionObject3D`（即 `CollisionBody`），写在根节点上读不到 —— 而**不会报任何错**。

| 组件 | 标记 | 消费方 | 缺了会怎样 |
|---|---|---|---|
| 5 件墙件（3 实墙 + 2 门墙 + 坍塌件） | `camera_lower_wall = true` | `TowerDescent3D._is_camera_lower_wall` | 玩家贴墙时相机退到墙外 |
| `ceiling_deck_5m` | `camera_ceiling_occluder = true` | `TowerDescent3D._is_camera_overhead_slab` | 相机停在顶盖之上，画面被顶盖挡住 |
| `floor_base_5m` / `floor_tile_5m` | **不得带** | — | 地板既不是后墙也不是顶盖 |

### 顶盖为什么要这个标记

默认相机在 **`CAMERA_HEIGHT_M = 9.993940 m`**，而本关顶盖底面在 **3.2 m** ——
**相机整个在顶盖之上**，视线从上往下穿过顶盖平面，角色被挡住（顶盖是实心盒，顶面朝向相机）。

修法**复用楼梯间「楼梯底部被斜楼板压低镜头」的同一套逻辑**
（`TowerDescent3D._update_camera_stair_slab_drop`）：它向上打竖直射线，
命中被标记的楼板就把镜头压到楼板下方。命中算法逐值复刻如下：

```text
探针起点 = 玩家.y + 1.31        (CAMERA_STAIR_SLAB_PROBE_START_HEIGHT_M)
探针终点 = 玩家.y + 9.993940    (desired = CAMERA_HEIGHT_M + lift)
命中顶盖底面 3.2 m
允许高度 = clamp(3.2 − 0.30(走面) − 0.28(clearance), 1.25, 9.993940) = 2.62 m
相机最终高度 = 允许高度 = 2.62 m  ← 落在顶盖下方 0.58 m
```

楼梯那套用的是 `camera_stair_slab`，本件**不借那个名字**（它不是楼梯件）：
判据 `_is_camera_overhead_slab()` 同时接受 `camera_stair_slab` 与
`camera_ceiling_occluder`，所以既有楼梯资产一行不用改。

### 端到端实测（`verify_expedition02_ceiling_camera.tscn`）

```
顶盖实例：CEILING_DECK_5M_083  world_pos=(-2.5, 3.2, -35.0)
射线命中：y=3.2000  collider=CollisionBody
允许高度=2.6200 m  下压量=7.3739 m
相机可压至 2.6200 m，顶盖底面 3.2000 m ⇒ 相机在室内（余量 0.5800 m）
对照 OK：挑高前厅 0 块顶盖（11.9m 通高不被压）
对照 OK：阳台安全屋 0 块顶盖
墙件标记 OK：WALL_STANDARD_5M_H12_060 带 camera_lower_wall
墙水平射线 OK：命中 CollisionBody 且读得到 camera_lower_wall
```

断言在 `build_expedition_common_component_prefabs_v015.py::assert_camera_markers`（三条），
反向对照覆盖「删标记 / 标记写错位置 / 地板硬塞标记」三种破坏场景。

> **未列入本表的两个机制**：`CAMERA_WALL_COLLISION_MASK` 含 layer 1，但墙探针是**水平**的
> （高度 1.09 m），打不到 3.2 m 的顶盖，所以顶盖不会误触发后墙收镜。
> 反之顶盖夹镜用 `desired = CAMERA_HEIGHT_M + lift` 计算，`lift` 会被 `drop` 全额吸收 ——
> 后墙抬升与顶盖下压**叠加后相机高度仍等于允许高度 2.62 m**，两者不打架。

## 材质与色盘

单材质角色 `01_哑光结构面`，色盘格 `(9, 5)`。GLB **不含内嵌图片**（导出时 `export_image_format=NONE`，
实测 `images=0 / textures=0`）；色盘靠 `.import` 的
`import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"`
后处理绑到唯一公共色盘，并置 `gltf/embedded_image_handling=0`。
`.import` 属于可复现导入契约，随 `.glb` 一起进版本控制。

## 验收

| 项 | 结果 |
|---|---|
| 构建 | `EXPEDITION_COMMON_V015_BUILD_OK components=5` |
| 源保护 | `source_unchanged = True`（5/5） |
| 优化记录 | 5/5 有 `triangles_before/after`、`reduction_ratio`、`operations` |
| 包装 TSCN | 5/5 生成，无 Windows 反斜杠绝对路径 |
| 封顶契约 | `top_cover_contract=OK`（含三条断言 + 反向对照） |
| 色盘导入契约 | 5/5 已打 `import_script` + `embedded_image_handling=0` |
| Godot 导入 | `--headless --import` EXIT=0，无本批资产的 ERROR |
| 独立加载 | `EXPEDITION_COMMON_V015_VERIFY_OK components=5`（含封顶专条、色盘绑定） |
| 账本登记 | 《资产主表》873–877、《3D-场景通用》733–737、《总览》12 处公式扩容、《域变更日志》v0.1.33 |
| 账本门禁 | `ASSET_REGISTRY_CHECK_OK scope=structure assets=1068 ledgers=9`，零 issue |
| 验收图 | `qa/expedition_common_components_v015_验收图.png` |

## 本版边界（如实登记，未做的事）

1. **只做通用件，不做房间。** 26 个房间的 `static_layout.tscn` 是下一阶段。
2. **没有门扇。** `wall_door_5m_h3` 只给门洞与门墙结构；门扇（`door_5m`）是否复用战局件待定
   —— 战局门扇高 11.9 m 段的配套件，3m 墙配它需要另判。
3. **美术是低模白件**，没有任何装甲壁板/破损细节。「破败旅馆」的主题落地靠后续房型件与陈设。
4. **未接运行时。** 没有任何房间或关卡引用本批组件，`TowerDescent3D` 未改动。
5. **封顶件是 5×5 模数件**，挑高前厅（30×15）需要 6×3 个；非 5m 整数倍的房间边界将来要收边。

## 与其它文档的关系

- 几何基准：`src/world3d/TowerGeometry3D.gd`（本库数值与其一致）
- 封顶契约：`docs/v0.1/06_技术施工_怪物精英与Boss.md` §7.3.1
- 导入规范：skill `02b-godot-model-asset-import-standard`
- 白盒几何来源：`art_source/design/whitebox/tower_zones/expedition_02/v001/`（v001 白盒）
- 设计页：`docs/v0.1/design/远征关卡02设计.md`

---

*建立：2026-10-12 · 摩斯拉*
