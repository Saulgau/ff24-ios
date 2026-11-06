'use strict';
// FF24 Click'n'Load (Safari/iOS-Fassung, 2026-11-06): faengt Anfragen an den lokalen JDownloader (127.0.0.1:9666) ab und schickt sie
// per HTTPS mit Schluessel an JDownloader auf dem FilmFrei24-Server.
const DEFAULTS = { server: 'https://direct82.filmfrei24.com/ff24-cnl', token: '0OtQrp2zQtTNRzSOJCjbHkDT7kiB_591Q-GY09OXNls' };
const recent = new Map();   // gegen doppelte Uebertragung (gleiche Daten innerhalb 60 s)
// 1.0.6: kleines Protokoll (letzte 40 Ereignisse) fuer die Einstellungsseite
async function plog(msg) {
  try {
    const { ff24log = [] } = await browser.storage.local.get('ff24log');
    ff24log.unshift(new Date().toLocaleTimeString('de-DE') + '  ' + msg);
    await browser.storage.local.set({ ff24log: ff24log.slice(0, 40) });
  } catch (e) {}
}

async function cfg() { return Object.assign({}, DEFAULTS, await browser.storage.local.get(['server', 'token'])); }

function note(title, msg) {
  // Safari (iOS) kennt keine Erweiterungs-Benachrichtigungen -> nur Protokoll in den Einstellungen
  plog(title + ': ' + msg);
}

function bodyOf(details, url) {
  const p = new URLSearchParams();
  const rb = details.requestBody;
  if (rb && rb.formData) {
    for (const [k, vs] of Object.entries(rb.formData)) for (const v of vs) p.append(k, v);
  } else if (rb && rb.raw && rb.raw.length) {
    const dec = new TextDecoder();
    const raw = rb.raw.map(r => r.bytes ? dec.decode(r.bytes) : '').join('');
    for (const [k, v] of new URLSearchParams(raw)) p.append(k, v);
  }
  for (const [k, v] of url.searchParams) if (!p.has(k)) p.append(k, v);
  return p;
}

async function forward(path, params) {
  const key = path + '|' + (params.get('crypted') || params.get('urls') || params.toString());
  const now = Date.now();
  for (const [k, t] of recent) if (now - t > 60000) recent.delete(k);
  if (recent.has(key)) { plog('doppelt, nicht erneut gesendet (' + path + ')'); return; }
  recent.set(key, now);
  if (!params.get('source')) params.set('source', 'ff24-erweiterung');
  const c = await cfg();
  try {
    const r = await fetch(c.server + path, {
      method: 'POST',
      headers: { 'X-FF24-CNL': c.token, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params.toString(), credentials: 'omit', cache: 'no-store'
    });
    const t = (await r.text()).trim();
    plog((r.ok && !/failed/i.test(t) ? 'OK ' : 'FEHLER ') + path + ' -> ' + r.status + ' ' + t.slice(0, 60));
    if (r.ok && !/failed/i.test(t)) note('An JDownloader gesendet', 'Die Links sind jetzt im LinkGrabber auf dem bw.');
    else { recent.delete(key); note('Click\'n\'Load fehlgeschlagen', 'Server-Antwort ' + r.status + ': ' + t.slice(0, 120)); }
  } catch (e) {
    plog('FEHLER keine Verbindung: ' + e);
    recent.delete(key);
    note('Click\'n\'Load fehlgeschlagen', 'Keine Verbindung zum FilmFrei24-Server: ' + e);
  }
}

// Uebergaben aus dem Inhaltsskript (Normalfall: Firefox laesst Webseiten nicht mehr direkt an 127.0.0.1)
browser.runtime.onMessage.addListener(m => {
  if (m && m.ff24log) { plog(String(m.ff24log).slice(0, 200)); return; }
  if (!m || !m.ff24cnl) return;
  let path = '/flash/addcrypted2';
  try { path = (new URL(m.url).pathname.replace(/\/+$/, '')) || path; } catch (e) {}
  const params = new URLSearchParams();
  for (const [k, v] of (m.data || [])) params.append(k, v);
  if (!params.get('crypted') && !params.get('urls') && !params.get('jk')) return;
  forward(path, params);
});
