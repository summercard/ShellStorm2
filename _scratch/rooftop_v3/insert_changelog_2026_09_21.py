#!/usr/bin/env python3
"""把 2026-09-21 的账本跟进条目插入 docs/v0.1/development/CHANGELOG.md（最新在上）。

CHANGELOG 是 CRLF 文件；read_text 会归一为 LF，写回时统一转 CRLF。
条目正文里不含字面 \\r\\n 串，故不会被二次折行。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "docs/v0.1/development/CHANGELOG.md"
MARKER = "## 2026-09-20｜100F 上层围护东西南三面与 24m 封顶换成天台参考组件库 v002"

ENTRY = """## 2026-09-21｜100F 天台按组件库完成装饰布局并接入 Godot，场景账本同步跟进

- 用户要求「用组件库里可装饰的组件装饰天台：墙上放空调、房子周围放花圃、加藤蔓、把水管接起来」。落地为**独立布局源 + 运行时重放**：Blender 侧新增 `source/layouts/100f_decorated_v001/rooftop_100f_decorated_layout_v001.{blend,json}`（469 个 Collection Instance，布局集合自身 0 Mesh、全部缩放 1）；Godot 侧由 `TowerFloorStage3D` 读清单重放 **113 个装饰实例**（房屋墙体 16 + 屋顶 16 + 空调与通风口 6 + 绿化 18 + 藤蔓 11 + 水管 38 + 立管支架 8，共 7 组）。
- 组件几何**不改**：11 类装饰（`ENV-ROOFTOP-REF-HVAC-SMALL/VENT`、`PIPE-STRAIGHT/ELBOW/TEE/RISER/BRACKET`、`IVY`、`FLOWERBOX`、`PLANT-LARGE/SMALL`）从 v002 主库逐件导出 GLB 到 `tower_zones/rooftop/components/`，并生成运行时 PackedScene `tower_zones/rooftop/runtime/<slug>.tscn`；11 件 `.import` 全部绑定 `tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`（否则白板且不触发任何 `*_OK` 门禁），并把天台组件目录加入 `.gitignore` 的 `.import` 白名单。
- 结构壳体不重复生成：234 块 5m 地砖、64 段女儿墙直段 + 4 个外角、楼梯与碰撞仍由 `TowerFloorStage3D` 负责；装饰件全部 `visual_only`，启用碰撞 0、非单位缩放 0。坐标转换固定 `Godot = (Blender X, Blender Z, -Blender Y)`。
- 账本（`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`）：《3D-场景通用》**11 行**由「Blender源已完成」→「正式美术已接入」，补 runtime PackedScene / GLB 路径、功能脚本 `src/world3d/TowerFloorStage3D.gd`、碰撞归零与实测记录；**专页与《资产主表》各新增 1 条** `ENV-ROOFTOP-DECOR-LAYOUT-100F`（100F 天台装饰布局，SHA 指向布局 Blend）；《资产主表》row 238 库行刷新为 **47 包** + 方案A 0.80m + SHA `ca091c6d… → d9e96fa1…` + 更新时间 2026-09-21；域变更日志追加 **v0.1.4**。遵守 README「AssetID 已存在 → 升级既有行」：11 类装饰**未新增任何组件 ID**。
- 扩容连带：新增主表行后，查重公式、数据校验、条件格式与筛选范围由 `$R$6:$R$239` 统一扩到 `$R$6:$R$240`，`总览` 10 格统计公式同步；旧范围 CF 条目已清理，不留重复范围。
- 门禁：`check_asset_registry --ledger scenes --scope full` **47 → 46**（`sha_mismatch` 24 → 23，恰为库行；`invalid_status` 5 / `path_not_found` 18 不变，**无任何一类增加**、无新增 `duplicate_asset_id`）；`verify_ledger_split` 13 → 14，**唯一新增**为 `asset_not_in_baseline: ENV-ROOFTOP-DECOR-LAYOUT-100F`（本次有意新增条目，与上一批 `ENV-TOWER-DOOR-LEAF-5M` 同类），历史行**零丢失、零改写**（GONE=∅，`missing` 仍是既有的两条 shelter）。
- 文档：`docs/v0.1/design/rooftop_component_library.md` 同步（女儿墙 1.8m → 0.80m 方案A、库内 47 包、「未接入」陈述改为「已按装饰布局接入」、接入边界改为装饰层 `visual_only`）。
- 旧账本留档：`ledgers/ShellStorm2_场景账本_v001.xlsx.bak_rooftop_decor_ledger`。

"""


def main() -> int:
    text = CHANGELOG.read_text(encoding="utf-8")
    assert MARKER in text, "找不到插入锚点"
    assert "2026-09-21｜100F 天台按组件库完成装饰布局" not in text, "条目已存在"
    new = text.replace(MARKER, ENTRY + MARKER, 1)
    new = new.replace("\r\n", "\n").replace("\n", "\r\n")
    CHANGELOG.write_text(new, encoding="utf-8", newline="")
    raw = CHANGELOG.read_bytes()
    print("CHANGELOG_ENTRY_INSERTED bytes=%d bare_LF=%d CR=%d" % (len(raw), raw.replace(b"\r\n", b"").count(b"\n"), raw.count(b"\r")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
