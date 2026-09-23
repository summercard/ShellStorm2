---
name: xlsx-git-conflict-resolution
description: 解决 git 中二进制 xlsx（台账/表格类）合并冲突。三方逐格比对定位真实差异、判断哪一侧是有意修改还是拿到了陈旧副本、用外科式 XML 补丁保真合并（不破坏 max_row/max_column、样式表、合并单元格与数据校验），再通过 rebase/merge 落地。用于资产台账、登记表、预算表等被多任务反复编辑的二进制表格冲突。
---

# 二进制 xlsx 的 git 冲突解决

二进制表格无法自动合并，git 只会报 `Cannot merge binary files`，把两侧都标成冲突。但真实差异往往只有几行——**逐格比对 + 保真合并**才是正解，不要用 `--ours` / `--theirs` 整份取舍。

## 适用范围

- 适用：`.xlsx` / `.xlsm` 等二进制表格在 rebase、merge、pull --rebase 时报冲突。
- 不适用：CSV / TSV 等文本表格——那些直接用普通文本合并即可。

## 分账本结构（2026-09-18 起）

项目资产台账已从单体账本改为「**总目录 + 9 个分账本**」：

- **总目录** `assets/registry/ShellStorm2_美术资产台账_v001.xlsx`：只放跨域契约与分账本索引，**不含资产行**。
- **分账本** `assets/registry/ledgers/ShellStorm2_{角色,敌人,场景,道具,武器,特效,UI,音效,音乐}账本_v001.xlsx`：资产条目按大类分域落位。
- 映射的**唯一真源**是 `assets/registry/ledger_index.json`（说明见 `assets/registry/README.md`）。

对冲突处理的直接影响：

1. **冲突面变小。** 两个任务若分属不同域（角色 vs 场景），改的是不同 xlsx，根本不会冲突；仍然冲突，说明是同一本分账本被并行编辑，逐格比对照常做。
2. **判域先于比对。** 先确认冲突文件是总目录还是哪一本分账本。总目录的冲突几乎都落在《分账本索引》/《3D Prefab总控》这类契约表上，改动应当**与 `ledger_index.json` 逐格一致**——不一致时以 json 声明的结构为准，去判断哪一侧拿的是陈旧副本。
3. **门禁两侧同跑。** 优先用 `python scripts/check_asset_registry.py`（默认跨全部账本 + 跨文件契约），它比 `--workbook <单个 xlsx>` 更能反映真实先进程度；单文件模式不做跨文件断言，只在需要隔离判断某一本时使用。

## 第 0 步：先看清状态，别急着动手

```bash
git status                          # 是否卡在 rebase/merge 中间
git ls-files -u                     # 冲突条目；stage 1=base, 2=ours, 3=theirs
git log --oneline -5
git reflog -12                      # 之前失败过几次
git merge-tree --write-tree <A> <B> # 无副作用预演，确认冲突文件清单
```

注意：`rebase` 与 `merge` 的 ours/theirs 语义相反。
rebase 时 **stage2 = onto（被 rebase 到的目标）= "ours"**，**stage3 = 正在重放的本地提交 = "theirs"**。判断前务必用 `git cat-file blob <stage2sha>` 的内容确认哪边是哪边，不要凭直觉。

## 第 1 步：导出三方内容，逐格比对

用 `git cat-file blob <sha>` 分别导出 base / ours / theirs 到临时目录，再用 openpyxl 逐工作表逐行比对**完整行元组**（不是只比前两列）：

```python
import openpyxl
def rows(path, sheet):
    ws = openpyxl.load_workbook(path)[sheet]
    return [tuple(c.value for c in r) for r in ws.iter_rows()]
```

对每一行分类输出：**仅 A 改 / 仅 B 改 / 双方都改**。只有"双方都改"的行才真正需要裁决。

**工作簿要全跑完，别用 `head` 截断。** 工作表成员名按**字符串**排序是 `sheet1 < sheet10 < sheet11 … < sheet19 < sheet2 < sheet20 < sheet3`——一旦对输出做 `head -40`，排在后面的 `sheet2`（往往是「资产主表」这类主数据表）会被静默切掉，让人误以为"只差两三行"，实际漏掉一大块。先只 grep 汇总行（`###`）拿到**完整**的每表差异格数，再按需展开明细。

## 第 2 步（最关键）：判断"哪侧是有意修改"

**不要只看 base 就直接裁定。** 一定要往前多找几个历史版本一起比——这是本技能最核心的经验。

真实案例：本地侧的行 73、行 90 相对 base 都"改了"，看起来像有意编辑。但把更早的提交 `C` 也导出来比对后发现：

```
LOCAL  vs  更早提交 C   ->  差异行数 = 1（只有行 86）
```

**说明本地那次"账本修改"基于一份陈旧的账本副本**——行 73、行 90 不是有意修改，只是旧内容；本地真正新增的信息只有行 86。

如果直接按"双方都改 → 各让一步"去合并，就会把陈旧内容当成有效修改保留下来，污染台账。

判断手法：`git log --oneline -- <file>` 列出所有改动过该文件的历史版本，逐个导出与两侧比对，找出**差异最小的那个版本**，就能确定某一侧的编辑基线。

同样要查的是**真实损失**：某一侧是不是把一条真实存在的记录整行覆盖掉了？去仓库里 grep 那个 AssetID / 编号，看它是否还有构建脚本、manifest、校验数据引用——如果资产真实存在，记录就不该消失，应当补回。

**最快的判定器：拿仓库自带门禁给两侧各跑一次。** 台账类文件多半配有 `scripts/check_asset_registry.py` 这类校验器，且常支持 `--workbook <path>`（**不必替换工作区文件**）。**问题数少的那版通常就是"更新过"的那版**——它已经消化过上一轮改动。真实案例：冲突前本地侧 37 条、远端侧 38 条，多出的那条正是远端这次新引入的一次枚举违规，据此一眼判定两侧先后关系。

## 第 2.5 步：优先「重放补丁脚本」，而不是手拼 XML

**如果被打回的那一侧，它的每处改动当初都是用脚本写进表格的，那么恢复方式就是重放那些脚本，而不是拿另一侧的整行 XML 去逐个替换。**

真实案例：项目里每次台账升版都留了 `patch_ledger_<用途>.py` / `update_ledger_rows_v00N.py`，它们**幂等**且带「目标行 AssetID 必须与预期一致」的断言。冲突把本地侧 9 行升级整批打回后，按行号顺序重放 3 个脚本即精确恢复了与冲突前逐格一致的内容，远端新增的 45 行毫发无损。逐格重放比手工搬 XML 更快、更可审计，也不依赖"两侧样式索引是否通用"这个前提。

- 先对每个脚本 **dry-run**，确认它仍能定位到目标行（**行号可能已被远端新增行推移**）。
- ⚠️ **2026-09-23 起账本为 9 个独立域**（UI/音效/音乐已从旧表现资源账本拆出，映射见 `assets/registry/ledger_index.json`）。**拆分之前**写下的批次脚本**不能直接重放**：它们既指向旧单体/合并账本，又用旧《资产主表》行号坐标。重放前必须①把目标改成该域分账本，②把行号重定为「按 AssetID 定位」。用 `python scripts/check_ledger_refs.py` 复查待处理清单；新脚本一律走 `scripts/ledger_registry.py` 解析路径。
- **只重放"被打回的那一侧"的改动**，另一侧的新增行原样保留——不要顺手"对齐"。
- ⚠️ 这类脚本通常自带 `shutil.copy2(src, src + BACKUP_SUFFIX)` 备份，**会覆盖仓库里已被 git 跟踪的既有 `.bak_*`**，平白制造几处无关改动。用一个 driver 先 `importlib` 加载脚本、把 `BACKUP` / `BACKUP_SUFFIX` 重定向到临时目录再调 `main()`；或跑完 `git checkout -- '<dir>/*.bak_*'` 复原。
- 恢复后额外做两项**语义自洽**检查：① 概览/汇总表的计数缓存**实算一遍**（它引用的是主数据表，两侧的缓存值可能各有陈旧，别默认新的一侧就对）；② 逐格差异闭包必须**恰好等于**预期行集合。

## 第 3 步：保真合并——用外科式 XML 补丁

> **不要用 openpyxl `load_workbook` → 修改 → `save` 整表重存。**

实测重存的破坏性后果：`dimensions` 从 `A1:T280` 缩成 `A1:P91`、`max_row/max_column` 变化、`sharedStrings.xml` 消失、`docProps` 被新增、样式表被重写。项目里若有 `verify_ledger.py` 这类脚本断言 `(max_row, max_column)` 不变，重存就会直接让它失败。

正确做法是**只改需要改的那张工作表的 XML**：

1. 先探明内部结构：

```python
import zipfile, re
z = zipfile.ZipFile(src)
print(z.namelist())                                   # 找 xl/worksheets/sheetN.xml
xml = z.read('xl/worksheets/sheetN.xml').decode()      # 注意命名空间前缀！
```

**坑点**：这类 xlsx 常使用自定义前缀（如 `<x:row>` / `<x:c>`）而非默认命名空间，正则必须写成 `<x:row r="(\d+)"` 或 `<(?:\w+:)?row r=...`，否则一个都匹配不到，会误以为"没有该行元素"。

2. 从另一侧的同名工作表里**原样取出整行 XML 复用**（两侧通常出自同一套工具链，样式索引 `s="393"` 之类完全通用），不要去手工拼 XML：

```python
def row_block(xml, n):
    return re.search(r'<x:row r="%d"[^>]*>.*?</x:row>' % n, xml, re.S).group(0)
```

3. 替换 / 插入。新增行时插入到最后一个数据行之后（先确认后面确实全是空行），并把行号整体重编号：

```python
block = re.sub(r'(<x:c r="[A-Z]+)%d"' % old, r'\g<1>%d"' % new, block)
new_xml = remote_xml.replace(remote_86, local_86, 1)          # 替换
new_xml = new_xml.replace(remote_90, remote_90 + block91, 1)  # 插入
```

4. 重新打包，**除该 sheet 外所有条目按原字节拷回**：

```python
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zo:
    for item in zr.infolist():
        data = zr.read(item.filename)
        if item.filename == SHEET_XML:
            data = new_xml.encode('utf-8')
        zo.writestr(item, data)
```

5. 校验清单（缺一不可）：

```
zip 条目集合一致，且除目标 sheet 外字节完全相同
全部工作表 max_row / max_column 与原文件一致
dimensions / merged_cells / data_validations 保留
styles.xml 两侧一致（跨版本引用 s= 索引才安全）
逐表逐格差异 == 预期的那几行
提交后：git rev-parse HEAD:<file> == git hash-object <worktree file>
```

## 第 4 步：落地

```bash
git rebase origin/<branch>          # 或 git merge origin/<branch>
# 冲突后，用合并产物覆盖该文件
git add -- "<path>"
GIT_EDITOR=true git rebase --continue
```

中文/空格路径一律加引号；`GIT_EDITOR=true` 避免 `--continue` 弹编辑器。

## 安全网（务必先做）

```bash
git rebase --quit                    # 清理卡死的 rebase 状态：只清状态，不动 HEAD/工作区
                                     # 绝不要用 git rebase --abort，它会 reset --merge 丢掉未提交改动
git branch backup/pre-resolve-<b> <local-sha>
git tag backup/pre-resolve-origin-<b> <remote-sha>
git stash push -m "WIP 解决冲突前备份"   # 只暂存已跟踪改动；未跟踪文件不会被 rebase 碰到，原地留着
git rev-parse "stash@{0}"            # 把 SHA 记下来！reflog 可能丢失
```

## stash 相关坑点

- **`git stash pop` 可能报 `refs/stash@{0} is not a valid reference`**，随后 `git stash list` 变空 —— 这是 `.git/logs/refs/stash`（reflog 文件）丢失造成的，`refs/stash` 本身和所有 stash 对象都完好。**用记录下来的 SHA 直接恢复**：`git stash apply <sha>`。
- `git update-ref` **默认不会为 `refs/stash` 写 reflog**（默认只覆盖 `refs/heads`、`refs/remotes`、`refs/notes`、`HEAD`），重建必须显式加 `--create-reflog`：
  ```bash
  git update-ref --create-reflog -m "On <branch>: Pull autostash <date>" refs/stash <sha>
  ```
- 恢复孤儿 stash 对象：`git cat-file --batch-all-objects --batch-check` 枚举全部对象，筛出 `commit`，再批量 `git cat-file --batch` 读内容匹配 `autostash` / `WIP on` 字样。
- 每次操作后**立刻给 stash 打标签**（`git tag wip/<name>-<date> <sha>`），否则 reflog 一丢就被 gc 回收。

## 环境坑点（Windows）

- 若 bash 缺 coreutils（`ls`/`mkdir`/`tail`/`head`/`wc` 全 not found），改用 Python 做文件操作：`shutil.copyfile`、`os.makedirs`、`pathlib`。git 命令本身正常，用 `git -C <绝对路径>` 形式最稳。
- **脚本必须在仓库根目录之外的 CWD 运行**。项目根若存在 `inspect.py` / `types.py` 等与标准库同名的文件，会遮蔽 stdlib 导致 `ModuleNotFoundError`（例如 `inspect.py` 里 `import bpy` 会让你以为是 bpy 缺失）。
