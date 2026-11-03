# SPECIAL-ITEMS · 2026-11-03

新增手雷、燃烧瓶、汽油瓶；99F自动贩卖机取得，I/Tab特殊槽绑定，右键投掷/按住铺油。规则Owner在src/special_items，数值在data/special_items/catalog.json；设计与开发记录均独立。

14个新资产ID：3模型双角色、2UI、3VFX、6录音音效。模型源共6份，ground均180三角；音效保留PCM24/OGG、来源授权及剪辑配方。独立账本在docs/v0.1/data与assets/registry/special_items_ledger.json，分域账本仍为唯一AssetID登记。

75核心+14正式接线、原生截图、音频播放通过；时长4秒反向对照准确失败后复绿。285条非目标资产行不变。历史装备测试、文档断链和2/5/7道具/UI/VFX哈希漂移单列，未宣称全局套件通过。

SPECIAL-ITEMS r6：火焰伤害24/s与32/s并伤玩家；范围伤害补入可破坏交互物/家具。共享火焰有汽油照明，末0.6秒火/灯/油迹渐隐，伤害5秒不变。85核心+19接线+10交互照明渐隐专项及原生暗场图通过。
