# 救援箱武器按实例归还（原枪原卡）

业主 2026-11-09：带一把刻了 2 张命运卡的步枪进远征，阵亡后从绿苔救援箱开出来，卡没了。
口径「回收物品里如果是武器，应该是原来那把」。

## 结论：搬运层不掉卡，掉在抽签的去重顺序

三组探针（真实远征/基地场景，逐跳打印 `fate_upgrades`）：装卡 → `_plan_rescue_items`
→ `commit_run_settlement` → `load_base`（磁盘往返）→ `build_rescue_chest_grants`
→ 99F 真实开箱 → 地面实体 → 拾取；另加「待带入栏带卡枪 → 进远征 → 装备 → 抽签」。
每一跳都是 2 张，实例 ID 不变 ⇒ 存储/JSON/发放都没问题。

真凶在 `_plan_rescue_items()`：先扫背包快照、后读装备槽，按 `weapon_instance_id`
"先到先得"去重。背包格存的是**字典快照**，卡刻在运行实例上（`append_fate_upgrade`），
槽位字典不跟着变 ⇒ 背包里只要有同实例的旧字典，它先登记就把装备槽那份 `continue` 掉，
箱子里于是成了"同一把枪、刻印 0 张"。

## 改动

- `src/world3d/Dungeon3D.gd` `_plan_rescue_items()`：装备槽先收集（候选前序 + 去重先手）；
  背包里同实例的字典换成装备槽那份（`live_weapons`）。
- `tests/verification/verify_base99_rescue.gd`：新增 R16 —— 刻 2 张星命运 + 背包塞同实例
  无卡副本，断言 抽签/落档/箱内清单 三跳的 实例ID / 刻印 / 装配快照 全等。
- 设计页 §4 加「武器口径」；CHANGELOG、feature_registry、开发记录同步。

## 验收

`verify_base99_rescue` → `BASE99_RESCUE_OK`，exit 0，0 条 SCRIPT/Parse Error。
反向对照（换回旧顺序）⇒ R16 精准三条红：`星命运刻印从 2 张变成 0 张`。

## 遗留

- 只做 headless 数值断言，真实渲染未出图。
- 业主当次档案全档 0 条 `fate_upgrades`、无步枪，无法回放那一把；再遇到需要 `#后缀`
  才能分清"同实例被换源"还是"两个不同实例"。
- 按设计会掉卡的两条，别再当 bug：月亮/太阳 scope 死亡即清；靶场沙盒不写 BaseManager。
- 副作用：候选顺序变了，同 `run_seed` 抽到的"哪几件"可能与旧版不同（件数/排除/去重口径不变）。
