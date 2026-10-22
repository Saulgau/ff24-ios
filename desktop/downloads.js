// 2026-10-22: Offline-Downloads in der PC-App (wie Prime Video).
// Hauptprozess: lädt die öffentlichen MP4s (+ Forced-VTT) nach <userData>/Downloads, merkt sich die
// q=play-Daten und meldet den Stand an alle Fenster. Abspielen offline über downloads.html.
const { app, ipcMain, net, session, BrowserWindow, shell } = require('electron');
const fs = require('fs');
const path = require('path');

const API = 'https://filmfrei24.com/beta/api.php?q=play';
let dir, metaFile, items = [];
const live = new Map();          // key -> DownloadItem (läuft gerade)
const pending = new Map();       // src -> key (wartet auf will-download)

const safe = k => String(k).replace(/[^A-Za-z0-9._-]/g, '_');
const file = k => path.join(dir, safe(k) + '.mp4');
const subFile = k => path.join(dir, safe(k) + '.de-forced.vtt');
const epSlug = (id, s, e) => id + 'S' + String(s).padStart(2, '0') + 'E' + String(e).padStart(2, '0');
const keyOf = o => o.type === 's' ? epSlug(o.id, o.season || 1, o.ep || 1) : o.id;

function save() { try { fs.writeFileSync(metaFile, JSON.stringify(items)); } catch (_) {} }
function load() { try { items = JSON.parse(fs.readFileSync(metaFile, 'utf8')); } catch (_) { items = []; } }
function publicList() {
  return items.map(d => ({ ...d, play: undefined, file: d.state === 'done' ? 'file://' + file(d.key).replace(/\\/g, '/') : '' }));
}
function notify() { const l = publicList(); BrowserWindow.getAllWindows().forEach(w => w.webContents.send('dl:changed', l)); }
let lastNotify = 0;
function notifySoon() { const n = Date.now(); if (n - lastNotify > 500) { lastNotify = n; notify(); } }
const upd = (k, f) => { const d = items.find(x => x.key === k); if (d) { f(d); } };

async function start(o) {
  const k = keyOf(o);
  const old = items.find(x => x.key === k);
  if (old && old.state !== 'failed') return { ok: true };
  const r = await net.fetch(API + '&type=' + o.type + '&id=' + encodeURIComponent(o.id) + (o.type === 's' ? '&season=' + (o.season || 1) + '&ep=' + (o.ep || 1) : ''),
    { session: session.defaultSession });
  const p = await r.json().catch(() => ({}));
  if (!p.ok || !p.src) return { ok: false, error: p.error || 'Nicht verfügbar' };
  remove(k);
  items.push({ key: k, type: o.type, id: o.id, season: p.season || o.season || null, ep: p.ep || o.ep || null,
    title: p.title, sub: p.sub || '', poster: p.poster || '', src: p.src, vtt: p.vtt || '', play: p,
    added: Date.now(), bytes: 0, done: 0, state: 'queued' });
  save(); notify();
  pending.set(p.src, k);
  session.defaultSession.downloadURL(p.src);
  if (p.vtt) net.fetch(p.vtt).then(x => x.ok ? x.arrayBuffer() : null).then(b => { if (b) fs.writeFileSync(subFile(k), Buffer.from(b)); }).catch(() => {});
  return { ok: true };
}

function remove(k) {
  const it = live.get(k); if (it) { try { it.cancel(); } catch (_) {} live.delete(k); }
  for (const f of [file(k), file(k) + '.part', subFile(k)]) { try { fs.unlinkSync(f); } catch (_) {} }
  items = items.filter(x => x.key !== k); save(); notify();
}

function init() {
  dir = path.join(app.getPath('userData'), 'Downloads');
  fs.mkdirSync(dir, { recursive: true });
  metaFile = path.join(dir, 'downloads.json');
  load();
  // Nach Neustart abgebrochene Downloads: Datei fertig? sonst als fehlgeschlagen (erneut versuchen)
  items.forEach(d => { if (d.state !== 'done') d.state = fs.existsSync(file(d.key)) ? 'done' : 'failed'; });
  save();

  session.defaultSession.on('will-download', (_e, item) => {
    const k = pending.get(item.getURL()) || [...pending.entries()].find(([u]) => item.getURLChain().includes(u))?.[1];
    if (!k) return;                       // normaler Browser-Download -> Standardverhalten
    pending.delete(item.getURL());
    item.setSavePath(file(k) + '.part');
    live.set(k, item);
    upd(k, d => { d.state = 'loading'; d.bytes = item.getTotalBytes(); });
    item.on('updated', (_ev, st) => {
      upd(k, d => { d.done = item.getReceivedBytes(); d.bytes = item.getTotalBytes() || d.bytes; d.state = st === 'interrupted' ? 'paused' : 'loading'; });
      notifySoon();
    });
    item.once('done', (_ev, st) => {
      live.delete(k);
      if (st === 'completed') {
        try { fs.renameSync(file(k) + '.part', file(k)); } catch (_) {}
        upd(k, d => { d.state = 'done'; d.done = d.bytes = fs.statSync(file(k)).size; });
      } else if (st !== 'cancelled') upd(k, d => { d.state = 'failed'; });
      save(); notify();
    });
  });

  ipcMain.handle('dl:start', (_e, o) => start(o).catch(err => ({ ok: false, error: String(err && err.message || err) })));
  ipcMain.handle('dl:remove', (_e, k) => { remove(k); return true; });
  ipcMain.handle('dl:list', () => publicList());
  ipcMain.handle('dl:info', () => ({ dir, used: items.reduce((a, d) => a + (d.state === 'done' ? d.bytes : d.done || 0), 0) }));
  ipcMain.handle('dl:folder', () => shell.openPath(dir));
  ipcMain.handle('dl:play', (_e, k) => {
    // Abspieldaten für downloads.html: lokale Datei, Untertitel, nächste heruntergeladene Folge
    const d = items.find(x => x.key === k); if (!d || d.state !== 'done') return null;
    const eps = items.filter(x => x.type === 's' && x.id === d.id && x.state === 'done').sort((a, b) => (a.season - b.season) || (a.ep - b.ep));
    const next = d.type === 's' ? eps.find(x => x.season > d.season || (x.season === d.season && x.ep > d.ep)) : null;
    return { ...d, play: undefined, src: 'file://' + file(k).replace(/\\/g, '/'),
      vtt: fs.existsSync(subFile(k)) ? 'file://' + subFile(k).replace(/\\/g, '/') : '', next: next ? next.key : null,
      intro: d.play && d.play.skip ? d.play.skip.intro || null : null };
  });
}

// Wird in filmfrei24.com eingespielt: Knöpfe „Herunterladen“ auf der Detailseite, je Folge, Menüpunkt „Downloads“.
const INJECT = String.raw`(() => {
  if (window.__ff24dl || !window.ff24desk) return; window.__ff24dl = 1;
  const SVG = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.5v11.5M7 10.5l5 5 5-5"/><path d="M4.5 19.5h15"/></svg>';
  const OK = '<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="#1a98ff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7.5"/></svg>';
  let L = [];
  const st = document.createElement('style');
  st.textContent = '.ffdl-ep{position:absolute;right:14px;top:50%;transform:translateY(-50%);width:44px;height:44px;border-radius:50%;display:grid;place-items:center;background:rgba(51,55,61,.85);color:#fff;border:0;cursor:pointer;z-index:3;font:700 12px Inter,sans-serif}.ffdl-ep:hover{background:rgba(255,255,255,.2)}.epc{position:relative}.epc .ffdl-ep~*{}.ffdl-pct{font:700 13px Inter,sans-serif}';
  document.head.appendChild(st);
  const find = k => L.find(d => d.key === k);
  const icon = d => !d || d.state === 'failed' ? SVG : d.state === 'done' ? OK : '<span class="ffdl-pct">' + (d.bytes ? Math.floor(d.done * 100 / d.bytes) : 0) + '%</span>';
  const label = d => !d ? 'Herunterladen' : d.state === 'done' ? 'Heruntergeladen – offline ansehen' : d.state === 'failed' ? 'Fehlgeschlagen – erneut versuchen' : 'Wird heruntergeladen';
  const epKey = (id, s, e) => id + 'S' + String(s).padStart(2, '0') + 'E' + String(e).padStart(2, '0');
  async function click(o, k) {
    const d = find(k);
    if (d && d.state === 'done') { if (confirm('„' + d.title + '“ ist heruntergeladen.\n\nOK = offline ansehen, Abbrechen = zurück')) ff24desk.open(k); return; }
    if (d && d.state !== 'failed') { if (confirm('Download von „' + d.title + '“ abbrechen?')) ff24desk.remove(k); return; }
    const r = await ff24desk.download(o);
    if (!r.ok) alert(r.error || 'Download nicht möglich');
  }
  function paint() {
    const m = location.hash.match(/^#\/titel\/([fs])\/([^?]+)/);
    // Menüpunkt
    const links = document.getElementById('links');
    if (links && !links.querySelector('[data-ffdl]')) {
      const a = document.createElement('a'); a.href = '#'; a.dataset.ffdl = 1; a.textContent = 'Downloads';
      a.onclick = e => { e.preventDefault(); ff24desk.open(''); }; links.appendChild(a);
    }
    if (!m) return;
    const t = m[1], id = decodeURIComponent(m[2]);
    if (t === 'f') {
      const ic = document.querySelector('.det .icons');
      if (ic) {
        let b = ic.querySelector('[data-ffdl]');
        if (!b) { b = document.createElement('button'); b.className = 'ico'; b.dataset.ffdl = 1; b.innerHTML = '<span class="rb o"></span><span>Herunterladen</span>';
          b.onclick = e => { e.stopPropagation(); click({ type: 'f', id }, id); }; ic.insertBefore(b, ic.children[1] || null); }
        const d = find(id); b.title = label(d); const n = icon(d); if (b.dataset.sig !== n) { b.dataset.sig = n; b.firstChild.innerHTML = n; }
      }
    } else {
      document.querySelectorAll('.epc[data-ep]').forEach(el => {
        const [s, e] = el.dataset.ep.split(':').map(Number), k = epKey(id, s, e);
        let b = el.querySelector('.ffdl-ep');
        if (!b) { b = document.createElement('button'); b.className = 'ffdl-ep';
          b.onclick = ev => { ev.stopPropagation(); click({ type: 's', id, season: s, ep: e }, k); }; el.appendChild(b); }
        const d = find(k); b.title = label(d); const n = icon(d); if (b.dataset.sig !== n) { b.dataset.sig = n; b.innerHTML = n; }
      });
    }
  }
  ff24desk.onChange(l => { L = l; paint(); });
  ff24desk.list().then(l => { L = l; paint(); });
  new MutationObserver(() => paint()).observe(document.getElementById('app') || document.body, { childList: true, subtree: true });
  addEventListener('hashchange', paint);
})();`;

module.exports = { init, INJECT };
