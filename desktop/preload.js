// Die Website erkennt die PC-App (z. B. um Download-Hinweise auszublenden).
const { contextBridge } = require('electron');
contextBridge.exposeInMainWorld('ff24Desktop', { version: process.versions.electron ? '1.0.0' : '' });
