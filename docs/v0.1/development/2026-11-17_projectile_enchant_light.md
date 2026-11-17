# 附魔灯光独立对象与特效直挂

- FeatureID：WEAPON-COMBAT / FATE-RULES / VFX-POOL；工程0.1.0。
- 来源：2026-11-17用户要求不同附魔灯色同步，灯做成不同颜色对象替换，直接绑到特效上。
- 本轮在上一轮包裹粒子v002基础上增量修改，不改变粒子数、颜色、包裹/短尾参数，不改伤害/碰撞/运动/存档。
- 设计主源：[战斗奖励与物品流转设计](../design/战斗奖励与物品流转设计.md)；工程契约：[14.6](../14.6_特效系统与制作规范.md) §3.5a独立灯增量。

## 实现

1. 新增七份独立灯PackedScene，稳定路径为`assets/art/vfx/combat_3d/vfx_projectile_enchant_light_{key}_root_top3d.tscn`，对应`VFX-PROJECTILE-ENCHANT-LIGHT-{KEY}-3D`、v001。根Node3D、子OmniLight3D；轻量`ProjectileEnchantLight3D`只管启停/复位/快照。
2. 单属性选择对应固定色灯对象；灯直接作为`ProjectileEnchantments/Enchant_{key}/EnchantLight_{key}`子节点，跟随特效移动旋转。对象按属性缓存复用，运行帧不重建。
3. 多属性仅一盏active：首属性仅决定对象和挂载宿主，最终颜色为全部去重属性RGB平均。无效/重复属性不增加灯数或权重。
4. 固定energy1.15、world range1.75m、无阴影、照明及阴影mask3、55m开始15m距离淡出。灯禁用缩放继承，不因父粒子scale/grow/axial扩大照明半径。
5. 有附魔时所有模块的主体旧灯关闭，标准与特殊弹/滚石都用附魔灯；主体染色仍仅标准弹。无附魔恢复主体原灯行为，无附魔滚石不新增灯。回收时新灯隐藏、energy0，复借只开本发对象。
6. `VfxBulletBody3D`、通用`VfxBulletVisual3D`与`VfxBulletElectric3D`均遵守`suppress_body_light`上下文，避免activate或逐帧tick重新点亮旧灯。

## 资产与文档

- 特效主表新增r74—80，3D-特效新增r268—274；七件独立灯，粒子附件r67—73仅补挂灯边界备注，仍v002。
- 新增后主表S覆盖80、总览与查重/筛选/CF范围扩大；baseline仅追加七灯、更新批准粒子备注指纹及3D页摘要。其他1456既有资产记录保持不变。
- 独立复核发现主表3条DV枚举formula1被写空，以及3D新增21格未扩围；已从修改前备份恢复枚举并扩展I/J/O到274，回读确认，见工程外`dv_repair.json`。不以现有门禁未报错替代此检查。
- 源生成器：`art_source/vfx/projectile_enchant/generate_projectile_enchant_lights.py`，从BODY_PALETTE生成七灯，不修改粒子贴图。
- 备份：工程同级`ShellStorm2-backup/2026-11-17_projectile_enchant_light/before_edits/`。

## 验证与故障记录

专项延续`verify_projectile_enchant_visuals`，新增七灯Prefab、真实灯快照交叉、八模块主体灯抑制/恢复、多属性唯一灯、缓存切换/回收无残留、固定世界basis与移动旋转、入树前配置；新增暗场地板/背板投光截图，不用emission冒充表面投光。

第一轮隔离工程`verification/weapon_hologram/20261118_004420_367b03`实际失败：
- 导入/运行被并行剧情修改的`NarrativeAdapter3D.gd:736—739`四处Variant推断警告（作错误）阻断；只补显式`: Variant`，不改逻辑，改前文件另备份。
- 新截图场景使用不存在的`REFLECTED_SOURCE_DISABLED`枚举；曾尝试`REFLECTED_SOURCE_AMBIENT`，见下方第二轮失败；最终删除该非必要赋值并保低ambient、关方向光/GI/glow。
- 第一轮720p超时退出1，1080p进入相同失败后主动停止本轮拥有的runner；故障日志保留，不算通过。

第二轮保留失败证据：REFLECTED_SOURCE_AMBIENT同样不是当前引擎枚举，两个分辨率各超时退出1；随后移除不必要的reflected_light_source赋值，保持低ambient/关GI/无天空。一次skip-import请求因副本原始导入记录失败而被runner拒绝（退出2，未运行场景），没有绕过校验；最终重新完整导入。

最终隔离报告：`ShellStorm2-work/verification/weapon_hologram/20261118_011159_2ba6d9/result.json`，导入exit0；Forward+/Vulkan 1280×720与1920×1080各14576检查、0失败、0非预期脚本错误、退出0；每档8张真实截图，共16张。已查看1080p暗场投光：七种彩色灯确实照亮受光地板/背板，多属性为单盏平均色，没有仅靠弹身自发光代替。截图配置倍率×2，固定灯世界范围不扩大。原始render_reviewed=false字段不篡改，图片审阅结论写在本记录。七灯由authored收口为validated仅限本轮专项。

门禁证据：工程外`ShellStorm2-work/sessions/2026-11-17_projectile_enchant_light/`。当前结构17/full-vfx9/split24/文档15项旧错误集合相同、目标新增错误0，运行命名exit0；灯资产SHA/指纹/公式/页摘要逐项匹配。旧错误没有通过批量重基线消除。

共享入口遗留：development/README本轮追加入口仍返回UNKNOWN写入失败，未强制替换文件；MODULE_INDEX等共享索引此前的写入限制保留，最终状态以本独立记录、14.6和账本为准。

未执行：满屏压力/GPU耗时、Android、整局人工验收、所有构筑组合；正式user目录在Autoload前隔离。灯范围1.75m/energy1.15是本轮固定表现预算，不代表满屏预算已验收。
