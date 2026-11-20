# 正式远征购卡上半区接管与验收

2026-11-20 · `FATE-RULES` / `UI-HUD` · 主树 `0.2` / `64107848` + 既有工作区改动。设计见 [UI-23](../design/UI与UX全局设计及全界面清单.md#ui-23-命运pickup三候选全息购卡层doorfateoverlay3d历史节点名保留)。状态：**已有布局，当前真渲染复验未通过启动阶段**。

- 接管时上半区布局已在主树：`Dungeon3D` 只对正式远征 `pickup` 选择新尺寸，`FateHologramPresentation` 将候选行下移 8 逻辑像素；本轮完整保留这两份脚本及同文件快捷栏改动。下板、其它来源、已购/取消、固定价格表和购买事务未改。
- 本轮强化 `capture_expedition_purchase_layout.gd`：逐卡断言卡面、文案与购买按钮不重叠且在视口内，检查三列居中等距、价签字号/描边；余额不足和实际扣款检查默认执行，不再依赖日志标签。PNG 保存失败不再输出通过。专用 `python -B scripts/run_expedition_layout_qa.py fate --godot <Godot console>` 在启动前隔离用户目录，使用主树既有导入缓存，输出写工程外。
- 历史 Godot 4.6.3 Compatibility 最终日志：1024×576 与 1280×720 各 5 张，现有样本标价和扣款均 60，余额不足拒绝、方向键聚焦后购买；较早 1024×576 复验曾报购买未提交，不能以早期结果代签本轮。
- 本轮 Godot 4.7.2 Compatibility 窗口在 1280×720、1920×1080、1024×576 均以超时 `124` 停止，未产生 `CAPTURE_FATE_PURCHASE_UI_OK`；未见脚本错误，部分窗口已进入场景资源加载。日志：工程外 `verification/expedition_layout/20261120_183351_849264/`。未签真实焦点、视觉及全息购买回归，也未推进共享 HUD 部分。
- 媒体域门禁与运行资产命名门禁均 `0`。UI 账本门禁 `1`，报告 5 个哈希漂移；`UI-FATE-HOLOGRAM-PRESENTATION` r28 的登记值既不同于 HEAD，也不同于当前工作区。未在验收未闭环时刷新哈希或改其它行。功能整体状态不提升。
