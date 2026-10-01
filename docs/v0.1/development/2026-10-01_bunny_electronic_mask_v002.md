# Bunny01 电子面具 v002：大颗粒眼睛与局部动画

FeatureID：ENTRY-AVATAR、ASSET-PIPELINE；工程版本0.1.0；日期2026-10-01。用户要求按红框放大眼睛和颗粒，制作眨眼与间歇闪烁，并按角色组件规则录入账本。

同一 AssetID `CHR-PLY-BUNNY01-FACE-ELECTRONIC-MASK` 升级v002，归类 `version_increment`。每眼5×14颗方块，共140颗；单颗10.8mm，中心间距14mm，眼睛约66.8×192.8mm。相对v001宽度约2.3倍、高度约1.8倍、颗粒约1.9倍。原黑色面罩曲面及头部挂点保留，原角色11个网格、UV、材质、权重和共享骨架不变，v001制作源保留。

## 双母版与动画消费契约

[模型母版](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/source/chr_bunny01_electronic_mask_model_v002.blend)与[动作母版](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/source/chr_bunny01_electronic_mask_animation_v002.blend)共享 `SKEL-BUNNY01-004`，静止签名 `203cbcaf9a7d4eaa55baacc6ea4d2093e157ad853ecab5bf08abb8a38f41edb8`。保留原角色动作依赖，不新增玩法状态。

| 剪辑 | 时长 | 循环 | 内容 |
| --- | --- | --- | --- |
| mask_idle | 12秒 | 是 | 2.8/7.2秒开始眨眼；5.1/10.1秒短闪；首尾恢复张眼/全亮 |
| mask_blink | 0.26秒 | 否 | 0.09秒闭眼，保持到0.16秒，0.26秒重新张眼 |
| mask_flicker | 0.42秒 | 否 | 亮度1→0.18→1→0.35→1→0.55→1 |

动作母版包含三个可编辑Action与预览驱动。GLB含壳体/眼睛两个网格，以及沿原曲面闭合的Blink形态键；没有重复骨架或碰撞。GLTF不传递发光强度动画，采用Blender线性曲线→[曲线中转JSON](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/components/chr_bunny01_electronic_mask_expression_curves.json)→[Godot AnimationLibrary](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/runtime/chr_bunny01_electronic_mask_animations.tres)。局部适配器只赋值形态键和独立材质亮度；不生成角色姿势或驱动碰撞/武器。稳定Prefab根缩放1，自动播放12秒循环，默认装备、替换和存档沿用原glasses框架。

## 验收与账本

- 独立重开模型与动作源，原11网格与原骨架逐项核对通过，1448壳体顶点仍来自原头部；三个动作源曲线与中转数据吻合，动作母版实际眨眼/闪烁预览验证。
- `verify_electronic_mask_flow`：无头及Forward+真实渲染均退出0；验证自动播放、闭眼/重新张眼、亮度降低/恢复、循环首尾、每实例独立材质、换装/读档、挂点跟随、碰撞和武器不变。真实截图眼睛蓝光40791像素，闭眼高度显著缩小，闪烁帧蓝光能量降低。
- 五项回归退出0：`verify_player3d_avatar_bounds`、`verify_player3d_animation_flow`、`verify_wardrobe_preview_fill_flow`、`verify_avatar_return_persistence_flow`、`verify_character_authoring_bundle`。
- 主资产行22升级v002；《角色组件》44、《3D-角色》9更新；《动画与状态》50–52明确登记为面饰局部剪辑而非玩家状态；《角色中转记录》18–24录入七项源/导出/包装/适配器哈希。主行与锁定专表分事务更新，各保留其余987项资产指纹，结构及无损分账本门禁通过。
- 退出码、预期故障、非预期错误和未执行项见[机器报告](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/verification_report.json)。最终专项/回归没有预期故障或非预期脚本错误；既有色盘UID回退警告保留。

## 预览与范围

[实际正面](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_front.png)、[大眼近景](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_face_closeup.png)、[闭眼](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_blink_closed.png)、[闪烁暗帧](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_flicker_dim.png)、[12秒真实渲染动画](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/godot_expression.gif)。截图是专项舞台灯光，Blender旧front/three_quarter/face_closeup预览为历史v001。

未运行整游戏full套件及移动设备性能检查；没有提交或推送。全局既有女仆头账本哈希、运行资产命名和三项未注册场景债务沿用[前版记录](2026-10-01_bunny_electronic_mask.md)，详细当前门禁结果见机器报告，未扩大接受债务。
