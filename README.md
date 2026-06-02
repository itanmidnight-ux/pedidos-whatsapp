# Sistema de Pedidos WhatsApp

Bot VPS + App Android para gestión de pedidos vía WhatsApp.

## Stack

- **Backend**: Node.js 20 + Express + better-sqlite3 (WAL)
- **Bot**: whatsapp-web.js (Puppeteer)
- **LLM**: Ollama llama3.2:1b (parser híbrido + reglas fuzzy)
- **Tunnel**: ngrok dominio fijo
- **App**: Flutter 3.44 (Android + Web)
- **OS dev**: Windows 10 LTSC x64

## Estructura

```
.
├── backend/          # Express + better-sqlite3
├── bot/              # whatsapp-web.js bot
├── app/              # Flutter (Android + Web)
└── scripts/          # Deploy & utils
```

## Requisitos

- Node.js 20+
- Dart/Flutter 3.44+
- Ollama (llama3.2:1b)
- ngrok (dominio configurado)

## Setup Rápido

### Backend + Bot
```bash
cd backend
npm install
npm start
```

### App
```bash
cd app
flutter pub get
flutter run -d android
```

## Notas

- DB always async (better-sqlite3 WAL mode)
- Nombres de empleados desde DB, no hardcoded
- Sin error handling para casos imposibles
- Validar solo en boundaries (input usuario, APIs externas)

## Credenciales

Configurar en `.env`:
```
OLLAMA_URL=http://localhost:11434
NGROK_DOMAIN=tu-dominio.ngrok.io
NGROK_TOKEN=xxxxx
```
