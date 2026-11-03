"""Recorded Foley edits: PCM24 masters, OGG runtime assets, retained licenses."""
from array import array
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
import wave
import zipfile
from special_items_workspace import ROOT, write, work_path
RATE=44100
SPECS=[('throw',.24),('blast',.85),('glass',.62),('pour',.32),('ignite',.42),('fire_loop',1.5)]
BANK=ROOT/'art_source/audio/sfx/special_items_recordings/source'
BANK.mkdir(parents=True,exist_ok=True)
FFMPEG='C:/ffmpeg/bin/ffmpeg.exe'
catalog_path='src/assets/audio/sfx/sfx_catalog.json'
catalog=json.loads((ROOT/catalog_path).read_text(encoding='utf-8'))
sources={}
for kind,filename,page,url in [
    ('fire','fire_recording.wav','https://opengameart.org/content/fireplace-sound-loop','https://opengameart.org/sites/default/files/fire.wav'),
    ('water','water_splash_recording.wav','https://opengameart.org/content/water-splash-and-sand-footsteps','https://opengameart.org/sites/default/files/splash1_0.wav')]:
    target=BANK/filename
    if not target.exists():
        with urllib.request.urlopen(url,timeout=40) as response:
            target.write_bytes(response.read())
    evidence=BANK.parent/('license_'+kind+'.json')
    if not evidence.exists():
        html=urllib.request.urlopen(page,timeout=40).read().decode('utf-8')
        if 'creativecommons.org/publicdomain/zero/1.0' not in html:
            raise RuntimeError('CC0 license evidence missing: '+page)
    sources[kind]={'path':target.relative_to(ROOT).as_posix(),'source_url':page,'download_url':url,'license':'CC0-1.0','sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    write(evidence.relative_to(ROOT).as_posix(),json.dumps(sources[kind],ensure_ascii=False,indent=2)+'\n')
glass=BANK/'kenney_impactGlass_heavy_002.ogg'
if not glass.exists():
    archive=work_path('sessions/2026-10-19_natural_world_audio/intake/impact.zip')
    with zipfile.ZipFile(archive) as pack:
        glass.write_bytes(pack.read('Audio/impactGlass_heavy_002.ogg'))
sources['glass']={'path':glass.relative_to(ROOT).as_posix(),'source_url':'https://kenney.nl/assets/impact-sounds','license':'CC0-1.0','credit':'Kenney','sha256':hashlib.sha256(glass.read_bytes()).hexdigest()}
for key in ['melee_swing','enemy_explosion']:
    asset=next(a for a in catalog['assets'] if a['key']==key and a['variant']==0)
    sources[key]={'path':asset['source_path'],'source_url':asset['license_source'],'license':asset['license_scope'],'sha256':asset['source_sha256']}
pcm={}
def decode(path):
    if path not in pcm:
        data=subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-i',str(ROOT/path),'-f','f32le','-ar',str(RATE),'-ac','1','pipe:1'],stdout=subprocess.PIPE,check=True).stdout
        values=array('f');values.frombytes(data);pcm[path]=values
    return pcm[path]
manifest=[]
for kind,duration in SPECS:
    source_key={'throw':'melee_swing','blast':'enemy_explosion','glass':'glass','pour':'water','ignite':'fire','fire_loop':'fire'}[kind]
    input_info=sources[source_key];input_pcm=decode(input_info['path'])
    offset=2.0 if kind=='fire_loop' else (0.5 if kind=='ignite' else 0.0)
    start=int(offset*RATE);count=int(duration*RATE)
    samples=[float(input_pcm[start+i]) if start+i<len(input_pcm) else 0.0 for i in range(count)]
    used_sources=[input_info]
    if kind=='ignite':
        swish=decode(sources['melee_swing']['path'])
        for i in range(min(len(swish),len(samples))):
            samples[i]+=float(swish[i])*.5
        used_sources.append(sources['melee_swing'])
    if kind=='fire_loop':
        crossfade=int(RATE*.08)
        for i in range(crossfade):
            f=i/(crossfade-1)
            samples[-crossfade+i]=samples[-crossfade+i]*(1-f)+samples[i]*f
        samples=samples[crossfade:]
    else:
        for i in range(len(samples)):
            samples[i]*=min(1,i/(RATE*.004),max(0,(len(samples)-1-i)/(RATE*.045)))
    peak=max(abs(v) for v in samples)
    if peak<.000001:
        raise RuntimeError('Silent source edit: '+kind)
    samples=[max(-1,min(1,v*.5/peak)) for v in samples]
    asset_id='AUD-SFX-SPECIAL-'+kind.upper().replace('_','-')
    source=f'art_source/audio/sfx/{asset_id}/source/special_{kind}_master_v001.wav'
    target=f'src/assets/audio/sfx/special_{kind}_v001.ogg'
    path=ROOT/source;path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as audio:
        audio.setnchannels(1);audio.setsampwidth(3);audio.setframerate(RATE)
        audio.writeframes(b''.join(round(value*8388607).to_bytes(3,'little',signed=True) for value in samples))
    subprocess.run([FFMPEG,'-hide_banner','-loglevel','error','-y','-i',str(path),'-c:a','libvorbis','-q:a','5','-ar',str(RATE),'-ac','1',str(ROOT/target)],check=True)
    entry={'asset_id':asset_id,'kind':kind,'source':source,'path':target,'duration_seconds':len(samples)/RATE,'sample_rate':RATE,'channels':1,'peak_dbfs':-6.02,
           'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'sha256':hashlib.sha256((ROOT/target).read_bytes()).hexdigest(),
           'license':'; '.join(sorted({s['license'] for s in used_sources})),'license_source':'; '.join(s['source_url'] for s in used_sources),
           'inputs':used_sources,'recipe':{'builder':'scripts/build_special_item_audio.py','offset_seconds':offset,'crossfade_seconds':.08 if kind=='fire_loop' else 0.0,'edits':'linear layering, trim/pad, fades, peak normalization'}}
    write(str(Path(source).parent.parent/'recipe.json').replace('\\','/'),json.dumps(entry,ensure_ascii=False,indent=2)+'\n')
    manifest.append(entry)
    key='special_'+kind;event='special.'+kind
    catalog['sound_sets'][key]={'id':'SFXSET-SPECIAL-'+kind.upper().replace('_','-'),'paths':['res://'+target],'loop':kind=='fire_loop','spatial_mode':'world_3d','bus':'WorldSFX','max_voices':1 if kind=='fire_loop' else (2 if kind=='pour' else 4),'priority':'P1' if kind=='blast' else 'P2'}
    catalog['events'][event]={'sound_set':key,'cue_id':'CUE-SPECIAL-'+kind.upper().replace('_','-'),'owner':'SpecialItemWorld3D' if kind!='pour' else 'SpecialItemController3D',
                             'trigger_fact':'successful special item domain edge','ai_signal':'domain_owned_unchanged','fallback_policy':'silence_and_report_once','acceptance_case':'verify_special_items_system','binding_status':'active'}
    asset={'asset_id':asset_id,'key':key,'variant':0,'source_path':source,'runtime_path':'res://'+target,'version':1,'duration_sec':entry['duration_seconds'],
           'source_format':'PCM24 WAV','runtime_format':'OGG Vorbis q5','sample_rate_hz':RATE,'source_channels':1,'runtime_channels':1,
           'sha256':entry['sha256'],'source_sha256':entry['source_sha256'],'production_revision':'special-items-r1','source_method':'Sourced recordings / Foley edits and linear layering; no tone synthesis',
           'license_source':entry['license_source'],'license_scope':entry['license'],'status':'imported_pending_listening','spatial_mode':'world_3d','loop':kind=='fire_loop',
           'peak_target_db':-6.02,'event_ids':[event],'sound_set_id':catalog['sound_sets'][key]['id']}
    catalog['assets']=[a for a in catalog['assets'] if a['asset_id']!=asset_id]+[asset]
    if key not in catalog['world_style_policy']['natural_world_sets']:
        catalog['world_style_policy']['natural_world_sets'].append(key)
catalog['world_style_policy']['changed_assets']=99
catalog['world_style_policy']['revision']='natural-world-r5 + world-environment-r6 + special-items-r1'
catalog['revision']=catalog['revision'].split(' + special-items')[0]+' + special-items-r1'
write(catalog_path,json.dumps(catalog,ensure_ascii=False,indent=2)+'\n')
write('assets/registry/special_items_audio_manifest.json',json.dumps({'schema':'special_items_audio_v1','assets':manifest},ensure_ascii=False,indent=2)+'\n')
credits='\n'.join(f"- {key}: {entry['source_url']} — {entry['license']} — {entry['path']}" for key,entry in sources.items())
write('art_source/audio/sfx/special_items_recordings/CREDITS.md','# Special item recorded Foley sources\n\n'+credits+'\n\nEdits and master recipes: scripts/build_special_item_audio.py. No tone synthesis.\n')
print('SPECIAL_ITEM_AUDIO_OK: six recorded Foley WAV/OGG pairs, 44.1kHz mono; licenses retained')
