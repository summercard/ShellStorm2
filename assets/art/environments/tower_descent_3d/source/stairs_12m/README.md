# 12米楼梯间 Blender 源

- 几何基线源：`env_tower_stairs_12m_source_v001.blend`
- 几何基线清单：`asset_manifest_v001.json`
- 当前美术源：`stairwell_art_v021/env_tower_stairwell_dual_art_source_v021.blend`
- 当前美术源清单：`stairwell_art_v021/asset_manifest.json`
- 反推合同：`source/art/whitebox/tower_zones/v012/data/whitebox_stairs_v012.json`
- 生成脚本：`scripts/blender/build_formal_tower_stairs_from_godot_v001.py`

`env_tower_stairs_12m_source_v001.blend` 保留为历史几何反推基线。`stairwell_art_v021/` 是当前可维护美术源单元：完整保留 v020 的墙地与配件设计，建立 100→99 和 99→98 两个独立楼梯间装配体并按区块合同相反朝向摆放；两套已分别导出为 GLB v002、以 PackedScene v002 接入 Godot 并替换旧临时资产。v001 GLB与v020源保留回滚。
