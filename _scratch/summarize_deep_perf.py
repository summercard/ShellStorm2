import json,sys,statistics as st
from pathlib import Path
p=Path(sys.argv[1] if len(sys.argv)>1 else 'outputs/deep_perf_live_20261004.json')
d=json.loads(p.read_text(encoding='utf-8'))
print('metadata',d['metadata'])
for phase in d['phases']:
    name=phase['name']; samples=[s for s in d['samples'] if s['phase']==name]
    print('\nPHASE',phase,'gpu median',round(st.median(s['gpu'] for s in samples),3),'locked',sum(s['locked'] for s in samples))
    labels={}
    for s in samples:
        for k,v in d['spans'].get(str(s['frame']-1),{}).items(): labels.setdefault(k,[]).append(v[0]/1000)
    print('SPANS',[(k,round(st.median(v),3),round(max(v),3)) for k,v in sorted(labels.items(),key=lambda i:max(i[1]),reverse=True)][:14])
    for s in sorted(samples,key=lambda s:s['ms'],reverse=True)[:4]:
        spans=d['spans'].get(str(s['frame']-1),{})
        print('LONG',s['frame'],round(s['ms'],3),round(s['gpu'],3),s['position'],sorted([(k,v[0]/1000) for k,v in spans.items()],key=lambda x:x[1],reverse=True)[:5])
print('EVENTS',d['events'])
