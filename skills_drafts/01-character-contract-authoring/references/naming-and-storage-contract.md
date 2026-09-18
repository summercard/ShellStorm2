# 角色类表现资产 · 命名与存放路径契约

适用域：`characters`（玩家 / NPC）与 `enemies`（普通怪 / 精英 / Boss）。

本契约是 **S1–S6 六个阶段 skill 的共同地基**。任何阶段在写路径、起文件名、建目录之前先读本文；与本文冲突的旧做法以本文为准。

---

## 0. 总原则：账本先行，路径是账本的派生

**账本是路径与命名的唯一权威。** 顺序不可逆：

```text
账本 ledger_index.json  →  域 + 大类 + 域根
        ↓
分账本《资产主表》新增行  →  AssetID + 逻辑名(slug) + 组件槽 + 变体父ID + 版本
        ↓
      目录路径            →  由域根 + 逻辑名按形态模板展开
        ↓
      文件名              →  由逻辑名 + 角色(母版/视觉/包装/清单) 展开
        ↓
   运行时引用 / Prefab    →  只引用稳定路径
```

- **未登记的资产不得落盘。** 先补《资产主表》，查重通过（S 列「查重结果」= `唯一`）后再建目录。
- **账本里的「文件路径」列就是路径真源。** 文档、skill、脚本不得各自维护一份路径表，一律读账本。
- **禁止硬编码账本文件名**：一律经 `scripts/ledger_registry.py` 的 `LedgerIndex` 解析。

```python
from ledger_registry import LedgerIndex          # scripts/ledger_registry.py
index = LedgerIndex.load(project_root)
index.path_for_category("<大类>")                 # -> 该大类的分账本路径
index.domain_for_category("<大类>")               # -> Domain(key, art_root, ...)
index.domain_for_sheet("3D-<分页>")               # -> 拥有该分页的域
index.rewrite_ref("<旧引用>")                     # 幂等改写
```

---

## 1. 域根目录（由 `ledger_index.json` 的 `art_root` 声明）

| 域 key | 族群 | 域根 | 现有形态 |
|---|---|---|---|
| `characters` | 玩家 | `assets/art/characters/player/` | **形态 B**（production/vNNN，存量冻结） |
| `characters` | NPC | `assets/art/characters/npc/` | **新增，形态 A** |
| `enemies` | 普通怪 | `assets/art/enemies/enemy_3d/` | **新增，形态 A**（存量套件根冻结） |
| `enemies` | 精英 | `assets/art/enemies/elite_3d/` | **形态 A**（已有唯一样板） |
| `enemies` | Boss | `assets/art/enemies/bosses/` | **新增，形态 A**（存量 `bosses_v01/` 冻结） |

> `art_root` 是**建议在 `ledger_index.json` 中新增的字段**，用于让门禁校验「登记的 `文件路径` 必须落在本域 `art_root` 下」。未落地前，本表即临时权威。

---

## 2. 三种路径形态

### 形态 A — 规范三段式（**新增资产默认形态**）

```text
<域根>/<slug>/
├─ source/<slug>_source_v<NNN>.blend          ← 唯一允许带版本号的位置
├─ components/<slug>_visual_top3d.glb         ← 稳定路径，替换=覆盖
└─ runtime/<slug>_root_top3d.tscn             ← 稳定路径，替换=覆盖
```

已按此形态成立：`assets/art/enemies/elite_3d/rift_boar_armed/`（**怪物侧唯一样板，新怪照抄它**）。

### 形态 B — 角色 production 版本形态（玩家专用，**存量冻结**）

```text
assets/art/characters/player/chr_player_capsule01_3d/variants/<变体>/
├─ production/v<NNN>/
│  ├─ source/model/<slug>_model_v<NNN>.blend
│   ├─ source/animation/<slug>_animation_v<NNN>.blend     ← 双母版：模型 / 动作分离
│  ├─ exports/<slug>_<部件>_v<NNN>.glb
│  ├─ runtime/<slug>_root_v<NNN>.tscn
│  └─ character_transfer_ledger_v<NNN>.json               ← 逐文件中转台账
├─ source/  components/  previews/                        ← 早期形态，冻结
└─ accessories/<槽>/<件>_v<NNN>/{source,runtime,previews}/
```

**该形态仅玩家使用，且已由 D3 冻结。** 新增 NPC 与怪物**不套用** production/vNNN，一律形态 A。玩家侧继续演进时在既有 `production/v<NNN>/` 内迭代，不另开形态。

### 形态 C — 共享套件 + 变体（怪物族）

怪物的「共享根 / 独立表现」关系**由账本「变体父ID」列表达，不由目录嵌套表达**：

```text
assets/art/enemies/<族根>/<套件 slug>/{source,components,runtime}/    ← 父，AssetID ENM-ECOSYSTEM-KIT-3D
assets/art/enemies/<族根>/<怪 slug>/{source,components,runtime}/      ← 子，变体父ID = ENM-ECOSYSTEM-KIT-3D
```

- 父子关系写进账本，**不为子怪建 `variants/` 子目录**（那是玩家形态 B 的写法，别混用）。
- 共享套件承担 `core / shell / appendages` 等模块化出件；子怪只提供差异件与自己那套动作。

---

## 3. 命名规范

### 3.1 AssetID（稳定身份，版本升级不变）

```text
<域前缀>-<子类码>-<逻辑名大写>-<形态后缀>
```

| 段 | 取值 |
|---|---|
| 域前缀 | `CHR`（角色） / `ENM`（敌人） / `SKEL`（骨架） / `BONE`（骨骼） |
| 子类码 | `PLY` 玩家 · `NPC` NPC · `MELEE`/`RANGED`/`SUMMON`/`TANK`/`BOMBER`/`TRAP` 普通怪 · `ELITE` 精英 · `BOSS` Boss · `ECOSYSTEM` 生态套件 · `AVATAR-TEMPLATE` 制作母版 · `3D` 3D 形态 · `SIDE`（历史 2D，弃用） |
| 逻辑名 | 大写入账本，词内不用连字符以外的分隔 |
| 形态后缀 | `-3D` 3D 运行形态；省略表示玩法根或逻辑身份 |

实例对照：

```text
CHR-PLY-CAPSULE01              玩家逻辑根（稳定身份）
CHR-PLY-CAPSULE01-3D-BUNNY01   玩家 3D 根变体（v021 在跑的就是它）
CHR-PLAYER-AVATAR-TEMPLATE-001 玩家 1.5m 制作母版
ENM-ECOSYSTEM-KIT-3D           七类怪物共享生态套件（父）
ENM-ELITE-RIFT-BOAR-ARMED-3D   精英（子，变体父ID = ENM-ECOSYSTEM-KIT-3D）
ENM-BOSS-ARCHIVIST-95          深渊档案官
SKEL-BUNNY01-004               骨架 ID（独立于 AssetID 的第二类身份）
```

**骨架 ID** 单独编号，形态 `SKEL-<族码><NN>-<NNN>`，同一骨架必须被模型母版与动作母版**共同引用**，导出时重算签名比对。

### 3.2 逻辑名 slug（目录名与文件名主干）

- 小写 `snake_case`，字符集仅 `[a-z0-9_]`。
- 结构：`<域缩写>_<子域>_<逻辑名>[_<变体/部件>]`

| 族群 | slug 模板 | 实例 |
|---|---|---|
| 玩家 | `chr_player_<name>` | `chr_player_capsule01_3d` |
| NPC | `chr_npc_<name>` | `chr_npc_vendor01` |
| 普通怪 | `enm_<职能>_<name>` | `enm_melee_fungboar01` |
| 精英 | `enm_elite_<name>` | `enm_elite_rift_boar_armed` |
| Boss | `enm_boss_<name>_<层号>` | `enm_boss_archivist_95` |
| 生态套件 | `enm_ecosystem_kit_3d` | — |

- **目录名不含版本号**（新增资产硬性；存量按 §4 冻结）。
- 目录名 = slug；`components/` 与 `runtime/` 下**一层同名子目录**再放文件，即 `<slug>/components/<slug>/<slug>_visual_top3d.glb`（与命名规范总纲一致）。

### 3.3 文件名模板

| 角色 | 模板 | 带版本号 |
|---|---|---|
| 源母版 | `<slug>_source_v<NNN>.blend` | ✅ |
| 模型母版（形态 B） | `<slug>_model_v<NNN>.blend` | ✅ |
| 动作母版（形态 B） | `<slug>_animation_v<NNN>.blend` | ✅ |
| 视觉件 GLB | `<slug>_visual_top3d.glb` | ❌ |
| 运行包装 | `<slug>_root_top3d.tscn` | ❌ |
| 资产清单 | `<slug>_manifest_v<NNN>.json` | ✅ |
| 严格中转 | `<slug>_transfer_ledger_v<NNN>.json` | ✅ |
| 预览图 | `<slug>_<front\|side\|back\|top\|overview>_v<NNN>.png` | ✅ |

部件件名在主 slug 后追加部件槽：`<slug>_<槽>_visual_top3d.glb`（如 `chr_npc_vendor01_head_visual_top3d.glb`）。

### 3.4 版本号落点（白名单，只有 4 处）

1. `source/**` 的**文件名与目录**（Blender 历史唯一保留地）
2. `asset_manifest.json` / `*_manifest_v<NNN>.json`
3. 分账本《资产主表》的**「版本」列**
4. Prefab 根节点的 `metadata/asset_version`

GLB 去版本后，这 4 处是**唯一溯源入口**；替换时必须同步写入，缺一即视为丢失溯源，门禁应拦下。

### 3.5 禁止项

- ❌ `components/` 或 `runtime/` 路径含 `_v<NNN>`（**新增**禁止）
- ❌ `src/**/*.gd` 出现 `_v0NN` 形式的资产路径
- ❌ 派生 `_v002.tscn` 与 `_v001.tscn` 并存；替换**只有覆盖同名文件**一种方式
- ❌ 工作区保留 `*.bak_*`（回滚靠 git）
- ❌ 新建 `bosses_v02/`、`v022/` 这类版本目录

---

## 4. D3 冻结条款（2026-09-17 主人指示，不可绕过）

> **存量带版本号的文件名视为正式命名，不再追改；门禁只保证「不新增」。**

| 套件 | 存量欠账 | 状态 |
|---|---|---|
| `characters/player` | 144 文件 / 13 个 `production/vNNN/` 目录 | ❄ B8 冻结 |
| `enemies/enemy_3d` + `elite_3d` + `bosses_v01` | 16 文件 | ❄ B7 冻结 |
| `weapons/weapon_3d` + `melee_3d` | 130 文件 | ❄ B5 冻结 |
| 已完成的 B1/B2/B3/B4/B6 | 已清零 | ✅ 不回滚 |

**执行口径**：
- 新增资产**必须**符合 §3；存量资产**照原样引用、照原样登记**，不得顺手改名。
- 台账「文件路径」列对存量写实际路径（带版本号），对新增写契约路径（不带版本号）——**两者并存是正确的**，不要试图统一。
- 门禁 `python3 scripts/check_asset_runtime_naming.py` 只查「新增」；存量在 `scripts/asset_runtime_naming_debt.json` 快照内。
- 细节见 `docs/v0.1/development/2026-09-17_godot_asset_deversioning_plan.md` 的 D1/D3 与 N1–N6 规则。

---

## 5. 新增资产的落盘流程（账本先行）

1. **定域**：读 `ledger_index.json` → 确定 `domain`、`大类`、`art_root`、责任 skill。
2. **登记**：在**该域分账本**《资产主表》新增一行，至少填

   `AssetID` · `中文名` · `大类` · `子类` · `逻辑ID/源键` · `组件槽` · `变体父ID` · `视角` · `状态/动画` · `复用范围` · `制作状态` · `优先级` · `版本` · `文件路径` · `源码/策划依据` · `SHA-256` · `负责人` · `来源/许可` · `源编号（Blender collection）`
3. **查重**：`查重结果` 列必须为 `唯一`。为 `重复` 时**禁止制作**，先合并或建立变体父子关系。
4. **建目录**：按 §2 形态 A 展开，路径写回《资产主表》「文件路径」列。
5. **制作 / 导出 / 验收**：走 S1 → S5。
6. **推进状态**：`design_only → authored → exported_pending_godot_validation → validated → active`，**不可跳级**。
7. **门禁**：`python3 scripts/check_asset_registry.py --ledger <域>`（结构 + 跨账本契约：每个 AssetID 全库恰好出现一次）。

---

## 6. NPC 与怪物的具体落位

### 6.1 NPC（新增链路，形态 A）

```text
assets/art/characters/npc/<slug>/
├─ source/<slug>_source_v001.blend
├─ components/<slug>_visual_top3d.glb
└─ runtime/<slug>_root_top3d.tscn
```

| 项 | 取值 |
|---|---|
| AssetID | `CHR-NPC-<NAME>`（如 `CHR-NPC-VENDOR01`）；部件 `CHR-NPC-<NAME>-<SLOT>` |
| slug | `chr_npc_<name>`（如 `chr_npc_vendor01`） |
| 大类 / 子类 | `角色` / `npc`、`npc_component`、`npc_accessory`（与玩家子类命名法对齐） |
| 骨架 ID | `SKEL-NPC<NN>-<NNN>`，独立于玩家 `SKEL-BUNNY01-004` |
| 状态集 | **`idle` + `talk`** 两态起步（未来可扩展；本期不引入移动/战斗态） |
| 槽位 | 复用玩家七槽名（`Body`/`Head`/`Hands`/`Feet`/`Hat`/`Glasses`/`LowerBody`）以留扩展口，**首版只需 `body` + `head`** |
| 账本归属 | `characters` 域 → `ledgers/ShellStorm2_角色账本_v001.xlsx`（该域 scope 已声明涵盖 NPC） |
| 分页 | 《角色组件》《动画与状态》《3D-角色》；NPC 状态集写入《动画与状态》 |

**NPC 不套用形态 B**：无 production/vNNN、无 variants 多代。NPC 是静态交互定位，单代三段式足够；未来若需多套外观，用 `组件槽` + `变体父ID` 扩展，不引入版本目录。

### 6.2 怪物（形态 A + 形态 C）

| 族群 | 目录 | 模板来源 | 现状 |
|---|---|---|---|
| 普通怪 ×7 | `assets/art/enemies/enemy_3d/<slug>/` | 照抄 `elite_3d/rift_boar_armed/` | 全部 `程序占位`，待建 |
| 生态套件 | `assets/art/enemies/enemy_3d/`（存量根节点冻结） | — | 已有 `enm_ecosystem_kit_root_top3d_v001.tscn` |
| 精英 | `assets/art/enemies/elite_3d/<slug>/` | 已定型 | 1/12 完成（`rift_boar_armed`），其余 11 只 `design_only` |
| Boss | `assets/art/enemies/bosses/<slug>/` | 照抄 `elite_3d/rift_boar_armed/` | 存量 3 只**裸 GLB**，需补 runtime 包装 |

| 项 | 取值 |
|---|---|
| AssetID | 普通怪 `ENM-<职能码>-<NAME>01`；精英 `ENM-ELITE-<NAME>-3D`；Boss `ENM-BOSS-<NAME>-<层号>` |
| slug | 见 §3.2 |
| 变体父ID | 一律指向 `ENM-ECOSYSTEM-KIT-3D`（共享生态根） |
| 状态集 | `src/enemy3d/Enemy3D.gd` 的 `VALID_STATES` 12 态，逐字取自代码；写入《敌人动画与状态》 |
| 账本归属 | `enemies` 域 → `ledgers/ShellStorm2_敌人账本_v001.xlsx` |
| 分页 | 《3D-敌人》《敌人动画与状态》 |

**Boss 待改造（P0）**：`bosses_v01/` 下 3 个 `.glb` 裸文件被 `BossContentCatalog.gd` 的 `presentation_scene` 直接加载，违反「禁止运行时直接加载裸 GLB」。改造时**新建 `bosses/<slug>/{source,components,runtime}/`**，把 GLB 移入 `components/`，在 `runtime/` 建包装，改 `BossContentCatalog` 引用；存量 `bosses_v01/` 按 D3 冻结保留，不删不改名。

---

## 7. 自检清单（每项新增资产卡片级）

- [ ] AssetID 已在**所属域分账本**《资产主表》登记，且查重结果为 `唯一`
- [ ] 目录落在该域 `art_root` 下的 `<slug>/`，形态为 A 或 C
- [ ] `source/` 文件名带 `_v<NNN>`；`components/`、`runtime/` **不带**
- [ ] 账本「文件路径」列与实际落盘路径逐字一致
- [ ] 骨架 ID 被模型母版与动作母版共同引用，导出时签名比对通过
- [ ] 没有在 `src/**/*.gd` 里硬编码带版本号的资产路径
- [ ] 制作状态按 `design_only → authored → exported → validated → active` 推进，未跳级
- [ ] `python3 scripts/check_asset_registry.py --ledger <域>` 与 `python3 scripts/check_asset_runtime_naming.py` 通过
