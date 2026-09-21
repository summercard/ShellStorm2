#!/usr/bin/env python3
"""写入 2026-09-21 事务文件与当日索引，并把账本细则补进 MEMORY-playbooks.md。

行尾约定：事务文件 = LF；_INDEX.md 与 MEMORY-playbooks.md = CRLF。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEM = ROOT.parent / ".workbuddy" / "memory"
DAY = MEM / "2026-09-21"
PLAYBOOKS = MEM / "MEMORY-playbooks.md"

TRANSACTION = """# 100F 天台装饰接入 · 场景账本跟进（域变更日志 v0.1.4）

时间：2026-09-21 07:26
类型：**实际改动（账本 + 文档）**
前置：上一轮已把 11 类装饰导出并接入运行时，但账本没跟。

## 起因
主人一句「账本也要跟着更新啊」。上一轮交付里组件库从 44 包涨到 47 包、11 类装饰从「Blender源已完成」变成「已导出+已接入」、还多了一份 100F 天台装饰布局 —— 账本一条都没动。

## 账本真实结构（容易踩错）
- `assets/registry/ShellStorm2_美术资产台账_v001.xlsx` = **总目录**，`asset_rows=0`，不含资产行。
- 资产条目在 `assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`：《资产主表》= 唯一登记源（234 → 235 行）、《3D-场景通用》等 = Prefab 视图、《域变更日志》。
- `ENV-ROOFTOP-REF-*` 家族登记在《3D-场景通用》；主表里只有 1 条库行 `ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY`（R238）。

## 改了什么
| 位置 | 改动 |
|---|---|
| 主表 R238 | 44包 → **47包**；复用范围改「装饰件已按布局接入运行场景」；SHA `ca091c6d… → d9e96fa1…`；更新时间 2026-09-21；备注写方案A + 11 类接入 |
| 主表 **R240（新增）** | `ENV-ROOFTOP-DECOR-LAYOUT-100F` 100F天台装饰布局，SHA 指向布局 Blend |
| 专页 11 行 | R113/115/118/119/120/121/122/125/126/127/128：Prefab=`runtime/<slug>.tscn`、GLB=`components/env_rooftop_ref_<slug>_top3d.glb`、功能脚本=`src/world3d/TowerFloorStage3D.gd`、碰撞=无/`引擎（visual_only）`、状态=正式美术已接入 |
| 专页 G96 | 库行说明改为 47 包 + 方案A + 11 件接入 |
| 专页 **G146（新增）** | 布局登记行（与主表 R240 同 AssetID） |
| 域变更日志 | 追加 **v0.1.4** |
| 连带扩容 | S 列查重公式 234 行、DV×3、CF×2、autofilter、总览 10 格：`$R$6:$R$239 → $R$6:$R$240` |

**AssetID 纪律**：11 类装饰全部升级既有行，**未新增任何组件 ID**；唯一新条目是装饰布局（真空缺）。

## 验收（实测）
- `check_asset_registry --ledger scenes --scope full`：**47 → 46**（`sha_mismatch` 24 → 23，恰为 R238；`invalid_status` 5 / `path_not_found` 18 不变，**无任何一类增加**、无新增 `duplicate_asset_id`）
- `--scope structure`：仍 5 条（既有 `invalid_status`）
- `verify_ledger_split`：**13 → 14**，唯一新增 `asset_not_in_baseline: ENV-ROOFTOP-DECOR-LAYOUT-100F`（有意新增，同批先例 `ENV-TOWER-DOOR-LEAF-5M`）；**历史行零丢失、零改写**（差集 GONE = ∅，`missing` 仍是既有两条 shelter）
- 前后对比手法：把 `.bak_rooftop_decor_ledger` 换回正式路径跑一次存 JSON → 立刻换回编辑版并断言 sha256 一致（实测 `MATCH=True`）→ 两份 JSON 做差集

## 证据
- 备份：`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx.bak_rooftop_decor_ledger`
- 日志：`_scratch/rooftop_v3/registry_scenes_{before,after,after2}.json`、`ledger_split_{before,after2}.json`
- 脚本：`_scratch/rooftop_v3/apply_rooftop_decor_ledger{,_stage2}.py`、`insert_changelog_2026_09_21.py`
- 文档：`docs/v0.1/development/CHANGELOG.md`（2026-09-21 条目）、`docs/v0.1/design/rooftop_component_library.md`（4 处口径同步：1.8m→0.80m 方案A、47 包、「未接入」→已接入、装饰层 visual_only）

## 遗留（未伪装修复）
- `verify_ledger_split` 的 2 条 `asset_lost`（`ENV-ROOFTOP-SHELTER-50M-3D` / `-90X80`）是分账前冻结基线与后来删除旧 Shelter 造成的**历史债**。
- 主表仍有 18 条 `path_not_found` + 5 条 `invalid_status`（既有基线）。
"""

INDEX = """# 2026-09-21 事务索引

> 约定见 [`../README.md`](../README.md)。

| 时间 | 事务 | 类型 | 结论一句话 |
|---|---|---|---|
| 07:26 | [100F 天台装饰接入 · 场景账本跟进](0726_rooftop_decor_ledger.md) | **实际改动** | 账本补登：库行 47 包/方案A、11 类装饰升「正式美术已接入」、新增装饰布局条目 + 域变更日志 v0.1.4；门禁 47→46、拆分红项 +1（唯一有意新增） |
"""

PLAYBOOK_EXTRA = [
    "  - ⚠️ **两个口径别混**（2026-09-21 实测）：官方脚本 `tools/asset_pipeline/verify_ledger_split.py` 的 `failure_count` 当时是 **14** = `row_content_mutated` 7 + `moved_sheet_mutated` 3 + `asset_lost` 2 + `asset_not_in_baseline` 2；上面那个 475 是 `_scratch/ledger_split_audit.py` 行级重放口径（含 470 条 R/S 派生列公式）。凡引用「红项数」必须写清是哪个脚本。",
    "  - ⚠️ **给《资产主表》加行 = 六处连带扩容**（2026-09-21 实测，漏一处就新增 `missing_dedupe`/`stale_overview_formula` 类红项）：① 全部既有行的 S 列查重公式 `$R$6:$R$239 → $R$6:$R$240`；② 三个 DV 的 `sqref`（C/K/L 列）；③ 两个 CF 的 `sqref`；④ `auto_filter.ref`；⑤ `总览` 10 格统计公式（A6/C6/E6/G6 + 分类行 B/C）——`总览` 公式写的是 `资产主表!$C$6:$C$239`，不带 `$R`；⑥ 新行自身的 R/S 用当前行号。",
    "  - ⚠️ **openpyxl 改 CF 范围别动 `_cf_rules` 的 dict key**：`for rng in ws.conditional_formatting` 拿到的 `ConditionalFormatting` 改 `sqref` **不会同步 dict key**；正确做法是 `ws.conditional_formatting.add(新范围, copy.copy(rule))`，再 `del ws.conditional_formatting[MultiCellRange(旧范围)]` 清掉旧条目（否则留下重复范围）。DV 的 `sqref` 存在 list 里，可直接赋值。",
    "  - ✅ **证明「账本改动零意外」的手法**：把 `.bak_*` 换回正式路径 → 跑一次门禁存 JSON → **立刻换回编辑版并断言 sha256 与编辑前一致** → 两份 JSON 按 `(kind, domain/sheet, asset_id)` 做 `Counter` 差集，要求 `NEW/GONE` 只出现本次有意项。（该门禁 JSON 只留 `failures[:40]`，所以差集要看 `failure_count` + kinds 计数，不能只看数组。）",
    "  - ⚠️ **`--scope full` 只校验《资产主表》里「已完成/原型已接入/正式美术已接入/已优化并正式接入/Blender源已完成/已导入；优化完成」这六种状态的行**（`ARTIFACT_STATUSES`）的 `O` 列路径存在性与 `T` 列 SHA；`待制作/程序占位/弃用` 不查。⇒ 新增主表行必须同时填对路径与 SHA，否则立刻新增 `path_not_found`/`sha_mismatch`；反之 `3D-*` 分页完全不参与该门禁。",
    "  - 登记层级口径（2026-09-21）：一个「参考组件库」在《资产主表》只占 **1 条库行**，库内各包登记在《3D-场景通用》分页（`ENV-ROOFTOP-REF-*` 家族 50 条）；但**独立交付物**（如布局 `ENV-ROOFTOP-DECOR-LAYOUT-100F`）要在主表与分页各登记 1 条，否则门禁看不见它。",
]


def write_lf(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="")
    raw = path.read_bytes()
    print("%s LF=%d CR=%d" % (path.name, raw.replace(b"\r\n", b"").count(b"\n"), raw.count(b"\r")))


def write_crlf(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = text.replace("\r\n", "\n").replace("\n", "\r\n")
    path.write_text(body, encoding="utf-8", newline="")
    raw = path.read_bytes()
    print("%s CRLF=%d bare_LF=%d" % (path.name, raw.count(b"\r\n"), raw.replace(b"\r\n", b"").count(b"\n")))


def main() -> int:
    write_lf(DAY / "0726_rooftop_decor_ledger.md", TRANSACTION)
    write_crlf(DAY / "_INDEX.md", INDEX)

    text = PLAYBOOKS.read_text(encoding="utf-8")
    anchor = "- 分账本 `verify_ledger_split`："
    lines = text.split("\n")
    hits = [i for i, line in enumerate(lines) if line.startswith(anchor)]
    assert len(hits) == 1, hits
    idx = hits[0]
    for extra in reversed(PLAYBOOK_EXTRA):
        if extra in text:
            print("SKIP already present: %s" % extra[:40])
            continue
        lines.insert(idx + 1, extra)
    body = "\n".join(lines).replace("\r\n", "\n").replace("\n", "\r\n")
    PLAYBOOKS.write_text(body, encoding="utf-8", newline="")
    raw = PLAYBOOKS.read_bytes()
    print("playbooks CRLF=%d bare_LF=%d bytes=%d" % (raw.count(b"\r\n"), raw.replace(b"\r\n", b"").count(b"\n"), len(raw)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
