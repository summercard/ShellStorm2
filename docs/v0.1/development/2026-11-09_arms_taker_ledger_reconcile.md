# 收租人台账对账：根场景登记回填（账本 v0.1.39）

- 日期：2026-11-09
- 范围：ELITE-ROSTER / ASSET-PIPELINE
- 资产：`ENM-ELITE-ARMS-TAKER-3D`
- 触发：业主「更新账本」（承接同日 r14 补底柱、r15 体型 1.5 倍起 / 12 级 3 倍两轮改动）

## 1. 对账结论

账本正文（xlsx）在 r15 那一轮已经改到位：资产主表 r55、3D-敌人 r11、域变更日志 v0.1.37 / v0.1.38 都是 3 倍口径，内容库《精英怪》r12 也是。**真正没跟上的是两份资产级 JSON 台账**，它们停在 2026-11-04 的 v002 快照。

| 文件 | 条目 | 旧登记 | 实物 | 结论 |
|---|---|---|---|---|
| `enm_elite_arms_taker_manifest_v002.json` | `runtime_files` → 根场景 | 830 B / `92dfd166…` | 1138 B / `5b63de8d…` | 陈旧 |
| `enm_elite_arms_taker_transfer_ledger_v002.json` | `outputs` → 根场景 | 830 B / `92dfd166…` | 1138 B / `5b63de8d…` | 陈旧 |
| `enm_elite_arms_taker_transfer_ledger_v002.json` | `outputs` → 清单自身 | 22067 B / `a9f6a9ec…` | 随清单改动而变 | 需同步 |

xlsx 这一侧本来就是对的：资产主表第 20 列与 Y 备注里的 `5b63de8d…` 与实物一致。也就是说，**同一个哈希在两套台账里一边对这一边错**，这类分叉比单纯过期更难发现，因为翻 xlsx 看不出来。

## 2. 改法

只做定点文本替换，不重排 JSON：

1. `manifest_v002.json`：根场景条目 `bytes` 830 → **1138**、`sha256` → `5b63de8d11ff2f9ded71d00ce12253092e51f2fc14273369257c848838d9fe69`。清单自身因此变成 **22068 B**、`67b1b59e66a70ab3428b4f95f54d7a535608f09e3a17c12f4e65b95a9dcad54f`。
2. `transfer_ledger_v002.json`：根场景条目同样回填；清单自身条目改为 22068 B / `67b1b59e…`。
3. 两份文件都保持 **CRLF 行尾**、键序与缩进原样（用 `io.open(..., newline='')` 读写，不做 `json.dump` 重排 —— 重排会把 651 / 491 处行尾与数组换行全部改写，diff 无法审阅）。

## 3. 校验

- **逐条哈希**：`manifest.runtime_files` 29 条、`transfer_ledger.outputs` 30 条，全部按「读实物 → sha256 + 字节数」复核，**mismatch 0 / missing 0**。
- **JSON 合法性 + 行尾**：两份均 `json.loads` 通过、`crlf` 651 / 491、孤立 LF 0。
- **xlsx 未被这次改动影响**：`ArrayFormula` 仍 50 个，六张表 `dims / freeze / dataValidation / conditionalFormatting / merged / columnDimensions` 与改前逐项相同。
- **门禁**：`check_asset_registry.py` 改动前后均为 **issues=331**，且 6 条结构化 issue 集合**完全相同**（0 新增 0 消失）；`check_ledger_refs.py` 退出 0（`LEDGER_REFS_OK pending=0 allowed=2 dangling=0`）；`check_media_asset_domains.py` 退出 0（`MEDIA_ASSET_DOMAINS_OK domains=3 assets=213`）；`check_documentation_contracts.py` 仍是 14 条既有断链，本次新增文档无一条断。
- **运行时不读这两份 JSON**：`src/`、`scenes/` 下无任何引用，改哈希不影响加载。

## 4. 账本内新增的记录

- 《域变更日志》新增 **v0.1.39「收租人台账对账（根场景哈希回填）」**，说明旧值、新值、清单位置变化与「不动资产文件」的兼容性。
- 《资产主表》r55 第 25 列（Y）备注追加同一段对账说明，避免下次有人只看主表以为两份 JSON 也是对的。

样式沿用 r80 的单元格样式与行高；`v0.1.38` **不改写**（它是体型变更的记录，本轮是台账纠错，两件事分开记）。

## 5. 顺带查出、但没动的既有漂移

对全账本做了路径存在性审计：304 处路径引用中 7 处不存在，其中 1 处是本轮新写措辞造成的假阳性（已改写），其余 **6 处属于别的资产，与本次改动无关**，原样保留待各自负责人确认：

| 位置 | 登记路径 | 磁盘实际 |
|---|---|---|
| 资产主表 P7、3D-敌人 E8 | `…sporeshooter01_model_v001.blend` | 只有 `…_model_v007.blend` |
| 资产主表 P7、3D-敌人 E8 | `…sporeshooter01_animation_v002.blend` | 只有 `…_animation_v005.blend` |
| 敌人动画与状态 G21 | `…fungboar01_animation_v003.blend` | 只有 `…_animation_v005.blend` |
| 域变更日志 E66 | `…infected01_model_v001.blend` | 只有 `…_model_v002.blend` |
| 资产主表 P8 / P9 / P10 | `src/enemy/EnemyTypes.gd` | 全仓无此文件 |
| 资产主表 P12 | `src/enemy/BossAvatarRenderer.gd` | 全仓无此文件 |

没顺手改的理由：这几行是别人的资产，**改版本号等于替对方宣布「当前用 v007 / v005」**，而磁盘上同时存在 v001—v007 多版，谁是出货版只有原作者知道；`src/enemy/*.gd` 那两个要么被合并要么被删，猜一个替代路径就是把错写在账本上。

## 6. 未做

- `asset_guard.py` 仍不认 `enm_elite_arms_taker_transfer_ledger_v002.json` 这个命名（它只找 `…_transfer_ledger.json` / `character_transfer_ledger.json` / `runtime/character_transfer_ledger.json`），所以该资产包的守门检查依旧报「找不到台账」。改名会牵动清单自引用与 `入库说明.md`，属结构决策，未动。
- 主账本《版本记录》未加行：本次只改本域资产级台账，未跨域、未改分类与命名，按「跨域才进主账本」的既有约定不入。
- 未在 Excel / WPS 里实际打开确认渲染（与上一轮一致）。
