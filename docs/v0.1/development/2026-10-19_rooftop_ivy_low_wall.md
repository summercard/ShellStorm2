# 井口藤蔓破损矮墙

FeatureID：ASSET-ROOFTOP / ASSET-PIPELINE / WORLD-BLOCKS。工程版本0.1.0；依据[首次登顶设计](../design/rooftop_first_visit_guidance.md)及2026-10-19用户位置截图。

## 交付与空间

新增正式组件 `ENV-ROOFTOP-IVY-BROKEN-LOW-WALL`，场景交互物件分类。井口东边、出口平台南端至杂物堆之间放置，中心(-29.4,0.015,7.7)，yaw90°。墙体长4.6m、厚0.7m、高0.98～1.55m，顶面高低缺损，两面藤蔓覆盖；独立内容ID193。布局v005共193实例、352个碰撞形状。仅将木料ID036向屋面内侧平移2m避免穿墙，其他既有实例变换保持。

墙体与藤蔓是同组件内两个独立视觉网格，墙体8段碰撞随组件移动；藤蔓归 `Foliage` 子树，单独绑定 `PlantSway3D`，墙体没有风摆材质。沿用未来移动/清除待实现状态，不新增可拾取物、存档或互动命令。

## 制作与登记

源包 `art_source/environments/tower_zones/rooftop/source/ivy_broken_low_wall/`；可编辑母版与 `export/v001/` 独立优化母版均保留。正式视觉和包装分别为 `assets/art/environments/tower_zones/rooftop/components/guidance/env_rooftop_ivy_broken_low_wall_visual_top3d.glb`、`runtime/guidance/env_rooftop_ivy_broken_low_wall_root_top3d.tscn`。资产清单记录定位、两份源及GLB的SHA、版本、面数与独立碰撞。

使用项目公共色盘；每面有效PaletteUV岛、活动/渲染UV与材质验证通过。优化执行孤立顶点和零面积清理、显式三角化；没有为追求减面破坏藤蔓背面、墙体破损轮廓和接缝，零减面如实记录。墙体1440三角、藤蔓7424三角，共8864，两个视觉网格；GLB无内嵌贴图，Godot通过公共导入脚本绑定唯一色盘。固定正/背/侧/游戏机位源与优化对照保存在工程外QA目录，清单保留源保护SHA。

场景账本主表新增1行，正式美术状态、`scene_interactive_object`；独立事务追加 `3D-场景通用` Prefab记录，并更新该页基线。布局v005的SHA与规格同步；其他资产行不接受哈希漂移。当前源索引补录母版和优化源。账本路径经 `ledger_index.json` 解析。

## 验证与边界

- 源与优化文件严格材质/UV检查通过。初轮低处叶尖越过地面被落地检查检出，抬高根部叶片生成区间后重做源、优化、导出；不放宽测试阈值。
- `verify_rooftop_guidance_clutter.tscn` 真实Forward+复验退出0，`ROOFTOP_GUIDANCE_OK`：193实例、67倾斜件、352形状，出口到桥口的玩家胶囊路线、既有剧情区域覆盖、关键阻挡点、墙体三段采样、东门净空及范围/贴地通过。
- 断言Foliage采用PlantSway3D和ShaderMaterial，Wall保留静态BaseMaterial3D；已有植物共享时钟推进/暂停检查通过。退出保留既有ObjectDB泄漏WARNING，无新增SCRIPT ERROR/ERROR。
- 进程启动前设置工程外独立APPDATA，先于Autoload隔离存档；本次直接运行正式专项，未执行全量suite/core/full或移动端专项。
- 实际出口近景与全景已查看，木料穿墙已消除，出口与桥前通路保留。
- 账本结构检查通过（1307资产/9域），目标Prefab与布局的SHA/基线指纹定点复核通过，运行资产命名通过。全局文档检查仍报告其他主题的断链和未注册 `verify_base_lamp_dynamics` / `verify_base_lamp_visual`；详见 `docs.log`，未改动这些无关条目，不宣称全库全绿。

过程日志、截图、固定机位脚本：`ShellStorm2-work/sessions/2026-10-19_rooftop_ivy_wall/`；改前布局、文档、测试、账本与基线及自动源备份位于 `ShellStorm2-backup/2026-10-19_rooftop_ivy_wall/`。未来场景交互执行/存档仍未实现。

## v002：按绿色轮廓调整厚度、高度与垂藤

依据用户补充截图，墙体结构厚度改为0.30m，与正式楼梯井围墙一致（GLB围墙截面为±0.15m）；表面细裂缝最多额外突出0.022m。墙长4.6m，靠出口端最高5.12m，向杂物堆方向破损下降至1.10m。连续断墙面取代分柱外观；原实例ID193与布局v005及其变换保留。

藤蔓直接读取 `ENV-ROOFTOP-REF-IVY` v002 的原始网格，保护原源SHA，保留叶型、色盘和UV。双面攀爬与下垂变种共用现有PlantSway3D，墙体静止。依据运行时父变换校正组件朝向；垂藤跨过屋面边缘，布置在井壁可见内侧面之外，最低世界Y约-4.01m，长短与疏密随位置变化。未来移动/清除继续为planned_locked。

源升级为 `rooftop_ivy_broken_low_wall_v002.blend`，独立优化源位于 `export/v002/`，旧版移至工程外备份。墙1216三角、藤蔓28752三角，共29968；未伪报减面。源与优化严格验证退出0，四个固定视角图像平均通道误差均小于1/255，GLB三角数一致且无内嵌贴图，原天台藤蔓源SHA未变。场景账本主表及Prefab页更新既有行到v002，当前源索引、源/导出清单与哈希同步，目标行与Prefab页基线复核通过。

最终 `verify_rooftop_guidance_clutter.tscn` 在独立APPDATA下真实Forward+运行退出0，193实例/352形状，出口到桥口胶囊通路及阻挡、风摆时钟/暂停均通过，实际近景确认垂藤可见。测试仅对该组件分开检查贴地墙体和获准向下延伸的藤蔓；新增高度、墙厚与井壁外侧包络断言，其余物件贴地约束不变。既有ObjectDB退出WARNING仍在，没有新增ERROR或SCRIPT ERROR。未执行全量套件。

运行资产命名、账本结构检查退出0；全局文档检查退出1，仍为其他主题断链及两个基地灯光用例未登记，详见本次docs_check.log。最终QA、渲染对照和日志位于 `ShellStorm2-work/sessions/2026-10-19_rooftop_ivy_revision/`；回滚备份位于同级 `ShellStorm2-backup/2026-10-19_rooftop_ivy_revision/`。
