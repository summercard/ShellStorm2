# 电子面具表情自发光减弱

FeatureID：ENTRY-AVATAR、ASSET-PIPELINE；ModuleID：CHARACTER-EXPRESSION；工程0.1.0；日期2026-10-01；设计修订r3。来源：用户要求“表情的自发光调弱一些，现在光晕太晃眼了”。[目标契约](../design/character_expression_system.md)。

8种表情材质的自发光强度从5降至1.25（减少75%），保留原RGB色彩和饱满无嘴部网格。模型/动作双母版均使用新强度；闪烁仍按原相对亮度曲线采样，恢复亮度也是1.25。父面具v005，8个既有子资产v003，稳定运行路径保持，旧v001–v004双母版保留。

## 验证与账本

- Blender独立重开源审计退出0：8种材质强度均为1.25，双母版闪烁曲线吻合；原11网格、UV、材质、权重、变换及骨架静止签名不变，1448壳体顶点保留；六种情绪闭眼形态与原网格计划通过。
- 实际8个导出GLB的KHR_materials_emissive_strength均为1.25；Forward+实拍总览已亲眼检查，光晕明显减弱、方块边界清晰。[总览](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/expressions_overview.png)。
- `verify_character_expression_flow`：无头696项、Forward+706项，退出0；8种随机可达、独立系统与状态机调用、显示、颜色、无嘴部几何不变。
- `verify_electronic_mask_flow`：无头73项、Forward+76项，退出0；眨眼、闪烁相对亮度及恢复、实际换装存档读回均通过。原亮度/颜色阈值未放宽。最终专项日志无非预期脚本或引擎错误；预期失败无。
- 角色账本主表父行22升级v005、8子行23–30升级v003；组件45–52、3D分页10–17、表达记录53–60更新原行；中转追加79–105，域日志v0.1.9。主表与锁定专表分事务回读并校验；保留其他987个资产指纹。结构/拆分门禁和九个version_increment资产守卫通过。
- 新版机器事实见[验证报告](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/verification_report.json)。未执行：整游戏full、移动设备性能、五项与材质无关的身体回归；上轮身体回归记录保留，不计入本次通过。未提交或推送。

全局既有女仆头SHA不符、运行资产版本路径债、三项未注册场景与本次材质调整分开记录，未批量接受其它资产哈希。

专项第一次面具运行恰逢共享工作区DungeonRoom3D的shape_diagnostic临时引用导致Autoload编译错误，虽退出0仍未接受。该处随其它工作恢复后重新运行无头/Forward+面具检查，两份最终日志没有脚本/引擎错误；本次未编辑world代码。文档检查退出1仅既有三项未注册场景；命名检查退出1为14个既有版本路径及既有引用；全角色资产检查退出1仅第21行女仆头SHA不符，逐格确认改前后相同。
