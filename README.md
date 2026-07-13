<div align="center">

# 📦 Plataforma de Pedidos por WhatsApp

**Convierte cualquier número de WhatsApp en un canal de ventas completo: bot con lenguaje natural, servidor endurecido en seguridad, panel de analíticas nativo y app multiplataforma para tu equipo y tus clientes.**

[![Node.js](https://img.shields.io/badge/Node.js-20_LTS-339933?logo=node.js&logoColor=white)](server/package.json)
[![Flutter](https://img.shields.io/badge/Flutter-3.44+-02569B?logo=flutter&logoColor=white)](android-app/pubspec.yaml)
[![Express](https://img.shields.io/badge/Express-4-000000?logo=express&logoColor=white)](server/package.json)
[![SQLite](https://img.shields.io/badge/SQLite-WAL_mode-003B57?logo=sqlite&logoColor=white)](server/src/db)
[![Security hardened](https://img.shields.io/badge/deploy-security_hardened-success)](deploy-linux.sh)
[![Platform](https://img.shields.io/badge/platform-Android_%7C_Web-informational)](android-app)

</div>

---

Pensada para equipos de ventas, distribución y atención al cliente que operan por WhatsApp — sin importar el rubro — y necesitan dejar de gestionar pedidos a mano en el chat. Los clientes piden en lenguaje natural, el bot interpreta la intención automáticamente, el equipo recibe y gestiona todo desde una app propia, y la gerencia obtiene analíticas reales de ventas sin depender de terceros.

Cualquier empresa con un flujo de "el cliente escribe, alguien anota el pedido en un cuaderno o en el chat" puede adoptar esta plataforma tal cual o como base para su propio catálogo, marca y reglas de negocio.

```
Cliente WhatsApp ──► Bot (Baileys, multi-device) ──► Servidor Express ──► App Flutter (admin/equipo/cliente)
                                                            │
                                                      SQLite (WAL)
                                                            │
                                              Panel de analíticas nativo (escritorio)
```

---

## Tabla de Contenidos

- [Por qué esta plataforma](#por-qué-esta-plataforma)
- [Stack Tecnológico](#stack-tecnológico)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Funcionalidades](#funcionalidades)
- [Roles de Usuario](#roles-de-usuario)
- [Requisitos](#requisitos)
- [Despliegue del Servidor (Linux)](#despliegue-del-servidor-linux)
- [Panel de Análisis](#panel-de-análisis)
- [Compilar la App Android](#compilar-la-app-android)
- [Seguridad](#seguridad)
- [Personalización de marca](#personalización-de-marca)
- [Versiones](#versiones)

---

## Por qué esta plataforma

- **Cero fricción para el cliente**: sigue escribiendo por WhatsApp como siempre, en su propio idioma natural — no instala nada, no aprende un menú de bot rígido.
- **Cero dependencia de terceros**: sin Puppeteer/Chrome headless, sin APIs de pago de WhatsApp Business, sin LLM externo pagado por token — el parser de intenciones corre local.
- **Propiedad total de los datos**: SQLite local, backups propios, sin enviar conversaciones de clientes a un proveedor externo de IA.
- **Marca propia sin tocar código**: logo, paleta de colores y nombre editables desde el rol admin.
- **Un solo despliegue instala todo**: servidor, firewall, hardening, acceso público seguro — sin ensamblar infraestructura a mano.

Actualmente en producción operando las ventas de **Concentrados Monserrath** (distribuidora de concentrados y alimentos para animales) como caso de referencia — la arquitectura de catálogo, roles y reglas de negocio está pensada para adaptarse a cualquier otro rubro de venta/distribución.

---

## Stack Tecnológico

| Capa | Tecnología |
|------|-----------|
| Bot WhatsApp | @whiskeysockets/baileys (multi-device, sin navegador/Puppeteer) |
| NLP | @nlpjs/basic — intención + entidades |
| Servidor | Node.js 20 + Express 4 |
| Base de datos | better-sqlite3 (WAL mode) |
| Auth | JWT + bcrypt + roles (admin / worker / client) |
| Seguridad servidor | helmet, express-rate-limit, CORS allowlist, systemd hardening, TLS 1.2/1.3 |
| Rendimiento | Compresión gzip de respuestas HTTP |
| PDF | pdfkit — reporte diario automático + exportación de rango bajo demanda (pedidos + chats) |
| App | Flutter 3.44 (Android + Web/PWA) |
| Estado app | Provider |
| Panel de análisis | Python 3 + GTK3 (dashboard.py) |
| Deploy Linux | Bash (deploy-linux.sh) — systemd, firewall, fail2ban, Tailscale Funnel / Cloudflare Tunnel / nginx+Let's Encrypt |

---

## Estructura del Proyecto

```
pedidos-whatsapp/
├── server/                        # Backend Node.js
│   └── src/
│       ├── index.js               # Entry point Express
│       ├── db/database.js         # SQLite + migraciones + seed de usuarios
│       ├── middleware/auth.js     # JWT + control de roles (admin/worker/client)
│       ├── routes/
│       │   ├── auth.js            # Login / JWT
│       │   ├── bot.js             # Control del bot WhatsApp
│       │   ├── cart.js            # Carrito de clientes
│       │   ├── chat.js            # Conversaciones + media
│       │   ├── estados.js         # "Historias" tipo WhatsApp (36h TTL)
│       │   ├── messages.js        # Mensajería interna (soft-delete: el texto nunca se pierde)
│       │   ├── orders.js          # Pedidos
│       │   ├── products.js        # Catálogo (admin)
│       │   ├── settings.js        # Tema/marca (colores, logo, nombre)
│       │   ├── users.js           # Gestión de usuarios
│       │   ├── analytics.js       # Ventas, productos, empleados, clientes
│       │   ├── reports.js         # Exportar rango de fechas a PDF (pedidos + chats)
│       │   └── webhook.js         # Eventos entrantes del bot
│       └── services/
│           ├── waBot.js           # Bot Baileys + NLP
│           ├── pdfGenerator.js    # Reporte diario + reporte por rango (PDF)
│           └── pdfScheduler.js    # Cron del reporte diario
├── android-app/                   # App Flutter (Android + Web)
│   └── lib/
│       ├── screens/               # admin_*, client_*, worker_*, login, chat, etc.
│       ├── theme/                 # Tokens + ThemeProvider (paleta personalizable)
│       └── services/api_service.dart
├── dashboard.py                   # Panel nativo GTK3 de análisis (standalone)
├── deploy-linux.sh                # Instala, asegura y gestiona el servidor en Linux
└── compilar-apk.sh                # Compila el APK release en Linux
```

---

## Funcionalidades

### Bot WhatsApp
- Interpreta pedidos en lenguaje natural ("quiero 2 bultos de maíz") — adaptable a cualquier catálogo de productos
- Detección de intenciones: pedido, consulta de precio, reclamo, fiado, cierre/agradecimiento
- Descarga y almacena mensajes de voz, imágenes, video y documentos recibidos
- Envío de media (audio/imagen/video/documento) a clientes desde la app, incluso desde el navegador
- Foto de perfil del contacto de WhatsApp
- Resuelve el número real del cliente aunque WhatsApp lo identifique por `@lid` (privacidad/multi-device), y fusiona automáticamente conversaciones duplicadas
- Filtra reenvíos de historial en reconexión — no repite respuestas ya enviadas

### App (Flutter — Android/Web)
- **Mensajería** estilo WhatsApp: chats activos/archivados, no leídos, audio, imágenes, video, documentos, llamada directa, y "Nuevo chat" a cualquier número sin conversación previa
- **Catálogo de productos**: gestión completa para admin, consulta para todos los roles
- **Carrito y pedidos** para clientes finales
- **Estados** tipo "historias" (36h de vida) con reacciones y comentarios
- **Analíticas** (solo admin): ventas reales por día (gráfica visual), productos top, desempeño y hora de entrada de empleados, clientes
- **Personalización de marca**: paleta de colores, nombre y logo editables desde el rol admin, sin tocar código — cualquier empresa puede aplicar su propia identidad
- **Drawer** agrupado por rol, con tokens de diseño consistentes (Material 3), responsivo en PC/tablet/móvil

### Servidor
- API REST con JWT + bcrypt, rate limiting, headers de seguridad (helmet), CORS allowlist
- Compresión gzip de respuestas HTTP (carga inicial de la app más rápida)
- Migraciones automáticas de base de datos
- Reporte PDF diario automático (pedidos + chats)
- Bind por defecto a `127.0.0.1` (nunca expuesto directo salvo que se configure explícitamente)

---

## Roles de Usuario

| Rol | Acceso |
|-----|--------|
| `admin` | Todo: catálogo, usuarios, analíticas, marca/tema, configuración del bot |
| `worker` | Mensajería, pedidos, estados — sin analíticas ni configuración |
| `client` | Catálogo, carrito, pedidos propios, estados del negocio |

Modelo de roles genérico: se adapta a cualquier estructura de equipo (dueño/vendedores/clientes, gerencia/repartidores/clientes, etc.) sin cambios de esquema.

---

## Requisitos

- Linux (Debian/Ubuntu/Kali — el deploy detecta `apt`/`dnf`/`pacman`)
- Node.js 20 (el deploy lo instala aislado en `/opt/nodejs`, sin tocar el Node del sistema)
- Python 3 + GTK3 (`python3-gi`) — solo si se quiere usar el panel de análisis
- Flutter 3.44+ y Android SDK — solo para compilar el APK

---

## Despliegue del Servidor (Linux)

`deploy-linux.sh` instala, asegura y gestiona el servidor de punta a punta. Se auto-eleva con `sudo` — necesita root para crear el usuario de sistema aislado, systemd, firewall y fail2ban. **La primera ejecución hace la instalación y configuración completa**; las siguientes solo verifican que el servicio esté arriba.

```bash
./deploy-linux.sh                # Instalación / despliegue completo (primera vez)
```

Comandos de control (no repiten el wizard de instalación):

| Comando | Acción |
|---------|--------|
| `./deploy-linux.sh --start` | Inicia el servidor (como servicio systemd aislado) |
| `./deploy-linux.sh --stop` | Detiene el servidor |
| `./deploy-linux.sh --localhost` | Cierra el acceso público (Tailscale Funnel/túnel/puertos, según cómo se instaló). El servidor sigue vivo, solo deja de ser alcanzable desde afuera |
| `./deploy-linux.sh --continue` | Reabre el acceso público |
| `./deploy-linux.sh --menu` | Panel de gestión en terminal (estado, logs, secretos, WhatsApp, etc.) |
| `./deploy-linux.sh --uninstall` | Detiene y elimina los servicios instalados (conserva datos) |
| `./deploy-linux.sh -h` / `--help` | Ayuda con todos los comandos y el estado actual de acceso público |

El servidor corre siempre como servicio systemd con un usuario de sistema dedicado, sin login, sin privilegios, `ProtectSystem=strict`, `NoNewPrivileges`, capacidades vacías y demás hardening — nunca como root.

### Acceso público

Por defecto el servidor solo escucha en `127.0.0.1`. El wizard de instalación ofrece cuatro métodos, elegible según la infraestructura de cada empresa:

| Método | Cuándo usarlo |
|--------|---------------|
| **Tailscale Funnel** | URL pública fija de por vida, gratis, HTTPS automático, sin abrir puertos ni IP fija |
| **Cloudflare Tunnel** | URL temporal, sin necesidad de cuenta, sin abrir puertos |
| **Dominio propio + nginx + Let's Encrypt** | Cuando ya se tiene un dominio; TLS 1.2/1.3 forzado con cifrados AEAD modernos |
| **Solo red local / VPN** | Uso interno, sin exposición a internet |

---

## Panel de Análisis

Herramienta de escritorio GTK3 **independiente** del deploy — se abre cuando se necesita, no se lanza automáticamente:

```bash
python3 dashboard.py
```

Pestañas: Monitoreo (estado del servicio, acceso público, gráficas de actividad), Pedidos activos, Bot WhatsApp (conexión, QR, pausa/reanuda), Ventas (ingresos reales por día en tarjetas, top productos, dona de estados), Empleados (desempeño, tiempo de entrega, hora de entrada por clic), Ubicaciones (mapa en vivo del equipo en campo), Datos (exportar historial completo a PDF por rango de fechas, incluidos chats borrados; borrado múltiple de pedidos con selección), Marca, Configuración, Seguridad (auditoría en vivo) y Logs.

---

## Compilar la App Android

```bash
chmod +x compilar-apk.sh
./compilar-apk.sh
```

Verifica/instala Java, Flutter y Android SDK si hacen falta (sin tocar el Java del sistema). El APK queda en la raíz del proyecto.

---

## Seguridad

- Servicio systemd aislado, sin root, con capacidades y superficie de ataque mínimas
- Firewall deny-by-default (ufw/firewalld/iptables, autodetectado): solo SSH + lo estrictamente necesario
- fail2ban contra fuerza bruta
- TLS 1.2/1.3 forzado con cifrados AEAD modernos en el path nginx+dominio propio; Tailscale Funnel y Cloudflare Tunnel terminan TLS moderno en su propio edge
- Secretos (`API_KEY`, `JWT_SECRET`) generados con `openssl rand -hex 32`, regenerables desde el panel
- `.env` nunca se commitea (ver `.gitignore`); usar `server/.env.example` como plantilla
- Rate limiting y helmet en toda la API
- Auditoría de seguridad en vivo disponible desde `deploy-linux.sh --menu` y desde el panel de análisis

---

## Personalización de marca

Cada empresa que adopte la plataforma puede definir su propia identidad sin tocar código, desde el rol admin:

- Nombre del negocio
- Logo
- Paleta de colores (aplicada en tiempo real a toda la app)

---

## Versiones

| Versión | Descripción |
|---------|-------------|
| v2.1 | Migración a Baileys (bot sin navegador), resolución de números `@lid`, acceso público vía Tailscale Funnel (URL fija sin router), envío de media reparado en Web, gráficas reales de ventas, corrección de zona horaria en métricas, hora de entrada de empleados, pestaña Datos (exportar PDF + borrado múltiple), chats con soft-delete, app responsiva PC completa, ubicaciones en tiempo real con mapa en vivo, compresión HTTP, TLS 1.2/1.3 forzado |
| v2.0 | Deploy Linux endurecido, panel GTK de análisis, roles admin/worker/client, estados, analíticas, marca personalizable |
| v1.1.0 | WhatsApp-clone UI, audio, imágenes, llamadas, fotos de perfil, productos solo admin |
| v1.0.0 | Bot NLP, gestión de pedidos, app base |
