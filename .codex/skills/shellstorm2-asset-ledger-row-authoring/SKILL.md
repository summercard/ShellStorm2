---
name: shellstorm2-asset-ledger-row-authoring
description: 在 ShellStorm2 的分账本（敌人/角色/场景/道具/武器/特效/UI/音乐/音效）里新增、修改或核对一行资产登记——改《资产主表》、同步所有写死的公式区间、补录无损基线、跑门禁。当用户说「把 XXX 登记进账本 / 加个新资产 / 给这个模型编号 / 台账表格加一行」时使用。不用于制作资产本身，也不用于 3D Prefab 分页表的随意改动。
agent_created: true
---

# ShellStorm2 分账本 · 资产行登记

## 先认清结构（别凭记忆）

- **机器可读真源**：`assets/registry/ledger_index.json` —— 域→文件→大类→AssetID 前缀→Prefab 分页的唯一映射。
  与它冲突时以它为准。**域数已扩到 9**：characters / enemies / scenes / props / weapons / vfx / ui / audio / music。
- **总目录**（只放索引，**不登记任何资产行**）：`assets/registry/ShellStorm2_美术资产台账_v001.xlsx`
  —— 只有跨域契约表：总览 / 分账本索引 / 分类与编码 / 命名与查重 / 版本记录 / 3D Prefab总控 / Skill清单。
- **分账本**：`assets/registry/ledgers/ShellStorm2_<域>账本_v001.xlsx`，敌人域的专表是
  《敌人动画与状态》+《3D-敌人》。**AssetID 必须只出现在一个分账本里。**
- 规则原文在总目录《分类与编码》《命名与查重》，**必须去读**，别自己发明子类/前缀。

## 三条硬规则

| 项 | 规则 |
|---|---|
| 页签 | 分账本固定四件套 + 域内专表：`总览 / 账本说明 / 资产主表 / 域变更日志` |
| 表头行 / 首数据行 | 见 `tools/asset_pipeline/split_asset_ledger.py` 的 `HEADER_ROW` / `FIRST_DATA_ROW`；**从权威常量取，别硬编码** |
| 派生列 | R=查重键、S=查重结果，**必须用 `dedupe_key_formula(row)` / `dedupe_result_formula(row, last)` 生成**，不要手写 |

《资产主表》25 列（A–Y）：AssetID / 中文名 / 大类 / 子类 / 逻辑ID-源键 / 组件槽 / 变体父ID / 视角 /
状态-动画 / 复用范围 / 制作状态 / 优先级 / 版本 / 规格 / 文件路径 / 源码-策划依据 / 关键词-别名 /
**查重键**(派生) / **查重结果**(派生) / SHA-256 / 负责人 / 更新时间 / 来源-许可 / 源编号 / 备注。

AssetID 正则 `^[A-Z0-9]+(?:-[A-Z0-9]+)+$`；制作状态 ∈ `ACCEPTED_STATUSES`；
优先级 ∈ `{P0,P1,P2}`（下拉里多一个 P3 但门禁不接纳）；「待制作 / 程序占位 / 弃用」**不检查路径与 SHA**。

---

## 🔴 新增一行要同步改的东西（漏一处就静默出错或门禁变红）

1. **`资产主表` 的 S 列要逐行重写成覆盖新行**：`dedupe_result_formula(r, last)` for r in 首数据行..新行。
   否则新行的 `COUNTIF($R$6:$R$17, R18)` **永远判「唯一」**（区间不含自己）。
2. **`总览` 的写死区间**：`A6 / C6 / E6 / G6 / B10 / C10 / B11 / C11` 全部要从 `$…$<旧末行>` 改成新末行。
   门禁 `check_asset_registry.py` 会断言「总览公式范围 == 本账本行数」（`stale_overview_formula`）。
3. **DataValidation 的 sqref**：`C6:C17 / K6:K17 / L6:L17` 要扩到新行，否则新行没下拉框。
4. **`域变更日志`** 追加一行（版本号 +1，如 v0.1.2 → v0.1.3）。
5. **`无损基线`** `assets/registry/ledger_split_baseline.json` 必须补录（见下）。

### ⛔ 三个必踩的坑

- 🔴 **字符串陷阱**：`"C6:C17"` 里**不存在**子串 `":17"` —— 冒号后面跟的是第二个引用的**列字母**。
  `"C6:C17".replace(":17", ":18")` 返回原串，静默不改。要改就用 `":C17"`，
  或者干脆用行号算（`f"C6:C{last}"`）。**这一坑实测浪费了两轮。**
- 🔴 **openpyxl 的 DataValidation**：`str(dv.sqref)` 返回的是 `<MultiCellRange [C6:C17]>` 这种 repr，
  拿它做 replace 会拼出非法区间、赋值被**静默丢弃**。正确做法：取 `list(dv.sqref.ranges)` → `str(rng)`，
  然后**重建** `DataValidation(type, formula1, allow_blank, …)` 再 `ws.add_data_validation(ndv)`。
  写完**必须回读 xlsx 的 zip 层**确认 `<dataValidations sqref="…">`。
- 🔴 **S 列不能靠 `insert_rows`**：openpyxl 不重算公式引用，插行会把区间关系搞坏。**一律追加到末行**。

### 样式

`from copy import copy; ws.cell(new_row, col)._style = copy(ws.cell(模板行, col)._style)`，
模板行选**同形态的行**（未实现的普通怪行 vs 已完成的 3D 行）；再 `ws.row_dimensions[new].height =
ws.row_dimensions[模板行].height`。日期列穿同款数字格式即可（复制 style 会带过来）。

---

## 🔴 无损基线：冻结资产集合的硬门禁

`tools/asset_pipeline/verify_ledger_split.py` 在 L119-121 对**任何不在基线里的 AssetID**
直接 `fail("asset_not_in_baseline")` —— 它**不区分**「被静默新增」和「有意新增」。
⇒ 新增资产后必须补录基线，否则这门禁长期红。

- ⛔ **绝对不要跑 `split_asset_ledger.py --baseline-only`**！它从 `ledger_index.json` 的 `master.path`
  读《资产主表》，而总目录**已不持有资产行** ⇒ 会把 409 行基线**清空**，反过来制造 409 条 `asset_lost`。
- ✅ 正确做法（最小外科编辑，见 `tools/ledger_reconcile_baseline_spikeshell.py` 模板）：
  1. 备份 `ledger_split_baseline.json` → `.bak_<tag>`；
  2. 用 `read_source_rows(ws)` 读新行，`_row_digest(values)` 算指纹，
     `bl["assets"][ID] = {"v": digest, "c": 大类, "d": 域key}`；`bl["asset_count"] = len(bl["assets"])`；
  3. 遍历 `index.domains` 汇总所有行，重算 `column_digests`（`CONTENT_COLUMNS` × `col_digest`）与
     `category_counts`；**其余资产的 `v` 保持原值不动**（历史投放/篡改仍能被抓）；
  4. 按 `json.dumps(..., ensure_ascii=False, indent=1) + "\n"` 写回。
  基线自身的 `source` 就是 `assets/registry/ledgers (current runtime-truth reconciliation)`，
  即「从当前分账本重建」是既有口径。
- `column_digest_drift` 与 `extra_assets` **只在报告里出现，不 fail**；唯一 fail 的是 `missing` 与
  `asset_not_in_baseline`。

## 🚫 摘要锁死的表（改了就 fail，`moved_sheet_mutated`）

`3D-*` / `角色组件` / `动画与状态` / `原型角色` / `角色中转记录`
（即 `sheet_digests` 里记录的域内专表）。新增怪要加《敌人动画与状态》行时，
**必须单独开一次事务**，连带重建基线，不能和"加资产行"混在一起。

另外《3D-敌人》这类 Prefab 分页自己声明「一行 = 一个实际存在的 Godot PackedScene」——
**没有 Prefab 就不能加行**。

---

## 跑门禁的标准姿势

```bash
export PATH="/c/Program Files/Git/usr/bin:$PATH"
PY="C:/Users/zhuangmenghong/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
mkdir -p "I:/工作项目/shellstrom2/_scratch/ledger_gate_cwd"
cd "I:/工作项目/shellstrom2/_scratch/ledger_gate_cwd"       # ASCII cwd，避开工作区 inspect.py 遮蔽
R="I:/工作项目/shellstrom2/ShellStorm2"

"$PY" "$R/scripts/check_asset_registry.py" --project-root "$R" --scope structure   # 期望 ASSET_REGISTRY_CHECK_OK
"$PY" "$R/scripts/check_asset_registry.py" --project-root "$R" --scope full --ledger 敌人
"$PY" "$R/tools/asset_pipeline/verify_ledger_split.py" --project-root "$R"          # 期望 LEDGER_SPLIT_VERIFY_OK
"$PY" "$R/scripts/check_asset_runtime_naming.py"                                    # 注意：**不接受 --project-root**
```

- **退出码别用管道取**（`| tail` 会把 `$?` 变成 tail 的）。用 `run(){ …; echo "EXIT=$?"; }` 落到文件再 grep。
- `--scope full` 会报**既有红项**（敌人域实测 4 条 `sha_mismatch`，落在 r6/r7/r13/r17）
  —— 那是账本记录哈希与磁盘 tscn 早已不符，与你的改动无关。**必须做反向对照**：
  比对该列**改前/改后逐格相同** + `git status --porcelain <资产目录>` 为空，才能说「非本次引入」。
- 敌人域的 `check_asset_registry` 走 `--ledger 敌人`；不带 `--ledger` 是 structure 全量。

### 文档侧状态表 × 账本：同步门禁

设计页/规范页里若有一张「资产完成情况」表，它必须与账本同步 —— 已经在跑的先例是远征关卡01：
`docs/v0.1/design/远征关卡01设计.md` §3.1.1 ↔ `scripts/check_expedition_room_asset_status.py`（先例建于 2026-09-24）。

判据五条：**A** 文档里的 AssetID 账本必须有；**B** 账本推出的级别必须出现在同行「账本制作状态」列；
**B2** 该行的汇总「级别」列必须等于「账本制作状态」列里出现过的**最低**级；**C** 账本里的相关行不许被文档漏写；
**D** 每个房型源目录必须「已在账本登记」或「已在文档里显式标为未登记」。

🔴 **B2 是补出来的洞 —— 写这类门禁，必须给每条判据各配一个负向自测**：最初只核「账本制作状态」列，
把汇总的「级别」列改坏**不报红**，而那恰是人最先读的一列。自测落在
`tests/tooling/test_check_expedition_room_asset_status.py`（对照组 + 四类不一致，每类断言一次 exit 1）；
为跑自测给门禁加了只给测试用的 `--doc <设计页路径>` 入口，业务调用不带它。

## 读 xlsx 用哪个工具

- ⛔ **别用 sheetagent MCP 的 `resolve_local_excel`** 读本项目：它解析不了中文绝对路径
  （`I:/…` 被判非绝对路径，`/i/…` 被拼成 `i:\i\…`，实测报 `INVALID_LOCAL_PATH` / `LOCAL_PATH_NOT_FOUND`）。
- ✅ 用零依赖的 `tools/xlsx_read.py`（值）与 `tools/xlsx_formula_dump.py`（值 + 公式），
  stdlib `zipfile` + `ElementTree`，避开 openpyxl 在本机偶发的 OpenBLAS 报错。
  `--formula-only` / `--rows` / `--cols` 可精确定位。

## 写 xlsx：只用 openpyxl，⛔ 别让本地编辑器保存台账

🔴 实测（2026-09-23）：把《敌人账本》交给本地 editor_sdk / 腾讯文档编辑器链路
（`tencent-local-office-edit`），**只改了 3 个文本单元格**，`save_file` 后由编辑器引擎整体重写，结果：
- `R` 列查重键写成 `==LOWER(TRIM(C6)&…)` —— **多一个等号**（`<f>` 里存了 `=LOWER(...)`）
- `S` 列写成**数组公式**（openpyxl 读为 `ArrayFormula` 对象）
- ⇒ `check_asset_registry` + `verify_ledger_split` 共报 **28 条** `dedupe_key_formula_wrong` /
  `dedupe_result_formula_wrong`

值看着没错，**公式契约已被破坏**；且只要走 `save_file` 就会触发，与改了什么内容无关。

纪律：
- 台账 / 内容库的写入一律 **openpyxl**（既有先例：`ShellStorm2/_scratch/ledger_edit_backup/apply_enemy_ledger_promotion.py`）。
- 已经用编辑器写过时的止损顺序：**① 先 `close_file` 释放实例**（否则它内存里的脏内容可能回写覆盖磁盘）
  → ② 从 `.bak_*` 回滚 → ③ 用 openpyxl 重做。
- 回滚自检：`R6` 应以 `=LOWER` 开头且**不以 `==` 开头**；`S6` 含 `COUNTIF`（它是 `IF(COUNTIF(...))` 包裹式，
  别断言成 `startswith("=COUNTIF")`，会误判）。
- openpyxl 往返不会动 `dataValidations` / 公式形态 / `dimension`（实测 DV `C6:C18,K6:K18,L6:L18` 保留、
  `ArrayFormula` 计数 0）。

## 改既有行的名称（改名，不动 AssetID）

只改「名称」语义相关的格，别碰 AssetID / 逻辑ID / 内容ID（稳定字段）：

1. 备份（账本 / 内容库 / 基线）+ 冻结一份「改前」副本，供事后逐格对照
2. openpyxl 改账本：`资产主表` 的 `B`(中文名)、`Q`(关键词)；`域变更日志` 的 `E`(说明文字里旧名 `.replace()`)
3. openpyxl 改内容库：`怪物与Boss` 的 `B`(名称)；**顺带核 `N`(事实源) 引用的账本行号对不对** ——
   新增行脚本里极易把「内容库行号」当成「账本行号」写进去（实测踩过一次：r15 vs r18）
4. **基线补录是硬要求**：该行 `_row_digest` 必须更新（改名 ⇒ 行指纹变，否则 `asset_hash_mismatch`），
   并重算 `column_digests`（**9 域 union**）与 `category_counts`
5. 逐格对照冻结副本：差异格必须**恰好等于**预期改名点（实测账本 3 格 / 内容库 2 格，多一格都要追）
6. 四个门禁 + 退出码单独捕获；`--scope full` 的既有 4 条 `sha_mismatch` 照旧做反向对照

## 写之前的自检清单

- [ ] 读过《分类与编码》《命名与查重》，大类/前缀/子类都合规？
- [ ] AssetID 正则过？**没有和既有行重复**（含预登记行）？
- [ ] 制作状态在 `ACCEPTED_STATUSES` 里？若是「待制作/程序占位」⇒ 路径与 SHA 必须留空。
- [ ] 该不该动域内专表？会不会触发 `moved_sheet_mutated`？
- [ ] 前置断言写齐（表名 / 表头 / 行号 / 既有公式形态）？备份做了吗？
- [ ] R/S 用权威函数生成？总览 8 格 + DV 都扩了？
- [ ] 基线补录了？四个门禁跑过、退出码单独捕获了？
