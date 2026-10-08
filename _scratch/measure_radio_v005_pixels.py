import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path('I:/工作项目/shellstrom2/ShellStorm2/outputs/base99_radio_v005')
projection = json.loads((OUT / 'runtime_camera_state.json').read_text(encoding='utf-8'))
results = {}
for name, state in projection.items():
    if not name.endswith('.png'):
        continue
    image = Image.open(OUT / name).convert('RGB')
    mask = Image.new('1', image.size)
    draw = ImageDraw.Draw(mask)
    for triangle in state['screen_triangles']:
        draw.polygon([tuple(point) for point in triangle], fill=1)
    counts = {'red_pixels': 0, 'green_pixels': 0, 'other_pixels': 0, 'white_pixels': 0}
    red_points=[]; green_points=[]
    for index, (color, selected) in enumerate(zip(image.getdata(), mask.getdata())):
        if not selected:
            continue
        r, g, b = color
        if r > 60 and r > g * 1.35 and r > b * 1.25:
            counts['red_pixels'] += 1
            red_points.append((index%image.width,index//image.width))
        elif g > 60 and g > r * 1.25 and g > b * 1.15:
            counts['green_pixels'] += 1
            green_points.append((index%image.width,index//image.width))
        else:
            counts['other_pixels'] += 1
        if min(r,g,b)>220 and max(r,g,b)-min(r,g,b)<25:
            counts['white_pixels'] += 1
    results[name] = {
        'resolution': list(image.size),
        'projected_light_bbox_xyxy': mask.getbbox(),
        'projected_geometry_pixels': counts['red_pixels']+counts['green_pixels']+counts['other_pixels'],
        'red_bbox_wh': [max(x for x,y in red_points)-min(x for x,y in red_points)+1,max(y for x,y in red_points)-min(y for x,y in red_points)+1] if red_points else [0,0],
        'green_bbox_wh': [max(x for x,y in green_points)-min(x for x,y in green_points)+1,max(y for x,y in green_points)-min(y for x,y in green_points)+1] if green_points else [0,0],
        'light_path': state['light_path'],
        'fov': state['fov'],
        'camera_position': state['camera_position'],
        'camera_rotation': state['camera_rotation'],
        'png_sha256': hashlib.sha256((OUT / name).read_bytes()).hexdigest(),
        **counts,
    }
pairs=[('runtime_after_off_player.png','runtime_after_a_player.png','runtime_before_v004_player.png','runtime_before_v004_green_player.png'),('attic_off.png','attic_a.png','runtime_before_v004_attic_off.png','runtime_before_v004_attic_green.png')]
checks={}; paired={}
for off,on,old_off,old_on in pairs:
    for left,right in [(off,on),(old_off,old_on)]:
        assert projection[left]['camera_position']==projection[right]['camera_position'] and projection[left]['camera_rotation']==projection[right]['camera_rotation']
    assert projection[off]['camera_position']==projection[old_off]['camera_position'] and projection[off]['fov']==projection[old_off]['fov']
    for left,right in [(off,on),(old_off,old_on)]:
        im0=Image.open(OUT/left).convert('RGB');im1=Image.open(OUT/right).convert('RGB')
        roi=Image.new('1',im0.size);d=ImageDraw.Draw(roi)
        for triangle in projection[left]['screen_triangles']:d.polygon([tuple(p) for p in triangle],fill=1)
        reds=[];greens=[]
        for i,(a,b,selected) in enumerate(zip(im0.getdata(),im1.getdata(),roi.getdata())):
            if not selected or max(abs(a[c]-b[c]) for c in range(3))<30:continue
            if a[0]>60 and a[0]>a[1]*1.35 and a[0]>a[2]*1.25 and b[1]>60 and b[1]>b[0]*1.25 and b[1]>b[2]*1.15:
                reds.append((i%im0.width,i//im0.width));greens.append((i%im0.width,i//im0.width))
        for name,pts,color in [(left,reds,'red'),(right,greens,'green')]:
            results[name]['paired_state_confirmed_'+color+'_pixels']=len(pts)
            results[name]['paired_state_confirmed_bbox_wh']=[max(x for x,y in pts)-min(x for x,y in pts)+1,max(y for x,y in pts)-min(y for x,y in pts)+1] if pts else [0,0]
    red=results[off]['paired_state_confirmed_red_pixels'];green=results[on]['paired_state_confirmed_green_pixels']
    paired[off]={'red_pixels':red,'green_pixels':green,'before_red_pixels':results[old_off]['paired_state_confirmed_red_pixels'],'before_green_pixels':results[old_on]['paired_state_confirmed_green_pixels'],'red_bbox_wh':results[off]['paired_state_confirmed_bbox_wh'],'green_bbox_wh':results[on]['paired_state_confirmed_bbox_wh'],'same_camera':True}
    # 门槛固定为原生1280x720中至少40个实色像素、双向边长至少7px，不以近景放大代替。
    checks[off]=red>=40 and green>=40 and min(results[off]['paired_state_confirmed_bbox_wh'])>=7 and min(results[on]['paired_state_confirmed_bbox_wh'])>=7 and results[off]['white_pixels']==0 and results[on]['white_pixels']==0
report = {
    'threshold':{'min_colored_pixels':40,'min_bbox_side_px':7,'max_white_pixels':0},
    'checks':checks,'same_camera_comparisons':paired,
    'method': 'Pillow左上原点原生PNG；Godot逐三角形屏幕投影掩膜，仅统计灯几何内像素。最终门禁进一步要求同镜头off/A对应像素红→绿且差值>=30，以排除机身与UI。原始分类、成对确认、白烧像素分开记录，前后镜头严格相等。',
    'visibility_passed': all(checks.values()),
    'images': results,
}
(OUT / 'pixel_metrics_runtime.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False, indent=2))
