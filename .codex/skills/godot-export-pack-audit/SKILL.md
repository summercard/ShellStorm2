---
name: godot-export-pack-audit
description: 实测 Godot 游戏导出包（PCK）里到底装了什么 —— 回答「这些东西会被打包进游戏吗 / 包为什么这么大 / 哪些开发期文件混进了发行包」。做法是真跑一次 `--export-pack` 导出 PCK，再用脚本解析 PCK 索引逐条统计（按目录分组、按扩展名分组、按 glob 命中）。当问题涉及「会不会打包」「包体为什么这么大」「临时/测试/文档/源码目录进包了吗」「某个 json 运行时读得到吗」，且必须用真实打包结果而不是看 `.gitignore` 或猜 Godot 语义时使用。不修改产品代码。
agent_created: true
---

# Godot 导出包（PCK）内容审计

## 为什么需要它

`.gitignore` 管的是**版本库**，`.gdignore` 管的是**Godot 导入**，`export_presets.cfg` 管的是**导出过滤** —— 三者互不相干。

实测（ShellStorm2，Godot 4.6.3）三条反直觉事实，**光看配置猜不出来**：

1. **`.blend` 源文件不进包**（0 个）—— Godot 用 `.godot/` 里的导入产物替代它。所以 `source/**/*.blend` 没被 `.gdignore` 排除，**也不会**把几百 MB 的 blend 带进发行包。
2. **`.json` 会进包**（ShellStorm2 实测 2454 个 / 33 MB）—— 构建期记账用的 `asset_manifest.json` 之类会被原样打进去，因为 `export_filter="all_resources"` 收所有文件。
3. **`.import`、`tests/`、`docs/`、`tools/`、`_scratch/` 一律进包** —— 只要 `exclude_filter` 是空的。

⇒ 结论：**必须实测，不能推理**。

## 前提

- 导出模板必须已装：`<APPDATA>/Godot/export_templates/<引擎版本>.stable`。缺了就 `ls` 一下确认，别硬跑。
- 预设名取自 `export_presets.cfg` 的 `[preset.N] name="..."`。
- 全量导出很慢（ShellStorm2 约 **4 分 22 秒**、输出 913 MB）⇒ 放后台跑，别占前台。

## 步骤

### 1) 导出 PCK（后台，输出到仓库外）

```bash
cd <项目根>
"<Godot>_console.exe" --headless --path . \
  --export-pack "<预设名>" "<仓库外目录>/_probe_export.pck"
```

- `--export-pack` 产出单个 `.pck`，比 `--export-release` 快且不需要装 exe。
- **输出路径放仓库外**（如父目录的 `_scratch/`），否则会污染工作区。
- 退出码 0 且日志末尾出现 `[ DONE ] savepack` 即成功。

### 2) 解析 PCK 索引

用 `scripts/pck_inspect.py`：

```bash
python scripts/pck_inspect.py <file.pck>
```

它会打印：引擎版本 / 文件总数 / 包内总字节 / 按目录分组 / 按扩展名分组 / 关键 glob 命中数。

### 3) 自定义统计

需要别的切面（例如「某子目录的 manifest 进了几个」）时，import 后自己过一遍条目：

```python
import sys; sys.argv = ['x', '<pck>']
exec(open('scripts/pck_inspect.py', encoding='utf-8').read().split('def main')[0])
E = parse('<pck>')            # [(path, offset, size), ...]
sel = lambda f: [(p, s) for p, _, s in E if f(p)]
print(len(sel(lambda p: 'asset_manifest' in p)))
```

### 4) 收尾

**删掉那个 PCK**（几百 MB ~ 1 GB 的临时产物）。脚本可以留着。

## PCK 格式（Godot 4.6 = pack format v3）—— 逆向结论

⚠️ 网上流传的 v2 布局（`file_base` 之后跟 64 字节 reserved、再 `file_count`）**在 v3 上解析出 0 个文件**。v3 实际布局：

| 偏移 | 类型 | 含义 |
|---|---|---|
| 0 | u32 | magic `GDPC` (`0x43504447`) |
| 4 | u32 | pack_format_version（4.6.3 = **3**） |
| 8 / 12 / 16 | u32×3 | 引擎 major / minor / patch |
| 20 | u32 | pack_flags（`0x2` = `PACK_REL_FILEBASE`，路径相对 `res://`） |
| 24 | u64 | `file_base`（数据区起点；文件 offset 相对它） |
| 32 | **u64** | **`dir_offset` —— 索引在文件尾部**，不是紧跟在 header 后面 |

索引（从 `dir_offset` 起）：

```
u32 file_count
重复 file_count 次:
    u32 path_len          # 含尾部 \0
    bytes path[path_len]  # UTF-8，pack 内相对路径（无 res:// 前缀）
    u64 offset            # 相对 file_base
    u64 size
    bytes md5[16]
    u32 flags
```

**自校验判据（必做）**：解析完 `file_count` 条后，游标必须**正好等于文件大小**。对不上就是格式假设错了 —— 别硬读。这个判据就是靠它发现 v2/v3 差异的。

排错提示：若在 header 之后（而不是尾部）读到一个像小整数的 `path_len`，就会得到 `file_count=0`；正确做法是先读偏移 32 的那个 u64 拿 `dir_offset`。

## 报告口径（写结论时用）

- **体积永远给绝对值 + 占比**：`3.07 MB / 913 MB = 0.34%`，别只说「很多」。
- **区分「进包了」与「有问题」**：进包 ≠ 有害。判有害要看①体积占比②运行时是否被读③是否属于开发期内容。
- **运行时硬依赖要单列**：任何被 `FileAccess` / `load()` 在 `res://` 下引用的路径，若打算用 `exclude_filter` 裁掉，**逐条验证过再裁**。ShellStorm2 的实例：`FloorPlanGenerator.gd` 用 `FileAccess.get_file_as_string()` 读 `…/expedition/source/room_types/boss_room/v002/boss_room_50x40_v002.layout.json` —— 它就在 `source/` 里，所以对 `source/**` 做一刀切排除会**打断 Boss 房装配**。
- **`exclude_filter` 的陷阱**：`export_filter="all_resources"` + 空 `exclude_filter` 是默认值，等于全收。要裁剪就在 `export_presets.cfg` 的 `exclude_filter` 里写 glob（逗号分隔），**改完重新导出并复查那几个硬依赖仍在包内**。
