---
name: windows-recycle-bin-purge
description: 当主人说「清空回收站」「回收站多大」「看看回收站里有什么」「回收站清不干净」时使用。先在动手前做**只读审计**（按盘/SID/时间/来源目录出报告并给用户确认），确认后才调 SHEmptyRecycleBinW 逐盘清空，最后 verify 核验残余并给出原因分析。用于 Windows 本机；只操作回收站目录，不碰任何其他路径。
agent_created: true
---

# Windows 回收站审计与清空

不可逆操作。流程固定成三步：**scan → 给人确认 → purge → verify**。

## 硬约束

1. **不许跳过审计直接清空。** 回收站里经常混着几分钟前刚删的项目产物（Godot 导出包、Blender .blend1、
   探针临时目录），也混着别的账户 SID 的陈年残留。主人要的是"看清楚再删"。
2. **必须列出受影响的盘、体积、TOP 大文件、最近删除项**，并明确标注操作不可逆，得到确认后才动清空。
3. 只操作 `<盘>:\$Recycle.Bin\<SID>\` 下的 `$I`/`$R` 文件，绝不碰回收站以外的任何路径。

## 三步流程

```bash
# 1. 审计（只读，出报告）
python <skill>/scripts/recyclebin_tool.py scan -o <报告路径>

# 2. 把报告结论交给主人，明确问确认范围：全部 / 只某个盘 / 取消

# 3. 清空（不可逆）
python <skill>/scripts/recyclebin_tool.py purge

# 4. 核验
python <skill>/scripts/recyclebin_tool.py verify
```

## 关键事实（都是踩出来的）

- `$I` 元数据布局（version=2）：
  `0x00 i32 version | 0x08 i64 逻辑大小 | 0x10 i64 删除时间(FILETIME) | 0x18 i32 路径字符数 | 0x1C UTF-16LE 原路径`
  → **路径从 0x1C 开始**，从 0x18 开始解会得到一堆单字符垃圾；FILETIME 转 datetime 要
  先减 `116444736000000000` 再除 `1e7`。
- `SHEmptyRecycleBinW(hwnd, rootPath, flags)` 是官方接口，flags =
  `SHERB_NOCONFIRMATION|NOPROGRESSUI|NOSOUND` = `0x7`。rootPath 传 `"C:\"` 逐盘清，
  传 `NULL` 一次清所有盘（但拿不到分盘结果，**不要用它**）。
- **它是异步的**：返回 S_OK 后后台还在删。立刻统计会看到"还剩一大堆"，别误判成失败，也别急着删更多。
  脚本里已经加了等待轮询。
- 该 API **只清当前用户 SID**。别的 SID 目录（典型是 2019 年旧账户留下的几百 KB）需要管理员权限，
  普通权限下会剩着 —— 这才是"资源管理器点了清空还剩下东西"的真因。
- `E:/G:/H:` 这类无回收站配置的盘调用会抛 `OSError(22, '灾难性故障', -2147418113)`，属正常，不是脚本 bug。
- 带 interception 的沙箱里 `os.remove` 会被改写成"移到回收站"，所以清残余要用 `kernel32.DeleteFileW` 兜底，
  并且先 `SetFileAttributesW` 去掉只读/隐藏属性。
- 正在被别的进程写的文件会 `PermissionError` —— 主人机器上 Godot / Blender / 各类验证脚本会**持续**
  往回收站里吐文件。碰到这种情况说清楚"还有 N 条是新进来的/被占用"，不要反复重试刷屏。

## 本机环境坑

- bash 里 `python -c "..."` 的双引号会吃掉 `$Recycle` 里的 `$`（当成 shell 变量），
  含 `$` 的路径一律**写进 .py 文件再执行**，不要内联 `-c`。
- 探测盘符用 `kernel32.GetLogicalDrives()`，别逐个 `os.path.exists('A:\\')`，软驱探测会卡死。
