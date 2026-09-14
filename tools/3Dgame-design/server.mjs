import { createServer as createViteServer } from 'vite';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readProjectBlocks, requireProjectBlock } from './project-blocks.mjs';

const root = path.dirname(fileURLToPath(import.meta.url));
const saveRoot = path.join(root, 'save');
const activePreviewPath = path.join(saveRoot, 'active-preview.json');
const blockSaveRoot = path.join(saveRoot, 'blocks');
const port = Number(process.env.PORT || 4173);
const safeName = value => String(value || '').replace(/[\\/:*?"<>|]/g, '_').trim().slice(0, 80) || '未命名场景';
const coordinateSystem = 'blender-z-up';
const componentTypes = [
  '成人角色 · 1.6m / 4头身', '儿童角色 · 1.1m / 2头身', '墙壁', '地板', '门', '窗', '桌子', '柜子', '衣柜', '电视柜', '椅子', '沙发', '懒人沙发', '床',
  '办公桌', '办公椅', '显示器', '笔记本电脑', '文件柜', '书架', '打印机', '饮水机', '会议桌', '白板', '路灯', '箱子', '楼梯'
];

const vector = (value, fallback) => ({
  x: Number.isFinite(value?.x) ? value.x : fallback.x,
  y: Number.isFinite(value?.y) ? value.y : fallback.y,
  z: Number.isFinite(value?.z) ? value.z : fallback.z
});
const uniqueName = (components, preferred) => {
  const base = safeName(preferred);
  if (!components.some(component => component.name === base)) return base;
  let index = 2;
  while (components.some(component => component.name === `${base}_${index}`)) index += 1;
  return `${base}_${index}`;
};
async function readScenePayload(id) {
  const sceneId = safeName(id);
  let filePath = path.join(saveRoot, sceneId, 'scene.json'), raw;
  try { raw = await fs.readFile(filePath, 'utf8'); } catch { filePath = path.join(saveRoot, sceneId, 'scene-preview.json'); raw = await fs.readFile(filePath, 'utf8'); }
  const parsed = JSON.parse(raw);
  const payload = Array.isArray(parsed) ? { version: 1, savedAt: (await fs.stat(filePath)).mtime.toISOString(), name: sceneId, components: parsed } : parsed;
  if (filePath.endsWith('scene-preview.json') || Array.isArray(parsed)) await fs.writeFile(path.join(saveRoot, sceneId, 'scene.json'), JSON.stringify(payload, null, 2), 'utf8');
  return { id: sceneId, payload };
}
async function writeScenePayload(id, payload) {
  const sceneId = safeName(id), folder = path.join(saveRoot, sceneId);
  await fs.mkdir(folder, { recursive: true });
  payload.id = sceneId; payload.name = payload.name || sceneId; payload.savedAt = new Date().toISOString();
  await fs.writeFile(path.join(folder, 'scene.json'), JSON.stringify(payload, null, 2), 'utf8');
  return payload;
}
const blockSceneFolder = (blockId, sceneId) => path.join(blockSaveRoot, safeName(blockId), safeName(sceneId));
async function readBlockScenePayload(blockId, id) {
  const block = await requireProjectBlock(blockId), sceneId = safeName(id);
  const filePath = path.join(blockSceneFolder(block.id, sceneId), 'scene.json');
  const payload = JSON.parse(await fs.readFile(filePath, 'utf8'));
  return { id: sceneId, block, payload };
}
async function writeBlockScenePayload(blockId, id, payload) {
  const block = await requireProjectBlock(blockId), sceneId = safeName(id), folder = blockSceneFolder(block.id, sceneId);
  await fs.mkdir(folder, { recursive: true });
  payload.id = sceneId; payload.name = payload.name || sceneId; payload.savedAt = new Date().toISOString();
  payload.project = { ...(payload.project || {}), blockId: block.id, blockName: block.name, blockNodePath: block.nodePath, floorRange: block.floorRange };
  await fs.writeFile(path.join(folder, 'scene.json'), JSON.stringify(payload, null, 2), 'utf8');
  return payload;
}
async function readActivePreview() {
  try { return JSON.parse(await fs.readFile(activePreviewPath, 'utf8')); }
  catch { return { sceneId: null, updatedAt: null }; }
}
async function writeActivePreview(sceneId, blockId = null) {
  const record = { blockId: blockId ? safeName(blockId) : null, sceneId: sceneId ? safeName(sceneId) : null, updatedAt: new Date().toISOString() };
  await fs.writeFile(activePreviewPath, JSON.stringify(record, null, 2), 'utf8');
  return record;
}
function applyAiOperations(payload, operations) {
  if (!Array.isArray(operations) || !operations.length) throw new Error('operations 不能为空');
  payload.components ||= [];
  payload.groups ||= [];
  const changed = [];
  for (const operation of operations) {
    if (!operation || typeof operation !== 'object') throw new Error('命令必须是对象');
    if (operation.op === 'add') {
      const source = operation.component || {};
      if (!componentTypes.includes(source.type)) throw new Error(`不支持的组件类型：${source.type || '未提供'}`);
      const name = uniqueName(payload.components, source.name || source.type);
      const component = {
        name, type: source.type, group: source.group || null,
        position: vector(source.position, { x: 0, y: 0, z: 0 }),
        rotation: vector(source.rotation, { x: 0, y: 0, z: 0 }),
        scale: vector(source.scale, { x: 1, y: 1, z: 1 })
      };
      ['characterSettings', 'surfaceSettings', 'chairSettings', 'tableSettings', 'stairSettings'].forEach(key => { if (source[key]) component[key] = source[key]; });
      payload.components.push(component); changed.push({ op: 'add', name });
      continue;
    }
    if (operation.op === 'remove') {
      const index = payload.components.findIndex(component => component.name === operation.name);
      if (index < 0) throw new Error(`找不到组件：${operation.name}`);
      payload.components.splice(index, 1); changed.push({ op: 'remove', name: operation.name });
      continue;
    }
    if (operation.op === 'update') {
      const component = payload.components.find(item => item.name === operation.name);
      if (!component) throw new Error(`找不到组件：${operation.name}`);
      const patch = operation.patch || {};
      if (patch.position) component.position = vector(patch.position, component.position);
      if (patch.rotation) component.rotation = vector(patch.rotation, component.rotation);
      if (patch.scale) component.scale = vector(patch.scale, component.scale);
      if (typeof patch.group === 'string' || patch.group === null) component.group = patch.group;
      ['characterSettings', 'surfaceSettings', 'chairSettings', 'tableSettings', 'stairSettings'].forEach(key => { if (patch[key]) component[key] = patch[key]; });
      if (patch.name && patch.name !== component.name) component.name = uniqueName(payload.components.filter(item => item !== component), patch.name);
      changed.push({ op: 'update', name: component.name });
      continue;
    }
    throw new Error(`不支持的命令：${operation.op}`);
  }
  payload.version = 3;
  payload.coordinateSystem = coordinateSystem;
  payload.axes = { right: 'X', forward: '-Y', up: 'Z' };
  payload.units = { distance: 'm', rotation: 'deg' };
  return changed;
}

async function ensureSaveRoot() { await fs.mkdir(saveRoot, { recursive: true }); }
async function readBlockScenes(blockId) {
  const block = await requireProjectBlock(blockId), folder = path.join(blockSaveRoot, block.id), scenes = [];
  let entries = []; try { entries = await fs.readdir(folder, { withFileTypes: true }); } catch { return []; }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    try {
      const payload = JSON.parse(await fs.readFile(path.join(folder, entry.name, 'scene.json'), 'utf8'));
      scenes.push({ id: entry.name, blockId: block.id, name: payload.name || entry.name, updatedAt: payload.savedAt || new Date().toISOString() });
    } catch { /* ignore incomplete scene folders */ }
  }
  return scenes.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
}
async function readScenes() {
  await ensureSaveRoot(); const entries = await fs.readdir(saveRoot, { withFileTypes: true }); const scenes = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    try {
      let filePath = path.join(saveRoot, entry.name, 'scene.json');
      let raw;
      try { raw = await fs.readFile(filePath, 'utf8'); } catch { filePath = path.join(saveRoot, entry.name, 'scene-preview.json'); raw = await fs.readFile(filePath, 'utf8'); }
      const parsed = JSON.parse(raw), payload = Array.isArray(parsed) ? { version: 1, savedAt: (await fs.stat(filePath)).mtime.toISOString(), name: entry.name, components: parsed } : parsed;
      scenes.push({ id: entry.name, name: payload.name || entry.name, updatedAt: payload.savedAt || new Date().toISOString() });
    } catch { /* ignore incomplete folders */ }
  }
  const sorted = scenes.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
  await fs.writeFile(path.join(saveRoot, 'index.json'), JSON.stringify({ version: 1, scenes: sorted }, null, 2), 'utf8');
  return sorted;
}
function json(res, status, body) { res.statusCode = status; res.setHeader('Content-Type', 'application/json; charset=utf-8'); res.end(JSON.stringify(body)); }
async function api(req, res, url) {
  if (req.method === 'GET' && url.pathname === '/api/blocks') {
    try { return json(res, 200, await readProjectBlocks()); }
    catch (error) { return json(res, 500, { error: error.message }); }
  }
  if (req.method === 'GET' && url.pathname === '/api/preview') return json(res, 200, await readActivePreview());
  if (req.method === 'POST' && url.pathname === '/api/preview') {
    let body = ''; for await (const chunk of req) body += chunk;
    try {
      const { blockId, sceneId } = JSON.parse(body);
      if (sceneId) blockId ? await readBlockScenePayload(blockId, sceneId) : await readScenePayload(sceneId);
      return json(res, 200, await writeActivePreview(sceneId, blockId));
    } catch { return json(res, 400, { error: '当前预览场景不存在' }); }
  }
  if (req.method === 'GET' && url.pathname === '/api/ai/schema') return json(res, 200, {
    version: 1,
    coordinateSystem,
    units: { distance: 'm', rotation: 'deg' },
    componentTypes,
    operations: ['add', 'update', 'remove'],
    endpoint: 'POST /api/ai/scenes/:sceneId/commands'
  });
  const blockSceneMatch = url.pathname.match(/^\/api\/blocks\/([^/]+)\/scenes(?:\/([^/]+))?$/);
  if (blockSceneMatch && req.method === 'GET') {
    const blockId = decodeURIComponent(blockSceneMatch[1]), sceneId = blockSceneMatch[2] && decodeURIComponent(blockSceneMatch[2]);
    try { return json(res, 200, sceneId ? (await readBlockScenePayload(blockId, sceneId)).payload : { scenes: await readBlockScenes(blockId) }); }
    catch (error) { return json(res, 404, { error: error.message || '区块或场景不存在' }); }
  }
  if (blockSceneMatch && req.method === 'POST' && !blockSceneMatch[2]) {
    let body = ''; for await (const chunk of req) body += chunk;
    try {
      const blockId = decodeURIComponent(blockSceneMatch[1]), input = JSON.parse(body), name = safeName(input.name), payload = input.payload;
      if (!payload?.components) return json(res, 400, { error: '场景数据无效' });
      await writeBlockScenePayload(blockId, name, payload);
      return json(res, 200, { id: name, blockId, name, updatedAt: payload.savedAt });
    } catch (error) { return json(res, 400, { error: error.message || '保存失败' }); }
  }
  const blockAiMatch = url.pathname.match(/^\/api\/ai\/blocks\/([^/]+)\/scenes\/([^/]+)\/commands$/);
  if (req.method === 'POST' && blockAiMatch) {
    let body = ''; for await (const chunk of req) body += chunk;
    try {
      const blockId = decodeURIComponent(blockAiMatch[1]), id = decodeURIComponent(blockAiMatch[2]);
      const input = JSON.parse(body), { payload } = await readBlockScenePayload(blockId, id);
      const changed = applyAiOperations(payload, input.operations); await writeBlockScenePayload(blockId, id, payload);
      return json(res, 200, { scene: payload, changed });
    } catch (error) { return json(res, 400, { error: error.message || 'AI 编辑命令执行失败' }); }
  }
  if (req.method === 'POST' && /^\/api\/ai\/scenes\/[^/]+\/commands$/.test(url.pathname)) {
    let body = ''; for await (const chunk of req) body += chunk;
    try {
      const id = decodeURIComponent(url.pathname.split('/')[4]);
      const input = JSON.parse(body), { payload } = await readScenePayload(id);
      const changed = applyAiOperations(payload, input.operations);
      await writeScenePayload(id, payload);
      await readScenes();
      return json(res, 200, { scene: payload, changed });
    } catch (error) { return json(res, 400, { error: error.message || 'AI 编辑命令执行失败' }); }
  }
  if (req.method === 'GET' && url.pathname === '/api/scenes') return json(res, 200, { scenes: await readScenes() });
  if (req.method === 'GET' && url.pathname.startsWith('/api/scenes/')) {
    const id = decodeURIComponent(url.pathname.slice('/api/scenes/'.length));
    try {
      const { payload } = await readScenePayload(id);
      return json(res, 200, payload);
    } catch { return json(res, 404, { error: '场景不存在' }); }
  }
  if (req.method === 'POST' && url.pathname === '/api/scenes') {
    let body = ''; for await (const chunk of req) body += chunk;
    try {
      const input = JSON.parse(body), name = safeName(input.name), payload = input.payload;
      if (!payload?.components) return json(res, 400, { error: '场景数据无效' });
      await writeScenePayload(name, payload);
      const scenes = await readScenes(); await fs.writeFile(path.join(saveRoot, 'index.json'), JSON.stringify({ version: 1, scenes }, null, 2), 'utf8');
      return json(res, 200, { id: name, name, updatedAt: payload.savedAt });
    } catch { return json(res, 400, { error: '保存失败' }); }
  }
  return false;
}

await ensureSaveRoot();
const vite = await createViteServer({ root, server: { middlewareMode: true, host: '0.0.0.0', port } });
const server = (await import('node:http')).createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  if (url.pathname.startsWith('/api/')) { try { const handled = await api(req, res, url); if (handled !== false) return; } catch { return json(res, 500, { error: '服务异常' }); } }
  vite.middlewares(req, res, () => { res.statusCode = 404; res.end('Not found'); });
});
server.listen(port, '0.0.0.0', () => console.log(`SceneKit local server: http://0.0.0.0:${port}`));
