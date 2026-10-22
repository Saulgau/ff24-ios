// Die Website erkennt die PC-App (z. B. um Download-Hinweise auszublenden).
// 2026-10-22: ff24desk = Offline-Downloads (Hauptprozess downloads.js).
const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('ff24Desktop', { version: '1.1.0' });
contextBridge.exposeInMainWorld('ff24desk', {
  download: o => ipcRenderer.invoke('dl:start', o),
  remove: k => ipcRenderer.invoke('dl:remove', k),
  list: () => ipcRenderer.invoke('dl:list'),
  info: () => ipcRenderer.invoke('dl:info'),
  play: k => ipcRenderer.invoke('dl:play', k),
  folder: () => ipcRenderer.invoke('dl:folder'),
  open: k => ipcRenderer.invoke('dl:open', k || ''),
  home: () => ipcRenderer.invoke('dl:home'),
  onChange: cb => ipcRenderer.on('dl:changed', (_e, l) => cb(l)),
});
