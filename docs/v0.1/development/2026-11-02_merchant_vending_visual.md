# 2026-11-02 远征03商人改用99F贩卖机

工程0.1.0；FeatureID WORLD-PLAN / ASSET-PIPELINE。来源：用户明确要求商人房模型使用99F基地自动贩卖机。

复用基地稳定包装 `assets/art/props/base_world_3d/runtime/vending_machine/prp_base_vending_machine_root_top3d.tscn`，仅迁移视觉、物理体、交互形状和提示锚点。原包装未进入树，基地交互/交易脚本不运行。03主题显式配置；其他主题默认空值，旧表现保留。场景陈设、模型源、GLB、资产哈希与台账资产版本未修改；新增消费映射归03主题。

隔离测试在工程外 `ShellStorm2-work/sessions/exp03_layout_vending1102/verify/`，验证OS用户目录和BaseManager保存路径后才实例化。Windows符号链接准备失败，改用目录junction保留相同隔离配置。前几次夹具断言失败，其中定位并修复主题属性先于script赋值导致丢失的错误；未冒充通过。最终final.log退出0，VENDING_OK，检查模型、碰撞尺寸、交互候选/执行和旧终端回退通过。无非预期SCRIPT ERROR；存在资源UID回退WARNING。预期故障注入未执行。未执行原生渲染、房内更大包络与家具净空、真实玩家购买和全关回归，整关partial不变。

文档门禁退出1（历史链接/测试登记问题，详docs.log）；关卡解耦退出0/0违规；资产运行命名门禁退出1（存量问题，未新增运行资源文件）。本次仅复用设施，没有导入/优化或重新导出资产。
