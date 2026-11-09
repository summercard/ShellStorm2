# 收租人台账对账（账本 v0.1.39）

时间：2026-11-09 22:11 · 资产 `ENM-ELITE-ARMS-TAKER-3D`

## 做了什么

用户「更新账本」承接同日 r14 补底柱 / r15 体型 3 倍。核对后发现 **xlsx 正文已经到位**（资产主表 r55、3D-敌人 r11、域变更日志 v0.1.37/38、内容库《精英怪》r12 都是 3 倍口径），
真正没跟上的是**两份资产级 JSON**：

| 文件 | 条目 | 旧 | 实物 |
|---|---|---|---|
| `enm_elite_arms_taker_manifest_v002.json` | runtime_files → 根场景 | 830 B / `92dfd166…` | 1138 B / `5b63de8d…` |
| `…_transfer_ledger_v002.json` | outputs → 根场景 | 同 | 同 |
| `…_transfer_ledger_v002.json` | outputs → 清单自身 | 22067 B / `a9f6a9ec…` | 改后 22068 B / `67b1b59e…` |

**关键坑：同一个哈希在两套台账里一边对一边错** —— 资产主表第 20 列与 Y 备注的 `5b63de8d…` 一直是对的，所以只翻 xlsx 永远发现不了 JSON 那边停在 2026-11-04 快照。
以后核对资产哈希必须**两套都查**（xlsx 与 manifest/transfer_ledger）。

## 手法

- 只做**定点文本替换**（`io.open(newline='')` 读写），绝不用 `json.dump` 重排 —— 会改写 651 / 491 处 CRLF 与数组换行，diff 不可审。
- 清单自身字节变了 ⇒ 台账里"清单"那条也要跟着改（自引用链，容易漏）。
- 账本《域变更日志》新增 v0.1.39；**v0.1.38 不改写**（体型变更 vs 台账纠错，两件事分开记）。

## 校验

- manifest 29 条 + ledger 30 条逐条读实物复核：**mismatch 0 / missing 0**，CRLF 保持、JSON 合法。
- `check_asset_registry` 改前改后均 **331**、6 条结构化 issue 集合完全相同；`LEDGER_REFS_OK`、`MEDIA_ASSET_DOMAINS_OK` 退出 0；文档断链仍 14 条（新增文档 0 断）。
- 运行时不读这两份 JSON（src、scenes 无引用）。
- `ArrayFormula` 仍 50，六表 dims/dv/cf/merged/colw 不变。

## 顺带审计（未改）

304 处路径引用中 6 处属**别的资产**、文件已不存在：sporeshooter model v001→实际 v007、animation v002→v005；fungboar animation v003→v005；infected01 model v001→v002；`src/enemy/EnemyTypes.gd`、`BossAvatarRenderer.gd` 全仓无此文件。
没改的理由：多版本并存时谁是出货版只有原作者知道，猜路径等于把错写进账本。

`asset_guard.py` 仍不认 `_v002` 台账命名（只找 `…_transfer_ledger.json` / `character_transfer_ledger.json` / `runtime/character_transfer_ledger.json`），改名会牵动清单自引用与入库说明，未动。主账本《版本记录》按「跨域才进」的约定不入。

记录：`docs/v0.1/development/2026-11-09_arms_taker_ledger_reconcile.md`
