# -*- coding: utf-8 -*-
"""把 MEMORY.md 重写为更紧凑的索引（CRLF 保持，事实不丢，只做合并去冗）。"""
from pathlib import Path

INDEX = Path(r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY.md")

CONTENT = r"""# ShellStorm2 项目长期约定

> 索引。详细手册见 `MEMORY-playbooks.md`，逐日记录见 `YYYY-MM-DD.md`。

## 环境
- 项目根 `I:\工作项目\shellstrom2\ShellStorm2\`；Godot 控制台 `I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe`。
- Bash 缺工具（`tail`/`grep`/`dirname`…）时前置 `export PATH="/c/Users/zhuangmenghong/.workbuddy/binaries/PortableGit/versions/1.2.0/bin:/usr/bin:/bin:$PATH"`。
- Python venv `~/.workbuddy/binaries/python/envs/default/Scripts/python.exe`；跑脚本先 `cd /tmp`（父目录 `inspect.py` 遮蔽标准库）。
- `.gd/.tscn/.md` 保持 CRLF；`preload` 是编译期解析，改名与改引用必须同批。**不要删除 `.workbuddy`**。

## 关卡生成 `src/map/FloorPlanGenerator.gd`（纯数据）
- **两套房表并存勿合并**：塔楼 `generate()/validate()`（硬拒内容房 `maxf<30||minf<25`）；远征 `generate_expedition()/validate_expedition()`（25×25，过不了塔楼校验）。
- 塔楼模板房几何只有 4 种可达（死分支 `rotation_steps%2==1`），真正在变的是内容类型；要形状真不同须改 `_normal_rooms()` 模板。
- 第三入口 `generate_from_level_plan()`（05.2 三层设计源）默认 **关**；**D4 存档兼容未裁决前不得开**。内容类型走 `_assign_content_types_data_driven`（钉死 `type` 优先；`FUNCTIONAL_ROLES` 跳过；boss 恒 BOSS），`_shuffle_content_types` 已弃用。
- **功能房 type 是隐形契约（2026-09-19 修复）**：入口/出口/撤离房/Boss/Boss 前厅的 `type` **不在设计源里**（`content_type` 是可选覆盖、缺省空合法），由 `_default_type_for_role()` 给：`stair_entry|stair_exit → STAIR_LOBBY`、`extraction → EXTRACTION`、`boss → BOSS`、`boss_prep → UPGRADE`（与内置房表逐值一致）。同一 `FUNCTIONAL_ROLES` 常量用于 `content_room_count`（远征 5 = 7 房减 entry/extraction）。**几何/门槽校验发现不了这类丢失**，必须靠产出断言。
- **新关卡放好目录即被 `LevelPlanLoader.data_root_for()` 自动发现，无需改代码**：`source/art/whitebox/tower_zones/<level_id>/v001/data/`（`battle_level01` 固定 `v004`，见 `DATA_ROOT_OVERRIDES`）。批量校验需登记进 `verify_level_plan_design_source.TARGET_LEVELS`，或跑时 `--level=<id>`。

## 运行时装配 `src/world3d/TowerDescent3D.gd`
- 走廊由 `_update_corridor_streaming()` 按门开关：**门未开时隐藏 + 碰撞卸载是既有契约，不是缺陷**。
- **禁止**对远征复用 `_reset_initial_loop_world_after_retreat()`；退出/放弃/撤离统一走 `_finish_run()` → `return_scene_path`。远征存档 `runtime_map_id="expedition_01"`，`_runtime_scope_for_save()` 对 `is_expedition()` 返 `combat`。

## 远征关卡01
- 入口链 99F 远征情报室(`mission_operations`) → `RogueMapSelectMenu` → `ExpeditionLoadingScreen` → `ExpeditionLevel01_3D.tscn`；区块 = 第五根 `Blocks/Expedition`。
- **⚠️ 该场景现在是 `TowerDescent3D.tscn` 的继承场景**（`instance=ExtResource`，塔楼整棵节点树无条件随加载），「干净」全靠运行时减法。**主人 2026-09-19 判定「继承」不对，要求改成真正独立的新场景 —— 待办，未实现。**
- 污染根因：`is_expedition()` 在 `TowerDescent3D` 里**散落 31 处**、三种风格，**默认分支 = 塔楼形态**，漏一处就是一次污染。
- **包络两道开关（缺一即回归）**：`TowerFloorStage3D.configure()` 第 5 参 `force_standard_map=true`（否则 `floor_index==0` 命中 100F 天台窄轮廓 → 6/7 房无楼面无外墙、玩家踩空）；第 6 参 `content_bounds=_expedition_content_world_rect()`（实测 `Rect2(-10,-50,135,70)`；否则铺满 250×250）。
- **干净场景**：`Blocks/Base/Art`（99F 美术≈1200 节点，y≈0）必须 `_remove_tower_base_art()` 整棵释放（只 `visible=false` 碰撞体仍在 → 隐形阻挡）；水平走廊走 `_connector_block()`；**垂直楼梯走廊禁止走它**（会打挂 `verify_tower_level_blocks`）。
- 门禁 `verify_expedition_level01_flow`（`EXPEDITION_LEVEL01_FLOW_OK`，core）。细节见 playbooks。

## 资产与命名
- `_vNNN` 视为已接受命名，只防新增；`assets/art/**/*.gd` 不纳入命名扫描。台账真源 `assets/registry/ledger_index.json`（条目在 7 个分账本）。
- **口径 = 统一契约、不统一装配**：墙/地砖 MultiMesh 批量，门墙/门逐 prefab。契约唯一解析入口 `TowerGeometry3D.resolve_visual_node|mesh|bounds` + `origin_offset_y()`；门禁 `PREFAB_CONTRACT_OK`。
- **A/B 两套装饰面朝向相反**：A 套（`prp_tower_*`）在 Godot **+Z**；B 套（`.../common_components`，含 v007）= **-Z**；跨套复用必须绕竖轴 180°。YUP 映射 **Blender +Y → Godot -Z**。墙体已落地该范式（v004：Blender 内烘焙 yaw=180° 再 `transform_apply`）。
- `TowerDescent3D.gd:25 TOWER_WALL_SCENE` **直接 preload 裸 GLB** → GLB 根节点变换直接决定走廊墙位置，**导出前必须把 ROOT 归零、变换烘焙进网格数据**。
- 版本字符串**无单一真源**，换版必须同批改三处：prefab `metadata/asset_version` + `TowerDescent3D.gd:2295 source_visual_version` + `verify_tower_grid_component_alignment.gd:262`。
- `bounds_size_m`（玩法阻挡，塔楼墙恒 0.30m）与 `visual_bounds_size_m`（实测可视包络，可更大且不对称）**刻意分离**。墙体 v004 可视 `5×11.9×0.4675`（装甲凸 +Z 0.3175、背 -0.15）；门禁判「结构盒 ⊂ 可视包络」而非「可视底面==0」。
- **Blender 导出三个坑**：① `--factory-startup` 不打开文件，要 `bpy.ops.wm.open_mainfile`；② glTF 默认写**全部** Scene（`use_active_scene` 默认 False）→ 源含审阅场景时会导出空场景，须收敛到 1 个；③ 删朝下面要**先三角化再删**（n-gon 面平均法线可能高于阈值而其三角形低于，先删会残留隐藏面）。
- **台账写入**：分账本带表对象/数据校验/派生列数组公式，**改行走外科式 XML 补丁**（`t="inlineStr"` + 保留 `s=`，其余条目按原 `date_time/compress_type` 字节复制），别用 openpyxl/Office 整本往返。内容编辑**必然**触发 `verify_ledger_split` 的 `row_content_mutated` → 口径 = `missing=0 extra=0` 且 `column_digest_drift` 仅命中被改列。**资产级改动日志写在《资产主表》备注列；总目录《版本记录》是全局粒度、不登记单件。**

## 验证与验收
- 逐场景 `--headless --path . res://tests/verification/<场景>.tscn` 再 grep `*_OK`；跑前先 `--headless --path . --import` 重导入。`visual` 场景**不带 `--headless` 直跑**（实测 `TOWER_DESCENT_VISUAL_OK`，截图落 `outputs/verification/`）。以 `*_OK`/`VERIFICATION_SUITE_OK`/`FAILED_SCENE` 为准，**不看裸退出码**。日志放 `_scratch/`。
- **别把既有环境性红项当回归**：`verify_ledger_split` / `check_asset_registry`（openpyxl 把派生列数组公式读成 `ArrayFormula`）、`verify_base_world_flow`、`verify_3d_performance_budget` 现在都是红的。判据 = 「红项 ⊆ 基线」。`verify_tower_descent_flow` 已迁移为占位（只印 `TOWER_DESCENT_FLOW_MIGRATED`），无 `_OK` 属正常。
- **GDScript 陷阱**：`Node3D` 类型变量上的方法返回值不能用 `:=` 推断（如 `stage.get_snapshot()`），必须显式标注类型；否则 parse error 令场景空跑挂死无输出。
- `verify_level_plan_design_source`（S7，core）**两条判据缺一不可**：`LEVEL_PLAN_VALIDATE_OK levels=2 checks=135 rooms=23 templates=9`（设计数据自洽）+ `LEVEL_PLAN_RUNTIME_GUARD_OK levels=2 rooms=23 checks=2`（**真调生成器**验产出可用：功能房 type / 尺寸 / 内容房计数）。**静态自洽 ≠ 产出可用**。带 `--emit-ports` 取门槽，**禁止手推**。
- **南北约定红线**：平面 `+y → 世界 +z → south`。门侧写反**不会让任何几何校验失败** → 靠 `LevelPlanValidator._validate_port_derivation` + `RoomDoorLane.port_pair` 断言。`LevelPlanLoader` **数据优先**，缺失才派生，**绝不静默覆盖**。

## 技能链路
- 场景美术 `00`→`01`→`02`→`03`→`04`；道具武器 `05`→`06`→`07`→`08`（资产根 `assets/art/items_weapons/`）。正本 `~/.workbuddy/skills/`，镜像走 `skill-mirror-sync`（`SKILL_MIRROR_CHECK_OK`）；交付包 `outputs/`。
- 关卡设计源 `09-level-plan-authoring`；配套填表 `docs/v0.1/design/新关卡设计表.md`。规范 `docs/v0.1/05.2_...md`（§8 批次表 / §8.1 门侧反向复盘 / §8.2 功能房类型丢失复盘）。
- **填表分区契约（主人定）**：六段 ①你要填的 ②可以改的 ③固定的 ④工具自动算的 ⑤硬规则 ⑥填完之后；**要填的在前、可调的居中、固定的在后；表内不放任何范例**。
- **技能触发契约**：主人说「**准备生成一个新关卡**」→ 第一动作是把设计表**第一部分原样贴出**，等他填完才动手。
- **面向主人的表述规范（硬要求）**：待拍板/待决策的事**说影响、不说计算机术语**（翻成「玩家存档会打不开」这类话）。
- **新增 Godot 脚本一律用显式 `const X := preload(...)`，不用 `class_name` 全局名**（缓存未刷新会连锁编译失败）；重建缓存 `--headless --path . --import`。

## 并发与安全
- 并行会话/常驻 Godot 进程可能造成批量文件暂时消失、重写 `.import`、占用 xlsx；动手前先取快照，**勿把缺失直接当本步骤删除**。

## 肉鸽新方向（提案，未授权）
- 关卡 01 固定 10 种完整房间、每房四固定门位、仅随机排列 + 门间走廊；是否每局全用 / 含安全屋终点 / 尺寸层数**待定**。**不要把提案当已完成能力。**
"""


def main() -> int:
    old = INDEX.read_bytes().decode("utf-8")
    assert old.count("\n") == old.count("\r\n"), "not pure CRLF"
    new = CONTENT.replace("\n", "\r\n")
    INDEX.write_bytes(new.encode("utf-8"))
    d = INDEX.read_bytes()
    print("MEMORY.md bytes=%d (was %d) CRLF=%d LF-only=%d" % (
        len(d), len(old.encode("utf-8")), d.count(b"\r\n"), d.count(b"\n") - d.count(b"\r\n")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
