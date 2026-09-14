import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { TransformControls } from 'three/examples/jsm/controls/TransformControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import './style.css';

const $ = (s) => document.querySelector(s);
const legacySavedSceneKey = 'scenekit-preview-scene-v1';
const legacyScenesKey = 'scenekit-preview-scenes-v2';
const sceneIndexKey = 'scenekit-preview-scene-index-v3';
const sceneDataKey = id => `scenekit-preview-scene-v3:${id}`;
const undoHistory = [], redoHistory = [], historyLimit = 40;
let activeSceneId = null, activeBlockId = null, activeBlenderSource = null, projectBlocks = [], currentSceneName = 'untitled_scene', pendingSceneAction = null, activeSceneSavedAt = null, sceneSyncInFlight = false;
let clipboardComponent = null;
let saveDirectoryHandle = null;
let activeGroup = null, transformMode = 'translate';
const rotationSnapDegrees = 5;
const rotationSnapRadians = THREE.MathUtils.degToRad(rotationSnapDegrees);
const groupClickTimers = new WeakMap();
const coordinateSystem = 'blender-z-up';
const assetLibraries = [
  { scope: 'common', groups: [
    { name: '角色', open: true, items: [{ type: '成人角色 · 1.6m / 4头身', icon: '♙', tint: '#d9a83d' }, { type: '儿童角色 · 1.1m / 2头身', icon: '♟', tint: '#76a5b4' }] },
    { name: '建筑', open: true, items: [{ type: '墙壁', icon: '▥', tint: '#92a4af' }, { type: '地板', icon: '▤', tint: '#9f8f7a' }, { type: '门', icon: '▯', tint: '#9a6748' }, { type: '窗', icon: '▦', tint: '#70a9c0' }, { type: '楼梯', icon: '▰', tint: '#a47b55' }] }
  ] },
  { scope: 'block', blockId: 'battle', groups: [
    { name: '家具', open: true, items: [{ type: '桌子', icon: '⊥', tint: '#b47852' }, { type: '柜子', icon: '▤', tint: '#947052' }, { type: '衣柜', icon: '▥', tint: '#a9b2b0' }, { type: '电视柜', icon: '▰', tint: '#71656a' }, { type: '椅子', icon: '♧', tint: '#b9825e' }, { type: '沙发', icon: '▱', tint: '#d8c7d0' }, { type: '懒人沙发', icon: '●', tint: '#d98fa8' }, { type: '床', icon: '▰', tint: '#6c9fb1' }] },
    { name: '办公', open: true, items: [{ type: '办公桌', icon: '▱', tint: '#526d7c' }, { type: '办公椅', icon: '♧', tint: '#4f7f9a' }, { type: '显示器', icon: '▣', tint: '#4e6f83' }, { type: '笔记本电脑', icon: '▱', tint: '#72818b' }, { type: '文件柜', icon: '▤', tint: '#81939b' }, { type: '书架', icon: '▥', tint: '#9a7959' }, { type: '打印机', icon: '▤', tint: '#56656d' }, { type: '饮水机', icon: '◉', tint: '#6c9bb4' }, { type: '会议桌', icon: '⊣', tint: '#7a6758' }, { type: '白板', icon: '▭', tint: '#8b9fa6' }] }
  ] },
  { scope: 'block', blockId: 'rooftop', groups: [
    { name: '道具', open: true, items: [{ type: '路灯', icon: '♧', tint: '#d7ac55' }, { type: '箱子', icon: '▣', tint: '#bc8b46' }] }
  ] }
];
let selected = null, snapping = true, grounding = true, rotationSnapping = true, collisionEnabled = true, passThrough = false, dragOffset = new THREE.Vector3(), dragging = false, gizmoInteraction = false, transformDragPreviousPosition = null, verticalSnapApplied = false, lastCollisionNotice = 0;
const instances = [];
const gltfLoader = new GLTFLoader();
let frameImportedTimer = null;

function frameImportedScene() {
  const box = new THREE.Box3(); instances.forEach(instance => box.expandByObject(instance));
  if (box.isEmpty()) return;
  const center = box.getCenter(new THREE.Vector3()), size = box.getSize(new THREE.Vector3()), radius = Math.max(size.x, size.y, size.z, 4);
  controls.target.copy(center); camera.position.copy(center).add(new THREE.Vector3(radius * .8, radius * .8, radius * .6)); camera.near = Math.max(.05, radius / 1000); camera.far = Math.max(100, radius * 10); camera.updateProjectionMatrix(); controls.update();
}

function loadBlenderModel(root, record) {
  if (!record.modelUrl) return;
  root.userData.blenderSettings = structuredClone(record.blenderSettings || {}); root.userData.modelUrl = record.modelUrl;
  gltfLoader.load(record.modelUrl, gltf => {
    modelRoot(root).add(gltf.scene);
    root.traverse(object => { if (object.isMesh) { object.userData.root = root; object.castShadow = true; object.receiveShadow = true; } });
    if (selected === root) selectionBox.setFromObject(root);
    clearTimeout(frameImportedTimer); frameImportedTimer = setTimeout(frameImportedScene, 120);
  }, undefined, () => showToast(`模型读取失败：${record.name}`));
}

function renderAssets(filter = '') {
  const list = $('#assetList'); list.innerHTML = '';
  const currentBlockId = $('#blockSelect')?.value;
  assetLibraries.filter(library => library.scope === 'common' || library.blockId === currentBlockId).forEach(library => {
    const visibleGroups = library.groups.map(group => ({ group, items: group.items.filter(asset => asset.type.includes(filter)) })).filter(entry => entry.items.length);
    if (!visibleGroups.length) return;
    const heading = document.createElement('div'); heading.className = `asset-scope ${library.scope}`;
    const blockName = projectBlocks.find(block => block.id === library.blockId)?.name || library.blockId;
    heading.innerHTML = `<strong>${library.scope === 'common' ? '通用组件' : `${blockName}组件`}</strong><span>${visibleGroups.reduce((sum, entry) => sum + entry.items.length, 0)}</span>`;
    list.append(heading);
    visibleGroups.forEach(({ group, items }) => {
      const title = document.createElement('button'); title.className = 'asset-group'; title.innerHTML = `<span class="chevron">${group.open ? '⌄' : '›'}</span>${group.name}<em>${items.length}</em>`;
      title.onclick = () => { group.open = !group.open; renderAssets(filter); }; list.append(title);
      if (group.open) items.forEach(asset => { const el = document.createElement('div'); el.className = 'asset'; el.draggable = true; el.dataset.type = asset.type; el.innerHTML = `<span class="asset-icon" style="color:${asset.tint}">${asset.icon}</span><span>${asset.type}</span><small>拖拽添加</small>`; el.addEventListener('dragstart', e => e.dataTransfer.setData('component', asset.type)); list.append(el); });
    });
  });
}
renderAssets();

const container = $('#viewport');
const scene = new THREE.Scene(); scene.background = new THREE.Color('#e7eceb');
const camera = new THREE.PerspectiveCamera(48, 1, .1, 100); camera.up.set(0, 0, 1); camera.position.set(8, 10, 7);
const renderer = new THREE.WebGLRenderer({ antialias: true }); renderer.setPixelRatio(Math.min(devicePixelRatio, 2)); renderer.shadowMap.enabled = true; renderer.shadowMap.type = THREE.PCFSoftShadowMap; container.prepend(renderer.domElement);
const controls = new OrbitControls(camera, renderer.domElement); controls.target.set(0, 0, 1); controls.enableDamping = true; controls.maxPolarAngle = Math.PI * .48;
const transformControls = new TransformControls(camera, renderer.domElement); transformControls.setMode(transformMode); transformControls.setSize(.9); transformControls.setRotationSnap(rotationSnapRadians); scene.add(transformControls.getHelper());
transformControls.addEventListener('dragging-changed', event => { controls.enabled = !event.value; if (event.value && selected) { captureHistory(); transformDragPreviousPosition = selected.position.clone(); } else if (!event.value) transformDragPreviousPosition = null; });
transformControls.addEventListener('mouseDown', () => { gizmoInteraction = true; });
transformControls.addEventListener('mouseUp', () => { gizmoInteraction = false; });
transformControls.addEventListener('objectChange', () => { if (!selected) return; if (transformMode === 'translate') { const previous = transformDragPreviousPosition?.clone() || selected.position.clone(); if (snapping) selected.position.copy(snapPosition(selected.position.clone())); const movingVertically = transformControls.axis === 'Z'; if (grounding && !verticalSnapApplied && !movingVertically) setOnGround(selected); preventCollision(selected, previous); transformDragPreviousPosition = selected.position.clone(); } selectionBox.setFromObject(selected); updateFields(); });
scene.add(new THREE.HemisphereLight(0xffffff, 0x83999a, 2));
const key = new THREE.DirectionalLight(0xffffff, 2.2); key.position.set(4, 5, 8); key.castShadow = true; scene.add(key);
const grid = new THREE.GridHelper(30, 30, 0xa3b1ae, 0xcbd3d0); grid.rotation.x = Math.PI / 2; grid.position.z = -.01; scene.add(grid);
const ground = new THREE.Mesh(new THREE.PlaneGeometry(30, 30), new THREE.ShadowMaterial({ color: 0x526463, opacity: .12 })); ground.receiveShadow = true; scene.add(ground);
const raycaster = new THREE.Raycaster(), pointer = new THREE.Vector2(), plane = new THREE.Plane(new THREE.Vector3(0, 0, 1), 0);
const selectionBox = new THREE.BoxHelper(new THREE.Object3D(), 0x299b92); selectionBox.visible = false; scene.add(selectionBox);
const orientationCanvas = $('#orientationGizmoCanvas'), orientationContext = orientationCanvas.getContext('2d');
const orientationAxes = [
  { name: 'X', vector: new THREE.Vector3(1, 0, 0), color: '#d16158' },
  { name: 'Y', vector: new THREE.Vector3(0, 1, 0), color: '#4eaa77' },
  { name: 'Z', vector: new THREE.Vector3(0, 0, 1), color: '#4c85bb' }
];
function drawOrientationGizmo() {
  if (!orientationContext) return;
  const cssSize = 96, ratio = Math.min(window.devicePixelRatio || 1, 2);
  if (orientationCanvas.width !== cssSize * ratio) { orientationCanvas.width = cssSize * ratio; orientationCanvas.height = cssSize * ratio; }
  orientationContext.setTransform(ratio, 0, 0, ratio, 0, 0);
  orientationContext.clearRect(0, 0, cssSize, cssSize);
  orientationContext.save(); orientationContext.translate(cssSize / 2, cssSize / 2);
  const inverseCamera = camera.quaternion.clone().invert(), radius = 32;
  const projected = orientationAxes.map(axis => { const point = axis.vector.clone().applyQuaternion(inverseCamera); return { ...axis, point, x: point.x * radius, y: -point.y * radius }; });
  orientationContext.lineCap = 'round';
  projected.forEach(axis => {
    orientationContext.beginPath(); orientationContext.moveTo(-axis.x, -axis.y); orientationContext.lineTo(axis.x, axis.y); orientationContext.strokeStyle = `${axis.color}55`; orientationContext.lineWidth = 2; orientationContext.stroke();
  });
  projected.sort((a, b) => b.point.z - a.point.z).forEach(axis => {
    orientationContext.beginPath(); orientationContext.moveTo(0, 0); orientationContext.lineTo(axis.x, axis.y); orientationContext.strokeStyle = axis.color; orientationContext.lineWidth = 3; orientationContext.stroke();
    orientationContext.beginPath(); orientationContext.arc(axis.x, axis.y, 8, 0, Math.PI * 2); orientationContext.fillStyle = 'rgba(250,252,251,.94)'; orientationContext.fill(); orientationContext.strokeStyle = axis.color; orientationContext.lineWidth = 1.5; orientationContext.stroke();
    orientationContext.fillStyle = axis.color; orientationContext.font = '700 10px Arial, sans-serif'; orientationContext.textAlign = 'center'; orientationContext.textBaseline = 'middle'; orientationContext.fillText(axis.name, axis.x, axis.y);
  });
  orientationContext.beginPath(); orientationContext.arc(0, 0, 3, 0, Math.PI * 2); orientationContext.fillStyle = '#647773'; orientationContext.fill(); orientationContext.restore();
}

function material(color) { return new THREE.MeshStandardMaterial({ color, roughness: .72, metalness: .03 }); }
function mesh(geometry, color, y = 0) { const m = new THREE.Mesh(geometry, material(color)); m.position.y = y; m.castShadow = m.receiveShadow = true; return m; }
function isCharacter(obj) { return Boolean(obj?.userData?.characterSettings); }
function isSurface(obj) { return Boolean(obj?.userData?.surfaceSettings); }
function isChair(obj) { return Boolean(obj?.userData?.chairSettings); }
function isTable(obj) { return Boolean(obj?.userData?.tableSettings); }
function isStair(obj) { return Boolean(obj?.userData?.stairSettings); }
function modelRoot(root) { return root.userData.modelRoot || root; }
function addPart(root, child) { modelRoot(root).add(child); return child; }
function clearComponent(root) { const target = modelRoot(root); target.children.slice().forEach(child => { child.traverse?.(part => { part.geometry?.dispose(); part.material?.dispose(); }); child.geometry?.dispose(); child.material?.dispose(); target.remove(child); }); }
function buildTable(root) {
  clearComponent(root);
  const s = root.userData.tableSettings, wood = 0x9b6745, legThickness = .13;
  addPart(root, mesh(new THREE.BoxGeometry(s.width, s.topThickness, s.depth), wood, s.legHeight + s.topThickness / 2));
  const legX = Math.max(0, s.width / 2 - legThickness / 2 - .05), legZ = Math.max(0, s.depth / 2 - legThickness / 2 - .05);
  [-1, 1].forEach(x => [-1, 1].forEach(z => { const leg = mesh(new THREE.BoxGeometry(legThickness, s.legHeight, legThickness), wood, s.legHeight / 2); leg.position.set(x * legX, s.legHeight / 2, z * legZ); addPart(root, leg); }));
  root.traverse(o => { if (o.isMesh) o.userData.root = root; });
}
function buildChair(root) {
  clearComponent(root);
  const s = root.userData.chairSettings, wood = 0x9b6745, seatThickness = .13, legThickness = .12, backThickness = .12;
  addPart(root, mesh(new THREE.BoxGeometry(s.seatWidth, seatThickness, s.seatDepth), wood, s.legHeight + seatThickness / 2));
  const legX = Math.max(0, s.seatWidth / 2 - legThickness / 2 - .04), legZ = Math.max(0, s.seatDepth / 2 - legThickness / 2 - .04);
  [-1, 1].forEach(x => [-1, 1].forEach(z => { const leg = mesh(new THREE.BoxGeometry(legThickness, s.legHeight, legThickness), wood, s.legHeight / 2); leg.position.set(x * legX, s.legHeight / 2, z * legZ); addPart(root, leg); }));
  const back = mesh(new THREE.BoxGeometry(s.backWidth, s.backHeight, backThickness), wood, s.legHeight + seatThickness + s.backHeight / 2);
  back.position.z = s.seatDepth / 2 - backThickness / 2; addPart(root, back);
  root.traverse(o => { if (o.isMesh) o.userData.root = root; });
}
function buildSurface(root) {
  clearComponent(root);
  const s = root.userData.surfaceSettings;
  const geometry = s.kind === 'wall'
    ? new THREE.BoxGeometry(s.width, s.height, s.thickness)
    : new THREE.BoxGeometry(s.length, s.thickness, s.width);
  const surface = mesh(geometry, s.kind === 'wall' ? 0xa9b8ba : 0x9d907e, s.kind === 'wall' ? s.height / 2 : s.thickness / 2);
  addPart(root, surface); surface.userData.root = root;
}
function buildStair(root) {
  clearComponent(root);
  const s = root.userData.stairSettings, steps = Math.max(1, Math.round(Number(s.steps) || 1));
  const width = Math.max(.3, Number(s.width) || 1.5), tread = .3, rise = .18;
  const total = steps * rise, wood = 0x9b7453, rail = 0x536a6e;
  for (let i = 0; i < steps; i++) { const step = mesh(new THREE.BoxGeometry(width, rise, tread), wood, (i + .5) * rise); step.position.z = (i + .5) * tread; addPart(root, step); }
  const railHeight = Math.max(.2, Number(s.handrailHeight) || 1);
  const run = steps * tread;
  [-1, 1].forEach(side => {
    if (!s[side < 0 ? 'leftHandrail' : 'rightHandrail']) return;
    const x = side * width / 2;
    const startPost = mesh(new THREE.BoxGeometry(.06, railHeight, .06), rail, railHeight / 2);
    startPost.position.x = x; startPost.position.z = 0; addPart(root, startPost);
    const endPost = mesh(new THREE.BoxGeometry(.06, total + railHeight, .06), rail, (total + railHeight) / 2);
    endPost.position.x = x; endPost.position.z = run; addPart(root, endPost);
    const beamLength = Math.hypot(run, total), beam = mesh(new THREE.BoxGeometry(.06, .06, beamLength), rail, railHeight + total / 2);
    beam.position.x = x; beam.position.z = run / 2; beam.rotation.x = -Math.atan2(total, run); addPart(root, beam);
  });
  s.totalHeight = total; root.traverse(o => { if (o.isMesh) o.userData.root = root; });
}
function characterPreset(type) {
  return type.includes('成人角色')
    ? { headShape: 'sphere', bodyShape: 'sphere', armShape: 'sphere', legShape: 'sphere', headSize: .40, bodyLength: .60, bodyThickness: .34, armLength: .45, armThickness: .095, legLength: .60, legThickness: .12, colors: { skin: 0xf0c4a0, clothing: 0x3f6c74, pants: 0x485b64 } }
    : { headShape: 'sphere', bodyShape: 'sphere', armShape: 'sphere', legShape: 'sphere', headSize: .55, bodyLength: .20, bodyThickness: .30, armLength: .28, armThickness: .085, legLength: .35, legThickness: .11, colors: { skin: 0xf0c4a0, clothing: 0x779eac, pants: 0x697f93 } };
}
function capsule(length, thickness, color, y) { const radius = thickness / 2; return mesh(new THREE.CapsuleGeometry(radius, Math.max(.01, length - thickness), 8, 14), color, y); }
function buildCharacter(root) {
  clearComponent(root);
  const s = root.userData.characterSettings, { skin, clothing, pants } = s.colors;
  const headRadius = s.headSize / 2;
  const head = s.headShape === 'box'
    ? mesh(new THREE.BoxGeometry(s.headSize, s.headSize, s.headSize), skin, s.legLength + s.bodyLength + headRadius)
    : mesh(new THREE.SphereGeometry(headRadius, 18, 14), skin, s.legLength + s.bodyLength + headRadius);
  addPart(root, head);
  addPart(root, s.bodyShape === 'box'
    ? mesh(new THREE.BoxGeometry(s.bodyThickness, s.bodyLength, s.bodyThickness), clothing, s.legLength + s.bodyLength / 2)
    : capsule(s.bodyLength, s.bodyThickness, clothing, s.legLength + s.bodyLength / 2));
  const shoulderY = s.legLength + s.bodyLength;
  const armOffset = s.bodyThickness / 2 + s.armThickness / 2;
  [-1, 1].forEach(side => {
    const shoulder = new THREE.Group();
    shoulder.name = side < 0 ? 'Shoulder.L' : 'Shoulder.R';
    shoulder.userData = { nodeType: 'shoulder', side: side < 0 ? 'left' : 'right' };
    shoulder.position.set(side * armOffset, shoulderY, 0);
    const arm = s.armShape === 'box'
      ? mesh(new THREE.BoxGeometry(s.armThickness, s.armLength, s.armThickness), skin, -s.armLength / 2)
      : capsule(s.armLength, s.armThickness, skin, -s.armLength / 2);
    arm.name = side < 0 ? 'Arm.L' : 'Arm.R'; shoulder.add(arm); addPart(root, shoulder);
  });
  const legOffset = Math.max(s.legThickness * .55, s.bodyThickness * .23);
  [-1, 1].forEach(side => {
    const leg = s.legShape === 'box'
      ? mesh(new THREE.BoxGeometry(s.legThickness, s.legLength, s.legThickness), pants, s.legLength / 2)
      : capsule(s.legLength, s.legThickness, pants, s.legLength / 2);
    leg.position.x = side * legOffset; addPart(root, leg);
  });
  root.traverse(o => { if (o.isMesh) o.userData.root = root; });
}
function createComponent(type) {
  const root = new THREE.Group(); const geometryRoot = new THREE.Group(); geometryRoot.rotation.x = Math.PI / 2; root.add(geometryRoot); root.userData = { type, name: `${type}_${instances.filter(i => i.userData.type === type).length + 1}`, modelRoot: geometryRoot };
  const wood = 0x9b6745, wall = 0xa9b8ba, fabric = 0x547f91, dark = 0x425157;
  const addLegs = (w, d, h) => [-1, 1].forEach(x => [-1, 1].forEach(z => { const leg = mesh(new THREE.BoxGeometry(.13, h, .13), wood, h / 2); leg.position.set(x*w/2.25, h/2, z*d/2.25); addPart(root, leg); }));
  if (type === 'Blender模型') { /* Geometry is loaded from the imported GLB preview. */ }
  else if (type === '墙壁') { root.userData.surfaceSettings = { kind: 'wall', width: 5, height: 3, thickness: .2 }; buildSurface(root); }
  else if (type === '地板') { root.userData.surfaceSettings = { kind: 'floor', length: 5, width: 5, thickness: .1 }; buildSurface(root); }
  else if (type === '楼梯') { root.userData.stairSettings = { steps: 10, width: 1.5, handrailHeight: 1, leftHandrail: true, rightHandrail: true, totalHeight: 1.8 }; buildStair(root); }
  else if (type === '门') { addPart(root, mesh(new THREE.BoxGeometry(1.25, 2.35, .13), wood, 1.175)); const knob = mesh(new THREE.SphereGeometry(.06, 12, 8), 0xd8b362); knob.position.set(.42, 1.15, -.1); addPart(root, knob); }
  else if (type === '窗') { const f = mesh(new THREE.BoxGeometry(2, 1.55, .12), 0x77aabe, 1.45); addPart(root, f); [-.65, 0, .65].forEach(x => { const b = mesh(new THREE.BoxGeometry(.07, 1.7, .17), 0xe5eeec, 1.45); b.position.x=x; addPart(root, b); }); const h=mesh(new THREE.BoxGeometry(2.15,.07,.17),0xe5eeec,1.45); addPart(root, h); }
  else if (type === '桌子') { root.userData.tableSettings = { legHeight: 1.1, width: 2.2, depth: 1.3, topThickness: .2 }; buildTable(root); }
  else if (type === '柜子') { addPart(root, mesh(new THREE.BoxGeometry(1.4,1.65,.55), 0x8c684d, .825)); [-.32,.32].forEach(x=>{const k=mesh(new THREE.SphereGeometry(.035,10,8),0xd0b36d); k.position.set(x, .85, -.3);addPart(root,k)}); }
  else if (type === '衣柜') {
    addPart(root, mesh(new THREE.BoxGeometry(2.4, 2.35, .65), 0xd9dddd, 1.175));
    const seam = mesh(new THREE.BoxGeometry(.025, 2.22, .018), 0x9ba8a7, 1.18); seam.position.z = -.335; addPart(root, seam);
    [-.08, .08].forEach(x => { const handle = mesh(new THREE.BoxGeometry(.035, .34, .035), 0x6f7d7d, 1.16); handle.position.set(x, 1.16, -.365); addPart(root, handle); });
  }
  else if (type === '电视柜') {
    addPart(root, mesh(new THREE.BoxGeometry(2.25, .62, .5), 0x6d6267, .31));
    [-.72, 0, .72].forEach(x => { const seam = mesh(new THREE.BoxGeometry(.018, .48, .018), 0x4e484b, .33); seam.position.set(x, .33, -.26); addPart(root, seam); });
  }
  else if (type === '椅子') { root.userData.chairSettings = { legHeight: .7, seatWidth: .8, seatDepth: .8, backHeight: .75, backWidth: .8 }; buildChair(root); }
  else if (type === '沙发') {
    const upholstery = 0xd7c8cf, frame = 0xbcaeb4;
    addPart(root, mesh(new THREE.BoxGeometry(2.2, .38, .92), frame, .28));
    const seat = mesh(new THREE.BoxGeometry(1.75, .18, .72), upholstery, .52); seat.position.z = -.04; addPart(root, seat);
    const back = mesh(new THREE.BoxGeometry(1.9, .72, .2), upholstery, .72); back.position.z = .38; addPart(root, back);
    [-1, 1].forEach(side => { const arm = mesh(new THREE.BoxGeometry(.2, .58, .88), upholstery, .5); arm.position.x = side * 1; addPart(root, arm); });
  }
  else if (type === '懒人沙发') {
    const bag = mesh(new THREE.IcosahedronGeometry(.72, 2), 0xd98fa8, .56);
    bag.scale.set(1, .78, .92); addPart(root, bag);
    const top = mesh(new THREE.SphereGeometry(.09, 14, 10), 0xb96782, 1.06);
    top.scale.y = .45; addPart(root, top);
  }
  else if (type === '床') { addPart(root, mesh(new THREE.BoxGeometry(2.25,.28,1.35),wood,.5)); addPart(root, mesh(new THREE.BoxGeometry(2.12,.28,1.25),0x7298a5,.78)); const pillow=mesh(new THREE.BoxGeometry(.55,.14,1.05),0xe4ded2,.99);pillow.position.x=-.7;addPart(root,pillow); addLegs(2.05,1.15,.42); }
  else if (type === '办公桌') {
    const desk = 0x516673, metal = 0x3e4b50;
    addPart(root, mesh(new THREE.BoxGeometry(1.6, .09, .75), desk, .75));
    [-.68, .68].forEach(x => [-.27, .27].forEach(z => { const leg = mesh(new THREE.BoxGeometry(.07, .72, .07), metal, .36); leg.position.set(x, .36, z); addPart(root, leg); }));
    addPart(root, mesh(new THREE.BoxGeometry(.38, .56, .6), 0x607681, .28)).position.x = -.53;
    [-.11, .11].forEach(y => { const handle = mesh(new THREE.BoxGeometry(.16, .03, .025), 0xc6d0d3, y + .29); handle.position.set(-.53, y + .29, -.315); addPart(root, handle); });
  }
  else if (type === '办公椅') {
    const blue = 0x3f718c, darkMetal = 0x39474d;
    addPart(root, mesh(new THREE.BoxGeometry(.62, .12, .62), blue, .5));
    const back = mesh(new THREE.BoxGeometry(.58, .7, .12), blue, .88); back.position.z = .26; addPart(root, back);
    addPart(root, mesh(new THREE.CylinderGeometry(.055, .055, .42, 12), darkMetal, .23));
    addPart(root, mesh(new THREE.CylinderGeometry(.24, .24, .06, 16), darkMetal, .04));
    for (let i = 0; i < 5; i++) { const arm = new THREE.Group(); arm.rotation.y = i * Math.PI * 2 / 5; const spoke = mesh(new THREE.BoxGeometry(.52, .045, .055), darkMetal, .07); spoke.position.x = .24; arm.add(spoke); const wheel = mesh(new THREE.SphereGeometry(.06, 10, 8), 0x232d31, .04); wheel.position.x = .51; arm.add(wheel); addPart(root, arm); }
  }
  else if (type === '显示器') {
    const frame = mesh(new THREE.BoxGeometry(.9, .56, .055), 0x29363b, 1.2); addPart(root, frame);
    const screen = mesh(new THREE.BoxGeometry(.79, .45, .018), 0x365f72, 1.2); screen.position.z = -.038; addPart(root, screen);
    addPart(root, mesh(new THREE.CylinderGeometry(.035, .035, .4, 10), 0x39474d, .67));
    addPart(root, mesh(new THREE.BoxGeometry(.42, .045, .25), 0x39474d, .47));
  }
  else if (type === '笔记本电脑') {
    const casing = 0x46545b;
    addPart(root, mesh(new THREE.BoxGeometry(.9, .055, .6), casing, .08));
    const keyboard = mesh(new THREE.BoxGeometry(.72, .012, .3), 0x202b30, .115); keyboard.position.z = -.07; addPart(root, keyboard);
    const trackpad = mesh(new THREE.BoxGeometry(.28, .012, .12), 0x87939a, .115); trackpad.position.z = -.28; addPart(root, trackpad);
    const hinge = new THREE.Group();
    hinge.position.set(0, .108, .276);
    hinge.rotation.x = -.18;
    const lid = mesh(new THREE.BoxGeometry(.9, .54, .045), casing, .27); hinge.add(lid);
    const display = mesh(new THREE.BoxGeometry(.78, .42, .012), 0x426c82, .27); display.position.z = -.03; hinge.add(display);
    const bezel = mesh(new THREE.BoxGeometry(.82, .46, .014), 0x1f2b30, .27); bezel.position.z = -.024; hinge.add(bezel);
    const visibleScreen = mesh(new THREE.BoxGeometry(.74, .38, .008), 0x4e8da5, .27); visibleScreen.position.z = -.034; hinge.add(visibleScreen);
    addPart(root, hinge);
  }
  else if (type === '文件柜') {
    const cabinet = 0x6f858e; addPart(root, mesh(new THREE.BoxGeometry(.85, 1.25, .52), cabinet, .625));
    [-.3, 0, .3].forEach(y => { const seam = mesh(new THREE.BoxGeometry(.72, .018, .02), 0x45575e, y + .63); seam.position.z = -.271; addPart(root, seam); const pull = mesh(new THREE.BoxGeometry(.16, .045, .035), 0xc4d0d3, y + .63); pull.position.z = -.295; addPart(root, pull); });
    [-.32, .32].forEach(x => { const foot = mesh(new THREE.CylinderGeometry(.035, .035, .07, 8), 0x38454a, .035); foot.position.set(x, .035, 0); addPart(root, foot); });
  }
  else if (type === '书架') {
    const shelfColor = 0x8d6b4f; addPart(root, mesh(new THREE.BoxGeometry(1.1, 1.8, .32), shelfColor, .9));
    [ .3, .74, 1.18, 1.62 ].forEach(y => { const shelf = mesh(new THREE.BoxGeometry(1.0, .055, .38), 0xb08b64, y); addPart(root, shelf); });
    const bookColors = [0x557f8b, 0xb35e4c, 0xc79a46, 0x6c8770];
    [ .38, .82, 1.26 ].forEach((y, row) => bookColors.forEach((color, index) => { const book = mesh(new THREE.BoxGeometry(.12, .25 + index * .025, .18), color, y + .14); book.position.set(-.33 + index * .18, y + .14, -.11); addPart(root, book); }));
  }
  else if (type === '打印机') {
    addPart(root, mesh(new THREE.BoxGeometry(.68, .3, .52), 0x4e5d63, .28));
    const paper = mesh(new THREE.BoxGeometry(.45, .018, .3), 0xe8ecea, .45); paper.position.y = -.04; addPart(root, paper);
    const tray = mesh(new THREE.BoxGeometry(.52, .035, .26), 0x344147, .12); tray.position.z = -.31; addPart(root, tray);
    const panel = mesh(new THREE.BoxGeometry(.16, .07, .02), 0x6ba1b3, .31); panel.position.set(.18, .31, -.27); addPart(root, panel);
  }
  else if (type === '饮水机') {
    addPart(root, mesh(new THREE.BoxGeometry(.38, 1.02, .42), 0xe4e8e7, .51));
    addPart(root, mesh(new THREE.CylinderGeometry(.18, .15, .42, 16), 0x79aabe, 1.22));
    [-.08, .08].forEach((x, index) => { const tap = mesh(new THREE.CylinderGeometry(.022, .022, .11, 8), index ? 0xd35c51 : 0x548fc0, .71); tap.rotation.x = Math.PI / 2; tap.position.set(x, .71, -.24); addPart(root, tap); });
    addPart(root, mesh(new THREE.BoxGeometry(.28, .12, .025), 0x2f3f44, .5)).position.z = -.225;
  }
  else if (type === '会议桌') {
    const top = mesh(new THREE.CylinderGeometry(.95, .95, .11, 24), 0x7d6756, .78); top.scale.z = .62; addPart(root, top);
    const base = mesh(new THREE.CylinderGeometry(.26, .36, .7, 16), 0x46545a, .35); addPart(root, base);
    addPart(root, mesh(new THREE.CylinderGeometry(.62, .62, .07, 20), 0x3b484d, .035)).scale.z = .62;
  }
  else if (type === '白板') {
    const frame = mesh(new THREE.BoxGeometry(1.6, 1.05, .065), 0x9aa9ac, 1.35); addPart(root, frame);
    const board = mesh(new THREE.BoxGeometry(1.46, .9, .018), 0xf5f6f2, 1.35); board.position.z = -.047; addPart(root, board);
    const tray = mesh(new THREE.BoxGeometry(1.1, .05, .13), 0x71888e, .78); tray.position.z = -.1; addPart(root, tray);
    [-.65, .65].forEach(x => { const leg = mesh(new THREE.BoxGeometry(.055, .78, .055), 0x586970, .39); leg.position.set(x, .39, 0); addPart(root, leg); });
  }
  else if (type === '路灯') { const pole=mesh(new THREE.CylinderGeometry(.055,.07,3.2,12),dark,1.6);addPart(root,pole); const lamp=mesh(new THREE.SphereGeometry(.25,16,12),0xe6bd5b,3.15);addPart(root,lamp); const glow=new THREE.PointLight(0xffd77e,1.4,5);glow.position.y=3.15;addPart(root,glow); }
  else if (type === '箱子') { addPart(root, mesh(new THREE.BoxGeometry(1, .82, .8), 0xb47d3e,.41)); [-.24,.24].forEach(x=>{const b=mesh(new THREE.BoxGeometry(.07,.87,.84),0x70472e,.41);b.position.x=x;addPart(root,b)}); }
  else if (type.includes('角色')) { root.userData.characterSettings = characterPreset(type); buildCharacter(root); }
  root.traverse(o => { if (o.isMesh) o.userData.root = root; }); return root;
}
function addComponent(type, point = new THREE.Vector3()) {
  captureHistory();
  const obj = createComponent(type); obj.position.copy(point); if (grounding) setOnGround(obj); scene.add(obj);
  preventCollision(obj, point);
  instances.push(obj); select(obj); $('#dropNotice').classList.add('hidden'); updateCounts(); showToast(`${type} 已添加`);
}
function setOnGround(obj) { const box = new THREE.Box3().setFromObject(obj); obj.position.z -= box.min.z; }
function preventCollision(obj, previousPosition) {
  if (!collisionEnabled || passThrough || obj.userData.type === '地板') return false;
  const movement = previousPosition ? obj.position.clone().sub(previousPosition) : new THREE.Vector3();
  let snapped = false;
  for (let attempt = 0; attempt < 3; attempt++) {
    obj.updateWorldMatrix(true, true);
    const candidate = new THREE.Box3().setFromObject(obj);
    const other = instances.find(item => {
      if (item === obj || item.userData.type === '地板') return false;
      const box = new THREE.Box3().setFromObject(item), epsilon = .002;
      return candidate.min.x < box.max.x - epsilon && candidate.max.x > box.min.x + epsilon
        && candidate.min.y < box.max.y - epsilon && candidate.max.y > box.min.y + epsilon
        && candidate.min.z < box.max.z - epsilon && candidate.max.z > box.min.z + epsilon;
    });
    if (!other) break;
    other.updateWorldMatrix(true, true);
    const target = new THREE.Box3().setFromObject(other), clearance = .015;
    const corrections = [
      { axis: 'x', value: target.min.x - candidate.max.x - clearance, direction: 1 },
      { axis: 'x', value: target.max.x - candidate.min.x + clearance, direction: -1 },
      { axis: 'y', value: target.min.y - candidate.max.y - clearance, direction: 1 },
      { axis: 'y', value: target.max.y - candidate.min.y + clearance, direction: -1 }
    ];
    const preferredAxis = Math.abs(movement.x) >= Math.abs(movement.y) ? 'x' : 'y';
    const preferredDirection = preferredAxis === 'x' ? Math.sign(movement.x) : Math.sign(movement.y);
    const preferred = corrections.filter(c => c.axis === preferredAxis && (!preferredDirection || c.direction === preferredDirection));
    const correction = (preferred.length ? preferred : corrections).reduce((best, item) => Math.abs(item.value) < Math.abs(best.value) ? item : best);
    obj.position[correction.axis] += correction.value;
    snapped = true;
  }
  if (!snapped) return false;
  const now = performance.now();
  if (now - lastCollisionNotice > 900) { showToast('已吸附到组件表面'); lastCollisionNotice = now; }
  return true;
}
function select(obj) { selected = obj; activeGroup = obj.userData?.nodeType === 'group' ? obj : (obj.parent?.userData?.nodeType === 'group' ? obj.parent : activeGroup); transformControls.attach(obj); selectionBox.setFromObject(obj); selectionBox.visible = true; $('#emptySelection').hidden=true; $('#propertyContent').hidden=false; $('#selectionName').textContent=obj.userData.name; $('#propertyName').textContent=obj.userData.name; $('#propertyType').textContent=obj.userData.nodeType === 'group' ? `分组 / ${obj.userData.name}` : `组件 / ${obj.userData.type}`; updateFields(); renderNodes(); }
function updateCharacterControls() {
  const visible = isCharacter(selected); $('#characterControls').hidden = !visible; if (!visible) return;
  const s = selected.userData.characterSettings;
  document.querySelectorAll('[data-character]').forEach(input => input.value = s[input.dataset.character]);
  document.querySelectorAll('[data-character-number]').forEach(input => input.value = s[input.dataset.characterNumber]);
  document.querySelectorAll('[data-shape-part]').forEach(button => button.classList.toggle('active', button.dataset.shapeValue === s[`${button.dataset.shapePart}Shape`]));
  $('#characterHeight').textContent = `身高 ${(s.headSize + s.bodyLength + s.legLength).toFixed(2)}m`;
}
function updateSurfaceControls() {
  const visible = isSurface(selected); $('#surfaceControls').hidden = !visible; if (!visible) return;
  const s = selected.userData.surfaceSettings, wall = s.kind === 'wall';
  $('#wallDimensions').hidden = !wall; $('#floorDimensions').hidden = wall;
  document.querySelectorAll('[data-surface]').forEach(input => { if (input.closest(wall ? '#wallDimensions' : '#floorDimensions')) input.value = s[input.dataset.surface].toFixed(1); });
}
function updateChairControls() {
  const visible = isChair(selected); $('#chairControls').hidden = !visible; if (!visible) return;
  const s = selected.userData.chairSettings; document.querySelectorAll('[data-chair]').forEach(input => input.value = s[input.dataset.chair].toFixed(1));
}
function updateTableControls() {
  const visible = isTable(selected); $('#tableControls').hidden = !visible; if (!visible) return;
  const s = selected.userData.tableSettings; document.querySelectorAll('[data-table]').forEach(input => input.value = s[input.dataset.table].toFixed(1));
}
function updateStairControls() {
  const visible = isStair(selected); $('#stairControls').hidden = !visible; if (!visible) return;
  const s = selected.userData.stairSettings;
  document.querySelectorAll('[data-stair]').forEach(input => { const value = s[input.dataset.stair]; input.value = typeof value === 'number' ? value.toFixed(input.dataset.stair === 'steps' ? 0 : 1) : value; });
  $('#stairHeight').textContent = `总高度 ${(Math.max(1, Number(s.steps) || 1) * .18).toFixed(2)}m`;
  document.querySelectorAll('[data-stair-toggle]').forEach(input => { input.checked = Boolean(s[input.dataset.stairToggle]); });
}
function snapRotation(obj) {
  obj.rotation.x = Math.round(obj.rotation.x / rotationSnapRadians) * rotationSnapRadians;
  obj.rotation.y = Math.round(obj.rotation.y / rotationSnapRadians) * rotationSnapRadians;
  obj.rotation.z = Math.round(obj.rotation.z / rotationSnapRadians) * rotationSnapRadians;
}
function updateFields() {
  if (!selected) return;
  document.querySelectorAll('[data-transform]').forEach(input => {
    const { transform, axis } = input.dataset;
    let value = Number(selected?.[transform]?.[axis]);
    if (!Number.isFinite(value)) value = 0;
    if (transform === 'rotation') value = THREE.MathUtils.radToDeg(value);
    input.value = value.toFixed(transform === 'rotation' ? 0 : 2);
  });
  const position = selected.position || { x: 0, y: 0, z: 0 };
  $('#coordinates').textContent = `${Number(position.x || 0).toFixed(2)}, ${Number(position.y || 0).toFixed(2)}, ${Number(position.z || 0).toFixed(2)}`;
  updateCharacterControls(); updateSurfaceControls(); updateChairControls(); updateTableControls(); updateStairControls();
}
function beginGroupRename(group, row) {
  const label = row.querySelector('strong');
  if (!label || row.querySelector('.node-group-name-input')) return;
  const original = group.userData.name;
  const input = document.createElement('input');
  input.className = 'node-group-name-input'; input.type = 'text'; input.value = original; input.maxLength = 32;
  let finished = false;
  const finish = save => {
    if (finished) return;
    finished = true; row.draggable = false;
    const nextName = input.value.trim();
    if (save && nextName && nextName !== original) { captureHistory(); group.userData.name = nextName; }
    renderNodes();
    if (selected === group) { const name = save && nextName ? nextName : original; $('#selectionName').textContent = name; $('#propertyName').textContent = name; updateFields(); }
  };
  input.onkeydown = event => { if (event.key === 'Enter') { event.preventDefault(); finish(true); } else if (event.key === 'Escape') { event.preventDefault(); finish(false); } };
  input.onblur = () => finish(true);
  input.onclick = event => event.stopPropagation();
  row.draggable = false; label.replaceWith(input); input.focus(); input.select();
}
function renderNodes() {
  const groups = [...scene.children].filter(o => o.userData?.nodeType === 'group');
  $('#nodeList').innerHTML = groups.map(g => `<div class="node-group"><div class="node-group-row ${g===selected?'selected':''}" role="button" tabindex="0" data-group="${g.uuid}">▾ <strong>${g.userData.name}</strong><small>${g.children.length}</small></div>${g.children.map(o=>`<button class="node-item nested ${o===selected?'selected':''}" draggable="true" data-node="${o.uuid}">◇ <span>${o.userData.name}</span></button>`).join('')}</div>`).join('') + instances.filter(o => !o.parent.userData?.nodeType).map(o=>`<button class="node-item ${o===selected?'selected':''}" draggable="true" data-node="${o.uuid}">◇ <span>${o.userData.name}</span></button>`).join('');
  $('#nodeList').ondblclick = e => {
    const row = e.target.closest?.('[data-group]');
    if (!row || !$('#nodeList').contains(row)) return;
    const group = scene.getObjectByProperty('uuid', row.dataset.group);
    if (group) { e.preventDefault(); e.stopPropagation(); clearTimeout(groupClickTimers.get(group)); groupClickTimers.delete(group); beginGroupRename(group, row); }
  };
  document.querySelectorAll('[data-node]').forEach(b=>b.onclick=()=>select(instances.find(o=>o.uuid===b.dataset.node)));
  document.querySelectorAll('[data-group]').forEach(b=>{
    const group = scene.getObjectByProperty('uuid',b.dataset.group);
    b.onclick=()=>{ clearTimeout(groupClickTimers.get(group)); const timer=setTimeout(()=>{ groupClickTimers.delete(group); select(group); }, 220); groupClickTimers.set(group,timer); };
    b.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(group);}};
    b.ondragover=e=>{e.preventDefault();b.classList.add('drop-target');};
    b.ondragleave=()=>b.classList.remove('drop-target');
    b.ondrop=e=>{e.preventDefault();b.classList.remove('drop-target');const child=scene.getObjectByProperty('uuid',e.dataTransfer.getData('node-uuid'));if(child&&child!==group&&!group.getObjectById(child.id)){captureHistory();group.attach(child);renderNodes();showToast(`已拖入 ${group.userData.name}`);}};
  });
  document.querySelectorAll('[data-node]').forEach(b=>{b.ondragstart=e=>e.dataTransfer.setData('node-uuid',b.dataset.node);});
}
function updateCounts(){ $('#assetCount').textContent=`${instances.length} 个组件`; }
function scenePayload() {
  return {
    version: 3,
    coordinateSystem,
    axes: { right: 'X', forward: '-Y', up: 'Z' },
    units: { distance: 'm', rotation: 'deg' },
    blenderSource: activeBlenderSource ? structuredClone(activeBlenderSource) : undefined,
    savedAt: new Date().toISOString(),
    camera: {
      position: { x: camera.position.x, y: camera.position.y, z: camera.position.z },
      target: { x: controls.target.x, y: controls.target.y, z: controls.target.z },
      fov: camera.fov
    },
    groups: [...scene.children].filter(o => o.userData?.nodeType === 'group').map(group => ({
      name: group.userData.name,
      position: { x: group.position.x, y: group.position.y, z: group.position.z },
      rotation: { x: THREE.MathUtils.radToDeg(group.rotation.x), y: THREE.MathUtils.radToDeg(group.rotation.y), z: THREE.MathUtils.radToDeg(group.rotation.z) },
      scale: { x: group.scale.x, y: group.scale.y, z: group.scale.z }
    })),
    components: instances.map(o => ({
      name: o.userData.name, type: o.userData.type, group: o.parent?.userData?.nodeType === 'group' ? o.parent.userData.name : null,
      position: { x: o.position.x, y: o.position.y, z: o.position.z },
      rotation: { x: THREE.MathUtils.radToDeg(o.rotation.x), y: THREE.MathUtils.radToDeg(o.rotation.y), z: THREE.MathUtils.radToDeg(o.rotation.z) },
      scale: { x: o.scale.x, y: o.scale.y, z: o.scale.z },
      characterSettings: o.userData.characterSettings,
      surfaceSettings: o.userData.surfaceSettings,
      chairSettings: o.userData.chairSettings,
      tableSettings: o.userData.tableSettings,
      stairSettings: o.userData.stairSettings,
      blenderSettings: o.userData.blenderSettings,
      modelUrl: o.userData.modelUrl
    }))
  };
}
const legacyToBlenderQuaternion = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), Math.PI / 2);
function normalizeTransform(record, payload) {
  const isBlenderSpace = payload?.coordinateSystem === coordinateSystem;
  if (isBlenderSpace) {
    // Version 2 wrote radians despite declaring degree units; version 3 is the canonical degree format.
    const rotation = payload.version >= 3 || payload.units?.rotation === 'rad'
      ? {
          x: THREE.MathUtils.degToRad(record.rotation?.x || 0),
          y: THREE.MathUtils.degToRad(record.rotation?.y || 0),
          z: THREE.MathUtils.degToRad(record.rotation?.z || 0)
        }
      : {
          x: record.rotation?.x || 0,
          y: record.rotation?.y || 0,
          z: record.rotation?.z || 0
        };
    return { position: record.position, rotation };
  }
  const position = { x: record.position?.x || 0, y: -(record.position?.z || 0), z: record.position?.y || 0 };
  const oldQuaternion = new THREE.Quaternion().setFromEuler(new THREE.Euler(record.rotation?.x || 0, record.rotation?.y || 0, record.rotation?.z || 0));
  const rotationQuaternion = legacyToBlenderQuaternion.clone().multiply(oldQuaternion).multiply(legacyToBlenderQuaternion.clone().invert());
  const rotationEuler = new THREE.Euler().setFromQuaternion(rotationQuaternion, 'XYZ');
  return { position, rotation: { x: rotationEuler.x, y: rotationEuler.y, z: rotationEuler.z } };
}
function writeSavedScenes(scenes) { localStorage.setItem(sceneIndexKey, JSON.stringify(scenes)); }
async function chooseSaveDirectory() {
  if (!window.showDirectoryPicker) { showToast('当前浏览器不支持文件夹存档，请使用最新版 Chrome 或 Edge'); return false; }
  try { saveDirectoryHandle = await window.showDirectoryPicker({ mode: 'readwrite' }); showToast(`已选择存档文件夹：${saveDirectoryHandle.name}`); return true; } catch { return false; }
}
async function ensureSaveDirectory() { return saveDirectoryHandle ? true : chooseSaveDirectory(); }
function downloadSceneFile(name, payload) {
  const safeName = name.replace(/[\\/:*?"<>|]/g, '_').trim() || '未命名场景';
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
  const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = `${safeName}.json`; link.click(); URL.revokeObjectURL(link.href);
}
async function readFileScenes() {
  if (!saveDirectoryHandle) return [];
  const scenes = [];
  for await (const [folderName, handle] of saveDirectoryHandle.entries()) {
    if (handle.kind !== 'directory') continue;
    try { const fileHandle = await handle.getFileHandle('scene.json'); const file = await fileHandle.getFile(); const payload = JSON.parse(await file.text()); scenes.push({ id: payload.id || folderName, name: payload.name || folderName, updatedAt: payload.savedAt || new Date().toISOString(), folderName, payload }); } catch { /* ignore non-scene folders */ }
  }
  return scenes.sort((a, b) => new Date(b.updatedAt) - new Date(a.updatedAt));
}
function migrateSavedScenes() {
  try {
    const indexed = JSON.parse(localStorage.getItem(sceneIndexKey) || '[]');
    if (Array.isArray(indexed) && indexed.length) return indexed;
    const saved = JSON.parse(localStorage.getItem(legacyScenesKey) || '[]');
    if (Array.isArray(saved) && saved.length) {
      const migrated = saved.map(item => {
        const id = item.id || crypto.randomUUID(); localStorage.setItem(sceneDataKey(id), JSON.stringify(item.payload));
        return { id, name: item.name || '未命名场景', updatedAt: item.updatedAt || item.payload?.savedAt || new Date().toISOString() };
      });
      writeSavedScenes(migrated); return migrated;
    }
    const legacy = JSON.parse(localStorage.getItem(legacySavedSceneKey) || 'null');
    if (!legacy?.components) return [];
    const record = { id: crypto.randomUUID(), name: '未命名场景', updatedAt: legacy.savedAt || new Date().toISOString() };
    localStorage.setItem(sceneDataKey(record.id), JSON.stringify(legacy)); writeSavedScenes([record]); return [record];
  } catch { return []; }
}
function readSavedScenes() { return migrateSavedScenes(); }
function readSavedScene(id) { try { return JSON.parse(localStorage.getItem(sceneDataKey(id)) || 'null'); } catch { return null; } }
const selectedBlock = () => projectBlocks.find(block => block.id === $('#blockSelect').value);
function updateSceneTitle() {
  const block = selectedBlock();
  $('.file-name').innerHTML = `<span class="status-dot"></span>${block ? `${block.name} / ` : ''}${currentSceneName} <span>·</span> ${activeSceneId ? 'Blender 已保存' : '未保存'}`;
}
async function loadProjectBlocks() {
  try {
    const response = await fetch('/api/blocks'); if (!response.ok) throw new Error('区块读取失败');
    const catalog = await response.json(); projectBlocks = catalog.blocks || [];
    const select = $('#blockSelect'); select.innerHTML = '';
    projectBlocks.forEach(block => { const option = document.createElement('option'); option.value = block.id; option.textContent = `${block.name} · ${block.floorRange}`; select.append(option); });
    $('#blockSource').textContent = catalog.source.split('/').pop();
    if (activeBlockId && projectBlocks.some(block => block.id === activeBlockId)) select.value = activeBlockId;
    activeBlockId = select.value || null; updateSceneTitle(); renderAssets($('#searchInput').value.trim());
  } catch { $('#blockSelect').innerHTML = '<option value="">项目区块读取失败</option>'; showToast('无法读取项目关卡区块文档'); }
}
function closeModal() { $('#modalBackdrop').classList.remove('is-open'); ['#saveModal', '#confirmModal', '#loadModal', '#aiModal'].forEach(id => $(id).classList.remove('is-open')); }
function openModal(id) {
  $('#modalBackdrop').classList.add('is-open');
  ['#saveModal', '#confirmModal', '#loadModal', '#aiModal'].forEach(modalId => $(modalId).classList.remove('is-open'));
  $(id).classList.add('is-open');
}
async function saveCurrentScene(name) {
  const trimmed = name.trim(); if (!trimmed) { showToast('请输入场景名称'); return false; }
  const block = selectedBlock(); if (!block) { showToast('请先选择项目区块'); return false; }
  const payload = { ...scenePayload(), id: activeSceneId || crypto.randomUUID(), name: trimmed };
  try {
    const response = await fetch(`/api/blocks/${encodeURIComponent(block.id)}/scenes`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: trimmed, payload }) });
    if (!response.ok) throw new Error('save');
    const record = await response.json(); activeSceneId = record.id; activeBlockId = block.id; currentSceneName = record.name; activeSceneSavedAt = record.updatedAt || activeSceneSavedAt; void setActivePreview(record.id, block.id); updateSceneTitle(); showToast(`已生成 ${record.blenderFile}`); return true;
  } catch { showToast('Blender 场景生成失败，请检查本地 Blender'); return false; }
}
function showSaveModal(afterSave = null) { pendingSceneAction = afterSave; $('#saveBlockName').textContent = selectedBlock()?.name || '未选择区块'; $('#sceneNameInput').value = currentSceneName === 'untitled_scene' ? '' : currentSceneName; openModal('#saveModal'); $('#sceneNameInput').focus(); }
async function showLoadModal() {
  let scenes = [];
  const block = selectedBlock(); if (!block) { showToast('请先选择项目区块'); return; }
  try { const response = await fetch(`/api/blocks/${encodeURIComponent(block.id)}/scenes`); if (!response.ok) throw new Error('load'); scenes = (await response.json()).scenes || []; } catch { showToast('本地存档服务未启动，请重新运行 npm run dev'); return; }
  $('#loadBlockName').textContent = `${block.name} · ${block.floorRange}`;
  const select = $('#savedSceneSelect'); select.innerHTML = '';
  if (!scenes.length) { select.innerHTML = '<option value="">暂无已保存场景</option>'; $('#confirmLoadBtn').disabled = true; }
  else { scenes.forEach(item => { const option = document.createElement('option'); option.value = item.id; option.textContent = `${item.name} · ${new Date(item.updatedAt).toLocaleString('zh-CN')}`; select.append(option); }); $('#confirmLoadBtn').disabled = false; }
  openModal('#loadModal');
}
function showAiModal() {
  if (!activeSceneId) { showToast('请先保存当前场景，再使用 AI 编辑'); return; }
  $('#aiCommandInput').value = '{\n  "operations": [\n    {\n      "op": "update",\n      "name": "组件名称",\n      "patch": { "position": { "x": 0, "y": 0, "z": 0 } }\n    }\n  ]\n}';
  openModal('#aiModal');
  $('#aiCommandInput').focus();
}
async function applyAiCommands() {
  if (!activeSceneId) { showToast('请先保存当前场景'); return; }
  let input;
  try { input = JSON.parse($('#aiCommandInput').value); } catch { showToast('AI 编辑命令不是有效 JSON'); return; }
  const operations = Array.isArray(input) ? input : input.operations;
  if (!Array.isArray(operations) || !operations.length) { showToast('请提供至少一条编辑命令'); return; }
  if (!(await saveCurrentScene(currentSceneName))) return;
  try {
    const response = await fetch(`/api/ai/blocks/${encodeURIComponent(activeBlockId)}/scenes/${encodeURIComponent(activeSceneId)}/commands`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ operations }) });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'AI 编辑失败');
    captureHistory(); restoreScene(result.scene); currentSceneName = result.scene.name || activeSceneId; activeSceneSavedAt = result.scene.savedAt || activeSceneSavedAt; updateSceneTitle(); closeModal(); showToast(`AI 已完成 ${result.changed.length} 项编辑`);
  } catch (error) { showToast(error.message || 'AI 编辑命令执行失败'); }
}
async function setActivePreview(sceneId, blockId = activeBlockId) {
  try { await fetch('/api/preview', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ blockId, sceneId }) }); }
  catch { /* The preview will retry when the local server is available. */ }
}
async function syncAiScenePreview() {
  if (sceneSyncInFlight) return;
  sceneSyncInFlight = true;
  try {
    const previewResponse = await fetch('/api/preview');
    if (previewResponse.ok) {
      const preview = await previewResponse.json();
      if (preview.sceneId && preview.blockId && (preview.sceneId !== activeSceneId || preview.blockId !== activeBlockId)) {
        const response = preview.blockId ? await fetch(`/api/blocks/${encodeURIComponent(preview.blockId)}/scenes/${encodeURIComponent(preview.sceneId)}`) : await fetch(`/api/scenes/${encodeURIComponent(preview.sceneId)}`);
        if (response.ok) {
          const payload = await response.json();
          captureHistory(); restoreScene(payload); activeSceneId = payload.id || preview.sceneId; activeBlockId = preview.blockId || null; if (activeBlockId) $('#blockSelect').value = activeBlockId; currentSceneName = payload.name || activeSceneId; activeSceneSavedAt = payload.savedAt || null; updateSceneTitle(); showToast(`已切换至“${currentSceneName}”预览`);
        }
        return;
      }
    }
    if (!activeSceneId) return;
    const response = activeBlockId ? await fetch(`/api/blocks/${encodeURIComponent(activeBlockId)}/scenes/${encodeURIComponent(activeSceneId)}`) : await fetch(`/api/scenes/${encodeURIComponent(activeSceneId)}`);
    if (!response.ok) return;
    const payload = await response.json();
    if (!payload.savedAt || payload.savedAt === activeSceneSavedAt) return;
    captureHistory(); restoreScene(payload); currentSceneName = payload.name || activeSceneId; activeSceneSavedAt = payload.savedAt; updateSceneTitle(); showToast('AI 编辑结果已更新到预览');
  } catch { /* The local server may be restarting; retry on the next sync. */ }
  finally { sceneSyncInFlight = false; }
}
function createNewScene() { captureHistory(); clearScene(); activeBlenderSource = null; $('#dropNotice').classList.remove('hidden'); updateCounts(); renderNodes(); activeSceneId = null; activeBlockId = $('#blockSelect').value || null; activeSceneSavedAt = null; void setActivePreview(null, activeBlockId); currentSceneName = 'untitled_scene'; updateSceneTitle(); showToast(`已在${selectedBlock()?.name || '当前区块'}新建空白场景`); }
function continueSceneTransition(action) {
  pendingSceneAction = null;
  closeModal();
  // Allow the confirmation dialog to finish closing before showing the next dialog.
  window.setTimeout(() => { void action?.(); }, 0);
}
function requestSceneTransition(action) { if (!instances.length) { void action(); return; } pendingSceneAction = action; openModal('#confirmModal'); }
function captureHistory() {
  undoHistory.push(scenePayload());
  if (undoHistory.length > historyLimit) undoHistory.shift();
  redoHistory.length = 0;
}
function clearScene() {
  transformControls.detach(); instances.forEach(o => scene.remove(o)); [...scene.children].filter(o => o.userData?.nodeType === 'group').forEach(group => scene.remove(group)); instances.length = 0; selected = null; activeGroup = null; selectionBox.visible = false;
  $('#emptySelection').hidden = false; $('#propertyContent').hidden = true; $('#selectionName').textContent = '全景';
}
function restoreScene(payload) {
  if (!payload?.components || !Array.isArray(payload.components)) throw new Error('场景数据无效');
  clearScene(); activeBlenderSource = payload.blenderSource ? structuredClone(payload.blenderSource) : null;
  const groups = new Map();
  (Array.isArray(payload.groups) ? payload.groups : []).forEach(record => {
    const group = new THREE.Group();
    group.userData = { nodeType: 'group', name: record.name || `分组_${groups.size + 1}` };
    const transform = normalizeTransform({ position: record.position, rotation: record.rotation }, payload);
    group.position.set(transform.position?.x || 0, transform.position?.y || 0, transform.position?.z || 0);
    group.rotation.set(transform.rotation?.x || 0, transform.rotation?.y || 0, transform.rotation?.z || 0);
    group.scale.set(record.scale?.x ?? 1, record.scale?.y ?? 1, record.scale?.z ?? 1);
    scene.add(group); groups.set(group.userData.name, group);
  });
  payload.components.forEach(record => {
    const obj = createComponent(record.type);
    obj.userData.name = record.name || obj.userData.name;
    if (record.characterSettings) { obj.userData.characterSettings = record.characterSettings; buildCharacter(obj); }
    if (record.surfaceSettings) { obj.userData.surfaceSettings = record.surfaceSettings; buildSurface(obj); }
    if (record.chairSettings) { obj.userData.chairSettings = record.chairSettings; buildChair(obj); }
    if (record.tableSettings) { obj.userData.tableSettings = record.tableSettings; buildTable(obj); }
    if (record.stairSettings) { obj.userData.stairSettings = record.stairSettings; buildStair(obj); }
    if (record.blenderSettings) loadBlenderModel(obj, record);
    const transform = normalizeTransform(record, payload);
    obj.position.set(transform.position?.x || 0, transform.position?.y || 0, transform.position?.z || 0);
    obj.rotation.set(transform.rotation?.x || 0, transform.rotation?.y || 0, transform.rotation?.z || 0);
    obj.scale.set(record.scale?.x ?? 1, record.scale?.y ?? 1, record.scale?.z ?? 1);
    const parent = record.group ? (groups.get(record.group) || (() => { const group = new THREE.Group(); group.userData = { nodeType: 'group', name: record.group }; scene.add(group); groups.set(record.group, group); return group; })()) : scene;
    parent.add(obj); instances.push(obj);
  });
  if (payload.camera?.position && payload.camera?.target) {
    const position = payload.camera.position, target = payload.camera.target;
    camera.position.set(Number(position.x) || 0, Number(position.y) || 0, Number(position.z) || 0);
    controls.target.set(Number(target.x) || 0, Number(target.y) || 0, Number(target.z) || 0);
    if (Number.isFinite(Number(payload.camera.fov))) { camera.fov = Number(payload.camera.fov); camera.updateProjectionMatrix(); }
    controls.update();
  }
  $('#dropNotice').classList.toggle('hidden', instances.length > 0); updateCounts(); renderNodes();
}
function componentSnapshot(obj) {
  return {
    name: obj.userData.name, type: obj.userData.type,
    position: { x: obj.position.x + .6, y: obj.position.y, z: obj.position.z + .6 },
    rotation: { x: obj.rotation.x, y: obj.rotation.y, z: obj.rotation.z },
    scale: { x: obj.scale.x, y: obj.scale.y, z: obj.scale.z },
    characterSettings: obj.userData.characterSettings ? structuredClone(obj.userData.characterSettings) : undefined,
    surfaceSettings: obj.userData.surfaceSettings ? structuredClone(obj.userData.surfaceSettings) : undefined,
    chairSettings: obj.userData.chairSettings ? structuredClone(obj.userData.chairSettings) : undefined,
    tableSettings: obj.userData.tableSettings ? structuredClone(obj.userData.tableSettings) : undefined
    ,stairSettings: obj.userData.stairSettings ? structuredClone(obj.userData.stairSettings) : undefined
  };
}
function pasteComponent() {
  if (!clipboardComponent) { showToast('请先选中组件并复制'); return; }
  if (clipboardComponent.type === 'Blender模型') { showToast('导入的 Blender 根组件不能复制；可移动、旋转、缩放或删除'); return; }
  captureHistory();
  const record = structuredClone(clipboardComponent), obj = createComponent(record.type);
  obj.userData.name = `${record.type}_${instances.filter(item => item.userData.type === record.type).length + 1}`;
  if (record.characterSettings) { obj.userData.characterSettings = record.characterSettings; buildCharacter(obj); }
  if (record.surfaceSettings) { obj.userData.surfaceSettings = record.surfaceSettings; buildSurface(obj); }
  if (record.chairSettings) { obj.userData.chairSettings = record.chairSettings; buildChair(obj); }
  if (record.tableSettings) { obj.userData.tableSettings = record.tableSettings; buildTable(obj); }
  if (record.stairSettings) { obj.userData.stairSettings = record.stairSettings; buildStair(obj); }
  obj.position.set(record.position.x, record.position.y, record.position.z); obj.rotation.set(record.rotation.x, record.rotation.y, record.rotation.z); obj.scale.set(record.scale.x, record.scale.y, record.scale.z);
  scene.add(obj); instances.push(obj); preventCollision(obj, selected?.position || obj.position); select(obj); $('#dropNotice').classList.add('hidden'); updateCounts(); showToast('组件已粘贴');
}
function undoScene() {
  const previous = undoHistory.pop();
  if (!previous) { showToast('没有可撤销的操作'); return; }
  redoHistory.push(scenePayload()); restoreScene(previous); showToast('已撤销');
}
function redoScene() {
  const next = redoHistory.pop();
  if (!next) { showToast('没有可重做的操作'); return; }
  undoHistory.push(scenePayload()); restoreScene(next); showToast('已重做');
}
function showToast(text){ const t=$('#toast');t.textContent=text;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),1700); }
function pointerFrom(e) { const r=renderer.domElement.getBoundingClientRect(); pointer.set(((e.clientX-r.left)/r.width)*2-1,-((e.clientY-r.top)/r.height)*2+1); raycaster.setFromCamera(pointer,camera); }
function snapPosition(pos) {
  verticalSnapApplied = false;
  if (!snapping) return pos;
  const threshold = .45;
  pos.x = Math.round(pos.x * 2) / 2;
  pos.y = Math.round(pos.y * 2) / 2;
  if (!selected) return pos;
  const currentBox = new THREE.Box3().setFromObject(selected);
  const offset = pos.clone().sub(selected.position);
  const candidate = currentBox.clone().translate(offset);
  const intervalDistance = (aMin, aMax, bMin, bMax) => Math.max(bMin - aMax, aMin - bMax, 0);
  const near = (aMin, aMax, bMin, bMax) => intervalDistance(aMin, aMax, bMin, bMax) <= threshold;
  const candidates = [];
  for (const other of instances) {
    if (other === selected) continue;
    const target = new THREE.Box3().setFromObject(other);
    const nearX = near(candidate.min.x, candidate.max.x, target.min.x, target.max.x);
    const nearY = near(candidate.min.y, candidate.max.y, target.min.y, target.max.y);
    const nearZ = near(candidate.min.z, candidate.max.z, target.min.z, target.max.z);
    const addFace = (axis, gap, requires) => { if (requires && Math.abs(gap) <= threshold) candidates.push({ axis, gap }); };
    addFace('x', target.min.x - candidate.max.x, nearY && nearZ);
    addFace('x', target.max.x - candidate.min.x, nearY && nearZ);
    addFace('y', target.min.y - candidate.max.y, nearX && nearZ);
    addFace('y', target.max.y - candidate.min.y, nearX && nearZ);
    addFace('z', target.min.z - candidate.max.z, nearX && nearY);
    addFace('z', target.max.z - candidate.min.z, nearX && nearY);
  }
  const byAxis = new Map();
  candidates.forEach(item => { const current = byAxis.get(item.axis); if (!current || Math.abs(item.gap) < Math.abs(current.gap)) byAxis.set(item.axis, item); });
  byAxis.forEach((item, axis) => { pos[axis] += item.gap; if (axis === 'z') verticalSnapApplied = true; });
  return pos;
}
renderer.domElement.addEventListener('pointerdown',e=>{ if(e.button!==0 || gizmoInteraction || transformControls.dragging)return;pointerFrom(e);const hits=raycaster.intersectObjects(instances,true);if(hits.length){const obj=hits[0].object.userData.root;select(obj);}else{selected=null;activeGroup=null;transformControls.detach();selectionBox.visible=false;$('#emptySelection').hidden=false;$('#propertyContent').hidden=true;$('#selectionName').textContent='全景';} });
renderer.domElement.addEventListener('pointermove',e=>{if(!dragging||!selected)return;pointerFrom(e);const p=new THREE.Vector3();raycaster.ray.intersectPlane(plane,p);p.sub(dragOffset);const previous=selected.position.clone();selected.position.copy(snapPosition(p));if(grounding)setOnGround(selected);preventCollision(selected,previous);selectionBox.setFromObject(selected);updateFields();});
renderer.domElement.addEventListener('pointerup',e=>{dragging=false;controls.enabled=true;renderer.domElement.releasePointerCapture?.(e.pointerId);});
container.addEventListener('dragover',e=>e.preventDefault());container.addEventListener('drop',e=>{e.preventDefault();const type=e.dataTransfer.getData('component');if(!type)return;pointerFrom(e);const p=new THREE.Vector3();raycaster.ray.intersectPlane(plane,p);addComponent(type,snapPosition(p));});
$('#searchInput').oninput=e=>renderAssets(e.target.value.trim());
$('#collapseAll').onclick=()=>{const groups=assetLibraries.flatMap(library=>library.groups),shouldOpen=groups.some(group=>group.open);groups.forEach(group=>group.open=!shouldOpen);renderAssets($('#searchInput').value.trim());};
$('#clearScene').onclick=()=>{captureHistory();clearScene();$('#dropNotice').classList.remove('hidden');updateCounts();renderNodes();showToast('场景已清空');};
$('#deleteBtn').onclick=()=>{if(!selected)return;captureHistory();transformControls.detach();scene.remove(selected);if(instances.includes(selected))instances.splice(instances.indexOf(selected),1);selected=null;selectionBox.visible=false;$('#emptySelection').hidden=false;$('#propertyContent').hidden=true;$('#selectionName').textContent='全景';updateCounts();renderNodes();};
$('#duplicateBtn').onclick=()=>{if(!selected){showToast('请先选择组件');return;}clipboardComponent=componentSnapshot(selected);pasteComponent();};
$('#resetTransform').onclick=()=>{if(!selected)return;captureHistory();selected.position.set(0,0,0);selected.rotation.set(0,0,0);selected.scale.set(1,1,1);setOnGround(selected);selectionBox.setFromObject(selected);updateFields();};
document.querySelectorAll('[data-transform]').forEach(input=>input.onchange=()=>{if(!selected)return;captureHistory();const previousPosition=selected.position.clone();let v=Number(input.value)||0;const {transform,axis}=input.dataset;if(transform==='rotation'){if(rotationSnapping)v=Math.round(v/rotationSnapDegrees)*rotationSnapDegrees;v=THREE.MathUtils.degToRad(v);}selected[transform][axis]=v;if(grounding&&transform==='position')setOnGround(selected);preventCollision(selected,previousPosition);selectionBox.setFromObject(selected);updateFields();});
function applyCharacterSetting(key, value) {
  if (!isCharacter(selected)) return;
  const s = selected.userData.characterSettings;
  s[key] = Number(value);
  const linked = { bodyLength: 'bodyThickness', armLength: 'armThickness', legLength: 'legThickness', bodyThickness: 'bodyLength', armThickness: 'armLength', legThickness: 'legLength' };
  if (linked[key]) {
    const lengthKey = key.endsWith('Thickness') ? linked[key] : key;
    const thicknessKey = key.endsWith('Thickness') ? key : linked[key];
    s[thicknessKey] = Math.min(s[thicknessKey], Math.max(.04, s[lengthKey] - .02));
  }
  buildCharacter(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields();
}
document.querySelectorAll('[data-character]').forEach(input => { input.onpointerdown = () => isCharacter(selected) && captureHistory(); input.oninput = () => applyCharacterSetting(input.dataset.character, input.value); });
document.querySelectorAll('[data-character-number]').forEach(input => input.onchange = () => { if (!isCharacter(selected)) return; captureHistory(); applyCharacterSetting(input.dataset.characterNumber, input.value); });
document.querySelectorAll('[data-shape-part]').forEach(button => button.onclick = () => { if (!isCharacter(selected)) return; captureHistory(); selected.userData.characterSettings[`${button.dataset.shapePart}Shape`] = button.dataset.shapeValue; buildCharacter(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields(); });
document.querySelectorAll('[data-surface]').forEach(input => input.onchange = () => { if (!isSurface(selected)) return; captureHistory(); selected.userData.surfaceSettings[input.dataset.surface] = Number(input.value); buildSurface(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields(); });
document.querySelectorAll('[data-chair]').forEach(input => input.onchange = () => { if (!isChair(selected)) return; captureHistory(); selected.userData.chairSettings[input.dataset.chair] = Number(input.value); buildChair(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields(); });
document.querySelectorAll('[data-table]').forEach(input => input.onchange = () => { if (!isTable(selected)) return; captureHistory(); selected.userData.tableSettings[input.dataset.table] = Number(input.value); buildTable(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields(); });
document.querySelectorAll('[data-stair]').forEach(input => input.onchange = () => { if (!isStair(selected)) return; captureHistory(); selected.userData.stairSettings[input.dataset.stair] = Number(input.value); buildStair(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields(); });
document.querySelectorAll('[data-stair-toggle]').forEach(input => input.onchange = () => { if (!isStair(selected)) return; captureHistory(); selected.userData.stairSettings[input.dataset.stairToggle] = input.checked; buildStair(selected); if (grounding) setOnGround(selected); selectionBox.setFromObject(selected); updateFields(); });
function setTransformMode(mode) {
  transformMode = mode;
  transformControls.setMode(mode);
  document.querySelectorAll('[data-mode]').forEach(item => item.classList.toggle('active', item.dataset.mode === mode));
}
document.querySelectorAll('[data-mode]').forEach(button => button.onclick = () => setTransformMode(button.dataset.mode));
function toggle(id, setter){ $(id).onclick=()=>{const b=$(id); const now=!b.classList.contains('on');b.classList.toggle('on',now);b.setAttribute('aria-pressed',String(now));setter(now);};} toggle('#snapToggle',v=>snapping=v);toggle('#groundToggle',v=>{grounding=v;if(v&&selected){setOnGround(selected);updateFields();}});toggle('#rotationSnapToggle',v=>{rotationSnapping=v;transformControls.setRotationSnap(v?rotationSnapRadians:null);document.querySelectorAll('[data-transform="rotation"]').forEach(input=>{input.step=v?rotationSnapDegrees:1;});if(v&&selected&&transformMode==='rotate'){snapRotation(selected);selectionBox.setFromObject(selected);updateFields();}});toggle('#collisionToggle',v=>{collisionEnabled=v;if(v){passThrough=false;$('#passThroughToggle').classList.remove('on');$('#passThroughToggle').setAttribute('aria-pressed','false');}});toggle('#passThroughToggle',v=>passThrough=v);
document.querySelectorAll('.inspector-tabs button').forEach(b=>b.onclick=()=>{document.querySelectorAll('.inspector-tabs button').forEach(x=>x.classList.remove('active'));b.classList.add('active');const nodes=b.dataset.tab==='nodes';$('#propertiesTab').hidden=nodes;$('#nodesTab').hidden=!nodes;});
document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-view]').forEach(x=>x.classList.remove('active'));b.classList.add('active');const view=b.dataset.view;if(view==='top')camera.position.set(0,0,14);else if(view==='front')camera.position.set(0,-14,2.5);else camera.position.set(8,10,7);controls.target.set(0,0,1);controls.update();});
$('#focusBtn').onclick=()=>{if(selected){controls.target.copy(selected.position);camera.position.copy(selected.position).add(new THREE.Vector3(5,6,4));controls.update();}};
$('#bindBtn').onclick=()=>showToast('基础版组件均绑定至 Scene 根节点');
$('#createGroupBtn').onclick=()=>{const group=new THREE.Group();group.userData={nodeType:'group',name:`分组_${[...scene.children].filter(o=>o.userData?.nodeType==='group').length+1}`};scene.add(group);activeGroup=group;select(group);showToast(`${group.userData.name} 已创建`);};
$('#newSceneBtn').onclick=()=>requestSceneTransition(createNewScene);
$('#openBlendBtn').onclick=()=>{if(!selectedBlock()){showToast('请先选择区块');return;}$('#blendFileInput').value='';$('#blendFileInput').click();};
$('#blendFileInput').onchange=async event=>{const file=event.target.files?.[0],block=selectedBlock();if(!file||!block)return;try{showToast(`正在打开 ${file.name}…`);const response=await fetch(`/api/blocks/${encodeURIComponent(block.id)}/import-blend`,{method:'POST',headers:{'X-File-Name':encodeURIComponent(file.name)},body:file});const payload=await response.json();if(!response.ok)throw new Error(payload.error||'打开失败');captureHistory();activeBlockId=block.id;activeSceneId=payload.id;currentSceneName=payload.name;activeSceneSavedAt=payload.savedAt;restoreScene(payload);void setActivePreview(activeSceneId,activeBlockId);updateSceneTitle();showToast(`已在${block.name}打开 ${file.name}`);}catch(error){showToast(error.message||'Blender 文件打开失败');}};
$('#saveSceneBtn').onclick=()=>showSaveModal();
$('#loadSceneBtn').onclick=()=>requestSceneTransition(showLoadModal);
$('#aiEditBtn').onclick=showAiModal;
$('#confirmSaveBtn').onclick=async()=>{const afterSave=pendingSceneAction;if(await saveCurrentScene($('#sceneNameInput').value)){continueSceneTransition(afterSave);}};
$('#saveBeforeActionBtn').onclick=()=>{const action=pendingSceneAction;showSaveModal(action);};
$('#discardSceneBtn').onclick=()=>{continueSceneTransition(pendingSceneAction);};
$('#confirmLoadBtn').onclick=async()=>{const id=$('#savedSceneSelect').value,block=selectedBlock();if(!id||!block)return;try{const response=await fetch(`/api/blocks/${encodeURIComponent(block.id)}/scenes/${encodeURIComponent(id)}`);if(!response.ok)throw new Error('load');const payload=await response.json();captureHistory();restoreScene(payload);activeSceneId=payload.id||id;activeBlockId=block.id;currentSceneName=payload.name||id;activeSceneSavedAt=payload.savedAt||null;void setActivePreview(activeSceneId,activeBlockId);updateSceneTitle();closeModal();showToast(`已从${block.name}读取“${currentSceneName}”`);}catch{showToast('场景文件读取失败');}};
$('#blockSelect').onchange=()=>{activeBlockId=$('#blockSelect').value||null;renderAssets($('#searchInput').value.trim());requestSceneTransition(createNewScene);updateSceneTitle();};
$('#applyAiCommandBtn').onclick=applyAiCommands;
if ($('#chooseSaveDirBtn')) $('#chooseSaveDirBtn').onclick=()=>showToast('Blender 场景保存在 tools/3Dgame-design/save/blocks/区块/场景/');
document.querySelectorAll('[data-modal-close]').forEach(button=>button.onclick=()=>{pendingSceneAction=null;closeModal();});
$('#modalBackdrop').onclick=e=>{if(e.target===e.currentTarget){pendingSceneAction=null;closeModal();}};
$('#undoBtn').onclick=undoScene; $('#redoBtn').onclick=redoScene;
document.addEventListener('keydown',e=>{
  const target = document.activeElement;
  const editingText = ['INPUT','TEXTAREA','SELECT'].includes(target?.tagName) || target?.isContentEditable;
  const key = e.key.toLowerCase();
  if (!e.ctrlKey && !e.metaKey && !e.altKey && !editingText) {
    const mode = { w: 'translate', r: 'rotate', s: 'scale' }[key];
    if (mode) { e.preventDefault(); setTransformMode(mode); showToast(`${mode === 'translate' ? '移动' : mode === 'rotate' ? '旋转' : '缩放'}工具已激活`); return; }
  }
  if (!(e.ctrlKey || e.metaKey)) return;
  if(key==='z'){e.preventDefault();e.shiftKey?redoScene():undoScene();}else if(key==='y'){e.preventDefault();redoScene();}else if(key==='c'&&!editingText){if(selected){clipboardComponent=componentSnapshot(selected);showToast('组件已复制');e.preventDefault();}}else if(key==='v'&&!editingText){pasteComponent();e.preventDefault();}
});
$('#exportBtn').onclick=()=>{if(!activeSceneId||!activeBlockId){showToast('请先保存 Blender 场景');return;}const a=document.createElement('a');a.href=`/api/blocks/${encodeURIComponent(activeBlockId)}/scenes/${encodeURIComponent(activeSceneId)}/blend`;a.download=`${activeSceneId}.blend`;a.click();showToast('开始下载 Blender 场景');};
function resize(){const r=container.getBoundingClientRect();camera.aspect=r.width/r.height;camera.updateProjectionMatrix();renderer.setSize(r.width,r.height);}new ResizeObserver(resize).observe(container);resize();
window.setInterval(syncAiScenePreview, 1200);
void loadProjectBlocks();
function animate(){requestAnimationFrame(animate);controls.update();drawOrientationGizmo();renderer.render(scene,camera);} animate();
