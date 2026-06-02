# CONTINUE.md — Contexto completo del proyecto

## Qué es este proyecto
Sistema completo de gestión de pedidos WhatsApp para **Concentrados Monserrath**
(empresa de alimento concentrado para cerdos, pollos, peces, gatos y perros).

Clientes escriben al WhatsApp del negocio → Bot IA detecta pedido automáticamente
→ Trabajadores gestionan desde app Android → PDF diario de entregas.

---

## Arquitectura del sistema

```
Windows 10 (servidor + bot unificado)
├── server/          → API REST Express + SQLite + Ollama LLM + wwebjs bot
├── android-app/     → App Flutter (Android + Web preview)
└── start-windows.ps1 → Arrancar todo

App Android (múltiples dispositivos)
└── Conecta a servidor via ngrok URL fija
```

---

## Credenciales y configuración

| Variable | Valor |
|---|---|
| ngrok authtoken | `34G7biMjp4tdGcupxvySfJvYqrQ_6BEU8VntbCjSudDRWntdB` |
| ngrok dominio | `francoise-subhumid-maire.ngrok-free.dev` |
| API Key server | `80721f27d4b9e6b1250ccf94f5356f1d9368993ffd0e51d1d9470754e85b9171` |
| JWT Secret | `a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2` |
| Worker PIN | `1234` |
| Ollama model | `llama3.2:1b` |
| Server port | `3000` |
| BOT_PROVIDER | `wwebjs` |

---

## Usuarios del sistema

| Usuario | Rol | PIN |
|---|---|---|
| jesus | admin | 1234 |
| johana | worker | 1234 |
| felipe | worker | 1234 |
| fabian | worker | 1234 |

Jesús puede crear/editar usuarios desde la app (admin panel).

---

## Stack tecnológico ACTUALIZADO

| Capa | Tecnología |
|---|---|
| Backend | Node.js 20 + Express + better-sqlite3 WAL |
| LLM | Ollama + llama3.2:1b (parser híbrido + fuzzy match) |
| WhatsApp bot | whatsapp-web.js (Puppeteer, LocalAuth, QR) |
| Tunnel | ngrok v3 (dominio fijo) |
| App móvil | Flutter 3.44 + Dart |
| Push | OneSignal |
| Runtime dev | Windows 10 LTSC x64 |
| Runtime prod | Cross-platform (Windows + Linux) |

---

## Plan de fases (ESTADO: iniciando)

### ✅ Fase 0 — DB Schema Migration
- Nuevas columnas: `order_items`, `claimed_by`, `cancel_reason`, `pin`, `display_name`
- Migrations en `database.js` (no rompe DB existente)
- Role admin para jesus

### ⏳ Fase 1 — User Management API
- Admin CRUD de usuarios (`/api/users`)
- Login por PIN (además de username/password)
- `adminAuth` middleware

### ⏳ Fase 2 — Order Lifecycle
- Estados: pending→claimed→en_camino→entregado|cancelled
- Endpoints: claim, unclaim, en_camino, cancel
- Multi-product orders con `order_items`

### ⏳ Fase 3 — Bot Migration wwebjs
- Reemplazar Baileys con whatsapp-web.js
- `server/src/services/waBot.js` + `messageProcessor.js`
- QR auth, LocalAuth, reconexión resiliente
- BOT_PROVIDER env flag

### ⏳ Fase 4 — Bot Intelligence
- Fuzzy product matching (errores ortografía)
- Multi-product extraction
- Confirmación con cliente si ambiguo

### ⏳ Fase 5 — Flutter: Roles + Order Lifecycle
- Admin panel (solo Jesús)
- Claim/unclaim UI
- "En camino por Felipe" visible a todos
- Llamar cliente, cancelar con motivo
- URL dinámica en SharedPreferences

### ⏳ Fase 6 — Flutter: Offline + Push
- Offline write queue (todas las acciones)
- sqflite para cache robusto
- OneSignal push + in-app sound/vibration

### ⏳ Fase 7 — UI Polish + Animaciones
- AnimatedList, AnimatedContainer
- SSE para chat en tiempo real
- Status badges animados

### ⏳ Fase 8 — Scripts cross-platform
- start-windows.ps1 completo
- stop-windows.ps1
- healthcheck.js

---

## Rutas API (actual + planeado)

| Ruta | Método | Auth | Descripción |
|---|---|---|---|
| `/health` | GET | - | Estado servidor |
| `/api/auth/token` | POST | PIN/pass | Login → JWT |
| `/api/users` | GET/POST/PUT | JWT+admin | CRUD usuarios |
| `/api/products` | GET/POST/PUT/DELETE | JWT | CRUD productos |
| `/api/orders` | GET | JWT | Pedidos activos |
| `/api/orders/:id/claim` | PUT | JWT | Reclamar pedido |
| `/api/orders/:id/unclaim` | PUT | JWT | Liberar pedido |
| `/api/orders/:id/en_camino` | PUT | JWT | Marcar en camino |
| `/api/orders/:id/deliver` | PUT | JWT | Marcar entregado |
| `/api/orders/:id/cancel` | PUT | JWT+admin | Cancelar con motivo |
| `/api/bot/status` | GET | JWT+admin | Estado bot WA |
| `/api/bot/qr` | GET | JWT+admin | QR para escanear |
| `/api/webhook/message` | POST | API Key | Bot → servidor |
| `/api/messages` | GET | JWT | Conversaciones |
| `/api/messages/:phone` | GET | JWT | Chat cliente |
| `/api/messages/send` | POST | JWT | Enviar mensaje WA |

---

## Decisiones arquitectónicas

### Por qué whatsapp-web.js (no Baileys)
- Usa Chrome oficial → más estable a largo plazo
- QR auth más confiable que pairing code
- Mejor manejo de reconexión
- Tradeoff: 400-600MB RAM para Chromium

### Por qué bot unificado (no VPS separado)
- Elimina latencia de polling HTTP
- Elimina punto de falla del VPS separado
- Bot llama funciones directamente (no HTTP)
- BOT_PROVIDER=none → fallback a webhook HTTP si se necesita

### Por qué better-sqlite3 (no async DB)
- Suficiente para volumen de pedidos de tienda pequeña
- WAL mode maneja concurrencia básica
- "Async" = patrones async en rutas Express, no reemplazar el driver

---

## Comandos útiles Windows

```powershell
# Arrancar sistema completo
.\start-windows.ps1

# Node con PATH correcto
$env:PATH = "$env:USERPROFILE\scoop\shims;$env:USERPROFILE\scoop\apps\nodejs20\current;$env:PATH"

# Ver estado bot
curl http://localhost:3000/api/bot/status -H "Authorization: Bearer $TOKEN"

# Instalar wwebjs
cd server && npm install whatsapp-web.js qrcode-terminal
```
