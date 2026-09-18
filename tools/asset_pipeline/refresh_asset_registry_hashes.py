"""Refresh SHA-256 fields for valid, non-placeholder rows in the asset ledgers.

账本已按域拆开，所以这里遍历 ``assets/registry/ledger_index.json`` 声明的**全部**分账本：
每个域各写各的文件，互不阻塞 —— 这也是拆账本的目的之一。
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

from openpyxl import load_workbook

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from ledger_registry import LedgerIndex  # noqa: E402

SKIP_STATUSES = {"待制作", "程序占位", "弃用", "旧资产已从正式基地移除"}
ASSET_SHEET = "资产主表"
FIRST_DATA_ROW = 6


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def refresh_ledger(path: Path, root: Path, dry_run: bool) -> tuple[int, int, int]:
    workbook = load_workbook(path, data_only=False)
    ws = workbook[ASSET_SHEET]
    changed = skipped = missing = 0
    for row in range(FIRST_DATA_ROW, ws.max_row + 1):
        asset_id = str(ws.cell(row, 1).value or "").strip()
        if not asset_id:
            continue
        status = str(ws.cell(row, 11).value or "").strip()
        if status in SKIP_STATUSES:
            skipped += 1
            continue
        raw_path = str(ws.cell(row, 15).value or "").strip()
        if not raw_path or raw_path.startswith("="):
            missing += 1
            continue
        target = Path(raw_path)
        if not target.is_absolute():
            target = root / target
        if not target.is_file():
            missing += 1
            continue
        actual = sha256(target)
        if str(ws.cell(row, 20).value or "").strip().lower() != actual:
            ws.cell(row, 20).value = actual
            changed += 1
    if changed and not dry_run:
        workbook.save(path)
    return changed, skipped, missing


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ledger", help="只刷新某一个域（默认刷新全部）")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.project.resolve()
    index = LedgerIndex.load(root)
    domains = list(index.domains)
    if args.ledger:
        domains = [index.domain_for_key(args.ledger)]
    totals = [0, 0, 0]
    for domain in domains:
        if not domain.path.is_file():
            raise SystemExit(f"账本缺失: {domain.relative_path}（先跑 tools/asset_pipeline/split_asset_ledger.py）")
        changed, skipped, missing = refresh_ledger(domain.path, root, args.dry_run)
        totals = [totals[0] + changed, totals[1] + skipped, totals[2] + missing]
        print(f"  {domain.key:<11} {domain.file:<36} changed={changed} skipped={skipped} missing={missing}")
    print(f"ASSET_REGISTRY_HASH_REFRESH changed={totals[0]} skipped={totals[1]} "
          f"missing={totals[2]} ledgers={len(domains)} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
