#!/usr/bin/env python3
"""Gate registered art packages against prior ledger IDs and file hashes.

Usage: python3 scripts/asset_guard.py <package> --classify version_increment
A duplicate without an explicit reuse/replacement/version classification exits 2.
"""
import argparse
import json
from pathlib import Path


CLASSIFICATIONS = {'reuse', 'replacement', 'version_increment', 'child_variant'}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('package', type=Path)
    parser.add_argument('--classify', choices=sorted(CLASSIFICATIONS))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    package = args.package.resolve()
    ledgers = sorted(root.glob('assets/art/**/character_transfer_ledger_v*.json'))
    current_path = package / f'character_transfer_ledger_{package.name}.json'
    if current_path not in ledgers or not current_path.is_file():
        raise SystemExit(f'Missing registered package ledger: {current_path}')
    current = json.loads(current_path.read_text())
    current_hashes = {entry['sha256']: entry['path'] for entry in current.get('files', [])}
    same_id = []
    same_hash = []
    for path in ledgers:
        if path == current_path:
            continue
        try:
            ledger = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if ledger.get('asset_id') == current.get('asset_id'):
            same_id.append(str(path.relative_to(root)))
        for entry in ledger.get('files', []):
            digest = entry.get('sha256')
            if digest in current_hashes:
                same_hash.append({
                    'current': current_hashes[digest],
                    'existing': entry.get('path'),
                    'ledger': str(path.relative_to(root)),
                    'sha256': digest,
                })
    duplicates = bool(same_id or same_hash)
    allowed = not duplicates or args.classify in CLASSIFICATIONS
    report = {
        'asset_id': current.get('asset_id'),
        'version': package.name,
        'classification': args.classify,
        'duplicates_found': duplicates,
        'same_asset_id_ledgers': same_id,
        'identical_registered_files': same_hash,
        'passed': allowed,
    }
    output = root / 'outputs/asset_guard' / f"{current.get('asset_id','unknown')}_{package.name}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    current['duplicate_gate'] = {
        'classification': args.classify,
        'passed': allowed,
        'report': str(output.relative_to(root)),
        'same_asset_id_count': len(same_id),
        'identical_registered_file_count': len(same_hash),
    }
    current_path.write_text(json.dumps(current, ensure_ascii=False, indent=2))
    print('ASSET_GUARD_PASS' if allowed else 'ASSET_GUARD_BLOCK', output.relative_to(root))
    if not allowed:
        raise SystemExit(2)


if __name__ == '__main__':
    main()
