#!/usr/bin/env python3
# ================================================================================
#  dashboard.py — Panel nativo de escritorio GTK3 para Concentrados Monserrath
#  Versión 3.0 — Reescritura completa del panel de administración del servidor.
#
#  9 módulos: Monitoreo · Ventas · Pedidos Activos · Bot WhatsApp · Empleados
#             · Marca · Configuración · Seguridad · Logs
#
#  Arquitectura:
#   - Sidebar lateral colapsable + área principal responsive (1200x800 min 900x600)
#   - Estilo claro empresarial con acentos de marca (olivo/ámbar), crossfade
#     nativo al cambiar de módulo
#   - Gráficos Cairo dibujados a mano (barras, líneas, dona, sparklines)
#   - Acceso híbrido: SQLite directo (stats) + systemd (control servicio)
#                      + API HTTP (estado del bot WhatsApp, QR)
#
#  Se lanza desde deploy-linux.sh (--menu) o directamente: python3 dashboard.py
# ================================================================================
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, GdkPixbuf
import cairo
import subprocess, sqlite3, os, re, sys, datetime, secrets, json, base64, threading, math
import urllib.request, urllib.error

# ─── Configuración de rutas y servicios ─────────────────────────────────────────
SERVICE         = os.environ.get('DEPLOY_SERVICE', 'pedidos-bot')
PROJ            = os.environ.get('DEPLOY_PROJ', os.path.dirname(os.path.abspath(__file__)))
ENV_FILE        = os.path.join(PROJ, 'server', '.env')
LOG_DIR         = os.environ.get('DEPLOY_LOG_DIR', '/var/log/pedidos-bot')
# API_BASE se define después de env_get() más abajo

# ─── Paleta de marca (para el módulo Marca) ─────────────────────────────────────
PRIMARY_DEFAULT = '#2D5016'
ACCENT_DEFAULT  = '#D4800A'
PRESETS = [
    ('Olivo & Ambar',     '#2D5016', '#D4800A'),
    ('Bosque & Cuero',    '#1B4332', '#B08968'),
    ('Slate & Terracota', '#264653', '#E76F51'),
    ('Vino & Oro',        '#5C1A28', '#C9A227'),
    ('Azul Corporativo',  '#1B3A6B', '#3D8BFD'),
    ('Carbon & Lima',     '#22302B', '#8AB833'),
]

# ─── Paleta "admin console" — claro empresarial + acentos de marca ──────────────
# Fondo blanco/gris claro, texto casi-negro (no negro puro), acentos
# puntuales (verde olivo / ámbar) para highlights de marca sin romper
# contraste. WARNING se oscurece respecto al amarillo original -- como
# texto sobre blanco el amarillo puro es ilegible.
BG          = '#ffffff'   # window background
SURFACE     = '#ffffff'   # cards, contenido
SURFACE_2   = '#f4f5f6'   # sidebar, hover, elevated
SURFACE_3   = '#e9ebed'   # active, pressed
BORDER      = '#dde0e3'   # 1px borders — visible pero no duro
BORDER_SOFT = '#eef0f2'   # subtle dividers
FG          = '#1a1d21'   # primary text
FG_MUTED    = '#52585f'   # secondary text
FG_DIM      = '#8a9099'   # tertiary / labels
ACCENT      = '#1B3A6B'   # azul corporativo (acciones primarias)
BRAND       = '#D4800A'   # acento de marca (highlights, indicadores activos)
BRAND_DARK  = '#2D5016'   # primario de marca (presets, preview)
SUCCESS     = '#1e8e5a'   # estados activos / OK
WARNING     = '#b8860b'   # advertencias / acciones sensibles
DANGER      = '#c62828'   # errores / cancelados / crítico
INFO        = '#1B3A6B'   # info / charts secundarios

# ─── CSS (claro empresarial + acentos de marca) ─────────────────────────────────
# Esquinas 6-10px, padding generoso, transiciones 150-200ms, sombras suaves
# de elevación en cards (soportadas en GTK3 3.22+), jerarquía tipográfica clara.
CSS = f"""
/* Reset universal -- el tema del sistema (Kali-Dark) mete gradientes,
   sombras y text-shadow propios en botones/headerbar/entries que una
   simple background-color no tapa (background-image se dibuja ENCIMA
   del background-color). Sin este reset se ve un remanente oscuro
   detrás de cada widget aunque el color de fondo ya sea claro. Los
   pocos casos que sí quieren sombra/gradiente (stat-card, bot-frame,
   etc.) la redeclaran explícitamente más abajo y ganan por especificidad. */
* {{
    font-family: 'Cantarell', 'Inter', 'Fira Sans', 'Segoe UI', sans-serif;
    color: {FG};
    background-image: none;
    box-shadow: none;
    text-shadow: none;
}}
.mono {{ font-family: 'Fira Code', 'JetBrains Mono', 'DejaVu Sans Mono', monospace; }}

window, .background {{ background-color: {BG}; }}

/* ─── Header bar ─────────────────────────────────── */
headerbar {{
    background-color: {SURFACE};
    border-bottom: 1px solid {BORDER};
    box-shadow: none;
    padding: 4px 10px;
}}
headerbar:backdrop {{ background-color: {SURFACE}; }}
headerbar .title {{
    color: {FG};
    font-weight: 700;
    font-size: 14px;
    letter-spacing: 0.3px;
}}
headerbar .subtitle {{
    color: {FG_MUTED};
    font-size: 11px;
    font-weight: 400;
}}
headerbar button {{
    background: {SURFACE_2};
    border: 1px solid {BORDER};
    border-radius: 6px;
    color: {FG};
    padding: 5px 12px;
    font-weight: 500;
    transition: background 150ms ease, border-color 150ms ease;
}}
headerbar button:hover {{ background: {SURFACE_3}; border-color: {FG_DIM}; }}
headerbar button:active {{ background: {SURFACE_3}; }}

/* ─── Sidebar ────────────────────────────────────── */
.win-controls button {{
    background: {SURFACE_2};
    border: none;
    border-radius: 6px;
    min-width: 30px;
    min-height: 26px;
    padding: 0;
    color: {FG_MUTED};
    transition: background 120ms ease, color 120ms ease;
}}
.win-controls button:hover {{ background: {SURFACE_3}; color: {FG}; }}
.win-controls .win-close:hover {{ background: {DANGER}; color: white; }}

.sidebar {{
    background-color: {SURFACE_2};
    border-right: 1px solid {BORDER};
    padding: 8px 6px;
}}
.sidebar-btn {{
    background: transparent;
    border: 1px solid transparent;
    border-radius: 6px;
    color: {FG_MUTED};
    padding: 10px 12px;
    font-weight: 500;
    font-size: 15px;
    transition: background 150ms ease, color 150ms ease, border-color 150ms ease;
    outline: none;
}}
.sidebar-btn:hover {{ background: {SURFACE_3}; color: {FG}; }}
.sidebar-btn.active {{
    background: {SURFACE};
    color: {FG};
    border-color: {BORDER};
    box-shadow: inset 2px 0 0 {BRAND};
}}
.sidebar-btn .badge {{
    background: {BRAND};
    color: {FG};
    border-radius: 10px;
    padding: 1px 7px;
    font-size: 10px;
    font-weight: 700;
    min-width: 16px;
}}
.sidebar-section {{
    color: {FG_DIM};
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.2px;
    padding: 14px 12px 6px 12px;
}}
.sidebar-divider {{
    background: {BORDER};
    min-height: 1px;
    margin: 6px 8px;
}}

/* ─── Content area ───────────────────────────────── */
.content {{ background-color: {BG}; padding: 20px 22px; }}
.content-scrolled {{ background-color: {BG}; }}

/* ─── Section headers ────────────────────────────── */
.section-title {{
    color: {FG_MUTED};
    font-weight: 700;
    font-size: 11px;
    letter-spacing: 1.2px;
}}
.section-h {{
    color: {FG};
    font-weight: 700;
    font-size: 16px;
    letter-spacing: 0.2px;
}}

/* ─── Stat cards ─────────────────────────────────── */
.stat-card {{
    background-color: {SURFACE};
    border-radius: 10px;
    border: 1px solid {BORDER};
    padding: 14px 16px;
    box-shadow: 0 1px 2px rgba(20,25,32,0.06);
    transition: border-color 150ms ease, background-color 150ms ease, box-shadow 150ms ease;
}}
.stat-card:hover {{
    border-color: {FG_DIM};
    background-color: {SURFACE_2};
    box-shadow: 0 2px 8px rgba(20,25,32,0.09);
}}
.stat-label {{
    color: {FG_DIM};
    font-size: 11px;
    letter-spacing: 0.5px;
    font-weight: 600;
}}
.stat-value {{
    color: {FG};
    font-size: 24px;
    font-weight: 700;
    margin-top: 4px;
}}
.stat-sub {{
    color: {FG_MUTED};
    font-size: 11px;
    margin-top: 2px;
}}
.stat-trend-up   {{ color: {SUCCESS}; font-size: 11px; font-weight: 600; }}
.stat-trend-down {{ color: {DANGER};  font-size: 11px; font-weight: 600; }}
.day-bar-bg {{ background-color: {BORDER}; border-radius: 3px; }}
.day-bar-fg {{ background-color: {BRAND};  border-radius: 3px; }}

/* ─── Status pills / dots ────────────────────────── */
.status-pill {{
    border-radius: 999px;
    padding: 3px 10px;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.5px;
}}
.pill-success {{ background: rgba(30,142,90,0.14); color: {SUCCESS}; border: 1px solid rgba(30,142,90,0.35); }}
.pill-warning {{ background: rgba(184,134,11,0.14); color: {WARNING}; border: 1px solid rgba(184,134,11,0.35); }}
.pill-danger  {{ background: rgba(198,40,40,0.14); color: {DANGER};  border: 1px solid rgba(198,40,40,0.35); }}
.pill-muted   {{ background: {SURFACE_3};            color: {FG_MUTED}; border: 1px solid {BORDER}; }}
.pill-info    {{ background: rgba(27,58,107,0.12); color: {INFO};    border: 1px solid rgba(27,58,107,0.3); }}
.pill-brand   {{ background: rgba(212,128,10,0.14); color: {BRAND};   border: 1px solid rgba(212,128,10,0.35); }}

.status-dot {{ border-radius: 999px; min-width: 9px; min-height: 9px; }}
.dot-active   {{ background-color: {SUCCESS}; }}
.dot-inactive {{ background-color: {FG_DIM}; }}
.dot-failed   {{ background-color: {DANGER}; }}
.dot-warning  {{ background-color: {WARNING}; }}

/* ─── Buttons ────────────────────────────────────── */
button.action-btn {{
    border-radius: 6px;
    padding: 8px 16px;
    font-weight: 600;
    font-size: 12px;
    letter-spacing: 0.3px;
    transition: background 150ms ease, border-color 150ms ease, box-shadow 150ms ease;
    outline: none;
}}
button.action-btn:disabled {{
    opacity: 0.35;
}}
.btn-primary {{
    background-color: {ACCENT};
    color: #ffffff;
    border: 1px solid {ACCENT};
}}
.btn-primary:hover {{ background-color: #24487f; }}
.btn-primary:active {{ background-color: #142c50; }}
.btn-brand {{
    background-color: {BRAND};
    color: {FG};
    border: 1px solid {BRAND};
}}
.btn-brand:hover {{ background-color: #e8901f; }}
.btn-warn {{
    background-color: transparent;
    color: {WARNING};
    border: 1px solid {WARNING};
}}
.btn-warn:hover {{ background-color: rgba(184,134,11,0.10); }}
.btn-danger {{
    background-color: transparent;
    color: {DANGER};
    border: 1px solid {DANGER};
}}
.btn-danger:hover {{ background-color: rgba(198,40,40,0.10); }}
.btn-flat {{
    background-color: {SURFACE_2};
    color: {FG};
    border: 1px solid {BORDER};
}}
.btn-flat:hover {{ background-color: {SURFACE_3}; border-color: {FG_DIM}; }}
.btn-small {{ padding: 4px 10px; font-size: 11px; }}
.btn-icon  {{ padding: 6px 8px; min-width: 30px; }}

/* ─── Inputs ─────────────────────────────────────── */
entry {{
    background-color: {SURFACE};
    color: {FG};
    border-radius: 6px;
    border: 1px solid {BORDER};
    padding: 7px 10px;
    transition: border-color 150ms ease, box-shadow 150ms ease;
}}
entry:focus {{
    border-color: {ACCENT};
    box-shadow: 0 0 0 2px rgba(27,58,107,0.18);
}}
entry:disabled {{ color: {FG_DIM}; background: {SURFACE_2}; }}

label {{ color: {FG}; }}
.label-muted {{ color: {FG_MUTED}; font-size: 12px; }}
.label-dim    {{ color: {FG_DIM}; font-size: 11px; }}
.label-bold   {{ font-weight: 700; }}

/* ─── Treeview / lists ───────────────────────────── */
scrolledwindow, treeview {{
    background-color: {SURFACE};
    color: {FG};
}}
treeview header button {{
    background-color: {SURFACE_2};
    color: {FG_DIM};
    border: none;
    border-bottom: 1px solid {BORDER};
    font-size: 11px;
    font-weight: 700;
    padding: 9px 10px;
    letter-spacing: 0.4px;
}}
treeview row:nth-child(even) {{ background-color: {SURFACE}; }}
treeview row:nth-child(odd)  {{ background-color: {SURFACE_2}; }}
treeview row:selected {{ background-color: rgba(27,58,107,0.14); color: {FG}; }}

/* ─── Textview (logs, security) ──────────────────── */
textview {{ background-color: {SURFACE}; }}
textview text {{ background-color: {SURFACE}; color: {FG_MUTED}; }}
textview selection {{ background-color: rgba(27,58,107,0.22); }}

/* ─── Separator / divider ────────────────────────── */
separator {{ background-color: {BORDER}; min-height: 1px; }}
.divider-v {{ background-color: {BORDER}; min-width: 1px; }}

/* ─── Brand swatches ─────────────────────────────── */
.preset-swatch {{
    border-radius: 8px;
    border: 1px solid {BORDER};
    background-color: {SURFACE};
    padding: 8px;
    transition: border-color 150ms ease, transform 100ms ease;
}}
.preset-swatch:hover {{ border-color: {FG_DIM}; }}
.preset-selected {{ border: 2px solid {BRAND}; }}

/* ─── QR / preview frames ────────────────────────── */
.frame {{
    background-color: {SURFACE};
    border: 1px solid {BORDER};
    border-radius: 10px;
    padding: 14px;
    box-shadow: 0 1px 2px rgba(20,25,32,0.05);
}}

/* ─── Order card (Pedidos Activos) ───────────────── */
.order-card {{
    background-color: {SURFACE};
    border: 1px solid {BORDER};
    border-left: 3px solid {FG_DIM};
    border-radius: 8px;
    padding: 12px 14px;
    box-shadow: 0 1px 2px rgba(20,25,32,0.05);
    transition: border-color 150ms ease, box-shadow 150ms ease;
}}
.order-card:hover {{ border-color: {FG_DIM}; box-shadow: 0 2px 6px rgba(20,25,32,0.08); }}
.order-pending  {{ border-left-color: {WARNING}; }}
.order-claimed  {{ border-left-color: {INFO}; }}
.order-en_camino{{ border-left-color: {BRAND}; }}

/* ─── Bot status card ────────────────────────────── */
.bot-frame {{
    background: linear-gradient(180deg, {SURFACE} 0%, {SURFACE_2} 100%);
    border: 1px solid {BORDER};
    border-radius: 12px;
    padding: 18px;
    box-shadow: 0 1px 3px rgba(20,25,32,0.06);
}}

/* ─── Scrollbar slim ─────────────────────────────── */
scrollbar slider {{
    background-color: {SURFACE_3};
    border-radius: 999px;
    min-width: 8px;
    min-height: 8px;
}}
scrollbar {{ background-color: transparent; }}

/* ─── Empty state ────────────────────────────────── */
.empty-state {{
    color: {FG_DIM};
    font-size: 13px;
    font-style: italic;
    padding: 32px;
}}
"""

# ─── Helpers ────────────────────────────────────────────────────────────────────

def _resolve_api_base():
    """Resuelve la URL base del API: lee PORT del .env (si existe) → 3000 por defecto.
    Autocontenida para poder llamarse al inicio del módulo antes que env_get()."""
    port = os.environ.get('PORT') or '3000'
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'server', '.env')
    if os.path.exists(env_path):
        try:
            with open(env_path) as f:
                for line in f:
                    if line.startswith('PORT='):
                        port = line.strip().split('=', 1)[1] or port
                        break
        except Exception:
            pass
    return os.environ.get('DEPLOY_API_BASE', f'http://127.0.0.1:{port}')

API_BASE = _resolve_api_base()


def sh(cmd):
    """Ejecuta comando shell con timeout — devuelve stdout stripped o '' si falla."""
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=6).stdout.strip()
    except Exception:
        return ''


def load_conf(key):
    """Lee una clave de .deploy-config (preferencias del deploy, ej. ACCESS_METHOD)."""
    conf_path = os.path.join(PROJ, '.deploy-config')
    if not os.path.exists(conf_path):
        return ''
    try:
        with open(conf_path) as f:
            for line in f:
                if line.startswith(key + '='):
                    return line.strip().split('=', 1)[1]
    except Exception:
        pass
    return ''


def env_get(key):
    """Lee una clave del .env del servidor."""
    if not os.path.exists(ENV_FILE):
        return ''
    try:
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith(key + '='):
                    return line.strip().split('=', 1)[1]
    except Exception:
        pass
    return ''


def env_set(key, value):
    """Setea una clave en el .env (crea o reemplaza)."""
    lines = []
    found = False
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE) as f:
                lines = f.readlines()
        except Exception:
            lines = []
    for i, line in enumerate(lines):
        if line.startswith(key + '='):
            lines[i] = f'{key}={value}\n'
            found = True
            break
    if not found:
        lines.append(f'{key}={value}\n')
    try:
        with open(ENV_FILE, 'w') as f:
            f.writelines(lines)
    except Exception as e:
        print(f'[dashboard] env_set error: {e}', file=sys.stderr)


def db_path():
    p = env_get('DB_PATH')
    return p if p else os.path.join(PROJ, 'server', 'pedidos.db')


def read_location_history(user_id):
    """Historial de ubicaciones de un trabajador -- vive en JSON liviano
    junto a la DB (server/src/services/locationHistory.js), no en
    staff_locations (esa tabla solo guarda la posición ACTUAL). Devuelve
    lista de dicts mas reciente primero, o [] si no hay archivo/error."""
    path = os.path.join(os.path.dirname(db_path()), 'locations', f'{user_id}.json')
    try:
        with open(path, encoding='utf-8') as f:
            history = json.load(f)
        return list(reversed(history)) if isinstance(history, list) else []
    except Exception:
        return []


def query(sql, params=()):
    """Query SQLite read-only (mode=ro) — devuelve lista de tuplas o [] si falla."""
    p = db_path()
    if not os.path.exists(p):
        return []
    try:
        con = sqlite3.connect(f'file:{p}?mode=ro', uri=True, timeout=2)
        cur = con.execute(sql, params)
        rows = cur.fetchall()
        con.close()
        return rows
    except Exception:
        return []


def db_write(sql, params=()):
    """Escribe en SQLite con timeout — devuelve True/False."""
    p = db_path()
    if not os.path.exists(p):
        return False
    try:
        con = sqlite3.connect(p, timeout=3)
        con.execute(sql, params)
        con.commit()
        con.close()
        return True
    except Exception:
        return False


def setting_get(key, default=''):
    rows = query("SELECT value FROM settings WHERE key=?", (key,))
    return rows[0][0] if rows else default


def setting_set(key, value):
    return db_write(
        "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, datetime('now','localtime')) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
        (key, value))


def hex_to_rgb(h):
    """Convierte #RRGGBB a tupla (r,g,b) 0-1."""
    h = (h or '').lstrip('#')
    if len(h) != 6:
        return (0.2, 0.3, 0.1)
    try:
        return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except Exception:
        return (0.2, 0.3, 0.1)


# ─── Mapa estático en vivo (tiles OSM compuestos a mano) ────────────────────────
# Sin webkit2gtk instalado en el sistema, un WebView con Leaflet no es viable sin
# agregar una dependencia nueva al deploy. En cambio: se descargan los mismos
# tiles publicos que usa cualquier mapa web (proyeccion Web Mercator estandar,
# "slippy map"), se componen a mano con Cairo y se dibuja un pin por persona --
# mismo patron que ya usa _load_qr() (fetch de imagen + Gtk.Image).
_MAP_TILE_SIZE = 256
_MAP_TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
_MAP_TILE_CACHE = {}  # (z,x,y) -> bytes PNG, valido mientras corra el proceso


def _map_lonlat_to_pixel(lon, lat, zoom):
    """Proyeccion Web Mercator estandar -- lon/lat a pixel global en ese zoom."""
    n = 2 ** zoom
    x = (lon + 180.0) / 360.0 * n * _MAP_TILE_SIZE
    lat_rad = math.radians(max(min(lat, 85.05), -85.05))
    y = (1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * n * _MAP_TILE_SIZE
    return x, y


def _map_fetch_tile(z, x, y):
    key = (z, x, y)
    if key in _MAP_TILE_CACHE:
        return _MAP_TILE_CACHE[key]
    n = 2 ** z
    if not (0 <= x < n and 0 <= y < n):
        return None
    req = urllib.request.Request(
        _MAP_TILE_URL.format(z=z, x=x, y=y),
        headers={'User-Agent': 'MonserrathDashboard/1.0 (panel interno, uso propio)'})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = resp.read()
        _MAP_TILE_CACHE[key] = data
        return data
    except Exception:
        return None


def _map_draw_pin(cr, x, y):
    cr.set_source_rgb(*hex_to_rgb(BRAND))
    cr.arc(x, y, 7, 0, 2 * math.pi)
    cr.fill()
    cr.set_source_rgb(1, 1, 1)
    cr.set_line_width(2)
    cr.arc(x, y, 7, 0, 2 * math.pi)
    cr.stroke()


def render_static_map(points, width=640, height=220):
    """points: lista de (label, lat, lng). Devuelve un GdkPixbuf.Pixbuf con
    el mapa compuesto + un pin por punto, o None si no hay puntos."""
    if not points:
        return None

    lats = [p[1] for p in points]
    lngs = [p[2] for p in points]
    min_lat, max_lat = min(lats), max(lats)
    min_lng, max_lng = min(lngs), max(lngs)
    # Si todos los puntos coinciden (o hay uno solo), dar un margen fijo en
    # vez de una caja de ancho cero (que rompería el calculo de zoom).
    if max_lat - min_lat < 0.002:
        min_lat -= 0.01; max_lat += 0.01
    if max_lng - min_lng < 0.002:
        min_lng -= 0.01; max_lng += 0.01
    center_lat = (min_lat + max_lat) / 2
    center_lng = (min_lng + max_lng) / 2

    padding_px = 40  # margen visual para que los pines no queden pegados al borde
    zoom = 2
    for z in range(16, 1, -1):
        x1, y1 = _map_lonlat_to_pixel(min_lng, max_lat, z)
        x2, y2 = _map_lonlat_to_pixel(max_lng, min_lat, z)
        if (x2 - x1) <= (width - 2 * padding_px) and (y2 - y1) <= (height - 2 * padding_px):
            zoom = z
            break

    center_px, center_py = _map_lonlat_to_pixel(center_lng, center_lat, zoom)
    top_left_x = center_px - width / 2
    top_left_y = center_py - height / 2

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    cr = cairo.Context(surface)
    cr.set_source_rgb(0.93, 0.94, 0.95)  # fondo por si algun tile no carga
    cr.paint()

    first_tx, first_ty = int(top_left_x // _MAP_TILE_SIZE), int(top_left_y // _MAP_TILE_SIZE)
    last_tx  = int((top_left_x + width) // _MAP_TILE_SIZE)
    last_ty  = int((top_left_y + height) // _MAP_TILE_SIZE)

    for tx in range(first_tx, last_tx + 1):
        for ty in range(first_ty, last_ty + 1):
            data = _map_fetch_tile(zoom, tx, ty)
            if not data:
                continue
            try:
                loader = GdkPixbuf.PixbufLoader()
                loader.write(data)
                loader.close()
                pixbuf = loader.get_pixbuf()
            except Exception:
                continue
            if not pixbuf:
                continue
            Gdk.cairo_set_source_pixbuf(cr, pixbuf, tx * _MAP_TILE_SIZE - top_left_x, ty * _MAP_TILE_SIZE - top_left_y)
            cr.paint()

    for _label, lat, lng in points:
        px, py = _map_lonlat_to_pixel(lng, lat, zoom)
        _map_draw_pin(cr, px - top_left_x, py - top_left_y)

    surface.flush()
    return Gdk.pixbuf_get_from_surface(surface, 0, 0, width, height)


def http_get(path, timeout=4):
    """GET a la API HTTP del servidor (con API-Key). Devuelve dict o None."""
    url = API_BASE + path
    api_key = env_get('API_KEY')
    req = urllib.request.Request(url, headers={
        'X-API-Key': api_key,
        'Authorization': 'Bearer ' + _get_admin_token(),
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception:
        return None


def http_post(path, data, timeout=5):
    url = API_BASE + path
    api_key = env_get('API_KEY')
    body = json.dumps(data).encode('utf-8')
    req = urllib.request.Request(url, data=body, method='POST', headers={
        'X-API-Key': api_key,
        'Authorization': 'Bearer ' + _get_admin_token(),
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception:
        return None


def http_put(path, data, timeout=5):
    url = API_BASE + path
    api_key = env_get('API_KEY')
    body = json.dumps(data).encode('utf-8')
    req = urllib.request.Request(url, data=body, method='PUT', headers={
        'X-API-Key': api_key,
        'Authorization': 'Bearer ' + _get_admin_token(),
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception:
        return None


def http_delete(path, data=None, timeout=5):
    url = API_BASE + path
    api_key = env_get('API_KEY')
    body = json.dumps(data or {}).encode('utf-8')
    req = urllib.request.Request(url, data=body, method='DELETE', headers={
        'X-API-Key': api_key,
        'Authorization': 'Bearer ' + _get_admin_token(),
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode('utf-8'))
    except Exception:
        return None


def run_in_background(work_fn, on_done=None):
    """Ejecuta work_fn() (típicamente una llamada http_*) en un hilo aparte y
    entrega el resultado a on_done(resultado) en el hilo principal de GTK vía
    GLib.idle_add -- sin esto, cada refresh/click con red lenta o el servidor
    caído congela toda la ventana por el timeout completo (hasta 30s en
    exportes)."""
    def _worker():
        try:
            result = work_fn()
        except Exception:
            result = None
        if on_done:
            GLib.idle_add(lambda: (on_done(result), False)[1])
    threading.Thread(target=_worker, daemon=True).start()


# Cache del token admin (renovado cada 6h)
_ADMIN_TOKEN = {'value': '', 'expires': 0}


def _get_admin_token():
    """Obtiene (con cache) un JWT admin haciendo login con las credenciales del .env.
    El dashboard asume que existe un usuario admin 'jesus' o el configurado en
    DASHBOARD_ADMIN_USER / DASHBOARD_ADMIN_PASS del .env."""
    import time
    now = time.time()
    if _ADMIN_TOKEN['value'] and now < _ADMIN_TOKEN['expires']:
        return _ADMIN_TOKEN['value']
    user = env_get('DASHBOARD_ADMIN_USER') or 'jesus'
    pw   = env_get('DASHBOARD_ADMIN_PASS') or 'jesus'
    url  = API_BASE + '/api/auth/token'
    body = json.dumps({'username': user, 'password': pw}).encode('utf-8')
    req  = urllib.request.Request(url, data=body, method='POST', headers={
        'Content-Type': 'application/json'
    })
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            if 'token' in data:
                _ADMIN_TOKEN['value'] = data['token']
                _ADMIN_TOKEN['expires'] = now + 6 * 3600  # 6h cache
                return data['token']
    except Exception:
        pass
    return ''


def fmt_money(v):
    """Formatea número como moneda colombiana."""
    try:
        return f'${int(v or 0):,}'
    except Exception:
        return '$0'


def fmt_relative(iso_dt):
    """ISO datetime → texto relativo ('hace 5 min', 'hace 2 h', '—')."""
    if not iso_dt:
        return '—'
    try:
        # Acepta formatos 'YYYY-MM-DD HH:MM:SS' o ISO con T
        s = iso_dt.replace('T', ' ').split('.')[0]
        dt = datetime.datetime.strptime(s, '%Y-%m-%d %H:%M:%S')
    except Exception:
        try:
            dt = datetime.datetime.fromisoformat(iso_dt.replace('Z', ''))
        except Exception:
            return '—'
    delta = datetime.datetime.now() - dt
    secs = int(delta.total_seconds())
    if secs < 0:
        return '—'
    if secs < 60:
        return 'hace segundos'
    if secs < 3600:
        return f'hace {secs // 60} min'
    if secs < 86400:
        return f'hace {secs // 3600} h'
    if secs < 86400 * 30:
        return f'hace {secs // 86400} d'
    return dt.strftime('%d/%m/%Y')


def status_pill(text, kind='muted'):
    """Crea un Gtk.Box con clase status-pill + pill-<kind>."""
    box = Gtk.Box()
    box.get_style_context().add_class('status-pill')
    box.get_style_context().add_class(f'pill-{kind}')
    lbl = Gtk.Label(label=text)
    lbl.get_style_context().add_class('mono')
    box.pack_start(lbl, True, True, 0)
    return box


# ─── Chart (Cairo) — barras, líneas, dona, sparkline ────────────────────────────

class Chart(Gtk.DrawingArea):
    """Gráfico dibujado a mano con Cairo. Cero dependencias externas.
    Kinds: 'bar' | 'line' | 'donut' | 'sparkline'.
    data: lista de (label, value) para bar/line/sparkline, lista de (label, value, color_rgb) para donut.
    """
    def __init__(self, title='', kind='bar', color=None, height=180):
        super().__init__()
        self.title = title
        self.kind = kind
        self.color = color or hex_to_rgb(ACCENT)
        self.data = []
        self.set_size_request(220, height)
        self.connect('draw', self.on_draw)

    def set_data(self, data):
        self.data = data or []
        self.queue_draw()

    def on_draw(self, widget, cr):
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()
        surface_rgb  = hex_to_rgb(SURFACE)
        border_rgb   = hex_to_rgb(BORDER)
        muted_rgb    = hex_to_rgb(FG_MUTED)
        dim_rgb      = hex_to_rgb(FG_DIM)

        # Fondo redondeado (Adwaita card style)
        cr.set_source_rgb(*surface_rgb)
        self._round_rect(cr, 0, 0, w, h, 8)
        cr.fill()
        cr.set_source_rgb(*border_rgb)
        cr.set_line_width(1)
        self._round_rect(cr, 0.5, 0.5, w - 1, h - 1, 8)
        cr.stroke()

        # Título
        if self.title:
            cr.set_source_rgb(*muted_rgb)
            cr.select_font_face('Sans', 0, 1)
            cr.set_font_size(10)
            cr.move_to(14, 20)
            cr.show_text(self.title.upper())

        if self.kind == 'donut':
            return self._draw_donut(cr, w, h, muted_rgb, dim_rgb)
        if not self.data or not any(v for _, v in self.data):
            cr.set_source_rgba(*dim_rgb, 0.7)
            cr.select_font_face('Sans', 0, 0)
            cr.set_font_size(11)
            cr.move_to(14, h / 2)
            cr.show_text('Sin datos todavía')
            return
        if self.kind == 'bar':
            return self._draw_bars(cr, w, h, muted_rgb, dim_rgb, border_rgb)
        if self.kind == 'line':
            return self._draw_line(cr, w, h, muted_rgb, dim_rgb)
        if self.kind == 'sparkline':
            return self._draw_sparkline(cr, w, h)

    @staticmethod
    def _round_rect(cr, x, y, w, h, r):
        cr.move_to(x + r, y)
        cr.arc(x + w - r, y + r, r, -1.5708, 0)
        cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
        cr.arc(x + r, y + h - r, r, 1.5708, 3.14159)
        cr.arc(x + r, y + r, r, 3.14159, 4.71239)
        cr.close_path()

    def _draw_bars(self, cr, w, h, muted_rgb, dim_rgb, border_rgb):
        pad_left, pad_bottom, pad_top = 14, 26, 34
        chart_h = h - pad_bottom - pad_top
        chart_w = w - pad_left - 14
        maxval = max((v for _, v in self.data), default=1) or 1
        n = len(self.data) or 1
        bw = chart_w / n

        # Gridlines horizontales sutiles
        for frac in (0.25, 0.5, 0.75, 1.0):
            gy = pad_top + chart_h * (1 - frac)
            cr.set_source_rgba(*border_rgb, 0.5)
            cr.set_line_width(1)
            cr.move_to(pad_left, gy)
            cr.line_to(pad_left + chart_w, gy)
            cr.stroke()

        # Valor máximo arriba a la derecha -- se omite si una barra llega
        # casi al tope justo cerca del borde derecho (común cuando el día
        # con más actividad es el último del rango): su propia etiqueta
        # de valor terminaría superpuesta con esta, ilegible.
        skip_corner_label = any(
            val > 0
            and (val / maxval) * chart_h > chart_h - 16
            and pad_left + i * bw + bw * 0.18 + bw * 0.64 > w - 60
            for i, (_, val) in enumerate(self.data)
        )
        if not skip_corner_label:
            cr.set_source_rgb(*dim_rgb)
            cr.select_font_face('Sans', 0, 0)
            cr.set_font_size(9)
            cr.move_to(w - 14 - len(str(maxval)) * 5, pad_top - 6)
            cr.show_text(str(maxval))

        # Barras con gradiente sutil
        for i, (label, val) in enumerate(self.data):
            bh = (val / maxval) * chart_h if maxval else 0
            x = pad_left + i * bw + bw * 0.18
            y = pad_top + (chart_h - bh)
            bar_w = bw * 0.64

            # Gradiente vertical (Adwaita usa fills sólidos pero un sutil gradiente
            # da profundidad sin romper la HIG)
            pat = cairo.LinearGradient(0, y, 0, y + bh)
            r, g, b = self.color
            pat.add_color_stop_rgb(0, min(r + 0.08, 1), min(g + 0.08, 1), min(b + 0.08, 1))
            pat.add_color_stop_rgb(1, r, g, b)
            cr.set_source(pat)
            self._round_rect(cr, x, y, bar_w, max(bh, 1), 3)
            cr.fill()

            # Valor encima de la barra si hay espacio
            if bh > 24 and val > 0:
                cr.set_source_rgb(*muted_rgb)
                cr.set_font_size(9)
                txt = str(val)
                cr.move_to(x + bar_w / 2 - len(txt) * 2.5, y - 3)
                cr.show_text(txt)

            # Etiqueta eje X
            cr.set_source_rgb(*dim_rgb)
            cr.set_font_size(9)
            cr.move_to(x + bar_w / 2 - len(label) * 2.2, h - pad_bottom + 14)
            cr.show_text(label)

    def _draw_line(self, cr, w, h, muted_rgb, dim_rgb):
        pad_left, pad_bottom, pad_top = 14, 26, 34
        chart_h = h - pad_bottom - pad_top
        chart_w = w - pad_left - 14
        maxval = max((v for _, v in self.data), default=1) or 1
        n = len(self.data) or 1
        bw = chart_w / n

        # Gridlines
        border_rgb = hex_to_rgb(BORDER)
        for frac in (0.25, 0.5, 0.75, 1.0):
            gy = pad_top + chart_h * (1 - frac)
            cr.set_source_rgba(*border_rgb, 0.5)
            cr.set_line_width(1)
            cr.move_to(pad_left, gy)
            cr.line_to(pad_left + chart_w, gy)
            cr.stroke()

        pts = []
        for i, (label, val) in enumerate(self.data):
            x = pad_left + i * bw + bw / 2
            y = pad_top + (chart_h - (val / maxval) * chart_h if maxval else chart_h)
            pts.append((x, y, label))

        # Área bajo la línea (fill sutil)
        if len(pts) >= 2:
            r, g, b = self.color
            cr.set_source_rgba(r, g, b, 0.12)
            cr.move_to(pts[0][0], pad_top + chart_h)
            for x, y, _ in pts:
                cr.line_to(x, y)
            cr.line_to(pts[-1][0], pad_top + chart_h)
            cr.close_path()
            cr.fill()

        # Línea
        cr.set_source_rgb(*self.color)
        cr.set_line_width(2)
        for i, (x, y, _) in enumerate(pts):
            if i == 0:
                cr.move_to(x, y)
            else:
                cr.line_to(x, y)
        cr.stroke()

        # Puntos + labels
        for x, y, label in pts:
            cr.set_source_rgb(*self.color)
            cr.arc(x, y, 3, 0, 6.2832)
            cr.fill()
            cr.set_source_rgb(*dim_rgb)
            cr.set_font_size(9)
            cr.move_to(x - len(label) * 2.2, h - pad_bottom + 14)
            cr.show_text(label)

    def _draw_sparkline(self, cr, w, h):
        """Sparkline compacta sin ejes — para cabeceras de cards."""
        if not self.data:
            return
        pad = 4
        chart_w = w - 2 * pad
        chart_h = h - 2 * pad
        maxval = max((v for _, v in self.data), default=1) or 1
        n = len(self.data) or 1
        bw = chart_w / n

        pts = []
        for i, (_, val) in enumerate(self.data):
            x = pad + i * bw + bw / 2
            y = pad + (chart_h - (val / maxval) * chart_h if maxval else chart_h)
            pts.append((x, y))

        if len(pts) >= 2:
            r, g, b = self.color
            cr.set_source_rgba(r, g, b, 0.15)
            cr.move_to(pts[0][0], pad + chart_h)
            for x, y in pts:
                cr.line_to(x, y)
            cr.line_to(pts[-1][0], pad + chart_h)
            cr.close_path()
            cr.fill()

        cr.set_source_rgb(*self.color)
        cr.set_line_width(1.5)
        for i, (x, y) in enumerate(pts):
            if i == 0:
                cr.move_to(x, y)
            else:
                cr.line_to(x, y)
        cr.stroke()
        if pts:
            cr.arc(pts[-1][0], pts[-1][1], 2, 0, 6.2832)
            cr.fill()

    def _draw_donut(self, cr, w, h, muted_rgb, dim_rgb):
        """Donut chart — data = [(label, value, color_rgb), ...]"""
        if not self.data:
            cr.set_source_rgba(*dim_rgb, 0.7)
            cr.set_font_size(11)
            cr.move_to(14, h / 2)
            cr.show_text('Sin datos')
            return
        # Acepta data con o sin color; si no tiene color, usa paleta rotatoria
        palette = [hex_to_rgb(BRAND), hex_to_rgb(INFO), hex_to_rgb(SUCCESS),
                   hex_to_rgb(WARNING), hex_to_rgb(DANGER), hex_to_rgb('#9c27b0'),
                   hex_to_rgb('#00bcd4'), hex_to_rgb('#ff5722')]
        clean = []
        for i, item in enumerate(self.data):
            if len(item) >= 3:
                clean.append((item[0], item[1], item[2]))
            else:
                clean.append((item[0], item[1], palette[i % len(palette)]))

        total = sum(v for _, v, _ in clean) or 1
        cx, cy = w / 2, h / 2 + 4
        radius = min(w, h) / 2 - 24
        inner = radius * 0.62

        # Anillos
        start = -1.5708  # 12 en punto
        for label, val, color in clean:
            angle = (val / total) * 6.2832
            cr.set_source_rgb(*color)
            cr.move_to(cx, cy)
            cr.arc(cx, cy, radius, start, start + angle)
            cr.close_path()
            cr.fill()
            start += angle

        # Agujero central
        cr.set_source_rgb(*hex_to_rgb(SURFACE))
        cr.arc(cx, cy, inner, 0, 6.2832)
        cr.fill()

        # Texto central: total
        cr.set_source_rgb(*muted_rgb)
        cr.select_font_face('Sans', 0, 1)
        cr.set_font_size(10)
        total_str = str(total)
        cr.move_to(cx - len(total_str) * 3, cy - 2)
        cr.show_text(total_str)
        cr.set_source_rgb(*dim_rgb)
        cr.set_font_size(8)
        cr.move_to(cx - 13, cy + 12)
        cr.show_text('TOTAL')

        # Leyenda lateral derecha
        ly = 24
        for label, val, color in clean[:6]:  # máximo 6 entradas en leyenda
            cr.set_source_rgb(*color)
            cr.rectangle(w - 110, ly, 8, 8)
            cr.fill()
            cr.set_source_rgb(*muted_rgb)
            cr.set_font_size(9)
            txt = label[:14] + ('…' if len(label) > 14 else '')
            cr.move_to(w - 98, ly + 7)
            cr.show_text(txt)
            cr.set_source_rgb(*dim_rgb)
            val_str = str(val)
            cr.move_to(w - 32, ly + 7)
            cr.show_text(val_str)
            ly += 14


# ─── Widgets reutilizables ──────────────────────────────────────────────────────

class StatCard(Gtk.Box):
    """Card de estadística: label pequeño + valor grande + subtexto opcional."""
    def __init__(self, label, value='—', sub='', trend=None):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.get_style_context().add_class('stat-card')

        lbl = Gtk.Label(label=label.upper(), xalign=0)
        lbl.get_style_context().add_class('stat-label')
        self.pack_start(lbl, False, False, 0)

        self.value_lbl = Gtk.Label(label=value, xalign=0)
        self.value_lbl.get_style_context().add_class('stat-value')
        self.value_lbl.get_style_context().add_class('mono')
        self.pack_start(self.value_lbl, False, False, 0)

        self.sub_row = Gtk.Box(spacing=6)
        self.pack_start(self.sub_row, False, False, 0)
        if sub:
            self.sub_lbl = Gtk.Label(label=sub, xalign=0)
            self.sub_lbl.get_style_context().add_class('stat-sub')
            self.sub_row.pack_start(self.sub_lbl, False, False, 0)
        if trend:
            t_lbl = Gtk.Label(label=trend)
            t_lbl.get_style_context().add_class('stat-trend-up' if trend.startswith('+') else 'stat-trend-down')
            self.sub_row.pack_start(t_lbl, False, False, 0)

    def set_value(self, v):
        self.value_lbl.set_text(str(v))

    def set_sub(self, s):
        if hasattr(self, 'sub_lbl'):
            self.sub_lbl.set_text(s)


class SectionHeader(Gtk.Box):
    """Título de sección: section-title pequeño + optional action a la derecha."""
    def __init__(self, title, subtitle=None, action_widget=None):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbl = Gtk.Label(label=title, xalign=0)
        lbl.get_style_context().add_class('section-h')
        vbox.pack_start(lbl, False, False, 0)
        if subtitle:
            sub = Gtk.Label(label=subtitle, xalign=0)
            sub.get_style_context().add_class('label-muted')
            vbox.pack_start(sub, False, False, 0)
        self.pack_start(vbox, False, False, 0)
        if action_widget:
            self.pack_end(action_widget, False, False, 0)


def make_btn(label, css_class='btn-flat', small=False, on_click=None, icon=None):
    """Crea un botón estilizado. css_class: btn-primary|btn-brand|btn-warn|btn-danger|btn-flat."""
    btn = Gtk.Button(label=label)
    ctx = btn.get_style_context()
    ctx.add_class('action-btn')
    ctx.add_class(css_class)
    if small:
        ctx.add_class('btn-small')
    if on_click:
        btn.connect('clicked', on_click)
    return btn



# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: MONITOREO
# ══════════════════════════════════════════════════════════════════════════════

class MonitorModule:
    """Estado en vivo del servidor: servicios systemd, memoria, pedidos/mensajes
    del día, gráficos de actividad 7 días, sparklines y acciones de control."""

    def __init__(self, parent):
        self.parent = parent
        self._current_tunnel_url = None
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        # Header del módulo
        header = SectionHeader('Estado en vivo',
                               'Servicios, recursos y actividad de las últimas 24 horas',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.parent.refresh_all()))
        self.box.pack_start(header, False, False, 0)

        # ─── Cards de estado de servicios (3 columnas) ───────────────
        cards_box = Gtk.Box(spacing=12)
        self.box.pack_start(cards_box, False, False, 0)

        # Servicio Node
        self.card_node = StatCard('Servicio Node', sub='systemd ' + SERVICE)
        self.dot_node = Gtk.Box()
        self.dot_node.set_size_request(9, 9)
        self.dot_node.get_style_context().add_class('status-dot')
        self.dot_node.get_style_context().add_class('dot-inactive')
        self.card_node.pack_start(self.dot_node, False, False, 0)
        cards_box.pack_start(self.card_node, True, True, 0)

        # Acceso público (Tailscale Funnel -- URL fija, sin abrir puertos)
        self.card_tunnel = StatCard('Acceso público', sub='Tailscale Funnel')
        self.dot_tunnel = Gtk.Box()
        self.dot_tunnel.set_size_request(9, 9)
        self.dot_tunnel.get_style_context().add_class('status-dot')
        self.dot_tunnel.get_style_context().add_class('dot-inactive')
        self.card_tunnel.pack_start(self.dot_tunnel, False, False, 0)
        cards_box.pack_start(self.card_tunnel, True, True, 0)

        # Bot WhatsApp
        self.card_bot = StatCard('Bot WhatsApp', sub='Conexión')
        self.dot_bot = Gtk.Box()
        self.dot_bot.set_size_request(9, 9)
        self.dot_bot.get_style_context().add_class('status-dot')
        self.dot_bot.get_style_context().add_class('dot-inactive')
        self.card_bot.pack_start(self.dot_bot, False, False, 0)
        cards_box.pack_start(self.card_bot, True, True, 0)

        # ─── Cards de métricas (4 columnas) ──────────────────────────
        metrics_box = Gtk.Box(spacing=12)
        self.box.pack_start(metrics_box, False, False, 0)

        self.card_uptime   = StatCard('Activo desde',  sub='Último inicio del servicio')
        self.card_mem      = StatCard('Memoria RSS',   sub='Consumo del proceso Node')
        self.card_orders   = StatCard('Pedidos hoy',   sub='Hoy / total histórico')
        self.card_msgs     = StatCard('Mensajes hoy',  sub='Hoy / total histórico')
        for c in (self.card_uptime, self.card_mem, self.card_orders, self.card_msgs):
            metrics_box.pack_start(c, True, True, 0)

        # ─── Gráficos de actividad 7 días ────────────────────────────
        charts_title = Gtk.Label(label='ACTIVIDAD — ÚLTIMOS 7 DÍAS', xalign=0)
        charts_title.get_style_context().add_class('section-title')
        self.box.pack_start(charts_title, False, False, 0)

        charts_box = Gtk.Box(spacing=12, homogeneous=True)
        # False,False: los charts tienen su propio alto fijo (height=200) --
        # con expand=True heredaban toda la altura sobrante del módulo y se
        # veían desproporcionados.
        self.box.pack_start(charts_box, False, False, 0)

        self.chart_orders = Chart('Pedidos por día', 'bar', hex_to_rgb(BRAND), height=200)
        self.chart_msgs   = Chart('Mensajes por día', 'line', hex_to_rgb(INFO), height=200)
        charts_box.pack_start(self.chart_orders, True, True, 0)
        charts_box.pack_start(self.chart_msgs,   True, True, 0)

        # ─── Acciones de control systemd ─────────────────────────────
        actions_title = Gtk.Label(label='CONTROL DEL SERVICIO', xalign=0)
        actions_title.get_style_context().add_class('section-title')
        self.box.pack_start(actions_title, False, False, 0)

        actions = Gtk.Box(spacing=8)
        self.box.pack_start(actions, False, False, 0)
        self.btn_restart = make_btn('↻ Reiniciar', 'btn-primary',
                                     on_click=lambda _w: self._run_with_tunnel('restart'))
        self.btn_stop    = make_btn('⏸ Detener', 'btn-warn',
                                     on_click=lambda _w: self._run_with_tunnel('stop'))
        self.btn_start   = make_btn('▶ Iniciar', 'btn-primary',
                                     on_click=lambda _w: self._run_with_tunnel('start'))
        for b in (self.btn_restart, self.btn_stop, self.btn_start):
            actions.pack_start(b, False, False, 0)

        actions.pack_start(Gtk.Label(label=''), True, True, 0)  # spacer

        # Tailscale control
        actions.pack_start(make_btn('⇄ Reiniciar Tailscale', 'btn-flat', small=True,
                            on_click=lambda _w: self._run('systemctl restart tailscaled')),
                            False, False, 0)
        actions.pack_start(make_btn('⎘ Copiar URL pública', 'btn-flat', small=True,
                            on_click=lambda _w: self._copy_tunnel_url()),
                            False, False, 0)

    def _run(self, cmd):
        sh(cmd)
        GLib.timeout_add(1500, lambda: (self.parent.refresh_all(), False)[1])

    def _get_tunnel_url(self):
        """URL publica fija de Tailscale Funnel (no cambia, a diferencia del
        viejo tunel rapido de Cloudflare) -- se lee del estado real por si
        se reconfigura, en vez de asumir que siempre es la misma."""
        out = sh('tailscale funnel status 2>/dev/null')
        if not out:
            return None
        matches = re.findall(r'https://[a-z0-9.-]+\.ts\.net', out)
        return matches[0] if matches else None

    def _copy_tunnel_url(self):
        if not self._current_tunnel_url:
            self.parent.show_toast('Acceso público inactivo — no hay URL para copiar')
            return
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(self._current_tunnel_url, -1)
        self.parent.show_toast(f'URL copiada: {self._current_tunnel_url}')

    def _run_with_tunnel(self, action):
        """Inicia/detiene/reinicia el servidor Node. Tailscale/Funnel es un
        servicio del sistema independiente (siempre corriendo) -- no se
        detiene ni reinicia junto con la app."""
        sh(f'systemctl {action} {SERVICE}')
        GLib.timeout_add(1500, lambda: (self.parent.refresh_all(), False)[1])

    def _update_action_buttons(self, is_active):
        """Reacciona al estado real: Detener solo tiene sentido si esta activo,
        Iniciar solo si esta detenido -- evita botones que no hacen nada."""
        self.btn_stop.set_sensitive(is_active)
        self.btn_start.set_sensitive(not is_active)

    def refresh(self):
        # Servicio Node
        active = sh(f'systemctl is-active {SERVICE} 2>/dev/null') or 'inactivo'
        self.card_node.set_value(active.upper() if active != 'inactivo' else 'INACTIVO')
        self._set_dot(self.dot_node, active == 'active', failed=(active == 'failed'))
        self._update_action_buttons(active == 'active')

        # Acceso público (Tailscale Funnel)
        ts_active = sh('systemctl is-active tailscaled 2>/dev/null') or 'no instalado'
        self._current_tunnel_url = self._get_tunnel_url() if ts_active == 'active' else None
        tactive = 'active' if self._current_tunnel_url else ('failed' if ts_active == 'active' else ts_active)
        self.card_tunnel.set_value(tactive.upper())
        self._set_dot(self.dot_tunnel, tactive == 'active', failed=(tactive == 'failed'))
        self.card_tunnel.set_sub(self._current_tunnel_url or 'Tailscale Funnel')

        # Bot WhatsApp (vía API HTTP) -- en background: no congelar la UI si
        # el servidor tarda o está caído.
        run_in_background(lambda: http_get('/api/bot/status'), self._apply_bot_status)

        # Uptime
        since = sh(f"systemctl show {SERVICE} -p ActiveEnterTimestamp --value")
        self.card_uptime.set_value(since or '—')

        # Memoria
        mem = sh(f"systemctl show {SERVICE} -p MemoryCurrent --value")
        try:
            self.card_mem.set_value(f'{int(mem) / 1024 / 1024:.1f} MB')
        except Exception:
            self.card_mem.set_value('—')

        # Pedidos
        orders_today = query("SELECT COUNT(*) FROM orders WHERE date(requested_at)=date('now')")
        orders_total = query("SELECT COUNT(*) FROM orders")
        today = orders_today[0][0] if orders_today else 0
        total = orders_total[0][0] if orders_total else 0
        self.card_orders.set_value(f'{today} / {total}')

        # Mensajes
        msgs_today = query("SELECT COUNT(*) FROM messages WHERE date(created_at)=date('now')")
        msgs_total = query("SELECT COUNT(*) FROM messages")
        today_m = msgs_today[0][0] if msgs_today else 0
        total_m = msgs_total[0][0] if msgs_total else 0
        self.card_msgs.set_value(f'{today_m} / {total_m}')

        # Gráficos
        self._refresh_chart(self.chart_orders, 'orders', 'requested_at')
        self._refresh_chart(self.chart_msgs, 'messages', 'created_at')

    def _apply_bot_status(self, bot):
        if bot:
            ready = bot.get('ready', False)
            self.card_bot.set_value('CONECTADO' if ready else ('QR PENDIENTE' if bot.get('hasQR') else 'INACTIVO'))
            self._set_dot(self.dot_bot, ready, failed=bot.get('reconnectExhausted', False))
            pending_q = bot.get('pendingQueue', 0)
            if pending_q:
                self.card_bot.set_sub(f'Cola: {pending_q} mensaje(s) en espera')
            else:
                self.card_bot.set_sub('Sin cola pendiente')
        else:
            self.card_bot.set_value('— API no disponible')
            self.card_bot.set_sub('El servidor no responde o credenciales inválidas')
            self._set_dot(self.dot_bot, False)

    def _set_dot(self, dot, active, failed=False):
        ctx = dot.get_style_context()
        for cls in ('dot-active', 'dot-inactive', 'dot-failed', 'dot-warning'):
            ctx.remove_class(cls)
        ctx.add_class('dot-failed' if failed else ('dot-active' if active else 'dot-inactive'))

    def _refresh_chart(self, chart, table, date_col):
        rows = query(f"""
            SELECT date({date_col}) d, COUNT(*) c FROM {table}
            WHERE {date_col} >= date('now', '-6 days')
            GROUP BY d ORDER BY d
        """)
        by_date = {r[0]: r[1] for r in rows}
        data = []
        for i in range(6, -1, -1):
            d = (datetime.date.today() - datetime.timedelta(days=i))
            data.append((d.strftime('%d/%m'), by_date.get(d.isoformat(), 0)))
        chart.set_data(data)


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: VENTAS
# ══════════════════════════════════════════════════════════════════════════════

class SalesModule:
    """Resumen de ventas: ingresos hoy, ticket promedio, % cancelados, entregados,
    gráfico de ingresos 7 días, dona de estados de pedidos y top productos."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        header = SectionHeader('Resumen de ventas',
                               'Ingresos, ticket promedio y productos más vendidos',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.parent.refresh_all()))
        self.box.pack_start(header, False, False, 0)

        # ─── Cards de KPIs ───────────────────────────────────────────
        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)

        self.card_today     = StatCard('Ventas hoy',       sub='Entregados hoy')
        self.card_avg       = StatCard('Ticket promedio',  sub='Histórico entregados')
        self.card_cancelled = StatCard('% Cancelados',     sub='Sobre el total de pedidos')
        self.card_delivered = StatCard('Entregados',       sub='Total histórico')
        for c in (self.card_today, self.card_avg, self.card_cancelled, self.card_delivered):
            cards.pack_start(c, True, True, 0)

        # ─── Fila: gráfico ingresos + dona estados ───────────────────
        charts_row = Gtk.Box(spacing=12, homogeneous=False)
        # False,False por la misma razón que en Monitoreo: alto fijo por
        # diseño (height=220), no debe estirarse con espacio sobrante.
        self.box.pack_start(charts_row, False, False, 0)

        # Gráfico de barras 7 días (más ancho)
        left_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        left_title = Gtk.Label(label='INGRESOS POR DÍA — ÚLTIMOS 7 DÍAS', xalign=0)
        left_title.get_style_context().add_class('section-title')
        left_box.pack_start(left_title, False, False, 0)
        self.chart_sales = Chart('Ingresos ($)', 'bar', hex_to_rgb(BRAND), height=220)
        left_box.pack_start(self.chart_sales, True, True, 0)
        charts_row.pack_start(left_box, True, True, 0)

        # Dona de estados
        right_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        right_title = Gtk.Label(label='DISTRIBUCIÓN DE PEDIDOS', xalign=0)
        right_title.get_style_context().add_class('section-title')
        right_box.pack_start(right_title, False, False, 0)
        self.chart_states = Chart('', 'donut', height=220)
        right_box.pack_start(self.chart_states, True, True, 0)
        charts_row.pack_start(right_box, False, False, 0)
        right_box.set_size_request(360, -1)

        # ─── Ventas por día (tarjetas clickeables, no listado) ────────
        days_title = Gtk.Label(label='VENTAS POR DÍA — ÚLTIMOS 14 DÍAS (clic para el detalle)', xalign=0)
        days_title.get_style_context().add_class('section-title')
        self.box.pack_start(days_title, False, False, 0)

        self.days_flow = Gtk.FlowBox()
        self.days_flow.set_selection_mode(Gtk.SelectionMode.NONE)
        self.days_flow.set_homogeneous(True)
        self.days_flow.set_column_spacing(10)
        self.days_flow.set_row_spacing(10)
        self.days_flow.set_max_children_per_line(7)
        self.box.pack_start(self.days_flow, False, False, 0)

        # ─── Top productos ───────────────────────────────────────────
        top_title = Gtk.Label(label='TOP 10 PRODUCTOS VENDIDOS', xalign=0)
        top_title.get_style_context().add_class('section-title')
        self.box.pack_start(top_title, False, False, 0)

        self.top_store = Gtk.ListStore(int, str, int, str)
        tree = Gtk.TreeView(model=self.top_store)
        tree.get_style_context().add_class('mono')
        for i, (colname, w) in enumerate([('#', 40), ('Producto', 280), ('Unidades', 100), ('Ingresos estimado', 140)]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            if i in (0, 2):
                renderer.set_property('xalign', 1.0)
            col.set_resizable(True)
            col.set_min_width(w)
            tree.append_column(col)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        scroll.set_min_content_height(200)
        self.box.pack_start(scroll, True, True, 0)

    def refresh(self):
        # Ventas hoy
        sales_today = query("""
            SELECT COALESCE(SUM(oi.product_price*oi.quantity),0) FROM orders o
            JOIN order_items oi ON oi.order_id=o.id
            WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime')=date('now','localtime')
        """)
        self.card_today.set_value(fmt_money(sales_today[0][0] if sales_today else 0))

        # Ticket promedio
        avg = query("""
            SELECT COALESCE(AVG(t),0) FROM (
              SELECT SUM(oi.product_price*oi.quantity) t FROM orders o
              JOIN order_items oi ON oi.order_id=o.id
              WHERE o.status IN ('entregado','delivered') GROUP BY o.id)
        """)
        self.card_avg.set_value(fmt_money(avg[0][0] if avg else 0))

        # Conteos
        counts = query("""
            SELECT COUNT(*) FILTER (WHERE status='cancelled'),
                   COUNT(*) FILTER (WHERE status IN ('entregado','delivered')),
                   COUNT(*) FROM orders
        """)
        if counts:
            cancelled, delivered, total = counts[0]
            pct = round((cancelled / total) * 100) if total else 0
            self.card_cancelled.set_value(f'{pct}%')
            self.card_delivered.set_value(str(delivered))
        else:
            self.card_cancelled.set_value('0%')
            self.card_delivered.set_value('0')

        # Gráfico de ingresos 7 días
        rows = query("""
            SELECT date(o.delivered_at,'localtime') d, SUM(oi.product_price*oi.quantity) t
            FROM orders o JOIN order_items oi ON oi.order_id=o.id
            WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime') >= date('now','-6 days','localtime')
            GROUP BY d ORDER BY d
        """)
        by_date = {r[0]: r[1] for r in rows}
        data = []
        for i in range(6, -1, -1):
            d = (datetime.date.today() - datetime.timedelta(days=i))
            data.append((d.strftime('%d/%m'), int(by_date.get(d.isoformat(), 0) or 0)))
        self.chart_sales.set_data(data)

        # Dona de estados
        states = query("""
            SELECT status, COUNT(*) FROM orders
            WHERE status IN ('pending','claimed','en_camino','entregado','delivered','cancelled')
            GROUP BY status
        """)
        status_colors = {
            'pending':   hex_to_rgb(WARNING),
            'claimed':   hex_to_rgb(INFO),
            'en_camino': hex_to_rgb(BRAND),
            'entregado': hex_to_rgb(SUCCESS),
            'delivered': hex_to_rgb(SUCCESS),
            'cancelled': hex_to_rgb(DANGER),
        }
        status_labels = {
            'pending': 'Pendiente', 'claimed': 'Reclamado', 'en_camino': 'En camino',
            'entregado': 'Entregado', 'delivered': 'Entregado', 'cancelled': 'Cancelado'
        }
        donut_data = [(status_labels.get(s, s), c, status_colors.get(s, hex_to_rgb(FG_DIM)))
                      for s, c in states if c > 0]
        self.chart_states.set_data(donut_data)

        # Top productos
        top = query("""
            SELECT oi.product_name, SUM(oi.quantity) q, SUM(oi.product_price*oi.quantity) v
            FROM order_items oi
            JOIN orders o ON o.id=oi.order_id
            WHERE o.status IN ('entregado','delivered')
            GROUP BY oi.product_name ORDER BY q DESC LIMIT 10
        """)
        self.top_store.clear()
        for i, (name, qty, val) in enumerate(top, 1):
            self.top_store.append([i, name, qty, fmt_money(val)])

        # Ventas por día — últimos 14 días
        day_rows = query("""
            SELECT date(o.delivered_at,'localtime') d, COUNT(DISTINCT o.id) n, SUM(oi.product_price*oi.quantity) t
            FROM orders o JOIN order_items oi ON oi.order_id=o.id
            WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime') >= date('now','-13 days','localtime')
            GROUP BY d ORDER BY d DESC
        """)
        by_day = {r[0]: (r[1], r[2]) for r in day_rows}
        for child in self.days_flow.get_children():
            self.days_flow.remove(child)
        max_total = max((t for _, t in by_day.values()), default=0) or 1
        for i in range(0, 14):
            d = datetime.date.today() - datetime.timedelta(days=i)
            iso = d.isoformat()
            n, t = by_day.get(iso, (0, 0))
            self.days_flow.add(self._build_day_card(d, n, t or 0, iso, max_total))
        self.days_flow.show_all()

    def _build_day_card(self, d, count, total, iso, max_total):
        """Tarjeta clickeable con barra de intensidad relativa al dia de
        mayor venta -- reemplaza el listado plano de antes (se veia como
        una tabla apretada de texto en vez de un dashboard)."""
        btn = Gtk.Button()
        btn.set_relief(Gtk.ReliefStyle.NONE)
        btn.get_style_context().add_class('stat-card')
        btn.connect('clicked', lambda *_: self._show_day_detail(iso, d.strftime('%A %d/%m').capitalize()))

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        lbl_date = Gtk.Label(label=d.strftime('%a %d/%m').capitalize(), xalign=0)
        lbl_date.get_style_context().add_class('stat-label')
        vbox.pack_start(lbl_date, False, False, 0)

        lbl_total = Gtk.Label(label=fmt_money(total), xalign=0)
        lbl_total.get_style_context().add_class('stat-value')
        lbl_total.get_style_context().add_class('mono')
        vbox.pack_start(lbl_total, False, False, 0)

        bar_bg = Gtk.Box()
        bar_bg.set_size_request(-1, 5)
        bar_bg.get_style_context().add_class('day-bar-bg')
        bar_fg = Gtk.Box()
        bar_fg.get_style_context().add_class('day-bar-fg')
        ratio = max(0.03, min(1.0, total / max_total)) if total else 0
        bar_fg.set_size_request(int(140 * ratio), 5)
        bar_bg.pack_start(bar_fg, False, False, 0)
        vbox.pack_start(bar_bg, False, False, 2)

        lbl_count = Gtk.Label(label=f'{count} pedido{"s" if count != 1 else ""}', xalign=0)
        lbl_count.get_style_context().add_class('stat-sub')
        vbox.pack_start(lbl_count, False, False, 0)

        btn.add(vbox)
        return btn

    def _show_day_detail(self, iso_date, label):
        """Subventana con el detalle de pedidos de un día + acceso al PDF diario
        (generado automáticamente a las 23:59 por el servidor)."""
        dialog = Gtk.Dialog(title=f'Detalle — {label}', transient_for=self.parent,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons('Cerrar', Gtk.ResponseType.CLOSE)
        dialog.set_default_size(640, 420)
        box = dialog.get_content_area()
        box.set_spacing(10)
        box.set_border_width(14)

        orders = query("""
            SELECT o.id, COALESCE(c.name, o.customer_id, '—'), oi.product_name, oi.quantity,
                   oi.product_price*oi.quantity, o.delivered_at
            FROM orders o
            JOIN order_items oi ON oi.order_id = o.id
            LEFT JOIN customers c ON c.id = o.customer_id
            WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at,'localtime') = ?
            ORDER BY o.delivered_at
        """, (iso_date,))

        store = Gtk.ListStore(str, str, str, int, str)
        tree = Gtk.TreeView(model=store)
        tree.get_style_context().add_class('mono')
        for i, (colname, w) in enumerate([('#Pedido', 70), ('Cliente', 150), ('Producto', 200), ('Cant.', 60), ('Subtotal', 100)]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            col.set_min_width(w)
            tree.append_column(col)
        for oid, customer, product, qty, subtotal, delivered_at in orders:
            hora = (delivered_at or '')[11:16]
            store.append([f'#{oid} {hora}', str(customer), product, qty, fmt_money(subtotal)])
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)

        if not orders:
            box.pack_start(Gtk.Label(label='Sin pedidos entregados este día.'), False, False, 0)

        pdf_bar = Gtk.Box(spacing=8)
        box.pack_start(pdf_bar, False, False, 0)
        reports_dir = env_get('REPORTS_DIR') or os.path.join(PROJ, 'server', 'reports')
        pdf_path = os.path.join(reports_dir, f'registro-{iso_date}.pdf')
        if os.path.exists(pdf_path):
            pdf_bar.pack_start(make_btn('📄 Abrir reporte PDF del día', 'btn-primary', small=True,
                                        on_click=lambda *_: sh(f'xdg-open "{pdf_path}" 2>/dev/null &')), False, False, 0)
        else:
            hint = Gtk.Label(label='Reporte PDF de este día aún no generado (se crea automáticamente a las 23:59).')
            hint.get_style_context().add_class('label-dim')
            pdf_bar.pack_start(hint, False, False, 0)

        box.show_all()
        dialog.run()
        dialog.destroy()


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: PEDIDOS ACTIVOS (NUEVO)
# ══════════════════════════════════════════════════════════════════════════════

class OrdersModule:
    """Lista en vivo de pedidos activos (pending/claimed/en_camino) con acciones:
    reclamar, liberar, marcar en camino, entregar, cancelar (admin)."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        header = SectionHeader('Pedidos activos',
                               'Gestión en tiempo real del flujo de pedidos',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        # ─── KPIs rápidos ────────────────────────────────────────────
        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)
        self.card_pending   = StatCard('Pendientes',   sub='Esperando ser reclamados')
        self.card_claimed   = StatCard('Reclamados',   sub='En proceso por un empleado')
        self.card_camino    = StatCard('En camino',    sub='En proceso por un empleado')
        self.card_today     = StatCard('Entregados hoy', sub='Total del día')
        for c in (self.card_pending, self.card_claimed, self.card_camino, self.card_today):
            cards.pack_start(c, True, True, 0)

        # ─── Lista de pedidos ────────────────────────────────────────
        list_title = Gtk.Label(label='PEDIDOS EN GESTIÓN', xalign=0)
        list_title.get_style_context().add_class('section-title')
        self.box.pack_start(list_title, False, False, 0)

        self.orders_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.orders_box)
        self.box.pack_start(scroll, True, True, 0)

        self.empty_label = Gtk.Label(label='No hay pedidos activos — todo al día ✓')
        self.empty_label.get_style_context().add_class('empty-state')
        self.orders_box.pack_start(self.empty_label, False, False, 0)

    def refresh(self):
        # KPIs
        stats = query("""
            SELECT
              COUNT(*) FILTER (WHERE status='pending') AS pending,
              COUNT(*) FILTER (WHERE status='claimed') AS claimed,
              COUNT(*) FILTER (WHERE status='en_camino') AS en_camino,
              COUNT(*) FILTER (WHERE status IN ('entregado','delivered')
                               AND date(delivered_at,'localtime')=date('now','localtime')) AS today
            FROM orders
        """)
        if stats:
            p, c, e, t = stats[0]
            self.card_pending.set_value(str(p))
            self.card_claimed.set_value(str(c))
            self.card_camino.set_value(str(e))
            self.card_today.set_value(str(t))

        # Lista de pedidos activos
        for w in self.orders_box.get_children():
            self.orders_box.remove(w)

        rows = query("""
            SELECT o.id, o.status, o.product_name, o.delivery_address,
                   o.requested_at, o.is_fiado, o.claimed_at,
                   c.phone, c.name AS customer_name,
                   u.display_name AS claimed_by_name
            FROM orders o
            LEFT JOIN customers c ON o.customer_id = c.id
            LEFT JOIN users u ON o.claimed_by = u.id
            WHERE o.status IN ('pending','claimed','en_camino')
            ORDER BY o.requested_at ASC
            LIMIT 50
        """)

        if not rows:
            self.empty_label = Gtk.Label(label='No hay pedidos activos — todo al día ✓')
            self.empty_label.get_style_context().add_class('empty-state')
            self.orders_box.pack_start(self.empty_label, False, False, 0)
            return

        for r in rows:
            card = self._build_order_card(r)
            self.orders_box.pack_start(card, False, False, 0)

    def _build_order_card(self, row):
        oid, status, product, address, requested_at, is_fiado, claimed_at, phone, customer, claimed_by = row

        card = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        card.get_style_context().add_class('order-card')
        status_class = {
            'pending': 'order-pending', 'claimed': 'order-claimed', 'en_camino': 'order-en_camino'
        }.get(status, '')
        if status_class:
            card.get_style_context().add_class(status_class)
        card.set_margin_start(0)
        card.set_margin_end(0)

        # Columna izquierda: ID + estado
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        id_lbl = Gtk.Label(label=f'#{oid}')
        id_lbl.get_style_context().add_class('mono')
        id_lbl.get_style_context().add_class('label-bold')
        left.pack_start(id_lbl, False, False, 0)

        status_map = {
            'pending': ('PENDIENTE', 'pill-warning'),
            'claimed': ('RECLAMADO', 'pill-info'),
            'en_camino': ('EN CAMINO', 'pill-brand'),
        }
        pill_text, pill_kind = status_map.get(status, (status.upper(), 'pill-muted'))
        left.pack_start(status_pill(pill_text, pill_kind), False, False, 0)
        card.pack_start(left, False, False, 0)

        # Columna central: producto + dirección + cliente
        center = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        prod_lbl = Gtk.Label(label=product or '(sin producto)', xalign=0)
        prod_lbl.get_style_context().add_class('label-bold')
        prod_lbl.set_line_wrap(True)
        center.pack_start(prod_lbl, False, False, 0)

        if address:
            addr_lbl = Gtk.Label(label='📍 ' + address, xalign=0)
            addr_lbl.get_style_context().add_class('label-muted')
            addr_lbl.set_line_wrap(True)
            center.pack_start(addr_lbl, False, False, 0)

        cust_text = customer or '(sin nombre)'
        if phone:
            cust_text += f' · 📱 {phone}'
        if is_fiado:
            cust_text += ' · FIADO'
        cust_lbl = Gtk.Label(label=cust_text, xalign=0)
        cust_lbl.get_style_context().add_class('label-dim')
        center.pack_start(cust_lbl, False, False, 0)

        card.pack_start(center, True, True, 0)

        # Columna derecha: tiempos + acciones
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        req_lbl = Gtk.Label(label='Pedido: ' + fmt_relative(requested_at))
        req_lbl.get_style_context().add_class('label-dim')
        right.pack_start(req_lbl, False, False, 0)

        if claimed_by:
            cl_lbl = Gtk.Label(label='Asignado a: ' + (claimed_by or '?'))
            cl_lbl.get_style_context().add_class('label-dim')
            right.pack_start(cl_lbl, False, False, 0)

        # Botones de acción según estado
        actions = Gtk.Box(spacing=4)
        if status == 'pending':
            actions.pack_start(make_btn('Reclamar', 'btn-primary', small=True, on_click=lambda _w, id=oid: self._action(id, 'claim')), False, False, 0)
        elif status == 'claimed':
            actions.pack_start(make_btn('Liberar', 'btn-warn', small=True, on_click=lambda _w, id=oid: self._action(id, 'unclaim')), False, False, 0)
            actions.pack_start(make_btn('En camino', 'btn-brand', small=True, on_click=lambda _w, id=oid: self._action(id, 'en_camino')), False, False, 0)
        elif status == 'en_camino':
            actions.pack_start(make_btn('Entregado ✓', 'btn-primary', small=True, on_click=lambda _w, id=oid: self._action(id, 'deliver')), False, False, 0)

        actions.pack_start(make_btn('Cancelar', 'btn-danger', small=True, on_click=lambda _w, id=oid: self._action_cancel(id)), False, False, 0)
        right.pack_start(actions, False, False, 0)

        card.pack_start(right, False, False, 0)
        return card

    def _action(self, oid, action):
        """Ejecuta acción sobre pedido vía API HTTP (en background)."""
        run_in_background(lambda: http_put(f'/api/orders/{oid}/{action}', {}),
                           lambda result: self._on_action_done(oid, action, result))

    def _on_action_done(self, oid, action, result):
        if result is None:
            self._toast(f'Error: no se pudo {action} el pedido #{oid}')
        else:
            self._toast(f'Pedido #{oid} → {action} OK' if 'id' in result or 'ok' in result
                        else f'Pedido #{oid}: {result.get("error", "ok")}')
        GLib.timeout_add(800, lambda: (self.refresh(), False)[1])

    def _action_cancel(self, oid):
        """Cancelar requiere motivo — diálogo de entrada."""
        dialog = Gtk.Dialog(title='Cancelar pedido', transient_for=self.parent,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons('Cancelar', Gtk.ResponseType.CANCEL,
                           'Confirmar', Gtk.ResponseType.OK)
        dialog.set_default_size(360, 140)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        box.pack_start(Gtk.Label(label='Motivo de cancelación:'), False, False, 0)
        entry = Gtk.Entry()
        entry.set_placeholder_text('Ej: cliente no respondió, sin stock…')
        box.pack_start(entry, False, False, 0)
        box.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            reason = entry.get_text().strip()
            if reason:
                run_in_background(lambda: http_put(f'/api/orders/{oid}/cancel', {'reason': reason}),
                                   lambda result: self._on_cancel_done(oid, result))
        dialog.destroy()

    def _on_cancel_done(self, oid, result):
        self._toast(f'#{oid} cancelado' if result else f'Error al cancelar #{oid}')
        GLib.timeout_add(800, lambda: (self.refresh(), False)[1])

    def _toast(self, msg):
        # Usamos la barra de estado del parent
        self.parent.show_toast(msg)



# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: BOT WHATSAPP (NUEVO)
# ══════════════════════════════════════════════════════════════════════════════

STATUS_LABELS = {
    'connected':    'CONECTADO',
    'qr_pending':   'QR PENDIENTE',
    'connecting':   'RECONECTANDO',
    'paused':       'PAUSADO',
    'disconnected': 'DESCONECTADO',
}


class BotModule:
    """Estado del bot WhatsApp: vincular/cambiar número (encriptado, persistente),
    pausar/reanudar la conexión, QR de vinculación, cola de mensajes, tasa de
    envío/hora, reconexiones y registro de eventos del bot línea por línea."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self._qr_pixbuf = None
        self._phone_configured = False
        self._paused = False

        header = SectionHeader('Bot de WhatsApp',
                               'Vincular número, pausar/reanudar y ver el estado de la conexión',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        # ─── Cards de estado (4 KPIs) ───────────────────────────────
        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)

        self.card_status  = StatCard('Estado conexión',  sub='Bot WhatsApp')
        self.card_phone   = StatCard('Número vinculado', sub='Encriptado en la base de datos')
        self.card_queue   = StatCard('Cola de envío',    sub='Mensajes pendientes')
        self.card_rate    = StatCard('Enviados/hora',    sub='Anti-baneo WhatsApp')
        for c in (self.card_status, self.card_phone, self.card_queue, self.card_rate):
            cards.pack_start(c, True, True, 0)

        # ─── Fila principal: estado detallado + QR ──────────────────
        main_row = Gtk.Box(spacing=16, homogeneous=False)
        self.box.pack_start(main_row, True, True, 0)

        # Panel izquierdo: estado detallado
        left_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        left_frame.get_style_context().add_class('bot-frame')
        main_row.pack_start(left_frame, True, True, 0)

        left_title = Gtk.Label(label='DETALLE DE CONEXIÓN', xalign=0)
        left_title.get_style_context().add_class('section-title')
        left_frame.pack_start(left_title, False, False, 0)

        self.detail_grid = Gtk.Grid(column_spacing=14, row_spacing=10)
        left_frame.pack_start(self.detail_grid, False, False, 0)

        self.detail_labels = {}
        rows_spec = [
            ('connected_since', 'Conectado desde'),
            ('last_message',    'Último mensaje'),
            ('reconnects',      'Reintentos reconexión'),
            ('max_reconnects',  'Máximo configurado'),
            ('reconnect_state', 'Estado reconexión'),
            ('bot_enabled',     'Bot habilitado'),
        ]
        for i, (key, label) in enumerate(rows_spec):
            lbl = Gtk.Label(label=label, xalign=0)
            lbl.get_style_context().add_class('label-muted')
            val = Gtk.Label(label='—', xalign=0)
            val.get_style_context().add_class('mono')
            self.detail_grid.attach(lbl, 0, i, 1, 1)
            self.detail_grid.attach(val, 1, i, 1, 1)
            self.detail_labels[key] = val

        # Acciones
        actions_title = Gtk.Label(label='ACCIONES', xalign=0)
        actions_title.get_style_context().add_class('section-title')
        left_frame.pack_start(actions_title, False, False, 8)

        actions = Gtk.Box(spacing=8)
        left_frame.pack_start(actions, False, False, 0)
        self.btn_phone  = make_btn('Vincular número', 'btn-primary', on_click=lambda *_: self._open_phone_dialog())
        self.btn_pause  = make_btn('Pausar conexión', 'btn-warn', on_click=lambda *_: self._toggle_pause())
        self.btn_retry  = make_btn('Reintentar conexión', 'btn-flat', on_click=lambda *_: self._retry())
        self.btn_logout = make_btn('Desvincular', 'btn-danger', on_click=lambda *_: self._logout())
        for b in (self.btn_phone, self.btn_pause, self.btn_retry, self.btn_logout):
            actions.pack_start(b, False, False, 0)

        self.bot_status_label = Gtk.Label(label='')
        self.bot_status_label.get_style_context().add_class('label-dim')
        left_frame.pack_start(self.bot_status_label, False, False, 8)

        # Registro del bot — línea por línea, más reciente al final
        log_title = Gtk.Label(label='REGISTRO DEL BOT', xalign=0)
        log_title.get_style_context().add_class('section-title')
        left_frame.pack_start(log_title, False, False, 4)

        self.bot_log_view = Gtk.TextView(editable=False, cursor_visible=False)
        self.bot_log_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.bot_log_view.set_monospace(True)
        self.bot_log_view.set_left_margin(8)
        self.bot_log_view.set_top_margin(6)
        self.bot_log_view.set_bottom_margin(6)
        log_scroll = Gtk.ScrolledWindow()
        log_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.ALWAYS)
        log_scroll.set_min_content_height(140)
        log_scroll.add(self.bot_log_view)
        left_frame.pack_start(log_scroll, True, True, 0)

        # Panel derecho: QR
        right_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        right_frame.get_style_context().add_class('frame')
        right_frame.set_size_request(320, -1)
        main_row.pack_start(right_frame, False, False, 0)

        qr_title = Gtk.Label(label='CÓDIGO DE VINCULACIÓN', xalign=0)
        qr_title.get_style_context().add_class('section-title')
        right_frame.pack_start(qr_title, False, False, 0)

        qr_info = Gtk.Label(label='Escanea con WhatsApp → Dispositivos vinculados')
        qr_info.get_style_context().add_class('label-dim')
        qr_info.set_line_wrap(True)
        right_frame.pack_start(qr_info, False, False, 0)

        self.qr_image = Gtk.Image()
        self.qr_image.set_size_request(260, 260)
        right_frame.pack_start(self.qr_image, True, True, 0)

        self.qr_status = Gtk.Label(label='')
        self.qr_status.get_style_context().add_class('label-muted')
        right_frame.pack_start(self.qr_status, False, False, 0)

    def refresh(self):
        run_in_background(lambda: http_get('/api/bot/status'), self._apply_status)

    def _apply_status(self, bot):
        if bot is None:
            self.card_status.set_value('API no disponible')
            self.card_phone.set_value('—')
            self.card_queue.set_value('—')
            self.card_rate.set_value('—')
            self.bot_status_label.set_text('No se pudo conectar al servidor. ¿Está corriendo?')
            self._set_qr_status('Sin conexión al servidor', is_error=True)
            return

        ready  = bot.get('ready', False)
        has_qr = bot.get('hasQR', False)
        status = bot.get('status', 'disconnected')
        paused = bot.get('paused', False)
        phone  = bot.get('phone')

        self._phone_configured = bool(phone)
        self._paused = paused

        self.card_status.set_value(STATUS_LABELS.get(status, status.upper()))
        self.card_phone.set_value(phone or 'No configurado')
        self.card_queue.set_value(str(bot.get('pendingQueue', 0)))
        self.card_rate.set_value(f"{bot.get('sentLastHour', 0)} / {bot.get('maxMsgsPerHour', 200)}")

        # Botones dinámicos — un solo botón que cambia de texto, no duplicados
        self.btn_phone.set_label('Cambiar número' if self._phone_configured else 'Vincular número')
        self.btn_pause.set_label('Reanudar conexión' if paused else 'Pausar conexión')
        self.btn_pause.set_sensitive(self._phone_configured)
        self.btn_retry.set_sensitive(self._phone_configured and not paused)
        self.btn_logout.set_sensitive(self._phone_configured)

        # Detalle
        self.detail_labels['connected_since'].set_text(
            fmt_relative(bot.get('connectedSince')) if ready else '—')
        self.detail_labels['last_message'].set_text(
            fmt_relative(bot.get('lastMessageAt')))
        self.detail_labels['reconnects'].set_text(
            f"{bot.get('reconnectAttempts', 0)} intentos")
        self.detail_labels['max_reconnects'].set_text(
            f"{bot.get('maxReconnectAttempts', 10)} máximo")

        exhausted = bot.get('reconnectExhausted', False)
        if exhausted:
            self.detail_labels['reconnect_state'].set_text('AGOTADO — usa "Reintentar conexión"')
            self.detail_labels['reconnect_state'].get_style_context().add_class('label-bold')
        elif paused:
            self.detail_labels['reconnect_state'].set_text('En pausa — sin reconectar')
        elif ready:
            self.detail_labels['reconnect_state'].set_text('OK — conectado')
        else:
            self.detail_labels['reconnect_state'].set_text('En progreso…')

        # BOT_ENABLED viene de la API, no del .env local -- el dashboard corre
        # como usuario de escritorio y el .env es 600 solo para pedidos-bot.
        bot_enabled = bot.get('botEnabled', False)
        self.detail_labels['bot_enabled'].set_text('Sí' if bot_enabled else 'No (BOT_ENABLED=false)')

        # QR
        if has_qr:
            self._load_qr()
        else:
            if not self._phone_configured:
                self._set_qr_status('Vincula un número para generar el QR')
            elif paused:
                self._set_qr_status('Bot en pausa')
            else:
                self._set_qr_status('Bot conectado o sin QR pendiente' if ready
                                    else 'Iniciando… esperando QR')

        self._refresh_bot_log()

    def _refresh_bot_log(self):
        run_in_background(lambda: http_get('/api/bot/logs?limit=60'), self._apply_bot_log)

    def _apply_bot_log(self, data):
        logs = (data or {}).get('logs', [])
        lines = []
        for entry in logs:
            t = (entry.get('time') or '')[11:19]  # HH:MM:SS de un ISO timestamp
            lines.append(f"{t}  {entry.get('msg', '')}")
        buf = self.bot_log_view.get_buffer()
        buf.set_text('\n'.join(lines) if lines else '(sin eventos del bot todavía)')
        end = buf.get_end_iter()
        mark = buf.create_mark(None, end, False)
        self.bot_log_view.scroll_to_mark(mark, 0, False, 0, 0)

    def _load_qr(self):
        """Descarga el QR como PNG desde /api/bot/qr (en background) y lo muestra."""
        run_in_background(self._fetch_qr_png, self._apply_qr)

    def _fetch_qr_png(self):
        url = API_BASE + '/api/bot/qr'
        api_key = env_get('API_KEY')
        req = urllib.request.Request(url, headers={
            'X-API-Key': api_key,
            'Authorization': 'Bearer ' + _get_admin_token(),
        })
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return ('ok', resp.read())
        except urllib.error.HTTPError as e:
            return ('http_error', e.code)
        except Exception as e:
            return ('error', str(e))

    def _apply_qr(self, result):
        if result is None:
            self._set_qr_status('Error al descargar QR', is_error=True)
            return
        kind, payload = result
        if kind == 'ok':
            loader = GdkPixbuf.PixbufLoader()
            loader.write(payload)
            loader.close()
            pixbuf = loader.get_pixbuf()
            if pixbuf:
                # Escalar a 260x260 manteniendo proporción
                scaled = pixbuf.scale_simple(260, 260, GdkPixbuf.InterpType.BILINEAR)
                self.qr_image.set_from_pixbuf(scaled)
                self._set_qr_status('QR listo — escanea pronto (expira en ~20s)')
        elif kind == 'http_error':
            if payload == 404:
                self._set_qr_status('No hay QR pendiente — bot ya conectado', is_error=False)
            else:
                self._set_qr_status(f'Error HTTP {payload} al descargar QR', is_error=True)
        else:
            self._set_qr_status(f'Error: {str(payload)[:60]}', is_error=True)

    def _set_qr_status(self, text, is_error=False):
        self.qr_status.set_text(text)
        ctx = self.qr_status.get_style_context()
        ctx.remove_class('label-muted')
        if is_error:
            ctx.add_class('pill-danger')
        else:
            ctx.add_class('label-muted')

    def _open_phone_dialog(self):
        """Diálogo para vincular o cambiar el número de la empresa. Cambiarlo
        cuando ya había uno cierra la sesión anterior y pide un QR nuevo."""
        is_change = self._phone_configured
        dialog = Gtk.Dialog(title='Cambiar número' if is_change else 'Vincular número',
                            transient_for=self.parent, modal=True, destroy_with_parent=True)
        dialog.add_buttons('Cancelar', Gtk.ResponseType.CANCEL,
                           'Guardar', Gtk.ResponseType.OK)
        dialog.set_default_size(360, 140)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        box.pack_start(Gtk.Label(label='Número de WhatsApp de la empresa (con indicativo de país):'), False, False, 0)
        entry = Gtk.Entry()
        entry.set_placeholder_text('Ej: 573001234567')
        box.pack_start(entry, False, False, 0)
        if is_change:
            warn = Gtk.Label(label='Cambiarlo cierra la sesión vinculada actual y pedirá un QR nuevo.')
            warn.get_style_context().add_class('label-dim')
            warn.set_line_wrap(True)
            box.pack_start(warn, False, False, 0)
        box.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            phone = entry.get_text().strip()
            if phone:
                self.bot_status_label.set_text('Guardando número…')
                run_in_background(lambda: http_post('/api/bot/configure', {'phone': phone}),
                                   self._on_configure_done)
        dialog.destroy()

    def _on_configure_done(self, result):
        if result and result.get('ok'):
            self.bot_status_label.set_text('Número guardado. Generando QR…')
        else:
            err = (result or {}).get('error', 'error desconocido')
            self.bot_status_label.set_text(f'Error: {err}')
        GLib.timeout_add(2000, lambda: (self.refresh(), False)[1])

    def _toggle_pause(self):
        endpoint = '/api/bot/resume' if self._paused else '/api/bot/pause'
        self.bot_status_label.set_text('Reanudando…' if self._paused else 'Pausando…')
        run_in_background(lambda: http_post(endpoint, {}), self._on_pause_done)

    def _on_pause_done(self, result):
        if result is None or not result.get('ok'):
            self.bot_status_label.set_text(f"Error: {(result or {}).get('error', 'no se pudo cambiar el estado')}")
        GLib.timeout_add(1200, lambda: (self.refresh(), False)[1])

    def _retry(self):
        self.bot_status_label.set_text('Reintentando conexión…')
        run_in_background(lambda: http_post('/api/bot/resume', {}), self._on_retry_done)

    def _on_retry_done(self, result):
        if result is None or not result.get('ok'):
            self.bot_status_label.set_text(f"Error: {(result or {}).get('error', 'no se pudo reconectar')}")
        GLib.timeout_add(1500, lambda: (self.refresh(), False)[1])

    def _logout(self):
        """Desvincula por completo: cierra sesión, borra credenciales y el
        número guardado. Vuelve al estado de fábrica (sin número)."""
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text='Esto desvincula el WhatsApp de la empresa por completo (borra sesión y número guardado). '
                 'Los clientes no podrán escribir al bot hasta que vincules uno nuevo. ¿Continuar?')
        resp = dialog.run()
        dialog.destroy()
        if resp == Gtk.ResponseType.YES:
            run_in_background(lambda: http_post('/api/bot/logout', {}), self._on_logout_done)

    def _on_logout_done(self, result):
        self.bot_status_label.set_text('Desvinculado.' if result and result.get('ok')
                                       else 'Error al desvincular')
        GLib.timeout_add(1000, lambda: (self.refresh(), False)[1])


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: MÉTODOS DE PAGO (NEQUI)
# ══════════════════════════════════════════════════════════════════════════════

class PaymentsModule:
    """Conexion de la cuenta Nequi receptora del negocio -- conectar/cambiar,
    pausar/reanudar, desconectar. Sin credenciales reales de la API de Nequi
    Conecta todavia (pago push): esto guarda la cuenta receptora (cifrada,
    igual que el numero del bot) para que la app la muestre en el checkout
    del cliente. El cobro automatico por push queda listo para activarse
    apenas haya convenio con Nequi/Bancolombia."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self._connected = False

        header = SectionHeader('Métodos de pago',
                               'Cuenta Nequi receptora que ven los clientes al pagar',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)
        self.card_status = StatCard('Estado', sub='Conexión Nequi')
        self.card_phone  = StatCard('Número Nequi', sub='Cifrado en la base de datos')
        self.card_name   = StatCard('Cuenta', sub='Nombre asociado')
        self.card_since  = StatCard('Conectado desde', sub='Última conexión')
        for c in (self.card_status, self.card_phone, self.card_name, self.card_since):
            cards.pack_start(c, True, True, 0)

        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        frame.get_style_context().add_class('bot-frame')
        self.box.pack_start(frame, True, True, 0)

        notice = Gtk.Label(
            label='Aún sin credenciales de la API de pago-push de Nequi Conecta -- esto guarda '
                  'la cuenta receptora para mostrarla en el checkout de la app. El cobro '
                  'automático se activa cuando haya convenio con Nequi/Bancolombia.',
            xalign=0)
        notice.set_line_wrap(True)
        notice.get_style_context().add_class('label-dim')
        frame.pack_start(notice, False, False, 0)

        actions_title = Gtk.Label(label='ACCIONES', xalign=0)
        actions_title.get_style_context().add_class('section-title')
        frame.pack_start(actions_title, False, False, 8)

        actions = Gtk.Box(spacing=8)
        frame.pack_start(actions, False, False, 0)
        self.btn_connect = make_btn('Conectar Nequi', 'btn-primary', on_click=lambda *_: self._open_connect_dialog())
        self.btn_pause   = make_btn('Pausar', 'btn-warn', on_click=lambda *_: self._toggle_pause())
        self.btn_disconnect = make_btn('Desconectar', 'btn-danger', on_click=lambda *_: self._disconnect())
        for b in (self.btn_connect, self.btn_pause, self.btn_disconnect):
            actions.pack_start(b, False, False, 0)

        self.status_label = Gtk.Label(label='')
        self.status_label.get_style_context().add_class('label-dim')
        frame.pack_start(self.status_label, False, False, 8)

    def refresh(self):
        run_in_background(lambda: http_get('/api/payments/nequi'), self._apply_refresh)

    def _apply_refresh(self, data):
        if data is None:
            self.card_status.set_value('API no disponible')
            self.card_phone.set_value('—')
            self.card_name.set_value('—')
            self.card_since.set_value('—')
            self.status_label.set_text('No se pudo conectar al servidor. ¿Está corriendo?')
            return

        status = data.get('status', 'disconnected')
        phone  = data.get('phone')
        self._connected = status != 'disconnected' and bool(phone)

        labels = {'connected': 'CONECTADO', 'paused': 'PAUSADO', 'disconnected': 'SIN CONECTAR'}
        self.card_status.set_value(labels.get(status, status.upper()))
        self.card_phone.set_value(phone or 'No configurado')
        self.card_name.set_value(data.get('account_name') or '—')
        self.card_since.set_value(fmt_relative(data.get('connected_at')) if data.get('connected_at') else '—')

        self.btn_connect.set_label('Cambiar cuenta' if self._connected else 'Conectar Nequi')
        self.btn_pause.set_label('Reanudar' if status == 'paused' else 'Pausar')
        self.btn_pause.set_sensitive(self._connected)
        self.btn_disconnect.set_sensitive(self._connected)

    def _open_connect_dialog(self):
        is_change = self._connected
        dialog = Gtk.Dialog(title='Cambiar cuenta Nequi' if is_change else 'Conectar Nequi',
                            transient_for=self.parent, modal=True, destroy_with_parent=True)
        dialog.add_buttons('Cancelar', Gtk.ResponseType.CANCEL, 'Guardar', Gtk.ResponseType.OK)
        dialog.set_default_size(380, 200)
        box = dialog.get_content_area()
        box.set_spacing(8)
        box.set_border_width(14)
        box.pack_start(Gtk.Label(label='Número Nequi receptor (celular colombiano):'), False, False, 0)
        phone_entry = Gtk.Entry()
        phone_entry.set_placeholder_text('Ej: 3001234567')
        box.pack_start(phone_entry, False, False, 0)
        box.pack_start(Gtk.Label(label='Nombre en la cuenta Nequi:'), False, False, 0)
        name_entry = Gtk.Entry()
        name_entry.set_placeholder_text('Ej: Concentrados Monserrath')
        box.pack_start(name_entry, False, False, 0)
        if is_change:
            warn = Gtk.Label(label='Esto reemplaza la cuenta Nequi conectada actualmente.')
            warn.get_style_context().add_class('label-dim')
            warn.set_line_wrap(True)
            box.pack_start(warn, False, False, 0)
        box.show_all()
        if dialog.run() == Gtk.ResponseType.OK:
            phone = phone_entry.get_text().strip()
            name  = name_entry.get_text().strip()
            if phone and name:
                self.status_label.set_text('Guardando...')
                run_in_background(
                    lambda: http_post('/api/payments/nequi/connect', {'phone': phone, 'account_name': name}),
                    self._on_connect_done)
        dialog.destroy()

    def _on_connect_done(self, result):
        if result and result.get('ok'):
            self.status_label.set_text('Cuenta Nequi conectada.')
        else:
            err = (result or {}).get('error', 'error desconocido')
            self.status_label.set_text(f'Error: {err}')
        GLib.timeout_add(800, lambda: (self.refresh(), False)[1])

    def _toggle_pause(self):
        endpoint = '/api/payments/nequi/resume' if self.btn_pause.get_label() == 'Reanudar' else '/api/payments/nequi/pause'
        self.status_label.set_text('Actualizando...')
        run_in_background(lambda: http_post(endpoint, {}), self._on_toggle_pause_done)

    def _on_toggle_pause_done(self, result):
        if result is None or not result.get('ok'):
            self.status_label.set_text(f"Error: {(result or {}).get('error', 'no se pudo cambiar el estado')}")
        GLib.timeout_add(600, lambda: (self.refresh(), False)[1])

    def _disconnect(self):
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text='Esto desconecta la cuenta Nequi -- los clientes dejarán de ver la opción de '
                 'pago Nequi en el checkout hasta que conectes una cuenta de nuevo. ¿Continuar?')
        resp = dialog.run()
        dialog.destroy()
        if resp == Gtk.ResponseType.YES:
            run_in_background(lambda: http_post('/api/payments/nequi/disconnect', {}), self._on_disconnect_done)

    def _on_disconnect_done(self, result):
        self.status_label.set_text('Desconectado.' if result and result.get('ok')
                                   else 'Error al desconectar')
        GLib.timeout_add(600, lambda: (self.refresh(), False)[1])


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: EMPLEADOS (NUEVO)
# ══════════════════════════════════════════════════════════════════════════════

class EmployeesModule:
    """Desempeño por empleado: pedidos entregados, tiempo promedio de entrega,
    ranking y sparkline de actividad reciente."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        header = SectionHeader('Desempeño de empleados',
                               'Pedidos entregados y tiempos de entrega por colaborador',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        # ─── KPIs globales ──────────────────────────────────────────
        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)

        self.card_total_emp   = StatCard('Empleados activos', sub='Con pedidos entregados')
        self.card_total_del   = StatCard('Pedidos entregados', sub='Total histórico')
        self.card_avg_time    = StatCard('Tiempo promedio',    sub='De pedido a entrega')
        self.card_best         = StatCard('Top empleado',       sub='Por pedidos entregados')
        for c in (self.card_total_emp, self.card_total_del, self.card_avg_time, self.card_best):
            cards.pack_start(c, True, True, 0)

        # ─── Tabla de empleados ─────────────────────────────────────
        table_title = Gtk.Label(label='RANKING DE EMPLEADOS', xalign=0)
        table_title.get_style_context().add_class('section-title')
        self.box.pack_start(table_title, False, False, 0)

        self.store = Gtk.ListStore(int, str, str, int, str, str, int)  # ultima col: user_id (oculto)
        tree = Gtk.TreeView(model=self.store)
        for i, (colname, w) in enumerate([
            ('#', 40), ('Usuario', 140), ('Nombre', 200),
            ('Entregados', 110), ('Tiempo prom.', 120), ('Eficiencia', 110)
        ]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            col.set_min_width(w)
            if i in (0, 3):
                renderer.set_property('xalign', 1.0)
            tree.append_column(col)
        tree.connect('row-activated', self._on_employee_activated)
        hint = Gtk.Label(label='Doble clic en un empleado para ver su historial de horas de entrada', xalign=0)
        hint.get_style_context().add_class('label-dim')
        self.box.pack_start(hint, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        scroll.set_min_content_height(200)
        self.box.pack_start(scroll, True, True, 0)

        # ─── Gráfico: barras de pedidos por empleado ────────────────
        chart_title = Gtk.Label(label='PEDIDOS ENTREGADOS POR EMPLEADO', xalign=0)
        chart_title.get_style_context().add_class('section-title')
        self.box.pack_start(chart_title, False, False, 0)

        self.chart_employees = Chart('', 'bar', hex_to_rgb(BRAND), height=180)
        self.box.pack_start(self.chart_employees, False, False, 0)

        # ─── Top productos reclamados ───────────────────────────────
        info_box = Gtk.Box(spacing=12, homogeneous=True)
        self.box.pack_start(info_box, False, False, 0)

        # Tiempos por día (sparkline)
        time_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        time_title = Gtk.Label(label='TIEMPO PROMEDIO DE ENTREGA (7 DÍAS)', xalign=0)
        time_title.get_style_context().add_class('section-title')
        time_box.pack_start(time_title, False, False, 0)
        self.chart_time = Chart('', 'line', hex_to_rgb(INFO), height=140)
        time_box.pack_start(self.chart_time, True, True, 0)
        info_box.pack_start(time_box, True, True, 0)

        # Pedidos por día
        deliv_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        deliv_title = Gtk.Label(label='ENTREGAS POR DÍA (7 DÍAS)', xalign=0)
        deliv_title.get_style_context().add_class('section-title')
        deliv_box.pack_start(deliv_title, False, False, 0)
        self.chart_deliv = Chart('', 'bar', hex_to_rgb(SUCCESS), height=140)
        deliv_box.pack_start(self.chart_deliv, True, True, 0)
        info_box.pack_start(deliv_box, True, True, 0)

    def refresh(self):
        # Empleados
        employees = query("""
            SELECT u.id, u.username, COALESCE(u.display_name, u.username),
                   COUNT(*) AS delivered_count,
                   ROUND(AVG((julianday(o.delivered_at) - julianday(o.requested_at)) * 24 * 60)) AS avg_minutes
            FROM orders o
            JOIN users u ON u.id = o.claimed_by
            WHERE o.status IN ('entregado','delivered')
            GROUP BY u.id
            ORDER BY delivered_count DESC
        """)

        # KPIs
        if employees:
            self.card_total_emp.set_value(str(len(employees)))
            total_del = sum(r[3] for r in employees)
            self.card_total_del.set_value(str(total_del))
            # Promedio de tiempos
            times = [r[4] for r in employees if r[4]]
            if times:
                avg_t = int(sum(times) / len(times))
                self.card_avg_time.set_value(f'{avg_t} min')
            else:
                self.card_avg_time.set_value('—')
            top = employees[0]
            self.card_best.set_value(top[2][:20])
        else:
            self.card_total_emp.set_value('0')
            self.card_total_del.set_value('0')
            self.card_avg_time.set_value('—')
            self.card_best.set_value('—')

        # Tabla
        self.store.clear()
        chart_data = []
        for i, (uid, username, name, count, avg_min) in enumerate(employees, 1):
            avg_str = f'{int(avg_min)} min' if avg_min else '—'
            # Eficiencia: pedidos/min (más alto = mejor)
            if avg_min and avg_min > 0:
                eff = count / (avg_min / 60)  # pedidos por hora
                eff_str = f'{eff:.1f} ped/h'
            else:
                eff_str = '—'
            self.store.append([i, username, name, count, avg_str, eff_str, uid])
            chart_data.append((name.split()[0] if name else username, count))

        self.chart_employees.set_data(chart_data)

        # Tiempos por día (7 días)
        time_rows = query("""
            SELECT date(o.delivered_at,'localtime') d,
                   ROUND(AVG((julianday(o.delivered_at) - julianday(o.requested_at)) * 24 * 60)) AS mins
            FROM orders o
            WHERE o.status IN ('entregado','delivered')
              AND date(o.delivered_at,'localtime') >= date('now','-6 days','localtime')
            GROUP BY d ORDER BY d
        """)
        by_date = {r[0]: r[1] for r in time_rows}
        data_t = []
        for i in range(6, -1, -1):
            d = (datetime.date.today() - datetime.timedelta(days=i))
            data_t.append((d.strftime('%d/%m'), int(by_date.get(d.isoformat(), 0) or 0)))
        self.chart_time.set_data(data_t)

        # Entregas por día (7 días)
        deliv_rows = query("""
            SELECT date(delivered_at,'localtime') d, COUNT(*) c
            FROM orders
            WHERE status IN ('entregado','delivered')
              AND date(delivered_at,'localtime') >= date('now','-6 days','localtime')
            GROUP BY d ORDER BY d
        """)
        by_date_d = {r[0]: r[1] for r in deliv_rows}
        data_d = []
        for i in range(6, -1, -1):
            d = (datetime.date.today() - datetime.timedelta(days=i))
            data_d.append((d.strftime('%d/%m'), by_date_d.get(d.isoformat(), 0)))
        self.chart_deliv.set_data(data_d)

    def _on_employee_activated(self, tree, path, column):
        row = tree.get_model()[path]
        self._show_employee_detail(row[6], row[2] or row[1])

    def _show_employee_detail(self, user_id, name):
        """Historial de horas de entrada del empleado -- se registra cada
        vez que inicia sesion (auth.js POST /token)."""
        dialog = Gtk.Dialog(title=f'Horario de entrada — {name}', transient_for=self.parent,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons('Cerrar', Gtk.ResponseType.CLOSE)
        dialog.set_default_size(420, 480)
        box = dialog.get_content_area()
        box.set_spacing(10)
        box.set_border_width(14)

        logins = query("""
            SELECT logged_in_at FROM login_events
            WHERE user_id = ? ORDER BY logged_in_at DESC LIMIT 60
        """, (user_id,))

        store = Gtk.ListStore(str, str)
        tree = Gtk.TreeView(model=store)
        tree.get_style_context().add_class('mono')
        for i, colname in enumerate(['Fecha', 'Hora de entrada']):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            tree.append_column(col)
        for (iso,) in logins:
            dt = datetime.datetime.fromisoformat(iso.replace('Z', '+00:00')).astimezone()
            store.append([dt.strftime('%d/%m/%Y'), dt.strftime('%H:%M:%S')])
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)

        if not logins:
            box.pack_start(Gtk.Label(label='Sin registros de entrada todavía.'), False, False, 0)

        box.show_all()
        dialog.run()
        dialog.destroy()


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: UBICACIONES
# ══════════════════════════════════════════════════════════════════════════════

class LocationsModule:
    """Ubicacion GPS de trabajadores/admin -- staff_locations se llena
    desde la app (POST /api/staff-locations, solo worker/admin, nunca
    clientes). Aca se ve la ultima posicion conocida de cada uno y, con
    doble clic, su historial reciente + info de dispositivo/sesion."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        header = SectionHeader('Ubicaciones de staff',
                               'Última posición conocida de trabajadores y administradores',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)
        self.card_total     = StatCard('Staff activo', sub='Con cuenta habilitada')
        self.card_reporting = StatCard('Compartiendo ubicación', sub='Con al menos un reporte')
        self.card_recent    = StatCard('Actualizado', sub='Reporte más reciente')
        for c in (self.card_total, self.card_reporting, self.card_recent):
            cards.pack_start(c, True, True, 0)

        # ─── Mapa en vivo ─────────────────────────────────────────────
        map_title = Gtk.Label(label='MAPA EN VIVO', xalign=0)
        map_title.get_style_context().add_class('section-title')
        self.box.pack_start(map_title, False, False, 0)

        map_frame = Gtk.Box()
        map_frame.get_style_context().add_class('frame')
        self.box.pack_start(map_frame, False, False, 0)
        self.map_image = Gtk.Image()
        self.map_image.set_size_request(-1, 220)
        map_frame.pack_start(self.map_image, True, True, 0)
        self.map_empty_label = Gtk.Label(label='Sin ubicaciones activas')
        self.map_empty_label.get_style_context().add_class('empty-state')
        map_frame.pack_start(self.map_empty_label, True, True, 0)

        table_title = Gtk.Label(label='STAFF', xalign=0)
        table_title.get_style_context().add_class('section-title')
        self.box.pack_start(table_title, False, False, 0)

        self.store = Gtk.ListStore(str, str, str, str, str, int)  # ultima col: user_id (oculto)
        tree = Gtk.TreeView(model=self.store)
        for i, (colname, w) in enumerate([
            ('Usuario', 120), ('Nombre', 180), ('Rol', 90),
            ('Última posición', 220), ('Actualizado', 140),
        ]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            col.set_min_width(w)
            tree.append_column(col)
        tree.connect('row-activated', self._on_row_activated)
        hint = Gtk.Label(label='Doble clic en un trabajador para ver su historial de ubicaciones y dispositivo', xalign=0)
        hint.get_style_context().add_class('label-dim')
        self.box.pack_start(hint, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        scroll.set_min_content_height(320)
        self.box.pack_start(scroll, True, True, 0)

    def refresh(self):
        rows = query("""
            SELECT u.id, u.username, COALESCE(u.display_name, u.username), u.role,
                   sl.lat, sl.lng, sl.recorded_at
            FROM users u
            LEFT JOIN (
                SELECT sl1.user_id, sl1.lat, sl1.lng, sl1.recorded_at
                FROM staff_locations sl1
                WHERE sl1.id = (SELECT MAX(sl2.id) FROM staff_locations sl2 WHERE sl2.user_id = sl1.user_id)
            ) sl ON sl.user_id = u.id
            WHERE u.role IN ('admin','worker') AND u.active = 1
            ORDER BY (sl.recorded_at IS NULL), sl.recorded_at DESC
        """)

        self.card_total.set_value(str(len(rows)))
        reporting = [r for r in rows if r[4] is not None]
        self.card_reporting.set_value(str(len(reporting)))
        if reporting:
            latest = max(r[6] for r in reporting)
            dt = datetime.datetime.fromisoformat(latest.replace('Z', '+00:00')).astimezone()
            self.card_recent.set_value(dt.strftime('%H:%M'))
        else:
            self.card_recent.set_value('—')

        self.store.clear()
        for uid, username, name, role, lat, lng, recorded_at in rows:
            if lat is not None:
                pos_str = f'{lat:.5f}, {lng:.5f}'
                dt = datetime.datetime.fromisoformat(recorded_at.replace('Z', '+00:00')).astimezone()
                when_str = dt.strftime('%d/%m %H:%M')
            else:
                pos_str = 'Sin reportar'
                when_str = '—'
            self.store.append([username, name, role, pos_str, when_str, uid])

        # Mapa en background -- descargar/componer tiles no debe congelar la UI.
        points = [(name, lat, lng) for _uid, _u, name, _r, lat, lng, _t in rows if lat is not None]
        run_in_background(lambda: render_static_map(points), self._apply_map)

    def _apply_map(self, pixbuf):
        if pixbuf is None:
            self.map_image.hide()
            self.map_empty_label.show()
        else:
            self.map_image.set_from_pixbuf(pixbuf)
            self.map_image.show()
            self.map_empty_label.hide()

    def _on_row_activated(self, tree, path, column):
        row = tree.get_model()[path]
        self._show_detail(row[5], row[1])

    def _show_detail(self, user_id, name):
        dialog = Gtk.Dialog(title=f'Ubicación — {name}', transient_for=self.parent,
                            modal=True, destroy_with_parent=True)
        dialog.add_buttons('Cerrar', Gtk.ResponseType.CLOSE)
        dialog.set_default_size(480, 520)
        box = dialog.get_content_area()
        box.set_spacing(10)
        box.set_border_width(14)

        last_login = query("""
            SELECT logged_in_at, logged_out_at, device_info FROM login_events
            WHERE user_id = ? ORDER BY id DESC LIMIT 1
        """, (user_id,))
        if last_login:
            logged_in_at, logged_out_at, device_info = last_login[0]
            dt_in = datetime.datetime.fromisoformat(logged_in_at.replace('Z', '+00:00')).astimezone()
            estado = 'En sesión' if not logged_out_at else 'Sesión cerrada'
            info_lbl = Gtk.Label(
                label=f'{estado} · entró {dt_in.strftime("%d/%m/%Y %H:%M")} · {device_info or "dispositivo desconocido"}',
                xalign=0)
            info_lbl.set_line_wrap(True)
            box.pack_start(info_lbl, False, False, 0)

        hist_title = Gtk.Label(label='HISTORIAL DE UBICACIONES', xalign=0)
        hist_title.get_style_context().add_class('section-title')
        box.pack_start(hist_title, False, False, 0)

        history = [(h.get('lat'), h.get('lng'), h.get('accuracy'), h.get('recorded_at'))
                   for h in read_location_history(user_id)[:200]]

        store = Gtk.ListStore(str, str, str)
        tree = Gtk.TreeView(model=store)
        tree.get_style_context().add_class('mono')
        for i, colname in enumerate(['Fecha/hora', 'Coordenadas', 'Precisión']):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            tree.append_column(col)
        for lat, lng, accuracy, recorded_at in history:
            dt = datetime.datetime.fromisoformat(recorded_at.replace('Z', '+00:00')).astimezone()
            acc_str = f'±{accuracy:.0f}m' if accuracy is not None else '—'
            store.append([dt.strftime('%d/%m/%Y %H:%M:%S'), f'{lat:.5f}, {lng:.5f}', acc_str])
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)

        if not history:
            box.pack_start(Gtk.Label(label='Sin ubicaciones registradas todavía.'), False, False, 0)

        box.show_all()
        dialog.run()
        dialog.destroy()


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: CONEXIONES
# ══════════════════════════════════════════════════════════════════════════════
class ConnectionsModule:
    """Actividad por IP agregada en vivo (tabla ip_activity, backend) -- fila
    roja si supera umbrales de comportamiento sospechoso. Doble clic para ver
    detalle + bloquear/desbloquear a nivel firewall (scripts/block-ip.sh +
    sudoers acotado). Incluye panel de alertas de seguridad recientes
    (tabla security_alerts, alimentada por el backend via raiseAlert())."""

    REQUESTS_THRESHOLD = 300
    AUTH_FAIL_THRESHOLD = 5
    SCAN_THRESHOLD = 10

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        header = SectionHeader('Conexiones en vivo',
                                'Actividad por IP en los últimos 5 minutos',
                                make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)
        self.card_total   = StatCard('IPs activas', sub='Últimos 5 min')
        self.card_suspect = StatCard('Sospechosas', sub='Comportamiento anómalo')
        self.card_blocked = StatCard('Bloqueadas', sub='A nivel firewall')
        for c in (self.card_total, self.card_suspect, self.card_blocked):
            cards.pack_start(c, True, True, 0)

        alerts_title = Gtk.Label(label='ALERTAS RECIENTES', xalign=0)
        alerts_title.get_style_context().add_class('section-title')
        self.box.pack_start(alerts_title, False, False, 0)
        self.alerts_store = Gtk.ListStore(str, str, str)
        alerts_tree = Gtk.TreeView(model=self.alerts_store)
        for i, colname in enumerate(['Cuándo', 'Tipo', 'Mensaje']):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            alerts_tree.append_column(col)
        alerts_scroll = Gtk.ScrolledWindow()
        alerts_scroll.set_min_content_height(120)
        alerts_scroll.add(alerts_tree)
        self.box.pack_start(alerts_scroll, False, False, 0)

        table_title = Gtk.Label(label='ACTIVIDAD POR IP', xalign=0)
        table_title.get_style_context().add_class('section-title')
        self.box.pack_start(table_title, False, False, 0)

        self.store = Gtk.ListStore(str, str, str, str, str, str)
        tree = Gtk.TreeView(model=self.store)
        for i, (colname, w) in enumerate([
            ('IP', 130), ('Requests/5min', 100), ('Fallos auth', 90),
            ('Rutas 404', 90), ('Última ruta', 220), ('Estado', 100),
        ]):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            col.set_resizable(True)
            col.set_min_width(w)
            tree.append_column(col)
        tree.connect('row-activated', self._on_row_activated)
        hint = Gtk.Label(label='Doble clic en una IP para ver detalle y bloquear/desbloquear', xalign=0)
        hint.get_style_context().add_class('label-dim')
        self.box.pack_start(hint, False, False, 0)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        scroll.set_min_content_height(320)
        self.box.pack_start(scroll, True, True, 0)

    def _is_suspicious(self, requests, auth_fails, scans):
        return (requests > self.REQUESTS_THRESHOLD
                or auth_fails >= self.AUTH_FAIL_THRESHOLD
                or scans >= self.SCAN_THRESHOLD)

    def refresh(self):
        rows = query("""
            SELECT ip,
                   SUM(requests)  AS requests,
                   SUM(count_401) + SUM(count_403) AS auth_fails,
                   SUM(count_404) AS scans,
                   MAX(last_path) AS last_path
            FROM ip_activity
            WHERE minute >= strftime('%Y-%m-%dT%H:%M', datetime('now','localtime','-5 minutes'))
            GROUP BY ip
            ORDER BY requests DESC
        """)
        blocked = {r[0] for r in query("SELECT ip FROM blocked_ips")}

        self.card_total.set_value(str(len(rows)))
        suspicious = [r for r in rows if self._is_suspicious(r[1], r[2], r[3])]
        self.card_suspect.set_value(str(len(suspicious)))
        self.card_blocked.set_value(str(len(blocked)))

        self.store.clear()
        for ip, requests, auth_fails, scans, last_path in rows:
            estado = 'BLOQUEADA' if ip in blocked else ('SOSPECHOSA' if self._is_suspicious(requests, auth_fails, scans) else 'normal')
            self.store.append([ip, str(requests), str(auth_fails), str(scans), last_path or '—', estado])

        alerts = query("SELECT kind, message, created_at FROM security_alerts ORDER BY id DESC LIMIT 20")
        self.alerts_store.clear()
        for kind, message, created_at in alerts:
            try:
                dt = datetime.datetime.fromisoformat(created_at.replace('Z', '+00:00')).astimezone()
                when_str = dt.strftime('%d/%m %H:%M')
            except Exception:
                when_str = created_at or '—'
            self.alerts_store.append([when_str, kind, message])
        db_write("UPDATE security_alerts SET read_at = datetime('now','localtime') WHERE read_at IS NULL")

    def _on_row_activated(self, tree, path, column):
        row = tree.get_model()[path]
        self._show_detail(row[0], row[5])

    def _show_detail(self, ip, estado_actual):
        dialog = Gtk.Dialog(title=f'IP — {ip}', transient_for=self.parent,
                             modal=True, destroy_with_parent=True)
        is_blocked = (estado_actual == 'BLOQUEADA')
        action_label = 'Desbloquear IP' if is_blocked else 'Bloquear IP'
        dialog.add_buttons(action_label, Gtk.ResponseType.APPLY, 'Cerrar', Gtk.ResponseType.CLOSE)
        dialog.set_default_size(480, 420)
        box = dialog.get_content_area()
        box.set_spacing(10)
        box.set_border_width(14)

        history = query("""
            SELECT minute, requests, count_401, count_403, count_404, last_path
            FROM ip_activity WHERE ip = ? ORDER BY minute DESC LIMIT 60
        """, (ip,))
        store = Gtk.ListStore(str, str, str, str)
        tree = Gtk.TreeView(model=store)
        for i, colname in enumerate(['Minuto', 'Requests', 'Fallos auth', 'Ruta']):
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=i)
            tree.append_column(col)
        for minute, requests, c401, c403, c404, last_path in history:
            store.append([minute, str(requests), str(c401 + c403), last_path or '—'])
        scroll = Gtk.ScrolledWindow()
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)
        box.show_all()

        response = dialog.run()
        if response == Gtk.ResponseType.APPLY:
            self._toggle_block(ip, block=not is_blocked)
        dialog.destroy()
        self.refresh()

    def _toggle_block(self, ip, block):
        action = 'block' if block else 'unblock'
        sh(f"sudo /usr/local/bin/pedidos-block-ip.sh {ip} {action}")
        if block:
            db_write("INSERT OR REPLACE INTO blocked_ips (ip, reason, blocked_at) VALUES (?, ?, datetime('now','localtime'))",
                      (ip, 'Bloqueada manualmente desde el dashboard'))
            self._raise_alert('ip_blocked', f'IP {ip} bloqueada manualmente desde el dashboard')
        else:
            db_write("DELETE FROM blocked_ips WHERE ip = ?", (ip,))

    def _raise_alert(self, kind, message):
        """Espejo Python de server/src/utils/securityAlert.js -- misma tabla,
        mismo mecanismo de cola de WhatsApp (tabla messages, direction=outbound),
        para que el bot ya existente la recoja sin cambios."""
        db_write("INSERT INTO security_alerts (kind, message) VALUES (?, ?)", (kind, message))
        admin = query("SELECT phone FROM users WHERE role='admin' AND phone IS NOT NULL LIMIT 1")
        if admin:
            db_write("INSERT INTO messages (phone, content, direction, sent, type) VALUES (?, ?, 'outbound', 0, 'security_alert')",
                      (admin[0][0], f'🔒 Alerta de seguridad: {message}'))


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: DATOS
# ══════════════════════════════════════════════════════════════════════════════

class DataModule:
    """Exportar historial completo (pedidos + chats, incluidos los ya
    borrados) a PDF por rango de fechas, y administrar pedidos viejos con
    seleccion multiple (uno por uno o todos a la vez)."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)

        header = SectionHeader('Datos y exportación',
                               'Exportar historial completo a PDF, o eliminar pedidos antiguos',
                               make_btn('↻ Actualizar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        # ─── Exportar a PDF por rango ────────────────────────────────
        export_title = Gtk.Label(label='EXPORTAR A PDF', xalign=0)
        export_title.get_style_context().add_class('section-title')
        self.box.pack_start(export_title, False, False, 0)

        export_card = Gtk.Box(spacing=10)
        export_card.get_style_context().add_class('stat-card')
        self.box.pack_start(export_card, False, False, 0)

        today    = datetime.date.today()
        week_ago = today - datetime.timedelta(days=7)

        export_card.pack_start(Gtk.Label(label='Desde:'), False, False, 0)
        self.from_entry = Gtk.Entry()
        self.from_entry.set_text(week_ago.isoformat())
        self.from_entry.set_width_chars(12)
        export_card.pack_start(self.from_entry, False, False, 0)

        export_card.pack_start(Gtk.Label(label='Hasta:'), False, False, 0)
        self.to_entry = Gtk.Entry()
        self.to_entry.set_text(today.isoformat())
        self.to_entry.set_width_chars(12)
        export_card.pack_start(self.to_entry, False, False, 0)

        export_card.pack_start(make_btn('📄 Exportar a PDF', 'btn-primary', small=True,
                                         on_click=lambda *_: self._export_pdf()), False, False, 0)
        export_card.pack_start(make_btn('📊 Exportar a Excel', 'btn-primary', small=True,
                                         on_click=lambda *_: self._export_excel()), False, False, 0)
        export_card.pack_start(Gtk.Label(label=''), True, True, 0)

        hint = Gtk.Label(
            label='Incluye pedidos de cualquier estado y todos los mensajes del rango '
                  '(incluye conversaciones ya borradas de la app -- el texto siempre queda guardado).',
            xalign=0)
        hint.get_style_context().add_class('label-dim')
        hint.set_line_wrap(True)
        self.box.pack_start(hint, False, False, 0)

        # ─── Tabla de pedidos con selección múltiple ─────────────────
        table_title = Gtk.Label(label='PEDIDOS — ÚLTIMOS 300 (selección múltiple para eliminar)', xalign=0)
        table_title.get_style_context().add_class('section-title')
        self.box.pack_start(table_title, False, False, 0)

        toolbar = Gtk.Box(spacing=8)
        self.box.pack_start(toolbar, False, False, 0)
        self.select_all_chk = Gtk.CheckButton(label='Seleccionar todos')
        self.select_all_chk.connect('toggled', self._on_select_all)
        toolbar.pack_start(self.select_all_chk, False, False, 0)
        self.selected_lbl = Gtk.Label(label='0 seleccionados')
        self.selected_lbl.get_style_context().add_class('label-dim')
        toolbar.pack_start(self.selected_lbl, False, False, 0)
        toolbar.pack_start(Gtk.Label(label=''), True, True, 0)
        toolbar.pack_start(make_btn('🗑 Eliminar seleccionados', 'btn-warn', small=True,
                                     on_click=lambda *_: self._delete_selected()), False, False, 0)

        # store: seleccionado, id, fecha, producto, cliente, estado, total
        self.store = Gtk.ListStore(bool, int, str, str, str, str, str)
        tree = Gtk.TreeView(model=self.store)
        toggle = Gtk.CellRendererToggle()
        toggle.connect('toggled', self._on_row_toggled)
        tree.append_column(Gtk.TreeViewColumn('', toggle, active=0))
        for colname, idx in [('#Pedido', 1), ('Fecha', 2), ('Producto', 3),
                              ('Cliente', 4), ('Estado', 5), ('Total', 6)]:
            renderer = Gtk.CellRendererText()
            col = Gtk.TreeViewColumn(colname, renderer, text=idx)
            col.set_resizable(True)
            tree.append_column(col)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scroll.add(tree)
        scroll.set_min_content_height(320)
        self.box.pack_start(scroll, True, True, 0)

    def refresh(self):
        self.select_all_chk.set_active(False)
        rows = query("""
            SELECT o.id, o.requested_at, COALESCE(o.product_name,'—'),
                   COALESCE(c.name, c.phone, '—'), o.status, o.product_price
            FROM orders o
            LEFT JOIN customers c ON c.id = o.customer_id
            ORDER BY o.requested_at DESC
            LIMIT 300
        """)
        self.store.clear()
        for oid, req_at, product, customer, status, price in rows:
            fecha = (req_at or '')[:16].replace('T', ' ')
            total = fmt_money(price) if price else '—'
            self.store.append([False, oid, fecha, product, customer, status, total])
        self._update_selected_count()

    def _on_row_toggled(self, renderer, path):
        self.store[path][0] = not self.store[path][0]
        self._update_selected_count()

    def _on_select_all(self, chk):
        active = chk.get_active()
        for row in self.store:
            row[0] = active
        self._update_selected_count()

    def _update_selected_count(self):
        n = sum(1 for row in self.store if row[0])
        self.selected_lbl.set_text(f'{n} seleccionados')

    def _delete_selected(self):
        ids = [row[1] for row in self.store if row[0]]
        if not ids:
            self.parent.show_toast('No hay pedidos seleccionados')
            return
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f'¿Eliminar {len(ids)} pedido(s) seleccionado(s)?\nEsta acción no se puede deshacer.')
        response = dialog.run()
        dialog.destroy()
        if response != Gtk.ResponseType.YES:
            return
        run_in_background(lambda: http_delete('/api/orders/bulk', {'ids': ids}), self._on_delete_done)

    def _on_delete_done(self, result):
        if result and result.get('success'):
            self.parent.show_toast(f'{result.get("deleted", 0)} pedido(s) eliminado(s)')
            self.refresh()
        else:
            self.parent.show_toast('Error eliminando pedidos')

    def _get_valid_range(self):
        from_date = self.from_entry.get_text().strip()
        to_date   = self.to_entry.get_text().strip()
        if not re.match(r'^\d{4}-\d{2}-\d{2}$', from_date) or not re.match(r'^\d{4}-\d{2}-\d{2}$', to_date):
            self.parent.show_toast('Fechas inválidas — formato AAAA-MM-DD')
            return None
        return from_date, to_date

    def _export_pdf(self):
        rng = self._get_valid_range()
        if not rng: return
        from_date, to_date = rng
        self.parent.show_toast('Generando reporte, esto puede tardar unos segundos...')
        run_in_background(
            lambda: http_post('/api/reports/export-range', {'from': from_date, 'to': to_date}, timeout=30),
            lambda result: self._on_export_done(result, 'reporte'))

    def _export_excel(self):
        rng = self._get_valid_range()
        if not rng: return
        from_date, to_date = rng
        self.parent.show_toast('Generando Excel, esto puede tardar unos segundos...')
        run_in_background(
            lambda: http_post('/api/reports/export-range-excel', {'from': from_date, 'to': to_date}, timeout=30),
            lambda result: self._on_export_done(result, 'Excel'))

    def _on_export_done(self, result, label):
        if result and result.get('success'):
            filepath = result.get('filepath')
            self.parent.show_toast(f'{label.capitalize()} generado: {result.get("filename")}')
            if filepath and os.path.exists(filepath):
                sh(f'xdg-open "{filepath}" 2>/dev/null &')
        else:
            self.parent.show_toast(f'Error generando el {label}')


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: MARCA
# ══════════════════════════════════════════════════════════════════════════════

class BrandModule:
    """Personalización de marca: nombre, paleta (presets + HEX custom),
    vista previa en vivo y carga de logo. Se aplica al instante en la app."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)

        header = SectionHeader('Personalización de marca',
                               'Paleta, nombre y logo que ven tus clientes en la app')
        self.box.pack_start(header, False, False, 0)

        info = Gtk.Label(label='Los cambios se aplican al instante — la app los toma en el próximo login del cliente. '
                               'No es necesario reiniciar el servidor.')
        info.get_style_context().add_class('label-muted')
        info.set_line_wrap(True)
        info.set_xalign(0)
        self.box.pack_start(info, False, False, 0)

        # ─── Nombre de marca ────────────────────────────────────────
        name_box = Gtk.Box(spacing=10)
        self.box.pack_start(name_box, False, False, 4)
        name_box.pack_start(Gtk.Label(label='Nombre de marca:'), False, False, 0)
        self.entry_name = Gtk.Entry()
        self.entry_name.set_width_chars(30)
        self.entry_name.set_placeholder_text('Ej: Concentrados Monserrath')
        name_box.pack_start(self.entry_name, False, False, 0)

        # ─── Presets ────────────────────────────────────────────────
        presets_title = Gtk.Label(label='PALETAS PREDEFINIDAS', xalign=0)
        presets_title.get_style_context().add_class('section-title')
        self.box.pack_start(presets_title, False, False, 0)

        self.preset_buttons = []
        presets_box = Gtk.FlowBox()
        presets_box.set_selection_mode(Gtk.SelectionMode.NONE)
        presets_box.set_max_children_per_line(6)
        presets_box.set_row_spacing(8)
        presets_box.set_column_spacing(8)
        self.box.pack_start(presets_box, False, False, 0)
        for name, primary, accent in PRESETS:
            btn = self._make_preset_swatch(name, primary, accent)
            presets_box.add(btn)

        # ─── Custom HEX ─────────────────────────────────────────────
        custom_title = Gtk.Label(label='COLOR PERSONALIZADO (HEX)', xalign=0)
        custom_title.get_style_context().add_class('section-title')
        self.box.pack_start(custom_title, False, False, 0)

        custom_box = Gtk.Box(spacing=10)
        self.box.pack_start(custom_box, False, False, 0)
        custom_box.pack_start(Gtk.Label(label='Primario'), False, False, 0)
        self.entry_primary = Gtk.Entry()
        self.entry_primary.set_width_chars(10)
        self.entry_primary.set_placeholder_text('#2D5016')
        custom_box.pack_start(self.entry_primary, False, False, 0)
        custom_box.pack_start(Gtk.Label(label='Acento'), False, False, 0)
        self.entry_accent = Gtk.Entry()
        self.entry_accent.set_width_chars(10)
        self.entry_accent.set_placeholder_text('#D4800A')
        custom_box.pack_start(self.entry_accent, False, False, 0)

        # ─── Vista previa ───────────────────────────────────────────
        preview_title = Gtk.Label(label='VISTA PREVIA', xalign=0)
        preview_title.get_style_context().add_class('section-title')
        self.box.pack_start(preview_title, False, False, 0)
        self.preview = Gtk.DrawingArea()
        self.preview.set_size_request(-1, 80)
        self.preview.connect('draw', self._draw_preview)
        self.box.pack_start(self.preview, False, False, 0)

        # ─── Logo ───────────────────────────────────────────────────
        logo_box = Gtk.Box(spacing=10)
        self.box.pack_start(logo_box, False, False, 4)
        logo_box.pack_start(make_btn('🖼 Cambiar logo', 'btn-flat', on_click=lambda *_: self._pick_logo()), False, False, 0)
        self.logo_status = Gtk.Label(label='')
        self.logo_status.get_style_context().add_class('label-muted')
        logo_box.pack_start(self.logo_status, False, False, 0)

        # ─── Botón guardar ──────────────────────────────────────────
        self.box.pack_start(make_btn('💾 Guardar marca', 'btn-brand', on_click=lambda *_: self._save()), False, False, 8)

        # Refrescar preview al editar
        for entry in (self.entry_primary, self.entry_accent, self.entry_name):
            entry.connect('changed', lambda *_: self.preview.queue_draw())

    def _make_preset_swatch(self, name, primary, accent):
        btn = Gtk.Button()
        btn.get_style_context().add_class('preset-swatch')
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_size_request(78, 64)
        swatch = Gtk.DrawingArea()
        swatch.set_size_request(64, 32)

        def draw(widget, cr, p=primary, a=accent):
            w = widget.get_allocated_width()
            h = widget.get_allocated_height()
            r, g, b = hex_to_rgb(p)
            cr.set_source_rgb(r, g, b)
            cr.rectangle(0, 0, w / 2, h)
            cr.fill()
            r, g, b = hex_to_rgb(a)
            cr.set_source_rgb(r, g, b)
            cr.rectangle(w / 2, 0, w / 2, h)
            cr.fill()
        swatch.connect('draw', draw)
        box.pack_start(swatch, False, False, 0)
        lbl = Gtk.Label(label=name)
        lbl.set_line_wrap(True)
        lbl.set_justify(Gtk.Justification.CENTER)
        lbl.get_style_context().add_class('label-dim')
        box.pack_start(lbl, False, False, 0)
        btn.add(box)
        btn.connect('clicked', lambda *_: self._apply_preset(primary, accent))
        return btn

    def _apply_preset(self, primary, accent):
        self.entry_primary.set_text(primary)
        self.entry_accent.set_text(accent)

    def _draw_preview(self, widget, cr):
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()
        primary = self.entry_primary.get_text() or PRIMARY_DEFAULT
        accent = self.entry_accent.get_text() or ACCENT_DEFAULT

        # Fondo redondeado con el color primario
        r, g, b = hex_to_rgb(primary)
        cr.set_source_rgb(r, g, b)
        self._round_rect(cr, 0, 0, w, h, 10)
        cr.fill()

        # Borde sutil
        cr.set_source_rgba(0, 0, 0, 0.15)
        cr.set_line_width(1)
        self._round_rect(cr, 0.5, 0.5, w - 1, h - 1, 10)
        cr.stroke()

        # Nombre de marca a la izquierda
        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face('Sans', 0, 1)
        cr.set_font_size(16)
        name = self.entry_name.get_text() or 'Nombre de tu negocio'
        cr.move_to(18, h / 2 + 5)
        cr.show_text(name)

        # Botón "Pedir ahora" a la derecha
        ra, ga, ba = hex_to_rgb(accent)
        cr.set_source_rgb(ra, ga, ba)
        btn_w, btn_h = 110, 32
        self._round_rect(cr, w - btn_w - 16, h / 2 - btn_h / 2, btn_w, btn_h, 6)
        cr.fill()

        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face('Sans', 0, 1)
        cr.set_font_size(12)
        cr.move_to(w - btn_w - 16 + 22, h / 2 + 4)
        cr.show_text('Pedir ahora')

    @staticmethod
    def _round_rect(cr, x, y, w, h, r):
        cr.move_to(x + r, y)
        cr.arc(x + w - r, y + r, r, -1.5708, 0)
        cr.arc(x + w - r, y + h - r, r, 0, 1.5708)
        cr.arc(x + r, y + h - r, r, 1.5708, 3.14159)
        cr.arc(x + r, y + r, r, 3.14159, 4.71239)
        cr.close_path()

    def _pick_logo(self, _btn=None):
        dialog = Gtk.FileChooserDialog(
            title='Elegí un logo', parent=self.parent,
            action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                           Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        filt = Gtk.FileFilter()
        filt.set_name('Imágenes')
        filt.add_mime_type('image/png')
        filt.add_mime_type('image/jpeg')
        dialog.add_filter(filt)
        if dialog.run() == Gtk.ResponseType.OK:
            src = dialog.get_filename()
            ext = 'png' if src.lower().endswith('png') else 'jpg'
            appdata = self.parent._appdata_dir()
            if appdata:
                dest_dir = os.path.join(appdata, 'pedidos-bot', 'branding')
                os.makedirs(dest_dir, exist_ok=True)
                fname = f'logo_{int(datetime.datetime.now().timestamp())}.{ext}'
                dest = os.path.join(dest_dir, fname)
                sh(f'cp "{src}" "{dest}"')
                setting_set('theme_logo_url', fname)
                self.logo_status.set_text(f'✓ Logo actualizado: {fname}')
            else:
                self.logo_status.set_text('No se encontró APPDATA del servicio')
        dialog.destroy()

    def _save(self, _btn=None):
        primary = self.entry_primary.get_text().strip() or PRIMARY_DEFAULT
        accent = self.entry_accent.get_text().strip() or ACCENT_DEFAULT
        name = self.entry_name.get_text().strip()
        setting_set('theme_primary', primary)
        setting_set('theme_accent', accent)
        if name:
            setting_set('theme_name', name)
        self.logo_status.set_text('✓ Marca guardada — la app la toma en el próximo login.')

    def refresh(self):
        if not self.entry_primary.get_text():
            self.entry_primary.set_text(setting_get('theme_primary', PRIMARY_DEFAULT))
        if not self.entry_accent.get_text():
            self.entry_accent.set_text(setting_get('theme_accent', ACCENT_DEFAULT))
        if not self.entry_name.get_text():
            self.entry_name.set_text(setting_get('theme_name', 'Concentrados Monserrath'))
        self.preview.queue_draw()



# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: CONFIGURACIÓN
# ══════════════════════════════════════════════════════════════════════════════

class ConfigModule:
    """Configuración de conexión (puerto, teléfono, dominio) y acciones sensibles
    (regenerar secretos, re-vincular WhatsApp, toggle de bot)."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)

        header = SectionHeader('Configuración y acceso',
                               'Parámetros de red del servidor y acciones sensibles')
        self.box.pack_start(header, False, False, 0)

        # ─── Conexión ───────────────────────────────────────────────
        conn_title = Gtk.Label(label='CONEXIÓN Y RED', xalign=0)
        conn_title.get_style_context().add_class('section-title')
        self.box.pack_start(conn_title, False, False, 0)

        grid = Gtk.Grid(column_spacing=14, row_spacing=10)
        self.box.pack_start(grid, False, False, 0)

        self.entry_port   = self._field(grid, 0, 'Puerto del servidor', env_get('PORT') or '3000')
        self.entry_phone  = self._field(grid, 1, 'Número WhatsApp (BOT_PHONE)', env_get('BOT_PHONE'))
        self.entry_domain = self._field(grid, 2, 'Dominio propio (HTTPS)', env_get('SERVER_DOMAIN'))
        self.entry_host   = self._field(grid, 3, 'Bind de host (recomendado 127.0.0.1)',
                                        env_get('HOST') or '127.0.0.1')
        self.entry_bot_enabled = self._field(grid, 4, 'Bot habilitado (true/false)',
                                             env_get('BOT_ENABLED') or 'false')

        self.box.pack_start(make_btn('💾 Guardar y reiniciar servicio', 'btn-primary', on_click=lambda *_: self._save_config()), False, False, 8)

        # ─── Acciones sensibles ─────────────────────────────────────
        sec_title = Gtk.Label(label='ACCIONES SENSIBLES', xalign=0)
        sec_title.get_style_context().add_class('section-title')
        self.box.pack_start(sec_title, False, False, 8)

        sensitive = Gtk.Box(spacing=8)
        self.box.pack_start(sensitive, False, False, 0)
        sensitive.pack_start(make_btn('🔑 Regenerar secretos', 'btn-warn', on_click=lambda *_: self._regen_secrets()), False, False, 0)
        sensitive.pack_start(make_btn('📱 Re-vincular WhatsApp', 'btn-warn', on_click=lambda *_: self._relink()), False, False, 0)
        sensitive.pack_start(make_btn('🧹 Limpiar media antiguos', 'btn-flat', on_click=lambda *_: self._clean_media()), False, False, 0)

        # ─── Estado ─────────────────────────────────────────────────
        self.status_label = Gtk.Label(label='')
        self.status_label.get_style_context().add_class('label-muted')
        self.box.pack_start(self.status_label, False, False, 8)

        # ─── Información del sistema ────────────────────────────────
        info_title = Gtk.Label(label='INFORMACIÓN DEL SISTEMA', xalign=0)
        info_title.get_style_context().add_class('section-title')
        self.box.pack_start(info_title, False, False, 8)

        self.info_grid = Gtk.Grid(column_spacing=14, row_spacing=8)
        self.box.pack_start(self.info_grid, False, False, 0)
        self.info_labels = {}
        for i, (key, label) in enumerate([
            ('service_user', 'Usuario del servicio'),
            ('node_version', 'Versión de Node.js'),
            ('db_path',      'Ruta de la base de datos'),
            ('appdata',      'Directorio APPDATA'),
            ('log_dir',      'Directorio de logs'),
        ]):
            lbl = Gtk.Label(label=label, xalign=0)
            lbl.get_style_context().add_class('label-muted')
            val = Gtk.Label(label='—', xalign=0)
            val.get_style_context().add_class('mono')
            val.set_selectable(True)
            self.info_grid.attach(lbl, 0, i, 1, 1)
            self.info_grid.attach(val, 1, i, 1, 1)
            self.info_labels[key] = val

    def _field(self, grid, row, label_text, value):
        lbl = Gtk.Label(label=label_text, xalign=0)
        lbl.get_style_context().add_class('label-muted')
        entry = Gtk.Entry()
        entry.set_text(value or '')
        entry.set_width_chars(30)
        grid.attach(lbl, 0, row, 1, 1)
        grid.attach(entry, 1, row, 1, 1)
        return entry

    def _save_config(self, _btn=None):
        env_set('PORT', self.entry_port.get_text().strip() or '3000')
        env_set('BOT_PHONE', re.sub(r'\D', '', self.entry_phone.get_text()))
        env_set('SERVER_DOMAIN', self.entry_domain.get_text().strip())
        env_set('HOST', self.entry_host.get_text().strip() or '127.0.0.1')
        env_set('BOT_ENABLED', self.entry_bot_enabled.get_text().strip().lower() in ('true', '1', 'yes'))
        sh(f'systemctl restart {SERVICE}')
        self.status_label.set_text('✓ Guardado. Servicio reiniciando…')
        GLib.timeout_add(2000, lambda: (self.parent.refresh_all(), False)[1])

    def _regen_secrets(self, _btn=None):
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, flags=0,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text='Esto regenerará API_KEY y JWT_SECRET. La app móvil y el bot deberán '
                 'reautenticarse. ¿Continuar?')
        resp = dialog.run()
        dialog.destroy()
        if resp == Gtk.ResponseType.YES:
            env_set('API_KEY', secrets.token_hex(32))
            env_set('JWT_SECRET', secrets.token_hex(32))
            sh(f'systemctl restart {SERVICE}')
            self.status_label.set_text('✓ Secretos regenerados. La app móvil debe reloguearse.')

    def _relink(self, _btn=None):
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, flags=0,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text='Esto borra la sesión de WhatsApp actual. El bot pedirá un nuevo código '
                 'de vinculación. ¿Continuar?')
        resp = dialog.run()
        dialog.destroy()
        if resp == Gtk.ResponseType.YES:
            appdata = self.parent._appdata_dir()
            if appdata:
                sh(f'rm -rf "{appdata}/pedidos-bot/auth" && mkdir -p "{appdata}/pedidos-bot/auth"')
            sh(f'systemctl restart {SERVICE}')
            self.status_label.set_text('✓ Sesión borrada. Revisa el módulo Bot WhatsApp para el QR.')

    def _clean_media(self, _btn=None):
        appdata = self.parent._appdata_dir()
        if appdata:
            media_dir = os.path.join(appdata, 'pedidos-bot', 'media')
            docs_dir = os.path.join(appdata, 'pedidos-bot', 'docs')
            for d in (media_dir, docs_dir):
                sh(f'find "{d}" -type f -mtime +30 -delete 2>/dev/null')
        self.status_label.set_text('✓ Media antiguos (>30 días) eliminados.')

    def refresh(self):
        # Información del sistema
        user = sh(f"systemctl show {SERVICE} -p User --value")
        self.info_labels['service_user'].set_text(user or '—')
        node_ver = sh('node --version 2>/dev/null') or sh('/opt/nodejs/bin/node --version 2>/dev/null')
        self.info_labels['node_version'].set_text(node_ver or '—')
        self.info_labels['db_path'].set_text(db_path())
        appdata = self.parent._appdata_dir()
        self.info_labels['appdata'].set_text(appdata or '—')
        self.info_labels['log_dir'].set_text(LOG_DIR)


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: SEGURIDAD
# ══════════════════════════════════════════════════════════════════════════════

class SecurityModule:
    """Auditoría de seguridad: usuario del servicio, permisos .env, bind de host,
    firewall, fail2ban, servicios activos y recomendaciones."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)

        header = SectionHeader('Auditoría de seguridad',
                               'Verificación de configuración de seguridad del servidor',
                               make_btn('↻ Reauditar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        # ─── Cards de estado rápido ─────────────────────────────────
        cards = Gtk.Box(spacing=12)
        self.box.pack_start(cards, False, False, 0)
        self.card_user  = StatCard('Usuario servicio',  sub='Debe ser no-root')
        self.card_env   = StatCard('Permisos .env',     sub='Recomendado 600')
        self.card_bind  = StatCard('Bind de host',      sub='Recomendado 127.0.0.1')
        self.card_fw    = StatCard('Firewall',          sub='Estado del filtro')
        self.card_f2b   = StatCard('fail2ban',          sub='Protección SSH')
        for c in (self.card_user, self.card_env, self.card_bind, self.card_fw, self.card_f2b):
            cards.pack_start(c, True, True, 0)

        # ─── Detalle extendido ──────────────────────────────────────
        detail_title = Gtk.Label(label='DETALLE DE LA AUDITORÍA', xalign=0)
        detail_title.get_style_context().add_class('section-title')
        self.box.pack_start(detail_title, False, False, 0)

        self.view = Gtk.TextView(editable=False, cursor_visible=False)
        self.view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.view.set_left_margin(10)
        self.view.set_top_margin(10)
        self.view.set_right_margin(10)
        self.view.set_bottom_margin(10)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.view)
        scroll.set_min_content_height(200)
        self.box.pack_start(scroll, True, True, 0)

    def refresh(self):
        lines = []
        issues = 0

        # Usuario
        user = sh(f"systemctl show {SERVICE} -p User --value")
        ok_user = user and user != 'root'
        if ok_user:
            self.card_user.set_value(user)
        else:
            self.card_user.set_value(user or '—')
            issues += 1
        lines.append(f"• Servicio corre como: {user or '?'} " +
                     ("✓ (OK, no-root)" if ok_user else "✗ (RIESGO: root)"))

        # Permisos .env
        try:
            perms = oct(os.stat(ENV_FILE).st_mode)[-3:] if os.path.exists(ENV_FILE) else '?'
        except Exception:
            perms = '?'
        ok_env = perms in ('600',)
        self.card_env.set_value(perms)
        if not ok_env:
            issues += 1
        lines.append(f"• Permisos .env: {perms} " +
                     ("✓" if ok_env else "(recomendado: 600)"))

        # Bind
        host = env_get('HOST') or '127.0.0.1'
        ok_bind = host in ('127.0.0.1', 'localhost')
        self.card_bind.set_value(host)
        if not ok_bind:
            issues += 1
        lines.append(f"• HOST bind: {host} " +
                     ("✓" if ok_bind else "(expuesto a la red — revisa firewall)"))

        # Firewall
        fw = 'ufw' if sh('command -v ufw') else (
             'firewalld' if sh('command -v firewall-cmd') else
             'iptables' if sh('command -v iptables') else 'ninguno')
        fw_active = False
        if fw == 'ufw':
            fw_active = 'active' in sh('ufw status 2>/dev/null')
        elif fw == 'firewalld':
            fw_active = 'running' in sh('firewall-cmd --state 2>/dev/null')
        self.card_fw.set_value(fw.upper() if fw != 'ninguno' else 'NINGUNO')
        if fw == 'ninguno':
            issues += 1
        lines.append(f"• Firewall: {fw} " +
                     ("(activo)" if fw_active else "(inactivo o no instalado)" if fw != 'ninguno' else "✗ (NINGUNO)"))

        # fail2ban
        f2b = sh('systemctl is-active fail2ban 2>/dev/null') or 'no instalado'
        self.card_f2b.set_value(f2b.upper())
        if f2b != 'active':
            issues += 1
        lines.append(f"• fail2ban: {f2b}")

        lines.append("")
        lines.append("─ SERVICIOS ─")
        lines.append(f"• Servicio Node: {sh(f'systemctl is-active {SERVICE} 2>/dev/null') or 'no instalado'}")
        lines.append(f"• Acceso público (Tailscale): {sh('systemctl is-active tailscaled 2>/dev/null') or 'no instalado'}")

        # Recomendaciones
        lines.append("")
        lines.append("─ RECOMENDACIONES ─")
        if issues == 0:
            lines.append("✓ Todo en orden. No se detectaron problemas críticos.")
        else:
            lines.append(f"Se detectaron {issues} punto(s) a revisar arriba.")

        buf = self.view.get_buffer()
        buf.set_text('\n'.join(lines))

    def _set_card_pill(self, card, ok):
        """(Reservado para futuras mejoras visuales)"""
        pass


# ══════════════════════════════════════════════════════════════════════════════
# MÓDULO: LOGS
# ══════════════════════════════════════════════════════════════════════════════

class LogsModule:
    """Visor de logs del servidor en vivo con auto-scroll y filtros básicos."""

    def __init__(self, parent):
        self.parent = parent
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)

        header = SectionHeader('Logs del servidor',
                               'Salida en vivo del log del servicio systemd',
                               make_btn('↻ Refrescar', 'btn-flat', small=True, on_click=lambda *_: self.refresh()))
        self.box.pack_start(header, False, False, 0)

        # ─── Info bar ───────────────────────────────────────────────
        info = Gtk.Box(spacing=12)
        self.box.pack_start(info, False, False, 0)
        info.pack_start(Gtk.Label(label='📁 ' + LOG_DIR), False, False, 0)
        info.pack_start(Gtk.Label(label='·'), False, False, 0)
        self.tail_label = Gtk.Label(label='Últimas 200 líneas · server.log')
        self.tail_label.get_style_context().add_class('label-dim')
        info.pack_start(self.tail_label, False, False, 0)

        # ─── Visor ──────────────────────────────────────────────────
        self.view = Gtk.TextView(editable=False, cursor_visible=False)
        self.view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.view.set_monospace(True)
        self.view.set_left_margin(10)
        self.view.set_top_margin(10)
        self.view.set_right_margin(10)
        self.view.set_bottom_margin(10)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.view)
        self.box.pack_start(scroll, True, True, 0)

        # ─── Botones inferiores ─────────────────────────────────────
        bottom = Gtk.Box(spacing=8)
        self.box.pack_start(bottom, False, False, 0)
        bottom.pack_start(make_btn('📋 Copiar', 'btn-flat', small=True, on_click=lambda *_: self._copy()), False, False, 0)
        bottom.pack_start(make_btn('🗑 Limpiar log', 'btn-danger', small=True, on_click=lambda *_: self._clear()), False, False, 0)
        bottom.pack_start(Gtk.Label(label=''), True, True, 0)
        bottom.pack_start(make_btn('📂 Abrir carpeta', 'btn-flat', small=True, on_click=lambda *_: self._open_dir()), False, False, 0)

    def refresh(self):
        p = os.path.join(LOG_DIR, 'server.log')
        if os.path.exists(p):
            raw = sh(f'tail -n 200 "{p}" 2>/dev/null')
            content = '\n'.join(self._format_line(l) for l in raw.splitlines()) if raw else ''
            size = sh(f'stat -c %s "{p}" 2>/dev/null')
            if size:
                try:
                    sz = int(size)
                    self.tail_label.set_text(f'Últimas 200 líneas · {sz/1024:.1f} KB · server.log')
                except Exception:
                    pass
        else:
            content = '(sin logs todavía — el servicio aún no ha escrito nada)'
        buf = self.view.get_buffer()
        buf.set_text(content)
        # Auto-scroll al final
        end = buf.get_end_iter()
        mark = buf.create_mark(None, end, False)
        self.view.scroll_to_mark(mark, 0, False, 0, 0)

    _LEVEL_NAMES = {10: 'TRACE', 20: 'DEBUG', 30: 'INFO', 40: 'WARN', 50: 'ERROR', 60: 'FATAL'}

    def _format_line(self, line):
        """El server.log guarda JSON crudo de pino (una línea por evento) --
        lo reformateamos a 'HH:MM:SS [NIVEL] mensaje' para que sea legible."""
        try:
            entry = json.loads(line)
        except Exception:
            return line
        t = datetime.datetime.fromtimestamp(entry.get('time', 0) / 1000).strftime('%H:%M:%S')
        level = self._LEVEL_NAMES.get(entry.get('level'), '')
        msg = entry.get('msg', '')
        if entry.get('req'):
            msg = f"{entry['req'].get('method','')} {entry['req'].get('url','')} -> {entry.get('res',{}).get('statusCode','')}"
        extra = {k: v for k, v in entry.items()
                 if k not in ('time', 'level', 'msg', 'pid', 'hostname', 'req', 'res', 'responseTime')}
        extra_txt = f" {extra}" if extra else ''
        return f"{t}  [{level:<5}] {msg}{extra_txt}"

    def _copy(self):
        buf = self.view.get_buffer()
        start, end = buf.get_bounds()
        text = buf.get_text(start, end, True)
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(text, -1)
        self.parent.show_toast('Logs copiados al portapapeles')

    def _clear(self):
        dialog = Gtk.MessageDialog(
            transient_for=self.parent, flags=0,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text='¿Vaciar el archivo server.log? Esto borra el historial de logs.')
        if dialog.run() == Gtk.ResponseType.YES:
            sh(f'> "{os.path.join(LOG_DIR, "server.log")}" 2>/dev/null')
            self.refresh()
        dialog.destroy()

    def _open_dir(self):
        sh(f'xdg-open "{LOG_DIR}" 2>/dev/null &')


# ══════════════════════════════════════════════════════════════════════════════
# VENTANA PRINCIPAL — Sidebar + Área de contenido
# ══════════════════════════════════════════════════════════════════════════════

class DashboardWindow(Gtk.ApplicationWindow):
    """Ventana principal con sidebar lateral colapsable y área de contenido
    que intercambia entre los 9 módulos disponibles."""

    def __init__(self, app):
        super().__init__(application=app, title='Concentrados Monserrath — Panel del Servidor')
        self.set_default_size(1200, 800)
        self.set_size_request(900, 600)

        # CSS provider global
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        # ─── Header bar ─────────────────────────────────────────────
        # Los botones nativos de minimizar/maximizar/cerrar de la CSD de GTK
        # (set_show_close_button) dependen de que el gestor de ventanas
        # traduzca el clic en la accion real -- en algunas combinaciones
        # WM/tema ese enganche no responde (el boton se ve pero no hace
        # nada). Se implementan a mano, llamando directo a iconify()/
        # maximize()/close(): funcionan siempre, sin depender de eso.
        header = Gtk.HeaderBar()
        header.set_title('Concentrados Monserrath')
        header.set_subtitle('Panel de administración del servidor')
        header.set_show_close_button(False)
        header.props.spacing = 8
        # Doble clic en el espacio vacio del header tambien maximiza/restaura
        # -- comportamiento nativo esperado en cualquier escritorio.
        header.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        header.connect('button-press-event', self._on_header_click)

        # Botón colapsar sidebar
        self.toggle_btn = Gtk.Button(label='☰')
        self.toggle_btn.set_tooltip_text('Mostrar/ocultar menú lateral')
        self.toggle_btn.connect('clicked', lambda *_: self._toggle_sidebar())
        header.pack_start(self.toggle_btn)

        # Botones de ventana propios (min / maximizar-restaurar / cerrar).
        # pack_end() apila cada llamada mas cerca del centro que la
        # anterior -- se agrega PRIMERO para que quede en el borde real
        # (a la derecha del todo), como cualquier ventana nativa.
        win_controls = Gtk.Box(spacing=4)
        win_controls.get_style_context().add_class('win-controls')

        self.minimize_btn = Gtk.Button()
        self.minimize_btn.set_image(Gtk.Image.new_from_icon_name('window-minimize-symbolic', Gtk.IconSize.MENU))
        self.minimize_btn.set_tooltip_text('Minimizar')
        self.minimize_btn.connect('clicked', lambda *_: self.iconify())
        win_controls.pack_start(self.minimize_btn, False, False, 0)

        self.maximize_btn = Gtk.Button()
        self.maximize_btn.set_image(Gtk.Image.new_from_icon_name('window-maximize-symbolic', Gtk.IconSize.MENU))
        self.maximize_btn.set_tooltip_text('Maximizar/restaurar')
        self.maximize_btn.connect('clicked', lambda *_: self._toggle_maximize())
        win_controls.pack_start(self.maximize_btn, False, False, 0)

        self.close_btn = Gtk.Button()
        self.close_btn.set_image(Gtk.Image.new_from_icon_name('window-close-symbolic', Gtk.IconSize.MENU))
        self.close_btn.set_tooltip_text('Cerrar')
        self.close_btn.get_style_context().add_class('win-close')
        self.close_btn.connect('clicked', lambda *_: self.close())
        win_controls.pack_start(self.close_btn, False, False, 0)

        header.pack_end(win_controls)
        # Refleja el icono correcto (maximizar vs restaurar) cuando el
        # estado cambia por cualquier via -- boton propio, doble clic, o
        # atajos de teclado del sistema.
        self.connect('window-state-event', self._on_window_state_event)

        # Botón actualizar global
        self.refresh_btn = Gtk.Button(label='↻ Actualizar')
        self.refresh_btn.set_tooltip_text('Refrescar todos los módulos')
        self.refresh_btn.connect('clicked', lambda *_: self.refresh_all())
        header.pack_end(self.refresh_btn)

        # Indicador de conexión
        self.conn_indicator = Gtk.Box(spacing=6)
        self.conn_dot = Gtk.Box()
        self.conn_dot.set_size_request(9, 9)
        self.conn_dot.get_style_context().add_class('status-dot')
        self.conn_dot.get_style_context().add_class('dot-inactive')
        self.conn_label = Gtk.Label(label='Desconectado')
        self.conn_label.get_style_context().add_class('label-muted')
        self.conn_indicator.pack_start(self.conn_dot, False, False, 0)
        self.conn_indicator.pack_start(self.conn_label, False, False, 0)
        header.pack_end(self.conn_indicator)

        self.set_titlebar(header)

        # ─── Layout principal: sidebar | contenido ──────────────────
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.add(self.main_box)

        # Sidebar
        self.sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        self.sidebar.get_style_context().add_class('sidebar')
        self.sidebar.set_size_request(220, -1)
        self.main_box.pack_start(self.sidebar, False, False, 0)

        # Branding en sidebar
        brand_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        brand_box.set_margin_top(8)
        brand_box.set_margin_bottom(8)
        brand_box.set_margin_start(12)
        brand_box.set_margin_end(12)
        brand_lbl = Gtk.Label(label='GESTIÓN')
        brand_lbl.get_style_context().add_class('label-bold')
        brand_lbl.set_xalign(0)
        brand_box.pack_start(brand_lbl, False, False, 0)
        sub = Gtk.Label(label='Panel v3.0')
        sub.get_style_context().add_class('label-dim')
        sub.set_xalign(0)
        brand_box.pack_start(sub, False, False, 0)
        self.sidebar.pack_start(brand_box, False, False, 0)

        # Divider
        divider = Gtk.Box()
        divider.get_style_context().add_class('sidebar-divider')
        self.sidebar.pack_start(divider, False, False, 0)

        # Botones de módulos
        self.module_buttons = {}
        self.modules = {}

        # Stack con crossfade nativo -- reemplaza el pack/remove manual del
        # área de contenido. GTK3 no soporta animaciones CSS @keyframes,
        # pero Gtk.Stack trae su propia transición animada entre hijos.
        self.content_stack = Gtk.Stack()
        self.content_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.content_stack.set_transition_duration(180)
        # Sin esto Gtk.Stack mide TODOS los módulos por el más alto de los
        # 15 (tamaño homogéneo por defecto) y le regala esa altura sobrante
        # a cualquier hijo con expand=True dentro de cada módulo -- los
        # gráficos terminaban ocupando el doble o triple de su alto real.
        # Cada módulo ya vive dentro de un ScrolledWindow propio, así que
        # medirse por su propio contenido es seguro (no se corta nada).
        self.content_stack.set_vhomogeneous(False)
        self.content_stack.get_style_context().add_class('content')

        # Sección: OPERACIÓN
        op_label = Gtk.Label(label='OPERACIÓN')
        op_label.get_style_context().add_class('sidebar-section')
        op_label.set_xalign(0)
        self.sidebar.pack_start(op_label, False, False, 0)

        self._add_module('monitor', 'Monitoreo', MonitorModule)
        self._add_module('orders',  'Pedidos activos', OrdersModule, badge_key='orders')
        self._add_module('bot',     'Bot WhatsApp', BotModule)
        self._add_module('sales',   'Ventas', SalesModule)
        self._add_module('employees','Empleados', EmployeesModule)
        self._add_module('locations','Ubicaciones', LocationsModule)
        self._add_module('connections', 'Conexiones', ConnectionsModule)
        self._add_module('data',    'Datos', DataModule)

        # Sección: CONFIGURACIÓN
        cfg_label = Gtk.Label(label='CONFIGURACIÓN')
        cfg_label.get_style_context().add_class('sidebar-section')
        cfg_label.set_xalign(0)
        self.sidebar.pack_start(cfg_label, False, False, 0)

        self._add_module('brand',  'Marca', BrandModule)
        self._add_module('payments', 'Métodos de pago', PaymentsModule)
        self._add_module('config', 'Configuración', ConfigModule)
        self._add_module('security', 'Seguridad', SecurityModule)
        self._add_module('logs',   'Logs', LogsModule)

        # Spacer
        self.sidebar.pack_start(Gtk.Box(), True, True, 0)

        # Footer del sidebar con info de versión
        footer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        footer.set_margin_top(8)
        footer.set_margin_bottom(8)
        footer.set_margin_start(12)
        footer.set_margin_end(12)
        ver = Gtk.Label(label='v3.0 · GTK3 nativo')
        ver.get_style_context().add_class('label-dim')
        ver.set_xalign(0)
        footer.pack_start(ver, False, False, 0)
        svc_label = Gtk.Label(label='systemd: ' + SERVICE)
        svc_label.get_style_context().add_class('label-dim')
        svc_label.set_xalign(0)
        footer.pack_start(svc_label, False, False, 0)
        self.sidebar.pack_start(footer, False, False, 0)

        # ─── Área de contenido ──────────────────────────────────────
        self.content_scroll = Gtk.ScrolledWindow()
        self.content_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.content_scroll.get_style_context().add_class('content-scrolled')
        self.main_box.pack_start(self.content_scroll, True, True, 0)

        self.content_scroll.add(self.content_stack)

        # ─── Toast / status bar ─────────────────────────────────────
        self.status_bar = Gtk.Box()
        self.status_bar.get_style_context().add_class('sidebar')
        self.status_bar.set_size_request(-1, 28)
        self.status_label = Gtk.Label(label='')
        self.status_label.get_style_context().add_class('label-dim')
        self.status_label.set_xalign(0)
        self.status_label.set_margin_start(12)
        self.status_bar.pack_start(self.status_label, False, False, 0)

        # ─── Estado interno ─────────────────────────────────────────
        self.current_module = None
        self._sidebar_visible = True
        self._pulse_on = True

        # Los módulos ya fueron inicializados en _add_module()

        # Switch al primer módulo -- recién cuando la ventana esté REALMENTE
        # mapeada (evento map-event, no idle_add ni una llamada sincrónica
        # en __init__: ambas corren antes de que exista una ventana X real).
        # Llamado demasiado temprano, Gtk.Stack deja bien puesta la
        # propiedad visible-child-name (y el botón del sidebar queda
        # marcado activo) pero lo que se pinta en pantalla se queda
        # mostrando el primer hijo agregado ('monitor'), sin importar cuál
        # se pidió -- por eso 'monitor' siempre "funcionaba" (coincidía por
        # accidente) y cualquier otro módulo no. Sin transición para este
        # primer despliegue (nada que crossfadear todavía); CROSSFADE queda
        # activo para la navegación real del usuario desde acá en adelante.
        self.content_stack.set_transition_type(Gtk.StackTransitionType.NONE)
        self._initial_module_shown = False
        def _show_initial_module(*_a):
            # map-event puede repetirse (minimizar/restaurar) -- solo debe
            # forzar 'monitor' la primerísima vez, nunca pisar la
            # navegación real del usuario en restauraciones posteriores.
            if self._initial_module_shown:
                return False
            self._initial_module_shown = True
            self.switch_module('monitor')
            self.content_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
            return False
        self.connect('map-event', _show_initial_module)

        # Auto-refresh cada 10s
        GLib.timeout_add_seconds(10, self._tick)
        # Pulse cada 800ms en indicadores
        GLib.timeout_add(800, self._pulse)

        # Refresh inicial
        GLib.idle_add(self.refresh_all)

    def _add_module(self, key, label, ModuleClass, badge_key=None):
        """Agrega un botón al sidebar y registra el módulo instanciado."""
        # Gtk.Button(label=...) centra su Label interno -- con textos de
        # largo distinto ("Monitoreo" vs "Configuración") cada boton
        # arranca en una x distinta y el menu se ve descuadrado. Se arma
        # el Label a mano, alineado a la izquierda, como cualquier menu
        # de navegacion nativo.
        btn = Gtk.Button()
        lbl = Gtk.Label(label=label)
        lbl.set_xalign(0)
        btn.add(lbl)
        btn.get_style_context().add_class('sidebar-btn')
        btn.set_relief(Gtk.ReliefStyle.NONE)
        btn.connect('clicked', lambda *_: self.switch_module(key))
        self.sidebar.pack_start(btn, False, False, 1)
        self.module_buttons[key] = btn
        # Instanciar módulo y registrarlo en el stack -- su .box es un hijo
        # nombrado más, Gtk.Stack decide solo cuál mostrar. OJO: no llamar
        # show_all() acá -- Gtk.Stack controla la visibilidad de sus hijos
        # el mismo (oculta todos menos el activo); forzar visible=True a
        # mano en cada uno pelea con esa lógica interna y el módulo que
        # terminaba "ganando" como visible salía no-determinista entre
        # corridas (una vez Pedidos, otra Conexiones, nunca el que se
        # pedía con switch_module). El show_all() de la ventana en main()
        # ya se encarga de revelar el árbol completo al final.
        self.modules[key] = ModuleClass(self)
        self.content_stack.add_named(self.modules[key].box, key)

    def switch_module(self, name):
        """Cambia el módulo visible en el área de contenido (crossfade nativo)."""
        if name not in self.modules:
            return
        # Marcar botón activo
        for key, btn in self.module_buttons.items():
            if key == name:
                btn.get_style_context().add_class('active')
            else:
                btn.get_style_context().remove_class('active')
        self.content_stack.set_visible_child_name(name)
        self.current_module = name
        # Refrescar el módulo recién mostrado
        try:
            self.modules[name].refresh()
        except Exception as e:
            print(f'[dashboard] refresh {name}: {e}', file=sys.stderr)

    def _toggle_maximize(self):
        if self.is_maximized():
            self.unmaximize()
        else:
            self.maximize()

    def _on_header_click(self, widget, event):
        """Doble clic en el espacio vacio del header = maximizar/restaurar
        (comportamiento nativo esperado). Ignora clics sobre los botones
        propios -- esos ya tienen su propio 'clicked'."""
        if event.type == Gdk.EventType._2BUTTON_PRESS and event.button == 1:
            self._toggle_maximize()
            return True
        return False

    def _on_window_state_event(self, widget, event):
        """Actualiza el icono del boton maximizar/restaurar segun el
        estado real de la ventana (por si cambia por atajos de teclado
        del sistema o el doble clic, no solo por el boton propio)."""
        maximized = bool(event.new_window_state & Gdk.WindowState.MAXIMIZED)
        icon = 'window-restore-symbolic' if maximized else 'window-maximize-symbolic'
        self.maximize_btn.set_image(Gtk.Image.new_from_icon_name(icon, Gtk.IconSize.MENU))
        self.maximize_btn.set_tooltip_text('Restaurar' if maximized else 'Maximizar')

    def _toggle_sidebar(self):
        """Colapsa/expande el sidebar lateral."""
        self._sidebar_visible = not self._sidebar_visible
        self.sidebar.set_visible(self._sidebar_visible)
        # Reajustar tamaño mínimo cuando está oculto
        if self._sidebar_visible:
            self.sidebar.set_size_request(220, -1)
        else:
            self.sidebar.set_size_request(0, -1)

    def _tick(self):
        """Refresh automático cada 10s."""
        self.refresh_all()
        return True

    def _pulse(self):
        """Sutil respiración en el dot de conexión cuando el servicio está activo."""
        self._pulse_on = not self._pulse_on
        ctx = self.conn_dot.get_style_context()
        if ctx.has_class('dot-active'):
            self.conn_dot.set_opacity(1.0 if self._pulse_on else 0.55)
        else:
            self.conn_dot.set_opacity(1.0)
        return True

    def refresh_all(self):
        """Refresca el módulo actual + indicador de conexión."""
        # Indicador de conexión al servidor
        active = sh(f'systemctl is-active {SERVICE} 2>/dev/null') == 'active'
        ctx = self.conn_dot.get_style_context()
        for cls in ('dot-active', 'dot-inactive', 'dot-failed'):
            ctx.remove_class(cls)
        ctx.add_class('dot-active' if active else 'dot-failed')
        self.conn_label.set_text('En línea' if active else 'Servicio caído')

        # Refrescar módulo actual
        if self.current_module:
            try:
                self.modules[self.current_module].refresh()
            except Exception as e:
                print(f'[dashboard] refresh_all {self.current_module}: {e}', file=sys.stderr)

    def show_toast(self, msg):
        """Muestra un mensaje temporal en la barra de estado."""
        self.status_label.set_text(msg)
        GLib.timeout_add_seconds(4, lambda: (self.status_label.set_text(''), False)[1])

    def _appdata_dir(self):
        """Devuelve el APPDATA configurado en el servicio systemd."""
        env = sh(f"systemctl show {SERVICE} -p Environment --value")
        m = re.search(r'APPDATA=(\S+)', env)
        return m.group(1) if m else None


# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

def main():
    app = Gtk.Application(application_id='com.concentrados.monserrath.dashboard',
                          flags=0)
    app.connect('activate', lambda a: DashboardWindow(a).show_all())
    app.run(None)


if __name__ == '__main__':
    main()
