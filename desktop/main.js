// FilmFrei24 für Windows/Linux (2026-10-20): eigenes Programmfenster mit filmfrei24.com,
// Google-Login + Bezahlseiten im normalen Browser (Rücksprung per filmfrei24://login?code=...),
// Update-Hinweis aus tv.filmfrei24.com/app-version.json ("desktop").
const { app, BrowserWindow, shell, dialog, session, net, Menu, ipcMain } = require('electron');
const path = require('path');
const VERSION_BUILD = 3;                 // bei jeder neuen Version hochzählen (app-version.json desktop.build)
const HOME = 'https://filmfrei24.com/';
const DL = require('./downloads');   // 2026-10-22: Offline-Downloads
let win = null;

// H.265/HEVC über die Grafikkarte erlauben (die meisten Filme sind HEVC)
app.commandLine.appendSwitch('enable-features', 'PlatformHEVCDecoderSupport,PlatformHEVCEncoderSupport');

if (!app.requestSingleInstanceLock()) { app.quit(); }
app.setAsDefaultProtocolClient('filmfrei24');

function isInternal(u) {
  try { const h = new URL(u).hostname; return h === 'filmfrei24.com' || h.endsWith('.filmfrei24.com'); } catch { return false; }
}
// Im Browser öffnen: Google-Login, Stripe, alles Fremde
function needsBrowser(u) {
  return !isInternal(u) || /\/api\/app\.php\?action=google_start|accounts\.google\.com|checkout\.stripe\.com/.test(u);
}

function createWindow() {
  win = new BrowserWindow({
    width: 1400, height: 860, minWidth: 900, minHeight: 560, backgroundColor: '#00050d', title: 'FilmFrei24',
    icon: path.join(__dirname, 'icon.png'), autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
  });
  Menu.setApplicationMenu(null);
  win.webContents.setUserAgent(win.webContents.getUserAgent() + ' FF24Desktop/' + app.getVersion());
  win.loadURL(HOME);
  // Scrollbalken ausblenden (wirkt wie eine App, Scrollen per Mausrad/Tasten bleibt)
  win.webContents.on('did-finish-load', () => {
    win.webContents.insertCSS('html::-webkit-scrollbar,body::-webkit-scrollbar{width:0!important;height:0!important}');
    if (isInternal(win.webContents.getURL())) win.webContents.executeJavaScript(DL.INJECT).catch(() => {});
  });
  // Ohne Internet: direkt die heruntergeladenen Videos zeigen
  win.webContents.on('did-fail-load', (_e, code, _d, url, isMain) => {
    if (isMain && code <= -100 && code > -200 && isInternal(url)) win.loadFile(path.join(__dirname, 'downloads.html'), { query: { offline: '1' } });
  });
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (needsBrowser(url)) { shell.openExternal(url); return { action: 'deny' }; }
    win.loadURL(url); return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (e, url) => {
    // Google-Anmeldung: in der App über den Browser mit Rücksprung (Google sperrt Logins in Programmfenstern)
    if (/accounts\.google\.com|\/auth\/social_login\.php|oauth/.test(url) && !/action=google_done/.test(url)) {
      e.preventDefault(); shell.openExternal('https://filmfrei24.com/api/app.php?action=google_start&desktop=1'); return;
    }
    if (needsBrowser(url)) { e.preventDefault(); shell.openExternal(url); }
  });
  // F11 = Vollbild, Esc verlässt es
  win.webContents.on('before-input-event', (e, i) => {
    if (i.type !== 'keyDown') return;
    if (i.key === 'F11') { win.setFullScreen(!win.isFullScreen()); e.preventDefault(); }
    if (i.key === 'Escape' && win.isFullScreen()) win.setFullScreen(false);
    if (i.key === 'F5') win.webContents.reload();
  });
}

// filmfrei24://login?code=... -> Code einlösen (setzt die Anmelde-Cookies im App-Fenster)
async function handleDeepLink(u) {
  try {
    const url = new URL(u);
    if (url.host !== 'login') return;
    const code = url.searchParams.get('code');
    if (!code) return;
    const r = await net.fetch('https://filmfrei24.com/api/app.php?action=redeem', {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'X-FF24-App': '1' }, body: JSON.stringify({ code }),
      session: session.defaultSession,
    });
    const d = await r.json().catch(() => ({}));
    if (win) { if (win.isMinimized()) win.restore(); win.focus(); win.loadURL(HOME); }
    if (!d.ok) dialog.showMessageBox(win, { type: 'warning', message: 'Anmeldung abgelaufen. Bitte erneut versuchen.' });
  } catch (e) { /* ignorieren */ }
}

async function checkUpdate() {
  try {
    const r = await net.fetch('https://tv.filmfrei24.com/app-version.json', { cache: 'no-store' });
    const d = (await r.json()).desktop;
    if (!d || !(d.build > VERSION_BUILD)) return;
    const res = await dialog.showMessageBox(win, {
      type: 'info', buttons: ['Update', 'Weiter nutzen'], defaultId: 0, cancelId: 1, title: 'Neue Version verfügbar',
      message: 'FilmFrei24 ' + (d.name || '') + ' ist da.',
      detail: '„Update“ lädt das neue Setup herunter – einfach ausführen, deine Anmeldung bleibt erhalten.',
    });
    if (res.response === 0) shell.openExternal(d.url || 'https://tv.filmfrei24.com/exe');
  } catch (e) { /* offline */ }
}

app.on('second-instance', (_e, argv) => {
  const link = argv.find(a => a.startsWith('filmfrei24://'));
  if (link) handleDeepLink(link);
  else if (win) { if (win.isMinimized()) win.restore(); win.focus(); }
});
app.on('open-url', (e, u) => { e.preventDefault(); handleDeepLink(u); });   // macOS
ipcMain.handle('dl:open', (_e, k) => win && win.loadFile(path.join(__dirname, 'downloads.html'), { hash: k || '' }));
ipcMain.handle('dl:home', () => win && win.loadURL(HOME));
app.whenReady().then(() => {
  DL.init();
  createWindow();
  const link = process.argv.find(a => a.startsWith('filmfrei24://'));
  if (link) handleDeepLink(link);
  setTimeout(checkUpdate, 4000);
});
app.on('window-all-closed', () => app.quit());
