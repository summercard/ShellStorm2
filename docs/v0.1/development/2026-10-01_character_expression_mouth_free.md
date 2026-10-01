# 电子面具无嘴部表情深化

FeatureID：ENTRY-AVATAR、ASSET-PIPELINE；ModuleID：CHARACTER-EXPRESSION；工程0.1.0；日期2026-10-01；设计修订r2。来源：用户要求“把嘴巴区域都去掉，然后其它的元素饱满一些”。[目标契约](../design/character_expression_system.md)。

## 实现与数据

父面具同AssetID升级v004，八个既有子资产升级v002；稳定GLB/Prefab路径、表情ID和独立系统接口不变。移除开心/难过/生气/惊讶/爱心的嘴部，六种情绪的中间嘴部区域无网格；难过保留眼部泪光。加宽加厚眼睛、爱心、问号与感叹号，方块边长从10.8mm增至11.8mm、间距仍14mm。生气仍红色，符号保留自身的点且不闭眼压缩。

| ID | 平静 | 开心 | 难过 | 生气 | 惊讶 | 爱心 | 疑问 | 警示 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| expression_id | neutral | happy | sad | angry | surprised | love | question | alert |
| 颗粒数 | 180 | 116 | 102 | 112 | 144 | 148 | 112 | 96 |

新模型/动作双母版保存到父组件source/下的v004命名文件，旧v001–v003源均保留；v003图案定义另冻结，避免旧构建脚本引用新版图案。集合继续使用角色组件/眼镜/电子面具/表情分类。所有情绪的Blink压缩完整眼部网格，无嘴部豁免；随机选择与状态机调用由原独立系统负责，没有新增玩法状态或改变存档。

## 验收与登记

- Blender独立重开通过：原11网格的几何/UV/材质/变换/权重不变，1448壳体顶点仍来自原头前侧+9mm，骨架静止签名不变；8种实际方块中心与无嘴部计划一致；六种情绪全部Blink形态高度压缩至原来的6%，完整眼部闭合；双母版曲线及文件哈希通过。
- `verify_character_expression_flow`：无头696项、Forward+706项，退出0；六种情绪实际GLB顶点均没有中心嘴部几何，8种全部随机可达且无连续重复，真实状态机调用、拒绝、保持、实例隔离和符号不闭合通过。8种Forward+实拍面部互不相同，红色生气专项通过。[总览](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/previews/expressions_overview.png)已亲眼检查嘴部移除及图案饱满效果。
- `verify_electronic_mask_flow`：无头73项、Forward+76项，退出0；放大的默认眼睛实际闭合/重新张开、间歇闪烁、换装、实际存档读回、碰撞/武器不变通过。
- 5项角色回归退出0：`verify_player3d_avatar_bounds`、`verify_player3d_animation_flow`、`verify_wardrobe_preview_fill_flow`、`verify_avatar_return_persistence_flow`、`verify_character_authoring_bundle`。最终日志无非预期脚本/引擎错误，原公共色盘UID回退警告保留。
- 角色账本：父主行22升级v004、子主行23–30升级v002，组件45–52、3D分页10–17、表达记录53–60更新原行；中转追加52–78，域日志v0.1.8。主表和摘要锁定专表分事务写入并回读；保留其他987个资产指纹。结构/拆分门禁通过，九个资产version_increment守卫通过。
- 源、导出、账本与验证机器事实见[报告](../../../assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/face/electronic_mask/verification_report.json)。预期失败：无。最终非预期错误：无。未执行：整游戏full、移动端性能。未提交或推送。

验收脚本首次加入无嘴部检查时误把同一检查插入渲染循环，产生未定义局部变量；已移除错误插入并重跑两模式。专表更新初次发现alert也用于既有玩家状态，事务在写盘前拒绝；改用类别+ID定位，仅更新面饰表达原行后通过。全局既有女仆头哈希、运行资产版本命名债和三项场景注册问题单独记录，不批量接受其它哈希。

全局门禁本次实际结果：文档检查退出1，仅三项既有场景未注册（verify_base99_swivel_chairs、verify_expedition01_spawn_ramp、verify_pushable_base_chairs）；全角色资产检查退出1，仅女仆头第21行SHA不符，已逐格确认改前/改后相同；运行命名检查退出1为既有版本路径债。本次九个面具/表达资产无新增门禁问题。
