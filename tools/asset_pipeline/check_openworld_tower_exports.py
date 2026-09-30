"""Static roundtrip/export guard complementary to real Godot renderer acceptance."""
import hashlib
import json
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'assets/art/environments/open_world'
counts=[]
for slug,version in [('tower_02','v003'),('tower_03','v001')]:
    manifest=json.loads((BASE/'source'/slug/'export'/version/'export_manifest.json').read_text(encoding='utf8'))
    assert hashlib.sha256((ROOT/manifest['source']).read_bytes()).hexdigest()==manifest['source_sha256']
    catalog=json.loads((BASE/'source'/slug/version/'catalog.json').read_text(encoding='utf8'))
    frozen={r['slug']:r for r in catalog['packages']}
    for record in manifest['records']:
        raw=(ROOT/record['glb']).read_bytes()
        assert struct.unpack_from('<4sII',raw)==(b'glTF',2,len(raw))
        length,kind=struct.unpack_from('<II',raw,12)
        assert kind==0x4E4F534A
        data=json.loads(raw[20:20+length])
        assert not data.get('images') and not data.get('textures') and not data.get('animations')
        assert not data.get('cameras') and not data.get('extensions',{}).get('KHR_lights_punctual')
        assert len(data.get('materials',[]))<=4
        assert all(m['name'].startswith(('01_','02_','03_','04_')) for m in data['materials'])
        for mesh in data['meshes']:
            for primitive in mesh['primitives']:
                assert primitive.get('mode',4)==4 and 'TEXCOORD_0' in primitive['attributes']
        expected=frozen[record['slug']]
        assert all(abs(a-b)<0.02 for a,b in zip(record['bounds_blender'][0],expected['bounds_min']))
        assert all(abs(a-b)<0.02 for a,b in zip(record['bounds_blender'][1],expected['bounds_max']))
        assert (ROOT/record['prefab']).is_file()
        assert hashlib.sha256(raw).hexdigest()==record['glb_sha256']
    counts.append({'tower':slug,'components':len(manifest['records']),'triangles':sum(r['triangle_count'] for r in manifest['records'])})
print('OPENWORLD_TOWER_EXPORTS_OK',json.dumps(counts))
