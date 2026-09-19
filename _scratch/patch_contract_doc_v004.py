# -*- coding: utf-8 -*-
"""CRLF 保持的文档补丁：把墙体 v004 实施记录写进契约对照文档。"""
from pathlib import Path

DOC = Path(r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\development\2026-09-19_关卡通用物体资产契约对照.md")

EDITS = [
    # 3.1 墙壁行：补可视包络
    (
        "| 墙壁 | `prp_tower_wall_solid_5m.tscn` | `ENV-TOWER-WALL-SOLID-5M` | 5.0 × 11.9 × 0.3（逻辑高 12.0，顶部留 0.1） | `bottom_center` | `+Z` |",
        "| 墙壁 | `prp_tower_wall_solid_5m.tscn` | `ENV-TOWER-WALL-SOLID-5M` | 结构 5.0 × 11.9 × 0.3；**可视 5.0 × 11.9 × 0.4675**（逻辑高 12.0，顶部留 0.1） | `bottom_center` | `+Z` |",
    ),
    # 实测 AABB
    (
        "- 实心墙首 mesh：`pos=(-2.5, 0.0, -0.15) size=(5.0, 11.9, 0.3) surfaces=1`",
        "- 实心墙（v004）可视包络：`pos=(-2.5, 0.0, -0.15) size=(5.0, 11.9, 0.4675) surfaces=3`；结构盒仍 `size=(5.0, 11.9, 0.3)`",
    ),
    # §10 债务 3：墙体已实际处理
    (
        "3. **基地 5 件的 `forward_axis` 是 `-Z`，塔楼是 `+Z`**，而两者用同一段 `match direction` 旋转逻辑摆放。对纯色墙无所谓，但对带装饰/带门洞的件，跨套替换会整体反 180°。未动美术，**仅记录**。",
        "3. **基地 5 件的 `forward_axis` 是 `-Z`，塔楼是 `+Z`**，而两者用同一段 `match direction` 旋转逻辑摆放。对纯色墙无所谓，但对带装饰/带门洞的件，跨套替换会整体反 180°。\n"
        "   → **墙体已按 8.4 落地「导出前烘焙 180°」的跨套迁移范式**（B 套装饰面 → A 套 `+Z`）；基地 5 件仍**仅记录**，未动美术。",
    ),
]

SECTION_84 = """### 8.4 墙体网格换为 v004（自 B 套 v007 通用实墙组件派生）

2026-09-19 追加：`ENV-TOWER-WALL-SOLID-5M` 的**可视网格**整体换成 v004 —— 源自 B 套
`source/art/whitebox/tower_zones/battle/components/common_components/v007`（包名 `wall_standard_5m_通用包`，
根件 `ROOT_wall_standard_5m_通用组件`）的派生物。**只换网格，不换玩法**：结构尺寸、原点契约、`forward_axis`、
碰撞责任、装配方式（`batched_multimesh`）全部不变；台账里 `bounds_size_m` 仍 5×11.9×0.30。

派生脚本：`assets/art/environments/tower_descent_3d/source/wall_height12/export_env_tower_wall_solid_5m_v004.py`
（`SS_WALL_PHASE=derive` 造源、`=export` 导出），产出
`env_tower_wall_solid_5m_source_v004.blend` + `env_tower_wall_solid_5m_v004_manifest.json`。

#### 跨套迁移的四个硬约束（这次都是实测踩出来的）

| # | 约束 | 为什么 | 落地做法 |
|---|---|---|---|
| 1 | **装饰面必须绕竖轴 180°** | Blender 侧厚度轴是 `+Y`，YUP 导出映射 `Blender +Y → Godot -Z`。B 套装饰面在 Blender `+Y` ⇒ Godot `-Z`；A 套四件套硬要求 `forward_axis="+Z"`（门禁第 5 项）。跨套直接用会整体反 180° | 在 Blender 内对根节点烘焙 `yaw=180°`（绕 Z）后 `transform_apply`，再导出。实测导出后装饰面落在 Godot `+Z`（GLB 顶点 `max.z = +0.3175`） |
| 2 | **根节点变换必须是单位矩阵** | 这个 GLB 除 prefab 外还被 `TowerDescent3D` **直接 preload 裸 GLB**（`_get_corridor_wall_module_mesh()` 取首网格、`_build_stair_approach_corridor()` 整树实例化挂 `StairApproachWall_*`）。GLB 根节点的 T/R/S 会**直接决定走廊墙位置** | 派生时把原根的世界平移（`[4, -58.344406, 0]`）先烘进网格再归零；导出后重新解析 GLB JSON 断言 `nodes=1` 且无 `translation/rotation/scale/matrix` |
| 3 | **先三角化，再删朝下面** | n-gon 用面平均法线判朝下会漏判：平均法线在阈值之上、但它的三角形在阈值之下。实测「先删后三角化」残留 11 个隐藏三角面 | 顺序固定为 `triangulate → remove_downward_faces(normal.z < -0.5)`；实测删面 1095，残留 0 |
| 4 | **批渲染只能吃单一 Mesh** | `batched_multimesh` 的 `MultiMesh.mesh` 是单资源槽，场景层合并（多 `MeshInstance3D`）不够 | 在 Blender 内 `join` 成单件；`mesh` 允许 3 个 primitive（材质 01/02/04），但必须落在**一个** mesh 资源里。导入后门禁第 8 项复查 |

#### 结构包络与可视包络在这件上正式分离

v003 是可视为对称的 0.30m；v004 的正面装甲只在一侧：

| | X | Y | Z |
|---|---|---|---|
| 结构/阻挡 `bounds_size_m` | 5.0 | 11.9 | **0.30** |
| 可视包络 `visual_bounds_size_m` | 5.0 | 11.9 | **0.4675** |

可视包络 `Z = [-0.15, +0.3175]`（背面 -0.15，正面装甲凸到 +0.3175），中心 `+0.08375`。
门禁判据仍是「结构盒 ⊂ 可视包络」而不是「可视底面 == 0」，所以装甲凸出**不触发** `bottom_center` 违规
（与门墙门框下探 0.14m 同一处理，见第 7 节第 4 项）。

#### 版本串**没有**单一真源 —— 换版必须同批改三处

| 落点 | 值 |
|---|---|
| `prp_tower_wall_solid_5m.tscn` 的 `metadata/asset_version` | `v004` |
| `TowerDescent3D.gd:2295` 的 `source_visual_version` | `v004` |
| `verify_tower_grid_component_alignment.gd:262` 的 `== "v004"` 断言与提示串 | `v004` |

漏改任一处不会当场报错，但会让「来源版本身份」和「对齐门禁的期望值」互相矛盾。

#### 实测与门禁

```text
可视包络 实测 = pos=(-2.5000, 0.0000, -0.1500) size=(5.0000, 11.9000, 0.4675)
可视包络 声明 = (5.0000, 11.9000, 0.4675)
origin_contract = bottom_center  结构盒=pos=(-2.5000, 0.0000, -0.1500) size=(5.0000, 11.9000, 0.3000)  包含=是
forward_axis = +Z   visual_only = true 内嵌碰撞=0   preserve_palette = true material_override=0
装配方式 = batched_multimesh
PREFAB_CONTRACT_OK: 四类通用物体统一契约全部成立
```

`TowerGeometry3D` 的解析入口、门禁八项、其余三件套均**未改**。

"""


def main() -> int:
    raw = DOC.read_bytes().decode("utf-8")
    assert "\r\n" in raw and raw.count("\n") == raw.count("\r\n"), "not pure CRLF"
    text = raw

    for old, new in EDITS:
        old_crlf = old.replace("\n", "\r\n")
        new_crlf = new.replace("\n", "\r\n")
        if old_crlf not in text:
            raise SystemExit("anchor not found:\n%s" % old_crlf[:120])
        text = text.replace(old_crlf, new_crlf, 1)

    anchor = "## 9. 统一契约字段表（就是「同一规格」的可执行定义）"
    if anchor not in text:
        raise SystemExit("section 9 anchor not found")
    text = text.replace(anchor, SECTION_84.replace("\n", "\r\n") + anchor, 1)

    DOC.write_bytes(text.encode("utf-8"))
    out = DOC.read_bytes()
    print("written bytes=%d CRLF=%d LF-only=%d" % (
        len(out), out.count(b"\r\n"), out.count(b"\n") - out.count(b"\r\n")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
