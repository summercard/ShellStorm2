---
name: 06-character-ledger
description: 角色类表现资产链路第 6 段，同时贯穿 S1–S5。以账本为核心登记与推进玩家、NPC、怪物、Boss 的表现资产：AssetID 预分配、查重、文件路径登记、制作状态推进、过期标记、跨账本契约校验与域责任 skill 维护。不用于制模（用 01-character-contract-authoring）、导出（用 02-character-export-transfer）、Godot 包装（用 03-character-godot-import）、状态接线（用 04-character-state-binding）、专项验收（用 05-character-verification）。
---

# S6 · 账本登记与状态推进（贯穿 S1–S5）

```text
        ┌────────── 账本导轨（本 skill，贯穿全链） ──────────┐
账本 → S1 契约反推 · 双母版 → S2 导出中转 → S3 Godot 包装 → S4 状态映射 → S5 验收 → 账本
        └─ 预分配 ID ─────── 每段出口推进状态 ─────── 过期标记 ─┘
```

**账本不是链路的最后一步，是贯穿全链的导轨。** 它是路径与命名的唯一权威；其他五段每完成一步，都在这里落一次账。

## 边界

- **适用**：`characters`（玩家 / NPC）与 `enemies`（普通怪 / 精英 / Boss）两个域的所有资产登记动作。
- **同样适用**：`SKEL` / `BONE` 骨架与骨骼身份、动画与状态清单、Prefab 分类分页。
- **不适用**：武器（`game-weapon-model-pipeline`）、道具（`game-prop-model-pipeline`）、场景与表现资源（各自域）。跨域时不代写别的账本。

## 账本结构

```text
assets/registry/
├─ ShellStorm2_美术资产台账_v001.xlsx      ← 总目录：只放跨域契约与索引，不含任何资产行
├─ ledgers/
│  ├─ ShellStorm2_角色账本_v001.xlsx        ← characters 域（已声明涵盖 NPC）
│  ├─ ShellStorm2_敌人账本_v001.xlsx        ← enemies 域
│  └─ ShellStorm2_{场景,道具,武器,特效,表现资源}账本_v001.xlsx
├─ ledger_index.json                        ← 单一真源：域→文件→大类→前缀→分页→责任 Skill
└─ ledger_split_baseline.json               ← 拆分无损基线
```

**硬规则**：

- 资产行**只落在分账本**的《资产主表》；总目录**不得写入资产行**。
- **禁止写死账本文件名**。一律经 `scripts/ledger_registry.py` 解析。

## 解析与写入

```python
from ledger_registry import LedgerIndex            # scripts/ledger_registry.py

index = LedgerIndex.load(project_root)
index.path_for_category("角色")        # -> ledgers/ShellStorm2_角色账本_v001.xlsx
index.path_for_category("敌人")        # -> ledgers/ShellStorm2_敌人账本_v001.xlsx
index.domain_for_category("基地资产包") # -> Domain(key='scenes', ...)
index.domain_for_sheet("3D-角色")      # -> 拥有该分页的域
index.rewrite_ref("<旧引用>")           # 旧 master#分页 -> 分账本#分页（幂等）

# 命令行自检
# python scripts/ledger_registry.py
# python scripts/ledger_registry.py --category 角色
# python scripts/ledger_registry.py --asset-id CHR-NPC-VENDOR01
```

> 前缀有歧义（`PRP` 同属场景域与道具域）时 `domain_for_asset_id()` 返回 `None`，**改用 `domain_for_category()`**。

## 两个域的分页职责

| 域 | 账本 | 资产主表 | 角色/敌人专用分页 |
|---|---|---|---|
| `characters` | 角色账本 | 唯一登记源 | 《角色组件》（槽位与挂点契约）· 《动画与状态》（玩家八态 × 组件映射）· 《原型角色》· 《角色中转记录》· 《3D-角色》 |
| `enemies` | 敌人账本 | 唯一登记源 | 《敌人动画与状态》（12 态 × 表现职责 + 敌人条目对照）· 《3D-敌人》 |

**NPC 走角色账本**（该域 `scope_note` 已写明「玩家与 NPC 角色的模型母版、换装组件、挂点、骨架、动作库与状态机映射」）。

## 状态推进（不可跳级）

```text
design_only  →  authored  →  exported_pending_godot_validation  →  validated  →  active
   S1 前           S1 出口              S2 出口                    S3 出口        S4/S5 出口
```

| 状态 | 含义 | 谁推进 |
|---|---|---|
| `design_only` | 仅登记设计，未开工 | S1 第 0 步 |
| `authored` | 双母版已成，契约已记录 | S1 |
| `exported_pending_godot_validation` | GLB 已出、中转 JSON 已生成，待 Godot 验证 | S2 |
| `validated` | 已导入包装并通过导入期验证 | S3 |
| `active` | 已接线并通过专项验收，正式在役 | S4 → S5 |

**过期机制**：重新编辑任一源文件，原导出即视为过期 → 状态**回退**到 `exported_pending_godot_validation`，`validated` 结论作废。

## 每段出口必做的账本动作

| 段 | 落账内容 |
|---|---|
| S1 入口 | 新增《资产主表》行；查重结果必须 `唯一`；目录路径写入「文件路径」列 |
| S1 出口 | 「版本」「源码/策划依据」（双母版路径 + 骨架 ID）→ `authored` |
| S2 出口 | 「SHA-256」「文件路径」（GLB）→ `exported_pending_godot_validation`；中转 JSON 路径 |
| S3 出口 | 《3D-角色》/《3D-敌人》分页行：Prefab 路径、GLB 路径、Blender 源、功能脚本、碰撞三列、标准尺寸、原点与朝向 → `validated` |
| S4 出口 | 「状态/动画」「功能脚本路径」→ `active`（待验收） |
| S5 出口 | 备注写入验收证据（入口名、SHA、日期、截图）→ `active` |
| S6 收口 | 域变更日志追加一条；`更新时间`、`负责人` |

## 各域关键字段的实际取值

**《资产主表》25 列**（两个域一致）：

`AssetID` · `中文名` · `大类` · `子类` · `逻辑ID/源键` · `组件槽` · `变体父ID` · `视角` · `状态/动画` · `复用范围` · `制作状态` · `优先级` · `版本` · `规格(px)` · `文件路径` · `源码/策划依据` · `关键词/别名` · `查重键` · `查重结果` · `SHA-256` · `负责人` · `更新时间` · `来源/许可` · `源编号（Blender collection）` · `备注`

其中 `查重键` / `查重结果` 是**公式列**，不要手工覆写；`查重结果 = 重复` 时**禁止制作**，先合并或建立变体父子关系。

**子类取值约定**

| 域 | 子类 |
|---|---|
| 角色 | `player` · `player_component` · `player_variant` · `player_accessory` · `npc` · `npc_component` · `npc_accessory` · `review_board` |
| 敌人 | `normal_melee` · `normal_ranged` · `normal_summoner` · `normal_tank` · `normal_bomber` · `normal_ambusher` · `normal_elite_boss` · `elite` · `boss` |

## 责任 Skill 的维护（本 skill 的独有职责）

`ledger_index.json` 每个域的 `primary_skill` / `supporting_skills` 声明**该域由哪些 skill 负责**。2026-09-18 起角色域与敌人域的链路已拆分为六个阶段 skill：

| 域 | 旧值 | 新值 |
|---|---|---|
| `characters` | `game-character-model-pipeline` | 见下「六段 skill 一览」 |
| `enemies` | `game-character-model-pipeline` | 同上 |

`game-character-model-pipeline` 已被拆分取代，**不应继续作为责任 skill 保留**。

**六段 skill 一览**（角色域与敌人域共用同一套阶段划分，参数与实例不同）：

| 段 | skill | 职责 |
|---|---|---|
| S1 | `01-character-contract-authoring` | 契约反推 + Blender 双母版 |
| S2 | `02-character-export-transfer` | 导出 + 严格中转 |
| S3 | `03-character-godot-import` | Godot 导入 + PackedScene 包装 |
| S4 | `04-character-state-binding` | 运行时接入 + 状态→动作映射 |
| S5 | `05-character-verification` | 专项验收 |
| S6 | `06-character-ledger` | 账本登记与状态推进（本 skill） |

**建议同时在 `ledger_index.json` 新增 `art_root` 字段**，声明各域美术根目录，供门禁校验「登记的 `文件路径` 必须落在本域 `art_root` 下」：

```json
"art_roots": {
  "characters_player": "assets/art/characters/player",
  "characters_npc":    "assets/art/characters/npc",
  "enemies_normal":    "assets/art/enemies/enemy_3d",
  "enemies_elite":     "assets/art/enemies/elite_3d",
  "enemies_boss":      "assets/art/enemies/bosses"
}
```

## 门禁（每次写账本后必跑）

```bash
python3 scripts/check_asset_registry.py --ledger characters   # 结构 + 跨账本契约：每个 AssetID 全库恰好出现一次
python3 scripts/check_asset_registry.py --ledger enemies
python3 scripts/check_asset_runtime_naming.py                 # 新增资产的运行路径不得带版本号
python3 scripts/check_ledger_refs.py                          # 引用可解析
python3 scripts/check_documentation_contracts.py               # 文档契约
python3 scripts/check_verification_log.py                      # 验收日志
```

整套资产套件门禁（`core` / `aggregate` / `full`）已内置 `check_asset_runtime_naming.py`。

## 常见错误

| 错误 | 正确 |
|---|---|
| 把资产行写进总目录 | 只写该域分账本《资产主表》 |
| 在脚本或文档里写死 `ShellStorm2_角色账本_v001.xlsx` | 经 `ledger_registry.py` 解析 |
| 手工覆写 `查重键` / `查重结果` 公式列 | 让公式计算；`重复` 时先合并或建变体父子 |
| 批量重写历史 `asset_manifest.json` 的 `asset_ledger` 字段 | 那是产出记录，改动即篡改历史；用 `resolve_ref()` 解析 |
| 新增资产顺手把存量带版本名也改了 | D3 冻结：存量照原样引用与登记；门禁只查「不新增」 |
| 制作状态跳级（`design_only` 直接写 `active`） | 按五级顺序推进，每一级都有对应段的产物 |
| 源改了但没标记过期 | 源一变，原导出立即过期，状态回退 |
