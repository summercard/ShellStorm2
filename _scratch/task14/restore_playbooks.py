# -*- coding: utf-8 -*-
"""恢复被我一次 shell heredoc 追加写坏的 MEMORY-playbooks.md。

损坏情况（已确证）：
  原文件 22 个 `## ` 章节；被写坏后只剩 21 个 = 22 - 2（丢「环境与运维坑」+「资产路径命名契约」）+ 1（我的新章节）。
  即原文件前 51 行（标题 + 引言 + 前两节）被新章节顶掉。

恢复源：本会话的自动备份
  modify_backup/9.m.f10340d5.MEMORY-playbooks.md（93489 B, CRLF=450, 22 章节, 完整）
= 我做 slots 修正**之前**的完整版本。

恢复步骤：备份 + ①slots 修正（+238 B） + ②追加新章节。全程 bytes 级，保持 CRLF。
"""
import os
import sys

BACKUP = (
    r"C:\Users\zhuangmenghong\.workbuddy\workspace\sessions"
    r"\d253842a-e66a-47b4-8118-b736ed4da788\modify_backup"
    r"\9.m.f10340d5.MEMORY-playbooks.md"
)
TARGET = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY-playbooks.md"
OUT = r"I:\工作项目\shellstrom2\ShellStorm2\_scratch\task14\playbooks_restored.md"

OLD_SLOTS = (
    "- 实测 seed=20260919：`slots=61 intact=44 dmg_a=6 dmg_b=3 dmg_c=8 "
    "damaged=17 ratio=0.2787`，四边均有破损。"
)
NEW_SLOTS = (
    "- 实测 seed=20260919：`slots=64 intact=46 dmg_a=7 dmg_b=3 dmg_c=8 "
    "damaged=18 ratio=0.2813`，四边均有破损。"
    "（⚠️ 同一 seed 下**槽位一变分布整体重排**；封西侧围栏缺口前是 "
    "`slots=61 intact=44 damaged=17 ratio=0.2787`。**别把某一次实测数字写成断言**。）"
)

NEW_SECTION = """

## 天台地板换件 + 低一层外立面环 + 封闭西侧围栏缺口（2026-09-19/20 落地）

三件资产（**均为既有 AssetID 升行，不新增行**）：

| AssetID | prefab | GLB | 包络 / 原点 |
|---|---|---|---|
| `ENV-ROOFTOP-REF-FLOOR-FULL`（行97） | `prp_rooftop_floor_5m.tscn` | `env_rooftop_ref_floor_full_top3d.glb` | 5×0.3×5 / `bottom_center` |
| `ENV-ROOFTOP-REF-FACADE-SOLID`（行132） | `prp_rooftop_facade_solid_5m.tscn` | `env_rooftop_ref_facade_solid_top3d.glb` | 5×11.9×0.3 / `bottom_center` |
| `ENV-ROOFTOP-REF-FACADE-WINDOW`（行133） | `prp_rooftop_facade_window_5m.tscn` | `env_rooftop_ref_facade_window_top3d.glb` | 5×11.9×0.3 / `bottom_center` |

导出脚本 `tower_zones/rooftop/source/export_env_rooftop_ref_floor_facade_v001.py`。三件 `visual_only=true` / `collision_owner=TowerFloorStage3D` / `preserve_authored_palette=true`。

### 铁律① 换 prefab 前必须先量「新件原点契约」
新地板是 **`bottom_center`（几何 Y=0..0.30）**，旧 `POLISHED_FLOOR_SCENE` 是**几何中心**。
旧代码 `Vector3(x, -FLOOR_THICKNESS*0.5, z)` 对新件会**沉/浮半块**。
改法：`_floor_visual_origin_y(mesh) -> return -mesh.get_aabb().end.y`，用 AABB 把**顶面对齐 Y=0**。
⇒ 通用：**替换任何 prefab 前，先读新件 AABB 与 `origin_contract`，再决定摆放偏移**；不要假设沿用旧偏移。

### 铁律② 天台西侧楼梯洞是「内部洞」，不是「外墙门洞」
- 事实：楼梯洞 `Rect2(-45,0,15,30)` **整个在轮廓内部**，西墙（x=-50）到洞口还有 5m 通道。
- 旧代码误按「楼梯洞 = 外墙门洞」在西墙挖 3 段（z=10/15/20）塞系统占位矮墙 `ParapetDoorWall_West_*`（scale.y=1.2）→ 就是主人看到的「系统栏杆 + 缺口没连起来」。
- 改法：`_wall_side_has_door_gap(side) -> return side in stair_hole_sides and not _uses_rooftop_parapet_modules()`（对天台恒 false）；`_add_wall_collision` 也改用它 → 西墙碰撞由「断成两段」变**一条连续 Box**。
- 结果：直段 **61→64**、`ParapetDoorWall_*` **3→0**、`side=west segments=15 door_gap_indices=[]`、物理扫描 z∈[-30,40] 全部 x=-50.000 命中 `OuterBoundaryCollision_West`。
- ✅ 不挡下降：100F→99F 的下降沿在西侧，但用的是房间 `DungeonRoom3D` 的 `start` 房门，**不是 stage 外墙**。

### 铁律③ 外立面环（「99 层外墙」）= 天台同一圈、低一层 y=-12
- `_build_rooftop_facade_ring()`：同轮廓、`y=ROOFTOP_FACADE_BOTTOM_Y=-12.0`、内缩 `THICKNESS/2=0.15`（**外皮与女儿墙共面**）、节奏 **实 1 : 窗 2**（`index % 3 == 0` 为实墙）。
- 朝向约定（照抄 `reference_assembly.json`，与 prefab 声明的「装饰面朝外」自洽）：north(最小Z)=**PI**、south(最大Z)=**0**、west(最小X)=**-PI/2**、east(最大X)=**+PI/2**。
- 碰撞 `_install_rooftop_facade_collision()`：每边一个 `FacadeBoundaryCollision_{North/South/West/East}`，0.30m 厚 × 12m 高、中心 y=-6、内缩 0.15；四角互相咬合 0.3m 不留缝。
- 实测：`facade=68`（实 24 / 窗 44），四边 coverage 满、gap=0、overlap=0，`facade_bottom_y=-12.000`。
- 根因解释「看到底下是空的」：`Floor_99` 的 `_outer_world_rect` 是 **160×160（x -80..80）**，远在天台圈外 → 天台边缘（y=0）到 99F 楼面（y=-12）那条 12m 竖带**本来什么都没有**。

### 铁律④ 期望值必须由几何/常量推出，禁止硬编码
`probe_rooftop_parapet_damage_layout` 硬编码 `SLOT_COUNT_EXPECTED := 61`；封缺口后槽位 64 → **误红**（排布其实完全正常）。
正解：`_expected_straight_slot_count()` 由 `ROOFTOP_WORLD_RECT` + `ROOFTOP_CORNER_ARM_M` + 模块 5m 算出（`2×((90-5)/5) + 2×((80-5)/5) = 64`），再**与 stage 快照对账**（`outer_straight_slot_count`、`outer_doorway_wall_count`）。反向对照已做（`+1` → exit=1、两条断言同时红 → 还原）。

### 铁律⑤ 暗场景「这层渲染了没有」用**可见性 A/B 像素差**判
本场景雾重、立面与背景都是低对比灰 → 单看一张图**极易误判成「什么都没画」**。
做法（`probe_rooftop_facade_visual_ab`）：同机位拍两张（正常 / 把 `ImportedRooftopFacade{Solid,Window}Grid5M` 设 `visible=false`），`ImageChops.difference` 逐像素比。
- 实测 `changed=21730/921600 ratio=0.0236 max_delta=184` ⇒ `facade_rendered=true`。
- 判据用 `ratio >= 0.005`（立面占画面很大一块，真渲染必有显著差异）。
- ⚠️ 机位也要对：原 `02_edge_look_down` 相机 y=4，视线与 x=-49.75 相交处只有 ~2.85m（虽勉强越过 1.8m 女儿墙顶，但擦边）→ 改成 y=8 才稳妥。**「从天台边缘往下看」的机位必须让视线在与墙相交处明显高于女儿墙顶。**
- 截图类场景**不加 `--headless`**。

### 验证与台账
- 回归批跑 17 场景：绿 14；红 3 = **既有基线**（`verify_verification_runner_contract` 2 / `verify_base_world_flow` 4 / `verify_3d_performance_budget` 2），与上一轮 **marker 逐项相同** 且日志**零引用** `TowerFloorStage3D|rooftop_facade|prp_rooftop` ⇒ 与本次无关。**对基线要逐项比 marker 数 + grep 引用确认**，别只看「有没有红」。
- 契约门禁 `ROOFTOP_WEST_EXPANSION_CONTRACT_PASS`（`[外立面环] plan solid=24 window=44 total=68 | actual 24/44`）；构件验收 `ROOFTOP_FLOOR_FACADE_COMPONENTS_PASS: 3 件 / 5 个表面`。
- 台账：`3D-场景通用` 只升既有 3 行（97/132/133：补 prefab/GLB 路径、碰撞归属、制作状态→正式美术已接入、原点改 Godot 口径、备注追加实测）+ `域变更日志` 追加 **v0.1.2 / 2026-09-19 / 资产升版**。
- ⚠️ **改台账 xlsx 安全手法**：①先 `cp` 快照 → ②改到临时文件 → ③与快照**逐格比对**（本次 21 处 diff 全为预期列；原本为空的路径列不产生 diff，故 3行×7格）→ ④确认无图表/图片（`zipfile` 列条目，本次仅 sheet3 一张 table 且未触碰）才落盘。
- ⚠️ 跑 openpyxl 脚本必须 **`cd` 到仓库外**（仓库根 `inspect.py` 遮蔽 stdlib `inspect` → openpyxl 导入崩、假报 `ModuleNotFoundError: bpy`）。
- ⚠️ 批跑脚本要 **`export PATH=.../Git/usr/bin:$PATH` 先于** `bash script.sh`（脚本内部 export 在 bash 启动之后才生效；否则 `bash`/`tee` not found）。
- ⚠️ **本文件（以及其它记忆 .md）禁止用 shell heredoc 追加**：本轮 `cat >> file <<'EOF'` 把文件头 51 行顶掉、正文被截断，靠「本会话自动备份」才救回。**一律用 Write/Edit 工具，或 Python 读 bytes 后拼接写回**（同目录 `_scratch/final/append_playbook.py` 就是这个安全范式）。
"""


def main() -> int:
    with open(BACKUP, "rb") as handle:
        data = handle.read()
    print("backup bytes=%d" % len(data))

    # 完整性自检：恢复源必须含完整前言与 22 个章节
    assert data.count(b"\r\n") == 450, data.count(b"\r\n")
    assert data.count(b"\n") - data.count(b"\r\n") == 0, "backup has bare LF"
    headings = data.count(b"\r\n## ")
    assert headings == 22, headings
    for marker in (
        "详细操作手册".encode("utf-8"),
        "环境与运维坑".encode("utf-8"),
        "资产路径命名契约".encode("utf-8"),
        "角色 / 武器资产布局".encode("utf-8"),
    ):
        assert marker in data, marker
    print("backup integrity OK: headings=%d" % headings)

    # ① slots 修正
    old = OLD_SLOTS.replace("\n", "\r\n").encode("utf-8")
    new = NEW_SLOTS.replace("\n", "\r\n").encode("utf-8")
    assert data.count(old) == 1, data.count(old)
    data = data.replace(old, new)

    # ② 追加新章节（保持 CRLF）
    data = data + NEW_SECTION.replace("\n", "\r\n").encode("utf-8")

    assert data.count(b"\n") - data.count(b"\r\n") == 0, "result has bare LF"

    with open(OUT, "wb") as handle:
        handle.write(data)
    print("wrote %s bytes=%d headings=%d" % (OUT, len(data), data.count(b"\r\n## ")))

    # 只读校验
    text_lines = data.decode("utf-8").split("\r\n")
    print("lines=%d" % len(text_lines))
    print("first line: %s" % text_lines[0])
    # 关键锚点必须在
    for anchor in (
        "# ShellStorm2 详细操作手册",
        "## 环境与运维坑",
        "## 资产路径命名契约",
        "## 角色 / 武器资产布局",
        "## 天台地板换件 + 低一层外立面环",
        "## 天台女儿墙 = 参考组件库 v002 的两件",
    ):
        assert anchor in data.decode("utf-8"), anchor
    print("anchors OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
