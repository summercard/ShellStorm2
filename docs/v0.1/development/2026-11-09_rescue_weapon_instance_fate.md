# 救援箱武器按实例归还（原枪原卡）· 2026-11-09

FeatureID：`BASE-RESCUE`。设计口径见[救援设计页](../design/战败归航救援与绿苔台词.md) §4，工程契约见[基地NPC](../20_技术施工_基地NPC.md) §14。

## 1. 来源

业主 2026-11-09：

> 我在关卡内死亡后，npc帮我回收的物品里，如果是武器的话，应该是原来的那把。我带进去一把步枪，有嵌进去了2张命运卡，出来后重新从箱子里开出这把步枪的时候，没有命运卡了。

即：救援箱里的枪必须是**死亡那一刻手上那个实例**（实例 ID + 星命运刻印 + 装配快照），不能是"同型号、无卡"的新枪。

## 2. 机制核查（先测，再改）

救援箱不复用掉落表：`_resolve_chest_grants()` 见到 `explicit_grants` 直接原样返回，
清单在死亡结算前由 `_plan_rescue_items()` 抽出，随 `commit_run_settlement()` 同事务写进
`BaseData.rescue_cache`，99F 开箱时由 `build_rescue_chest_grants()` 翻回 grants 落地。

三组 headless 探针（真实 `ExpeditionLevel01_3D` / `TowerDescent3D` 场景，逐跳打印 `fate_upgrades` 数量）：

| 链路 | 结果 |
|---|---|
| 装 2 张星命运 → `_plan_rescue_items()` | 2 张，`weapon_instance_id` 不变 |
| → `commit_run_settlement()` → `get_rescue_cache()` | 2 张 |
| → `BaseManager.load_base()`（磁盘往返） | 2 张，实例 ID 不变 |
| → `build_rescue_chest_grants()` | 2 张 |
| 99F 真实开箱 → 地面实体 → 拾取入包 | 2 张 |
| 基地「待带入」栏带卡枪 → 进远征 → 装备 → 抽签 | 2 张 |

结论：**存储与搬运层没有掉卡**。`WeaponInstance.to_item_dictionary()` 把
`fate_upgrades` / `assembly_snapshot` 一起写进物品字典，链路上每一跳都是整字典复制。

## 3. 根因：抽签按"先到先得"去重，背包里的旧字典会顶掉装备槽

`_plan_rescue_items()` 原实现先扫背包快照、再读装备槽，并用
`weapon_instance_id` 去重（"同一实例不重复抽到"）。问题在两处叠加：

1. 去重是"先到先得"——背包里那份先登记，装备槽那份就被 `continue` 掉；
2. 背包格里的字典是**快照拷贝**，不是运行实例。装备槽才是权威：
   卡是在实例上刻的（`WeaponInstance.append_fate_upgrade`），槽位字典不会跟着变。

于是只要背包里存在一份**同实例、无卡**的旧字典（跨存档还原、事务回滚、
拾取同实例物件的边界都可能留下），箱子里出现的就会是"同一把枪、刻印 0 张"——
与业主看到的症状逐字对上。

## 4. 改动

| 文件 | 改动 |
|---|---|
| `src/world3d/Dungeon3D.gd` `_plan_rescue_items()` | 装备槽**先收集**（成为候选前序 + 去重先手）；背包里同实例的字典换成装备槽那份（`live_weapons` 替换）。背包物品本身不受影响，仅"同实例"这一种情况换源 |
| `tests/verification/verify_base99_rescue.gd` | 新增 **R16**：给装备枪刻 2 张星命运，再往背包塞一份同实例无卡副本，断言 `抽签 → 落档 → 箱内清单` 三跳的 `weapon_instance_id` / `fate_upgrades` / `assembly_snapshot` 全部等于权威版本 |
| `docs/v0.1/design/战败归航救援与绿苔台词.md` | §4 增「武器口径」一行（业主 2026-11-09） |

不改：抽签件数（携带物 1–2、补给 1–2）、独立随机流、保险格排除、
`item_id == item.id` 一致性校验、开箱链与消失计时。

一处**可观察的副作用**：候选顺序变了（装备槽在前），同 `run_seed` 下"抽到哪几件"
可能与旧版不同；件数上下界、同实例不重复、保险格排除三条口径不变。

## 5. 验收

```bash
godot --headless --path . --scene res://tests/verification/verify_base99_rescue.tscn
```

- 修复后：`BASE99_RESCUE_OK`，exit 0，日志内 `SCRIPT ERROR` / `Parse Error` 为 0。
- **反向对照**：把 `_plan_rescue_items()` 换回旧顺序（背包先、装备槽后、无换源）重跑，
  R16 精准三条变红：

```
ERROR: R16 [抽签] 星命运刻印从 2 张变成 0 张
ERROR: R16 [落档] 星命运刻印从 2 张变成 0 张
ERROR: R16 [箱内清单] 星命运刻印从 2 张变成 0 张
```

即这条断言真的盯着"原来那把"这件事，不是恒绿的注释。

## 6. 未覆盖 / 待确认

- 只做 headless 数值断言，真实渲染下箱内枪械卡面/详情的观感未出图。
- 业主当次实测用的是哪条路径（局内刻卡 / 靶场沙盒 / 两个同型号实例）未能从存档复现：
  当次档案里全档 0 条 `fate_upgrades`，无法回放该把枪。若再次出现，需要枪械的
  `#后缀`（`weapon_instance_id` 末 6 位）才能定位是"同一实例被换源"还是"两个不同实例"。
- 两种**按设计**会掉卡的情形，与本次修复无关，排查时先排除：
  ① 月亮/太阳 scope 的卡（角色/世界本局临时，死亡即清）；
  ② 靶场沙盒里刻的卡（`TrainingFateBenchPanel` 明确不写 `BaseManager`，离开靶场即还原）。
