# -*- coding: utf-8 -*-
"""写入 B4 执行记录 + 落实 D3 决策（既有带版本名冻结）。

按前缀定位行，避免长字符串精确匹配的脆弱性；整体按 bytes 读写保 CRLF。
用法：python _scratch/b4_write_record.py
"""
from __future__ import annotations
from pathlib import Path

DOC = Path("docs/v0.1/development/2026-09-17_godot_asset_deversioning_plan.md")

STATUS = (
    "日期：2026-09-17；记录ID：待补；工程版本：0.1.0；状态：**P1 / P2 / P4 已完成；原子批 "
    "B1（`tower_zones/battle`）、B2（`dungeon_3d` + `tower_descent_3d` + `base_world_3d` 五根）、"
    "B3（`environments/base_facility_3d`，443 欠账 / 体量最大）、"
    "B4（`environments/rooftop_shelter_3d`，311 欠账 / 扁平 runtime 多代并存）、"
    "B6（`vfx/*` + `ui/*` + `environments/training_range_3d`，14 场景 / 纯改名批）均已完成（2026-09-17）；"
    "**按 D3 决策，B5 / B7 / B8 冻结（不再执行）**，B9 降级为可选清理**。"
)

ROW_B4 = (
    "| **B4** ✅ **已完成（2026-09-17）** | `environments/rooftop_shelter_3d` | "
    "311 → 改名 145 / 删除 158 / 改参照 3 文件·4 处（另套件内 69 处） | "
    "0（无 `.gd` 耦合） | **扁平 runtime + 多代并存批**：为工具新增 `obsolete_globs` 整代淘汰模式；"
    "`layout_v017/` → `layout/`；规范名归当前在用代 v021、旧代加 `_genNNN`；"
    "50m 代经台账核对后恢复 v011、只删 v003–v010；详见下「B4 执行记录」 |"
)

ROW_B5 = (
    "| **B5** ❄ **已冻结（2026-09-17，D3）** | `weapons/weapon_3d` + `weapons/melee_3d` | 130（保留） | "
    "14 | 原本耦合 `WeaponModel3D.gd`(10)、`Player3D.gd`(2)、`ItemModelFactory3D`、`TrainingRack3D`。"
    "按 D3 不再去版本化：`GUN_VISUAL_SCENES`/`MELEE_VISUAL_SCENES` 里的 `_v001`/`_v003` 视为正式命名 |"
)

ROW_B7 = (
    "| **B7** ❄ **已冻结（2026-09-17，D3）** | `enemies/enemy_3d` + `elite_3d` + `bosses_v01` + "
    "`environments/boss_arenas_v01` | 16（保留） | 9 | 原耦合 `BossContentCatalog.gd`(6)、"
    "`EliteContentCatalog`、`Player3DStateGallery`、`Dungeon3D`。按 D3 不再执行 |"
)

ROW_B8 = (
    "| **B8** ❄ **已冻结（2026-09-17，D3）** | `characters/player` | 144（保留） | 1 | "
    "含 13 个 `production/vNNN/` 目录；原本还绑「角色链版本契约」待决项。按 D3 不再执行 |"
)

ROW_B9 = (
    "| **B9** ⚪ **降级为可选清理（2026-09-17，D3）** | 纯清理：空版本目录 / 孤儿 GLB / `.bak_*` | "
    "22 目录 + 14 备份 | — | 与命名无关的部分（空目录、备份残留）仍可做，但非法务；"
    "**欠账快照清零已取消**（D3 后快照即「已接受的既有命名」） |"
)

D3 = (
    "| D3 | 存量带版本名是否必须清零 | **冻结（2026-09-17 用户指示）**：既有带版本号的文件名"
    "**视为正式命名**，不再追改；门禁只保证「**不新增**」—— 快照内的既有项不再当欠账追。"
    "已完成批次不回滚；未执行的 B5 / B7 / B8 取消，B9 与命名无关部分降级为可选 |"
)

B4_RECORD = """### B4 执行记录（2026-09-17，已完成）

**范围**：`assets/art/environments/rooftop_shelter_3d`（311 欠账 / 无 `.gd` 耦合 / 自带 `verify_rooftop_shelter_asset_contract`）。

**形状 —— 与 B1 / B2 / B3 / B6 都不同的「扁平 runtime + 多代并存」批**

- `runtime/` 是**扁平布局**（不是 `components/` + `runtime/` 三件套），且多代同名资产并存：
  `50m_game` v003–v011（6 代）、`90x80m_game` v012–v016（5 代）、`90x80m_root_top3d.tscn` v012–v016（5 代）、
  `facilities` v017/v019/v021（3 代）、`facilities_root_top3d.tscn` v017/v019（2 代），
  另有 **`layout_v016/` 与 `layout_v017/` 两套并行的 69 件组件目录**。
- 工具原有的 `collapse` / `keep_version` / `superseded` 三种模式**无法表达「整代退役、一份不留」**，
  故为 `deversion_batch.py` 新增第 4 种模式 **`obsolete_globs`（整代淘汰）**，并让 `--apply-renames`
  跳过未跟踪旁文件（否则会把构建产物误当改名源）。

**两处人工裁决（2026-09-17 拍板）**

1. **死岛随批删除**：`layout_v016/**`(138) + `90x80m_game` v012–v016(10) + `90x80m_root_top3d` v012–v016(5)
   —— 除彼此与 `reports/*.json` 历史记录外**零外部引用**；删除前用 `_scratch/b4_preflight.py` 做「真·悬空 = 0」预检。
2. **命名归属**：规范名归**当前在用代**，旧代加 `_genNNN` 后缀 —— `..._facilities.glb` ← **v021**
   （真运行时 `tower_zones/rooftop/runtime/zone_rooftop.tscn:3` 指向它）、`..._facilities_gen017.glb` ← v017、
   `..._facilities_gen019.glb` ← v019；场景侧 `..._facilities_root_top3d.tscn` ← v017（契约代，
   被 `verify_rooftop_shelter_asset_contract.gd` 与 repair 工具认）、`..._root_top3d_gen019.tscn` ← v019。
   `runtime/layout_v017/` 目录一并去版本为 `runtime/layout/`。

**⚠️ 一处口径自我纠正：50m 代不是死岛**

初判把 `50m_game` v003–v011 当作「被 90x80m 整体取代、无消费者的代」整代删。收尾核账时发现
**`资产主表!O300` 是 50m 场景在权威台账里的唯一运行文件登记（M300 = v011、K300 = 已完成、P1）** ——
即它是有登记的正式资产，只是当前无场景引用。按核心纪律「绝不静默破坏被引用资产」，
已从 HEAD **原样恢复 v011 并改名为稳定名** `env_rooftop_shelter_50m_game.glb`
（sha 与 HEAD 逐字节相同），只删 v003–v010。源 `.blend`（29 MB）与 `reports/asset_manifest_v011.json` 始终完整保留。

**执行数据**

| 项 | 数量 | 说明 |
|---|---|---|
| 改名 | **145** | 73 `.glb`（全部 R100 逐字节）+ 70 `.glb.import`（Godot 重生成）+ 2 `.tscn`（R091 / R099，含内部 `ext_resource` 改写） |
| 删除 | **158** | `layout_v016/**` 138 + `90x80m_game` v012–v016 10 + `90x80m_root_top3d` v012–v016 5 + `50m_game` v003–v010 5 |
| 外部引用改写 | **3 文件 / 4 处** | `zone_rooftop.tscn`(1，真运行时入口) + `verify_rooftop_shelter_asset_contract.gd`(2) + `export_godot_rooftop_reference.gd`(1) |
| 套件内引用改写 | 69 处 | v017 场景 68 条 `layout_v017/components/*_v017.glb` → `layout/components/*.glb`；v019 场景 1 条 |
| `.gitignore` | 9 行 → 3 行 | 删 6 条退役 `!…` 白名单；改 3 条路径（`facilities_v017`→`_gen017`、`facilities_v021`→稳定名、`layout_v017/**`→`layout/**`） |
| 台账 | **2 格** | 白名单化补丁（只改运行路径列）：`3D-场景通用!D61`、`资产主表!O300`；`E`(source) / `P`(关联清单) 记录列按契约保留 |
| 缩表 | **601 → 290** | −311（B4 欠账全部还清）；tscn 引用 236 → 93 |

**验收**：`aggregate core` → `count=68 / failed=6`（**与 B3 / B6 完全同一组红项，⊆ 基线**）；
加载失败类 `Cannot open file` / `Failed loading resource` / `No loader found` = **0**；
两个 rooftop 契约场景 `verify_rooftop_shelter_asset_contract` / `verify_rooftop_32x32_contract`
在**最终状态**（含 50m 恢复之后）单跑均 **PASS**；
`_scratch/b4_index_imports.py` 断言 B4 根 70 个暂存 `.import`「索引 == 工作树」且 `source_file=` 全部指向存在文件（防 B2 缺陷 1）；
`_scratch/index_refs_scan.py` → **BATCH_DANGLING = 0**；三道门禁全绿（命名 exit 0 / 台账 38 = 基线 / 文档 issues `[]`）。

**两次踩到并兜住的坑**

1. **调色板陷阱在 `--import` 时被触发**：编辑器把 `设施低亮多巴胺色盘_10x10_512.png.import` 的
   `detect_3d/compress_to` 由 **0 改成 1**（会让所有 GLB 取色失真）。已 `git checkout --` 还原，
   sha1 与基线 `23d13998baa8b73524790220f88eb21614be722f` 一致。**B4 有 `.glb`，本坑必查**；
   第二次 `--import` 未再触发。
2. **49 个文件「无记录消失」**：`--apply-renames` 与 `--apply-deletes` 之间，工作区丢了一批文件
   （22 个 `layout_v016` 组件 + 27 个死岛），随后 `stage_roots()` 的 `git add -A` 把「工作区缺失」
   顺带暂存成删除，导致删除日志只报 116（实际 158）。已用三视图（HEAD / 索引 / 磁盘）逐字节核对：
   **内容级无损** —— `layout/` 与 HEAD 的 `layout_v017` 136 个文件逐字节一致（缺失 0 / 多出 0 / 内容不符 0），
   且 `git diff --cached -M` 把 33 对内容相同组件的改名源归给字典序在前的 v016 **只是展示假象**
   （修改前的 `b4_plan.txt` 证明 `collect()` 取的源 100% 是 v017）。
   **教训：本仓并行会话会抖动工作区，跨步骤的执行器不能把「工作区缺失」等同于「本步骤删除」。**

**遗留（按约定保留，非遗漏）**：`tools/asset_pipeline/repair_rooftop_v017_coordinate_contract.py`
（→ 旧 `..._facilities_root_top3d_v017.tscn`）与 `build_rooftop_v021_wrapper.py`（→ 旧 `..._root_top3d_v019.tscn` + `..._facilities_v019.glb`）
属 `.py` 一次性构建 / 修复脚本，`fix_code_refs` 刻意排除 `.py` 与 `docs/`（同 B3 / B6 先例），
其路径属**历史记录**；若要重跑须先更新路径。

"""


def main() -> int:
    raw = DOC.read_bytes()
    print("before: bytes=%d CRLF=%d lone_LF=%d" % (
        len(raw), raw.count(b"\r\n"), raw.count(b"\n") - raw.count(b"\r\n")))
    text = raw.decode("utf-8")
    lines = text.split("\r\n")
    print("lines=%d" % len(lines))
    log = []

    def replace_prefix(prefix, new):
        hits = [i for i, ln in enumerate(lines) if ln.startswith(prefix)]
        assert len(hits) == 1, f"{prefix!r} 命中 {len(hits)} 行"
        lines[hits[0]] = new
        log.append(f"REPLACE L{hits[0]+1}: {prefix[:28]}...")

    def insert_before(prefix, block):
        # ⚠️ 多行 block 必须按行展开插入，否则内部 `\n` 会在 join 时留下 lone LF
        hits = [i for i, ln in enumerate(lines) if ln.startswith(prefix)]
        assert len(hits) == 1, f"{prefix!r} 命中 {len(hits)} 行"
        lines[hits[0]:hits[0]] = block.split("\n")
        log.append(f"INSERT  L{hits[0]+1}: {prefix[:28]}...")

    def insert_after(prefix, block):
        hits = [i for i, ln in enumerate(lines) if ln.startswith(prefix)]
        assert len(hits) == 1, f"{prefix!r} 命中 {len(hits)} 行"
        lines[hits[0] + 1:hits[0] + 1] = block.split("\n")
        log.append(f"INSERT  L{hits[0]+2}: after {prefix[:28]}...")

    replace_prefix("日期：2026-09-17；记录ID", STATUS)
    insert_after("| D2 |", D3)
    replace_prefix("| **B4** ", ROW_B4)
    replace_prefix("| **B5** ", ROW_B5)
    replace_prefix("| **B7** ", ROW_B7)
    replace_prefix("| **B8** ", ROW_B8)
    replace_prefix("| **B9** ", ROW_B9)
    insert_before("### P4 执行记录", B4_RECORD.rstrip("\n"))

    out = "\r\n".join(lines).encode("utf-8")
    DOC.write_bytes(out)
    for x in log:
        print("  " + x)
    print("after : bytes=%d CRLF=%d lone_LF=%d" % (
        len(out), out.count(b"\r\n"), out.count(b"\n") - out.count(b"\r\n")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
