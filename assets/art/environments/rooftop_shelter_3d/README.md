# 末世天台庇护所 90×80m 模块化场景

- 当前资产 ID：`ENV-ROOFTOP-SHELTER-90X80`，版本 `v017`；v016及更早文件保留回滚。
- 网格契约：90×80m，由 18×16 个 5×5m 标准地砖组成；扣除36格基地中庭与18格西楼梯开口后，运行输出严格为234块地砖。
- 游戏坐标契约：屋顶 `Rect2(-50,-35,90,80)`；基地中庭净空 `Rect2(-15,-10,30,30)`；西楼梯净空 `Rect2(-45,0,15,30)`。
- Blender 单位：米；正面 `-Y`；上方向 `+Z`。
- 场景源文件保留独立地砖、结构、家具、植物、设备、灯光和动效对象。
- `01_制作组件_已统一材质` 保存 12 种隐藏地砖母版；`02_游戏输出_独立模块` 保存可编辑总场景。
- 运行 GLB 不内嵌图片；引擎导入时绑定项目公共色盘。

当前文件：

- `source/env_rooftop_shelter_90x80m_top3d_v017.blend`
- `runtime/env_rooftop_shelter_90x80m_facilities_v017.glb`（只含设施，不含地板和围护）
- `runtime/layout_v017/components/*.glb`（68个可独立编辑组件）
- `runtime/env_rooftop_shelter_90x80m_facilities_root_top3d_v017.tscn`
- `reports/asset_manifest_v017.json`、`reports/collision_manifest_v017.json`、`reports/validation_v017.json` 与 `reports/validation_palette_v017.json`

v017沿用v016最终布局：通信高台固定在东北角`Rect2(30.5,34,9.5,10.5)`；棚屋贴北边缘布置在其西侧`Rect2(7.5,27.5,21,17.5)`，两区保持2米净距；种植继续向西收拢到`Rect2(-24,22,12.5,20)`。黄色门前动线`Rect2(15.25,-6,24,20)`仍保持零阻挡。棚屋使用独立木块搭建0.5米高平台，以可见木踏步和连续坡面落地。

棚屋是当前重点细节区：保留沙发、床铺、工作台、卷筒桌、桌面收音机、餐桌餐具、晾晒、盆栽和生活杂物，并包含高出棚顶的彩色小风车与棚内吊挂风铃动画。Blender输出细化为68个语义组件目录，未归类对象为0；Godot包装场景的`布局_可手动编辑`下按生活棚、生存日常、能源供水、种植、通信高台五组展开，每个组件父节点都可在编辑器中单独移动，视觉与碰撞会一起随动。

阻挡采用双层职责：Blender 的`03_阻挡代理_不导出`保存39个组件级线框代理，运行GLB不包含这些代理；Godot v017包装场景将39个`StaticBody3D`直接挂到对应可编辑组件下，共82个细分`CollisionShape3D`。圆桌、水箱、风机等圆形物体使用圆柱碰撞；沙发、桌椅、棚架、高台与栏杆使用贴合结构的组合形状；温室只阻挡四根立柱；太阳能板使用薄斜面，避免空气墙。小木梯与高台楼梯使用连续倾斜坡面，黄色动线内无阻挡。

正式运行时由`src/world3d/TowerFloorStage3D.gd`在100F实例化v017设施包装场景。v017只负责68个可编辑设施组件及39组/82形状的设施阻挡，不再导入Blender地板、围护、灯光、植被、VFX或远景。100F原有Godot地砖、围栏、门洞视觉、承重面和外围边界碰撞全部保留；`布局_可手动编辑`统一下移0.34米，使设施落在原生地面Y=0上。

灯光变体：

- `source/env_rooftop_shelter_50m_lighting_day_v011.blend`：大雾阴天白昼。
- `source/env_rooftop_shelter_50m_lighting_night_v011.blend`：此前夜间暖灯参数，使用同一套 v011 实体化场景模型。

唯一公共色盘：

`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`

材质角色固定为：

1. `01_精工金属_紫色骨架`
2. `02_细腻哑光_青绿大面`
3. `03_清漆反光_紫粉点缀`
4. `04_柔和自发光_UI灯光`

`components/` 对应 Blender 内部资产分类；v017对象级位置、尺寸、材质、集合、动画和资产 ID 记录于 `reports/asset_manifest_v017.json`，组合阻挡尺寸与坐标记录于`reports/collision_manifest_v017.json`。`components/UI/` 保持为空，场景展示不包含 UI。
