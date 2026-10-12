# 98F 第四间门厅壁画补碰撞

- 功能：ASSET-PIPELINE / WORLD-BLOCKS；工程 0.1.0。
- 来源：主人反馈「98F 第四个房间的掉下来的那个壁画的组件，没有阻挡，帮我加一下」。
- 对象：`PRP-BLOCK00-CONSTRUCTIVIST-MURAL`（工业时代构成主义壁画），98F 第四间门厅唯一实例 `constructivist_mural_014`。

## 现状与根因

该壁画在 2026-10-09 反馈轮里从「悬挂」改成「向后倾 22°、侧倾 6°、斜靠地面」（见 [98F 四房设施导入](2026-10-09_block00_facilities_import.md)）。但它在 `scripts/assemble_block00_facilities.py` 里没进 `solid` 集合，被判成纯装饰：`collision_policy = visual_only`，Prefab 里连 `Collision` 节点都没有 —— 玩家能直接穿过画板。

## 改动

1. **稳定 Prefab** `assets/art/environments/master_office_3d/runtime/prp_block00_constructivist_mural/prp_block00_constructivist_mural_root.tscn`：新增 `BoxShape3D`(10.3×6.28×0.37m) 与 `StaticBody3D`/`CollisionShape3D`（layer 1 / mask 0），`collision_policy` 由 `visual_only` 改为 `fitted_box`。盒尺寸与中心由导入清单 `bounds_min`/`bounds_max` 经 `assemble_block00_facilities.py` 的同一公式换算，所以盒体随实例 transform 一起倾斜，底面正好落在实测最低网格点 0.091m，不穿地、不与房间壳体互相侵入。
2. **导入清单** `art_source/.../env_block00_story_rooms/export/v001/import_manifest.json`：`constructivist_mural` 的 `collision_policy` 与 `prefab_sha256` 同步（`check_block00_import_delivery.py` 逐件比对这两个字段）。
3. **来源脚本** `scripts/assemble_block00_facilities.py`：`solid` 集合补入 `constructivist_mural`，注明补入日期与原因，避免从零重建时又漏掉。
4. **验收** `tests/verification/verify_block00_facilities.gd` 新增断言：`Collision` 节点存在 → 形状是 `BoxShape3D` → 盒尺寸匹配视觉包围盒 → **从盒外 0.6m 向盒中心打物理射线必须被命中**（`mural_blocks_ray`）。改回 `visual_only` 必红。
5. **账本**：`ShellStorm2_场景账本_v001.xlsx`《资产主表》壁画行与 `3D-设施` 分页同步——碰撞开关 无→开、碰撞归属 无→Prefab自身、碰撞方式 `visual_only`→`fitted_box`、SHA-256 与更新时间；`ledger_split_baseline.json` 对应行指纹、列指纹与分页指纹一并更新。

变更脚本：`scripts/add_block00_mural_collision.py`（Prefab + 清单）、`scripts/register_block00_mural_collision.py`（账本 + 基线）。取证目录 `outputs/block00_mural_collision_20261012/`。

## 边界

- Blender 源、GLB、`lobby_facilities.tscn` 布局与实例姿态一字未动：房间尺寸、存档布局 ID、门洞开口与其余 27 件设施不受影响。
- 壁画本身是板状体，AABB 盒即实体本身，不存在非矩形件那类「空阻挡」（区别于需要手工分段的 L 形/U 形组件）。
- 未做：真实窗口渲染截图、全套件（smoke/scene）回归。

## 验证

- `verify_block00_facilities`（headless）：**265 项通过、0 错误**（改前 259 项）。新增 6 条断言全绿：
  - `mural_collision_shape_present` / `mural_collision_is_box` / `mural_box_matches_visual_bounds`
  - `mural_blocks_ray`：从盒外 0.6m 向盒中心打物理射线，必须被命中 —— 这条直接证明「玩家过不去」。
  - `mural_collision_box_not_sunk_into_floor` / `mural_collision_box_ground_contact_matches_visual`
  - 实测：网格最低点 `0.09099996`（与改前一致，姿态未变）、碰撞盒角点最低 `0.07424`（贴地、比视觉最低点低 1.7cm，不穿地）。
- `verify_ledger_split`：`LEDGER_SPLIT_VERIFY_OK assets=1063`，失败 0，列指纹漂移 0。
- `check_asset_registry --scope structure --ledger scenes`：OK（867 行）。
- `check_asset_registry --scope full --ledger scenes`：464 条 `sha_mismatch` 全为既有债务，**壁画与门厅布局两个目标资产零问题**（改前同口径为 466 条）。
- `check_documentation_contracts` / `check_asset_runtime_naming` / `check_workspace_hygiene` / `check_verification_registry`：新增内容无新问题，报出的仍是既有债务（1 条历史断链、6 项未注册测试、媒体域 ui 行数、outputs 在项目内、300 个历史带版本文件名）。

### 未执行

- 真实 Forward+ 窗口渲染截图分支（只跑了 headless 物理与几何断言）。
- 全套件 `smoke` / `scene` 回归。
- `check_block00_import_delivery.py`：它依赖 `outputs/block00_story_rooms_20261009/`（该目录已不在当前工程里），跑必崩，与本改动无关。**其中「清单哈希 == 磁盘哈希」的断言已单独复验：壁画的 `prefab_sha256`、`glb_sha256`、`optimized_sha256` 三处一致。**
- 验收脚本结尾顺带修了一处会吞结论的缺陷：原先先写产物再 `print`，而产物目录不存在时 `store_string` 打在 null 上会中断函数，导致既不打印结论也不 `quit()`（进程被 autoload 挂着空转）。现改为**先打印结论**，写入失败只 `push_warning`。

## 遗留（既有债务，非本次引入）

- 导入清单里 29 件组件的 `glb_path` 哈希当前**全部对不上**磁盘文件（`prefab_sha256` / `optimized_sha256` 全部匹配）。这不是本次造成的 —— 改前改后同为 29 条。但 `check_block00_import_delivery.py` 的逐件哈希断言因此本来就过不去，需要单独一轮确认是 GLB 被后处理过、还是清单没跟着更新。
