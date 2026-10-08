# 玩家持枪左移、右移、后退动作 v027

日期：2026-10-07；功能ID：PLAYER-STATE / ENTRY-AVATAR / ASSET-PIPELINE；工程版本：0.1.0；交付：工作区未提交。
依据：用户指定沿用v026持枪状态制作三方向；[主设计](../16.1_角色美术制作与动作导入流程.md)。

## 交付范围

三枪型 `sidearm / longgun / machinegun`，两个速度档 `walking / moving`，三个方向 `strafe_left / strafe_right / backward`，共18条独立循环。慢走1秒、正常移动0.8秒；前进不在本批。短枪按本轮明确要求保留v026前上倾，长枪斜持、机枪低持；不套用较早通用低枪口规则。

源文件：`assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation/chr_bunny01_animation_v027.blend`，场景17–34，名称直接含类型/速度/方向。模型继续链接v021，v026文件及全部旧Action保留。运行源仍未切换。

左/右按角色自身坐标：Blender -X/+X；朝向+Y，后退-Y。分别控制先迈脚、支撑相位、横向张脚或纵向撤步轨迹。支撑段匀速反向滑动用于原地动画抵消未来玩法位移，恢复段为匹配端点速度的Hermite曲线与抬脚；不是旋转或倒放前进动画。机枪步幅为同档88%、抬脚85%，上身摆幅更小。保持v026的枪体相对躯干/头/双手矩阵，整个上身随步态轻微起伏。

现有角色是悬浮手脚刚性组件，腿部辅助骨只作连接求值，不声明适用于连续腿网格。root不动，模型和静止骨架签名不变；动画内枪、相机及枪预览Action仍仅用于预览，不导出为角色资产。

## 验证与状态

制作与验收：`scripts/blender/author_bunny_directional_v027.py`；独立方向/接触检查：`scripts/blender/check_bunny_directional_v027.py`。证据目录 `outputs/character_pipeline/directional_v027/`。

- 保存重开，每0.5帧检查18条骨架签名、单位缩放、根不动、面朝向、臂链、双握点、首尾接缝；每2帧检查可见网格接地。结果 `validation.json`。
- 独立按0.25帧验证支撑速度方向、两脚抬起以及相对v026的上身/枪/握点矩阵。结果 `direction_contact_validation.json`。运行速度同步未接线，不能据此声称游戏内无滑步。
- 原生Workbench每循环20帧，共360张；侧移正视、后退侧视。每条GIF及慢走/正常移动九宫格预览由真实渲染帧组成，不是AI合成。
- 源级中转 `source/animation/chr_bunny01_directional_v027.json` 登记文件哈希、方向、时长、步幅与创作参考速度；同角色ID登记账本，不新增Prefab或修改运行版本。

状态仅authored/待导入。Godot播放、移动速度同步、进出动作混合、正式镜头、全工程套件未执行。回退使用保留的v026；四方向完整集合还缺本枪型基准的前进循环。按工程规范分别保留改前/改后门禁，不批量接受无关资产哈希或路径债务。

验收结果：18条动作的两组数值检查通过，已查看慢走/正常移动总览及后退不同相位渲染；账本新增动画行64–81、中转行110–111，主表仅追加P13/Y13的源路径与说明，保留原运行版本和数据验证。账本结构、无损拆分检查改前/改后均通过。角色全量检查仍有既有第21行头部Prefab哈希差异，文档检查仍有4个既有未登记测试；本次未扩大这些失败。运行命名门禁仍报告既有14个版本化文件、3个目录及TSCN引用93→98，无v027运行资源；未更新债务豁免。详见证据目录的before/after日志与ledger_edit_report.json。
