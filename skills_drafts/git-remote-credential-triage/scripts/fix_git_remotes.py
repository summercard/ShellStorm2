"""
Fork 仓库 HTTPS -> SSH 远程地址切换（含备份与回滚）

用法:
    python fix_git_remotes.py            # 只备份 + 干跑（不改动任何仓库）
    python fix_git_remotes.py --apply    # 备份后实际切换（逐个 SSH 验证通过才改）

安全设计:
  1. 永远先备份：每个仓库的 .git/config 与全局 ~/.gitconfig 都会复制到备份目录
  2. 逐个用 `git ls-remote` 验证 SSH 可达，失败则跳过、保持 HTTPS 不动
  3. 生成 restore.py，可一键回滚到原始地址
"""

import os
import re
import sys
import json
import shutil
import subprocess
from datetime import datetime

APPLY = "--apply" in sys.argv

TOML = r"C:\Users\zhuangmenghong\AppData\Local\ForkData\repositories.toml"
GITCONFIG = r"C:\Users\zhuangmenghong\.gitconfig"
GIT = r"C:\Program Files\Git\cmd\git.exe"
BASE = r"I:\tools\.workbuddy\backup\2026-09-25_git-remote-fix"

# 这些不用切：私有且当前密钥无权限
EXCLUDE = {"summercard/match3-cocos"}

HTTPS_GH = re.compile(
    r"^https?://(?:[^@/]+@)?github\.com/([^/]+)/(.+?)(?:\.git)?/?$"
)


def repo_slug(path: str) -> str:
    s = re.sub(r"[^0-9A-Za-z]+", "_", path).strip("_")
    return s[-70:]


def run(args, cwd=None):
    return subprocess.run(
        args, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
        errors="replace",
    )


def to_ssh(url: str):
    """https github 地址转 ssh 地址；返回 (owner/repo, ssh_url) 或 None"""
    m = HTTPS_GH.match(url.strip())
    if not m:
        return None
    owner, repo = m.group(1), m.group(2)
    repo = repo[:-4] if repo.endswith(".git") else repo
    return f"{owner}/{repo}", f"git@github.com:{owner}/{repo}.git"


def ssh_reachable(ssh_url: str) -> bool:
    env = dict(os.environ)
    env["GIT_SSH_COMMAND"] = (
        "ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10"
    )
    env["GIT_TERMINAL_PROMPT"] = "0"
    r = subprocess.run(
        [GIT, "ls-remote", ssh_url, "HEAD"],
        capture_output=True, text=True, env=env,
    )
    return r.returncode == 0


# ---------- 1. 收集目标仓库 ----------
paths = re.findall(r"path = '(.*?)'", open(TOML, encoding="utf-8").read())
targets = []          # (repo_path, remote_name, old_url, key, new_url, note)
skipped = []

for p in paths:
    if not os.path.isfile(os.path.join(p, ".git", "config")):
        continue
    r = run([GIT, "remote"], cwd=p)
    if r.returncode != 0:
        continue
    for name in r.stdout.split():
        g = run([GIT, "remote", "get-url", name], cwd=p)
        url = g.stdout.strip()
        if not url:
            continue
        conv = to_ssh(url)
        if not conv:
            if url.startswith("http") and "github.com" not in url:
                skipped.append((p, name, url, "非 GitHub，保持原样"))
            continue
        key, new = conv
        if key in EXCLUDE:
            skipped.append((p, name, url, f"{key} 在排除名单，保持 HTTPS"))
            continue
        note = "原地址内嵌明文凭据，将一并清除" if "@github.com" in url.split("//")[1] else ""
        targets.append((p, name, url, key, new, note))

print("=" * 100)
print(f"待切换远程 {len(targets)} 个 / 跳过 {len(skipped)} 个")
print("=" * 100)
for p, name, old, key, new, note in targets:
    print(f"[{name}] {key}")
    print(f"    {old}")
    print(f" -> {new}" + (f"   ({note})" if note else ""))
if skipped:
    print("\n--- 跳过 ---")
    for p, name, url, why in skipped:
        print(f"    {url}\n      {why}")

# ---------- 2. 备份 ----------
os.makedirs(BASE, exist_ok=True)
manifest = {
    "created": datetime.now().isoformat(timespec="seconds"),
    "applied": APPLY,
    "gitconfig_backup": None,
    "entries": [],
}

if os.path.isfile(GITCONFIG):
    dst = os.path.join(BASE, "gitconfig.bak")
    shutil.copy2(GITCONFIG, dst)
    manifest["gitconfig_backup"] = dst
    print(f"\n[备份] 全局配置 -> {dst}")

for p, name, old, key, new, note in targets:
    slug = repo_slug(p)
    d = os.path.join(BASE, "repos", slug)
    os.makedirs(d, exist_ok=True)
    shutil.copy2(os.path.join(p, ".git", "config"), os.path.join(d, "config.bak"))
    manifest["entries"].append(
        {"path": p, "remote": name, "old_url": old, "new_url": new, "key": key}
    )

with open(os.path.join(BASE, "manifest.json"), "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)

# 回滚脚本
restore = '''"""回滚：把远程地址恢复成备份时的样子。用法: python restore.py"""
import json, os, subprocess
BASE = os.path.dirname(os.path.abspath(__file__))
GIT = r"C:\\Program Files\\Git\\cmd\\git.exe"
m = json.load(open(os.path.join(BASE, "manifest.json"), encoding="utf-8"))
for e in m["entries"]:
    subprocess.run([GIT, "remote", "set-url", e["remote"], e["old_url"]],
                   cwd=e["path"], check=False)
    print(f"已回滚 {e['remote']} -> {e['old_url']}  ({e['path']})")
print("\\n回滚完成。如还需恢复全局配置，请手动执行：")
print(f'  copy "{m["gitconfig_backup"]}" "%USERPROFILE%\\.gitconfig"')
'''
with open(os.path.join(BASE, "restore.py"), "w", encoding="utf-8") as f:
    f.write(restore)

print(f"[备份] {len(manifest['entries'])} 个仓库的 .git/config -> {BASE}\\repos")
print(f"[备份] 清单 -> {BASE}\\manifest.json")
print(f"[备份] 回滚脚本 -> {BASE}\\restore.py")

if not APPLY:
    print("\n>>> 干跑结束，未改动任何仓库。加 --apply 才会真正切换。")
    sys.exit(0)

# ---------- 3. 逐个验证并切换 ----------
print("\n" + "=" * 100)
print("开始逐个验证并切换")
print("=" * 100)
ok = fail = 0
for p, name, old, key, new, note in targets:
    if old == new:
        print(f"已是 SSH，跳过  {key}")
        continue
    if not ssh_reachable(new):
        fail += 1
        print(f"[失败] SSH 不可达，保持原样  {key}")
        continue
    r = run([GIT, "remote", "set-url", name, new], cwd=p)
    if r.returncode == 0:
        ok += 1
        print(f"[成功] {key}  已切换为 SSH")
    else:
        fail += 1
        print(f"[失败] set-url 出错  {key}: {r.stderr.strip()}")

print("\n" + "=" * 100)
print(f"切换完成：成功 {ok} 个，跳过/失败 {fail} 个")
print(f"备份目录：{BASE}")
