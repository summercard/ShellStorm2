# ShellStorm2 道具资产契约

本文件服务于 `game-prop-model-pipeline`。它定义道具总源、单资产导出和后续 Godot 包装的边界，不替代 `assets/registry/ledger_index.json`、内容数据库或玩法设计。

## 1. 分类与身份

| 真实账本分类 | 归属 | 本 Skill 处理方式 |
|---|---|---|
| 子弹、弹药模块、武器配件 | `weapons` / 武器账本 | 只允许在本总源中作为独立物品视觉记录时引用；实际制作与运行接入仍受武器 Skill 约束 |
| 道具、物品、可装备背包 | `props` / 道具账本 | 本 Skill 的主要对象 |
| 固定设施、场景道具 | `scenes` / 场景账本 | 不迁移、不重分类、不改历史行 |
| 蓝图 | 读取真实账本大类 | 不按“看起来像道具”猜分类；按现有 ledger 行保持原归属 |

每一项必须保留既有 `asset_id`、内容ID、稳定运行路径、尺寸、版本和背包/装备逻辑。没有现成身份时只记录待确认，不擅自生成编号。资产分类来源必须可追溯到 `assets/registry/ledger_index.json` 与实际分账本。

## 2. 总源与单资产隔离

本轮唯一可编辑总源：

```text
art_source/items_weapons/props/reference_kit/source/
├─ prp_reference_item_kit_source_v001.blend
├─ asset_contract.json             # 待生成；不得虚报
└─ source_manifest.json             # 待生成；不得虚报
```

总源内允许多个资产，但每个资产必须有以下唯一字段：

```json
{
  "asset_id": "既有账本AssetID",
  "content_id": "既有内容ID",
  "source_collection": "唯一Collection名",
  "item_root": "唯一ItemRoot名",
  "export_collection": "唯一游戏输出Collection名",
  "restore_item_root": "从导出/展示布局恢复的根定位",
  "dimensions_m": {"width": 0.0, "depth": 0.0, "height": 0.0},
  "dimension_source": "ledger/内容数据库/既有契约的具体引用",
  "status": "待验证"
}
```

总源的展示排布只服务于审阅。展示间距、总览相机、地面、灯光、参考图平面和文字标注不得进入 `dimensions_m`、导出 Collection、局部包围盒或运行时坐标。任何由总源恢复单资产的流程都必须按 `restore_item_root` 复位，而不是沿用展示排布坐标。

## 3. 造型基线

- 本轮参考截图优先于旧文字描述：`C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-13T10-34-36-193Z-1dc7482b.jpg`（6 面板 / 31 件）。文件不可访问时记录“参考图未执行目视核验”，不得假设截图已通过。
- 全组采用粉、蓝、紫、青、黄的低模识别语言；识别核心为兔标（七顶点双耳剪影），其次为星形（预算紧张处降级为六顶点三星尖）与闪电标。
- 标识贴片必须用绝对厚度（约 0.03m）并探出宿主表面；按尺度缩放的贴片会被埋进主体，视为不可读。
- 该造型覆盖旧小包“圆顶”和中包“黄色”等历史描述；历史描述不得继续约束新造型轮廓与配色。
- 兔标为核心识别；蓝图类物品保留蓝图线稿，线稿各段 x 区间不得互相重叠，保证轮廓可读。
- 阵列排布必须让 31 件各自落在唯一 `ItemRoot` 坐标（9 列 × 4 行），网格顶点在各自 `ItemRoot` 局部居中；禁止全部叠在世界原点后靠位移假装分离。
- 背包的现有尺寸、容量、`BackpackSocket`、Godot `+Z` 前袋朝向、Blender 坐标转换、AssetID 和内容ID均保持不变。新造型只替换视觉，不改变这些运行契约。

## 4. 几何预算与反作弊判据

- 每个独立资产最终可见导出网格 `triangles <= 100`。
- 三角数必须在所有修改器求值之后从 evaluated mesh 的 `loop_triangles` 读取；ngon 不得按“一面”计数。
- 统计范围包含兔标、星星、闪电、蓝图线稿和所有装饰贴花几何；合并对象、拆分对象和实例对象都不能规避预算。
- 隐藏、禁渲染、背面遮挡、移出导出集合后再恢复、只给预览关闭或放到展示 Collection 的超标几何均属于违规。源与导出视图都要执行“无隐藏超标网格”审计。
- 旧背包 `<=500` 是历史兼容上限，不能覆盖本轮 `<=100`。记录字段可同时保存 `legacy_max_triangles: 500` 与 `max_triangles: 100`，但门禁只接受 100。
- 所有面必须有真实面积；退化三角、零面积贴花和仅用于骗取计数的线段不算有效装饰。

建议 `source_manifest.json` 为每项记录：

```json
{
  "asset_id": "既有ID",
  "evaluated_triangles": 0,
  "max_triangles": 100,
  "legacy_max_triangles": 500,
  "modifiers_evaluated": true,
  "ngon_count_after_export": 0,
  "hidden_overbudget_geometry": false,
  "status": "待验证"
}
```

## 5. 材质与 UV

- 公共色盘外链：`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`，采样 `Closest`，不得 Pack，不能在总源中复制一份色盘。
- 材质角色最多四类，采用“实际使用才创建/绑定”原则。检查每个网格的材质槽、面索引与 `material_roles_used`；未使用材质不能留作占位。
- 无贴花部分只使用 `PaletteUV`。
- 兔标与蓝图线稿允许共享一个外链 `detail_atlas.png`，所有引用指向同一文件，不为每件物品复制 PNG 或材质。
- 只在实际使用 atlas 的网格上创建 `DecalUV`，并在契约中声明 `DecalUV` 是唯一额外 UV 用途；不得创建第三种 UV 层。
- `detail_atlas.png` 只表达图案/线稿，不是第二套固有色色盘。固有色仍由公共 PaletteUV 与公共色盘决定。

## 6. 根、朝向与运行分权

| 项目 | 约束 |
|---|---|
| 根节点 | `ItemRoot`，静态资产以接地/稳定摆放基准定位 |
| 背包正面 | Godot `+Z` 朝前袋外侧，`+Y` 向上；沿用既有 Blender↔Godot 转换 |
| 手持 | 仅按真实契约建立 `HoldAnchor`；默认右/上/前为 `+X/+Y/-Z` |
| 骨架 | 静态无 Armature、无骨骼、无蒙皮、无角色动作 |
| GLB | 视觉网格、外链图像引用和必要视觉锚点；不含玩法碰撞、触发器或脚本 |
| Godot | 负责碰撞、拾取、刚体、库存、内容映射、交互和包装场景 |

GLB 与 Godot 包装要分别登记状态。源完成、GLB 导出、Godot 导入、碰撞验收和正式可用不可合并成一个“完成”字段；任何未执行阶段必须如实写明。

## 7. 未来交付字段与待验证口径

`asset_contract.json` 至少要声明：总源路径、资产清单、真实账本/分页、AssetID、内容ID、尺寸来源、`ItemRoot`、导出恢复路径、风格参考、材质角色、公共色盘、UV 层、三角预算、骨架状态、GLB/碰撞/玩法所有权及回滚路径。

`source_manifest.json` 至少要声明：源文件 SHA-256、Blender 版本、总源保存时间、每资产 Collection/root、应用修改器后的三角数、面数、包围盒、材质/UV 审计、外链文件 SHA-256、导出状态、未执行项和验证命令。

在这些文件和实际证据生成前，统一使用 `待验证`；本规范本身不证明 `.blend`、GLB、碰撞、Godot 导入或真实渲染已经完成。
