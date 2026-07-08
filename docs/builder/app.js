// Koti Card Builder — a plain HTML/CSS/JS page (no build step, no external
// dependencies) that produces JSON matching docs/CARD_FORMAT.md's canvas
// popup layout. Output is designed to paste straight into the app's card
// editor: no login, no network calls, nothing but a JSON textarea in, a
// JSON textarea out.

const STORAGE_KEY = 'koti-card-builder-draft';

const BLOCK_DEFS = {
  text: {
    label: 'Text', defaultW: 0.5, defaultH: 0.08,
    fields: [
      { key: 'text', label: 'Text (template)', type: 'text', default: 'Label' },
      { key: 'size', label: 'Size', type: 'select', options: ['small', 'normal', 'large', 'title'], default: 'normal' },
      { key: 'align', label: 'Align', type: 'select', options: ['left', 'center', 'right'], default: 'left' },
      { key: 'color', label: 'Color', type: 'text', placeholder: 'active / secondary / #rrggbb' },
    ],
  },
  icon: {
    label: 'Icon', defaultW: 0.18, defaultH: 0.16,
    fields: [
      { key: 'icon', label: 'Icon', type: 'iconpicker', default: 'power_on' },
      { key: 'circle', label: 'Circle background', type: 'checkbox', default: true },
      { key: 'activeWhen', label: 'Active when', type: 'text', placeholder: "state == 'on'" },
    ],
  },
  entity: {
    label: 'Entity row', defaultW: 0.6, defaultH: 0.12,
    fields: [
      { key: 'entity', label: 'Entity (blank = card default)', type: 'text' },
      { key: 'icon', label: 'Icon override', type: 'iconpicker' },
    ],
  },
  toggle: {
    label: 'Toggle', defaultW: 0.55, defaultH: 0.09,
    fields: [
      { key: 'entity', label: 'Entity (blank = card default)', type: 'text' },
      { key: 'label', label: 'Label', type: 'text' },
    ],
  },
  slider: {
    label: 'Slider', defaultW: 0.75, defaultH: 0.11,
    fields: [
      { key: 'label', label: 'Label', type: 'text' },
      { key: 'value', label: 'Value path', type: 'text', placeholder: 'attributes.brightness' },
      { key: 'min', label: 'Min', type: 'number', default: 0 },
      { key: 'max', label: 'Max', type: 'number', default: 100 },
      { key: 'step', label: 'Step', type: 'number' },
      { key: 'service', label: 'Service', type: 'text', placeholder: 'light.turn_on' },
      { key: 'field', label: 'Field', type: 'text', placeholder: 'brightness' },
      { key: 'entity', label: 'Entity (blank = card default)', type: 'text' },
    ],
  },
  progress: {
    label: 'Progress bar', defaultW: 0.75, defaultH: 0.05,
    fields: [
      { key: 'value', label: 'Value path', type: 'text', placeholder: 'attributes.progress' },
      { key: 'max', label: 'Max', type: 'number', default: 100 },
    ],
  },
  button: {
    label: 'Button', defaultW: 0.35, defaultH: 0.09,
    fields: [
      { key: 'text', label: 'Text', type: 'text', default: 'Button' },
      { key: 'icon', label: 'Icon', type: 'iconpicker' },
      { key: 'style', label: 'Style', type: 'select', options: ['outlined', 'filled'], default: 'outlined' },
    ],
    action: true,
  },
  divider: { label: 'Divider', defaultW: 0.8, defaultH: 0.015, fields: [] },
};

let design = defaultDesign();
let selectedId = null;
let idCounter = 0;

function defaultDesign() {
  return {
    name: '{name}', icon: 'power_on', entity: '', state: '{state|title}', activeWhen: '',
    popupLayout: 'canvas', canvasSize: [360, 480],
    popup: [],
  };
}

function newBlockId() { return `b${++idCounter}`; }

// --- init -------------------------------------------------------------

function init() {
  const iconList = document.getElementById('icon-list');
  iconList.innerHTML = KNOWN_ICONS.map(i => `<option value="${i}">`).join('');

  const grid = document.getElementById('palette-grid');
  grid.innerHTML = Object.entries(BLOCK_DEFS)
    .map(([type, def]) => `<button class="palette-block" data-type="${type}">${def.label}</button>`)
    .join('');
  grid.addEventListener('click', e => {
    const btn = e.target.closest('.palette-block');
    if (btn) addBlock(btn.dataset.type);
  });

  bindCardFields();
  bindTopbar();
  bindModal();

  loadDraft();
  renderAll();
}

function bindCardFields() {
  const map = {
    'f-name': 'name', 'f-entity': 'entity', 'f-icon': 'icon',
    'f-state': 'state', 'f-activeWhen': 'activeWhen',
  };
  for (const [id, key] of Object.entries(map)) {
    document.getElementById(id).addEventListener('input', e => {
      design[key] = e.target.value;
      saveDraft();
      renderWarnings();
    });
  }
  document.getElementById('f-canvas-w').addEventListener('input', e => {
    design.canvasSize[0] = Number(e.target.value) || 360;
    renderCanvas();
    saveDraft();
  });
  document.getElementById('f-canvas-h').addEventListener('input', e => {
    design.canvasSize[1] = Number(e.target.value) || 480;
    renderCanvas();
    saveDraft();
  });
}

function bindTopbar() {
  document.getElementById('btn-new').addEventListener('click', () => {
    if (design.popup.length && !confirm('Start a new card? Unsaved changes will be lost.')) return;
    design = defaultDesign();
    selectedId = null;
    idCounter = 0;
    saveDraft();
    renderAll();
  });
  document.getElementById('btn-export').addEventListener('click', openExportModal);
  document.getElementById('btn-import').addEventListener('click', openImportModal);
}

// --- blocks -------------------------------------------------------------

function addBlock(type) {
  const def = BLOCK_DEFS[type];
  const block = { _id: newBlockId(), type };
  for (const f of def.fields) if (f.default !== undefined) block[f.key] = f.default;
  if (def.action) block.action = { action: 'toggle' };

  const n = design.popup.length;
  const cascade = (n % 6) * 0.03;
  block.x = round3(0.08 + cascade);
  block.y = round3(0.06 + cascade);
  block.w = def.defaultW;
  block.h = def.defaultH;

  design.popup.push(block);
  selectedId = block._id;
  saveDraft();
  renderAll();
}

function removeBlock(id) {
  design.popup = design.popup.filter(b => b._id !== id);
  if (selectedId === id) selectedId = null;
  saveDraft();
  renderAll();
}

function getBlock(id) { return design.popup.find(b => b._id === id); }

function round3(n) { return Math.round(n * 1000) / 1000; }

// --- canvas rendering -----------------------------------------------------

function renderCanvas() {
  const canvas = document.getElementById('canvas');
  const [w, h] = design.canvasSize;
  const maxW = 420;
  const cssW = Math.min(maxW, w);
  canvas.style.width = cssW + 'px';
  canvas.style.aspectRatio = `${w} / ${h}`;
  canvas.innerHTML = '';

  for (const block of design.popup) {
    canvas.appendChild(buildBlockEl(block));
  }

  canvas.onpointerdown = e => {
    if (e.target === canvas) selectBlock(null);
  };
}

function buildBlockEl(block) {
  const el = document.createElement('div');
  el.className = 'block' + (block._id === selectedId ? ' selected' : '');
  el.style.left = (block.x * 100) + '%';
  el.style.top = (block.y * 100) + '%';
  el.style.width = (block.w * 100) + '%';
  el.style.height = (block.h * 100) + '%';
  el.dataset.id = block._id;

  const inner = document.createElement('div');
  inner.className = 'block-inner';
  inner.innerHTML = previewHtml(block);
  el.appendChild(inner);

  const handle = document.createElement('div');
  handle.className = 'resize-handle';
  el.appendChild(handle);

  el.addEventListener('pointerdown', e => startDrag(e, block, el));
  handle.addEventListener('pointerdown', e => startResize(e, block, el));

  return el;
}

function previewHtml(b) {
  switch (b.type) {
    case 'text':
      return `<div class="bp-text size-${b.size || 'normal'}" style="text-align:${b.align || 'left'}">${escapeHtml(b.text || 'Label')}</div>`;
    case 'icon':
      return b.circle === false
        ? `<div class="bp-icon">${escapeHtml(b.icon || '?')}</div>`
        : `<div class="bp-icon"><div class="bp-icon-circle">${escapeHtml(b.icon || '?')}</div></div>`;
    case 'entity':
      return `<div class="bp-entity"><div class="dot"></div><div class="lines"><div>${escapeHtml(b.entity || 'Entity')}</div><div>state</div></div></div>`;
    case 'toggle':
      return `<div class="bp-toggle"><span>${escapeHtml(b.label || b.entity || 'Toggle')}</span><div class="switch"></div></div>`;
    case 'slider':
      return `<div class="bp-slider"><div class="label">${escapeHtml(b.label || 'Slider')}</div><div class="track"></div></div>`;
    case 'progress':
      return `<div class="bp-progress"><div class="bar"></div></div>`;
    case 'button':
      return `<div class="bp-button ${b.style === 'filled' ? 'filled' : ''}">${escapeHtml(b.text || b.icon || 'Button')}</div>`;
    case 'divider':
      return `<div class="bp-divider"></div>`;
    default:
      return `<div class="bp-text">?</div>`;
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function updateBlockPreview(id) {
  const el = document.querySelector(`.block[data-id="${id}"]`);
  if (!el) return;
  el.querySelector('.block-inner').innerHTML = previewHtml(getBlock(id));
}

// --- drag / resize --------------------------------------------------------

// Listens on `document` rather than the dragged element (and skips
// setPointerCapture) so a fast drag that outruns the element's own bounds
// — easy to do with a small block — keeps tracking the pointer instead of
// silently going dead.
function startDrag(e, block, el) {
  if (e.target.classList.contains('resize-handle')) return;
  e.preventDefault();
  selectBlock(block._id);
  const canvas = document.getElementById('canvas');
  const rect = canvas.getBoundingClientRect();
  const startX = e.clientX, startY = e.clientY;
  const origX = block.x, origY = block.y;
  el.classList.add('dragging');

  function move(ev) {
    const dx = (ev.clientX - startX) / rect.width;
    const dy = (ev.clientY - startY) / rect.height;
    block.x = clamp(round3(origX + dx), 0, 1 - block.w);
    block.y = clamp(round3(origY + dy), 0, 1 - block.h);
    el.style.left = (block.x * 100) + '%';
    el.style.top = (block.y * 100) + '%';
  }
  function up() {
    el.classList.remove('dragging');
    document.removeEventListener('pointermove', move);
    document.removeEventListener('pointerup', up);
    saveDraft();
  }
  document.addEventListener('pointermove', move);
  document.addEventListener('pointerup', up);
}

function startResize(e, block, el) {
  e.preventDefault();
  e.stopPropagation();
  const canvas = document.getElementById('canvas');
  const rect = canvas.getBoundingClientRect();
  const startX = e.clientX, startY = e.clientY;
  const origW = block.w, origH = block.h;

  function move(ev) {
    const dw = (ev.clientX - startX) / rect.width;
    const dh = (ev.clientY - startY) / rect.height;
    block.w = clamp(round3(origW + dw), 0.03, 1 - block.x);
    block.h = clamp(round3(origH + dh), 0.02, 1 - block.y);
    el.style.width = (block.w * 100) + '%';
    el.style.height = (block.h * 100) + '%';
  }
  function up() {
    document.removeEventListener('pointermove', move);
    document.removeEventListener('pointerup', up);
    saveDraft();
  }
  document.addEventListener('pointermove', move);
  document.addEventListener('pointerup', up);
}

function clamp(v, lo, hi) {
  if (hi < lo) return lo; // block is larger than the canvas on this axis
  return Math.min(Math.max(v, lo), hi);
}

function selectBlock(id) {
  selectedId = id;
  document.querySelectorAll('.block').forEach(el => {
    el.classList.toggle('selected', el.dataset.id === id);
  });
  renderInspector();
}

// --- inspector --------------------------------------------------------

function renderInspector() {
  const body = document.getElementById('inspector-body');
  const block = selectedId ? getBlock(selectedId) : null;
  if (!block) {
    body.className = 'inspector-empty';
    body.textContent = 'Select a block on the canvas to edit it.';
    return;
  }
  body.className = '';
  const def = BLOCK_DEFS[block.type];
  body.innerHTML = '';

  const heading = document.createElement('div');
  heading.className = 'field';
  heading.innerHTML = `<label>Block type</label><input value="${def.label}" disabled>`;
  body.appendChild(heading);

  for (const f of def.fields) body.appendChild(renderField(block, f));

  if (def.action) body.appendChild(renderActionField(block));

  const showWhenField = document.createElement('div');
  showWhenField.className = 'field';
  showWhenField.innerHTML = `<label>Show when (optional)</label>
    <input type="text" placeholder="state == 'on'" value="${escapeAttr(block.showWhen || '')}">`;
  showWhenField.querySelector('input').addEventListener('input', e => {
    block.showWhen = e.target.value;
    saveDraft();
  });
  body.appendChild(showWhenField);

  const del = document.createElement('button');
  del.className = 'btn';
  del.style.width = '100%';
  del.style.marginTop = '8px';
  del.style.borderColor = 'var(--danger)';
  del.style.color = 'var(--danger)';
  del.textContent = 'Delete block';
  del.addEventListener('click', () => removeBlock(block._id));
  body.appendChild(del);
}

function renderField(block, f) {
  const wrap = document.createElement('div');
  wrap.className = f.type === 'checkbox' ? 'field-check' : 'field';
  const value = block[f.key] !== undefined ? block[f.key] : (f.default !== undefined ? f.default : '');

  let input;
  if (f.type === 'select') {
    input = document.createElement('select');
    input.innerHTML = f.options.map(o => `<option value="${o}" ${o === value ? 'selected' : ''}>${o}</option>`).join('');
  } else if (f.type === 'checkbox') {
    input = document.createElement('input');
    input.type = 'checkbox';
    input.checked = value !== false;
  } else {
    input = document.createElement('input');
    input.type = f.type === 'number' ? 'number' : 'text';
    input.value = value;
    if (f.placeholder) input.placeholder = f.placeholder;
    if (f.type === 'iconpicker') input.setAttribute('list', 'icon-list');
  }

  const label = document.createElement('label');
  label.textContent = f.label;
  if (f.type === 'checkbox') {
    wrap.appendChild(input);
    wrap.appendChild(label);
  } else {
    wrap.appendChild(label);
    wrap.appendChild(input);
  }

  input.addEventListener('input', () => {
    if (f.type === 'checkbox') block[f.key] = input.checked;
    else if (f.type === 'number') block[f.key] = input.value === '' ? undefined : Number(input.value);
    else block[f.key] = input.value;
    updateBlockPreview(block._id);
    renderWarnings();
    saveDraft();
  });

  return wrap;
}

function renderActionField(block) {
  const wrap = document.createElement('div');
  wrap.className = 'field';
  block.action = block.action || { action: 'toggle' };

  const typeSel = document.createElement('select');
  typeSel.innerHTML = ['none', 'toggle', 'service', 'popup']
    .map(t => `<option value="${t}" ${t === block.action.action ? 'selected' : ''}>${t}</option>`).join('');

  const label = document.createElement('label');
  label.textContent = 'Tap action';
  wrap.appendChild(label);
  wrap.appendChild(typeSel);

  const serviceField = document.createElement('div');
  serviceField.className = 'field';
  serviceField.innerHTML = `<label>Service (domain.service)</label>
    <input type="text" placeholder="light.turn_on" value="${escapeAttr(block.action.service || '')}">`;
  serviceField.style.display = block.action.action === 'service' ? '' : 'none';
  serviceField.querySelector('input').addEventListener('input', e => {
    block.action.service = e.target.value;
    saveDraft();
    renderWarnings();
  });

  const entityField = document.createElement('div');
  entityField.className = 'field';
  entityField.innerHTML = `<label>Action entity override</label>
    <input type="text" value="${escapeAttr(block.action.entity || '')}">`;
  entityField.querySelector('input').addEventListener('input', e => {
    block.action.entity = e.target.value;
    saveDraft();
  });

  typeSel.addEventListener('change', () => {
    block.action.action = typeSel.value;
    serviceField.style.display = typeSel.value === 'service' ? '' : 'none';
    renderWarnings();
    saveDraft();
  });

  const container = document.createElement('div');
  container.appendChild(wrap);
  container.appendChild(serviceField);
  container.appendChild(entityField);
  return container;
}

function escapeAttr(s) { return String(s).replace(/"/g, '&quot;'); }

// --- warnings (mirrors CustomCardSpec.validate in lib/custom/card_spec.dart) --

function renderWarnings() {
  const warnings = [];
  if (!KNOWN_ICONS.includes(design.icon)) {
    warnings.push(`Unknown card icon "${design.icon}" — falls back to "home"`);
  }
  for (const b of design.popup) {
    if (b.type === 'icon' && b.icon && !KNOWN_ICONS.includes(b.icon)) {
      warnings.push(`Unknown icon "${b.icon}" in a block`);
    }
    if (b.type === 'button' && b.icon && !KNOWN_ICONS.includes(b.icon)) {
      warnings.push(`Unknown icon "${b.icon}" in a button`);
    }
    if (b.type === 'button' && b.action?.action === 'service' && !(b.action.service || '').includes('.')) {
      warnings.push(`A button's service must be "domain.service"`);
    }
    if (b.type === 'slider' && !(b.service || '').includes('.')) {
      warnings.push(`A slider needs "service": "domain.service"`);
    }
  }
  const el = document.getElementById('warnings');
  el.innerHTML = warnings.map(w => `<div class="warning">${escapeHtml(w)}</div>`).join('');
}

// --- export / import ----------------------------------------------------

function toExportJson() {
  const out = {
    name: design.name || '{name}',
    icon: design.icon || 'power_on',
    state: design.state || '{state|title}',
    popupLayout: 'canvas',
    canvasSize: design.canvasSize,
    popup: design.popup.map(stripBlock),
  };
  if (design.entity) out.entity = design.entity;
  if (design.activeWhen) out.activeWhen = design.activeWhen;
  return JSON.stringify(out, null, 2);
}

function stripBlock(b) {
  const { _id, ...rest } = b;
  return rest;
}

function openExportModal() {
  renderWarnings();
  document.getElementById('modal-title').textContent = 'Export card';
  document.getElementById('modal-textarea').value = toExportJson();
  document.getElementById('modal-textarea').readOnly = true;
  document.getElementById('modal-hint').textContent = 'Paste this into the Custom card editor in Koti, or share it with someone else.';
  document.getElementById('modal-copy').classList.remove('hidden');
  document.getElementById('modal-download').classList.remove('hidden');
  document.getElementById('modal-load').classList.add('hidden');
  document.getElementById('modal-backdrop').classList.remove('hidden');
}

function openImportModal() {
  document.getElementById('modal-title').textContent = 'Import card';
  document.getElementById('modal-textarea').value = '';
  document.getElementById('modal-textarea').readOnly = false;
  document.getElementById('modal-hint').textContent = 'Paste a card\'s JSON here.';
  document.getElementById('modal-copy').classList.add('hidden');
  document.getElementById('modal-download').classList.add('hidden');
  document.getElementById('modal-load').classList.remove('hidden');
  document.getElementById('modal-backdrop').classList.remove('hidden');
  document.getElementById('modal-textarea').focus();
}

function bindModal() {
  document.getElementById('modal-close').addEventListener('click', closeModal);
  document.getElementById('modal-backdrop').addEventListener('click', e => {
    if (e.target.id === 'modal-backdrop') closeModal();
  });
  document.getElementById('modal-copy').addEventListener('click', async () => {
    const ta = document.getElementById('modal-textarea');
    ta.select();
    try {
      await navigator.clipboard.writeText(ta.value);
      document.getElementById('modal-hint').textContent = 'Copied!';
    } catch {
      document.getElementById('modal-hint').textContent = 'Select all (Ctrl/Cmd+A) and copy manually.';
    }
  });
  document.getElementById('modal-download').addEventListener('click', () => {
    const blob = new Blob([document.getElementById('modal-textarea').value], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = (design.name || 'card').replace(/[^a-z0-9]+/gi, '-').toLowerCase() + '.json';
    a.click();
    URL.revokeObjectURL(a.href);
  });
  document.getElementById('modal-load').addEventListener('click', () => {
    const text = document.getElementById('modal-textarea').value;
    try {
      loadFromJson(JSON.parse(text));
      closeModal();
    } catch (e) {
      document.getElementById('modal-hint').textContent = 'Not valid JSON: ' + e.message;
    }
  });
}

function closeModal() {
  document.getElementById('modal-backdrop').classList.add('hidden');
}

function loadFromJson(json) {
  const loaded = defaultDesign();
  loaded.name = json.name || loaded.name;
  loaded.icon = json.icon || loaded.icon;
  loaded.entity = json.entity || '';
  loaded.state = json.state || loaded.state;
  loaded.activeWhen = json.activeWhen || '';
  if (Array.isArray(json.canvasSize) && json.canvasSize.length === 2) {
    loaded.canvasSize = [Number(json.canvasSize[0]) || 360, Number(json.canvasSize[1]) || 480];
  }

  const rawPopup = Array.isArray(json.popup) ? json.popup : [];
  const isCanvas = json.popupLayout === 'canvas';
  loaded.popup = rawPopup
    .filter(b => b && BLOCK_DEFS[b.type])
    .map((b, i) => {
      const block = { ...b, _id: newBlockId() };
      if (!isCanvas || block.x === undefined || block.y === undefined) {
        const cascade = (i % 6) * 0.03;
        block.x = 0.08 + cascade;
        block.y = 0.06 + cascade;
      }
      if (block.w === undefined) block.w = BLOCK_DEFS[b.type].defaultW;
      if (block.h === undefined) block.h = BLOCK_DEFS[b.type].defaultH;
      return block;
    });

  design = loaded;
  selectedId = null;
  saveDraft();
  renderAll();
}

// --- persistence (local draft only, nothing leaves the browser) -----------

function saveDraft() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(design)); } catch { /* storage unavailable */ }
}

function loadDraft() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw);
    if (parsed && Array.isArray(parsed.popup)) {
      design = parsed;
      idCounter = design.popup.length;
      design.popup.forEach((b, i) => { if (!b._id) b._id = newBlockId(); });
    }
  } catch { /* ignore a corrupt draft */ }
}

// --- top-level render ---------------------------------------------------

function renderAll() {
  document.getElementById('f-name').value = design.name;
  document.getElementById('f-entity').value = design.entity;
  document.getElementById('f-icon').value = design.icon;
  document.getElementById('f-state').value = design.state;
  document.getElementById('f-activeWhen').value = design.activeWhen;
  document.getElementById('f-canvas-w').value = design.canvasSize[0];
  document.getElementById('f-canvas-h').value = design.canvasSize[1];
  renderCanvas();
  renderInspector();
  renderWarnings();
}

init();
