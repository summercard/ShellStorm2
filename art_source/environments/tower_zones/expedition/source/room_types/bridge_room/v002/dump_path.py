import bpy,os,json,sys
argv=sys.argv[sys.argv.index('--')+1:]
target=argv[0] if argv else ''
rows=[]
for i in bpy.data.images:
    fp=i.filepath; ab=bpy.path.abspath(fp) if fp else ''
    rows.append({'name':i.name,'filepath':fp,'is_relative':fp.startswith('//'),'norm':os.path.normpath(ab),'exists_norm':os.path.exists(os.path.normpath(ab))})
from pathlib import Path
Path(target).write_text(json.dumps({'blend':bpy.data.filepath,'images':rows},ensure_ascii=False,indent=1),encoding='utf-8')
