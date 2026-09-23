# 美术资产账本（registry）入口

本目录是项目美术资产的**唯一登记入口**。

自 2026-09-23 起，登记结构为「**总目录 + 9 个分账本**」：角色、敌人、场景、道具、武器、特效、UI、音效、音乐九条生产线可以**并行编辑各自的账本**。
2026-09-18 的初始拆分由 `ledger_split_baseline.json` 保留；2026-09-23 受控媒体迁移另由 `media_domain_split_manifest.json` 声明，除「账本归属/大类」外不改 AssetID、路径、哈希、状态或授权。

## 1. 目录结构

| 路径 | 角色 | 内容 |
|---|---|---|
| `ShellStorm2_美术资产台账_v001.xlsx` | **总目录**（索引） | 只放跨域契约与索引：`总览` / `分账本索引` / `分类与编码` / `命名与查重` / `版本记录` / `3D Prefab总控` / `Skill清单`。**不含任何资产行。** |
| `ledgers/ShellStorm2_角色账本_v001.xlsx` | 分账本 | 角色域资产条目与角色专用分页 |
| `ledgers/ShellStorm2_敌人账本_v001.xlsx` | 分账本 | 敌人物 |
| `ledgers/ShellStorm2_场景账本_v001.xlsx` | 分账本 | 关卡场景域（含场景道具、基地资产包） |
| `ledgers/ShellStorm2_道具账本_v001.xlsx` | 分账本 | 可拾取/可消耗/可交互道具 |
| `ledgers/ShellStorm2_武器账本_v001.xlsx` | 分账本 | 枪械、近战武器、子弹与配件 |
| `ledgers/ShellStorm2_特效账本_v001.xlsx` | 分账本 | 可独立实例化的 3D 特效 |
| `ledgers/ShellStorm2_UI账本_v001.xlsx` | 分账本 | HUD、页面、面板、图标与焦点表现 |
| `ledgers/ShellStorm2_音效账本_v001.xlsx` | 分账本 | 短时 SFX、事件键、运行 OGG 与源母版 |
| `ledgers/ShellStorm2_音乐账本_v001.xlsx` | 分账本 | BGM、A/B 曲目、循环与场景触发 |
| `ledger_index.json` | **单一真源**（机器可读） | 「域 → 文件 → 大类 → AssetID 前缀 → Prefab 分页 → 责任 Skill」的唯一映射 |
| `ledger_split_baseline.json` | 拆分无损基线 | 拆分前单体账本的逐格快照，供无损证明比对 |
| `*.xlsx.bak_*` | 备份 | 历史批次与拆分前的快照，只作回溯，不参与任何流程 |

每个分账本的资产行**只落在《资产主表》**；`3D-场景通用` / `3D-设施` / `3D-武器` 等分页只是 Prefab 分类视图，
与《资产主表》用同一个 AssetID 关联。

### 九个分账本

| 域 key | 账本 | 大类 | AssetID 前缀 | 责任 Skill |
|---|---|---|---|---|
| `characters` | 角色账本 | 角色 | `CHR` `SKEL` `BONE` | `game-character-model-pipeline` |
| `enemies` | 敌人账本 | 敌人 | `ENM` | `game-character-model-pipeline` |
| `scenes` | 场景账本 | 场景 / 场景道具 / 基地资产包 | `ART` `ENV` `BPK` `PRP` | `scene-full-pipeline` |
| `props` | 道具账本 | 道具 | `ITM` `PRP` | `game-prop-model-pipeline` |
| `weapons` | 武器账本 | 武器 | `WPN` | `game-weapon-model-pipeline` |
| `vfx` | 特效账本 | 特效 | `VFX` `FX` | `vfx-combat-effect-authoring` |
| `ui` | UI账本 | UI | `UI` | `ui-asset-pipeline` |
| `audio` | 音效账本 | 音效 | `AUD` | `audio-sfx-asset-pipeline` |
| `music` | 音乐账本 | 音乐 | `AUD` | `music-asset-pipeline` |

> `PRP` 同时服务场景域与道具域，`ART`/`ENV` 同属场景域 —— **前缀有歧义**，归属一律以《资产主表》的「大类」列为准，
> 不要靠前缀猜。`LedgerIndex.domain_for_asset_id()` 对歧义前缀会返回 `None`，请改用 `domain_for_category()`。

## 2. 不许硬编码路径

`ledger_index.json` 是唯一映射源。**任何门禁、写入工具、脚本、Skill 都不得写死账本文件名**，
也不得假定「某个分页还在总目录里」。

解析入口 `scripts/ledger_registry.py`：

```python
from ledger_registry import LedgerIndex

index = LedgerIndex.load(project_root)
index.path_for_category("武器")          # assets/registry/ledgers/ShellStorm2_武器账本_v001.xlsx
index.domain_for_category("基地资产包")   # Domain(key='scenes', ...)
index.domain_for_sheet("3D-场景通用")     # Domain(key='scenes', ...)
index.path_for_asset_id("WPN-...")        # 前缀有歧义时返回 None
index.rewrite_ref("assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用")
```

命令行自检：

```bash
python scripts/ledger_registry.py
python scripts/ledger_registry.py --category 武器
python scripts/ledger_registry.py --asset-id VFX-COMBAT-KIT-3D
```

## 3. 旧引用怎么处理

### 3.1 `asset_ledger` 字段：只有 `#分页` 可信

全仓 834 份 `asset_manifest.json` 里，`asset_ledger` 的历史写法并不统一：

| 写法 | 文件数 | 说明 |
|---|---|---|
| `assets/registry/ShellStorm2_美术资产台账_v002.xlsx#3D-场景通用` | 46 | **该文件从来不存在** —— 拆分之前就断链 |
| `assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用` | 163 | 拆分前的总目录路径，`resolve_ref()` 可解析 |
| 根本没有 `asset_ledger` 键 | 627 | — |

结论：**字段里的文件部分不可信，只有 `#分页` 有意义。** 消费方一律经
`LedgerIndex.domain_for_sheet(分页)` / `resolve_ref()` 解析到真正拥有该分页的分账本。

- **不要**为了「路径好看」批量重写历史资产包里的 `asset_ledger` —— 那是产出记录，改了就是篡改历史。
- **新批次**一律写分账本路径；`index.rewrite_ref(旧引用)` 可直接得到规范形式，且幂等。

### 3.2 批次 QA 脚本：重放前必须重定向 + 重定行号

`assets/art/**/qa/` 与 `source/art/**/qa/` 下还有 **21 个会读写账本的脚本**
（`update_registry.mjs` / `verify_registry.py` / `update_ledger_rows_v00N.py` / `register_*_ledger_rows.py`…），
它们仍直接打开总目录，并且用的是**单体账本的《资产主表》行号坐标** —— 一部分直接按 `sheet10` 的
`<x:row r="N">` 做 XML 补丁。

- 这些是**已完成批次的生产工具**，不是「改个路径就行」：分账本里行号已经平移，**只换路径必然失配**。
- 重放前先把目标改成该域的分账本，再把行号重定为「按 AssetID 定位」或分账本行号。
- 因此 `xlsx-git-conflict-resolution` 里「重放补丁脚本」的做法，对**拆分前**的批次脚本不成立，必须先做上述重定。
- 新批次不要照抄这些脚本；写账本走 `scripts/ledger_registry.py`。

### 3.3 随时复查

```bash
python scripts/check_ledger_refs.py                                  # 退出码 1 = 有待处理脚本
python scripts/check_ledger_refs.py --json-output _scratch/ledger_refs.json
python scripts/check_ledger_refs.py --allow-pending                  # 仅报告，不置失败
```

它把引用分成四类：待处理脚本（21）/ 设计允许（注册表工具）/ 指向不存在账本的文件（46）/ 历史记录（190）。

## 4. 校验与门禁

```bash
python scripts/check_asset_registry.py                     # 全部账本 + 跨文件契约（默认 full）
python scripts/check_asset_registry.py --scope structure   # 结构+枚举；当前仍报5条P0「白盒组件」状态债务
python scripts/check_asset_registry.py --ledger 武器        # 只查一个域
python scripts/check_asset_registry.py --workbook <xlsx>   # 单文件 legacy 模式（不做跨文件断言）
python tools/asset_pipeline/verify_ledger_split.py         # 拆分无损证明：并集 / 缺失 / 漂移
python scripts/check_media_asset_domains.py                 # UI / 音效 / 音乐账本、Skill 和验收入口
python tools/asset_pipeline/refresh_asset_registry_hashes.py --ledger 场景 --dry-run
python scripts/classify_asset_repository.py                # 仓库文件 → 账本行对照
python scripts/check_ledger_refs.py                        # 旧账本引用审计（见 3.3）
```

`check_asset_registry.py` 强制的**跨文件契约**：

1. 每个 AssetID **恰好出现一次**，不跨分账本重复；
2. 总目录**不得**出现资产行；
3. 总目录《分账本索引》与 `ledger_index.json` **逐格一致**；
4. 《3D Prefab总控》的「归属账本」列必须指向**真正拥有该分页**的账本；
5. 每本账本内：AssetID 形状、大类枚举、前缀×大类组合、派生列公式形状、总览公式跨度 = 本账本行数。

## 5. 重新拆分 / 刷新

```bash
python tools/asset_pipeline/split_asset_ledger.py --plan          # 只打印拆分计划，不落盘
python tools/asset_pipeline/split_asset_ledger.py                 # 幂等重建 9 账本 + 总目录（先备份总目录）
python tools/asset_pipeline/split_asset_ledger.py --source <单体账本>
```

拆分脚本是**幂等**的：源为总目录时按 `ledger_index.json` 重算各分账本；源为历史单体账本时先建基线再拆。
派生列（查重键 / 查重结果）的公式只有 `split_asset_ledger.py` 一处定义，其余工具与校验器一律 import，
不得另抄一份。

## 6. 相关文档

- 资产与内容规范：[`docs/v0.1/10_资产与内容规范.md`](../../docs/v0.1/10_资产与内容规范.md)
- 3D 场景美术生产流程：[`docs/v0.1/10.1_3D场景美术生产流程.md`](../../docs/v0.1/10.1_3D场景美术生产流程.md)
- Prefab 分类与目录命名：[`assets/art/3D模型资产目录与命名规范.md`](../art/3D模型资产目录与命名规范.md)
- 二进制 xlsx 冲突处理：Skill `xlsx-git-conflict-resolution`
