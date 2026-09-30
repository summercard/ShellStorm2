# 主塔与周边室外云雾

功能归属：`ASSET-PIPELINE` / `VFX-POOL` / `WORLD-BLOCKS`。工程版本：0.1.0；设计修订 r1。来源：2026-09-30 用户参考图与追加的空中稀疏雾气要求。状态：制作与专项验收中。

## 目标与范围

主云海位于99F楼面以下。现行100F楼面世界Y=0，层高12m，99F世界Y=-12；主云海完整可视包络上沿不高于-13.5m。建筑周围使用有体积的圆团轮廓、暖白亮部、淡蓝阴影和半透明叠层，风格参考用户的插画城市图。缓慢流动表现由云团内部密度形状连续变化产生，不移动到建筑中。

空中另有稀疏雾团，大小不一、高度错落、透明度低于主云海；允许部分高于99F，仍仅在室外。主塔、周边楼体、塔吊、设备和背景城市都必须避让。主塔全平面壳体作为全高度禁云区，即使门打开或墙体因遮挡隐藏，云雾也不能进入室内。体积盒距建筑至少1.5m，失败时隐藏该云团，不能降级为全屏雾或穿插模型。

## 所有者、数据与生命周期

唯一资产出口为 `assets/art/vfx/environment_3d/cloud_sea/vfx_env_cloud_sea_root_top3d.tscn`，AssetID `VFX-ENV-CLOUD-SEA-3D`，根脚本 `VfxCloudSea3D` 继承 `VfxEffectBase3D`。摆位和参数保存在Prefab的 `CloudSea` / `AirWisps` 静态网格节点；运行时不拼装几何。源目录保留版本及生成脚本、参数清单，运行路径不含版本号。

常驻环境特效由主场景的 `OutdoorClouds` 实例拥有，随主场景卸载释放，不借用有寿命的战斗池。`TowerDescent3D` 在既有Atmosphere完成背景城市构建后，通过基类 `configure(color, size, context)` 传入边界数据；不调用特效私有实现。`context` 的schema为 `world_root:Node3D`、`city_layout:Array[Dictionary]`（Atmosphere权威布局）、`main_tower_rect:Rect2`、`floor_99_y:float`、`enabled:bool`。独立预览可使用作者包的冻结边界；正式接入必须使用运行时建筑边界。

根节点仅拥有表现时钟和可见性。暂停时停止时钟，恢复后继续；内部流动保持在静态体积盒内。重复configure必须复位被拒绝云团的可见性，再按当前边界验证。关闭时隐藏整体；远征独立关卡关闭本资产。无碰撞、无光照节点、无玩法或存档写入，无室内触发器。

`get_presentation_snapshot()` 提供启用状态、数量、流动时间、拒绝数量和边界数量；`get_cloud_volumes()` / `get_exclusion_bounds()` 是只读验收查询。云层与空中雾团共用一套风格Shader，通过独立材质参数控制密度、尺寸与随机形态。

## 拒绝、回滚与验收

任一云团体积盒与膨胀后的建筑边界相交、或主云层越过高度上限，则隐藏该云团并记录拒绝数量。重新配置正确边界后恢复。主场景移除 `OutdoorClouds` 实例即可退役，不改变周边模型、碰撞、天桥或全塔既有雾浓度。

独立入口：`tests/verification/verify_outdoor_clouds.tscn`。验收覆盖正式场景接入、完整世界包络、楼面高度、稀疏雾团的大小和层次、真实Shader参数、暂停/持续运行、场景卸载、禁用与重复配置，并用故意进入主塔的云团验证拒绝。自动化在Autoload启动前隔离APPDATA。真实渲染另存主塔整体、边缘近景、桥楼视角和不同时间帧；headless不代签视觉效果。

资产主表与 `3D-特效` 均登记同一AssetID及稳定Prefab路径。授权来源为用户提供的风格参考和本项目原创程序化Shader，无外部云纹理依赖。开发结果见对应独立交付记录。
