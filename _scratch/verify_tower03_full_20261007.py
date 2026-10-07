import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import os
import tempfile
from datetime import datetime

ROOT = Path('I:/工作项目/shellstrom2/ShellStorm2')
ART = ROOT / 'assets/art/environments/open_world'
REPORT = ROOT / 'outputs/towers_restore_full_20261007/tower03_restore.json'
BACKUP = ROOT / '_scratch/towers_restore_full_20261007/tower03_before'
META = re.compile(rb'^metadata/(?:asset_version|source_blend) = [^\r\n]*(?:\r?\n|$)', re.M)


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def load(path):
    return json.loads(path.read_bytes().decode('utf-8-sig'))


report = load(REPORT)
export = load(ART / 'source/tower_03/export/v001/export_manifest.json')
inventory = load(BACKUP / 'backup_inventory.json')['files']
root_manifest = load(ART / 'runtime/tower_03/asset_manifest.json')
root_by_id = {r['asset_id']: r for r in root_manifest['records']}
triangles = meshes = primitives = 0
for record in export['records']:
    path = ROOT / record['glb']
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == record['glb_sha256']
    size, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4e4f534a
    doc = json.loads(data[20:20 + size])
    component_triangles = 0
    for mesh in doc['meshes']:
        for primitive in mesh['primitives']:
            assert primitive.get('mode', 4) == 4
            accessor = doc['accessors'][primitive['indices']] if 'indices' in primitive else doc['accessors'][primitive['attributes']['POSITION']]
            assert accessor['count'] % 3 == 0
            component_triangles += accessor['count'] // 3
            primitives += 1
    assert component_triangles == record['triangle_count']
    triangles += component_triangles
    meshes += len(doc['meshes'])
    manifest = load((ROOT / record['prefab']).parent / 'asset_manifest.json')
    assert manifest == root_by_id[record['asset_id']]
    assert manifest['glb_sha256'] == record['glb_sha256']
    assert manifest['triangle_count_glb'] == component_triangles
    assert manifest['version'] == 'v001'
    assert manifest['runtime_verified'] is False and manifest['godot_reimport_pending'] is True
    assert manifest['ledger_pending'] is True and manifest['runtime_integrated'] is False
    assert 'optimized_blend' not in manifest and 'runtime_verification_evidence' not in manifest
    assert manifest['historical_runtime']['active'] is False
assert (triangles, meshes, primitives) == (212967, 228, 321)
scene_count = 0
for scene in (ART / 'runtime/tower_03').rglob('*.tscn'):
    saved = BACKUP / 'runtime' / scene.relative_to(ART / 'runtime/tower_03')
    before, after = saved.read_bytes(), scene.read_bytes()
    assert META.sub(b'', before) == META.sub(b'', after)
    assert re.findall(rb'^metadata/asset_version = "([^"]+)"', after, re.M) == [b'v001']
    assert re.findall(rb'^metadata/source_blend = "([^"]+)"', after, re.M) == [export['source'].encode('utf-8')]
    scene_count += 1
assert scene_count == 218
written = set(report['written_files'])
for name, expected in inventory.items():
    path = ROOT / name
    section = path.relative_to(ART).parts[0]
    stable_root = ART / section / 'tower_03'
    saved = BACKUP / section / path.relative_to(stable_root)
    assert sha(saved) == expected
    if name not in written:
        assert sha(path) == expected
for name, expected in report['protected_files'].items():
    assert sha(ROOT / name) == expected, name
for key in ('source', 'derived'):
    assert sha(ROOT / export[key]) == export[key + '_sha256']
assert (BACKUP / '.gdignore').is_file()
assert root_manifest['runtime_verified'] is False and root_manifest['godot_reimport_pending'] is True
assert root_manifest['ledger_pending'] is True and root_manifest['version'] == 'v001'
assert root_manifest['optimization']['active'] is False
assert root_manifest['historical_runtime']['active'] is False
assert root_manifest['triangle_count_glb'] == triangles
head = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], check=True, capture_output=True).stdout.decode().strip()
request = ''.join(head + ':' + r['glb'] + '\n' for r in export['records']).encode()
stream = subprocess.run(['git', '-C', str(ROOT), 'cat-file', '--batch'], input=request, check=True, capture_output=True).stdout
pos = matches = 0
for record in export['records']:
    end = stream.index(b'\n', pos)
    header = stream[pos:end].split()
    assert header[1] == b'blob'
    size = int(header[2])
    pos = end + 1
    data = stream[pos:pos + size]
    pos += size + 1
    assert hashlib.sha256(data).hexdigest() == record['glb_sha256']
    matches += 1
assert matches == 217
assert len(written) == 653 and all('/tower_03/' in name for name in written)
assert report['transaction_committed'] is True
report['independent_static_verification'] = dict(passed=True, script='_scratch/verify_tower03_full_20261007.py',
    verified_at=datetime.now().astimezone().isoformat(), head=head, head_original_hash_matches=matches,
    actual_accessor_triangles=triangles, glb_count=217, mesh_count=meshes, primitive_count=primitives,
    metadata_only_scene_count=scene_count, full_backup_files_verified=len(inventory),
    protected_files_verified=len(report['protected_files']), godot_executed=False)
prior = REPORT.read_bytes()
fd, temp = tempfile.mkstemp(prefix='.tower03_independent_', dir=REPORT.parent)
try:
    with os.fdopen(fd, 'wb') as f:
        f.write((json.dumps(report, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
        f.flush()
        os.fsync(f.fileno())
    assert REPORT.read_bytes() == prior
    os.replace(temp, REPORT)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
print(json.dumps(dict(independent_verification='passed', report=REPORT.as_posix(),
    glb_count=217, actual_accessor_triangles=triangles, mesh_count=meshes,
    primitive_count=primitives, metadata_only_scenes=scene_count, manifests=218,
    source_hashes_unchanged=True, original_manifest_hash_matches=217,
    head=head, head_hash_matches=matches, mismatches=0,
    full_backup_files_verified=len(inventory), protected_files_verified=len(report['protected_files']),
    tower02_written_by_this_transaction=False, route_unchanged=True,
    runtime_verified=False, godot_reimport_pending=True, ledger_pending=True,
    godot_executed=False, ledger_baseline_written=False), ensure_ascii=False))
