# 关卡接入解耦：通用机制不再按关卡 ID 分支

日期：2026-10-18。FeatureID：`FATE-RULES` / `WORLD-ENTRY`；版本 0.1.0。
来源：业主提出「远征 02 要能同步开发」，排查发现 `Dungeon3D` 有 5 处关卡 ID 硬编码把 02 锁在门外。
规范：[关卡接入规范](../关卡接入规范.md)。

## 根因：一对互相掩盖的死分支

```gdscript
# 配置环节：configure_expedition_fate_economy
if plan.is_empty() or str(plan.get("level_id", "")) != "expedition_01":
    return                                    # ⇒ 02 从不被配置

# 消费环节：_fate_price / _fate_price_bounds / _show_door_fate_choices / 价格标签
if get_runtime_map_id() == "expedition_01" and _fate_economy.is_configured():
    ...                                       # ⇒ 02 恒为假
```

两处互相「证明」对方正确：因为前半句挡掉了 02，后半句在 02 上永远为假，
于是没有任何用例能暴露它 —— 既有的 `verify_fate_economy_service`（762 项）全绿，
因为它只跑 01。

后果不是崩溃，是**静默降级**：02 的命运卡会退回固定价格表 `FATE_PRICE_BY_RARITY`，
没有逐门定价、没有稀有度解锁、没有报价区间。

## 改动

### 1. 建立唯一判据 `Dungeon3D.uses_dynamic_fate_economy()`

```gdscript
## **唯一判据**：本局是否使用关卡级动态命运经济。
## 只看能力，不看关卡 ID。
func uses_dynamic_fate_economy() -> bool:
	return _fate_economy.is_configured()
```

`is_configured()` 由 `FateEconomyService.configure_from_runtime()` 在真实编成建模成功时置真，
所以它天然就是「能不能算」的能力判断，不需要再叠加关卡 ID。

### 2. 配置环节去掉关卡 ID 条件

`configure_expedition_fate_economy`：

```diff
- if plan.is_empty() or str(plan.get("level_id", "")) != "expedition_01":
+ if plan.is_empty():
```

该函数只在 `TowerDescent3D._build_expedition_records()`（远征分支）调用，
塔楼不走此路径，因此去掉关卡判断不会误伤塔楼。plan 为空仍是唯一拒绝条件。

### 3. 四处消费方改用统一判据

| 位置 | 函数 | 改动 |
|---|---|---|
| L6340 | `_show_door_fate_choices` | `map_id == "expedition_01" and is_configured()` → `uses_dynamic_fate_economy()` |
| L7152 | `_fate_price` | 同上 |
| L7160 | `_fate_price_bounds` | 同上 |
| L7460 | 门后价格标签 | 同上 |
| — | `_expedition_fate_max_rarity` | `is_configured()` → `uses_dynamic_fate_economy()`（口径统一） |

改后 `grep 'expedition_0[0-9]' src/world3d/Dungeon3D.gd` 只命中 2 处**注释**，无活代码。

### 4. 新增静态门禁 `scripts/check_level_decoupling.py`

文档约束不了三个月后的人，门禁可以。脚本扫描 7 个「通用机制容器」文件，
发现 `"expedition_0N"` 字面量出现在**活代码**（非注释、非行内注释）即退出 1。

纳入扫描：`Dungeon3D` / `FateEconomyService` / `InventoryModule` /
`EquipmentTransactionService` / `RuntimeRewardCoordinator` / `RewardService` /
`RunPersistenceService`。

`TowerDescent3D.gd` **不在**扫描范围 —— 它是关卡装配器，按 ID 分支是合法的（见规范 §4）。

### 5. 规范文档 `docs/v0.1/关卡接入规范.md`

给出分界线：**通用机制按能力分支，关卡专属内容按 ID 分支**。
含数据层清单、终局房要求（`BOSS_ROOM` + `EXTRACTION_ROOM`）、
并行开发文件归属、加关卡自检清单。

## 验收（本轮实跑）

| 项 | 结果 |
|---|---|
| `verify_fate_economy_service` | **通过**，`FATE_ECONOMY_SERVICE_OK checks=762 failures=0`，`FATE_FORMAL_PATH_COMPLETED`，exit 0 |
| `verify_expedition_level01_flow` | **通过**，`EXPEDITION_LEVEL01_FLOW_OK`：13 房、15×15 安全屋含 2 门、Boss、`STANDARD` 撤离信标、塔楼未被改动，exit 0 |
| `check_level_decoupling.py` | 0 违规，exit 0 |
| 反向对照（注入 1 处旧写法） | **violations=1，exit 1**，还原后 0 违规；还原文件与该注入前字节一致（`cmp` IDENTICAL） |
| `check_documentation_contracts.py` | `issues: []`，文档 328、链接 1824、功能 38 |

为验证解耦，`verify_fate_economy_service` 用固定种子跑正式 `ExpeditionLevel01_3D`，
走真实击杀→金币→拾取→门→扣费→JSON→重建恢复全链。

## 未执行 / 边界

- **没有为 02 跑经济验收**：02 的设计源缺 `monster_rules`，`configure_from_runtime`
  拿不到编成会保持未配置，仍回退固定价格表。这是数据缺口，不是本次解耦缺陷。
  02 补完 `monster_rules` 后应自动获得逐门定价，届时补一条 02 专属验收。
- 未跑 `core` / `full` 全量套件。
- `TowerDescent3D.gd` 里的 9 处 `expedition_01/02` 判定**未改**：经逐个核对，
  全部是关卡专属内容（出生偏移、整体朝向、北向版拒绝降级、相机档案、氛围），
  属规范 §4 允许范围，且已符合 C1–C3（注释齐全、收口在单函数、有默认分支）。
- 场景账本、`feature_registry.json`、`MODULE_INDEX.md` 未改：本次无新增资产、
  无新增 FeatureID，仅有通用机制判据替换。
