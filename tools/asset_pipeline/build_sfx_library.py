#!/usr/bin/env python3
"""Render the authored industrial SFX library. Offline originals, no sampled content.

Requires numpy/scipy and ffmpeg. Each asset retains 24-bit master, separate stems,
seed, authoring recipe and exact runtime hash. Outputs are staged outside the game;
--install explicitly publishes the staged catalog and OGG files.
"""
from __future__ import annotations
import argparse, hashlib, json, math, shutil, subprocess, sys
from pathlib import Path
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from workspace_paths import work_path
RATE=44100
CONTRACT=ROOT/'art_source/audio/sfx/library_contract.json'

def db(x): return 10**(x/20)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

class Voice:
 def __init__(self, duration, seed):
  self.n=round(duration*RATE); self.t=np.arange(self.n)/RATE
  self.rng=np.random.default_rng(seed); self.stems={}
 def add(self,name,x): self.stems[name]=self.stems.get(name,0)+x
 def env(self,start=0,decay=.08,attack=.001):
  t=np.maximum(self.t-start,0)
  return (self.t>=start)*(1-np.exp(-t/attack))*np.exp(-t/decay)
 def tone(self,name,f=100,amp=1,start=0,decay=.1,drop=0,attack=.001,ratio=0):
  t=np.maximum(self.t-start,0)
  phase=2*np.pi*(f*t+drop*.025*(1-np.exp(-t/.025)))
  carrier=np.sin(phase+ratio*np.sin(phase*1.417)*np.exp(-t/.05))
  self.add(name,amp*carrier*self.env(start,decay,attack))
 def noise(self,name,amp=1,start=0,decay=.08,lo=200,hi=8000,attack=.0006):
  raw=self.rng.normal(0,1,self.n)
  filt=signal.sosfilt(signal.butter(2,[lo,hi],btype='bandpass',fs=RATE,output='sos'),raw)
  filt/=max(np.std(filt),.0001)
  self.add(name,filt*amp*self.env(start,decay,attack))
 def metal(self,name,f=700,amp=.2,start=0,decay=.07):
  for i,r in enumerate([1,1.47,2.09,2.71,3.86]):
   self.tone(name,f*r,amp/(1+i)**1.4,start,decay/(1+i*.6),attack=.0004)
 def click(self,start=0,weight=1,f=1000):
  self.noise('mechanism',.23*weight,start,.003,1500,10000)
  self.metal('mechanism',f,.13*weight,start,.018)
  self.tone('mechanism',230,.13*weight,start,.009)
 def sequence(self,notes,step=.1,amp=.2,decay=.12,start=.006):
  for i,f in enumerate(notes):
   self.tone('electronic_identity',f,amp,start+i*step,decay,attack=.004)
   self.tone('electronic_identity',f*2.003,amp*.13,start+i*step,decay*.42,attack=.003)
 def sweep(self,name,f0,f1,duration,amp=.3,start=0,noise=False):
  t=np.clip(self.t-start,0,duration); p=t/duration
  env=np.sin(np.pi*p)**1.4*(self.t>=start)*(self.t<start+duration)
  if noise:
   x=signal.sosfilt(signal.butter(2,[f0,f1],btype='bandpass',fs=RATE,output='sos'),self.rng.normal(size=self.n))
   self.add(name,x*env*amp)
  else:
   phase=2*np.pi*(f0*t+(f1-f0)*t*t/(2*duration))
   self.add(name,(np.sin(phase)+.17*np.sin(2.017*phase))*env*amp)

def render(spec,variant):
 seed=int(hashlib.sha256((spec['key']+str(variant)+'industrial-r2').encode()).hexdigest()[:8],16)
 v=Voice(spec['duration'],seed); p=spec['preset']; f=spec.get('frequency',160)
 # Variants alter real transient/noise/modal construction, not playback pitch alone.
 f*=1+(variant%3-1)*.017
 if p=='gun':
  caliber=spec.get('weight',1); tail=spec.get('tail',.11)
  v.noise('muzzle_crack',.8,0,.008+caliber*.003,900,11000)
  v.noise('combustion',.36,0,tail*.5,55,1800)
  v.tone('body',f,.7,0,.036+caliber*.024,drop=f*2)
  v.tone('body',f*.49,.24,.005,.045+caliber*.016,drop=25)
  v.click(.021+variant*.001,.65,1600); v.click(.058,.3,950)
  v.noise('room_tail',.11,.018,tail,100,2200,attack=.007)
  v.metal('receiver',630/caliber,.065,.012,.035)
 elif p=='laser':
  v.tone('energy_core',210,.42,0,.065,drop=2100,ratio=3.7)
  v.tone('energy_core',87,.28,.003,.052,drop=330,ratio=1.9)
  v.noise('ion_snap',.2,0,.006,2400,11500)
  v.metal('capacitor',1450,.06,.02,.048)
 elif p in ['impact','hurt','death','explosion','land']:
  weight=spec.get('weight',1)
  v.tone('mass',f,.55,0,.045*weight,drop=f*.8)
  v.noise('contact',.38,0,.015*weight,120,2400)
  v.noise('fracture',.15,.009,.032*weight,1000,7500)
  if p=='hurt': v.tone('body_pressure',64,.18,.017,.085,ratio=.6)
  if p=='death':
   v.noise('collapse',.18,.13,.085,90,1800)
   v.tone('collapse',52,.3,.12,.14,drop=90)
  if p=='explosion':
   v.noise('debris',.23,.05,.33,70,5000)
   for at in [.09,.18,.27,.42]: v.metal('fragments',v.rng.uniform(400,1800),.06,at,.05)
  if p=='impact': v.metal('contact_ring',f*6,.15,0,.035*weight)
 elif p in ['swing','dash']:
  d=spec['duration']*.72
  v.sweep('air',180,6500,d,2.5,noise=True)
  v.sweep('weight',80,460,d,.2)
  v.noise('cloth',.16,.02,.055,500,3000)
  if p=='swing': v.metal('blade',900,.03,d*.47,.06)
 elif p=='footstep':
  v.tone('sole',f,.32,0,.025,drop=45)
  v.noise('heel',.25,0,.011,140,2400)
  v.noise('toe_grit',.18,.034,.025,1000,8500)
  if spec.get('material')=='metal': v.metal('floor',430,.13,0,.05)
  if spec.get('material')=='debris':
   for at in [.021,.044,.076]: v.noise('grit',.14,at,.008,2000,10000)
 elif p in ['mechanical','door','container']:
  v.click(.002,1.3,f*3)
  for i,at in enumerate(spec.get('clicks',[.065,.19,.31])): v.click(at,.5+i*.15,f*(2+i))
  if p in ['door','container']:
   v.sweep('rail_friction',120,2300,spec['duration']*.65,.9,start=.04,noise=True)
   v.tone('motor',74,.12,.06,spec['duration']*.25,ratio=1.2,attack=.015)
   v.tone('end_stop',95,.3,spec['duration']*.65,.045,drop=70)
   v.metal('panel',f,.16,.015,.11)
 elif p=='power':
  rising=spec.get('rising',True)
  v.click(0,.45,1600)
  v.sweep('coil',95 if rising else 1250,1450 if rising else 45,spec['duration']*.8,.26)
  if rising: v.sequence([1046,1568],.07,.11,.075,start=spec['duration']*.77)
  else: v.noise('electrical_decay',.07,.08,spec['duration']*.25,400,5000)
 elif p in ['ui','signal','stinger','enemy']:
  notes=spec.get('notes',[f,f*1.5])
  v.sequence(notes,spec.get('step',.11),spec.get('tone_amp',.23),spec.get('decay',.12))
  if p=='ui': v.click(0,.13,2400)
  if p=='signal': v.metal('relay',950,.04,0,.05)
  if p=='stinger':
   v.tone('industrial_weight',f,.42,0,.23,drop=f*.4,ratio=.35)
   v.noise('impact_air',.17,0,.13,70,2200)
   v.metal('steel_resonance',f*3,.12,.04,.22)
  if p=='enemy':
   v.tone('vocal_resonator',f,.28,0,.11,drop=f*.5,ratio=2.6)
   v.noise('breath_grit',.12,0,.09,240,2200,attack=.01)
 elif p=='ambience':
  # Integer cycles and a periodic noise spectrum make a seamless mathematical bed.
  n=v.n; freqs=np.fft.rfftfreq(n,1/RATE)
  spectrum=(v.rng.normal(size=len(freqs))+1j*v.rng.normal(size=len(freqs)))
  spectrum*=1/np.maximum(freqs,35)**.8
  spectrum[(freqs<35)|(freqs>spec.get('cutoff',2500))]=0
  bed=np.fft.irfft(spectrum,n); bed/=np.std(bed)
  modulation=1+.15*np.sin(2*np.pi*v.t/spec['duration'])
  v.add('room_air',bed*.07*modulation)
  base=round(f*spec['duration'])/spec['duration']
  v.add('machinery',.09*np.sin(2*np.pi*base*v.t)+.025*np.sin(2*np.pi*base*2*v.t))
  if spec.get('pulse',False):
   v.add('beacon',.045*np.sin(2*np.pi*round(900*spec['duration'])/spec['duration']*v.t)*(1+np.sin(2*np.pi*4*v.t/spec['duration']))**3/8)
 else: raise ValueError(p)
 # Remove subsonic energy and leave a true fade for one-shots, preserving onsets.
 stems={}
 for name,x in v.stems.items():
  x=signal.sosfilt(signal.butter(2,28,btype='highpass',fs=RATE,output='sos'),x) if p!='ambience' else x-x.mean()
  if p!='ambience':
   x[:44]*=np.linspace(0,1,44)
   nr=min(round(.045*RATE),len(x)//4); x[-nr:]*=np.linspace(1,0,nr)**2
  stems[name]=x
 summed=sum(stems.values()); peak=max(abs(summed).max(),1e-9)
 gain=db(spec['peak_db'])/peak
 stems={k:x*gain for k,x in stems.items()}; summed*=gain
 return seed,stems,summed

def write24(path,x):
 path.parent.mkdir(parents=True,exist_ok=True)
 # WAVE PCM 24, little endian, no dithering of known digital silence.
 import wave
 ints=np.rint(np.clip(x,-1,1)*(2**23-1)).astype('<i4')
 frames=ints.view(np.uint8).reshape(-1,4)[:,:3].tobytes()
 with wave.open(str(path),'wb') as w:
  w.setnchannels(1); w.setsampwidth(3); w.setframerate(RATE); w.writeframes(frames)

def main():
 parser=argparse.ArgumentParser(); parser.add_argument('--install',action='store_true'); args=parser.parse_args()
 contract=json.loads(CONTRACT.read_text(encoding='utf-8'))
 stage=work_path('sessions/2026-10-13_sfx_rebuild/staged/catalog.json').parent
 catalog={'schema_version':1,'revision':'industrial-r2','sample_rate':RATE,'sound_sets':{},'events':{},'legacy':{},'assets':[]}
 for spec in contract['sounds']:
  key=spec['key']; version=2 if spec.get('legacy') else 1
  paths=[]
  for var in range(spec.get('variants',1)):
   suffix='' if var==0 else '_alt%02d'%(var+1)
   asset='AUD-SFX-'+key.upper().replace('_','-')+('' if var==0 else '-VAR%02d'%(var+1))
   filename=f'{key}{suffix}_v{version:03d}'
   source=ROOT/'art_source/audio/sfx'/asset/'source'
   seed,stems,mix=render(spec,var)
   master=source/(filename+'.wav'); write24(master,mix)
   for name,x in stems.items(): write24(source/'stems'/(name+'.wav'),x)
   runtime=stage/(filename+'.ogg')
   subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(master),'-c:a','libvorbis','-q:a','6',str(runtime)],check=True)
   path='res://src/assets/audio/sfx/'+runtime.name; paths.append(path)
   record={'asset_id':asset,'key':key,'variant':var,'source_path':master.relative_to(ROOT).as_posix(),'runtime_path':path,'version':version,'duration_sec':spec['duration'],'source_format':'PCM24 WAV','runtime_format':'OGG Vorbis q6','sample_rate_hz':RATE,'source_channels':1,'runtime_channels':1,'sha256':sha(runtime),'source_sha256':sha(master),'seed':seed,'license_source':'Original deterministic DSP synthesis; no external samples','license_scope':'Project-owned authored recipe; no third-party sample license','status':'imported_pending_listening','spatial_mode':spec['spatial_mode'],'loop':spec['preset']=='ambience','peak_target_db':spec['peak_db'],'event_ids':spec['events'],'sound_set_id':'SFXSET-'+key.upper().replace('_','-')}
   (source/'recipe.json').write_text(json.dumps({'renderer':'tools/asset_pipeline/build_sfx_library.py','renderer_sha256':sha(Path(__file__)),'spec':spec,'asset':record,'stems':list(stems)},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
   catalog['assets'].append(record)
  catalog['sound_sets'][key]={'id':'SFXSET-'+key.upper().replace('_','-'),'paths':paths,'loop':spec['preset']=='ambience','spatial_mode':spec['spatial_mode'],'bus':spec['bus'],'max_voices':spec['max_voices'],'priority':spec['priority']}
  if spec.get('legacy'): catalog['legacy'][key]=key
  for event in spec['events']:
   if event in catalog['events']: raise ValueError('Duplicate event '+event)
   catalog['events'][event]={'sound_set':key,'cue_id':'CUE-'+event.upper().replace('.','-'),'owner':spec['owner'],'trigger_fact':spec['trigger_fact'],'ai_signal':'domain_owned_unchanged','fallback_policy':'silence_and_report_once','acceptance_case':'verify_audio_library_flow','binding_status':'legacy_adapter' if spec.get('legacy') else 'asset_ready_domain_binding_pending'}
  print(key,len(paths),flush=True)
 (stage/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 if args.install:
  dest=ROOT/'src/assets/audio/sfx'
  for p in stage.glob('*.ogg'): shutil.copy2(p,dest/p.name)
  shutil.copy2(stage/'catalog.json',dest/'sfx_catalog.json')
 print(json.dumps({'sound_sets':len(catalog['sound_sets']),'assets':len(catalog['assets']),'events':len(catalog['events']),'installed':args.install}))

if __name__=='__main__': main()
