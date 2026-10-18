# 传送支线（秘密房间）第一阶段：位点 · 隐藏门 · 传送 · 子图

日期：2026-10-18。FeatureID：`WORLD-SECRET`（新，**待登记**）；版本 0.1.0。
设计：[支线秘密房间设计](../design/支线秘密房间设计.md)；施工边界：[05 §5.5](../05_技术施工_关卡生成与爬楼.md)。

## 交付范围

| 项 | 状态 |
|---|---|
| 四个静态位点声明 + 五级字段透传 | ✅ |
| 隐藏门板体（程序化 Box、可被打爆、三段状态） | ✅ |
| 入口 / 出口 / 撤离 三处传送区 | ✅ |
| 子图白盒房间（2–3 间等距串联，主图外 +1000m） | ✅ |
| 配对与种子刷出（pair 0 恒刷、pair 1 50%） | ✅ |
| 存档导出 / 恢复（幂等） | ✅ |
| 未清房时入口板不可破 | ❌ 下一阶段 |
| 撤离门按已清房阈值解锁 | ❌ 下一阶段 |
| 撤离信标与结算（`commit_run_settlement`） | ❌ 下一阶段 |
| 子图刷怪、掉落加成、击杀账 | ❌ 下一阶段 |
| 跳跃边界 B1–B3 运行时断言 | ❌ 仅静态核对 |

## 关键实现

### 1. 数据：位点用「墙面」表达，不存世界坐标

```jsonc
"secret_site": {"site_id":"S1","pair_id":0,"role":"entry","wall":"south","door_width_m":2.2}
```

坐标由**房间外框 + wall 在运行时推导**（`SecretBranch3D._collect_sites`）。改版图时位点自动跟随，不会出现「JSON 里写着 A 点、房间已经挪到 B 处」的两处不同步。

五个位点全在无端口的墙面上，朝外 3m 无遮挡 —— 已由 `verify_secret_branch_flow` 的 A1–A3 静态断言钉住。

### 2. 五级透传（少一级就静默失效）

```
真源 art_source/.../floor_00.json
  → data/level_plans/...（脚本投影，不可手改）
  → LevelPlanLoader.normalize_floor（白名单重建）
  → FloorPlanGenerator._constrained_slot（蓝图槽位）
  → FloorPlanGenerator._constrained_floor_from（房表）
  → FloorPlanGenerator.room_from_source（出口白名单）
  → TowerDescent3D._append_plan_room_record（运行时记录）
  → Dungeon3D._prepare_layout_rooms（房间实例）
```

⚠️ 本次实测踩到的坑：**中间两层是独立的字段白名单**（`_constrained_slot` 与 `_constrained_floor_from`），它们不在文档里显式列出，漏登记的表现是「设计源写了、运行时为空」，全链无报错。补完这两层后规划层才见到位点。同类历史事故：2026-09-25「刷怪批次与设计不符」。

### 3. 装配时机：远征不走 `_generate_layout`

最初把触发放在 `Dungeon3D._finish_layout_connections()`，实测**永远不执行** —— 远征走 `TowerDescent3D._prepare_floor_bundle()` 逐房追加记录。最终触发点定在 `_prepare_floor_bundle` 补完非入口房之后，并在 `_build_expedition_records` 末尾保留一次（幂等，第一轮会因 records 里还没有带位点的房间而提前返回）。

`_create_secret_branches()` 自带幂等守卫（`_secret_branch != null` 直接返回），否则两处调用会造出两套板体。

### 4. 隐藏门：脚本挂在 StaticBody3D 上

`Projectile3D._hit_target()` 与近战扇区查询拿到的 collider 是**碰撞体节点本身**，直接对它调 `take_damage()`。脚本若挂在父节点会收不到伤害 —— 因此 `SecretDoor3D extends StaticBody3D`。

板体为程序化 BoxMesh（2.2 × 2.4 × 0.3），**不是门扇 Prefab**：门扇有门框与把手，一眼看出是门，与「隐藏门」冲突。设计文档 §4.2 已同步改写。

### 5. 传送：改坐标，不切场景

子图与主图在同一场景，隔 1000 m。切场景会牵动存档、流送与相机重建，而这里只需要瞬移。落点用 `set_deferred("global_position", ...)` —— `body_entered` 在物理查询期间触发，直接改 transform 会被物理服务器拒绝。

传送区开启同样必须 `set_deferred("monitoring", true)`：破板发生在伤害回调里，当帧直接写 `monitoring` 不生效。**这个坑实测出现过**：首轮 A9 一直是「玩家未移动」，根本原因就是 monitoring 没真正打开。

### 6. 子图不进主图记录

子图房间是独立的 `Node3D` 分支（`SecretBranch_N`），不写 `_records`、不进全层地图、不参与流送与拓扑校验。验收 A8 断言：`_records` 里不得出现 `Secret*` 前缀的 id，且子图房间 x 坐标必须落在 ≥ 1000 − 400 的偏移带。

## 验收（本轮实跑）

| 项 | 结果 |
|---|---|
| `verify_secret_branch_flow` | **通过**：`SECRET_BRANCH_FLOW_OK 位点=4 生成规则=确定 传送=可达 隔离=通过 存档=往返一致` |
| 反向对照（`_pair_spawned(0)` 改 `false`） | **A4 逐种子报红**（`种子 N 下 pair 0 未刷出`）；还原后复绿 |
| `verify_expedition_level01_flow` | 通过（13 房 / Boss / STANDARD 撤离 / 塔楼未改动） |
| `verify_fate_economy_service` | 未在本轮重跑（上一轮解耦后 762 项通过） |

种子 77001199 实测：2 对全刷；pair 0 子图 3 间（x = 1012.5 / 1041.5 / 1073.0），pair 1 子图 2 间（x = 1312.5 / 1341.5）。

## 测试脚本自身的三个坑（已修）

1. `normalize_floor` 返回的房间**没有 `id` 键**，用 `id` 做字典键会让 13 间房全部撞到一个空键上，判定「位点数量 0」。改用 `key`。
2. `pair_id` 经 JSON 往返后是 **float**（`0.0`），用字符串比较会误报不一致。改 `int()`。
3. 存档往返**不能用新建空实例**测：它没有门可恢复，导出必然为空。改为对同一实例重放同一份快照，断言幂等。

## 未执行 / 边界

- 子图目前是**白盒**（地板 + 四面墙，无天花板、无美术）。设计 §12 已把「正式美术」列为范围外。
- 子图房间之间**不物理连通**，靠传送串联；本期不建走廊、不做拐弯。
- 撤离房已建（25×25 白盒 + 传送区），但**没有信标、没有结算**。
- 未跑 `core` / `full` 全量套件。
- 板体血量按 `60 + 20 × 已清内容房数` 计算，但「未清房不可破」这条规则尚未实现，因此当前任何已清房数下都可被打破。
