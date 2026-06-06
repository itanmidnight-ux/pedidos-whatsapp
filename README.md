# Concentrados Monserrath — Sistema de Pedidos WhatsApp

Sistema integral de gestión de pedidos recibidos por WhatsApp para **Concentrados Monserrath**, empresa distribuidora de concentrados y alimentos para animales. Incluye bot de WhatsApp con procesamiento de lenguaje natural, servidor REST y aplicación Android nativa.

---

## Tabla de Contenidos

- [Descripción General](#descripción-general)
- [Stack Tecnológico](#stack-tecnológico)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Funcionalidades](#funcionalidades)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Versiones](#versiones)

---

## Descripción General

Los clientes envían pedidos por WhatsApp en lenguaje natural colombiano. El bot los interpreta automáticamente usando NLP, los registra en base de datos y notifica al equipo de ventas a través de la aplicación Android. El equipo puede responder, enviar imágenes, audios y gestionar conversaciones directamente desde la app.

```
Cliente WhatsApp ──► Bot (Baileys) ──► Servidor Express ──► App Android
                                              │
                                        SQLite (WAL)
```

---

## Stack Tecnológico

| Capa | Tecnología |
|------|-----------|
| Bot WhatsApp | @whiskeysockets/baileys v6 |
| NLP | @nlpjs/basic — intención + entidades |
| Servidor | Node.js 20 + Express 4 |
| Base de datos | better-sqlite3 (WAL mode) |
| Tunnel | ngrok dominio fijo |
| App Android | Flutter 3.44 (arm64) |
| Estado app | Provider |
| Auth | JWT + roles (admin / empleado) |

---

## Estructura del Proyecto

```
pedidos-whatsapp/
├── server/                    # Backend Node.js
│   └── src/
│       ├── index.js           # Entry point Express
│       ├── db/database.js     # SQLite + migraciones
│       ├── routes/
│       │   ├── auth.js        # Login / JWT
│       │   ├── messages.js    # Conversaciones + media
│       │   ├── products.js    # Catálogo (admin)
│       │   └── webhook.js     # Recibe eventos del bot
│       └── services/
│           └── waBot.js       # Bot Baileys + NLP
├── android-app/               # Flutter App
│   └── lib/
│       ├── models/            # Message, Conversation, Product
│       ├── screens/
│       │   ├── login_screen.dart
│       │   ├── home_screen.dart
│       │   ├── messages_screen.dart   # Lista conversaciones
│       │   ├── chat_screen.dart       # Chat individual
│       │   └── products_screen.dart   # Catálogo
│       └── services/
│           └── api_service.dart       # Cliente HTTP
├── compilar-apk.ps1           # Script compilación Windows
└── start-all.sh               # Arranque completo Linux/macOS
```

---

## Funcionalidades

### Bot WhatsApp
- Interpreta pedidos en español colombiano natural ("quiero 2 bultos de maíz")
- Detección de intenciones: pedido, consulta de precio, reclamo, fiado
- Descarga y almacena mensajes de voz e imágenes recibidas
- Envía media (audio/imagen) a clientes desde la app
- Obtiene foto de perfil del contacto de WhatsApp
- Lógica anti-ban integrada

### App Android
- **Pantalla de mensajes** estilo WhatsApp
  - Tabs: Chats activos / Archivadas
  - Badges de mensajes no leídos
  - Fotos de perfil desde WhatsApp
  - Deslizar para archivar (con Deshacer) o borrar
  - Alertas visuales para reclamos y fiados bloqueados
- **Chat individual**
  - Reproducción de audios recibidos
  - Grabación y envío de audios
  - Envío de imágenes desde galería
  - Vista de imágenes en pantalla completa
  - Botón de llamada directa al cliente
  - Actualización en tiempo real (polling 2s)
  - Marcado automático como leído
- **Catálogo de productos**
  - Solo administradores pueden crear, editar y eliminar
  - Todos los usuarios pueden consultar
- **Roles de usuario**: admin / empleado

### Servidor
- API REST con autenticación JWT
- Gestión de conversaciones, media, pedidos y productos
- Archivo de conversaciones
- Migraciones automáticas de base de datos
- Rate limiting y headers de seguridad

---

## Requisitos

- Node.js 20+
- Java 17+ (para compilar APK)
- Flutter 3.44+ (para compilar APK)
- Android SDK (para compilar APK)
- ngrok (tunnel WhatsApp webhook)
- Windows 10+ o Linux/macOS

---

## Instalación

### Servidor

```bash
cd server
npm install
cp .env.example .env   # completar variables de entorno
npm start
```

### Compilar APK (Windows)

```powershell
.\compilar-apk.ps1
```

El script verifica e instala automáticamente Java 17, Flutter y Android SDK si no están presentes. El APK resultante queda en la raíz del proyecto.

### Arranque completo (Linux/macOS)

```bash
chmod +x start-all.sh
./start-all.sh
```

---

## Uso

1. Ejecutar servidor (`npm start` en `server/`)
2. Iniciar ngrok y configurar webhook URL en `.env`
3. Escanear QR en consola con el WhatsApp del negocio
4. Instalar APK en dispositivo Android del equipo
5. Iniciar sesión con credenciales de empleado o admin

---

## Versiones

| Versión | Descripción |
|---------|-------------|
| v1.1.0 | WhatsApp-clone UI, audio, imágenes, llamadas, fotos de perfil, productos solo admin |
| v1.0.0 | Bot NLP, gestión de pedidos, app base |
