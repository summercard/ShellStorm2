# 独立角色表情系统

FeatureID：ENTRY-AVATAR、ASSET-PIPELINE；ModuleID：CHARACTER-EXPRESSION；工程0.1.0；设计修订r3；来源：2026-10-01用户要求网格情绪/符号表情8种、逐项入账、先随机调用、状态机调用独立系统。

## 目标与所有者

`CharacterExpressionSystem` 是每个角色独立的表情事实所有者，持有当前expression_id、随机生成器、随机间隔和命令保持时间。它不引用玩家、战斗、衣柜、存档或角色动作库，不拥有HP/碰撞/玩法状态。`ElectronicMaskExpression3D`只订阅表情事件并呈现网格、颜色、现有Blender眨眼/闪烁剪辑。`PlayerExpressionStateAdapter`是玩法表现状态事件到表情命令的单向适配器；不把玩家状态机装进面具Prefab。

## 数据与接口

目录JSON schema1记录8个稳定expression_id、独立AssetID、名称、情绪/符号类别、颜色、blink_enabled和稳定PackedScene路径。首批neutral平静、happy开心、sad难过、angry生气（红色）、surprised惊讶、love爱心、question疑问（?）、alert警示（!）；每种由实际方块网格组成，逐项登记角色账本。

- `request_expression(id, hold_seconds=2)`：有效ID与有限非负时长才接受；拒绝时返回false且不改变当前状态。
- `request_random(hold_seconds=2)`：从目录中抽取，8种均可选，避免连续重复；保持时间期间暂停背景随机。
- `set_random_enabled(enabled)`：开关背景随机；默认开启，首次4秒后切换，此后间隔3–6秒。不改变当前表情。
- `get_snapshot()`：schema1，expression_id、random_enabled、hold_remaining、remaining_to_random、change_count。
- 事件`expression_changed(expression_id)`：有效变更后发出；再次选中同一ID只刷新保持时长，不重复变更事件。

初版状态调用策略为随机：`Player3D.presentation_state_changed`经适配器在状态ID变化时调用一次request_random(2)，初始状态不立即随机。重复同状态/进度事件不重复抽取；没有随机情绪与伤害、武器、输入或存档的混用。状态机和其他授权调用者可显式请求指定表情，显示保持结束后恢复背景随机。此版不持久化表情；面饰换装仍由原框架负责。

## 网格美术约束

2026-10-01用户追加要求：六种情绪只保留眼部/爱心，不设置嘴巴或嘴部网格。保持左右眼各自完整的形状，加宽加厚轮廓和发光颗粒，保留方块间隙；难过的泪光属于眼部。问号、感叹号保留符号本身的点。生气仍使用红色。8种稳定ID、独立系统接口、随机与状态调用不变，局部眨眼/闪烁继续沿用。表情材质默认自发光强度1.25（原5的25%），降低颗粒周围光晕；8种材质使用同一强度，仍保留各自颜色。闪烁曲线继续按相对亮度采样，在新强度下恢复；网格形状不变。每次视觉修订保留旧双母版，新版本覆盖稳定运行路径，逐项更新角色账本规格及中转哈希。

## 生命周期与拒绝

系统可单独实例化，无Autoload依赖。Actor卸载时销毁它及信号订阅。面具绑定时立即读取快照；换装隐藏期间保留系统状态，重新可见时显示最新表情。资源加载失败保持当前有效网格并返回false，未知ID不替换显示。每实例独立材质；符号表情不参与闭眼压缩，保持符号可读，仍可闪烁。默认平静及原眨眼/闪烁保留。

## 接入与验收

Player3D创建独立系统并绑定面具显示；完成既有状态机初始化后连接表现事件。独立逻辑专项验证8种资源、红色生气、符号、非法命令原子拒绝、随机不重复/全部可达、保持/恢复、实例隔离、状态机实际调用且玩法/动作/换装不变。Forward+逐种真实渲染并归档总览。源与动画双母版保持原骨架签名和原角色几何；各表情独立稳定Prefab/GLB，账本主表、组件、3D分页及中转同步。
