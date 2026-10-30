# 远征03 商店房落地 + 金币统一为「每只 1~2 枚」

**日期**：2026-10-30
**范围**：远征03 的 1 间 `SHOP` 房、`monster_rules.currency`、`egt_mimic` 编成
**起因**：业主「宝箱还没做正式设计，先不做宝箱怪。怪物掉落里头先统一掉金币。然后商人房间是否建立了？」

三句话对应三件事，其中第三句是**提问**，答案需要实测，不能靠读配置。

## 1. 商店房：一直存在，但一次都没能用过

业主问「商人房间是否建立了」。这个问题的答案分两层，而第二层才是真答案。

**第一层（配置层）：建了。** 六张 flow 骨架每张都恰好有 1 个 `SHOP` 节点，
`room_quota` 里明写 `"SHOP": 1`，`远征关卡03设计.md §3.1` 的房型表也把它列为独立房型。

**第二层（运行时）：没有。** 每张 flow 都有 1 间 `shop` 房，但里面是空的 ——
没有商人、没有终端、没有商品、没有购买。而且**没有任何报错**。

### 1.1 断点在哪：`room_type` 不是从 `_flow_room_type()` 来的

第一直觉会去查 `_flow_room_type()`：

```gdscript
static func _flow_room_type(role: String) -> String:
	match role:
		"stair_entry": return "SAFE_ROOM"
		"extraction":  return "EXTRACTION_ROOM"
		"boss":        return "BOSS_ROOM"
		_:             return "COMMON_ROOM"
```

`SHOP` 的 role 是 `main`（`FLOW_KIND_ROLE` 里写死），所以它落到 `_` 分支 → `COMMON_ROOM`。
看起来"改这里就行"—— 但**改这里没用**，因为：

```
_generate_flow_floor() 产出 rooms[]，同时写两个键：
  "room_type": _flow_room_type(role)         ← 校验器用
  "content_type": FLOW_KIND_CONTENT.get(kind)← 运行时用

room_from_source() 是**出口白名单**，只搬 content_type → type
  "room_type" 这个键根本没有登记 ⇒ 被静默丢弃

TowerDescent3D._append_tower_record(..., spec["type"], ...)
  ⇒ DungeonRoom3D.room_type == content_type
```

也就是说 flow 房间的**运行时 `room_type` 等于 `content_type`**，而 `content_type`
在 `FLOW_KIND_CONTENT` 里没有 `SHOP` 这一项 → 空串 → 被
`_assign_content_types_data_driven()` 洗成 `COMBAT` / `STORAGE` / `TRAP`。

于是 `DungeonRoom3D._build_detail()` 里那句

```gdscript
if room_type in ["MERCHANT", "UPGRADE", "EVENT"]:
	_create_service_station(room_type.to_lower(), dimensions)
```

**一次都没成立过**。服务点没建 → `ServiceStation3D.activated` 永远不发 →
`Dungeon3D._on_service_activated()` 永远不跑 → `_open_merchant()` 永远不调。

修法只有一行：`FLOW_KIND_CONTENT["SHOP"] = "MERCHANT"`。

### 1.2 为什么是 `MERCHANT` 而不是设计文档写的 `EVENT`

原设计（`远征关卡03设计.md §3.1` 第 2 条）写的是「`SHOP` 复用 `EVENT` 房型 + 商人终端」，
理由是「`GameDesignConfig.ROOM_TYPES_WITH_HOSTILES` 里没有 `SHOP`，内容类型白名单也没有」。

这条理由只对了一半：

- 白名单（`LevelPlanLoader.VALID_ROOM_TYPES` 四项）校验的是 **`room_type` 字段**，
  即 `_flow_room_type()` 的产物；而运行时认的是 `content_type`，**没走那份白名单**。
- 所以不存在"必须先改 `GameDesignConfig`"这道门。

而选 `EVENT` 会走进另一条**错**的分支：

```gdscript
func _on_service_activated(_room, station) -> void:
	match station.station_type:
		"merchant": _open_merchant(...)
		"upgrade":  _open_workbench()
		"event":    _resolve_event_room(_room)   # 随机 CURSE/BLESSING/TRADE/GAMBLE/...
```

`EVENT` 房的终端打开的是**随机事件**，不是商店。只有 `room_type == "MERCHANT"`
才会让 `_create_service_station("merchant", ...)` 建出 `station_type = "merchant"`
的终端，进而命中 `"merchant"` 分支。设计文档已同步改成 `MERCHANT`，并把 D3 标为已落地。

### 1.3 顺带确认的三件事

- 商店房仍是 **enemyless**（`SHOP` 在 `FLOW_PEACEFUL_KINDS` 里）：不封门、不刷怪。
  实测 `spawn_placements` 与 `chest_placements` 都是空 ✓
- 货架 6 件来自 `LootModule.generate_merchant_goods(tier, 6)`，价格 ±10% 浮动；
  购买扣 `GameManager.currency` 并占**真实背包格**（`inventory.plan_purchase_add()` 失败会返回 `inventory_full`）
- 进店第一次会 flush 一次运行时检查点（`run_merchant_stock_opened`），
  失败就回滚货架并提示「商人货架保存失败」—— 这是既有逻辑，没动

**实测**（`tools/_egt_merchant_probe.gd`，3 个种子）：

```
[seed 77003244] MERCHANT 房：1 间 → ["shop"]  服务点存在=true
  货架 6 件：weapon_greatblade/160枚, bp_shotgun/62枚, ... mod_bullet_standard/27枚
  购买 标准子弹模块（27 枚）：77 → 50 枚，货架 6 → 5
[seed 1]  MERCHANT 房：1 间 → ["shop"]  服务点存在=true
  购买 房间钥匙（39 枚）：89 → 50 枚，货架 6 → 5
[seed 42] MERCHANT 房：1 间 → ["shop"]  服务点存在=true
  购买 治疗药水（40 枚）：90 → 50 枚，货架 6 → 5
EGT_MERCHANT_PROBE_OK
```

## 2. 金币统一：从「按血量 2/3/8」到「每只 1~2 枚」

改前 `monster_rules.currency.per_kind` 逐只写了 33 条，按血量分 2 / 3 / 8 三档。
一层 52 只怪合计约 82 枚，而原作一层总量是社区统计的 **≈59 枚**（非官方，见
[普通怪掉落](../reference/挺进地牢/普通怪掉落.md) §2）。

问题是**一层到底多少只怪**之前没人算过。这次用六张 flow 的真实编成统计：

| flow | 怪数 | 非自爆怪 |
|---|---|---|
| flow_01 | 52 | 39 |
| flow_02 | 51 | 38 |
| flow_03 | 52 | 39 |
| flow_04 | 61 | 48 |
| flow_05 | 42 | 31 |
| flow_06 | 61 | 48 |

均值 53 只，其中**自爆怪占 25%**（13 只）—— 而它们按原作规则
（"All enemies that will self-destruct will not drop shells"）掉 0 枚。
这就是"统一"唯一不能取整数的原因：

| 每只给几枚 | 一层总量 | 相对原作 ≈59 |
|---|---|---|
| 1 枚 | 40.8 | −31% |
| 2 枚 | 81.6 | +38% |
| **1~2 枚（均值 1.5）** | **61.3** | **+3.8%** |

所以 `default = {min:1, max:2}`。

### 2.1 给 `_currency_amount_for()` 开了 `{min,max}`

`RewardService._currency_amount_for()` 原本只认 `{base, per_floor}`：

```gdscript
if not (entry.has("base") and entry.has("per_floor")):
	continue
```

而下游的 `_eval_amount()` **本来就支持** `{min,max}`（`rng.randi_range(lo, hi)`）。
所以只在上游放行即可，求值链路一行没动：

```gdscript
if entry.has("min") or entry.has("max"):
	var lo := int(entry.get("min", 1))
	var hi := int(entry.get("max", lo))
	...
	return {"min": lo, "max": hi}
```

影响面为零：只有配了 `monster_rules.currency` 的关卡才走这段，
未配置的关卡 `currency_spec_for()` 直接返回 `{}`。

### 2.2 差点把 Boss 打成 1 枚

第一版配置只加了 `default`，没加 `per_tier`。看起来"所有普通怪统一"很干净，
但 `_currency_amount_for()` 的候选顺序是：

```
per_tier.get(tier) > per_kind.get(monster_id) > rules.get("default")
```

`tier` 是 `boss` 时 `per_tier` 是空的（没写），`per_kind` 也没有 `boss` 这条，
于是**落到 `default` → Boss 掉 1~2 枚**。探针当场测出：

```
<elite 强化变种>  1.00 枚   （期望 70）
<boss>            1.00 枚   （期望 220）
```

补上 `per_tier.elite = {base:50, per_floor:20}` / `per_tier.boss = {base:200, per_floor:20}`
（与 `MonsterInjector.DROP_CURRENCY_BASE_ELITE / BASE_BOSS / PER_FLOOR_ELITE_BOSS` **逐值一致**）之后：

```
<elite 强化变种>  70.00 枚
<boss>            220.00 枚
```

> 这个坑的要害是**它不报错**：`default` 是合法配置，解析链全程无 warning，
> 只有把"精英 / Boss 单只产出"单独测一遍才能发现。

另一个更隐蔽的同类坑：`RuntimeRewardCoordinator.resolve_kill()` 判档位读的是
`enemy_data.is_boss` / `enemy_data.is_elite` 两个**布尔**，不读 `monster_tier` 字符串。
第一版探针传 `monster_tier: "boss"`，被当成 normal —— 又一次"看起来在测，其实没测到"。

### 2.3 商店价格对得上吗

`tools/_egt_shop_price_probe.gd` 实测：货架 6 件价格区间 **27 ~ 250 枚**、中位 **113 枚**。

所以一层 61 枚的实际含义是「攒一层买得起最便宜的 1~2 件，攒两层买得起中位价」——
与原作「一层 ≈59 铸币 / 商店一件 60~100」的节奏一致。

## 3. 宝箱拟态：摘掉，不是删掉

`egt_mimic` 的数值（hp 1000 / damage 17）、AI、掉落全部已注册，
`box_egt_mimic_trap.json` 也还在。本次**只把它从 `spawn_roster.by_node.n07.boxes` 里摘掉**。

理由不是"不想做"，是**顺序问题**：拟态的全部玩法值来自"它长得像一个你正要开的宝箱"，
而宝箱本体仍是无正式设计的占位（品质池没拆、四档品质只做掉落加成、拟态触发协议未定）。
先摆拟态等于把「箱子会咬人」这条规则钉在一个还要改的箱子上。

接回来的成本很低：把 `"box_egt_mimic_trap"` 加回 n07 的 `boxes` 即可。
真正的前置是宝箱的正式设计，已记为待裁决项 D5。

## 4. 验收

| 探针 | 结果 |
|---|---|
| `_egt_shop_currency_probe`（新） | MERCHANT 房 1 间 · 33 只逐只金币 · 精英 70 / Boss 220 · 一层 61.3 枚（+3.8%） |
| `_egt_merchant_probe`（新） | 3 种子：MERCHANT 可识别 / 服务点建出 / UI 可开 / 买得动 / 关得掉 |
| `_egt_shop_price_probe`（新） | 货架 27~250 枚，中位 113 |
| `_egt_drop_probe` | OK（33 只结构不变、清房 17.1% / 7.3%、对照组 14.4% / 36.5%） |
| `_egt_roster_probe` | OK（n07 由 3 盒降到 2 盒，6 种子全战斗房有编成） |
| `_egt_chest_probe` | OK（2 间宝箱房、开箱 +2 件 +1 卡、不可重复开） |
| `_egt_clear_rewards_wiring_probe` | OK |
| `_egt_tuning_runtime_probe` | OK（33 只进场 hp/damage） |
| `verify_3d_enemy_behavior_flow` | OK |
| `verify_3d_combat_progression_flow` | OK |

## 5. 留下的

- **商店房是终端造型**（`ServiceStation3D` + 「拾荒商终端」标题），不是 EGT 那种站在房间里的商人 NPC。
  最小可用的取舍，换造型要改 `_create_service_station()` 或另做 `MerchantNpc3D`。
- **钥匙仍然偏紧**：可支配约 1~1.5 把 vs 宝箱 2 间。商店里能买到钥匙（实测一件 39 枚），
  但那是"用金币换钥匙"，玩家得自己权衡。
- **宝箱正式设计**（品质池拆分 / 拟态触发时机 / 拟态击败掉落）未做 —— 这是拟态接回的前置。
