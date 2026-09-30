# 主塔室外云海

稳定AssetID：VFX-ENV-CLOUD-SEA-3D；版本v002。正式出口vfx_env_cloud_sea_root_top3d.tscn。品质优先：一个连续体积、24块漂浮小云、三维结构+薄雾+方向透射。机制与状态见docs/v0.1/design/outdoor_cloud_sea.md和v002开发记录。

## 离线重建顺序

所有Godot进程启动前使用独立APPDATA；不要写入正式用户存档。

1. Godot `--headless --path . --script assets/art/vfx/environment_3d/cloud_sea/source/v002/measure_buildings.gd`：按正式场景更新building_snapshot.json（隐藏网格也参与）。
2. Python `source/v002/build_outdoor_clouds.py --boundaries source/v002/building_snapshot.json`：更新静态Prefab、布局与保守建筑距离数据。相对路径以资产目录为基准。
3. Python `source/v002/build_billow_volume.py`：从保留的image-2原图生成运行灰度数据，构建128³RGB周期结构。
4. Godot `--path . --rendering-method forward_plus --script assets/art/vfx/environment_3d/cloud_sea/source/v002/bake_cloud_textures.gd`：生成native Texture3D；不能用headless/Compatibility烘焙。
5. 运行真实Forward+专项 `tests/verification/verify_outdoor_clouds.tscn`，检查正式玩家视角。运行 `tools/asset_pipeline/render_outdoor_clouds.gd -- --motion` 保存性能、截图和12秒实时帧。
6. 通过后更新Manifest与既有账本行；`tools/asset_pipeline/update_cloud_sea_ledger.py main`、`... prefab`为两个独立事务，只更新本AssetID。

纹理不是发光颜色：cloud_billow_density为灰度密度；cloud_noise的RGB分别为大/中圆团与柔软侵蚀；cloud_keepout为0～16米保守距离。边界变化后云雾会在配置检查中停用，需重建。原始贴图和生成模型信息在source/v002/texture_provenance.json。
