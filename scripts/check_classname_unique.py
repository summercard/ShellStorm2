#!/usr/bin/env python3
"""门禁：res:// 内不得存在重复的 `class_name` 声明（类名抢注）。

背景（2026-09-21 二次踩坑，见 memory/2026-09-21/1725_气泡残影复发与类名抢注.md）
  Godot 的全局类名是**唯一**的。当 res:// 内有两个脚本声明同一个 `class_name`
  时，Godot 不报错，只在 `.godot/global_script_class_cache.cfg` 里留下**一个**
  `path` —— 谁被扫到最后谁赢，而且是**跨目录**的（`_scratch/` 里的副本会顶掉
  `src/` 里的真源）。
  后果：所有 `X.new()` / `var v: X` 都解析到那份副本，且**没有任何报错**。
  2026-09-21 实测症状：`src/ui/bubble/SpeechBubble3D.gd` 已改为不透明管线 +
  alpha 裁剪（防 TAA 残影），但 `_scratch/rv4/old_ok.gd` 抢注了同名类，缓存里
  `path` 指向副本 → 气泡残影"修复后又复发"，查代码无问题（真源是对的）。

本门禁只做一件事：扫 res:// 下所有 `.gd`，按 `class_name` 分组，只要有任一
组落在多个文件上 → 退出 1。

  * 无重复                → 退出 0（打印类名总数）
  * 有重复                → 退出 1（逐组打印文件清单 + 缓存里的实际指向）
  * `--strict`            → 额外把「快照/副本目录（`_scratch` 等）里声明了
                            `class_name`」也判为失败（哪怕当前没重名，也是隐患）

修复办法：把副本**移出 res://**（不是删），再跑一次
  <godot> --headless --path . --import
刷新 `.godot/global_script_class_cache.cfg`，然后复核本门禁 + 相关验收场景。

注：本脚本**尚未**接入 `scripts/run_verification_suite.sh`；如需纳入，
在套件里加 `python3 "${project_root}/scripts/check_classname_unique.py" || rc=$?`
即可（比照 check_asset_runtime_naming.py 的用法）。

用法：
  python3 scripts/check_classname_unique.py            # 检查
  python3 scripts/check_classname_unique.py --quiet    # 通过时静默
  python3 scripts/check_classname_unique.py --strict   # 快照目录声明类名也算失败
  python3 scripts/check_classname_unique.py --json     # 机器可读
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys

# 扫描时剪掉的目录（非 res:// 源码）：导入缓存、版本库、导出产物、用户数据。
SKIP_DIRS = {".godot", ".git", "Godot", "app_userdata"}

# 「快照/副本」目录特征 —— 这些目录里的 .gd 不该声明 class_name。
SNAPSHOT_HINTS = ("_scratch", ".before", "backup", "_bak", "old_ok")

CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)


def project_root() -> str:
    # scripts/ 的上一级即项目根（res:// 落盘位置）。
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def scan(root: str) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = collections.defaultdict(list)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".gd"):
                continue
            full = os.path.join(dirpath, fn)
            try:
                with open(full, "rb") as fh:
                    text = fh.read().decode("utf-8", "replace")
            except OSError:
                continue
            m = CLASS_RE.search(text)
            if m:
                rel = os.path.relpath(full, root).replace("\\", "/")
                groups[m.group(1)].append(rel)
    return groups


def cache_path_for(class_name: str, root: str) -> str:
    """从全局类缓存里读出该 class_name 实际被解析到的脚本路径（诊断用）。"""
    cfg = os.path.join(root, ".godot", "global_script_class_cache.cfg")
    if not os.path.isfile(cfg):
        return ""
    try:
        with open(cfg, "rb") as fh:
            text = fh.read().decode("utf-8", "replace")
    except OSError:
        return ""
    needle = '"class": &"%s"' % class_name
    idx = text.find(needle)
    if idx < 0:
        return ""
    m = re.search(r'"path":\s*"([^"]+)"', text[idx:])
    return m.group(1) if m else ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="通过时静默")
    ap.add_argument("--strict", action="store_true", help="快照目录声明类名也判失败")
    ap.add_argument("--json", action="store_true", dest="as_json", help="输出 JSON")
    args = ap.parse_args()

    root = project_root()
    groups = scan(root)

    duplicates = {k: v for k, v in groups.items() if len(v) > 1}
    snapshot_decls = {
        k: [rel for rel in v if any(h in rel for h in SNAPSHOT_HINTS)]
        for k, v in groups.items()
        if any(any(h in rel for h in SNAPSHOT_HINTS) for rel in v)
    }

    failed = bool(duplicates) or (args.strict and bool(snapshot_decls))

    if args.as_json:
        payload = {
            "class_count": len(groups),
            "duplicates": {k: sorted(v) for k, v in sorted(duplicates.items())},
            "resolved_paths": {k: cache_path_for(k, root) for k in duplicates},
            "snapshot_decls": {k: sorted(v) for k, v in sorted(snapshot_decls.items())},
            "ok": not failed,
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        if duplicates:
            for name in sorted(duplicates):
                print("CLASSNAME_UNIQUE_DUPLICATE class_name=%s count=%d"
                      % (name, len(duplicates[name])), file=sys.stderr)
                for rel in sorted(duplicates[name]):
                    print("    - res://%s" % rel, file=sys.stderr)
                resolved = cache_path_for(name, root)
                if resolved:
                    print("    (缓存实际指向: %s)" % resolved, file=sys.stderr)
        if snapshot_decls:
            tag = "CLASSNAME_UNIQUE_FORBIDDEN" if args.strict else "CLASSNAME_UNIQUE_WARN"
            for name in sorted(snapshot_decls):
                print("%s class_name=%s in snapshot dirs: %s"
                      % (tag, name, ", ".join(sorted(snapshot_decls[name]))),
                      file=sys.stderr)

    if failed:
        print("CLASSNAME_UNIQUE_CHECK_FAILED classes=%d duplicates=%d snapshot_decls=%d"
              % (len(groups), len(duplicates), len(snapshot_decls)), file=sys.stderr)
        return 1

    if not args.quiet:
        print("CLASSNAME_UNIQUE_CHECK_OK classes=%d duplicates=0" % len(groups))
    return 0


if __name__ == "__main__":
    sys.exit(main())
