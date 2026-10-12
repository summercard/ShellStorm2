"""Guard exported texture dimensions and prevent embedded duplicate GLB images."""
from pathlib import Path
import fnmatch
import json
import re
import struct
import sys
import hashlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'scripts'))
from configure_export_boundaries import EXCLUDES


def main():
    errors, textures, models = [], 0, 0
    seen_imports = {}
    excludes = EXCLUDES.split(',')
    collections = [ROOT.glob('*.import')] + [(ROOT/folder).rglob('*') for folder in ['assets', 'scenes', 'src']]
    for paths in collections:
        for path in paths:
            if path.suffix.lower() not in {'.import', '.glb'}:
                continue
            rel = path.relative_to(ROOT).as_posix()
            if any(fnmatch.fnmatch(rel, pattern) for pattern in excludes):
                continue
            if any((d/'.gdignore').exists() for d in path.parents if d == ROOT or ROOT in d.parents):
                continue
            if path.suffix == '.glb':
                with path.open('rb') as stream:
                    header=stream.read(20)
                    if len(header)<20 or header[:4]!=b'glTF':
                        errors.append({'path':rel,'error':'invalid_glb'});continue
                    doc=json.loads(stream.read(struct.unpack_from('<I',header,12)[0]))
                models+=1
                for image in doc.get('images', []):
                    if 'bufferView' in image or image.get('uri','').startswith('data:'):
                        errors.append({'path':rel,'error':'embedded_image_requires_externalization'})
                    elif 'uri' in image and not (path.parent/image['uri']).is_file():
                        errors.append({'path':rel,'error':'missing_image','uri':image['uri']})
                continue
            text=path.read_text(encoding='utf8')
            if 'importer="texture"' not in text:
                continue
            textures+=1
            limit=512 if '/enemies/' in rel or '/textures/enemies/' in rel else 1024
            match=re.search(r'^process/size_limit=(\d+)',text,re.M)
            if not match or not 0<int(match[1])<=limit:
                errors.append({'path':rel,'error':'import_size_limit','limit':limit})
            # 共享色盘契约（业主 2026-10-12 反馈「材质球不能加 MipMap、会纹理叠加」）：
            # 色盘是 10×10 纯色格，一旦开 MipMap 或改用块压缩（mode=2），缩小采样时
            # 相邻色格会互相插值 ⇒ 全项目引用它的模型集体串色。这两项都是引擎在
            # 「全新 APPDATA / 缓存失配」下重导时按默认值回归的，必须由断言盯着。
            if rel=='assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png.import':
                for want_key,want_value in (('compress/mode','0'),('mipmaps/generate','false')):
                    found=re.search(r'^'+re.escape(want_key)+r'=(\S+)',text,re.M)
                    got=found.group(1) if found else None
                    if got!=want_value:
                        errors.append({'path':rel,'error':'shared_palette_contract',
                                       'key':want_key,'want':want_value,'got':got})
            signature = []
            for texture_format, target in re.findall(r'path(?:\.([\w]+))?="res://([^"]+\.ctex)"',text):
                imported=ROOT/target
                if not imported.exists():
                    errors.append({'path':rel,'error':'missing_import','target':target});continue
                with imported.open('rb') as stream:header=stream.read(16)
                if header[:4]!=b'GST2':
                    errors.append({'path':rel,'error':'invalid_ctex_header'});continue
                width,height=struct.unpack_from('<II',header,8)
                if max(width,height)>limit:
                    errors.append({'path':rel,'error':'oversize_import','size':[width,height],'limit':limit})
                signature.append((texture_format, hashlib.sha256(imported.read_bytes()).hexdigest()))
            if signature:
                # Compare payloads across every imported platform format.
                key = tuple(sorted(signature))
                if key in seen_imports:
                    errors.append({'path':rel,'error':'duplicate_import_payload','canonical':seen_imports[key]})
                else:
                    seen_imports[key] = rel
    print(json.dumps({'result':'RUNTIME_TEXTURE_POLICY_OK' if not errors else 'RUNTIME_TEXTURE_POLICY_FAILED',
                      'textures':textures,'models':models,'errors':errors},ensure_ascii=True))
    return bool(errors)


if __name__=='__main__':raise SystemExit(main())
