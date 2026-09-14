# 局内关卡01-顶部数据库命名规范

## 结果

98–95F区段统一使用组合显示名`局内关卡01-顶部数据库`。

- 稳定编号：`level_number=1`、`level_code=局内关卡01`。
- 可变设定名：`setting_name=顶部数据库`。
- 组合规则：`display_name={level_code}-{setting_name}`。
- 稳定工程身份：`block_id=battle`、Godot节点`Blocks/Battle`、AssetID和文件路径保持不变。

后续只改设定时更新`setting_name`与组合后的`display_name`，不得修改编号、节点路径或AssetID。后续关卡编号统一使用两位数字，例如`局内关卡02`。

## 同步范围

已同步区块主设计、3D场景生产示例、Godot场景元数据、Battle白盒JSON、区块README和资产台账。本次不改变98–95F玩法、楼层、模型或运行时生成逻辑。
