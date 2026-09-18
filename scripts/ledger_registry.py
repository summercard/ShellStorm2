#!/usr/bin/env python3
"""Resolve which art-asset ledger owns a category, AssetID or sheet.

The split into per-domain ledgers is described by ``assets/registry/ledger_index.json``.
This module is the only place that turns that description into paths, so gates, writer
tools and tests never hardcode a ledger filename.

Usage::

    from ledger_registry import LedgerIndex
    index = LedgerIndex.load(project_root)
    index.path_for_category("武器")        # assets/registry/ledgers/ShellStorm2_武器账本_v001.xlsx
    index.sheet_domain("3D-场景通用")       # Domain(key='scenes', ...)
    index.resolve_ref("assets/registry/ShellStorm2_美术资产台账_v001.xlsx#3D-场景通用")
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

INDEX_RELATIVE_PATH = "assets/registry/ledger_index.json"


class LedgerIndexError(RuntimeError):
    """Raised when the ledger index is missing, malformed or inconsistent."""


@dataclass(frozen=True)
class Domain:
    key: str
    name: str
    file: str
    categories: tuple[str, ...]
    id_prefixes: tuple[str, ...]
    sheet_scope: tuple[str, ...]
    prefab_pages: tuple[str, ...]
    animation_sheets: tuple[str, ...]
    primary_skill: str
    supporting_skills: tuple[str, ...]
    owner: str
    scope_note: str
    index: LedgerIndex

    @property
    def relative_path(self) -> str:
        return f"{self.index.ledger_dir_relative}/{self.file}"

    @property
    def path(self) -> Path:
        return self.index.project_root / self.relative_path

    @property
    def label(self) -> str:
        return f"{self.name}（{self.file}）"


@dataclass(frozen=True)
class LedgerIndex:
    project_root: Path
    raw: dict[str, Any]
    domains: tuple[Domain, ...]

    # ---- loading -----------------------------------------------------------
    @classmethod
    def load(cls, project_root: Path) -> LedgerIndex:
        project_root = Path(project_root).resolve()
        index_path = project_root / INDEX_RELATIVE_PATH
        if not index_path.is_file():
            raise LedgerIndexError(f"ledger index not found: {index_path}")
        raw = json.loads(index_path.read_text(encoding="utf-8"))
        domains = tuple(
            Domain(
                key=entry["key"],
                name=entry["name"],
                file=entry["file"],
                categories=tuple(entry["categories"]),
                id_prefixes=tuple(entry.get("id_prefixes", ())),
                sheet_scope=tuple(entry.get("sheet_scope", ())),
                prefab_pages=tuple(entry.get("prefab_pages", ())),
                animation_sheets=tuple(entry.get("animation_sheets", ())),
                primary_skill=entry.get("primary_skill", ""),
                supporting_skills=tuple(entry.get("supporting_skills", ())),
                owner=entry.get("owner", "待分配"),
                scope_note=entry.get("scope_note", ""),
                index=None,  # type: ignore[arg-type]
            )
            for entry in raw["domains"]
        )
        instance = cls(project_root=project_root, raw=raw, domains=domains)
        # Dataclass instances are frozen; rebind Domain.index through object.__setattr__.
        for domain in instance.domains:
            object.__setattr__(domain, "index", instance)
        instance._validate()
        return instance

    # ---- derived maps -----------------------------------------------------
    @property
    def master_path(self) -> Path:
        return self.project_root / self.raw["master"]["path"]

    @property
    def master_relative_path(self) -> str:
        return self.raw["master"]["path"]

    @property
    def ledger_dir_relative(self) -> str:
        return self.raw["ledger_dir"]

    @property
    def asset_sheet(self) -> str:
        return self.raw.get("asset_sheet", "资产主表")

    def domain_for_category(self, category: str) -> Domain:
        token = _norm(category)
        for domain in self.domains:
            if any(_norm(c) == token for c in domain.categories):
                return domain
        raise LedgerIndexError(f"category not assigned to any ledger: {category!r}")

    def domain_for_key(self, key: str) -> Domain:
        for domain in self.domains:
            if domain.key == key or domain.name == _norm(key):
                return domain
        raise LedgerIndexError(f"unknown ledger domain: {key!r}")

    def domain_for_asset_id(self, asset_id: str) -> Domain | None:
        prefix = _prefix(asset_id)
        matches = [d for d in self.domains if prefix in d.id_prefixes]
        if len(matches) == 1:
            return matches[0]
        return None

    def domain_for_sheet(self, sheet: str) -> Domain | None:
        owner = None
        for domain in self.domains:
            if sheet in domain.sheet_scope:
                if owner is not None:
                    raise LedgerIndexError(f"sheet claimed by two ledgers: {sheet!r}")
                owner = domain
        return owner

    def path_for_category(self, category: str) -> Path:
        return self.domain_for_category(category).path

    def path_for_asset_id(self, asset_id: str) -> Path | None:
        domain = self.domain_for_asset_id(asset_id)
        return None if domain is None else domain.path

    def ledger_paths(self) -> list[Path]:
        return [domain.path for domain in self.domains]

    def all_categories(self) -> set[str]:
        return {c for domain in self.domains for c in domain.categories}

    def prefix_pairs(self) -> set[tuple[str, str]]:
        return {(p, c) for p, c in self.raw.get("prefix_category_pairs", [])}

    # ---- legacy compatibility --------------------------------------------
    def resolve_ref(self, ref: str) -> tuple[Domain, str]:
        """Resolve ``"<relative path>[#<sheet>]"`` to ``(domain, sheet)``.

        Accepts both the current per-domain paths and legacy pointers that still name
        the master workbook plus a sheet name, so manifests written before the split
        keep resolving. Returns the sheet name as ``""`` when the ref carries none.
        """
        path_part, _, sheet = ref.partition("#")
        path_part = path_part.strip().replace("\\", "/")
        if path_part.endswith(self.master_relative_path):
            if not sheet:
                raise LedgerIndexError(f"legacy master ref needs a #sheet to resolve: {ref!r}")
            domain = self.domain_for_sheet(sheet)
            if domain is None:
                raise LedgerIndexError(f"legacy ref names a sheet with no owning ledger: {ref!r}")
            return domain, sheet
        for domain in self.domains:
            if path_part.endswith(domain.relative_path) or path_part.endswith(domain.file):
                return domain, sheet
        raise LedgerIndexError(f"ref does not name any known ledger: {ref!r}")

    def rewrite_ref(self, ref: str) -> str:
        """Return the post-split equivalent of ``ref`` (idempotent)."""
        domain, sheet = self.resolve_ref(ref)
        return f"{domain.relative_path}#{sheet}" if sheet else domain.relative_path

    # ---- integrity --------------------------------------------------------
    def _validate(self) -> None:
        seen_categories: dict[str, str] = {}
        seen_sheets: dict[str, str] = {}
        seen_files: set[str] = set()
        for domain in self.domains:
            if domain.file in seen_files:
                raise LedgerIndexError(f"two ledgers share a filename: {domain.file}")
            seen_files.add(domain.file)
            for category in domain.categories:
                if category in seen_categories:
                    raise LedgerIndexError(
                        f"category {category!r} assigned to both "
                        f"{seen_categories[category]!r} and {domain.key!r}"
                    )
                seen_categories[category] = domain.key
            for sheet in domain.sheet_scope:
                if sheet in seen_sheets:
                    raise LedgerIndexError(
                        f"sheet {sheet!r} assigned to both {seen_sheets[sheet]!r} and {domain.key!r}"
                    )
                seen_sheets[sheet] = domain.key
        unknown = {p for p, _ in self.prefix_pairs()} - {
            prefix for domain in self.domains for prefix in domain.id_prefixes
        }
        if unknown:
            raise LedgerIndexError(f"prefix_category_pairs names undeclared prefixes: {sorted(unknown)}")


def _norm(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _prefix(asset_id: str) -> str:
    return _norm(asset_id).split("-", 1)[0]


def load(project_root: Path | str | None = None) -> LedgerIndex:
    """Convenience loader defaulting to the repository that contains this file."""
    if project_root is None:
        project_root = Path(__file__).resolve().parents[1]
    return LedgerIndex.load(Path(project_root))


if __name__ == "__main__":  # pragma: no cover - manual inspection helper
    import argparse

    parser = argparse.ArgumentParser(description="Inspect the art-asset ledger index.")
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--category")
    parser.add_argument("--asset-id")
    parser.add_argument("--ref")
    args = parser.parse_args()
    idx = LedgerIndex.load(args.project_root)
    print(f"master           : {idx.master_relative_path}")
    print(f"ledger dir       : {idx.ledger_dir_relative}")
    for domain in idx.domains:
        exists = "OK " if domain.path.is_file() else "MISSING"
        print(
            f"  [{exists}] {domain.key:<11} {domain.file:<34} "
            f"大类={'/'.join(domain.categories)} 前缀={'/'.join(domain.id_prefixes)}"
        )
    if args.category:
        print("category ->", idx.domain_for_category(args.category).relative_path)
    if args.asset_id:
        print("asset id ->", idx.path_for_asset_id(args.asset_id))
    if args.ref:
        print("ref ->", idx.rewrite_ref(args.ref))
