# 标准弹附魔染色与粗粒子包裹短尾

- FeatureID：WEAPON-COMBAT / FATE-RULES / VFX-POOL；工程版本0.1.0。
- 来源：2026-11-17用户要求标准弹附魔颜色一致（火橙红）、粒子包裹弹身而不是仅拖在后方、颗粒放大且保留拖尾，并同步设计与账本。
- 状态：本轮附魔表现专项validated；不提升模块partial，不代签整局/压力性能/Android。
- 主设计：[战斗奖励与物品流转设计](../design/战斗奖励与物品流转设计.md)；工程契约：[14.6 §3.5a](../14.6_特效系统与制作规范.md#35a-弹体附魔持续粒子附件2026-11-17修订)。

## 改动与边界

1. `ProjectileEnchantmentVisuals3D`统一按实际behavior解析去重属性。仅标准弹`mod_bullet_standard`的壳/芯/灯随附魔染色，火RGB=(1,0.22,0.06)；多属性RGB等权平均，芯色lightened(0.22)。特殊弹保主体色、力量保滚石例外；不写回bullet_color，不改伤害/命中/碰撞/弹道/存档。
2. 七独立附件Prefab升v002，稳定路径和贴图不变；每件仍单GPU、单draw pass、256² RGBA、无碰撞灯影。中心box发射体覆盖标准弹芯壳，Quad宽0.28—0.38m/高0.34—0.46m，scale=1.1—1.25且尺寸曲线恒1，出生即足尺寸，不缩成碎点。
3. 局部+Z低速漂移0.12—0.42m/s，寿命0.16—0.38s、alpha渐隐，形成短尾；最大漂移基值0.064—0.1176m，不等于总包络或世界尾长。local_coords=true，旧几何尾迹总开关仍false；本轮不是持久世界空间历史轨迹。
4. 总数量仍`N*floor(24/N)`，N为属性数；每种`max(1,floor(24/N))`。不因放大颗粒增加粒子数。每实例process材质独立，box.z随轴向变化，池化回收清色、清GPU、清生长和box/AABB。
5. 源生成器与七Prefab可重现同步；正式实现4脚本、七Prefab、源生成器与专项测试。设计同步主设计、04、14.6、MODULE_INDEX相关段；特效账本主表r27、r67—73与3D页同AssetID的版本/规格/哈希/状态同步；标准弹Prefab未改，保持v001。

## 验证证据

工程外证据根：`ShellStorm2-work/verification/weapon_hologram/20261117_233008_ea46d2/`。

| 验证 | 结果 | 退出码 | 非预期脚本错误 |
|---|---|---:|---:|
| 隔离工程导入 | 通过，详见result.json import | 0 | 0 |
| Forward+/Vulkan 1280×720 | 3885检查、0失败、7截图 | 0 | 0 |
| Forward+/Vulkan 1920×1080 | 3885检查、0失败、7截图 | 0 | 0 |
| 八弹种profile/路由/枪族尺寸/生长/面数回归 | BULLET_VFX_PROFILES_OK，samples=70 | 0 | 0 |
| 准星弹道/屏幕投影/碰撞随视觉回归 | BULLET_AIM_ALIGNMENT_OK，samples=20 | 0 | 0 |

回归根为`ShellStorm2-work/verification/weapon_hologram/20261117_234250_30367b/`。该通用runner仅识别全息/附魔JSON marker，因此两个旧入口虽然退出0且打印各自OK，汇总仍passed=false、runner退出1；本记录保留该报告协议不兼容，不能写成runner全绿。旧入口结果依各自console/engine日志、退出码和OK marker单独判定。

新增断言覆盖标准七色与芯色、原bullet_color不变、特殊弹保色/滚石、2—7属性平均色与数量、无附魔复借恢复、材质互不污染、box真实包围弹芯壳、粗粒径、alpha渐隐和低速尾、轴向复借、非池化先configure后入树。

已逐图查看1080p七单属性、混合、移动帧：火包裹橙红、冰为成片冰晶、毒为绿色云团，机制粒子为大图形，尾为局部短拖曳。展示配置倍率×2且保留原生脉动；不是关卡默认镜头比例，不将展示棚拍冒充整局观感。多元素堆叠会遮挡一部分弹芯，满屏可读性留待整局压力审查。`render_reviewed=false`是测试自动结果字段；人工/代理图片复核记录在此，不篡改原始报告。

## 门禁与遗留

最终结果见工程外会话`ShellStorm2-work/sessions/2026-11-17_projectile_enchant_wrap/final_gates.json`：文档exit1（14条断链及1项无关fat_zombie21_gait未登记）、全库结构exit1（17项）、full-vfx exit1（1个非本轮状态值及8项非本轮哈希）、split exit1（24项，均不含本轮8项）、运行资产命名exit0，限定源码diff --check exit0。目标8项的validated状态、实际SHA、行指纹、R/S公式与3D页摘要逐项通过，见target_audit.json；full-vfx报错的9行与document_ledger_baseline备份逐格相同。最终回填前后非目标资产指纹变化0；较早文档备份至最终回填前存在并发L-CORRIDOR指纹变化，保留他人更新，没有回滚或重新接纳无关哈希。

交付收尾限制：MODULE_INDEX已有本轮规则链接但仍写authored待验，development/README与CHANGELOG的本轮入口未能追加。对这些共享索引的写入返回UNKNOWN/OSError Errno22，文件并非只读；未用替换/重命名规避该失败。主设计、04与14.6正文以及账本已更新为本轮validated，最终结果以本记录与账本为准；共享索引状态待解除写入问题后补齐。全库红项保留，不为全绿接受无关哈希漂移。

- 预期故障注入：本轮未执行破坏式反向注入；拒绝/空属性/未知键/复借负向用例包含在专项3885检查内。
- 未执行：整关人工游玩、武器命运全组合穷举、同屏弹幕压力、GPU耗时采样、Android。
- 用户正式存档：Autoload前隔离APPDATA、LOCALAPPDATA及custom_user_dir，未读写正式档。
- 修改前备份位于工程同级`ShellStorm2-backup/2026-11-17_projectile_enchant_wrap/before_edits/`，含implementation_baseline_20261117、document_ledger_baseline及final_validation；专项测试另有同级带时间戳备份。
