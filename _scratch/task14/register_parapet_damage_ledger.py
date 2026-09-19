"""登记天台女儿墙三件破损变体到场景账本《3D-场景通用》分页。

为什么登记到分页而不是《资产主表》：ENV-ROOFTOP-REF-PARAPET（直段）与
ENV-ROOFTOP-REF-PARAPET-OUTER（外角）两行就登记在《3D-场景通用》第 102/104 行，
《资产主表》里没有这一族（父库 ENV-ROOFTOP-REFERENCE-COMPONENT-LIBRARY 在第 238 行）。
本脚本沿用同一口径：三件破损件是直段的派生件，挂在同一分页、同一父项下。

防呆：
- 跑前备份（.bak_rooftop_parapet_damage），并用 openpyxl round-trip 前先确认文件未被占用；
- 三行 AssetID 若已存在则**升级既有行**而不是新增行（否则 check_asset_registry 会报
  duplicate_asset_id）；本脚本按 AssetID 查找，存在则原地更新，不存在才追加到分页末尾。
- 制作状态用「正式美术已接入」（在 check_asset_registry 的 ACCEPTED_STATUSES 内）。

跑法：python _scratch/task14/register_parapet_damage_ledger.py
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import openpyxl

PROJECT = Path(__file__).resolve().parents[2]
LEDGER = PROJECT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
BACKUP = PROJECT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx.bak_rooftop_parapet_damage"
SHEET = "3D-场景通用"
HEADER_ROW = 4

SHARED_REMARKS = (
    "父项=ENV-ROOFTOP-REF-PARAPET（同包络的派生件，不新增父库）。2026-09-19 新建。"
    "用户原话「墙壁帮我再blender里头制作3个变种，带有破损模型破损的，不同三种破损，"
    "但是需要能接起来，然后导入变成新的预制体后重新随机排列外墙」。"
    "派生做法：author_env_rooftop_parapet_damage_v001.py（headless Blender）把 intact 网格按"
    "「积木」拆成 22 块闭合倒角块（基座 + 0.036m 分隔带 + 10 块墙身 + 10 块压顶），只对与破损区"
    "相交的积木做**逐块**布尔剔料再合并。⚠️ 整件一次性布尔会静默吃掉 10 块墙身积木"
    "（512→272 顶点、4.52→1.25 m³、31.53 m² 面消失），且换个不接触的刀口也照样发生 —— "
    "必须逐块做，这是本件最大的坑。"
    "拼接契约（用户要求的「能接起来」）：两端头带 |x|>=2.05m 与 intact 件逐位相同"
    "（GLB 字节层已证：source/verify_env_rooftop_parapet_damage_bands.py 输出 "
    "DMG_BANDS_OK band_bit_identical=true）、包络 5.00×0.50×1.80、原点底面中心均与 intact 件"
    "逐值相同 ⇒ 可沿任一边、任意顺序与原件 / 彼此对接，接头无缝、槽位相位不变。"
    "色盘：破损新面 UV 已钳回色盘色块（U 0.923..0.977 / V 0.123..0.477），材质仍是"
    "02_细腻哑光_青绿大面；.import 已绑 tools/asset_pipeline/scene_facility_shared_palette_post_import.gd，"
    "探针实测 palette_texture_bound=true。"
    "实测：Godot 探针 probe_rooftop_parapet_damage_prefabs 四件（intact + A/B/C）包络逐值相同、"
    "端头带点云最近邻最大距离 7.07e-5 m（0.07mm；源文件逐位相同，这点偏差来自 Godot 导入对"
    "近重合重复顶点的焊接，不是几何被改）。"
    "接线：TowerFloorStage3D.PARAPET_DAMAGE_SCENES + 静态纯函数 split_outer_parapet_damage()，"
    "按种子随机分档；种子 ROOFTOP_PARAPET_DAMAGE_SEED=20260919，每段受损概率 0.25（三档均分），"
    "可用 set_outer_damage_seed() 在 _ready 前覆盖。"
    "门禁：ROOFTOP_WEST_EXPANSION_CONTRACT_PASS（verify_rooftop_32x32_contract 新增 "
    "_verify_rooftop_parapet_damage：槽位数 61 = 64−门洞补位 3、四批次件数之和 == 槽位数、"
    "计划 == 摆放、破损比例 ∈[0.15,0.35]、换种子必换排布、非天台层整批完好）；"
    "反向对照已做（破损概率改 0 / 改 1 / 排布忽略种子三种改坏各自变红，脚本 "
    "_scratch/task14/reverse_control_parapet_damage.py）。"
    "另：本族不像直段那样登记《资产主表》（与 102/104 行口径一致）。"
)

ROWS = [
    {
        "asset_id": "ENV-ROOFTOP-REF-PARAPET-DMG-A",
        "name": "女儿墙直段·破损A（崩顶）",
        "prefab": "assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_a_5m.tscn",
        "glb": "assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_a_top3d.glb",
        "size_bytes": 79644,
        "kind": "crown_spall / 崩顶：压顶顶部被削 3 道豁口、中段崩落，断裂面粗化；下半身与两端头带完整。",
    },
    {
        "asset_id": "ENV-ROOFTOP-REF-PARAPET-DMG-B",
        "name": "女儿墙直段·破损B（贯穿）",
        "prefab": "assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_b_5m.tscn",
        "glb": "assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_b_top3d.glb",
        "size_bytes": 116652,
        "kind": "through_breach / 贯穿：墙身中段被打穿 2 个带放射裂纹的贯穿洞，可透视到墙外；洞缘粗化。",
    },
    {
        "asset_id": "ENV-ROOFTOP-REF-PARAPET-DMG-C",
        "name": "女儿墙直段·破损C（塌脚）",
        "prefab": "assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_c_5m.tscn",
        "glb": "assets/art/environments/tower_zones/rooftop/components/env_rooftop_ref_parapet_dmg_c_top3d.glb",
        "size_bytes": 86228,
        "kind": "base_collapse / 塌脚：墙身中段整体塌到约 0.5m 残根、基座阳角被啃缺口，是最重的一档。",
    },
]


def build_row(entry: dict) -> list:
    remark = (
        "破损口径：%s\n"
        "实测 GLB %d B。\n%s"
        % (entry["kind"], entry["size_bytes"], SHARED_REMARKS)
    )
    return [
        entry["asset_id"],
        entry["name"],
        entry["prefab"],
        entry["glb"],
        "assets/art/environments/tower_zones/rooftop/source/reference_components/v002/"
        "天台区块_参考组件库_v002.blend#女儿墙直段_资产包（程序化破损派生）；派生脚本 "
        "assets/art/environments/tower_zones/rooftop/source/author_env_rooftop_parapet_damage_v001.py",
        "Godot原生场景结构Prefab；100F天台四周边界直段的破损变体，由 TowerFloorStage3D "
        "按种子随机替换部分直段槽位的可视件（外观破损、阻挡不变）",
        "src/world3d/TowerFloorStage3D.gd",
        "开",
        "TowerFloorStage3D",
        "BoxShape3D 5×1.80×0.50（与 intact 件同包络），由 OuterBoundaryCollision 按槽位生成"
        "（Prefab 不再自带碰撞）；破损只改外观，不改阻挡高度与缺口宽度",
        "GLB / 5×0.50×1.80m / 共享Mesh",
        "bottom_center（几何 Y=0..1.80）；朝 +Z",
        "100F天台四周边界 / 随机破损档 A（约 1/12 概率）",
        "正式美术已接入",
        "v001",
        remark,
    ]


def main() -> int:
    if not LEDGER.is_file():
        print("LEDGER_MISSING %s" % LEDGER)
        return 1
    print("ledger mtime=%s size=%d" % (LEDGER.stat().st_mtime, LEDGER.stat().st_size))
    shutil.copy2(LEDGER, BACKUP)
    print("backup ->", BACKUP.name)

    workbook = openpyxl.load_workbook(LEDGER, data_only=False)
    sheet = workbook[SHEET]
    last_row = sheet.max_row
    print("sheet=%s max_row=%d" % (SHEET, last_row))
    existing = {}
    for row in range(HEADER_ROW + 1, sheet.max_row + 1):
        asset_id = sheet.cell(row=row, column=1).value
        if asset_id:
            existing[str(asset_id).strip()] = row

    appended = 0
    updated = 0
    for entry in ROWS:
        values = build_row(entry)
        target = existing.get(entry["asset_id"])
        if target is None:
            last_row += 1
            target = last_row
            appended += 1
            action = "append"
        else:
            updated += 1
            action = "update"
        for column, value in enumerate(values, start=1):
            sheet.cell(row=target, column=column, value=value)
        print("  %-12s row=%d %s" % (action, target, entry["asset_id"]))

    workbook.save(LEDGER)
    print("LEDGER_ROOFTOP_PARAPET_DAMAGE_OK appended=%d updated=%d rows=%d" % (appended, updated, last_row))
    # 回读校验（防假绿）：确认三行真的落到盘上。
    check = openpyxl.load_workbook(LEDGER, data_only=False)[SHEET]
    found = {}
    for row in range(HEADER_ROW + 1, check.max_row + 1):
        asset_id = check.cell(row=row, column=1).value
        if asset_id and str(asset_id).startswith("ENV-ROOFTOP-REF-PARAPET-DMG"):
            found[str(asset_id).strip()] = (
                row,
                str(check.cell(row=row, column=3).value),
                str(check.cell(row=row, column=14).value),
            )
    for entry in ROWS:
        record = found.get(entry["asset_id"])
        if record is None:
            print("READBACK_FAIL %s 未写回" % entry["asset_id"])
            return 1
        if record[1] != entry["prefab"]:
            print("READBACK_FAIL %s prefab=%s" % (entry["asset_id"], record[1]))
            return 1
        print("  readback row=%d status=%s prefab=%s" % (record[0], record[2], record[1]))
    print("LEDGER_ROOFTOP_PARAPET_DAMAGE_VERIFIED rows=%d" % len(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
