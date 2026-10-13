"""每日发布流水线：打包 → 验证 → 收集更新内容 → 生成更新文档 → 发布（覆盖同一链接）。

为什么验证放在发布之前（硬门禁）
    2026-10-12 实际发生过：导出的包启动即失败（`启动失败：Can't open`），
    而当时只看了「导出退出码 0 + 日志有 savepack 标记」就发出去了。
    **「导出成功」≠「能启动」**，所以本流水线里任何一步验证失败就
    **中止发布**并保留上一版线上包，宁可当天不发，也不发坏包。

验证顺序（全部通过才发布）
    ① 静态门禁：check_export_runtime_refs.py（运行时引用不得指向被排除目录）
    ② 静态门禁：check_fixture_shadow_casting.py（灯具外壳必须有运行时兜底）
    ③ 隔离冒烟：smoke_exported_pack.py（隔离 APPDATA 跑包，不动真实存档）

产物
    <输出目录>/ShellStorm2.exe            安装包
    <输出目录>/index.html                 入口页＝更新文档（网页）
    <输出目录>/更新日志_<日期>.md          更新文档（Markdown 存档版）

用法
    python scripts/daily_release.py                    # 全流程
    python scripts/daily_release.py --skip-publish     # 只打包+验证+生成，不上传
    python scripts/daily_release.py --skip-build       # 复用已有 exe，验证+生成+发布
    python scripts/daily_release.py --site-id <ID>     # 覆盖指定站点

退出码：0 = 成功；非 0 = 失败（未发布或发布未通过校验）。
"""
import argparse
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT.parent / "ShellStorm2-work"
DEFAULT_OUT = WORK / "outputs" / "daily_release"
DEFAULT_SITE_ID = "shellstorm2-20261012-190519"
PRESET = "Windows Desktop"
EXE_NAME = "ShellStorm2.exe"

SKILL_CANDIDATES = [
    Path.home() / ".workbuddy" / "skills" / "sofunny-resource-sharing" / "scripts" / "publish.py",
    Path.home() / ".codex" / "skills" / "sofunny-resource-sharing" / "scripts" / "publish.py",
    Path.home() / ".agents" / "skills" / "sofunny-resource-sharing" / "scripts" / "publish.py",
    Path.home() / ".claude" / "skills" / "sofunny-resource-sharing" / "scripts" / "publish.py",
]

# 运行时嵌入包布局：尾部 4B magic 'GDPC'，其前 8B 为 pck 数据长度(u64)
_EMBED_TAIL = 12


def log(msg: str) -> None:
    print(f"[daily-release] {msg}", flush=True)


def find_publish_script() -> Path | None:
    for p in SKILL_CANDIDATES:
        if p.is_file():
            return p
    return None


# Godot 可执行：自动化环境与交互式 shell 的 PATH 可能不同，逐级回退。
GODOT_FALLBACKS = [
    Path(r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"),
    Path(r"I:\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64.exe"),
    Path.home() / "bin" / "godot.cmd",
]


def resolve_godot() -> str:
    """按 GODOT_BIN → 已知安装路径 → PATH 的顺序定位 Godot。"""
    env = os.environ.get("GODOT_BIN")
    if env and Path(env).is_file():
        return env
    for c in GODOT_FALLBACKS:
        if c.is_file():
            return str(c)
    return "godot"


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", **kw)


# ---------------------------------------------------------------- ① 打包

def build(out_dir: Path) -> Path:
    exe = out_dir / EXE_NAME
    if exe.exists():
        exe.unlink()
    godot = resolve_godot()
    log(f"开始导出（预设 {PRESET}，引擎 {godot}）…")
    try:
        proc = run(
            [godot, "--headless", "--path", str(ROOT),
             "--export-release", PRESET, str(exe)],
            cwd=ROOT, timeout=3600,
        )
    except OSError as exc:
        raise RuntimeError(f"无法执行 Godot（{godot}）：{exc}") from exc
    if proc.returncode != 0 or not exe.is_file():
        raise RuntimeError(
            f"导出失败（退出码 {proc.returncode}）\n{(proc.stdout or '')[-2000:]}\n{(proc.stderr or '')[-2000:]}"
        )
    log(f"导出完成：{exe.name}  {exe.stat().st_size/1048576:.1f} MiB")
    return exe


# ---------------------------------------------------------------- ② 验证

def gate_scripts() -> list[str]:
    names = ("check_export_runtime_refs.py", "check_fixture_shadow_casting.py")
    found = [str(ROOT / "scripts" / n) for n in names if (ROOT / "scripts" / n).is_file()]
    return found


def verify(exe: Path) -> None:
    failures: list[str] = []

    for script in gate_scripts():
        proc = run([sys.executable, script], cwd=ROOT, timeout=300)
        tail = (proc.stdout or "").strip().splitlines()
        verdict = tail[-1] if tail else ""
        if proc.returncode == 0:
            log(f"门禁通过：{Path(script).name}  ({verdict})")
        else:
            failures.append(f"{Path(script).name} 退出码 {proc.returncode}\n" +
                            "\n".join(tail[-15:]))

    smoke = ROOT / "scripts" / "smoke_exported_pack.py"
    if smoke.is_file():
        proc = run([sys.executable, str(smoke), str(exe)], cwd=ROOT, timeout=1800)
        tail = (proc.stdout or "").strip().splitlines()
        if proc.returncode == 0:
            log("隔离冒烟通过（SMOKE_OK，未触碰真实存档）")
        else:
            failures.append(f"隔离冒烟失败（退出码 {proc.returncode}）\n" + "\n".join(tail[-20:]))
    else:
        failures.append("找不到 smoke_exported_pack.py，无法做启动冒烟")

    if failures:
        raise RuntimeError("验证未通过，已中止发布（线上保持上一版）：\n\n" + "\n\n".join(failures))
    log("全部验证通过")


# ---------------------------------------------------------------- ③ 收集

def collect(hours: int) -> dict:
    script = ROOT / "scripts" / "collect_daily_changes.py"
    proc = run([sys.executable, str(script), "--json", "--hours", str(hours)],
               cwd=ROOT, timeout=300)
    if proc.returncode != 0 or not (proc.stdout or "").strip():
        raise RuntimeError(f"收集更新内容失败：{(proc.stdout or '')[-800:]}{(proc.stderr or '')[-800:]}")
    return json.loads(proc.stdout)


def pkg_info(exe: Path) -> dict:
    size = exe.stat().st_size
    h = hashlib.sha256()
    with open(exe, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return {
        "name": exe.name,
        "bytes": size,
        "size_text": f"{size / 1048576:.1f} MiB",
        "sha256": h.hexdigest(),
    }


# ---------------------------------------------------------------- ④ 生成文档

def render_md(data: dict, pkg: dict, site_id: str, base_url: str) -> str:
    L: list[str] = []
    L.append("# 弹壳风暴2 · 每日更新")
    L.append("")
    L.append(f"> 生成时间：{data['generated_at']}　|　统计窗口：过去 {data['window_hours']} 小时"
             f"（自 {data['window_since']}）")
    L.append(f"> 安装包：`{pkg['name']}`　{pkg['size_text']}　SHA256 `{pkg['sha256']}`")
    L.append(f"> 下载：{base_url}/{site_id}.exe")
    L.append("")

    L.append("## 一、本轮更新内容")
    L.append("")
    entries = data["changelog_entries"]
    if entries:
        for e in entries:
            L.append(f"### {e['date']} {e['title']}")
            L.append("")
            for b in e["bullets"]:
                L.append(f"- {b}")
            rest = e["bullet_total"] - len(e["bullets"])
            if rest > 0:
                L.append(f"- …（另有 {rest} 条细节，见项目 CHANGELOG）")
            L.append("")
    else:
        L.append("_窗口内 CHANGELOG 没有新增条目。_")
        L.append("")

    L.append("## 二、同期提交记录")
    L.append("")
    if data["commits"]:
        for c in data["commits"]:
            L.append(f"- `{c['sha']}`　{c['when']}　{c['subject']}")
        if data["commits_folded"]:
            L.append(f"- …（另有 {data['commits_folded']} 条记账/同步类提交已折叠）")
    else:
        L.append("_窗口内没有提交。_")
    L.append("")

    wt = data["worktree"]
    L.append("## 三、工作区状态")
    L.append("")
    if wt["total"]:
        state = "　".join(f"{k} {v}" for k, v in wt["by_state"].items())
        L.append(f"- 未提交改动共 **{wt['total']}** 项：{state}")
        if wt["by_area"]:
            L.append("- 主要集中：")
            for area, n in wt["by_area"]:
                L.append(f"  - `{area}`　{n} 项")
        L.append("")
        L.append("> ⚠️ 本安装包**包含上述未提交改动**（按工作区当前状态打包）。")
    else:
        L.append("- 工作区干净，无未提交改动。")
    L.append("")
    return "\n".join(L)


def md_inline(text: str) -> str:
    """极简行内 Markdown → HTML：转义 → 反引号代码 → 粗体 → 链接。"""
    out = html.escape(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"<span class='ref'>\1</span>", out)
    return out


def render_html(data: dict, pkg: dict, site_id: str, base_url: str) -> str:
    dl = f"{base_url}/{site_id}.exe"
    parts: list[str] = []
    parts.append(f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>弹壳风暴2 · 下载与更新日志</title>
<style>
:root {{ color-scheme: light dark; }}
* {{ box-sizing: border-box; }}
body {{ margin:0; padding:2.5rem 1.25rem 4rem; font:15px/1.7 -apple-system,"PingFang SC","Microsoft YaHei",system-ui,sans-serif; }}
main {{ max-width:54rem; margin:0 auto; }}
h1 {{ font-size:1.6rem; margin:0 0 .3rem; letter-spacing:.01em; }}
.sub {{ opacity:.6; font-size:.86rem; margin:0 0 1.8rem; }}
.dl {{ display:block; text-decoration:none; border:1px solid rgba(128,128,128,.35); border-radius:12px;
      padding:1.1rem 1.3rem; margin:0 0 2rem; }}
.dl:hover {{ border-color:rgba(128,128,128,.7); }}
.dl .t {{ font-weight:700; font-size:1.05rem; }}
.dl .m {{ opacity:.65; font-size:.84rem; margin-top:.3rem; word-break:break-all; }}
h2 {{ font-size:1.05rem; margin:2.2rem 0 .9rem; padding-bottom:.4rem;
      border-bottom:1px solid rgba(128,128,128,.3); }}
h3 {{ font-size:.97rem; margin:1.5rem 0 .5rem; }}
ul {{ margin:.2rem 0 .2rem 1.1rem; padding:0; }}
li {{ margin:.34rem 0; }}
code {{ font-family:ui-monospace,Menlo,Consolas,monospace; font-size:.86em;
        background:rgba(128,128,128,.16); padding:.1em .38em; border-radius:4px; word-break:break-all; }}
.hash {{ font-size:.75rem; opacity:.55; word-break:break-all; }}
.note {{ opacity:.6; font-size:.82rem; margin-top:2.5rem; padding-top:1rem;
         border-top:1px solid rgba(128,128,128,.25); }}
.warn {{ border-left:3px solid rgba(200,140,40,.75); padding:.5rem .9rem; margin:.8rem 0;
         background:rgba(200,140,40,.08); font-size:.86rem; }}
.ref {{ opacity:.75; }}
</style></head><body><main>
<h1>弹壳风暴2</h1>
<p class="sub">每日自动打包发布　·　{html.escape(data['generated_at'])}</p>

<a class="dl" href="{html.escape(EXE_NAME)}">
  <div class="t">↓ 下载 {html.escape(pkg['name'])}　<span style="font-weight:400;opacity:.7">{pkg['size_text']}</span></div>
  <div class="m">SHA256 {pkg['sha256']}</div>
</a>
""")

    entries = data["changelog_entries"]
    parts.append("<h2>一、本轮更新内容</h2>")
    if entries:
        for e in entries:
            parts.append(f"<h3>{html.escape(e['date'])} {md_inline(e['title'])}</h3><ul>")
            for b in e["bullets"]:
                parts.append(f"<li>{md_inline(b)}</li>")
            rest = e["bullet_total"] - len(e["bullets"])
            if rest > 0:
                parts.append(f"<li style='opacity:.6'>…（另有 {rest} 条细节，见项目 CHANGELOG）</li>")
            parts.append("</ul>")
    else:
        parts.append("<p style='opacity:.6'>窗口内 CHANGELOG 没有新增条目。</p>")

    parts.append("<h2>二、同期提交记录</h2><ul>")
    if data["commits"]:
        for c in data["commits"]:
            parts.append(
                f"<li><code>{html.escape(c['sha'])}</code>　{html.escape(c['when'])}　"
                f"{md_inline(c['subject'])}</li>"
            )
        if data["commits_folded"]:
            parts.append(
                f"<li style='opacity:.6'>…（另有 {data['commits_folded']} 条记账/同步类提交已折叠）</li>"
            )
    else:
        parts.append("<li style='opacity:.6'>窗口内没有提交。</li>")
    parts.append("</ul>")

    wt = data["worktree"]
    parts.append("<h2>三、工作区状态</h2>")
    if wt["total"]:
        state = "　".join(f"{html.escape(k)} {v}" for k, v in wt["by_state"].items())
        parts.append(f"<ul><li>未提交改动共 <strong>{wt['total']}</strong> 项：{state}</li>")
        if wt["by_area"]:
            parts.append("<li>主要集中：<ul>")
            for area, n in wt["by_area"]:
                parts.append(f"<li><code>{html.escape(area)}</code>　{n} 项</li>")
            parts.append("</ul></li></ul>")
        else:
            parts.append("</ul>")
        parts.append('<div class="warn">⚠️ 本安装包<strong>包含上述未提交改动</strong>（按工作区当前状态打包）。</div>')
    else:
        parts.append("<ul><li>工作区干净，无未提交改动。</li></ul>")

    parts.append(
        '<p class="note">本页由每日发布流水线自动生成。链接为内网 HTTPS 能力链接，'
        '任何持有该链接的人都可下载。首次运行 Windows 可能提示 SmartScreen，'
        '选择「更多信息 → 仍要运行」即可。</p>\n</main></body></html>'
    )
    return "\n".join(parts)


# ---------------------------------------------------------------- ⑤ 发布

def publish(out_dir: Path, publish_py: Path, site_id: str) -> str:
    """用 --site-id 显式覆盖同一站点（保证 URL 不变）。返回本次发布输出。"""
    proc = run([sys.executable, str(publish_py), "server", str(out_dir), "--site-id", site_id],
               cwd=publish_py.parent.parent, timeout=3600)
    out = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 or "发布成功" not in out:
        raise RuntimeError(f"发布失败（退出码 {proc.returncode}）：\n{out[-2000:]}")
    return out.strip()


def verify_online(url: str, expect_bytes: int) -> str:
    """实测线上链接：状态码、Content-Length 必须与本地一致。"""
    req = urllib.request.Request(url, method="HEAD",
                                 headers={"User-Agent": "daily-release/1"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        code = resp.status
        length = resp.headers.get("Content-Length")
    if not (200 <= code < 400):
        raise RuntimeError(f"线上校验失败：HTTP {code}")
    if length is not None and int(length) != expect_bytes:
        raise RuntimeError(f"线上文件大小不一致：服务器 {length} ≠ 本地 {expect_bytes}")
    return f"HTTP {code}，Content-Length={length}"


# ---------------------------------------------------------------- main

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site-id", default=DEFAULT_SITE_ID, help=f"要覆盖的站点（默认 {DEFAULT_SITE_ID}）")
    parser.add_argument("--hours", type=int, default=24, help="更新内容统计窗口（小时）")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT), help="输出目录")
    parser.add_argument("--skip-build", action="store_true", help="复用已有 exe，跳过导出")
    parser.add_argument("--skip-publish", action="store_true", help="只打包+验证+生成，不上传")
    parser.add_argument("--base-url", default="https://sofunny-resource-sharing.hnfunny.com")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    exe = out_dir / EXE_NAME

    try:
        if args.skip_build:
            if not exe.is_file():
                raise RuntimeError(f"--skip-build 但找不到已有包：{exe}")
            log(f"复用已有包：{exe}（{exe.stat().st_size/1048576:.1f} MiB）")
        else:
            exe = build(out_dir)

        verify(exe)

        data = collect(args.hours)
        pkg = pkg_info(exe)
        log(f"包信息：{pkg['size_text']}  sha256={pkg['sha256'][:16]}…")
        log(f"更新内容：CHANGELOG {len(data['changelog_entries'])} 条 / "
            f"提交 {len(data['commits'])} 条 / 未提交 {data['worktree']['total']} 项")

        stamp = datetime.now().strftime("%Y-%m-%d")
        md_path = out_dir / f"更新日志_{stamp}.md"
        md_path.write_text(render_md(data, pkg, args.site_id, args.base_url), encoding="utf-8")
        for old in out_dir.glob("更新日志_*.md"):
            if old.name != md_path.name:
                old.unlink()
        html_path = out_dir / "index.html"
        html_path.write_text(render_html(data, pkg, args.site_id, args.base_url), encoding="utf-8")
        log(f"已生成更新文档：{md_path.name} + index.html")

        if args.skip_publish:
            log("--skip-publish：不上传。产物目录 " + str(out_dir))
            print("\n" + render_md(data, pkg, args.site_id, args.base_url))
            return 0

        publish_py = find_publish_script()
        if publish_py is None:
            raise RuntimeError("找不到 sofunny-resource-sharing 的 publish.py")
        out = publish(out_dir, publish_py, args.site_id)
        log("发布输出：\n" + out)

        direct = f"{args.base_url}/{args.site_id}.exe"
        info = verify_online(direct, pkg["bytes"])
        log(f"线上校验通过：{direct}  （{info}）")

        print()
        print("=" * 66)
        print(f"每日发布完成　{data['generated_at']}")
        print(f"  下载直链 : {direct}")
        print(f"  更新页   : {args.base_url}/{args.site_id}/")
        print(f"  包大小   : {pkg['size_text']}")
        print(f"  SHA256   : {pkg['sha256']}")
        print("=" * 66)
        return 0

    except Exception as exc:  # noqa: BLE001 — 这是编排入口，需把一切失败都转成非零退出
        print(f"\n{'!' * 66}\n失败：{exc}\n{'!' * 66}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
