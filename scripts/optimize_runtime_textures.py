"""Externalize GLB images, share exact pixels and bound runtime texture sizes.

Requires Pillow and numpy. Authoring directories and .blend masters are untouched.
Every replaced/removed file is copied and hash-verified in an external backup.
Run --apply only against an audited pack CSV; then perform a native Godot import.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import struct

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
IMAGE_EXT = {'.png', '.jpg', '.jpeg', '.webp', '.svg'}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def active(path):
    return not any((d / '.gdignore').exists() for d in [path.parent, *path.parents]
                   if d == ROOT or ROOT in d.parents)


def domain(path):
    if '/characters/player/' in path:
        return 'player', 1024
    if '/enemies/' in path:
        return 'enemies', 512
    return 'general', 1024


def read_glb(path):
    data = path.read_bytes()
    assert struct.unpack_from('<III', data) == (0x46546c67, 2, len(data))
    n, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4e4f534a
    doc = json.loads(data[20:20+n])
    pos = 20+n
    if pos == len(data):
        return doc, b''
    m, kind = struct.unpack_from('<II', data, pos)
    assert kind == 0x004e4942 and pos+8+m == len(data)
    assert len(doc.get('buffers', [])) == 1 and 'uri' not in doc['buffers'][0]
    return doc, data[pos+8:pos+8+m]


def write_glb(doc, binary):
    js = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    binary += b'\0' * (-len(binary) % 4)
    return (struct.pack('<III', 0x46546c67, 2, 28+len(js)+len(binary)) +
            struct.pack('<II', len(js), 0x4e4f534a) + js +
            struct.pack('<II', len(binary), 0x004e4942) + binary)


def compact_views(doc, binary, removed):
    """Keep every non-image bufferView byte-for-byte, including skin/animation data."""
    old = doc.get('bufferViews', [])
    new, remap, out = [], {}, bytearray()
    for i, view in enumerate(old):
        if i in removed:
            continue
        assert view['buffer'] == 0
        out.extend(b'\0' * (-len(out) % 4))
        start = view.get('byteOffset', 0)
        chunk = binary[start:start+view['byteLength']]
        assert len(chunk) == view['byteLength']
        remap[i] = len(new)
        new.append(dict(view, byteOffset=len(out)))
        out.extend(chunk)
    def visit(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == 'bufferView':
                    assert value not in removed, 'image view is also referenced by geometry'
                    node[key] = remap[value]
                else:
                    visit(value)
        elif isinstance(node, list):
            for value in node:
                visit(value)
    doc['bufferViews'] = new
    visit(doc)
    doc['buffers'][0]['byteLength'] = len(out)
    return bytes(out)


def resized(image, limit, normal):
    image = image.convert('RGBA' if 'A' in image.getbands() else 'RGB')
    if max(image.size) <= limit:
        return image
    scale = limit/max(image.size)
    image = image.resize(tuple(max(1, round(x*scale)) for x in image.size), Image.Resampling.LANCZOS)
    if normal:
        values = np.asarray(image).copy()
        vec = values[..., :3].astype(np.float32)/127.5-1
        vec /= np.maximum(np.linalg.norm(vec, axis=-1, keepdims=True), 1e-8)
        values[..., :3] = np.clip(np.round((vec+1)*127.5), 0, 255).astype(np.uint8)
        image = Image.fromarray(values)
    return image


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--pack-csv', type=Path, required=True)
    ap.add_argument('--backup', type=Path, required=True)
    ap.add_argument('--report', type=Path, required=True)
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()
    backup = args.backup.resolve()
    assert backup != ROOT and ROOT not in backup.parents
    records, backed = [], set()
    def protect(path):
        assert ROOT in path.resolve().parents and not path.is_symlink() and not path.is_junction()
        rel = path.relative_to(ROOT).as_posix()
        if rel in backed:
            return
        target = backup / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            assert digest(target.read_bytes()) == digest(path.read_bytes()), rel
        else:
            shutil.copy2(path, target)
        assert digest(target.read_bytes()) == digest(path.read_bytes())
        backed.add(rel)
    def replace(path, data):
        before = digest(path.read_bytes()) if path.exists() else None
        if path.exists() and path.read_bytes() == data:
            return
        records.append({'path': path.relative_to(ROOT).as_posix(), 'before': before, 'after': digest(data)})
        if args.apply:
            if path.exists():
                protect(path)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    rows = list(csv.DictReader(args.pack_csv.open(encoding='utf-8-sig')))
    sources = sorted({r['source_path'] for r in rows if Path(r['source_path']).suffix.lower() in IMAGE_EXT})
    by_raw, raster = collections.defaultdict(list), {}
    for rel in sources:
        path = ROOT / rel
        assert path.exists() and active(path), rel
        if path.suffix.lower() == '.svg':
            continue
        data = path.read_bytes()
        by_raw[digest(data)].append(rel)
        raster[rel] = Image.open(io.BytesIO(data)).copy()

    # Match embedded images to the exact extracted files, never just their names.
    models, generated = [], set()
    for path in (ROOT/'assets').rglob('*.glb'):
        if not active(path):
            continue
        doc, binary = read_glb(path)
        matches = {}
        for i, image in enumerate(doc.get('images', [])):
            if 'bufferView' not in image:
                continue
            view = doc['bufferViews'][image['bufferView']]
            start = view.get('byteOffset', 0)
            raw = binary[start:start+view['byteLength']]
            candidates = by_raw.get(digest(raw), [])
            assert candidates, (path.relative_to(ROOT).as_posix(), image)
            preferred = [x for x in candidates if (ROOT/x).parent == path.parent]
            rel = sorted(preferred or candidates)[0]
            matches[i] = rel
            generated.add(rel)
        if doc.get('images'):
            models.append((path, doc, binary, matches))

    # Pixel identity + import semantics + size budget define safe sharing.
    groups = collections.defaultdict(list)
    settings, keys = {}, {}
    for rel, image in raster.items():
        text = (ROOT/(rel+'.import')).read_text(encoding='utf8')
        params = text.split('[params]', 1)[1].strip()
        bucket, limit = domain(rel)
        params = re.sub(r'process/size_limit=\d+', f'process/size_limit={limit}', params)
        normal = 'normal' in Path(rel).stem.lower()
        if rel in generated or '/characters/player/' in rel or '/enemies/' in rel:
            params = re.sub(r'compress/mode=\d+', 'compress/mode=2', params)
            params = re.sub(r'compress/normal_map=\d+', f'compress/normal_map={1 if normal else 0}', params)
            params = re.sub(r'detect_3d/compress_to=\d+', 'detect_3d/compress_to=0', params)
        # UI and 3D remain separate; filtering/color/alpha settings must match.
        pixel = digest(str(image.size).encode() + image.convert('RGBA').tobytes())
        key = digest((bucket+pixel+params).encode())
        groups[key].append(rel)
        settings[key] = (params, limit, normal, bucket)
        keys[rel] = key
    mapping, dimensions = {}, []
    for key, members in groups.items():
        params, limit, normal, bucket = settings[key]
        use_shared = len(members)>1 or any(x in generated for x in members)
        if use_shared:
            role = 'normal' if normal else 'color'
            canonical = f'assets/art/shared/textures/{bucket}/tex_{role}_{key[:20]}.png'
            target = ROOT/canonical
            image = resized(raster[members[0]], limit, normal)
            buf = io.BytesIO(); image.save(buf, format='PNG', optimize=True)
            replace(target, buf.getvalue())
            sidecar = ('[remap]\n\nimporter="texture"\nimporter_version=1\ntype="CompressedTexture2D"\n\n'
                       '[deps]\n\nsource_file="res://'+canonical+'"\n\n[params]\n\n'+params+'\n')
            replace(Path(str(target)+'.import'), sidecar.encode())
            for rel in members:
                if rel != canonical:
                    mapping[rel] = canonical
        else:
            canonical = members[0]
            image = resized(raster[canonical], limit, normal)
            if image.size != raster[canonical].size:
                buf = io.BytesIO()
                fmt = Image.registered_extensions()[(ROOT/canonical).suffix.lower()]
                kwargs = {'quality': 95, 'subsampling': 0} if fmt == 'JPEG' else {}
                image.save(buf, format=fmt, **kwargs)
                replace(ROOT/canonical, buf.getvalue())
            imp = ROOT/(canonical+'.import')
            text = imp.read_text(encoding='utf8')
            text = text.split('[params]',1)[0]+'[params]\n\n'+params+'\n'
            replace(imp, text.encode())
        dimensions.append({'path': canonical, 'size': list(image.size), 'limit': limit, 'sources': members})

    # Keep original palette paths used by current Blender masters. Their directories
    # contain only source palettes; ignore them in Godot after runtime rewiring.
    source_dependencies = set()
    source_scan = ROOT.parent/'ShellStorm2-backup/2026-10-11_slimming/management/blend_image_scan.json'
    if source_scan.exists():
        scan = json.loads(source_scan.read_text(encoding='utf8'))
        for source in scan['linked_sources']:
            for image in source['images']:
                path = Path(image['resolved'])
                if path.is_relative_to(ROOT):
                    rel = path.relative_to(ROOT).as_posix()
                    if rel in mapping:
                        source_dependencies.add(rel)
        for rel in source_dependencies:
            parent = (ROOT/rel).parent
            assert all(x.suffix.lower() in IMAGE_EXT or x.name.endswith('.import') or x.name == '.gdignore' for x in parent.iterdir())
            replace(parent/'.gdignore', b'# Authoring palette dependency; runtime uses shared/textures.\n')

    for rel in sources:
        if Path(rel).suffix.lower() != '.svg':
            continue
        imp = ROOT/(rel+'.import')
        text = imp.read_text(encoding='utf8')
        replace(imp, re.sub(r'process/size_limit=\d+', 'process/size_limit=1024', text).encode())

    geometry_checked = 0
    for path, doc, binary, matches in models:
        removed = set()
        old_views = doc['bufferViews']
        retained_hashes = [digest(binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']])
                           for i,v in enumerate(old_views) if i not in {doc['images'][x]['bufferView'] for x in matches}]
        for i, rel in matches.items():
            image = doc['images'][i]
            removed.add(image.pop('bufferView'))
            image.pop('mimeType', None)
            image['uri'] = os.path.relpath(ROOT/mapping.get(rel, rel), path.parent).replace('\\','/')
        for image in doc.get('images', []):
            if 'uri' in image and not image['uri'].startswith('data:'):
                original = (path.parent/image['uri']).resolve()
                if original.is_relative_to(ROOT):
                    source = original.relative_to(ROOT).as_posix()
                    if source in mapping:
                        image['uri'] = os.path.relpath(ROOT/mapping[source], path.parent).replace('\\','/')
        new_binary = compact_views(doc, binary, removed) if removed else binary
        assert retained_hashes == [digest(new_binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]) for v in doc['bufferViews']]
        geometry_checked += len(retained_hashes)
        replace(path, write_glb(doc, new_binary))

    # Update external GLTF and text resource references, preserving model/prefab paths.
    for folder in ['assets', 'src', 'scenes', 'data']:
        for path in (ROOT/folder).rglob('*'):
            if path.suffix not in {'.tscn','.tres','.gd','.json','.gltf'} or not active(path):
                continue
            text = path.read_text(encoding='utf8')
            updated = text
            for old, new in mapping.items():
                updated = updated.replace('res://'+old, 'res://'+new).replace('"'+old+'"', '"'+new+'"')
            # UIDs of removed image files cannot override the canonical paths.
            updated = re.sub(r'(\[ext_resource[^\n]*?) uid="uid://[^"]+"([^\n]*path="res://assets/art/shared/textures/[^\n]*)', r'\1\2', updated)
            if updated != text:
                replace(path, updated.encode())

    removed_bytes = 0
    for rel in sorted(mapping):
        if rel in source_dependencies:
            continue
        for path in [ROOT/rel, ROOT/(rel+'.import')]:
            if path.exists():
                removed_bytes += path.stat().st_size
                records.append({'path': path.relative_to(ROOT).as_posix(), 'before': digest(path.read_bytes()), 'after': None})
                if args.apply:
                    protect(path)
                    path.unlink()

    # Retain only the audited runtime texture import contracts in Git.
    ignore = ROOT/'.gitignore'
    original = ignore.read_text(encoding='utf8')
    original = re.sub(r'\n# Runtime texture import contracts:[\s\S]*?# END runtime_texture_policy\n?', '\n', original)
    paths = sorted({x['path']+'.import' for x in dimensions} |
                   {x+'.import' for x in sources if Path(x).suffix.lower()=='.svg'})
    block = ('\n# Runtime texture import contracts: budgets and normal/VRAM settings.\n'
             '# BEGIN runtime_texture_policy\n' + '\n'.join('!'+x for x in paths) + '\n# END runtime_texture_policy\n')
    replace(ignore, (original.rstrip()+'\n'+block).encode())
    report = {'applied':args.apply, 'sources':len(sources), 'shared_groups':sum(1 for x in dimensions if x['path'].startswith('assets/art/shared/textures/')),
              'source_mapping':mapping, 'textures':dimensions, 'models_modified':len(models), 'unchanged_geometry_views':geometry_checked,
              'removed_source_bytes':removed_bytes, 'preserved_source_dependencies':sorted(source_dependencies), 'changes':records, 'backup':str(backup)}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({k:report[k] for k in ['applied','sources','shared_groups','models_modified','unchanged_geometry_views','removed_source_bytes']}))


if __name__ == '__main__':
    main()
