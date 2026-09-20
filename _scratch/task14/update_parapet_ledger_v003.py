# -*- coding: utf-8 -*-
"""把天台女儿墙族 1.80m -> 0.80m（含压顶总高，方案A 平整墙板）落进场景账本。

只改《3D-场景通用》分页既有 5 行 + 追加 1 条域变更日志；不新增行、不改 AssetID。
台账真源 = assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx
"""
from __future__ import annotations

import shutil
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
LEDGER = ROOT / "assets" / "registry" / "ledgers" / "ShellStorm2_场景账本_v001.xlsx"
BACKUP = ROOT / "assets" / "registry" / "ledgers" / "ShellStorm2_场景账本_v001.xlsx.bak_rooftop_parapet_080m"

# 列号（1-based，与《3D-场景通用》表头一致）
C_SRC = 5      # Blender源文件
C_COLL = 10    # 碰撞方式
C_SIZE = 11    # 标准尺寸
C_ORIGIN = 12  # 原点与朝向
C_USE = 13     # 使用位置
C_VER = 15     # 版本
C_NOTE = 16    # 备注

PARAPET_SRC_APP = (
    "\n2026-09-20：改由 source/author_env_rooftop_parapet_v003.py 在 source/parapet_v003_work.blend 上"
    "重建 0.80m 方案A 平整墙板，再由 source/export_env_rooftop_parapet_v001.py 导出 GLB"
    "（source/reference_components/v002 保持只读，不改动）。"
)
DMG_SRC_APP = (
    "\n2026-09-20：派生口径升级，改由 source/author_env_rooftop_parapet_damage_v003.py 在 0.80m "
    "三块式 base（source/parapet_v003_work.blend）上重做破损；拼缝判据脚本 "
    "source/verify_env_rooftop_parapet_damage_bands.py 同步改为「去重位置集合 + Hausdorff」。"
)

PARAPET_NOTE_APP = (
    "\n2026-09-20：用户「改成 0.8 米的，变体也要一起改，然后中间的竖杠太密了 不好看，横杆在两边即可」。"
    "原 v002 配方是 22 块（基座 + 0.036m 分隔带 + 10 块墙身 + 10 块压顶），运行时表现为密集竖杠；"
    "本次重建为方案A 平整墙板，块数 22→3：基座带 5.0×0.50×0.10（z0..0.10）+ 墙板 5.0×0.43×0.64"
    "（z0.08..0.72）+ 压顶带 5.0×0.50×0.10（z0.70..0.80），合计**含压顶总高 0.80m**（用户选定口径）。"
    "厚度仍 0.50m ⇒ 边界内缩 _outer_wall_inset() 不变，四边/西侧碰撞位置与槽位相位不动。"
    "asset_version v002→v003；GLB 同路径覆盖重导（11,752 B）。"
    "TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT 1.80→0.80；_outer_wall_height()、"
    "OuterBoundaryCollision_* 高度、楼梯口矮墙缩放（ROOFTOP_PARAPET_HEIGHT / "
    "ROOFTOP_PARAPET_DOOR_BASE_HEIGHT = 0.80/1.50）自动跟随。"
    "⚠️ Player3D 无跳跃、无台阶攀爬，0.80m 与 1.80m 碰撞对玩法等价（都只是「走不出去」），"
    "差异仅在视觉高度、越过墙顶的相机视线与 0.80m 以上的弹道。"
    "实测 probe_rooftop_parapet_components：AABB=(5.0,0.80,0.50)、底面 Y=0、色盘已绑；"
    "门禁 ROOFTOP_WEST_EXPANSION_CONTRACT_PASS（外墙上限高度改断言为常量口径，不再硬编码 1.8）。"
)

OUTER_NOTE_APP = (
    "\n2026-09-20：随直段一起改为 0.80m（同一套三块式配方）。asset_version v002→v003；"
    "GLB 同路径覆盖重导（21,768 B），AABB=2.5×2.5×0.80、底面中心、两臂中心线 x=−1.0 / z=+1.0 "
    "与开口朝向均不变；四角落座位置（SW/SE/NE/NW）不动。"
    "实测 probe_rooftop_parapet_alignment：转角件 4 件 span 均 2.500×2.500，四条边 coverage=全长 / "
    "gap=0.000 / overlap=0.000。"
)

DMG_NOTES = {
    "A": (
        "\n2026-09-20：随直段降到 0.80m 并改 3 块式 base，破损配方同步重调"
        "（crown_spall 崩顶：压顶带被削 3 道豁口、中段崩落；下半身与两端头带完整）。"
        "asset_version v001→v002；GLB 同路径覆盖重导（38,784 B）。"
        "实测 probe_rooftop_parapet_damage_prefabs：包络 5.0×0.80×0.50、端头带去重位置 72（与 intact 同）、"
        "点云双向最近邻 5.22e-5 m ≪ 2e-4 阈值；"
        "source/verify_env_rooftop_parapet_damage_bands.py 输出 "
        "DMG_BANDS_OK variants=3 band_bit_identical=true envelope_identical=true height_m=0.80。"
    ),
    "B": (
        "\n2026-09-20：随直段降到 0.80m 并改 3 块式 base，破损配方同步重调"
        "（through_breach 贯穿：墙身中段打穿 2 个带放射裂纹的贯穿洞，可透视墙外；端头带完整）。"
        "asset_version v001→v002；GLB 同路径覆盖重导（37,084 B）。"
        "实测：包络 5.0×0.80×0.50、端头带原始顶点 292（去重后 72 —— 多出的 4 个是布尔切割改变了既有端头带"
        "顶点的 UV 参数化、glTF 按 (position,normal,uv) 拆点所致，几何未变，Hausdorff 5.22e-5 m）。"
        "⚠️ 探针判据已由「原始顶点数相等」改为「去重位置集合相等 + Hausdorff」——原始顶点数是导入管线的"
        "记账产物，不是几何；反向对照已做（把端头带起点从 2.05 放宽到 1.0 必变红），确认判据不空转。"
        "source/verify_env_rooftop_parapet_damage_bands.py 输出 DMG_BANDS_OK band_bit_identical=true height_m=0.80。"
    ),
    "C": (
        "\n2026-09-20：随直段降到 0.80m 并改 3 块式 base，破损配方同步重调"
        "（base_collapse 塌脚：墙身中段整体塌落成约 0.22m 残根、基座带被掏空，最重一档；端头带完整）。"
        "asset_version v001→v002；GLB 同路径覆盖重导（29,096 B）。"
        "实测：包络 5.0×0.80×0.50、端头带去重位置 72（与 intact 同）、点云双向最近邻 5.22e-5 m；"
        "source/verify_env_rooftop_parapet_damage_bands.py 输出 DMG_BANDS_OK band_id_identical=true height_m=0.80。"
    ),
}

# (row, kind)
TARGETS = [
    (102, "PARAPET"),
    (104, "OUTER"),
    (141, "DMG"),
    (142, "DMG"),
    (143, "DMG"),
]


def _append(cell_value, extra: str) -> str:
    base = "" if cell_value is None else str(cell_value)
    return base + extra


def main() -> int:
    if not LEDGER.is_file():
        raise SystemExit(f"账本不存在: {LEDGER}")
    shutil.copy2(LEDGER, BACKUP)
    print(f"backup -> {BACKUP.name}")

    wb = openpyxl.load_workbook(LEDGER)
    ws = wb["3D-场景通用"]

    for row, kind in TARGETS:
        asset_id = ws.cell(row=row, column=1).value
        before_ver = ws.cell(row=row, column=C_VER).value
        if kind == "PARAPET":
            ws.cell(row=row, column=C_SRC).value = _append(ws.cell(row=row, column=C_SRC).value, PARAPET_SRC_APP)
            ws.cell(row=row, column=C_COLL).value = "BoxShape3D 5×0.80×0.50，由 OuterBoundaryCollision 按槽位生成（Prefab 不再自带碰撞）"
            ws.cell(row=row, column=C_SIZE).value = "GLB / 5×0.50×0.80m / 共享Mesh"
            ws.cell(row=row, column=C_ORIGIN).value = "bottom_center（几何 Y=0..0.80）；朝 +Z"
            ws.cell(row=row, column=C_VER).value = "v003"
            ws.cell(row=row, column=C_NOTE).value = _append(ws.cell(row=row, column=C_NOTE).value, PARAPET_NOTE_APP)
        elif kind == "OUTER":
            ws.cell(row=row, column=C_SRC).value = _append(ws.cell(row=row, column=C_SRC).value, PARAPET_SRC_APP)
            ws.cell(row=row, column=C_SIZE).value = "GLB / 2.5×2.5×0.80m 包络（两臂中心线在局部 x=-1.0 与 z=+1.0，臂厚 0.50m）/ 共享Mesh"
            ws.cell(row=row, column=C_ORIGIN).value = "bottom_center（几何 Y=0..0.80）；朝 +Z；外角两臂在局部 −X 与 +Z"
            ws.cell(row=row, column=C_VER).value = "v003"
            ws.cell(row=row, column=C_NOTE).value = _append(ws.cell(row=row, column=C_NOTE).value, OUTER_NOTE_APP)
        else:  # DMG
            letter = str(asset_id).rsplit("-", 1)[-1]  # A / B / C
            ws.cell(row=row, column=C_SRC).value = _append(ws.cell(row=row, column=C_SRC).value, DMG_SRC_APP)
            ws.cell(row=row, column=C_COLL).value = (
                "BoxShape3D 5×0.80×0.50（与 intact 件同包络），由 OuterBoundaryCollision 按槽位生成"
                "（Prefab 不再自带碰撞）；破损只改外观，不改阻挡高度与缺口宽度"
            )
            ws.cell(row=row, column=C_SIZE).value = "GLB / 5×0.50×0.80m / 共享Mesh"
            ws.cell(row=row, column=C_ORIGIN).value = "bottom_center（几何 Y=0..0.80）；朝 +Z"
            ws.cell(row=row, column=C_USE).value = f"100F天台四周边界 / 随机破损档 {letter}（每段约 1/4 受损，A/B/C 三档均分）"
            ws.cell(row=row, column=C_VER).value = "v002"
            ws.cell(row=row, column=C_NOTE).value = _append(ws.cell(row=row, column=C_NOTE).value, DMG_NOTES[letter])
        after_ver = ws.cell(row=row, column=C_VER).value
        print(f"row {row} {asset_id}: ver {before_ver} -> {after_ver}")

    log = wb["域变更日志"]
    log_row = log.max_row + 1
    log.cell(row=log_row, column=1).value = "v0.1.3"
    log.cell(row=log_row, column=2).value = "2026-09-20"
    log.cell(row=log_row, column=3).value = "资产升版"
    log.cell(row=log_row, column=4).value = "关卡场景"
    log.cell(row=log_row, column=5).value = (
        "天台女儿墙族由 1.80m 改为 0.80m（含压顶总高），并把 v002 的 22 块「密集竖杠」配方重建为"
        "方案A 平整墙板（三块式：基座带 + 墙板 + 压顶带）。用户原话「改成0.8米的，变体也要一起改，"
        "然后中间的竖杠太密了 不好看，横杆在两边即可」。重导 5 件 GLB 同路径覆盖："
        "ENV-ROOFTOP-REF-PARAPET（v002→v003）、ENV-ROOFTOP-REF-PARAPET-OUTER（v002→v003）、"
        "ENV-ROOFTOP-REF-PARAPET-DMG-A/B/C（各 v001→v002）。"
        "TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT 1.80→0.80，碰撞高度与楼梯口矮墙缩放自动跟随；"
        "厚度 0.50m 不变，故四边/西侧碰撞位置与槽位相位不动。"
        "资产主表未增删行（本族只登记在《3D-场景通用》分页）；总览跨度不变。"
    )
    log.cell(row=log_row, column=6).value = (
        "AssetID 不变，只升版本；5 件 GLB 均为同路径覆盖重导，不新增文件；旧 v002 配方留档于 "
        "source/reference_components/v002（只读）。破损拼缝判据由「原始顶点数相等」改为「去重位置集合 + "
        "Hausdorff」，理由见 ENV-ROOFTOP-REF-PARAPET-DMG-B 行备注。"
    )
    log.cell(row=log_row, column=7).value = "摩斯拉"
    print(f"域变更日志 row {log_row} appended: {log.cell(row=log_row, column=1).value}")

    wb.save(LEDGER)
    print("saved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
