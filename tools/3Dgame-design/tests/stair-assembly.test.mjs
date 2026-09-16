import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { stairProfileParts } from '../src/stair-profile.mjs';
import { validateFixedModules } from '../component-policy.mjs';
const scene=JSON.parse(fs.readFileSync(new URL('../../../source/art/whitebox/tower_zones/stairs/v015/data/whitebox_tower_stairs_v015.json',import.meta.url)));
const profile=JSON.parse(fs.readFileSync(new URL('../src/stair-flight-profile.json',import.meta.url)));
const settings=scene.components.find(c=>c.stairwellSettings).stairwellSettings;
const zThickness=part=>Math.max(...part.vertices.map(p=>p[2]))-Math.min(...part.vertices.map(p=>p[2]));

test('both stairwells retain original roots and each lower floor uses 18 fixed tiles',()=>{
  assert.deepEqual(scene.groups[0].position,{x:-32.5,y:0,z:0});
  assert.deepEqual(scene.groups[3].position,{x:32.5,y:0,z:-9});
  for(const code of ['A','B']) {
    const tiles=scene.components.filter(c=>c.name.startsWith(code+'_LowerDoorLanding'));
    assert.equal(tiles.length,18);
    assert.ok(Math.abs(tiles.reduce((sum,c)=>sum+c.surfaceSettings.length*c.surfaceSettings.width,0)-450)<.002);
    tiles.forEach(c=>assert.ok(Math.abs(c.surfaceSettings.length-5)<.0001 && Math.abs(c.surfaceSettings.width-5)<.0001));
  }
  validateFixedModules(scene);
});
test('surface, parent group, and stair scale are rejected',()=>{
  for(const target of ['surface','group','stair']) {
    const copy=structuredClone(scene);
    const item=target==='group'?copy.groups[0]:copy.components.find(c=>target==='stair'?c.stairwellSettings:c.surfaceSettings);
    item.scale.z=2;
    assert.throws(()=>validateFixedModules(copy),/不能缩放/);
  }
});
test('default flight retains the original first tread vertices',()=>{
  const actual=stairProfileParts(profile,settings).find(p=>p.name==='踏步_1');
  const expected=profile.parts.find(p=>p.role==='tread');
  actual.vertices.forEach((p,i)=>p.forEach((value,j)=>assert.ok(Math.abs(value-expected.vertices[i][j])<.00001)));
});
test('height and angle changes preserve tread thickness and match the requested rise',()=>{
  const baseline=stairProfileParts(profile,settings).filter(p=>p.name.startsWith('踏步_'));
  const changed=stairProfileParts(profile,{...settings,runLength:18,slopeDeg:Math.atan2(9,18)*180/Math.PI}).filter(p=>p.name.startsWith('踏步_'));
  changed.forEach((part,i)=>assert.ok(Math.abs(zThickness(part)-zThickness(baseline[i]))<.000001));
  assert.ok(Math.abs((changed[0].vertices[0][2]-changed.at(-1).vertices[0][2])*20/19-9)<.000001);
});
