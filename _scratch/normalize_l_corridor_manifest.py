# -*- coding: utf-8 -*-
"""规范化 L 型走廊三个版本的 room_type_manifest.json。

* 补 v001 缺失的 version / source_blend（与 v002/v003 对齐）
* 修正 v003 陈旧的 layout_source（原写 10 m，实际 v003 已拓宽到 15 m）
* 收进 renders/ 后同步图片字段前缀
* 补 block_id_note / whitebox_note，记录业主裁决与「无白模」事实
写出时统一 CRLF，保持仓库行尾契约。
"""

import json
from collections import OrderedDict
from pathlib import Path

DST = Path(r"I:\工作项目\shellstrom2\ShellStorm2"
           r"\assets\art\environments\tower_zones\expedition\source\room_types\l_corridor")

BLEND = {
    "v001": "L型走廊种类_数据连廊_45x35m_v001.blend",
    "v002": "L型走廊种类_数据连廊_45x35m_v002.blend",
    "v003": "L型走廊种类_数据连廊_45x40m_v003.blend",
}

BLOCK_NOTE = (
    "业主 2026-09-24 裁决：L 型走廊归属远征关卡01。原 battle 区块的产出记录保留在 "
    "docs/v0.1/development/2026-09-23_battle_l_corridor_room_type_v001..v003.md；"
    "skill 01 的房间种类清单未包含 L_CORRIDOR，归属按源文件实际服务区块判定。"
)

WHITEBOX_NOTE = (
    "远征01 版图与白盒目录均无走廊白模；本房间种类源为参考图推定尺寸，"
    "门位与两臂长度见 door_centers_m / dimensions_m，接入前需远征白盒补走廊席位。"
)

for ver, blend in BLEND.items():
    path = DST / ver / "room_type_manifest.json"
    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)

    data["version"] = ver
    data["source_blend"] = blend
    data["block_id"] = "expedition"
    data["block_id_note"] = BLOCK_NOTE
    data["whitebox_source"] = None
    data["whitebox_note"] = WHITEBOX_NOTE
    data["asset_ledger"] = "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx::3D-场景通用"

    # 图片字段改为 renders/ 前缀（本次已把散放 png 收进 renders/）
    if "reference_image" in data and isinstance(data["reference_image"], str):
        data["reference_image"] = "renders/" + data["reference_image"].split("/")[-1]
    if "reference_crops" in data and isinstance(data["reference_crops"], list):
        data["reference_crops"] = ["renders/" + p.split("/")[-1] for p in data["reference_crops"]]

    # v003 陈旧描述修正
    if ver == "v003":
        data["layout_source"] = (
            "reference-derived dimensions; 15 m corridor width (three 5 m lanes) is user specified; "
            "no whitebox exists"
        )
    elif ver in ("v001", "v002"):
        data["layout_source"] = (
            "reference-derived dimensions; 10 m corridor width (two 5 m lanes) is user specified; "
            "no whitebox exists"
        )

    text = json.dumps(data, ensure_ascii=False, indent=2)
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))
    print("ok", ver, blend)

print("TOKEN_LCORRIDOR_MANIFEST_NORMALIZED")
