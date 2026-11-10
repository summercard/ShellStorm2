"""固定镜头像素对照与制作产物只读核查。"""
from pathlib import Path
import hashlib
import importlib.util
import json
from PIL import Image, ImageChops, ImageStat, ImageDraw

PACKAGE = Path(__file__).resolve().parent
PROJECT = PACKAGE.parents[3]
spec = importlib.util.spec_from_file_location('workspace_paths', PROJECT / 'scripts/workspace_paths.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
OUT = module.work_path('outputs/2026-11-10_key_inset/model/.anchor').parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    path = PACKAGE / 'asset_manifest.json'
    manifest = json.loads(path.read_text(encoding='utf-8'))
    comparisons = []
    sheet = Image.new('RGB',(1000, 6*375),(35,40,48))
    draw = ImageDraw.Draw(sheet)
    for i, name in enumerate(['front','back','side','game_angle','top','socket_close']):
        before = Image.open(OUT / ('before_'+name+'.png')).convert('RGB')
        after = Image.open(OUT / ('after_'+name+'.png')).convert('RGB')
        diff = ImageChops.difference(before,after)
        stat = ImageStat.Stat(diff)
        changed = sum(1 for pixel in diff.getdata() if any(pixel))
        record = {'view':name,'resolution':list(before.size),'max_absolute_channel_error_8bit':max(v[1] for v in diff.getextrema()),'mean_absolute_channel_error_8bit':stat.mean,'changed_pixel_count':changed,'total_pixels':before.width*before.height,'identical_pixels':changed==0,'difference_bbox':diff.getbbox()}
        comparisons.append(record)
        diff.save(OUT / ('difference_'+name+'.png'))
        for col,image in enumerate([before,after]):
            sheet.paste(image.resize((500,350)),(col*500,i*375+25))
            draw.text((col*500+10,i*375+7),('BEFORE ' if col==0 else 'AFTER ')+name,fill=(240,240,240))
    sheet.save(OUT / 'before_after_contact_sheet.png')
    manifest['fidelity']['pixel_comparison'] = comparisons
    manifest['fidelity']['contact_sheet'] = str(OUT / 'before_after_contact_sheet.png')
    manifest['fidelity']['human_visual_review'] = {'status':'待最终图像检查','criteria':'正背侧、游戏视角、俯视与孔口特写保持轮廓、孔口、阴影与细节；像素差异只实报，不编造项目容差。'}
    protected = manifest['protected_hashes_before']
    assert all(sha(p)==value for p,value in protected.items())
    for role, key in [('source','source_sha256_before'),('optimized','optimized_sha256'),('stable_glb','glb_sha256'),('wrapper','wrapper_sha256')]:
        assert sha(PROJECT / manifest[role]) == manifest[key]
    assert manifest['source_sha256_before'] == manifest['source_sha256_after']
    assert manifest['fidelity']['fixed_camera_settings_equal']
    # 私有资产路径不得生成PNG贴图或打包公共色盘。
    roots = [PACKAGE, PROJECT / Path(manifest['stable_glb']).parent, PROJECT / Path(manifest['wrapper']).parent]
    private_images = [str(p) for root in roots for p in root.rglob('*') if p.suffix.lower() in {'.png','.jpg','.jpeg','.webp'}]
    assert not private_images
    manifest['materials_and_uv']['private_image_files'] = private_images
    manifest['evidence_check_script'] = str(Path(__file__).relative_to(PROJECT)).replace('\\','/')
    manifest['artifact_sizes_bytes'] = {role:(PROJECT / manifest[role]).stat().st_size for role in ['source','optimized','stable_glb','wrapper']}
    text = json.dumps(manifest,ensure_ascii=False,indent=2)
    path.write_text(text,encoding='utf-8')
    (OUT/'asset_manifest.json').write_text(text,encoding='utf-8')
    print(json.dumps({'triangles_before':manifest['optimization']['triangles_before'],'triangles_after':manifest['optimization']['triangles_after'],'uv_valid_faces':manifest['materials_and_uv']['valid_uv_faces'],'comparisons':comparisons,'protected_files':len(protected),'protected_unchanged':True},ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
