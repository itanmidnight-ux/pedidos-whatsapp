# Concentrados Monserrath — Sistema de Pedidos WhatsApp

Sistema integral de gestión de pedidos recibidos por WhatsApp para **Concentrados Monserrath**, empresa distribuidora de concentrados y alimentos para animales. Bot de WhatsApp con procesamiento de lenguaje natural, servidor REST endurecido en seguridad, panel nativo de análisis para el administrador y aplicación Android/Web para admin, empleados y clientes.

---

## Tabla de Contenidos

- [Descripción General](#descripción-general)
- [Stack Tecnológico](#stack-tecnológico)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Funcionalidades](#funcionalidades)
- [Roles de Usuario](#roles-de-usuario)
- [Requisitos](#requisitos)
- [Despliegue del Servidor (Linux)](#despliegue-del-servidor-linux)
- [Panel de Análisis (dashboard.py)](#panel-de-análisis-dashboardpy)
- [Compilar la App Android](#compilar-la-app-android)
- [Seguridad](#seguridad)
- [Versiones](#versiones)

---

## Descripción General

Los clientes envían pedidos por WhatsApp en lenguaje natural colombiano. El bot los interpreta automáticamente usando NLP, los registra en base de datos y notifica al equipo de ventas a través de la app. El equipo (admin/empleados) responde, gestiona pedidos, catálogo, estados tipo "historias" y ve analíticas de ventas; los clientes finales tienen su propia vista para pedir y hacer seguimiento.

```
Cliente WhatsApp ──► Bot (Baileys, multi-device) ──► Servidor Express ──► App Flutter (admin/worker/client)
                                                            │
                                                      SQLite (WAL)
                                                            │
                                            dashboard.py (panel de análisis nativo)
```

---

## Stack Tecnológico

| Capa | Tecnología |
|------|-----------|
| Bot WhatsApp | @whiskeysockets/baileys (multi-device, sin navegador/Puppeteer) |
| NLP | @nlpjs/basic — intención + entidades |
| Servidor | Node.js 20 + Express 4 |
| Base de datos | better-sqlite3 (WAL mode) |
| Auth | JWT + bcrypt + roles (admin / worker / client) |
| Seguridad servidor | helmet, express-rate-limit, CORS allowlist, systemd hardening |
| PDF | pdfkit — reporte diario automático + exportación de rango bajo demanda (pedidos + chats) |
| App | Flutter 3.44 (Android + Web/PWA) |
| Estado app | Provider |
| Panel de análisis | Python 3 + GTK3 (dashboard.py) |
| Deploy Linux | Bash (deploy-linux.sh) — systemd, firewall, fail2ban, Tailscale Funnel (URL pública fija, sin abrir puertos) |

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
- Interpreta pedidos en español colombiano natural ("quiero 2 bultos de maíz")
- Detección de intenciones: pedido, consulta de precio, reclamo, fiado, cierre/agradecimiento
- Descarga y almacena mensajes de voz, imágenes, video y documentos recibidos
- Envío de media (audio/imagen/video/documento) a clientes desde la app, incluso desde el navegador
- Foto de perfil del contacto de WhatsApp
- Resuelve el número real del cliente aunque WhatsApp lo identifique por `@lid` (privacidad/multi-device), y fusiona automáticamente conversaciones duplicadas
- Filtra reenvíos de historial en reconexión — no repite respuestas ya enviadas

### App (Flutter — Android/Web)
- **Mensajería** estilo WhatsApp: chats activos/archivados, no leídos, audio, imágenes, video, documentos, llamada directa, y "Nuevo chat" a cualquier número colombiano sin conversación previa
- **Catálogo de productos**: gestión completa para admin, consulta para todos
- **Carrito y pedidos** para clientes finales
- **Estados** tipo "historias" (36h de vida) con reacciones y comentarios
- **Analíticas** (solo admin): ventas reales por día (gráfica visual), productos top, desempeño y hora de entrada de empleados, clientes
- **Personalización de marca**: paleta de colores y logo editables desde el rol admin, sin tocar código
- **Drawer** agrupado por rol, con tokens de diseño consistentes (Material 3), responsivo en PC/tablet/móvil

### Servidor
- API REST con JWT + bcrypt, rate limiting, headers de seguridad (helmet), CORS allowlist
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

El usuario admin por defecto es `jesus`, con contraseña inicial `jesus` (cambiarla tras el primer login). El resto de usuarios sembrados reciben contraseña aleatoria criptográfica.

---

## Requisitos

- Linux (Debian/Ubuntu/Kali — el deploy detecta `apt`/`dnf`/`pacman`)
- Node.js 20 (el deploy lo instala aislado en `/opt/nodejs`, sin tocar el Node del sistema)
- Python 3 + GTK3 (`python3-gi`) — solo si se quiere usar `dashboard.py`
- Flutter 3.44+ y Android SDK — solo para compilar el APK

---

## Despliegue del Servidor (Linux)

`deploy-linux.sh` instala, asegura y gestiona el servidor. Se auto-eleva con `sudo` — necesita root para crear el usuario de sistema aislado, systemd, firewall y fail2ban.

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

El servidor corre siempre como servicio systemd con un usuario de sistema dedicado (`pedidos-bot`, sin login, sin privilegios), `ProtectSystem=strict`, `NoNewPrivileges`, capacidades vacías y demás hardening — nunca como root.

### Acceso público

Por defecto el servidor solo escucha en `127.0.0.1`. Para exponerlo a internet sin necesidad de IP pública fija ni abrir puertos en el router, se usa **[Tailscale Funnel](https://tailscale.com/kb/1223/funnel)**: URL pública fija (`https://<máquina>.<tailnet>.ts.net`) de por vida, gratis en el plan Personal, con HTTPS automático. Alternativas soportadas por el instalador: túnel Cloudflare (URL temporal, sin cuenta) o dominio propio con nginx + Let's Encrypt (requiere abrir 80/443).

---

## Panel de Análisis (dashboard.py)

Herramienta de escritorio GTK3 **independiente** del deploy — el admin la abre cuando quiere, no se lanza automáticamente:

```bash
python3 dashboard.py
```

Pestañas: Monitoreo (estado del servicio, acceso público, gráficas de actividad), Pedidos activos, Bot WhatsApp (conexión, QR, pausa/reanuda), Ventas (ingresos reales por día en tarjetas, top productos, dona de estados), Empleados (desempeño, tiempo de entrega, hora de entrada por clic), Datos (exportar historial completo a PDF por rango de fechas, incluidos chats borrados; borrado múltiple de pedidos con selección), Marca, Configuración, Seguridad (auditoría en vivo) y Logs.

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
- Secretos (`API_KEY`, `JWT_SECRET`) generados con `openssl rand -hex 32`, regenerables desde el panel
- `.env` nunca se commitea (ver `.gitignore`); usar `server/.env.example` como plantilla
- Rate limiting y helmet en toda la API

---

## Versiones

| Versión | Descripción |
|---------|-------------|
| v2.1 | Migración a Baileys (bot sin navegador), resolución de números `@lid`, acceso público vía Tailscale Funnel (URL fija sin router), envío de media reparado en Web, gráficas reales de ventas, corrección de zona horaria en métricas, hora de entrada de empleados, pestaña Datos (exportar PDF + borrado múltiple), chats con soft-delete, app responsiva PC completa |
| v2.0 | Deploy Linux endurecido, panel GTK de análisis, roles admin/worker/client, estados, analíticas, marca personalizable |
| v1.1.0 | WhatsApp-clone UI, audio, imágenes, llamadas, fotos de perfil, productos solo admin |
| v1.0.0 | Bot NLP, gestión de pedidos, app base |
