# 塔4 · 植被侵占破损商城 v008

源文件：`塔4_植被侵占破损商城_150x50m_v008.blend`。AssetID：`ENV-OPENWORLD-TOWER04`。

按用户对高覆盖植被的纠正，重做棚边叶冠、柱体攀缘、屋顶与立面垂挂、花池溢生及砖缝杂草；补非承重玻璃缺片、框架锈蚀和铺装细小剥落。保留150×50m结构、五层、原路线、设施摆位及四个原材质。

共1673独立组件包、37组件族，新增564个植被包。制作源隐藏，`02_游戏输出_独立资产包_v008`为输出集合。每包清单位于`component_packages/`；植被末级包XY≤8m。中性固定场景为`Scene`，展示场景为`塔4_黄昏末世氛围`。

`previews/`与`mood/`各有6张真实模型渲染。构建、保存重开、UV及逐图观察分别在`qa/`。制作方自检与用户视觉确认分别记录，不能将技术通过写成用户已认可。

这是约608万输出面的高密制作源，尚未制作低模/LOD、碰撞、导航，未导入Godot。保留公共色盘风格，地表与设施仍比写实参考整洁，参考远景城市未纳入资产。

制作入口：`tools/blender/refine_tower04_overgrowth_v008.py`；未登记草稿的校验和保护表面修订：`tools/blender/refine_tower04_v008_surface_finish.py`；保存重开验收：`tools/blender/audit_tower04_overgrowth_v007.py`（读取当前文件目录，可校验v008）；逐图记录：`tools/blender/review_tower04_overgrowth_v008.py`。
