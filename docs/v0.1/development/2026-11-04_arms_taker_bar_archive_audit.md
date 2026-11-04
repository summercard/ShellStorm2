# 收租人血条细化与怪物档案室审计

FeatureID：ELITE-ROSTER / UI-HUD / BASE-FACILITY / ASSET-PIPELINE。工程 0.1.0；日期 2026-11-04。来源为用户要求血条变细、首遇后在怪物档案室显示等级和物品，以及后续“已有设施，先检查功能和文档”的指示。本次交付为血条调整和现有档案链路审计，档案接线判定为未闭环。

## 血条调整

收租人 `health_bar_profile.size` 从 `2.05×0.23m` 改为 `2.05×0.12m`，约收细 48%。Enemy3D 从当前内容库读取精英条尺寸，恢复旧敌人数据时不会沿用嵌入其中的 0.23m 高度。名称保留至少 0.24m 的中心偏移，避免细化后文字下移、被血条遮住。名称、血量和物品规则仍由原有所有者维护。

使用真实 Windows / Vulkan Forward+ / NVIDIA GeForce RTX 4060 Ti、1280×720 运行。独立 APPDATA 在 Autoload 前设置。旧尺寸配置实例实测结果 `(2.05, 0.12)`，血条为 top_level，未随1.6倍模型再次放大。最终截图为工程外 `ShellStorm2-work/sessions/2026-11-04_arms_taker_bar_archive_audit/bar_thin.png`。

## 档案链路实测

| 环节 | 结果 | 当前事实 |
|---|---|---|
| 首次预约 | 已具备 | reserve 后 encounter_count 仍为0，不应算已经见到 |
| 首次生成确认 | 已具备 | confirm_reservation 后 encounter_count 为1，等级为1，保存成功 |
| 夺取资产保存 | 已具备 | 测试物品“备弹”与自定义字段、25货币均写入收租人自己的档案；磁盘重载后保留 |
| 页面列表装配 | 缺陷 | 脚本查找 `Panel/VBox/Content`；实际节点为 `Panel/VBox/ScrollContainer/Content`。content 为 null，构建函数提前返回；真实页面只剩标题和关闭按钮 |
| 已遭遇过滤 | 缺陷 | 在探针实例上临时校正 content 引用后，列表直接读取 get_all_elites，显示全部12只；未遭遇角色也提前显示为 Lv.1 |
| 持有物品和货币显示 | 缺陷 | 行构建只读取 stolen_modules。新保存的 stolen_items、stolen_currency 没有接入界面；临时校正列表路径后仍不显示备弹和25货币 |
| 数据刷新 | 缺陷 | 首次确认后没有 roster_changed 通知（实测0次）；菜单本身也未订阅档案变化，只在 ready 构建 |
| 现有设施绑定 | 存在差异 | 正式 TowerDescent3D 运行实例有8个 BaseFacility3D。原49号工作台实体为 weapon_forge，打开 WorkbenchMenu；没有绑定 monster_archive 的实例。catalog 中 monster_archive 和 MonsterArchiveMenu 场景仍保留 |

探针只在临时菜单实例上修改 content 引用以定位后续问题，正式 MonsterArchiveMenu 脚本和场景未修改。现有设施的模型、位置与功能绑定保持当前工作区值。当前 get_all_elites 属于完整名册查询，应继续供系统使用；目标需另提供“已遭遇”查询，不能为了界面过滤破坏系统的12名册。

## 文档核对

- [精英技术施工 §5.2–5.4](../06_技术施工_怪物精英与Boss.md)已有“定义/存档分离”和“当前等级、夺取来源/转译结果”要求。本轮补充首次确认后公开、已遭遇查询及物品/货币展示的目标契约，并标记当前接线未完成。
- [UI-39](../design/UI与UX全局设计及全界面清单.md)目标要求展示已遭遇角色；当前页面没有落实已遭遇过滤。原文普通怪/Boss分类、弱点/掉落说明仍是目标，本轮没有宣称已实现。
- [UI-21](../design/UI与UX全局设计及全界面清单.md)记录了2026-10-19原怪物档案台位点改成武器改造台；运行时绑定与此一致。设施施工页原有 `monster_archive→49号模型` 的当前映射陈旧，本轮同步其现行功能。
- [收租人契约 r6](../design/精英02收租人状态与动作契约.md)分别登记已实现的细血条与待接通的档案显示目标。

建议后续按“列表节点绑定→已遭遇查询→物品/货币展示→提交成功后的刷新→现有设施动作绑定核对”收口，沿用现有设施系统和 UI-SCREEN-MONSTER-ARCHIVE，不建立另一套档案存档。

## 验收与范围

正式场景探针和最终血条渲染退出码均为0，日志门禁均为0；无预期故障注入，无非预期脚本错误。初次尝试用 `--script` 启动外部 SceneTree 因 Autoload 标识符编译顺序失败；首次简化血条探针也因 ready 期间向忙碌父节点添加对象失败，产生退出资源错误。已分别改为正常 TSCN 入口和延后执行，最终日志为 probe_scene.log、bar_final.log，均单独通过日志门禁；失败试跑不计为验收通过。现存资源 UID 路径回退警告仍在。

没有执行档案功能修复后的专项或键鼠/手柄全输入矩阵，档案功能不标记验收通过。敌人账本对血条显示规格登记9格变更，采用 artifact-tool 候选编辑和逐格保真合并，保留其余资产和样式。最终文档及资产门禁结果见本次工程外日志。

门禁补录：敌人域 full 检查退出0（50资产），分账无损检查退出0（1434资产），媒体域检查退出0（213资产）。UI域 full 检查退出1，报告本轮范围外的 UI-SCREEN-HUD、UI-SCREEN-VAULT、UI-SCREEN-PAUSE-3D、UI-PANEL-FATE-SOURCE 四项现存SHA漂移；本次没有回填这些哈希。全局文档门禁退出1，仍为15条既有断链和4个既有未登记用例；本轮新增文档引用可解析。

默认基地补查：GameDesignConfig.BASE_SCENE_3D 指向 BaseWorld3D.tscn；独立运行探针检测到7个设施，ID为 mission_operations, weapon_workshop, vault, fate_collection, base_vending, base_recovery, avatar_wardrobe，同样没有 monster_archive 绑定。base_facilities.log 的引擎退出码/日志门禁为0/0。
