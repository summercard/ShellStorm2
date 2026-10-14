# 物品道具账本与掉落调用归属

日期：2026-10-14。工程版本：0.1.0。功能：ASSET / WORLD-LOOT / REWARD-SERVICE / INVENTORY-SLOTS / WEAPON-OWNERSHIP。来源：用户指定可入包物品建立独立账本、不放《资产主表》，子弹及配件保留武器账本。状态：导航整理与静态核对完成；不代表新增物品美术已完成。

## 交付

- 新增 `assets/registry/ledgers/ShellStorm2_物品道具账本_v001.xlsx`，含《物品道具》《掉落归属导航》《非背包与待设计》《功能调用链》，无《资产主表》。20个运行内容ID：8种蓝图碎片、3种背包、3种电池/电芯、3种手电模块、治疗药水、信标、普通钥匙。
- 武器账本新增《背包物品调用索引》：11种成品武器、8种子弹模块、6种枪械配件、通用弹药，共26个内容ID。与新账本互斥、并集完整覆盖ItemRegistry的46个ID。通用弹药按用户“子弹归武器账本”的要求归入武器侧，使用接口指向背包点击的换弹分流。
- 怪物掉落CSV的16行逐行定位：原作者表行、关卡/怪物/物品ID、唯一账本登记行、正式运行投影及编译/调度入口。魂与未注册设计中的Boss下行钥匙单列；不复制掉落概率、数量或堆叠规则。
- `ledger_index.json#content_ledgers.inventory_items`登记新账本的内容导航角色；武器域`sheet_scope`登记新增页。九个资产域、1241个AssetID以及资产主表未变。原武器账本5张表逐格值、样式、尺寸和数据校验与改前副本一致，无损基线未改。
- 新增 `scripts/sync_inventory_item_ledger.py`，默认只读：核对CSV/关卡投影的怪物-物品行序列、46个运行定义归属互斥与覆盖、保存的源定位值、调用函数存在性；`--write`用于审查后刷新导航。不会修改原内容表、掉落CSV、运行配置或游戏代码。
- 资产规范§6.1、registry入口和功能索引ASSET行同步记录现行责任边界。

## 调用审查

正式链路：`ItemRegistry → MonsterDropTable.compile / MonsterInjector.drop_spec_for → RuntimeRewardCoordinator.resolve_kill → RewardService → RewardSink.apply_ground → Dungeon3D._spawn_loot_items → GroundLootPickup3D → Dungeon3D._on_ground_loot_requested → InventoryModule.add_item`。

背包事实由InventoryModule持有，满包时物品留地、部分接收保留余量。Dungeon3D背包点击先分流换弹、武器、背包、手电模块、配件及子弹模块，普通动作由ItemUseHandler处理；子弹模块实际走`_install_weapon_module_from_item`，配件走`_install_attachment_from_inventory`。地面模型与UI图标共用ItemModelFactory3D。账本没有运行时读取入口，不新增Owner。

审查暴露的现行差距：内容数据库《掉落物品》仅44个运行ID和1个设计ID，缺`weapon_sprinkler`及`bp_sprinkler`；新账本标记缺行，以运行ItemRegistry身份为准，不擅自改旧内容表。三种电池/电芯和手电模块使用逻辑存在，但模型工厂仍落入crate通用箱体。背包有独立PackedScene路径，但资产登记仍为待制作。旧combat/spawn池声明不等于可达掉落。Boss下行钥匙未注册，魂直接入货币余额。

## 验证与限制

| 核对 | 退出码 | 结果 |
|---|---:|---|
| sync_inventory_item_ledger | 0 | 20物品＋26武器；16掉落行；2排除项；函数及源定位存在 |
| check_asset_registry --scope structure | 0 | 1241资产、9美术账本；无结构错误 |
| check_asset_registry --scope full --ledger weapons | 0 | 武器36资产；无错误 |
| verify_ledger_split | 0 | 资产并集、列摘要及锁定分页无漂移 |
| check_documentation_contracts | 1 | 30项既有问题；通过改前文档替身复查，问题列表与改前相同 |
| check_asset_runtime_naming | 1 | 既有14文件/3目录带版本债务及tscn引用数上升债务；本次未修改assets/art或运行脚本 |

预期故障注入：未执行。非预期脚本错误：上述专项无；全局检查按既有问题报告失败。未执行：Godot运行与真实游戏渲染（本次只改账本、导航工具与文档）；原有美术未重新验收。新账本4页与武器新增页已用Artifact Tool渲染检查；原页无布局改动。项目账本使用openpyxl写入，未通过编辑器重存原表。

过程日志、五张分页预览与退出码记录位于工程外 `ShellStorm2-work/sessions/2026-10-14_inventory_item_ledger/`。改前副本位于 `ShellStorm2-backup/2026-10-14_inventory_item_ledger/before_edits/`。默认python3缺openpyxl；专项用项目现有WorkBuddy Python，文档复查把其bin加入PATH以便子检查找到依赖。
