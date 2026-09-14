import json
import math
from pathlib import Path

def profile_parts(settings):
    profile = json.loads((Path(__file__).resolve().parent.parent / 'src/stair-flight-profile.json').read_text())
    count = max(4, round(settings['stepCount']))
    run = max(3, settings['runLength'])
    rise = run * math.tan(math.radians(max(5, min(60, settings['slopeDeg']))))
    result = []
    for part in profile['parts']:
        if part['name'] in settings.get('omitParts',[]): continue
        for i in range(count if part['role'] == 'tread' else 1):
            vertices = []
            for x,y,z in part['vertices']:
                if part['role'] == 'tread':
                    vertices.append((x*(settings['width']-.42)/5.58,(i+.5)*run/count+.125+(y-.5)*(run/count-.03)/.72,z-i*rise/count))
                else:
                    vertices.append((x*settings['width']/6,y*run/15,z+y*.4-y/15*rise+(settings['handrailHeight']-1.2 if part['role']=='guard' else 0)))
            result.append(dict(name=f'踏步_{i+1}' if part['role']=='tread' else part['name'],vertices=vertices,faces=part['faces']))
    return result
