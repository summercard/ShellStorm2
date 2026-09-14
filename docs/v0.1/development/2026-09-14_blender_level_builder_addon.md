# Blender 原生关卡搭建插件

日期：2026-09-14  
功能ID：`ASSET-LEVEL-BUILDER`  
设计修订：`ASSET-SCENE-3D r3`

## r2（2026-09-14 修订）

针对 r1 试用反馈的四类问题做定点修复：组件结构过深、吸附不可用、预览不可读、可用性不足。

### 组件改为单网格 + 锚点对齐游戏资产

- 新增 `geometry.py`：所有组件（墙/地板/柱/门洞/楼梯/栏杆/设施）先算出一组局部盒子，再合并为**一个 Mesh**，不再生成 Mesh+子物体的层级。楼梯按踏面+踢面逐步堆叠，底面统一为 `Z=0`。
- 锚点策略由 `Scene.sslb.origin_mode` 控制：
  - `BOTTOM_CENTER`（默认）：原点在包围盒底面中心，与游戏内实墙 GLB（`env_tower_wall_solid_5m_top3d_v003.glb`，Z 范围 `0..11.9`）一致。
  - `GAME_ASSET`：地砖类使用**厚度居中原点**，与运行时地砖 GLB（`env_tower_floor_tile_5m_top3d_v002.glb`，Z 范围 `-0.15..0.1505`，manifest 标注 `runtime offset -0.15`）一致，其余类型仍为底面中心。
- 实测依据：上述 GLB 经 Blender 导入量取包围盒得出，结论以真实 GLB 为准，不按命名或视觉猜测。
- `reanchor_object()` 直接改写 Mesh 数据并反向补偿物体矩阵平移，重设锚点前后世界坐标不变（自测断言覆盖）。
- 新增 `sslb.reanchor` 算子：对选中组件重算锚点，用于 r1 旧组件或手工编辑后的模型。

### 吸附恢复可用

- 根因：r1 依赖 Blender 原生吸附，但从未打开 `tool_settings.use_snap`，也没有设置吸附元素/目标，视口里自然"吸不动"。
- 新增 `sslb.configure_snap`：一键把 `use_snap`、`snap_elements={VERTEX, INCREMENT}`、`snap_target=CLOSEST`、绝对网格与对齐旋转打开，并把视图网格步进取 `grid_size`（默认 5m）。「建立规范集合」会自动调用它，保证建场景后吸附必定是开的。
- 新增 `snapping.py`：`unit_members` / `unit_roots` 把"Library Asset Collection"视作一个整体，吸附按整组包围盒计算，不会把子级拆散。
- 新增算子：
  - `sslb.snap_to_grid`：整组吸附到 5m 平面网格 + 0.3m 标高步进，并归零旋转。
  - `sslb.snap_adjacent`：按 +X/-X/+Y/-Y/顶面 五个方向贴边对齐到活动对象。
  - `sslb.align_to_active`：按 X/Y/Z 单轴或多个轴把中心对齐到活动对象。
  - `sslb.move_to_cursor`：整组移动到 3D 游标。
- 「吸附与对齐」面板同时暴露原生开关，保留 Blender 原生操作习惯，插件不实现第二套移动系统。

### 预览增强

- 新增 `materials.py`：按类型着色白盒色盘（墙/地板/楼梯/门/设施/柱/栏杆），新增组件自动套用，`sslb.refresh_appearance` 可一键刷新。
- 白盒配色与线框描边改为**即时开关**：切换后直接作用到全部插件组件，不必再点刷新；关闭配色只摘掉插件占位材质，用户自定义材质保留。
- 线框描边开关（`show_wireframe`），顶视图下轮廓可读。
- 「预览与统计」面板：`sslb.measure_layout` 输出组件数量、类型分布、占地包围盒与总网格数到 `layout_summary`。
- 顶视图标注：`sslb.build_annotations` 生成 5m 网格底板与组件标注（独立 Collection，可一键 `sslb.clear_annotations`）；「显示标注」开关直接控制标注显隐，生成与删除各有独立按钮。
- 标注文字改为中文类型名 + 两行紧凑尺寸（`墙壁` / `5×0.3×11.9`），字号随网格缩放（`0.12 × 网格`，钳制 0.4–1.2m），并设 `show_in_front` 让文字压过几何；此前英文键名加单行尺寸会在相邻 5m 组件上连成一行。
- `sslb.setup_top_camera` 建立正交顶视相机；`sslb.render_top_view` 用 Workbench 渲染验收图到 `render_root`，渲染后恢复原设置（`finally` 保护）。

### 可用性与数据安全

- 新建组件改为**先建 Mesh 再建 Object**，修复 r1 的空网格数据路径。
- 组件库面板按分组展示并支持搜索；组件面板显示锚点模式与实际尺寸读数。
- `sslb.scan_library` 兼容项目 manifest 的字段别名（`manifest_source` / `manifest_collection`），此前字段名不一致导致项目资产扫不到。
- 组件库扫描给出可读诊断：面板显示"N 个可用 / 共 M 个清单（跳过 X：缺字段 a、源 `.blend` 缺失 b）"，不再只丢一个数字；空结果与搜索无结果分别提示。
- `sslb.sync_manifests` 增加保护：要求 `.blend` 已保存、拒绝空资产包，避免把空 catalog/tree 写盘；写出的清单补充 `object_names`、`blender_collection`、`generator`、`generated_at`。
- `sslb.validate_structure` 增加未归包对象报告。
- 新增 `sslb.rebuild_component` 支持多选批量重建参数。
- 对齐/吸附算子在无需位移时给出"已在网格上/已在游标位置"提示，不再报 0 个组件已移动。
- `sslb.render_top_view` 恢复的渲染设置补全描边颜色与阴影强度，渲染不再残留视口改动。
- 版本提升至 `0.2.0`，安装脚本只复制 `.py`/`.md` 并清理 `__pycache__`。

### r2 验证

- `tools/blender_addons/test_shellstorm_level_builder.py` 在 Blender 4.5 后台通过（打印 `{"ok": true, ...}`），覆盖：锚点断言、局部/世界包围盒、吸附、重设锚点世界坐标守恒、项目式 manifest 扫描兼容、算子在应中止时确实中止。
- 自测同时输出顶视图 PNG，用于人工确认网格底板、浅色标注与组件配色。
- 安装目录启用后 6 个面板与 21 个算子全部注册（Blender 4.5 下用 `bpy.ops.preferences.addon_enable(module="shellstorm_level_builder")` 验证；`--addons` 命令行开关在本版本对用户 Add-ons 目录不生效，r1 记录的该方式不可复现）。
- 仍未导出 GLB、未改动 Godot 引用，`.blend` 仍是事实源头。

### r2 遗留

- 缩略图缓存、LOD、碰撞自动生成、GLB 批量导出与 Godot 接入仍未实现。
- 真实项目资产库仍依赖 manifest 同时提供有效 `source_blend` 与 Collection 名。

## r1（初版）

## 交付

- 新增 `tools/blender_addons/shellstorm_level_builder/`，面向 Blender 4.3+，当前在 Blender 4.5.0 验证。
- 复用 Blender 原生视口、变换、吸附、编辑模式与撤销；插件不实现第二套移动或磁吸系统。
- 提供参数化墙、地板、拐角柱、门洞、直梯、栏杆和固定设施占位组件。墙体默认 `5×0.3×11.9m`。
- 建立可编辑白盒、制作组件、版本化游戏输出、展示验收及四类末级资产包 Collection。
- 支持项目 `asset_manifest.json` 扫描和源 Collection Append，本地副本可继续编辑。
- 支持所选对象及组件完整子层级归包，验证空包与多包归属，并同步 manifest、catalog 和 tree。
- 提供 `install_shellstorm_level_builder.ps1`，已安装到 Blender 4.5 用户 Add-ons 目录。

## 验证

- Blender 4.5 `--factory-startup` 注册、建墙、11.9m尺寸、参数重建、归包、结构验证和清单写盘：退出码0。
- 从已安装 Add-ons 目录使用 `--addons shellstorm_level_builder` 启用：`Scene.sslb` 与侧栏面板均存在。
- Python模块编译：退出码0。
- 插件不会导出GLB、修改Godot或覆盖已有Blend；这些仍由后续资产导入流程负责。

## 遗留

- r1项目资产库依赖现有 manifest 中同时提供有效 `source_blend` 与 Collection 名；缺字段或源文件不存在的记录不会显示。
- 尚未实现缩略图缓存、LOD、碰撞生成、GLB批量导出及Godot接入。
