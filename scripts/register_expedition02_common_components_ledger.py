"""把远征关卡02 通用组件库 v015 的 5 件组件登记进场景分账本。

Run from any directory that is NOT the project root（项目根的 `inspect` 模块会遮蔽 stdlib）：

    python scripts/register_expedition02_common_components_ledger.py

写三处（全部逐格写值 + 按模板行复制样式，不重写既有单元格）：
  * 《资产主表》   — 5 行（每个组件一行），并重算全表 S 列查重公式的范围末尾
  * 《3D-场景通用》— 5 行 prefab 页，与既有场景组件同页对齐
  * 《总览》       — 把 资产主表 公式范围从 $872 扩到 $877
  * 《域变更日志》 — 1 条
"""

from __future__ import annotations

import copy
import json
from datetime import date
from pathlib import Path

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
VERSION = "v015"
LIBRARY_ID = "ENV-EXPEDITION-COMMON-COMPONENT-LIBRARY"
FIRST_DATA_ROW = 6
PACKAGE_DIR = ROOT / "art_source/environments/tower_zones/expedition/source/common_components" / VERSION / f"component_packages_{VERSION}"

# 每个组件在主表 / prefab 页各自的补充语义（其余字段从 manifest 推）
COMPONENT_EXTRA = {
    "wall_standard_5m_h3": {
        "usage": "远征关卡02 旅馆各层通用实墙；5m 槽位一件，可直接沿网格平铺",
        "tags": "远征关卡02;通用组件;实墙;3m;5m槽位;旅馆",
        "note": "低矮层（3m）实墙。与战局 ENV-BATTLE-COMMON-WALL-STANDARD-5M 同 5m 槽位、同 0.30 墙厚，只是墙高 3.00 而非 11.90。",
    },
    "wall_door_5m_h3": {
        "usage": "远征关卡02 旅馆各层通用门墙；5m 槽位一件，让出 2.2×2.5 门洞",
        "tags": "远征关卡02;通用组件;门墙;3m;门洞2.2x2.5;旅馆",
        "note": "3m 墙上楣底 2.80 ⇒ 门楣只有 0.20 高，由既有门契约决定，不是错值。",
    },
    "wall_collapse_5m_h12": {
        "usage": "远征关卡02 挑高前厅↔长廊的坍塌门洞；洞口占满一整格",
        "tags": "远征关卡02;通用组件;坍塌门洞;11.9m;5m整格;旅馆",
        "note": "洞口占满一整格、无门垛、高 2.5m（比标准门矮 0.5m）。占位 5.00×0.30×11.90，可视只有上方门楣 5.00×0.30×9.10。",
    },
    "ceiling_deck_5m": {
        "usage": "远征关卡02 旅馆封顶模块（阳台除外）；layer=1 碰撞挡住太阳射线",
        "tags": "远征关卡02;通用组件;封顶;天花板;遮光;layer1;旅馆",
        "note": "按 06 §7.3.1 封顶件硬契约：碰撞盒 layer=1，挡住朝太阳的采样射线。缺了它房间不受日照就是假的，且画面上看不出来。",
    },
    "floor_base_5m": {
        "usage": "远征关卡02 旅馆各层地板底层；顶面 0.26，地砖叠到走面 0.30",
        "tags": "远征关卡02;通用组件;地板底层;5m;旅馆",
        "note": "与地砖（4.94×4.94×0.04）配套，与封顶件同模数。",
    },
    "wall_standard_5m_h12": {
        "usage": "远征关卡02 挑高前厅通高层实墙（11.9m）；其余房间全走 3m 的 h3 版",
        "tags": "远征关卡02;通用组件;实墙;11.9m;挑高前厅;旅馆",
        "note": "通高层实墙，高度 = 项目基线 WALL_VISUAL_HEIGHT_M（11.90）。白盒里 16 面，全部属挑高前厅。",
    },
    "wall_door_5m_h12": {
        "usage": "远征关卡02 挑高前厅↔阳台安全屋的通高门墙（11.9m）",
        "tags": "远征关卡02;通用组件;门墙;11.9m;挑高前厅;旅馆",
        "note": "11.9m 墙上门墙：门垛与墙同高 11.90、门楣 9.10。白盒里只有 1 扇。",
    },
    "floor_tile_5m": {
        "usage": "远征关卡02 旅馆各层通用地砖（5m 格内可替换面砖）",
        "tags": "远征关卡02;通用组件;地砖;5m;旅馆",
        "note": "铺在 floor_base_5m 顶面（0.26）之上到走面 0.30，四面留 0.03 缝。独立成件是为了「破败旅馆」的做旧面砖要单独做，不复用办公/数据中心的干净面砖。",
    },
}


def copy_style(source_cell, target_cell) -> None:
    target_cell._style = copy.copy(source_cell._style)


def dedupe_key(row: int) -> str:
    return (
        f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})'
        f'&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'
    )


def dedupe_result(row: int, last_row: int) -> str:
    return f'=IF(COUNTIF($R${FIRST_DATA_ROW}:$R${last_row},R{row})>1,"重复","唯一")'


def load_components() -> list[dict]:
    out = []
    for slug in COMPONENT_EXTRA:
        path = PACKAGE_DIR / slug / "asset_manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        out.append({"manifest": manifest, "extra": COMPONENT_EXTRA[slug]})
    return out


def collision_policy_of(slug: str) -> str:
    """碰撞方式从**包装场景的 metadata** 读，不从 manifest 的描述字段猜。

    单一真源：prefab 的 `metadata/collision_policy` 是运行时真正生效的那个值；
    manifest 里的 `collision` 只是一句人读的描述（"owned by runtime prefab …"），
    把它填进账本的「碰撞方式」列等于把描述当策略 —— 第一版就是这么填错的。
    """
    tscn = (
        ROOT / "assets/art/environments/tower_zones/expedition/runtime/common_components"
        / slug / f"{slug}_root_top3d.tscn"
    )
    if not tscn.is_file():
        raise SystemExit("找不到包装场景，先跑 build_expedition_common_component_prefabs_v015.py：%s" % tscn)
    for line in tscn.read_text(encoding="utf-8").splitlines():
        if line.startswith("metadata/collision_policy ="):
            return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit("包装场景缺 metadata/collision_policy：%s" % tscn)


def main() -> None:
    components = load_components()
    wb = load_workbook(LEDGER)
    report: dict[str, object] = {}

    # ---------------- 1. 《资产主表》 ----------------
    main_sheet = wb["资产主表"]
    template_row = main_sheet.max_row
    first_new = template_row + 1
    main_rows = {}
    for offset, component in enumerate(components):
        manifest = component["manifest"]
        extra = component["extra"]
        slug = manifest["slug"]
        row = first_new + offset
        glb_rel = "assets/art/environments/tower_zones/expedition/components/common_components/%s/%s_visual_top3d.glb" % (slug, slug)
        values = {
            1: manifest["asset_id"],
            2: manifest["name_zh"],
            3: "场景",
            4: "common_component_3d",
            5: slug,
            6: "root_3d",
            7: None,
            8: "Top3D / local -Z 正面",
            9: "default / prefab",
            10: extra["usage"],
            11: "正式美术已接入",
            12: "P1",
            13: VERSION,
            14: "结构 %s m；占位 %s m" % (
                "×".join("%g" % v for v in manifest["visual_bounds_size_m"]),
                "×".join("%g" % v for v in manifest["slot_size_m"]),
            ),
            15: glb_rel,
            16: None,
            17: extra["tags"],
            20: manifest["export"]["glb_sha256"],
            21: "摩斯拉",
            22: date.today().isoformat(),
            23: "用户设计（按 5m 网格程序化建库；与战局通用墙同槽位口径，墙高 3m 为远征02 专用）",
            24: slug,
            25: "%s ｜ 库 %s ｜ 源 %s" % (extra["note"], LIBRARY_ID, manifest["optimized_blend"]),
        }
        for column, value in values.items():
            cell = main_sheet.cell(row=row, column=column)
            cell.value = value
            copy_style(main_sheet.cell(row=template_row, column=column), cell)
        main_sheet.cell(row=row, column=18).value = dedupe_key(row)
        main_sheet.cell(row=row, column=19).value = dedupe_result(row, first_new + len(components) - 1)
        copy_style(main_sheet.cell(row=template_row, column=18), main_sheet.cell(row=row, column=18))
        copy_style(main_sheet.cell(row=template_row, column=19), main_sheet.cell(row=row, column=19))
        if main_sheet.row_dimensions[template_row].height:
            main_sheet.row_dimensions[row].height = main_sheet.row_dimensions[template_row].height
        main_rows[slug] = row

    last_row = first_new + len(components) - 1
    rewritten = 0
    for row in range(FIRST_DATA_ROW, last_row + 1):
        expected = dedupe_result(row, last_row)
        cell = main_sheet.cell(row=row, column=19)
        if cell.value != expected:
            cell.value = expected
            rewritten += 1
    report["main_sheet"] = {"rows": main_rows, "dedupe_rows_rewritten": rewritten, "last_row": last_row}

    # ---------------- 2. 《总览》扩范围 ----------------
    overview = wb["总览"]
    extended: list[str] = []
    for row in overview.iter_rows():
        for cell in row:
            value = cell.value
            if isinstance(value, str) and "资产主表" in value and "$872" in value:
                cell.value = value.replace("$872", "$%d" % last_row)
                extended.append(cell.coordinate)
    report["overview_extended_cells"] = extended

    # ---------------- 3. 《3D-场景通用》 ----------------
    prefab_sheet = wb["3D-场景通用"]
    prefab_template = prefab_sheet.max_row
    prefab_rows = {}
    for offset, component in enumerate(components):
        manifest = component["manifest"]
        extra = component["extra"]
        slug = manifest["slug"]
        row = prefab_template + 1 + offset
        glb_rel = "assets/art/environments/tower_zones/expedition/components/common_components/%s/%s_visual_top3d.glb" % (slug, slug)
        tscn_rel = "assets/art/environments/tower_zones/expedition/runtime/common_components/%s/%s_root_top3d.tscn" % (slug, slug)
        values = {
            1: manifest["asset_id"],
            2: manifest["name_zh"],
            3: tscn_rel,
            4: glb_rel,
            5: manifest["source_blend"],
            6: extra["usage"],
            7: "",
            8: "有",
            9: "self",
            10: collision_policy_of(slug),
            11: "结构 %s m（占位 %s m）" % (
                "×".join("%g" % v for v in manifest["visual_bounds_size_m"]),
                "×".join("%g" % v for v in manifest["slot_size_m"]),
            ),
            12: "底面中心；Blender XY/Z → Godot XZ/Y",
            13: "远征关卡02 第1层（长廊 / 客房 / 横廊 / 支廊 / 封顶）",
            14: "正式美术已接入",
            15: VERSION,
            16: extra["note"],
        }
        for column, value in values.items():
            cell = prefab_sheet.cell(row=row, column=column)
            cell.value = value
            copy_style(prefab_sheet.cell(row=prefab_template, column=column), cell)
        if prefab_sheet.row_dimensions[prefab_template].height:
            prefab_sheet.row_dimensions[row].height = prefab_sheet.row_dimensions[prefab_template].height
        prefab_rows[slug] = row
    report["prefab_sheet"] = {"rows": prefab_rows}

    # ---------------- 4. 《域变更日志》 ----------------
    changelog = wb["域变更日志"]
    changelog_template = changelog.max_row
    changelog_row = changelog_template + 1
    previous_version = str(changelog.cell(row=changelog_template, column=1).value or "v0.1.0")
    try:
        bumped = "v0.1.%d" % (int(previous_version.rsplit(".", 1)[-1]) + 1)
    except ValueError:
        bumped = previous_version + "+1"
    changelog_values = {
        1: bumped,
        2: date.today().isoformat(),
        3: "新增条目",
        4: "关卡场景 / 远征关卡02",
        5: (
            "新增远征关卡02 通用组件库 v015 共 5 件（%s）：3m 实墙 / 3m 门墙 / 坍塌门洞 / "
            "封顶模块 / 地板底层模块。战局通用墙是 11.9m 高，与远征02 的 3m 净高对不上，故新开一版；"
            "封顶件按 06 §7.3.1 带 layer=1 碰撞。"
            % "、".join(COMPONENT_EXTRA.keys())
        ),
        6: (
            "同批登记《资产主表》第 %d-%d 行、《3D-场景通用》第 %d-%d 行。"
            "不改动既有 AssetID / 路径 / 哈希；未改任何既存组件，未新建房间，未改运行时。"
            % (
                first_new, last_row,
                prefab_template + 1, prefab_template + len(components),
            )
        ),
        7: "摩斯拉",
    }
    for column, value in changelog_values.items():
        cell = changelog.cell(row=changelog_row, column=column)
        cell.value = value
        copy_style(changelog.cell(row=changelog_template, column=column), cell)
    report["changelog"] = {"row": changelog_row, "version": bumped, "previous": previous_version}

    wb.save(LEDGER)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
