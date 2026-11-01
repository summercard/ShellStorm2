# 2026-11-01 远征03顶灯外壳与室内投影

工程0.1.0；FeatureID：WORLD-PLAN、ASSET-PIPELINE。来源：用户要求去掉每房中央方形灯模型，保留照明功能，并指出室内家具没有投影。主设计：[其余房间与通道陈设](../design/远征03其余房间与通道陈设.md)。

根因：此前顶盖遮住太阳，`IndoorEnvelopeBounce`却沿Omni默认值关闭阴影，作者重点灯也主要不投影，导致房内物件缺少落地阴影。修正只在远征03专属表现脚本：基础Omni启用真实阴影；不打开太阳、不删除顶盖、不修改共享灯或其他关卡。

中央黑色方块是WastelandLight3D的顶灯挂座/灯体/灯罩几何。表现节点只隐藏`CeilingMount/Fixture/Lens`并关闭其自身投影；不隐藏父节点、不删除LampLight，不动开关、运行激活、闪烁或房间状态。初始子树扫描及node_added的延后处理覆盖随后进房与detail重建；公馆台灯/壁灯沿原Prefab。房间TSCN、门、家具、碰撞和存档规则不改。

测试在工程外显式独立用户目录工程进行，guard核对OS用户路径和BaseManager.save_path退出0。正式project.godot保持原样；当前采用用户截图种子1211616576、Godot4.7.2、Mac M1/OpenGL Compatibility真实渲染。逐房灯壳、开关能量、detail卸载重建及相同相机投影开关画面结果在交付附记登记。开启阴影增加渲染成本，不把功能通过当目标设备性能通过；未执行整关通关、全部种子、Forward+和Windows性能预算。

## 交付附记

原生验收退出0：`EXP03_LIGHT_OK checks=340 fixtures=26 failures=0`，覆盖26个实际房间。顶灯外壳隐藏、开关能量归零/重新点亮、detail重建后继续隐藏通过；所有室内主光开启投影。最终SCRIPT/渲染ERROR 0，Compatibility的既有Forward+限定效果WARNING保留。

[真实画面与机器摘要](../../art/expedition03_light_shell_shadow_20261101/README.md)。同机位阴影开关对比有436774像素差异超过10；已亲眼确认角色、家具和瓶罐投影。当前阴影较硬，不宣称目标设备性能已通过。

文档检查退出1，仍为相同44项旧问题；关卡解耦退出0；运行命名退出1，仍是既有bunny版本目录/import；diff检查退出0。全部原房间资源与正式project.godot哈希不变，模型/房间文件未变故不回填资产或布局SHA。仅更新表现策略与开发记录。

本次独立测试工程及UUID用户目录链接已清理，复现配置/脚本/日志/隔离数据留在工程外；未动默认存档或用户游戏。重新进入远征03读取修改。
