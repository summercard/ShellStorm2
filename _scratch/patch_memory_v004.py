# -*- coding: utf-8 -*-
"""CRLF 保持：把 v004 墙体接入这一轮写进工作区记忆。"""
from pathlib import Path

MEM = Path(r"I:\工作项目\shellstrom2\.workbuddy\memory")
DAILY = MEM / "2026-09-19.md"
INDEX = MEM / "MEMORY.md"

DAILY_SECTION = """
---

## 墙体 v004 接入（ENV-TOWER-WALL-SOLID-5M：v007 通用实墙组件 → 塔楼 A 套）

### 任务
把 B 套 `battle/components/common_components/v007`「wall_standard_5m_通用包」派生为 A 套墙体网格 v004，
**原地覆盖**稳定路径 GLB `assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d.glb`。
主人四条裁决：①**不动阻挡**（`bounds_size_m` 保持 0.30m）②③ Blender 源按版本号迭代、Godot 侧文件名统一并直接覆盖
④ 0 面的 `03_清漆反光_紫粉点缀` 槽先用其他替代（实际该槽无几何，直接丢弃）。

### 派生实现
- 脚本 `.../tower_descent_3d/source/wall_height12/export_env_tower_wall_solid_5m_v004.py`（`SS_WALL_PHASE=derive|export`）。
- 只读打开 v007 源，复制 `wall_standard_5m_主体_输出` + `..._UI灯光_柔和自发光`，烘焙 `yaw=180°绕Z` @ 归零根平移，
  `transform_apply` 后**先三角化、再删朝下面**（`normal.z < -0.5`），`join` 成单件 `ENV_TOWER_WALL_SOLID_5M`。
- **三处实测坑**：① `--factory-startup` 不会打开文件（要用 `bpy.ops.wm.open_mainfile`）；
  ② v007 源里带 **11 个 Scene datablock**（10 个空审阅场景 + 生产场景），Blender 默认导出**全部**场景
  → Godot 取 index 0 = 空的 → 必须删到只剩 1 个 + 导出时 `use_active_scene=True`；
  ③ 「先删朝下面再三角化」会残留 11 个隐藏三角面（n-gon 平均法线在阈值上、其三角形在阈值下），
  正确顺序 = **先三角化再删**，实测删面 613 → 1095、残留 0。
- 产物：`env_tower_wall_solid_5m_source_v004.blend` + `_v004_manifest.json`（faces 3615→5319、材质角色 01/02/04、scenes_removed=11）。
- GLB 契约（重新解析 JSON 断言）：`scenes=1 nodes=1 mesh=1 prims=3`、节点 TRS 恒等、Godot 包络
  `min[-2.5,0,-0.15] max[2.5,11.9,0.3175]`（装饰面在 **+Z** ⇒ 180° 翻转生效）、无内嵌贴图。

### 三处同批改动
| 落点 | 改动 |
|---|---|
| GLB（稳定路径） | 原地覆盖，新 sha256 `0bca134e…49fb9`，378408 B |
| `.glb.import` | `import_script/path` 空 → `scene_facility_shared_palette_post_import.gd`；`embedded_image_handling` 1→0 |
| `prp_tower_wall_solid_5m.tscn` | `asset_version`→v004；`visual_node_name`→`ENV_TOWER_WALL_SOLID_5M`；`visual_bounds_size_m`→`(5,11.9,0.4675)` + 新增 `visual_bounds_policy`；注释重写；`bounds_size_m` **保持 0.30** |
| `TowerDescent3D.gd:2295` | `source_visual_version`→v004 |
| `verify_tower_grid_component_alignment.gd:262` | 断言 `== "v003"` → `"v004"` + 提示串 |

### 台账同步（场景分账本两行）
- `资产主表` R55：M→v004、N→可视包络口径、O 改去版本号稳定路径、P 改派生源链路、T→新哈希、
  V→46284、W「程序生成 Blender 源集合」→「Blender 派生（自 v007 通用实墙组件）」、Y 追加 2026-09-19 段。
- `3D-场景通用` R48：E 改派生源、K 加可视包络、O→v004、P 改写（补 `visual_bounds_size_m` 分离、
  跨套 +180°、根变换单位矩阵三条）。旧的「保留美术自带 PaletteUV（MAT_Structure_DarkSteel）」已过期（实际走共享色盘 01/02/04），一并更正。
- 做法：**外科式 XML 补丁** `_scratch/patch_ledger_wall_v004.py`（`t="inlineStr"` + 保留 `s=`，其余 26 个 zip 条目按原
  `date_time/compress_type/external_attr` 字节复制）。验证：改动条目**恰好** `sheet3.xml`+`sheet4.xml`，`testzip()=None`。
- 门禁口径：`check_asset_registry --scope structure` 改前/改后**逐项一致**（`{dedupe_key_formula_wrong:235, dedupe_result_formula_wrong:235, invalid_status:6}`，424 资产、各账本行数不变）；
  `verify_ledger_split` `missing=0 extra=0`，`column_digest_drift` **仅** M,N,O,P,T,V,W,Y（= 精确被改的列）。
  结论：这两项红色都是**既有/环境性**的（openpyxl 把数组公式读成 `ArrayFormula`），本次未新增。
- 未写总目录《版本记录》：该表是**全局**变更日志，历史同类组件登记（塔楼模块/安全房）也没登记，粒度不符。

### 验收（全绿）
`PREFAB_CONTRACT_OK`（实测包络 `(5,11.9,0.4675)` == 声明、结构盒被包含、`forward_axis=+Z`、`visual_only` 无内嵌碰撞、
`preserve_authored_palette` 无 material_override、`batched_multimesh`）；
`TOWER_GRID_COMPONENT_ALIGNMENT_OK` / `TOWER_LEVEL_BLOCKS_OK` / `EXPEDITION_LEVEL01_FLOW_OK` /
`ARRIVAL_GATE_FLOOR_BUNDLE_OK initial_rooms=3 generated_rooms=69` / `TOWER_FLOOR_ROOM_AUTHORITY_OK` /
`ROOFTOP_WEST_EXPANSION_CONTRACT_PASS` / `TOWER_JOURNEY_POLISH_OK` / `TOWER_EXTRACTION_RETURN_OK` /
`COMMON_WALL_DOOR_COMPONENTS_V004_OK` / `verify_door_passability` 15/15；
视觉验收**不带 headless** 直跑 `verify_tower_descent_visual.tscn` → `TOWER_DESCENT_VISUAL_OK` + 13 张新 PNG，
肉眼复核 98F 亮灯房墙、95F Boss 房墙、99F 走廊、楼梯口均正常（面板/装甲网格对齐、无缺面、无错位）。
- 注意：`verify_tower_descent_flow` 现在是**迁移占位**，只打印 `TOWER_DESCENT_FLOW_MIGRATED`（动态到店门流已由
  `verify_arrival_gate_floor_bundle_flow` 覆盖），跑它「无 `_OK`」是正常的。
- 补充：改前 `check_asset_registry`/`verify_ledger_split` **本来就是红的**（非本轮引入），别误判为回归。

### 文档
`docs/v0.1/development/2026-09-19_关卡通用物体资产契约对照.md`：§3.1 墙壁行补可视包络、实测 AABB 行改 v004、
新增 **§8.4 墙体网格换为 v004**（跨套迁移四条硬约束表 + 结构/可视包络分离表 + 版本串三处表 + 实测与门禁）、
§10 债务 3 标注「墙体已落地 180° 范式、基地 5 件仍仅记录」。CRLF 保持（280/0）。
"""

INDEX_EDITS = [
    (
        "- 逐场景 `--headless --path . res://tests/verification/<场景>.tscn` 再 grep `*_OK`；`visual/renderer` 场景**不能 headless 直跑**（走 `run_verification_suite.sh`）。以 `*_OK`/`VERIFICATION_SUITE_OK`/`FAILED_SCENE` 为准，**不看裸退出码**。日志放 `_scratch/`。",
        "- 逐场景 `--headless --path . res://tests/verification/<场景>.tscn` 再 grep `*_OK`；`visual` 场景**不带 `--headless` 直跑**即可（实测 `TOWER_DESCENT_VISUAL_OK`，截图落 `outputs/verification/`）。以 `*_OK`/`VERIFICATION_SUITE_OK`/`FAILED_SCENE` 为准，**不看裸退出码**。日志放 `_scratch/`。\n"
        "- 跑场景前先 `--headless --path . --import` 重导入。**部分「红项」是本机环境性的**（`verify_ledger_split` / `check_asset_registry` 现在就是红的：判据 = 「红项 ⊆ 基线」，别当回归）。`verify_tower_descent_flow` 已迁移为占位，只打印 `TOWER_DESCENT_FLOW_MIGRATED`，无 `_OK` 属正常。",
    ),
    (
        "- `bounds_size_m`（玩法阻挡，塔楼墙恒 0.30m）与 `visual_bounds_size_m`（实测可视包络，可更大且不对称）**刻意分离**。",
        "- `bounds_size_m`（玩法阻挡，塔楼墙恒 0.30m）与 `visual_bounds_size_m`（实测可视包络，可更大且不对称）**刻意分离**。墙体 v004 实测可视 `5×11.9×0.4675`（装甲凸到 +Z 0.3175、背面 -0.15），门禁判「结构盒 ⊂ 可视包络」而非「可视底面==0」。\n"
        "- **删朝下面要「先三角化、再删」**：n-gon 面平均法线在阈值上而它的三角形在阈值下，「先删后三角化」会残留隐藏三角面（实测 11）。\n"
        "- **Blender 导出 glTF 默认写全部 Scene**（`use_active_scene` 默认 False）——源里有多个审阅场景时 Godot 会取到空场景；导出前收敛到 1 个 Scene。\n"
        "- **台账写入**：分账本带表对象/数据校验/派生列数组公式，**改行走外科式 XML 补丁**（`t=\"inlineStr\"` + 保留 `s=`，其余条目按原 `date_time/compress_type` 字节复制），别用 openpyxl/Office 整本往返。内容编辑**必然**触发 `verify_ledger_split` 的 `row_content_mutated`（基线锚在拆分前单体账本）→ 口径 = `missing=0 extra=0` 且 `column_digest_drift` 仅命中被改列。**资产级改动的日志写在《资产主表》备注列，总目录《版本记录》是全局粒度、不登记单件**。",
    ),
]


def main() -> int:
    daily = DAILY.read_bytes().decode("utf-8")
    idx = INDEX.read_bytes().decode("utf-8")
    for name, text in (("daily", daily), ("index", idx)):
        assert text.count("\n") == text.count("\r\n"), "%s not pure CRLF" % name

    if "墙体 v004 接入" not in daily:
        daily = daily.rstrip("\r\n") + "\r\n" + DAILY_SECTION.replace("\n", "\r\n")
    for old, new in INDEX_EDITS:
        o, n = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
        if o not in idx:
            raise SystemExit("index anchor not found:\n%s" % o[:100])
        idx = idx.replace(o, n, 1)

    DAILY.write_bytes(daily.encode("utf-8"))
    INDEX.write_bytes(idx.encode("utf-8"))
    for p in (DAILY, INDEX):
        d = p.read_bytes()
        print("%s bytes=%d CRLF=%d LF-only=%d" % (p.name, len(d), d.count(b"\r\n"), d.count(b"\n") - d.count(b"\r\n")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
