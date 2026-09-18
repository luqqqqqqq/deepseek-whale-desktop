// V2 启动器：给原版宿主提供一套最小 DSH 环境（shim），并用本地 HTTP 服务承载挂件网页
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.dirname(HERE)
const SRC = path.join(HERE, 'widget')
const DATA_DIR = process.env.DSH_HOME || path.join(ROOT, '.dshw-data')
fs.mkdirSync(DATA_DIR, { recursive: true })
process.env.DSH_HOME = DATA_DIR

const CRED_FILE = path.join(DATA_DIR, 'credentials.json')
function readCreds() { try { return JSON.parse(fs.readFileSync(CRED_FILE, 'utf8')) } catch (e) { return {} } }
function writeCreds(c) { fs.writeFileSync(CRED_FILE, JSON.stringify(c, null, 2), 'utf8') }

const routes = []
const indexHooks = []
const listeners = []

const credentials = {
  async resolve(ref) { const c = readCreds(); return Object.prototype.hasOwnProperty.call(c, ref) ? c[ref] : undefined },
  async set(ref, val) { const c = readCreds(); if (val === undefined || val === null) delete c[ref]; else c[ref] = String(val); writeCreds(c) },
}
const connection = { requestRejection() { return false } }
const webServer = {
  register(route) { routes.push(route); return () => {} },
  tapIndex(fn) { indexHooks.push(fn); return () => {} },
}
const services = { webServer, credentials, connection }
const ctx = {
  get(name) { return services[name] },
  get webServer() { return webServer },
  get credentials() { return credentials },
  get connection() { return connection },
  on(ev, fn) { listeners.push([ev, fn]); return () => {} },
  effect(fn) { try { const c = fn(); if (typeof c === 'function') listeners.push(['cleanup', c]) } catch (e) {} },
}

const plugin = (await import(pathToFileURL(path.join(SRC, 'lib', 'index.js')).href)).default
plugin.apply(ctx)

const HOST_DRAG_SCRIPT = `<script>
(function(){
  if (window.__dshwWinDrag) return; window.__dshwWinDrag = true;
  function post(s){ try { if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(s); } catch(e){} }
  window.addEventListener('pointerdown', function(e){
    try {
      if (e.pointerType === 'mouse' && e.button !== 0) return;
      if (e.target && e.target.closest) {
        if (e.target.closest('.dshwv-pop,.dshwv-menu,.dshwv-menu-btn,.dshwv-rolelist,.dshwv-audiolist,.dshwv-cropmask,.dshwv-confirmmask,.dshwv-audiomask,.dshwv-snapmask,.dshwv-bubmask,.dshwv-qedit,.dshwv-usagepanel,.dshwv-usage-mask,.dshwv-resmask,.dshwv-custmenu,.dshwv-custbtn,.dshwv-rolebtn,.dshwv-audiobtn')) return;
      }
      post('dragstart');
    } catch(err){}
  }, true);
  window.addEventListener('pointerup', function(){ try { post('dragend'); } catch(err){} }, true);
  window.addEventListener('pointercancel', function(){ try { post('dragend'); } catch(err){} }, true);
  window.addEventListener('keydown', function(e){
    try { if (e.key === 'Escape') { e.preventDefault(); post('close'); } } catch(err){}
  }, true);
})();
<\/script>`;

const HOST_SIZE_SCRIPT = `<script>
(function(){
  if (window.__dshwSizeWatch) return; window.__dshwSizeWatch = true;
  function post(s){ try { if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(s); } catch(e){} }
  var PAD = 8;
  var sels = ['.dshwv-root', '.dshwv-menu.dshwv-menu-open', '.dshwv-rolelist', '.dshwv-audiolist', '.dshwv-usagepanel', '.dshwv-pop.dshwv-pop-open'];
  function measure(){
    var out = [];
    for (var i=0;i<sels.length;i++){
      var els = document.querySelectorAll(sels[i]);
      for (var j=0;j<els.length;j++){
        var el = els[j];
        var cs = el.ownerDocument.defaultView.getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden') continue;
        var r = el.getBoundingClientRect();
        if (r.width > 0 && r.height > 0) out.push(r);
      }
    }
    return out;
  }
  function report(){
    try {
      var rs = measure();
      if (!rs.length) return;
      var minL=Infinity, minT=Infinity, maxR=-Infinity, maxB=-Infinity;
      for (var i=0;i<rs.length;i++){
        var r = rs[i];
        if (r.left < minL) minL = r.left;
        if (r.top < minT) minT = r.top;
        if (r.right > maxR) maxR = r.right;
        if (r.bottom > maxB) maxB = r.bottom;
      }
      var w = Math.ceil(maxR - minL + PAD*2);
      var h = Math.ceil(maxB - minT + PAD*2);
      if (w === lastW && h === lastH) return;
      lastW = w; lastH = h;
      post('setsize:' + w + ',' + h);
    } catch(e){}
  }
  var lastW = 0, lastH = 0;
  function watchSize(el){
    if (!el || el.__dshwWatched) return; el.__dshwWatched = true;
    if (window.ResizeObserver) { try { new ResizeObserver(function(){ report(); }).observe(el); } catch(e){} }
  }
  function watchMenu(el){
    if (!el || el.__dshwMenuWatched) return; el.__dshwMenuWatched = true;
    if (window.MutationObserver) { try { new MutationObserver(function(){ report(); setTimeout(report, 220); }).observe(el, {attributes:true, attributeFilter:['class']}); } catch(e){} }
    watchSize(el);
  }
  function scan(){
    watchSize(document.querySelector('.dshwv-root'));
    watchMenu(document.querySelector('.dshwv-menu'));
    var extra = ['.dshwv-rolelist','.dshwv-audiolist','.dshwv-usagepanel','.dshwv-pop'];
    for (var i=0;i<extra.length;i++){ watchSize(document.querySelector(extra[i])); }
    report();
  }
  var iv = setInterval(scan, 500);
  scan();
})();
<\/script>`;

const HOST_MENU_SCRIPT = `<script>
(function(){
  if (window.__dshwMenuHost) return; window.__dshwMenuHost = true;
  function post(s){ try { if (window.chrome && window.chrome.webview) window.chrome.webview.postMessage(s); } catch(e){} }
  var LOCK_KEY = 'dshw-lock';
  function snapCfgFlat(){
    try {
      var raw = localStorage.getItem('dshw-snap');
      if (!raw) return null;
      var d = JSON.parse(raw);
      if (!d || !d.mode) return null;
      var r = d.ratio || {}; var p = d.px || {};
      return d.mode + ',' +
        (r.L != null ? r.L : 10) + ',' + (r.T != null ? r.T : 0) + ',' + (r.R != null ? r.R : 10) + ',' + (r.B != null ? r.B : 15) + ',' + (r.F != null ? r.F : 50) + ',' +
        (p.L != null ? p.L : 80) + ',' + (p.T != null ? p.T : 0) + ',' + (p.R != null ? p.R : 80) + ',' + (p.B != null ? p.B : 80) + ',' + (p.F != null ? p.F : -1);
    } catch(e){ return null; }
  }
  function postSnap(){ var f = snapCfgFlat(); if (f) post('snapcfg:' + f); }
  try {
    var origSet = localStorage.setItem.bind(localStorage);
    localStorage.setItem = function(k, v){
      try { origSet(k, v); } catch(e){}
      if (k === 'dshw-snap') postSnap();
    };
  } catch(e){}
  function lockOn(){ try { return localStorage.getItem(LOCK_KEY) === '1'; } catch(e){ return false; } }
  function postLock(){ post('lock:' + (lockOn() ? '1' : '0')); }
  var lastGap = '';
  function postScrollGap(){
    try {
      fetch('/dsh-whale/size.json', {cache:'no-store'})
        .then(function(r){ return r.json(); })
        .then(function(d){
          var on = (d && d.scrollGapOn === true) ? '1' : '0';
          var px = (d && typeof d.scrollGapPx === 'number' && d.scrollGapPx > 0) ? String(Math.round(d.scrollGapPx)) : '0';
          var g = on + ',' + px;
          if (g !== lastGap) { lastGap = g; post('scrollgap:' + g); }
        })
        .catch(function(){});
    } catch(e){}
  }
  function injectLock(){
    var view = document.querySelector('.dshwv-menuview');
    if (!view || view.__dshwLockRow) return;
    view.__dshwLockRow = true;
    var row = document.createElement('div');
    row.className = 'dshwv-menu-row';
    var label = document.createElement('span');
    label.textContent = '锁定位置';
    var toggle = document.createElement('input');
    toggle.type = 'checkbox';
    toggle.className = 'dshwv-check';
    toggle.checked = lockOn();
    toggle.title = '锁定后鲸鱼不能拖动';
    toggle.addEventListener('change', function(){
      try { localStorage.setItem(LOCK_KEY, toggle.checked ? '1' : '0'); } catch(e){}
      postLock();
    });
    row.appendChild(label);
    row.appendChild(toggle);
    view.appendChild(row);
  }
  function boot(){ postSnap(); postLock(); postScrollGap(); injectLock(); }
  boot();
  setTimeout(boot, 1500);
  setInterval(injectLock, 500);
  setInterval(postScrollGap, 1500);
})();
<\/script>`;

const PORT = Number(process.env.PORT || 9876)
const server = http.createServer(async (req, res) => {
  const u = new URL(req.url || '/', 'http://localhost')
  const p = u.pathname
  const route = routes.find((r) => r.path === p)
  if (route) { try { await route.handler(req, res) } catch (e) { if (!res.headersSent) { res.writeHead(500); res.end(String(e && e.message || e)) } } return }
  if (p === '/' || p === '/index.html') {
    let html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>DeepSeek Whale</title><style>html,body{margin:0;height:100%;overflow:hidden;background:transparent}.dshwv-root{position:fixed!important;left:auto!important;top:auto!important;right:0!important;bottom:0!important;--dshw-base:clamp(122px,calc(250px * var(--dshw-scale)),625px)!important}.dshwv-root.dshwv-left{transform:none!important}.dshwv-root.dshwv-left .dshwv-gif{transform:translate(-50%,-50%)!important}.dshwv-root.dshwv-left .dshwv-text{transform:translate(-50%,-50%)!important}.dshwv-root.dshwv-host-left{right:auto!important;left:0!important;transform:scaleX(-1)!important}.dshwv-root.dshwv-host-left .dshwv-gif{transform:translate(-50%,-50%) scaleX(-1)!important}.dshwv-root.dshwv-host-left .dshwv-text{transform:translate(-50%,-50%) scaleX(-1)!important}</style></head><body><div id="root"><textarea style="width:1px;height:1px;opacity:0"></textarea></div>' + HOST_DRAG_SCRIPT + HOST_SIZE_SCRIPT + HOST_MENU_SCRIPT + '</body></html>'
    for (const fn of indexHooks) { try { html = fn(html) || html } catch (e) {} }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
    res.end(html)
    return
  }
  res.writeHead(404)
  res.end('not found')
})
server.listen(PORT, '127.0.0.1', () => {
  console.log('whale-v2 listening on http://127.0.0.1:' + PORT)
  console.log('data dir: ' + DATA_DIR)
  if (process.argv.includes('--selftest')) {
    const base = 'http://127.0.0.1:' + PORT
    const probe = async (u) => {
      try {
        const r = await fetch(base + u)
        const t = await r.text()
        return r.status + ' ' + (r.headers.get('content-type') || '') + ' len=' + t.length + ' ' + t.slice(0, 80).replace(/\n/g, ' ')
      } catch (e) { return 'ERR ' + e.message }
    }
    ;(async () => {
      console.log('SELFTEST /            -> ' + (await probe('/')))
      console.log('SELFTEST /dsh-whale/widget.js -> ' + (await probe('/dsh-whale/widget.js')))
      console.log('SELFTEST /dsh-whale/balance.json -> ' + (await probe('/dsh-whale/balance.json')))
      if (server.closeAllConnections) server.closeAllConnections()
      server.close()
      setTimeout(() => process.exit(0), 300)
    })()
  }
})
