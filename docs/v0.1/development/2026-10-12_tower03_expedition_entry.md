# 塔3检修平台与远征入口

日期：2026-10-12。FeatureID：WORLD-ENTRY / ASSET-PIPELINE。依据：用户三张实际游戏截图，要求修方片闪面、补设施阻挡和可走楼梯、门前增加远征01入口、按入口来源返航，并更新设计说明。

主设计：[跨塔天台 WORLD-ENTRY r5](../design/rooftop_cross_tower_route.md)、[远征01](../design/远征关卡01设计.md)、[全息城市共享交接](../design/远征全息城市交互设计.md)。存档合同同步到[09](../09_技术施工_存档结算与复活.md)。基于现有工作区施工，保留同时进行的剧情、时钟、鸟群和基地设施修改，未提交Git。

## 实际改变

屋面结构顶与112块地砖主面共面，正式route只覆写可视方片局部Y+0.04m；三组周边护栏可视底座Y+0.08m。承重面、塔/桥摆位与GLB/Blend不变。跨塔route运行包装v003。

左检修平台运行组件v002增加18个BoxShape3D：平台承重薄板、双连续坡面、梯侧栏杆、平台前栏杆三段、左右栏杆与六根立柱。双梯通道净宽1.78m，坡面高度1.42m、水平长2.22m。复用原机组设备阻挡，不把整块凹形设施包成大盒。实际玩家胶囊双向行走通过。

机房门入口位于(-22,0.05,-168.8)，靠近3.2m内可E/手柄交互或点击门。确认框“是否进入远征关卡01？”和“是/否”；取消恢复输入且不写盘。确认选定expedition_01，再走与基地相同的ExpeditionDepartureService和ExpeditionLoadingScreen。读取页、退出及死亡确认文案显示相应入口。

TowerDescent3D拥有行动来源，BaseManager负责持久化。来源expedition_entry_source为base_99f/tower03_rooftop，旧档或非法值默认为基地。基地选关显式覆盖来源；行动快照续局保留来源。结束后的expedition_return_source是非战局标记，不能续入已结束关卡。塔3门前固定安全点(-22,0.08,-167.3)，实际落地约Y=0.0133；延迟恢复携带物不得覆盖该落点。死亡来源随保险/损失/幂等记录原子写入，退出保存失败恢复携带物及提供者。成功撤离所有权、保险、弃局损失沿用原流程。

远征加载检查暴露room_03布局base_layout仍指迁移前旧路径，修正制作源中的这一字段为data/layouts/expedition/v009/component_instances.json，再投影到运行数据。没有重生成正式房间或改变布局。

场景账本只改两个现有AssetID及14个单元格：版本、SHA、日期、说明与碰撞声明。使用artifact-tool导入/编辑/预览/导出，再合并目标XML单元格；原样式、公式、合并、验证范围与其他ZIP部分保真。只补两行及受影响专表/列指纹，未接受其他哈希漂移。

## 本次验证

所有Godot进程启动前APPDATA隔离到工程外；正式用户档未被验收调用。

| 验证 | 退出码与结果 |
|---|---|
| verify_tower03_expedition_entry | 0，TOWER03_EXPEDITION_ENTRY_OK；双梯上/下、栏杆、承重、交互范围/取消、保存拒绝、基地来源重置、出发回滚、卸载、续局、死亡标记、成功携带返回、退出意图、旧档默认 |
| verify_expedition_departure_carry | 0，原基地出发携带回归通过 |
| verify_expedition_extraction_carry_return | 0，原基地撤离所有权回归通过 |
| 实际Forward+窗口 | 0，RTX4060Ti；鼠标点击门，确认/取消按钮键盘派发，读取远征01，死亡确认、成功撤离、主动退出三种真实场景返回；TOWER03_WINDOW_CLICK_ALL_RETURNS_OK |
| 实际Forward+资产画面 | 0；前/后截图复核方片共面修复、双梯及门前，GLB/源不动 |
| 场景账本结构 | 0，866资产 |
| 九域无损基线 | 0，1062资产；目标单元格以外保真 |
| 运行设计数据投影 | 0，39份，issues=[] |

日志无非预期脚本ERROR；Godot退出时仍有ObjectDB实例泄漏WARNING，未作为通过项掩盖。保存故障注入是预期拒绝，不执行出发。最初窗口探针使用InputEventAction不能派发子Window按钮，改为对子Window派发Enter事件后完成真实GUI验证；不改产品输入规则。未跑完整游戏套件、手柄硬件或性能压力测试。

场景full门禁退出1，剩余464项既有SHA漂移；改前账本对照为466项SHA，另有备份单文件被识别为legacy而产生的三项专表声明报告。目标两项Prefab当前SHA已精确验证；无批量更新。运行命名门禁退出1，旧角色production版本路径、旧椅子组件及带版本引用债务保留，本次新增路径均稳定无版本。

文档门禁退出1：既有Boss002开发记录缺链、六项旧验收未登记，以及默认python3缺openpyxl。使用bundled Python复核子检查后，第三项定位为既有UI域预期16/实际18；没有新增本次入口问题。独立功能追溯门禁退出0，37项一致。verify_game_entry_flow和verify_run_settlement_transaction均退出0，基础入口与原子结算未回归。新专项已加入core套件清单。不据专项通过宣称远征整关旧墙体/走廊缺口已修复。

最终场景账本与改前冻结副本逐格差异恰为14格，样式、公式、表范围保持，两个目标Prefab SHA与当前文件一致；九域基线最终再次退出0。

过程证据在工程外ShellStorm2-work/sessions/2026-10-12_tower03_entry（verify_complete.log、departure_regression.log、extract_regression.log、ui_complete.log、before.png、after.png、confirmation.png和三种return.png）。改前备份在ShellStorm2-backup/2026-10-12_tower03_entry/before_edits。
