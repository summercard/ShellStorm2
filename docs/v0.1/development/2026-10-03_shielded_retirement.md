# 壳甲卫兵退役与胖子僵尸替换

用户要求将壳甲卫兵配置换成胖子僵尸，并退役壳甲卫兵。ENEMY-AI / ASSET-PIPELINE；玩法状态Owner仍为Enemy3D，出怪配置Owner为MonsterInjector/SpawnBoxCatalog，规则见[胖子僵尸运行配置](../design/胖子僵尸03运行配置.md)。

远征01引用的纵列盒和桥心盒将shielded改为fat_zombie03；纵列仍为1只、延迟1.5秒，桥心仍为4只、延迟1秒，其余条目/盒尺寸/放置/波次不变。默认随机池、锈炉与深渊主题池、守卫及精英缺省底型同步替换，原重复权重保留。shielded移出MonsterInjector基础/表现表、触发盒白名单、Enemy3D编辑器枚举和状态展示选择。

壳甲卫兵的旧Profile/程序视觉只为旧存档与历史行为兼容保留；没有现行刷怪入口。尚未实装的铁壁和反射者精英设计保留，未擅自改写成胖子精英。壳甲卫兵资产ENM-TANK-SHELLGUARD01及内容monster_shielded标记退役，稳定ID与历史记录保留。胖子继续使用自己的696生命、19伤害、0.3/0.6m/s速度和抱扑动作，没有继承旧正面格挡。

运行验收verify_shielded_retirement：固定种子77001199生成远征全部房间的实际盒波次，记录小僵尸115、炸弹果14、保安37、胖子10、召唤者1；壳甲为0，并验证白名单、显式拒绝退役类型、两主题池和正式实体。verify_fat_zombie03的152项复测退出0。日志和报告在outputs/fat_zombie03_retirement。

远征加量门禁退出1，仅Boss房boss#1漂移快照0.63米与实测2.12米不符。隔离副本恢复替换前源码、两盒与主题配置，复现同一失败；没有刷新旧快照掩盖问题。正式源/存档未在对照时切换，Autoload前隔离APPDATA。共享色盘UID警告仍通过文本路径加载。

原配置及表格备份位于_scratch/fat_zombie03/shielded_retirement_backup。门禁退出码见outputs/fat_zombie03_retirement/gates.json；全工程既有文档、命名、其他资产SHA问题单列。未提交Git，未删除历史美术源。
