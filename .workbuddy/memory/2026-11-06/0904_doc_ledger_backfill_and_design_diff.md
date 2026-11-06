# 0904 近两日工作落档核对 + 设计/实现差异盘点

## 起因
主人：检查这两天（11-05 / 11-06 两次每日提交）的工作哪些没记进文档/账本，先补记录，
再对比设计文档与游戏实际内容的差异。

## 盘点结果（6 个工作项）
- 完整：远征03 关灯底光 0.15、宝箱免钥匙 + 钥匙经济退役、开箱前后过渡。
- 缺档 3 项，全在 VFX 域：
  1. Boss 仪式封印门 → MODULE_INDEX 缺摘要（其余齐）。
  2. 子弹尾迹隐藏 → 特效账本无记录、MODULE_INDEX 缺。
  3. 黏液血泊贴图 → CHANGELOG / MODULE_INDEX / 特效账本三处缺
     （FX01-17/19 规格列还写着「4 块扁平方形地面液体」）。

## 已补
- 特效账本：FX01-19 / FX01-17 规格 + 关键词 + 更新时间 + 备注（含贴图路径与 SHA-256）；
  域变更日志 `v0.1.36`（贴图）、`v0.1.37`（尾迹开关）。
- `ledger_split_baseline.json`：新增 `scripts/refresh_ledger_baseline_goo_puddle_20261105.py`，
  白名单只放这两行 + `3D-特效` 页摘要；`LEDGER_SPLIT_VERIFY_OK assets=1437`。
- CHANGELOG 补黏液一条；MODULE_INDEX 补 3 条摘要；development 记录补「账本」一节。
- `05_技术施工_关卡生成与爬楼.md` §5.4 后补「远征03 钥匙经济退役」例外说明。
- `TreasureChest3D.gd` 头注释时间轴纠正：0.54/0.92 → 0.59/0.97（漏算回正 0.05s）。

## 关键判断
- **贴图不单开 AssetID 行**：按 FX01-16 吼叫图标（`vfx_monster_roar_icon_atlas_v001.png`）先例，
  贴图算所属特效的内嵌资产，路径 + SHA 写在 FX 行备注 ⇒ 资产总数 1437 与查重范围不变。
  账本「一行 = 一个 AssetID」的规则对贴图并不适用，别再为此单开行。
- 16 条 SHA 漂移**没有批量重算**（AGENTS.md 要求先溯源）。
- 套件被既有 27 项房间门位指纹漂移预检阻断，11-05 的绿是 3 只专项探针的绿，不是全套绿。

## 落地产物
- `docs/v0.1/audits/2026-11-06_design_vs_build_audit.md`（12 条差异 + 门禁读数 + 处理顺序）

## 环境备注
本机 bash 的 `python` 无 openpyxl；带账本的检查用
`C:\Users\zhuangmenghong\AppData\Local\Python\pythoncore-3.14-64\python.exe`。
PowerShell 重定向会把中文写成 UTF-16，读回乱码 —— 用 `PYTHONIOENCODING=utf-8` + bash 重定向。
