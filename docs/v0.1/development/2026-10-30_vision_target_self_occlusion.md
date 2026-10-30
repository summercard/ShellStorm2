# 远征03：房间中间的空阻挡 = 设施被自己的碰撞盒判成「被遮挡」（2026-10-30）

## 1. 业主报单（原文）

> 附图（25×25 改造站房间第一视角，地面一片干净、中央什么都没有）
> 「这个房间中间有个空阻挡」

## 2. 先说结论

**不是墙、不是家具、不是碰撞代孕盒残留。**
中间那块走不过去的实体是**改造台本体**（`ServiceStation3D`），它的碰撞盒一直在、
但整台模型被视野系统判成「被遮挡」而 `visible = false`。
玩家看到的是空地，撞上的是实体 —— 6 个面里唯一看不见的就是它自己。

一句话因果：

```
改造成台 StationBody 挂 layer 1（与墙同层，属 occlusion_mask）
  → 遮挡射线从玩家眼睛水平射向目标中心
  → 第一根被打中的就是目标自己
  → is_position_visible() 恒为 false
  → target.visible = false（整台隐形）
  → visible 不影响物理，碰撞盒照挡
```

## 3. 排查过程（按实际顺序，含走过的弯路）

### 3.1 先按「碰撞代孕盒」查，全错

房间组件走 `safe_box_proxy` 的件，按 `godot-collision-proxy-segmentation`
口径跑了全量扫描：1136 个 prefab、100 个命中 policy 白名单，
`office_room / db_room` 那 6 个候选与本房间无关（本房是 `rt_std_25x25` 程序化壳体）。

### 3.2 再按「玩家胶囊站不进去」查，也全绿

写探针把整间房按 0.5m 网格铺玩家胶囊（r=0.35 / h=1.7）做 `intersect_shape`：
`blocked_points=0`。**这一步的绿是假绿** —— 胶囊合法地"站不进"家具是预期行为，
但我当时只统计了"有没有被挡"，没有问"挡我的东西看不看得见"。

### 3.3 换个问法才抓到

把判据从「能不能站」换成「**挡路的 collider 有没有可见网格顶着**」，
逐房间列出所有挡路 StaticBody 并读 `is_visible_in_tree()`：

```
UPSCAN collider=.../RuntimeDetail/ServiceStation3D/StationBody cells=15 visible_in_tree=false
UPSCAN collider=.../RuntimeDetail/RoomFurniture3D/CollisionBody  cells=9  visible_in_tree=true
UPSCAN collider=.../RuntimeDetail/SearchContainer3D/CollisionBody cells=15 visible_in_tree=true
```

**唯一 `visible_in_tree=false` 的就是那台改造台**，而且它挡了 15 格（≈3.75㎡）——
与业主截图里那块空地的尺寸吻合。

### 3.4 对照实验确认成因

```
station_ray_visible_before = false
（把 StationBody.collision_layer 清零）
station_ray_visible_after  = true   self_visible = true
（还原 layer=1）
station_after_restore_visible = false
```

只改碰撞层、别的一行不动，可见性就翻转 ⇒ **成因是自遮挡，不是距离、不是灯光、不是流送**。

### 3.5 为什么只有设施中招

| 目标类型 | 自身碰撞层 | 在 `occlusion_mask`(1) 里 | 症状 |
|---|---|---|---|
| `ServiceStation3D`（改造台/交易台） | 1 | **是** | 整台隐形，碰撞照挡 |
| `ExtractionBeacon3D` | 0 | 否 | 正常 |
| `RoomKeyPickup3D` | 0 | 否 | 正常 |
| `GroundLoot3D` | 0 | 否 | 正常 |
| `Enemy3D` | 4 | 否 | 正常 |

`ServiceStation3D._build_visual()` 里唯一一段带注释的分支就是给 `merchant`/`upgrade`
建实体体积（注释原文：「事件终端是房间必做目标，不能因为镜头裁切或模型载入异常留下
『透明阻挡』。商店/改造台保留实体体积」）——**这条注释救的正是本 bug 的反面**：
事件终端确实没变成透明阻挡，但商店/改造台变成了**隐形实体阻挡**。

## 4. 修法

`src/player3d/PlayerVision3D.gd`：

1. `is_position_visible(pos, exclude_rids = [])` / `_is_occluded(pos, exclude_rids = [])`
   新增排除表（默认空 ⇒ 老调用点逐字不变）；
2. `_refresh_one_target_visibility()` 传入 `_target_collision_rids(target)`，
   把目标自身及其子孙的 `CollisionObject3D` RID 全部排除；
3. 缓存写在目标 meta 上（25Hz 刷新，不必每次重扫子树）。**空结果只保留
   `RID_RESCAN_S = 2.0` 秒**——首次刷新可能早于设施子体建成，永久缓存空表会让自遮挡残留。

**为什么不改设施的碰撞层**：layer 1 是「玩家会被它挡住」的载体，也是子弹/交互射线依赖的层；
改它等于让改造台可以被穿过去。**也不改 `occlusion_mask`**：那会把墙一起放过。

## 5. 门禁（新增 `verify_vision_target_self_occlusion`）

三条断言，实现改错必须变红：

| 断言 | 防什么 |
|---|---|
| 空地上的改造台必须 `visible` | 自遮挡回退（本轮主 bug） |
| 自身 layer 清零后必须**立刻**可见 | 证明成因确实是自遮挡，而非距离/灯光碰巧 |
| 玩家与设施之间加墙后必须不可见 | 防止「排除自身」把第三方遮挡物一起放过 |
| 事件终端不得有 `StationBody` | 该约定被破坏就会重新出现透明阻挡 |

**反向验证**（按 2026-10-30 确立的规矩，新门禁必须先故意撤掉修复、确认报错、再恢复）：

```
# HEAD 版 PlayerVision3D.gd
ERROR: 空地上的改造台被判成被遮挡（自己挡住自己）⇒ 玩家会撞上看不见的实体
EXIT=1

# 修复版
VISION_TARGET_SELF_OCCLUSION_OK: 设施不再被自身碰撞盒遮挡，第三方遮挡仍生效
EXIT=0
```

## 6. 回归

| 项 | 结果 |
|---|---|
| `verify_vision_target_self_occlusion`（新） | `VISION_TARGET_SELF_OCCLUSION_OK`，退出 0 |
| `verify_3d_vision_input_flow` | `3D_VISION_INPUT_FLOW_OK`（含"墙后目标必须不可见"那条） |
| `verify_unified_player_interaction_flow` | `UNIFIED_PLAYER_INTERACTION_OK` |
| `verify_interaction_dot_presentation` | `INTERACTION_DOT_PRESENTATION_OK` |
| `probe_expedition03_playable` | `PLAYABLE_OK`（门/封闭/幕墙/出口标志全绿） |
| `probe_expedition03_entry_chain` | `ENTRY03_CHAIN_OK` |
| `verify_3d_parity_core` | 4 条既有红项（12 格背包 / 2 格保险 / 相邻房间流送 / 节点预算 3198>2200），**与 HEAD 逐条相同**；修复版反而少了 HEAD 上那 3 条 `Parameter "material" is null.` |

真实渲染取证（`capture_expedition03_upgrade_view`，种子 163794671，房间 `boss_foyer` 25×25）：
`station_visible_in_tree: false → true`，四张图 `outputs/expedition03_upgrade_view_20261030/`，
其中 `01_player_live_view.png` 是站在房间中部正对改造台的第一视角 —— 台子回来了，
业主截图里那块空地就是它。

## 7. 遗留与提醒

- **影响面是"所有有实体体积的交互设施"**：改造站、交易站（`merchant`）都会隐形。
  两者都在远征/tower 的 `MERCHANT`/`UPGRADE` 房里，本轮一起修好，无需分别处理。
- 取证探针 `capture_expedition03_upgrade_view` 保留（真实渲染，需要窗口）。
  三个一次性诊断探针（`room_blockers` / `mid_obstacle` / `walkability`）已删除 ——
  它们的判据要么全错（§3.1）要么假绿（§3.2），留下只会误导下一次排查。
- 这条缺陷**不是远征03 专属**，是 `PlayerVision3D` 的通用判定缺陷；
  塔楼里的交易站同样中招。修复放在通用层，不写关卡分支。
