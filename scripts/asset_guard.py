#!/usr/bin/env python3
"""Gate registered art packages against prior ledger IDs and file hashes.

Usage: python3 scripts/asset_guard.py <package> --classify version_increment
A duplicate without an explicit reuse/replacement/version classification exits 2.

`<package>` 是**资产包目录**。脚本先在该目录里找本包的登记账本，命中顺序：

  1. ``<package>/character_transfer_ledger_<package.name>.json``  ← 角色域：版本包目录（如 production/v021/）
  2. ``<package>/character_transfer_ledger.json``                 ← 敌人等域：资产包根
  3. ``<package>/runtime/character_transfer_ledger.json``         ← 敌人等域：runtime 子目录

只有「找得到登记账本」的包才受门禁约束（角色域当前唯一实现；敌人域 2026-09-20 起接入）。
重复判定两路：同 AssetID、任一同哈希文件。命中重复时必须显式 ``--classify`` 归类，
否则 exit 2 —— 「同 AssetID / 同哈希不是自动错误，但必须归类并留报告」。

哈希清单兼容两种登记形态（跨域 schema 尚未统一，取并集即可）：
  * ``files: [{path, sha256, ...}]`` / ``runtime_files: [...]``（角色 / 敌人）
  * ``outputs: {path: sha256}`` / ``source_sha256: {path: sha256}``（敌人早期形态）
"""
import argparse
import json
from pathlib import Path


CLASSIFICATIONS = {'reuse', 'replacement', 'version_increment', 'child_variant'}

# 两种登记文件命名并存：角色域带版本号，敌人等域走恒定名。
LEDGER_GLOBS = (
    'assets/art/**/character_transfer_ledger_v*.json',
    'assets/art/**/character_transfer_ledger.json',
)
# 本包登记账本的候选位置，按优先级排列。
CURRENT_LEDGER_CANDIDATES = (
    'character_transfer_ledger_{name}.json',
    'character_transfer_ledger.json',
    'runtime/character_transfer_ledger.json',
)


def _norm_rel(value: str) -> str:
    """把账本里可能出现的 Windows 反斜杠路径统一成正斜杠，便于跨机比对。"""
    return str(value).replace('\\', '/') if value else ''


def _hash_entries(ledger: dict) -> dict[str, str]:
    """收集 {sha256_lower: path}，兼容 files / runtime_files / outputs / source_sha256。"""
    entries: dict[str, str] = {}

    def add(sha, path) -> None:
        digest = str(sha or '').strip().lower()
        if len(digest) != 64:
            return
        entries.setdefault(digest, _norm_rel(path))

    for key in ('files', 'runtime_files'):
        for entry in ledger.get(key) or []:
            if isinstance(entry, dict):
                add(entry.get('sha256'), entry.get('path'))
    for key in ('outputs', 'source_sha256'):
        mapping = ledger.get(key) or {}
        if isinstance(mapping, dict):
            for path, sha in mapping.items():
                add(sha, path)
    return entries


def _discover_ledgers(root: Path) -> list[Path]:
    found: set[Path] = set()
    for pattern in LEDGER_GLOBS:
        found.update(root.glob(pattern))
    return sorted(found)


def _resolve_current(package: Path) -> Path | None:
    for candidate in CURRENT_LEDGER_CANDIDATES:
        path = package / candidate.format(name=package.name)
        if path.is_file():
            return path
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('package', type=Path)
    parser.add_argument('--classify', choices=sorted(CLASSIFICATIONS))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    package = args.package.resolve()
    ledgers = _discover_ledgers(root)
    current_path = _resolve_current(package)
    if current_path is None or current_path not in ledgers:
        tried = ' / '.join(
            str((package / c.format(name=package.name)).relative_to(root))
            for c in CURRENT_LEDGER_CANDIDATES
        )
        raise SystemExit(f'Missing registered package ledger for {package.relative_to(root)}; tried: {tried}')
    current = json.loads(current_path.read_text(encoding='utf-8'))
    current_hashes = _hash_entries(current)
    same_id = []
    same_hash = []
    for path in ledgers:
        if path == current_path:
            continue
        try:
            ledger = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            continue
        if ledger.get('asset_id') == current.get('asset_id'):
            same_id.append(str(path.relative_to(root)))
        for digest, owner in _hash_entries(ledger).items():
            if digest in current_hashes:
                same_hash.append({
                    'current': current_hashes[digest],
                    'existing': owner,
                    'ledger': str(path.relative_to(root)),
                    'sha256': digest,
                })
    duplicates = bool(same_id or same_hash)
    allowed = not duplicates or args.classify in CLASSIFICATIONS
    report = {
        'asset_id': current.get('asset_id'),
        'package': str(package.relative_to(root)),
        'ledger': str(current_path.relative_to(root)),
        'classification': args.classify,
        'duplicates_found': duplicates,
        'same_asset_id_ledgers': same_id,
        'identical_registered_files': same_hash,
        'passed': allowed,
    }
    output = root / 'outputs/asset_guard' / f"{current.get('asset_id', 'unknown')}_{package.name}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    current['duplicate_gate'] = {
        'classification': args.classify,
        'passed': allowed,
        'report': str(output.relative_to(root)),
        'same_asset_id_count': len(same_id),
        'identical_registered_file_count': len(same_hash),
    }
    current_path.write_text(json.dumps(current, ensure_ascii=False, indent=2), encoding='utf-8')
    print('ASSET_GUARD_PASS' if allowed else 'ASSET_GUARD_BLOCK', output.relative_to(root))
    if not allowed:
        raise SystemExit(2)


if __name__ == '__main__':
    main()
