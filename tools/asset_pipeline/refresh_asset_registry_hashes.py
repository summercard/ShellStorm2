"""Refresh SHA-256 fields for valid, non-placeholder rows in the asset registry."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from openpyxl import load_workbook


SKIP_STATUSES = {"待制作", "程序占位", "弃用", "旧资产已从正式基地移除"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    root = args.project.resolve()
    workbook_path = root / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
    workbook = load_workbook(workbook_path, data_only=False)
    ws = workbook["资产主表"]
    changed = skipped = missing = 0
    for row in range(6, ws.max_row + 1):
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
        path = Path(raw_path)
        if not path.is_absolute():
            path = root / path
        if not path.is_file():
            missing += 1
            continue
        actual = sha256(path)
        if str(ws.cell(row, 20).value or "").strip().lower() != actual:
            ws.cell(row, 20).value = actual
            changed += 1
    if not args.dry_run:
        workbook.save(workbook_path)
    print(f"ASSET_REGISTRY_HASH_REFRESH changed={changed} skipped={skipped} missing={missing} dry_run={args.dry_run}")


if __name__ == "__main__":
    main()
