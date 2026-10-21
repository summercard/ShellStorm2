"""收集指定时间窗口内的工作内容，产出「每日更新文档」（Markdown）。

为什么需要三个来源（单一来源都不够）
    - 只读 `docs/v0.1/development/CHANGELOG.md`：条目是人工按里程碑写的，
      粒度粗，且有些日子的收尾工作没单独开条目。
    - 只读 `git log`：**会漏掉未提交的工作**。2026-10-13 实测工作区有 397 个
      未提交改动（230 新增 / 95 修改 / 72 删除），这些在 git log 里完全看不到。
    - 只读 `git status`：只有「改了多少」没有「改了什么」，读者看不懂。

    三者合并后：CHANGELOG 给「做了什么、为什么」，
    git log 给「当天提交过哪些批次」，git status 给「还有多少没落库」。

时间窗口
    默认过去 24 小时。凌晨 5 点跑时，窗口 = 前一天 05:00 → 今天 05:00，
    覆盖的正是「昨天一整天的工作」。
    CHANGELOG 条目没有时刻，只有日期，故按「条目日期 >= 窗口起始日的日期」纳入。

用法
    python scripts/collect_daily_changes.py                    # 输出 Markdown 到 stdout
    python scripts/collect_daily_changes.py --hours 24 --out <file>
    python scripts/collect_daily_changes.py --json             # 机器可读，供发布脚本消费

退出码：0 = 成功（即使内容为空）；1 = 仓库不可用。
"""
import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "docs" / "v0.1" / "development" / "CHANGELOG.md"

# CHANGELOG 条目：`## YYYY-MM-DD 标题`，正文是 `- ` 开头的要点。
# 实际文件混用 `#` / `##` 两级标题（2026-10-20 起新条目写成 `#`），
# 只认 `##` 会静默漏报整条 —— 2026-10-21 就因为这条正则把当日 4 条记成 0 条。
_ENTRY_RE = re.compile(r"^#{1,3}\s+(\d{4}-\d{2}-\d{2})\s+(.+?)\s*$", re.M)
# 另一种写法：直接以日期开头的列项 `- 2026-10-20 · 标题：正文`
_DATED_BULLET_RE = re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})\s*[·:：]\s*(.+?)\s*$", re.M)
_BULLET_RE = re.compile(r"^-\s+(.+?)\s*$", re.M)

# 这些提交是「记账/同步」类的机械提交，对读者没有信息量，默认折叠
NOISE_PREFIXES = ("记忆：", "记忆:", "sync", "Sync", "chore", "chore:")
NOISE_CONTAINS = ("账本与索引同步", "索引同步", "文档索引同步")

# 段落式条目的摘要上限（字符）。CHANGELOG 里两种写法混用：
# 有的条目用 `- ` 要点列表，有的是整段叙述 —— 后者取段落拼成摘要，避免整条空白。
PARA_SUMMARY_LIMIT = 320

MAX_CHANGELOG_ENTRIES = 20
MAX_BULLETS_PER_ENTRY = 3
MAX_COMMITS = 40


def run_git(args: list[str]) -> str:
    """跑 git 并返回 stdout；失败返回空串（调用方按「无内容」处理）。"""
    try:
        proc = subprocess.run(
            ["git", "-c", "core.quotepath=false", *args],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return proc.stdout if proc.returncode == 0 else ""


def parse_changelog(since_date: str) -> list[dict]:
    """取 CHANGELOG 里日期 >= since_date 的条目。

    文件大体「最新在最上面」，但尾部还混着后来追记的日期列项，所以不能
    碰到第一条更早的就 break —— 改成按位置排序后逐条按日期过滤。
    """
    if not CHANGELOG.is_file():
        return []
    text = CHANGELOG.read_text(encoding="utf-8", errors="ignore")
    spans: list[tuple[int, int, str, str, str]] = []
    for m in _ENTRY_RE.finditer(text):
        spans.append((m.start(), m.end(), m.group(1), m.group(2), "heading"))
    for m in _DATED_BULLET_RE.finditer(text):
        spans.append((m.start(), m.end(), m.group(1), m.group(2), "bullet"))
    spans.sort(key=lambda s: s[0])

    entries: list[dict] = []
    for i, (start, end, date, raw_title, kind) in enumerate(spans):
        if date < since_date:
            continue
        body_end = spans[i + 1][0] if i + 1 < len(spans) else len(text)
        body = text[end:body_end]
        title = raw_title
        seeded: list[str] = []
        if kind == "bullet":
            # 列项写成「- 日期 · 分类：正文」，把分类当标题、正文当要点。
            # 没有冒号时退一步按首个逗号切（如「[基地发电机总电源](…)，POWER-SYSTEM r2」）。
            plain_title = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", raw_title)
            head, sep, tail = plain_title.partition("：")
            if not sep:
                head, sep, tail = plain_title.partition("，")
            if sep and tail.strip():
                title, seeded = head.strip(), [tail.strip()]
            else:
                title = plain_title
        bullets = [b.strip() for b in _BULLET_RE.findall(body)]
        bullets = [b for b in bullets if b]
        bullets = seeded + bullets
        is_paragraph = False
        if not bullets:
            # 段落式条目：把非空行拼成一段摘要，避免条目在发布页上显示为空
            paras = [ln.strip() for ln in body.splitlines() if ln.strip()]
            if paras:
                joined = " ".join(paras)
                # 摘要是纯文本：先把 markdown 链接降级成链接文字，
                # 避免截断后留下 `[文字](半截路径` 这种残缺语法。
                joined = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", joined)
                joined = re.sub(r"\s+", " ", joined).strip()
                if len(joined) > PARA_SUMMARY_LIMIT:
                    joined = joined[:PARA_SUMMARY_LIMIT].rstrip() + "…"
                bullets = [joined]
                is_paragraph = True
        entries.append(
            {
                "date": date,
                "title": title,
                "bullets": bullets[:MAX_BULLETS_PER_ENTRY],
                "bullet_total": len(bullets),
                "is_paragraph": is_paragraph,
            }
        )
        if len(entries) >= MAX_CHANGELOG_ENTRIES:
            break
    return entries


def is_noise(subject: str) -> bool:
    if subject.startswith(NOISE_PREFIXES):
        return True
    return any(k in subject for k in NOISE_CONTAINS)


def parse_commits(since_iso: str) -> tuple[list[dict], int]:
    """返回 (有信息量的提交, 被折叠的噪声提交数)。"""
    out = run_git(["log", f"--since={since_iso}", "--format=%h\t%ad\t%s", "--date=format:%m-%d %H:%M"])
    if not out.strip():
        return [], 0
    kept: list[dict] = []
    skipped = 0
    for line in out.splitlines():
        parts = line.split("\t", 2)
        if len(parts) < 3:
            continue
        sha, when, subject = parts
        if is_noise(subject):
            skipped += 1
            continue
        kept.append({"sha": sha, "when": when, "subject": subject})
    return kept[:MAX_COMMITS], skipped


def parse_worktree() -> dict:
    """未提交改动统计：按状态计数 + 按顶层路径分组。"""
    out = run_git(["status", "--porcelain"])
    if not out.strip():
        return {"total": 0, "by_state": {}, "by_area": []}
    by_state: dict[str, int] = {}
    by_area: dict[str, int] = {}
    total = 0
    for line in out.splitlines():
        if len(line) < 4:
            continue
        state = line[:2].strip() or "?"
        path = line[3:].strip().strip('"')
        total += 1
        key = {"??": "新增", "M": "修改", "D": "删除", "A": "新增", "R": "重命名"}.get(state, state)
        by_state[key] = by_state.get(key, 0) + 1
        head = "/".join(path.split("/")[:2]) if "/" in path else path
        by_area[head] = by_area.get(head, 0) + 1
    areas = sorted(by_area.items(), key=lambda kv: -kv[1])[:8]
    return {"total": total, "by_state": by_state, "by_area": areas}


def build(args) -> dict:
    now = datetime.now().astimezone()
    since = now - timedelta(hours=args.hours)
    since_date = since.strftime("%Y-%m-%d")
    since_iso = since.strftime("%Y-%m-%d %H:%M:%S")

    entries = parse_changelog(since_date)
    commits, noise = parse_commits(since_iso)
    worktree = parse_worktree()
    return {
        "generated_at": now.strftime("%Y-%m-%d %H:%M:%S"),
        "window_hours": args.hours,
        "window_since": since_iso,
        "window_since_date": since_date,
        "changelog_entries": entries,
        "commits": commits,
        "commits_folded": noise,
        "worktree": worktree,
    }


def render_markdown(data: dict, pkg: dict | None = None) -> str:
    lines: list[str] = []
    lines.append(f"# 弹壳风暴2 · 每日更新")
    lines.append("")
    lines.append(f"> 生成时间：{data['generated_at']}　|　统计窗口：过去 {data['window_hours']} 小时（自 {data['window_since']}）")
    if pkg:
        lines.append(
            f"> 安装包：`{pkg.get('name', 'ShellStorm2.exe')}`　{pkg.get('size_text', '')}　"
            f"SHA256 `{pkg.get('sha256', '')}`"
        )
    lines.append("")

    entries = data["changelog_entries"]
    lines.append("## 一、本轮更新内容")
    lines.append("")
    if entries:
        for e in entries:
            lines.append(f"### {e['date']} {e['title']}")
            lines.append("")
            for b in e["bullets"]:
                lines.append(f"- {b}")
            if e["bullet_total"] > len(e["bullets"]):
                lines.append(f"- …（该条目另有 {e['bullet_total'] - len(e['bullets'])} 条细节，见 CHANGELOG）")
            lines.append("")
    else:
        lines.append("_窗口内 CHANGELOG 没有新增条目。_")
        lines.append("")

    lines.append("## 二、同期提交记录")
    lines.append("")
    if data["commits"]:
        for c in data["commits"]:
            lines.append(f"- `{c['sha']}`　{c['when']}　{c['subject']}")
        if data["commits_folded"]:
            lines.append(f"- …（另有 {data['commits_folded']} 条记账/同步类提交已折叠）")
    else:
        lines.append("_窗口内没有提交。_")
    lines.append("")

    wt = data["worktree"]
    lines.append("## 三、工作区状态")
    lines.append("")
    if wt["total"]:
        state_text = "　".join(f"{k} {v}" for k, v in wt["by_state"].items())
        lines.append(f"- 未提交改动共 **{wt['total']}** 项：{state_text}")
        if wt["by_area"]:
            lines.append("- 主要集中：")
            for area, n in wt["by_area"]:
                lines.append(f"  - `{area}`　{n} 项")
        lines.append("")
        lines.append("> ⚠️ 本次安装包**包含上述未提交改动**（按工作区当前状态打包）。")
    else:
        lines.append("- 工作区干净，无未提交改动。")
    lines.append("")

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hours", type=int, default=24, help="统计窗口（小时），默认 24")
    parser.add_argument("--out", help="Markdown 输出路径；不给则打到 stdout")
    parser.add_argument("--json", action="store_true", help="输出 JSON（机器可读）")
    args = parser.parse_args()

    data = build(args)

    if args.json:
        payload = json.dumps(data, ensure_ascii=False, indent=2)
    else:
        payload = render_markdown(data)

    if args.out:
        Path(args.out).write_text(payload + "\n", encoding="utf-8")
        n_entries = len(data["changelog_entries"])
        n_commits = len(data["commits"])
        print(f"已写入 {args.out}")
        print(f"  CHANGELOG 条目 {n_entries} 条 / 提交 {n_commits} 条 / 未提交 {data['worktree']['total']} 项")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
