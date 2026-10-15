# 物品专用高亮色板接入

FeatureID：ASSET-PIPELINE / WORLD-LOOT / INVENTORY-SLOTS。工程版本0.1.0；设计修订r4。来源：用户要求物品与场景区分，色板饱和度和亮度提高40%，同步所有物品材质、skill、设计和账本。

新正式贴图为 `assets/art/shared/palette/item_high_visibility_palette_10x10_512.png`，512×512 RGBA、10×10格。由原场景色板在sRGB HSV中令S/V各乘1.40并封顶1，保留H、Alpha及UV格位；灰阶保持中性，亮色达到上限后封顶。配方由 `tools/asset_pipeline/item_palette.py` 与 `art_source/shared/palette/item_palette_recipe_v001.json` 持有；逐像素核对通过，原场景PNG哈希保持不变。

范围为28种已制作物品及三款背包，共31个资产：51个GLB切换独立导入脚本，底色与发光贴图统一绑定新色板、Nearest采样、发光乘法；色板无损导入、无mipmap，禁止自动改为3D有损压缩。GLB原有几何无需重导，仍不内嵌图片。64份当前Blender源、优化母版、参考套件及道具模板重新保存与打开；材质贴图使用相对外链，几何、逐面UV、物体变换和父子关系签名保持不变。

31个运行时物品（含背包）的地面和背包图标已实际渲染；51个GLB全部独立实例化，共检查350处材质，底色、发光、最近邻与乘法均通过。另加载现有场景组件确认仍使用原场景色板；实际地面渲染31个物品完成。隔离APPDATA位于工程外工作目录，没有使用正式存档。运行验收退出0，无脚本错误。导入扫描出现既有缓存MD5文件读取错误，随后正式运行51个资源均加载及材质检查通过；旧场景色板UID回退及兼容渲染器TAA警告仍存在。

账本新增 `ITM-PALETTE-ITEM-HIGH-VISIBILITY` 贴图行，更新31个模型资产、64个当前源哈希和90份契约/清单；同步既有Prefab分页的材质记录，色板不新增Prefab。物品调用账本生成器记录新色板并纳入三款背包的实际映射，重建后调用导航检查通过。非目标资产行指纹保持原值。

三个skill（item-prop-dual-model-authoring、06-items-weapons-blender-authoring、07-items-weapons-godot-prefab-assembly）在WorkBuddy正本更新，并逐文件复制、哈希核对到skills_drafts、项目.codex/skills、用户.codex/skills；物品专用色板规则覆盖原场景色板要求，枪械主体及场景保持各自规则。

持久证据见[色板绑定清单](../../../art_source/shared/palette/item_palette_binding_manifest.json)；规范见[物品双模型规范](../design/物品道具双模型制作规范.md)。过程日志与同灯光旧/新图标、地面渲染位于工程同级 `ShellStorm2-work/sessions/2026-10-15_item_palette/`；备份位于 `ShellStorm2-backup/2026-10-15_item_palette/before_edits/`。

全工程资产结构检查退出0。本批32个资产（31模型+1贴图）的完整账本路径/哈希检查无问题；道具域另有14项旧资产哈希差异、武器域另有19项旧资产哈希差异。无损检查仍有15项特效域差异，命名检查仍被其他角色/场景带版本资源阻挡。文档门禁结果另见本记录后续检查条目；这些既有或其他任务问题未批量接受到本次基线。

收尾检查：三个skill的quick_validate均退出0；色板导入设置白名单已保存，最终Godot重新导入退出0、没有ERROR，仍有旧场景UID路径回退警告。文档检查退出1：两处旧/特效链接失效、VFX-POOL索引列数错误、7项其他验收未登记、其他包裹设计追溯缺项及UI账本计数16/18不一致；本次新增色板设计与交付链接无报错。检查时设置PYTHONUTF8/PYTHONIOENCODING，避免Windows子进程中文编码导致检查器提前崩溃。
