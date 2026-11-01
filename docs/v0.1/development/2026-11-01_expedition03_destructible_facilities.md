# 远征03三房易碎设施布置与验收

日期：2026-11-01；FeatureID：WORLD-PLAN、ASSET-PIPELINE；工程版本：0.1.0。

依据：[远征03§7.5.4](../design/远征关卡03设计.md)、[可交互物件设计r6](../design/场景可交互低模物件设计.md)。用户要求套件中的易碎组件作为设施增加布置，并补充墙边、非通道角落多，中部少。范围沿用前轮大中小三间正式房间；不改其他15份资源、游戏代码或随机生成规则。用户后续授权追加墙边书架、柜子及配套陈列。

## 布置与资源

通过Godot实例化原正式TSCN，在ArtComponents下新增AuthoredDestructibles，原AuthoredSalon、结构与灯光保留。组件根引用既有稳定PackedScene，单位缩放、底面位于本房地砖顶面0.10m，不展开Prefab内部视觉、受击体或接触Area。节点名Facility_序号_类型固定，房间沿现有能力认领为authored_稳定ID。

| 房间 | 新增 | 墙边/角落 | 中部 | 罐/书/瓶/椅/箱 |
|---|---|---|---|---|
| 入口15×15m | 24 | 22 | 2 | 5 / 5 / 5 / 5 / 4 |
| 事件25×25m | 48 | 44 | 4 | 10 / 10 / 10 / 9 / 9 |
| 大堂45×40m | 96 | 88 | 8 | 20 / 19 / 19 / 19 / 19 |

合计168件，91.7%距最近房边不超过3.2m；保留中轴和横向主通道。墙边取全部合法门槽之间及首尾无门墙段，角落分组陈列。全部体积避让门前净空、现有家具，距墙边界至少0.25m，组件中心间距不少于1.12m。没有叠高，避免既有碎片局部落地规则使高台陈设碎后悬空。

复用共享易碎陈设五种既有v002运行资源：罐子、书本堆、花瓶、椅子、木箱。源/优化LFS OID、独立优化记录与五份GLB哈希匹配；源文件未实际展开重开，未宣称重新导出。没有新增模型、AssetID、Prefab副本、受击代理或碰撞规则。layer4受击、PlayerContact破碎与房间状态账沿用组件；不新增玩家阻挡、伤害、掉落或刷新规则。

三份文件保持当前运行路径，未创建种子房间；现有陈设、灯光和结构逐节点对照本轮备份。布局账本只同步三行数量/SHA/备注；易碎受击体不混算家具阻挡碰撞。

## 追加墙边丰富度

墙边增加40组固定家具：小房8组（2衣柜/4书架/2窄桌）、中房12组（3衣柜/6书架/3窄桌）、大堂20组（3衣柜/12书架/5窄桌），另配50件黄铜灯饰/台灯/画框，共90个既有组件实例。柜架带显式玩家阻挡碰撞，图案与模型不改；灯饰仅视觉，无新交互或Omni灯。原有作者灯光均保留。三份源组件/陈设/阻挡碰撞为78/57/16、157/112/36、324/218/66，易碎受击体单独计数；18份正式资源现为585件陈设、243份家具阻挡碰撞，168件易碎设施包含在陈设计数内。

墙边新增内容在WallCollections组；易碎件重新避让柜架后数量、墙边比例不变。结构和原AuthoredSalon与追加墙边工作前备份逐节点对照一致。期间事件房GalleryCeilingWarm由外部编辑改为energy=11.901/color=(1,0.3882,0.3608)，差异来源可定位为本轮基线外的灯光编辑；本轮保留现值、不回写旧参数，也不把该灯改动算作本次制作。

## 验收

运行使用Godot 4.7.2原生OpenGL Compatibility窗口；headless只用于结构/碰撞/状态。最终命令分别记录退出码，未把早期失败累计成通过。

| 验证 | 退出码 | 结果 |
|---|---|---|
| 明确用户目录路径核查 | 0 / 0 | 两个进程实际OS.get_user_data_dir与BaseManager.save_path分别指向独立headless/native自定义目录，见path_headless/path_native日志 |
| 三房结构/净空/受击/持久化专项 | 0 | 15,761项检查，0失败；2种子/7实例、480次真实Projectile3D命中均触发破碎；每件5碎片，受击层关闭/本体隐藏/幂等/落定/房间账/流送/JSON序列化后新房间回灌均通过 |
| 组件与家具包络专项 | 0 | 新增组件均稳定Prefab/单位缩放/在房内；家具互穿0、全部合法门位净空冲突0；正式源不含已碎状态 |
| 原生实关卡破碎画面 | 0 | 3间房玩家现有武器各击碎1件、真实玩家接触各破碎1件；每间局部连射破碎陈列组，保留完整/飞散/落定/书架/柜体截图；最终0脚本错误及ERROR |
| probe_authored_breakable_clutter | 0 | AUTHORED_CLUTTER_PROBE OK，真实认领与目录/撒点避让检查 |
| probe_expedition03_save_roundtrip | 0 | STATE_PROBE OK。旧C4误把常驻作者件当随机detail件，已按现有生命周期分别要求作者件仍是同一实例、随机件必须新实例；未改游戏逻辑或放宽破碎持久化判据。额外新实例恢复由480件专项覆盖 |
| 固定陈设24种子回归 | 0 | checks=7136 failures=0 files=58 used=18 door_samples=3888；最终脚本错误/ERROR为0 |

账本结构/全域拆分一致性检查退出0（场景1013项，全域1417项）；仅布局页三行/总计、域日志v0.1.57和布局页摘要变更，6个既有非日志分页值/公式未变，其余15房SHA匹配。关卡解耦检查退出0；diff --check退出0。文档检查退出1，44项既有问题（43断链及1组3个未登记验证）；运行命名检查退出1，为既有bunny v022/v023/v024三处版本目录，不是本轮新增。未执行全量core/aggregate、全量资产历史哈希扫描、完整通关/结算、所有交互及目标设备性能预算。大堂单房96件全部破碎产生480片的功能状态已测，不等于移动设备性能达标。

实关卡截图（保持关卡环境/雾/灯，仅用观察相机取景）：

| 房间 | 墙边柜体 | 书架陈列 | 易碎设施完整→破碎 |
|---|---|---|---|
| 小 | [柜体](../../art/expedition03_destructible_facilities_20261101/small_wall_collections.png) | [书架](../../art/expedition03_destructible_facilities_20261101/small_bookcases.png) | [完整](../../art/expedition03_destructible_facilities_20261101/small_intact.png) / [破碎](../../art/expedition03_destructible_facilities_20261101/small_broken.png) |
| 中 | [柜体](../../art/expedition03_destructible_facilities_20261101/medium_wall_collections.png) | [书架](../../art/expedition03_destructible_facilities_20261101/medium_bookcases.png) | [完整](../../art/expedition03_destructible_facilities_20261101/medium_intact.png) / [破碎](../../art/expedition03_destructible_facilities_20261101/medium_broken.png) |
| 大 | [柜体](../../art/expedition03_destructible_facilities_20261101/large_wall_collections.png) | [书架](../../art/expedition03_destructible_facilities_20261101/large_bookcases.png) | [完整](../../art/expedition03_destructible_facilities_20261101/large_intact.png) / [破碎](../../art/expedition03_destructible_facilities_20261101/large_broken.png) |


首轮角落密集排列出现射击角度遮挡，已扩大间距并增加无门墙段。第一版射击探针沿单一斜向发弹，起点会落进邻近家具；修正为实际物理射线与球形起点净空查询，使用真实Projectile3D命中，未直接调用take_damage制造通过。失败日志保留，不计为通过。

## 用户数据隔离事故

初始测试副本通过字符串替换指定自定义用户目录，但来源配置没有该字段，替换未生效。仅创建工程外目录/符号链接不能隔离Godot的user路径，导致测试进程实际共用默认存档并出现BaseManager旧revision拒存。本次操作存在隔离遗漏，不能将这部分运行签为安全隔离通过。

发现后停止相关进程，保留默认目录当前base_save.json、其bak及设置副本到工程外备份user_data_audit；明确插入config/use_custom_user_dir与config/custom_user_dir_name，并以独立进程打印实际OS.get_user_data_dir后才重跑。headless/native使用两个不同目录，隔离后的目录与实际存档路径核查通过；默认目录同时存在用户游戏窗口和其他探针进程，其文件SHA仍可变化，不能作为本测试隔离的唯一判据，也不能据此把所有存档变化归因于本轮。没有改写正式项目配置。

未找到可确认的本轮开始前正式存档副本，未以其他测试档冒充正式备份，也未猜测回滚。已向用户询问是否有已知备份，恢复需先比对。此风险与设施验收结果分开记录。

过程脚本、哈希核查、原生截图、失败和最终日志位于工程外ShellStorm2-work/sessions/2026-11-01_authored_destructible_facilities/。修改前文件及用户目录当前状态备份位于ShellStorm2-backup/2026-11-01_authored_destructible_facilities/。不提交或推送，不提升整关partial状态。
