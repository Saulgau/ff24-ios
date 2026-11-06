const D = { server: 'https://direct82.filmfrei24.com/ff24-cnl', token: '0OtQrp2zQtTNRzSOJCjbHkDT7kiB_591Q-GY09OXNls' };
const $ = id => document.getElementById(id);
browser.storage.local.get(['server', 'token']).then(c => { $('server').value = c.server || D.server; $('token').value = c.token || D.token; });
$('save').onclick = () => browser.storage.local.set({ server: $('server').value.trim(), token: $('token').value.trim() }).then(() => $('msg').textContent = 'Gespeichert');
$('test').onclick = async () => {
  $('msg').textContent = 'Teste...';
  try {
    const r = await fetch($('server').value.trim() + '/jdcheck.js', { headers: { 'X-FF24-CNL': $('token').value.trim() }, cache: 'no-store' });
    const t = await r.text();
    $('msg').textContent = r.ok && t.includes('jdownloader=true') ? 'OK: JDownloader auf dem bw erreichbar' : 'Fehler ' + r.status;
  } catch (e) { $('msg').textContent = 'Keine Verbindung: ' + e; }
};

// 1.0.6: Protokoll
const showLog = () => browser.storage.local.get('ff24log').then(c => { $('log').textContent = (c.ff24log || []).join('\n') || '– noch nichts –'; });
showLog(); setInterval(showLog, 2000);
$('clr').onclick = () => browser.storage.local.set({ ff24log: [] }).then(showLog);
