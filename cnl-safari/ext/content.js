// FF24 Click'n'Load – Inhaltsskript, Safari/iOS-Fassung (2026-11-06).
// Safari kennt die Firefox-Spezialfunktionen (wrappedJSObject/exportFunction) nicht. Darum:
//  * filecrypt-Helper-Fenster: die Containerseite schickt die Links per postMessage (JDData) – das Inhaltsskript
//    liest diese Nachricht direkt mit und gibt sie an JDownloader auf dem FilmFrei24-Server weiter.
//  * Formulare an 127.0.0.1:9666 werden beim Absenden abgefangen.
//  * hide.cx: fetch() an 127.0.0.1:9666 wird im Seitenkontext (eingefuegtes Skript) abgefangen.
(function () {
  const RX = /^https?:\/\/(127\.0\.0\.1|localhost|cnl\.filecrypt\.cc):9666(\/|$)/i;
  function plog(m) { try { browser.runtime.sendMessage({ ff24log: m + ' [' + location.hostname + location.pathname + ']' }); } catch (e) {} }
  // 2026-11-06: Safari auf iOS gibt der Erweiterung oft keine Rechte fuer direct82.filmfrei24.com (nur fuer die
  // besuchte Seite) -> der Hintergrund-Abruf scheiterte still. Darum sendet das Inhaltsskript selbst (Server erlaubt
  // CORS fuer filecrypt/hide.cx); nur wenn das scheitert, geht es ueber das Hintergrundskript.
  const D = { server: 'https://direct82.filmfrei24.com/ff24-cnl', token: '0OtQrp2zQtTNRzSOJCjbHkDT7kiB_591Q-GY09OXNls' };
  const gesendet = {};
  function send(url, data) {
    let path = '/flash/addcrypted2';
    try { path = (new URL(url).pathname.replace(/\/+$/, '')) || path; } catch (e) {}
    const p = new URLSearchParams(); (data || []).forEach(function (kv) { p.append(kv[0], kv[1]); });
    if (!p.get('crypted') && !p.get('urls') && !p.get('jk')) return;
    if (!p.get('source')) p.set('source', location.href);
    const key = path + '|' + (p.get('crypted') || p.get('urls'));
    if (gesendet[key] && Date.now() - gesendet[key] < 60000) return;
    gesendet[key] = Date.now();
    const weiter = function () { try { browser.runtime.sendMessage({ ff24cnl: true, url: String(url), data: data }); } catch (e) {} };
    Promise.resolve(browser.storage && browser.storage.local ? browser.storage.local.get(['server', 'token']) : {}).catch(function () { return {}; }).then(function (c) {
      const server = (c && c.server) || D.server, token = (c && c.token) || D.token;
      return fetch(server + path, { method: 'POST', headers: { 'X-FF24-CNL': token, 'Content-Type': 'application/x-www-form-urlencoded' },
                                    body: p.toString(), credentials: 'omit', cache: 'no-store' });
    }).then(function (r) {
      if (!r.ok) throw new Error('Server ' + r.status);
      plog('OK ' + path + ' -> ' + r.status + ' (direkt)');
    }).catch(function (e) { plog('Direkt fehlgeschlagen (' + e + '), versuche Hintergrund'); weiter(); });
  }
  function formData(f) { const d = []; try { for (const el of f.elements) if (el.name && !el.disabled) d.push([String(el.name), String(el.value)]); } catch (e) {} return d; }

  document.addEventListener('submit', function (e) {
    const f = e.target;
    if (f && RX.test(f.action || '')) { e.preventDefault(); e.stopImmediatePropagation(); send(f.action, formData(f)); }
  }, true);

  if (/^\/helper\.html$/i.test(location.pathname)) {
    plog('Helper-Fenster geladen');
    let sent = false;
    window.addEventListener('message', function (e) {
      const jd = e.data;
      if (sent || !jd || typeof jd !== 'object' || !(jd.length >= 2) || !jd[1]) return;
      sent = true; plog('Links gefunden, sende an bw');
      send('http://127.0.0.1:9666/flash/addcrypted2', [
        ['jk', "function f(){ return '" + String(jd[0]) + "';}"], ['crypted', String(jd[1])],
        ['source', String(jd[3] || location.href)], ['passwords', '']]);
      const ok = function () { try { const t = document.getElementById('jdtransmitter'); if (t) { t.classList.remove('error'); t.classList.add('success'); } } catch (x) {} };
      ok(); setTimeout(ok, 1500); setTimeout(ok, 3500);
    }, true);
  }

  const FETCH_HOSTS = /(^|\.)hide\.cx$/i;
  if (FETCH_HOSTS.test(location.hostname)) {
    const tag = 'ff24cnl-' + Math.random().toString(36).slice(2);
    window.addEventListener('message', function (e) {
      if (!e.data || e.data.tag !== tag) return;
      send(String(e.data.url), Array.isArray(e.data.data) ? e.data.data.map(p => [String(p[0]), String(p[1])]) : []);
    }, false);
    const code = '(' + function (TAG) {
      var RX = /^https?:\/\/(127\.0\.0\.1|localhost):9666(\/|$)/i;
      function pairs(b) { try { if (!b) return []; if (typeof b === 'string') return Array.from(new URLSearchParams(b));
        if (b instanceof URLSearchParams) return Array.from(b); if (b instanceof FormData) { var o = []; b.forEach(function (v, k) { o.push([k, String(v)]); }); return o; }
        return Array.from(new URLSearchParams(String(b))); } catch (e) { return []; } }
      var of = window.fetch;
      window.fetch = function (input, init) {
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        if (RX.test(url)) { window.postMessage({ tag: TAG, url: url, data: pairs(init && init.body) }, '*'); return Promise.resolve(new Response('success', { status: 200 })); }
        return of.apply(this, arguments);
      };
    } + ')(' + JSON.stringify(tag) + ');';
    const inject = function () { try { const sc = document.createElement('script'); sc.textContent = code; (document.head || document.documentElement).appendChild(sc); sc.remove(); } catch (e) {} };
    if (document.documentElement) inject(); else document.addEventListener('readystatechange', inject, { once: true });
  }
})();
