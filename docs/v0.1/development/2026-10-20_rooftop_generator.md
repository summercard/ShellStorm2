# 100F中央房屋东门南侧发电机

FeatureID：ASSET-ROOFTOP / ASSET-PIPELINE / WORLD-BLOCKS。工程版本0.1.0。依据[首次登顶场景设计](../design/rooftop_first_visit_guidance.md)及2026-10-20用户确认：占地1.5×2米，中央房屋东侧门南边。

## 资产与接入

新增 `ENV-ROOFTOP-GENERATOR` v001，包含底座/隔振脚、机组外壳、防护框架、散热格栅、油箱盖、排气口、控制面板、输出插座和自然落地电缆。主体占地1.5×2m，最高约1.47m；电缆是随宿主的固定附件，宽度超出机身占地，不冒记为全件包络1.5×2m，也不虚构建筑供电连接。现有基地99层备用发电机保留，本件是天台独立资产。

正式源 `art_source/environments/tower_zones/rooftop/source/generator/rooftop_generator_v001.blend`；独立优化源在同包 `export/v001/`。稳定GLB：`assets/art/environments/tower_zones/rooftop/components/generator/env_rooftop_generator_visual_top3d.glb`；稳定Prefab：`assets/art/environments/tower_zones/rooftop/runtime/generator/env_rooftop_generator_root_top3d.tscn`。

正式引导布局v006新增 `EastDoorGenerator/roof_clutter_194`，位置(18,0.015,4.5)，中央房屋东门南侧。193个已有实例节点块逐一一致，不调整已有花箱、断墙、箱堆或剧情触发。全布局194实例、353碰撞形状。机身一个独立碰撞盒，电缆无碰撞，预留InteractionAnchor与CableSocket。

归scene_interactive_object与scene_interactive_content；交互状态planned_locked。用户未指定启动/停机、供电对象、条件或存档设计，当前只登记场景交互资产与预留接口，不宣称已能发电或移动清除。

## 制作与验证

使用项目唯一共享色盘，两个材质角色、两个输出网格；源制作组件隐藏、正式输出显示。机身3005三角、电缆1552三角，共4557；独立优化源执行零面积与孤立点清理、法线重算、三角化，低段倒角和电缆保留，减面率0如实记录。重新打开优化文件再导出，源SHA保持；GLB无内嵌贴图，使用共享色盘导入脚本。

源/优化严格PaletteUV与材质验证退出0；正/背/侧/游戏视角固定相机对照平均通道误差小于1/255；原193实例范围签名保持。独立进程APPDATA在Autoload前隔离；真实场景专项增加尺寸、机身碰撞、电缆无阻挡、东门南侧位置、门前通路及与其他碰撞不重叠检查。

最终真实Forward+专项退出0，ROOFTOP_GUIDANCE_OK：194物件、353碰撞，新增尺寸/位置/门前净空/无重叠检查及原有桥前路线检查均通过；实际截图已核对。退出保留既有ObjectDB泄漏WARNING；无SCRIPT ERROR/ERROR。未运行全量套件或新增发电玩法验证。

场景账本主表新增第972行、Prefab专页第800行；查重公式、总览范围、DV和筛选范围同步，当前源索引与导出清单齐备。目标发电机与布局的SHA、行基线及场景Prefab页基线通过，非目标资产主表内容逐格保持。账本结构退出0（1335资产/9域）；命名门禁退出0。

场景域全量哈希门禁退出1：与改前对照，基地总布局、基地剩余设施、地下街三项SHA差异完全相同，本次布局SHA已同步；未接受无关漂移。跨域拆账门禁退出1，报告其他工作中的VFX-BOARD-DEBRIS-3D未入基线及3D-特效页差异；未修改该域。全局文档门禁退出1，为其他主题断链及基地灯光/楼梯栏杆用例未登记，本次文档未出现断链。过程文件统一位于 `ShellStorm2-work/sessions/2026-10-20_rooftop_generator/`，改前备份位于 `ShellStorm2-backup/2026-10-20_rooftop_generator/`。

## v002：杂乱多线入墙

依据用户绿色标线，保留原盘绕备用线，新增三条不同长度、弯曲路径和粗细的落地电缆，总计四条。三条新增线终止于东墙厚度中间：墙体世界X区间14.85～15.15m，端点X=15.00m；端点Z分别8.8、3.3、7.4m。端部略抬起入墙，未穿到内侧墙面。机身网格/UV/材质面索引SHA与v001一致，1.5×2m主体及布局位置不变，电缆继续无碰撞。接线仅为表现，供电规则仍待定义。

可编辑源与独立优化源升v002，稳定GLB/Prefab定点替换；旧源已归档。当前6885三角（机身3005、电缆3880），源/优化严格UV材质验证退出0；四个固定视角保真对比通过，原源SHA在优化中保持。场景账本既有行972、Prefab页800及当前源索引同步v002，非目标资产行保持。布局沿用v006，实例ID194不变。

真实Forward+专项退出0、ROOFTOP_GUIDANCE_OK：四线数量、三处端点在墙厚内、射线命中实墙外表面、全部电缆顶点不越过室内墙面、东门净空和原桥前路线均通过；实景近照确认。194物件/353碰撞不变，既有ObjectDB退出WARNING保留，无新增ERROR。未执行全量套件。

本轮日志、源/优化渲染与实景图位于 `ShellStorm2-work/sessions/2026-10-20_generator_cables/`；回滚目录为 `ShellStorm2-backup/2026-10-20_generator_cables/`。
