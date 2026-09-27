"""远征房型组件「全量 UV 色盘提亮」—— 保色相提亮，只改 UV 指向的色盘格。

背景：房型源的建模脚本大量使用公共色盘的**深色格**（尤其中性灰阶栏第 10 列的行 0~3），
实测 239.8 万面里 64% 落在第 10 列、62% 明度低于 40%，整房发闷；
地板等大面还叠了高金属度材质。本脚本只处理**配色**（材质角色由
`normalize_expedition_room_type_material_roles.py` 负责）。

## 色盘结构（实测 10x10）
- 列 0→8：每条色相族的明度挡位（越右越浅），族内最亮只到列 8（V≈45%）。
- **第 10 列（u=9）：固定冷调灰阶栏**，图面行 0→9 由深到浅严格单调（V 20%→85%）。
- 图面行 0：饱和原色行；图面行 9：近黑阴影行 —— **这两行不是渐变，列位移无意义**。

## 映射规则（主人 2026-09-27 裁定）
1. u == 9（灰阶栏）：图面行 +3；行 7/8/9 已到浅端，**原样保留**。
2. 色相族（图面行 1~8，列 0~5）：**列 +3**（同色相提亮）；列 6/7/8 已在族内最亮，原样。
3. 图面行 0 / 行 9 的非灰阶格：原样不动 —— 含近黑 `(0,0)` `#05050c`，
   实测它是**斜角描边面**（法线 `(∓0.33,∓0.89,∓0.33)`，每件约占 5% 表面积）
   与 db「沿墙黄黑警示边带」的**黑条**，是刻意的深色语义，不是误用。

只平移 UV 岛，不动几何/顶点/材质槽/色盘 PNG。幂等：靠场景自定义属性打标，
重复执行不会二次位移（除非 `--force`）。

统计口径：母版 blend 已包含全部分包的网格，故 `per_library` 直方图**只按母版汇总**
（否则母版+分包会把同一网格算两遍）。分包 blend 的直方图在 `records` 里逐条保留。

Run with Blender 4.5+:
  blender --factory-startup --background --python <this> -- --project-root <root>
  # 只读复核（不改任何 blend，按磁盘重算并回写报告）：
  blender ... -- --project-root <root> --verify
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

import bpy

LIBRARIES = (
    ("office_room", "v009"),
    ("bridge_room", "v010"),
    ("boss_room", "v011"),
    ("l_corridor", "v002"),
    ("db_room", "v003"),
)
LIBRARY_ROOT = Path(
    "assets/art/environments/tower_zones/expedition/source/common_components"
)
REPORT_REL = Path(
    "assets/art/environments/tower_zones/expedition/runtime/room_type_components"
    "/palette_lighten_correction.json"
)

MARK_VERSION = "palette_lighten_v001"
MARK_KEY = "shellstorm2_palette_lighten"
UV_LAYER = "PaletteUV"
GRID = 10.0  # 10x10 色盘格
ROW_SHIFT = 3
COL_SHIFT = 3

## 实测色盘（图面行 0..9 × 列 0..9），仅用于报告标注，不参与运算。
PALETTE_HEX = [
    ["090813", "00574c", "311b73", "0f5f72", "733700", "731b33", "736005", "175f45", "1b3b6f", "1b2533"],
    ["29070e", "390d0d", "4b0c13", "5a0e1a", "650d20", "6e1c2a", "71333c", "724a4f", "725c5f", "263242"],
    ["291102", "381408", "451708", "571d05", "692805", "70340a", "71421b", "725434", "72614d", "324052"],
    ["211700", "331c08", "3c2306", "482c03", "5b3e02", "695104", "715c09", "726520", "726c3e", "3f4f62"],
    ["081b0e", "092514", "0a2d17", "093a1b", "0a4921", "0f592a", "21643a", "3c6c4d", "546f5e", "4d5e72"],
    ["041a1a", "03231b", "073532", "06433d", "09534b", "145f56", "0f5f6b", "2e6870", "4a6d71", "5d6e82"],
    ["051128", "0a1126", "0e1a3e", "0d2361", "112d6a", "1b3b6f", "2b4a71", "425972", "566372", "718195"],
    ["15072d", "1b032d", "220d43", "290f52", "311262", "381a6b", "3f296f", "4b3f71", "585172", "8998aa"],
    ["240310", "320c35", "3c0b40", "490d4f", "56115f", "631236", "6a2045", "6e3352", "704c5f", "a5b2c1"],
    ["05050c", "0e0c22", "16153a", "0a232d", "092321", "1c2c08", "381408", "3b0b1e", "716d63", "c5ced8"],
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--dry-run", action="store_true", help="只统计不落盘")
    parser.add_argument("--force", action="store_true", help="忽略幂等标记重新位移")
    parser.add_argument("--verify", action="store_true", help="只读复核：按磁盘重算并回写报告")
    parser.add_argument(
        "--backup-root",
        default="I:/workbuddy_tmp/palette_lighten_backup",
        help="提亮前的库备份根目录，--verify 用它算「提亮前直方图」",
    )
    parser.add_argument(
        "--libraries", default="", help="逗号分隔 room_slug，默认全部；用于分批复跑"
    )
    parser.add_argument(
        "--report", default="", help="报告输出路径（相对 project-root）"
    )
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def hex_of(cell: tuple[int, int]) -> str:
    return "#" + PALETTE_HEX[9 - cell[1]][cell[0]]


def cell_of(u: float, v: float) -> tuple[int, int]:
    """UV → (u格, v格自下而上)。图面行 = 9 - v格。"""
    return (min(9, max(0, int(u * GRID))), min(9, max(0, int(v * GRID))))


def target_cell(cell: tuple[int, int]) -> tuple[int, int]:
    """保色相提亮映射。返回与入参相同即表示本格不动。"""
    u, v = cell
    row = 9 - v
    if u == 9:
        # 中性灰阶栏：行 +3；行 7/8/9 已到浅端，原样保留。
        if row <= 9 - ROW_SHIFT:
            return (9, v - ROW_SHIFT)
        return cell
    if 1 <= row <= 8 and u <= 8 - COL_SHIFT:
        # 色相族：同色相列 +3；列 6/7/8 已在族内最亮，原样。
        return (u + COL_SHIFT, v)
    # 图面行 0（饱和原色行）/ 行 9（近黑阴影行，含 0_0 描边与警示黑）：非渐变，不动。
    return cell


def mesh_uv_layer(me: bpy.types.Mesh):
    layer = me.uv_layers.get(UV_LAYER)
    if layer is not None:
        return layer
    if me.uv_layers.active is not None:
        return me.uv_layers.active
    return me.uv_layers[0] if me.uv_layers else None


def scan_blend(blend_path: Path) -> dict:
    """只读：打开 blend，按 mesh 数据块去重统计色盘格直方图。"""
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    cells: collections.Counter = collections.Counter()
    layer_names: collections.Counter = collections.Counter()
    seen: set[int] = set()
    meshes = missing = polygons = spanning = 0
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        pointer = me.as_pointer()
        if pointer in seen:
            continue
        seen.add(pointer)
        layer = mesh_uv_layer(me)
        if layer is None:
            missing += 1
            continue
        meshes += 1
        layer_names[layer.name] += 1
        uvs = layer.data
        for poly in me.polygons:
            if poly.loop_total == 0:
                continue
            polygons += 1
            cu = cv = 0.0
            loop_cells = set()
            for li in poly.loop_indices:
                uv = uvs[li].uv
                cu += uv[0]
                cv += uv[1]
                loop_cells.add(cell_of(uv[0], uv[1]))
            cu /= poly.loop_total
            cv /= poly.loop_total
            if len(loop_cells) > 1:
                spanning += 1
            cells[cell_of(cu, cv)] += 1
    return {
        "cells": {f"{c}_{v}": n for (c, v), n in cells.most_common()},
        "meshes": meshes,
        "meshes_missing_uv": missing,
        "uv_layer_names": dict(layer_names),
        "polygons": polygons,
        "polygons_spanning_cells": spanning,
        "mark": str(bpy.context.scene.get(MARK_KEY, "")),
    }


def remap_blend(blend_path: Path, dry_run: bool, force: bool) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    scene = bpy.context.scene
    marked = str(scene.get(MARK_KEY, "")) if scene else ""
    record: dict = {
        "blend": blend_path.as_posix(),
        "applied": False,
        "meshes": 0,
        "meshes_missing_uv": 0,
        "uv_layer_names": {},
        "polygons": 0,
        "polygons_moved": 0,
        "loops_moved": 0,
        "polygons_spanning_cells": 0,
        "cells_before": {},
        "cells_after": {},
    }
    if marked == MARK_VERSION and not force:
        record["skip_reason"] = f"已打标 {marked}，幂等跳过"
        return record

    before: collections.Counter = collections.Counter()
    after: collections.Counter = collections.Counter()
    seen: set[int] = set()
    polygons = meshes = missing = spanning = 0
    polygons_moved = loops_moved = 0
    layer_names: collections.Counter = collections.Counter()

    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        me = obj.data
        pointer = me.as_pointer()
        if pointer in seen:
            continue
        seen.add(pointer)
        layer = mesh_uv_layer(me)
        if layer is None:
            missing += 1
            continue
        meshes += 1
        layer_names[layer.name] += 1
        uvs = layer.data
        for poly in me.polygons:
            if poly.loop_total == 0:
                continue
            polygons += 1
            cu = cv = 0.0
            loop_cells = set()
            for li in poly.loop_indices:
                uv = uvs[li].uv
                cu += uv[0]
                cv += uv[1]
                loop_cells.add(cell_of(uv[0], uv[1]))
            cu /= poly.loop_total
            cv /= poly.loop_total
            src = cell_of(cu, cv)
            before[src] += 1
            if len(loop_cells) > 1:
                spanning += 1
            dst = target_cell(src)
            after[dst] += 1
            if dst == src:
                continue
            du = (dst[0] - src[0]) / GRID
            dv = (dst[1] - src[1]) / GRID
            for li in poly.loop_indices:
                nu = uvs[li].uv[0] + du
                nv = uvs[li].uv[1] + dv
                if not (-1e-6 <= nu <= 1.0 + 1e-6 and -1e-6 <= nv <= 1.0 + 1e-6):
                    raise ValueError(
                        "UV 越界：%s face%d -> (%.6f, %.6f)" % (me.name, poly.index, nu, nv)
                    )
                uvs[li].uv = (nu, nv)
            polygons_moved += 1
            loops_moved += poly.loop_total

    record.update(
        {
            "meshes": meshes,
            "meshes_missing_uv": missing,
            "uv_layer_names": dict(layer_names),
            "polygons": polygons,
            "polygons_moved": polygons_moved,
            "loops_moved": loops_moved,
            "polygons_spanning_cells": spanning,
            "cells_before": {f"{c}_{v}": n for (c, v), n in before.most_common()},
            "cells_after": {f"{c}_{v}": n for (c, v), n in after.most_common()},
        }
    )

    if polygons_moved and not dry_run:
        scene[MARK_KEY] = MARK_VERSION
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
        record["applied"] = True
    elif polygons_moved and dry_run:
        record["skip_reason"] = "dry-run：未落盘"
    else:
        record["skip_reason"] = "无需位移（所有格已满足映射）"
    return record


def library_targets(root: Path, room_slug: str, version: str) -> tuple[Path, list[Path]]:
    library_root = root / LIBRARY_ROOT / version
    catalog = json.loads(
        (library_root / "component_catalog.json").read_text(encoding="utf-8")
    )
    master = library_root / f"expedition_{room_slug}_components_source_{version}.blend"
    packages: list[Path] = []
    for package in catalog["packages"]:
        slug = package["slug"]
        blend = library_root / "component_packages" / slug / f"{slug}.blend"
        if not blend.is_file():
            raise FileNotFoundError(blend)
        packages.append(blend)
    return master, packages


def cells_block(counter: collections.Counter) -> dict:
    return {
        f"{c}_{v}": {"faces": n, "hex": hex_of((c, v)), "row": 9 - v}
        for (c, v), n in counter.most_common()
    }


def counter_of(mapping: dict) -> collections.Counter:
    out: collections.Counter = collections.Counter()
    for key, value in mapping.items():
        u, v = (int(t) for t in key.split("_"))
        out[(u, v)] += value if isinstance(value, int) else value["faces"]
    return out


def run_verify(args: argparse.Namespace, root: Path, wanted: set[str]) -> None:
    """只读复核：拿**备份**的提亮前色盘格跑一遍映射，与磁盘现状逐格比对。

    判据不能是「现状每个格都是映射不动点」—— 映射是**位移**不是归一化，
    正确落点 r3/r4/r5/r6 本身还会被再移一次。真判据＝
    `map(备份直方图) == 现状直方图`，逐 blend（母版 + 每个分包）成立。
    """
    report_path = root / (args.report or REPORT_REL)
    report = json.loads(report_path.read_text(encoding="utf-8"))
    recorded = {r["blend"]: r for r in report["records"]}
    backup_root = Path(args.backup_root).resolve()
    per_library: dict[str, dict] = {}
    failures: list[str] = []
    for room_slug, version in LIBRARIES:
        if wanted and room_slug not in wanted:
            continue
        master, packages = library_targets(root, room_slug, version)
        targets = [master] + packages
        master_before: collections.Counter = collections.Counter()
        master_after: collections.Counter = collections.Counter()
        for blend in targets:
            rel = blend.relative_to(root / LIBRARY_ROOT / version)
            pristine = backup_root / version / rel
            if not pristine.is_file():
                failures.append(f"备份缺失：{pristine}")
                continue
            before = counter_of(scan_blend(pristine)["cells"])
            after = counter_of(scan_blend(blend)["cells"])
            expected: collections.Counter = collections.Counter()
            for (u, v), n in before.items():
                expected[target_cell((u, v))] += n
            if expected != after:
                diff = {
                    k: (expected.get(k, 0), after.get(k, 0))
                    for k in set(expected) | set(after)
                    if expected.get(k, 0) != after.get(k, 0)
                }
                failures.append(f"{blend.name} map(前)≠现状：{diff}")
            rec = recorded.get(blend.as_posix())
            if rec is None:
                failures.append(f"报告缺记录：{blend}")
            elif scan_blend(blend)["cells"] != rec["cells_after"]:
                failures.append(f"{blend.name} 现状直方图与报告 cells_after 不符")
            if blend == master:
                master_before += before
                master_after += after
        per_library[f"{room_slug}/{version}"] = {
            "blends": len(targets),
            "master_polygons": sum(master_before.values()),
            "master_polygons_moved": sum(
                n for (u, v), n in master_before.items() if target_cell((u, v)) != (u, v)
            ),
            "cells_before": cells_block(master_before),
            "cells_after": cells_block(master_after),
            "cells_after_expected": cells_block(
                sum(
                    (
                        collections.Counter({target_cell((u, v)): n})
                        for (u, v), n in master_before.items()
                    ),
                    collections.Counter(),
                )
            ),
        }
        print(
            "  %-22s blends=%-4d 母版面=%-7d 母版位移=%d"
            % (
                f"{room_slug}/{version}",
                len(targets),
                sum(master_before.values()),
                per_library[f"{room_slug}/{version}"]["master_polygons_moved"],
            )
        )
    report["per_library"] = per_library
    report["verified_from_disk"] = not failures
    report["verify_failures"] = failures
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if failures:
        for line in failures[:20]:
            print("  FAIL", line)
        print("ROOM_TYPE_PALETTE_VERIFY_FAIL:failures=%d" % len(failures))
        raise SystemExit(1)
    print("ROOM_TYPE_PALETTE_VERIFY_OK => %s" % report_path)


def cells_before_from_after(after: collections.Counter) -> dict:
    """反向映射（−3 行 / −3 列）重建提亮前直方图，用于报告留痕。"""
    inverse: collections.Counter = collections.Counter()
    for (u, v), n in after.items():
        row = 9 - v
        if u == 9:
            src = (9, v + ROW_SHIFT) if row >= 3 else (u, v)
        elif 1 <= row <= 8 and u >= COL_SHIFT:
            src = (u - COL_SHIFT, v)
        else:
            src = (u, v)
        inverse[src] += n
    return cells_block(inverse)


def main() -> None:
    args = parse_args()
    root = Path(args.project_root).resolve()
    wanted = {t for t in args.libraries.split(",") if t}

    if args.verify:
        run_verify(args, root, wanted)
        return

    records: list[dict] = []
    per_library: dict[str, dict] = {}

    for room_slug, version in LIBRARIES:
        if wanted and room_slug not in wanted:
            continue
        master, packages = library_targets(root, room_slug, version)
        targets = [master] + packages
        print("==== %s / %s  目标 blend %d 个" % (room_slug, version, len(targets)))
        master_record: dict | None = None
        for blend in targets:
            rec = remap_blend(blend, args.dry_run, args.force)
            rec.update({"room_type": room_slug, "version": version})
            records.append(rec)
            if blend == master:
                master_record = rec
            print(
                "  %-46s 面=%-7d 位移=%-7d 跨格=%d%s"
                % (
                    blend.name,
                    rec["polygons"],
                    rec["polygons_moved"],
                    rec["polygons_spanning_cells"],
                    "" if rec["applied"] else "（%s）" % rec.get("skip_reason", "-"),
                )
            )
        # 母版已含全部分包的网格 ⇒ per_library 只按母版汇总，避免重复计数。
        assert master_record is not None
        lib_cells = counter_of(master_record["cells_after"])
        per_library[f"{room_slug}/{version}"] = {
            "blends": len(targets),
            "master_polygons": master_record["polygons"],
            "master_polygons_moved": master_record["polygons_moved"],
            "master_uv_layer_names": master_record["uv_layer_names"],
            "package_polygons": sum(
                r["polygons"] for r in records if r["version"] == version and r is not master_record
            ),
            "cells_before": master_record["cells_before"],
            "cells_before_annotated": {
                k: {
                    "faces": n,
                    "hex": hex_of(tuple(int(t) for t in k.split("_"))),
                    "row": 9 - int(k.split("_")[1]),
                }
                for k, n in master_record["cells_before"].items()
            },
            "cells_after": cells_block(lib_cells),
        }
        print()

    if args.dry_run:
        print("DRY-RUN：未写任何 blend 文件")
    report_path = root / (args.report or REPORT_REL)
    if args.dry_run and not args.report:
        report_path = report_path.parent / (report_path.stem + ".dryrun.json")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        json.dumps(
            {
                "schema": "shellstorm2.expedition.room_type_palette_lighten.v001",
                "mark": MARK_VERSION,
                "scope": (
                    "只处理房型**组件库**（母版 + 每个独立组件包）；"
                    "房型概念源 blend 未动（美术参考 + 场景账本已登记 sha256）。"
                ),
                "rules": {
                    "neutral_column_u9": "图面行 +3；行 7/8/9 已到浅端，原样保留",
                    "hue_family_rows_1_8_col_0_5": "同色相列 +3；列 6/7/8 已在族内最亮，原样",
                    "rows_0_and_9_colored": "非渐变行（饱和原色行 / 近黑阴影行），原样不动",
                    "near_black_0_0": (
                        "原样保留：#05050c 实测是斜角描边面（法线 ∓0.33/∓0.89/∓0.33，"
                        "每件约 5% 表面积）与 db 沿墙黄黑警示边带的黑条"
                    ),
                },
                "row_shift": ROW_SHIFT,
                "col_shift": COL_SHIFT,
                "libraries": [f"{a}/{b}" for a, b in LIBRARIES],
                "per_library": per_library,
                "records": records,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    total_polys = sum(r["polygons"] for r in records)
    total_moved = sum(r["polygons_moved"] for r in records)
    print(
        "ROOM_TYPE_PALETTE_LIGHTENED:blends=%d polys=%d moved=%d => %s"
        % (len(records), total_polys, total_moved, report_path)
    )


if __name__ == "__main__":
    main()
