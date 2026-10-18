# 天台场景交互物件正式美术与风摆草

FeatureID：ASSET-ROOFTOP / ASSET-PIPELINE / WORLD-BLOCKS。工程版本0.1.0。设计依据：[首次登顶杂物引导r3](../design/rooftop_first_visit_guidance.md)。用户要求：补大箱类物体、地板长出与花圃同方式摆动的草、替代方块改防洪包/水泥石块，按正式流程登记为场景交互物件。

## 交付

8个独立组件：水泥碎块A/B/C、旧木料、防洪沙袋、大型旧木箱、篷布货包、地缝风摆杂草。前6项沿用既有AssetID，后2项新增。稳定GLB及Prefab位于 `assets/art/environments/tower_zones/rooftop/components/guidance/` 与 `runtime/guidance/`。场景账本主表子类 `scene_interactive_object`、正式美术状态，8行Prefab专页记录源/视觉/碰撞/版本；不将未来移动/清除能力标为完成。

布局v003沿用130个内容ID和自然疏密摆位，破损花圃白盒引用改成防洪沙袋，石块/木料包装覆盖原稳定路径；仅按新模型实际顶点重新贴地。新增12个大型箱货、48片无碰撞杂草，总190实例，其中142阻挡物，342个碰撞形状。草直接使用 `PlantSway3D`，共享花圃风摆材质和时钟；根部固定、叶尖摆动、随游戏暂停，不改公共风摆代码。

## 正规制作与导入证据

可编辑源：`art_source/environments/tower_zones/rooftop/source/interactive_clutter/rooftop_interactive_clutter_v001.blend`；独立优化源：同包 `export/v001/rooftop_interactive_clutter_optimized_v001.blend`。8个非空独立Collection、8份磁盘manifest、catalog与目录树逐件对应。源组件隐藏，输出独立；公共色盘外链、两种标准材质角色、逐面有面积PaletteUV，GLB不含images/textures，导入由公共post-import绑定唯一色盘。

优化执行孤立顶点、零面积检查与显式三角化；现有低面造型没有适合安全删除的几何，零删除量如实记录，保留底面、背面、木板接缝及轮廓，不虚构减面率。草初轮共面双面叶在glTF导出时丢失83个三角，专项发现后改为3mm厚闭合叶片，并重新验证源、优化和导出。每件源保护SHA、优化SHA、实际面数、参数、固定正/背/侧/游戏机位对照见各 `component_packages/<slug>/asset_manifest.json` 及 `export/v001/import_manifest.json`。未设未经项目批准的面数预算。

## 验收

- 源与优化Blend：严格公共色盘、逐面UV岛、活动UV/渲染UV、材质与输出检查通过；证据保留源包 `qa/`。
- 真实Forward+主场景：`verify_rooftop_guidance_clutter.tscn`，190实例/67倾斜件/342形状；胶囊路线、桥前既有剧情触发区覆盖、关键阻挡、东门净空、范围与贴地检查通过；48片草的共享风摆时钟推进与暂停检查通过。
- 8件独立加载：核对GLB实际三角数、材质表面、唯一公共色盘、根单位缩放和正式元数据。草1328三角，其余276～2084三角/件，1～2材质表面/件；不以实例总数冒充组件面数。
- 同机位源/优化预览、正式场景俯视、出口视角、草近景双时刻截图人工复核；过程日志在工程外 `ShellStorm2-work/sessions/2026-10-18_rooftop_formal/`。
- 实测前在进程环境设置独立APPDATA，先于Autoload启动；本轮直接运行正式验证场景并检查日志，未将它表述为整套suite通过。
- 场景账本全域检查仅发现既有第962行地下街源SHA不符，本次目标条目无错误；无损基线检查仅发现并行武器工作涉及的“背包物品调用索引”专页漂移。本次未接受无关资产哈希或专页差异。
- 账本结构检查通过（1306资产/9域）；运行资产命名检查通过。文档契约检查受到并行 `RUN-FORGE` 工作中尚未落盘的设计/开发/验证引用、非法 `designed` 状态及既有技术施工链接影响而失败，详见 `documentation.log`；本次天台文档与验证引用已落盘，不修改其他工作中的文件来消除红项。
- 制作源边界检查扫描时发现地下街既有 `.blend1` 和本次草修复产生的 `.blend1` 被Git忽略；本次源包自动备份随后已移入工程外备份并完成定点复核，当前包仅保留正式源与独立优化源。地下街文件未改，不宣称全库源边界已全绿。

全场景卸载仍有既有ObjectDB泄漏WARNING；日志门禁未发现非预期SCRIPT ERROR/ERROR。不宣称工程全量门禁通过。未执行全量core/full、移动端性能与LOD远景专项、移动/清除/存档玩法验收（功能尚未实现）。本轮性能核查范围为组件面数/表面数、共享风摆时钟及目标设备真实渲染，无帧率优化或跨设备性能承诺。

备份位于工程外 `ShellStorm2-backup/2026-10-18_rooftop_formal/`；包含改前布局/Prefab、账本/基线、草导出修正前源。正式布局始终由TSCN拥有，制作脚本只输出组件，不重建房间。
