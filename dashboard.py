#!/usr/bin/env python3
# ================================================================
#  dashboard.py — Panel nativo de escritorio (GTK3) para
#  Concentrados Monserrath: monitoreo, ventas, marca, configuracion
#  y seguridad del servidor, con datos reales (systemd + SQLite).
#
#  Se lanza desde deploy-linux.sh (--menu), que ya corre como root
#  y deja DISPLAY/XAUTHORITY listos para dibujar en la sesion real.
# ================================================================
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
import subprocess, sqlite3, os, re, sys, datetime, secrets

SERVICE = os.environ.get('DEPLOY_SERVICE', 'pedidos-bot')
TUNNEL_SERVICE = os.environ.get('DEPLOY_TUNNEL_SERVICE', 'pedidos-bot-tunnel')
PROJ = os.environ.get('DEPLOY_PROJ', os.path.dirname(os.path.abspath(__file__)))
ENV_FILE = os.path.join(PROJ, 'server', '.env')
LOG_DIR = os.environ.get('DEPLOY_LOG_DIR', '/var/log/pedidos-bot')

PRIMARY_DEFAULT = '#2D5016'
ACCENT_DEFAULT  = '#D4800A'

PRESETS = [
    ('Olivo & Ambar',    '#2D5016', '#D4800A'),
    ('Bosque & Cuero',   '#1B4332', '#B08968'),
    ('Slate & Terracota','#264653', '#E76F51'),
    ('Vino & Oro',       '#5C1A28', '#C9A227'),
    ('Azul Corporativo', '#1B3A6B', '#3D8BFD'),
    ('Carbon & Lima',    '#22302B', '#8AB833'),
]

# Paleta "admin console" — deliberadamente neutra/tecnica (slate + OLED),
# distinta de la paleta de marca del negocio: esta es una herramienta de
# operacion interna, no la app que ve el cliente final.
BG        = '#020617'
SURFACE   = '#0F172A'
SURFACE_2 = '#1E293B'
BORDER    = '#334155'
FG        = '#F8FAFC'
FG_MUTED  = '#94A3B8'
ACCENT    = '#22C55E'   # positivo / activo
WARNING   = '#F59E0B'
DANGER    = '#EF4444'
INFO      = '#3B82F6'

CSS = f"""
* {{ font-family: 'Inter', 'Fira Sans', 'Cantarell', sans-serif; }}
.mono {{ font-family: 'Fira Code', 'JetBrains Mono', monospace; }}

window {{ background-color: {BG}; }}

headerbar {{
    background-color: {SURFACE};
    border-bottom: 1px solid {BORDER};
    box-shadow: none;
    color: {FG};
}}
headerbar label {{ color: {FG}; }}
headerbar .title {{ font-weight: 700; letter-spacing: 0.2px; font-size: 14px; }}
headerbar .subtitle {{ color: {FG_MUTED}; font-size: 11px; }}
headerbar button {{
    background: transparent;
    border: 1px solid {BORDER};
    border-radius: 6px;
    color: {FG};
    padding: 4px 12px;
    transition: background 150ms ease, border-color 150ms ease;
}}
headerbar button:hover {{ background: {SURFACE_2}; border-color: {FG_MUTED}; }}

notebook > header {{ background-color: {SURFACE}; border-bottom: 1px solid {BORDER}; }}
notebook > header > tabs > tab {{
    padding: 10px 18px;
    color: {FG_MUTED};
    font-weight: 500;
    font-size: 12px;
    letter-spacing: 0.4px;
    border-bottom: 2px solid transparent;
    transition: color 150ms ease, border-color 150ms ease;
}}
notebook > header > tabs > tab:checked {{
    color: {FG};
    border-bottom: 2px solid {ACCENT};
    background-color: shade({SURFACE}, 1.15);
}}
notebook > header > tabs > tab:hover {{ color: {FG}; }}
notebook stack {{ background-color: {BG}; }}

.section-title {{
    color: {FG_MUTED};
    font-weight: 600;
    font-size: 11px;
    letter-spacing: 1px;
}}

.stat-card {{
    background-color: {SURFACE};
    border-radius: 8px;
    border: 1px solid {BORDER};
    padding: 14px 16px;
    box-shadow: 0 1px 2px rgba(0,0,0,0.4);
    transition: border-color 150ms ease;
}}
.stat-card:hover {{ border-color: {FG_MUTED}; }}
.stat-label {{ color: {FG_MUTED}; font-size: 11px; letter-spacing: 0.3px; }}
.stat-value {{ color: {FG}; font-size: 22px; font-weight: 700; }}

.status-dot {{ border-radius: 999px; min-width: 8px; min-height: 8px; }}
.dot-active   {{ background-color: {ACCENT}; }}
.dot-inactive {{ background-color: {FG_MUTED}; }}
.dot-failed   {{ background-color: {DANGER}; }}

button.action-btn {{
    border-radius: 6px;
    padding: 8px 16px;
    font-weight: 600;
    font-size: 12px;
    letter-spacing: 0.3px;
    transition: background 150ms ease, border-color 150ms ease;
}}
.btn-primary {{ background-color: {ACCENT}; color: {BG}; border: 1px solid {ACCENT}; }}
.btn-primary:hover {{ background-color: shade({ACCENT}, 1.1); }}
.btn-warn {{ background-color: transparent; color: {WARNING}; border: 1px solid {WARNING}; }}
.btn-warn:hover {{ background-color: rgba(245,158,11,0.12); }}
.btn-danger {{ background-color: transparent; color: {DANGER}; border: 1px solid {DANGER}; }}
.btn-danger:hover {{ background-color: rgba(239,68,68,0.12); }}
.btn-flat {{ background-color: {SURFACE_2}; color: {FG}; border: 1px solid {BORDER}; }}
.btn-flat:hover {{ background-color: shade({SURFACE_2}, 1.2); }}

entry {{
    background-color: {SURFACE_2};
    color: {FG};
    border-radius: 6px;
    border: 1px solid {BORDER};
    padding: 7px 10px;
}}
entry:focus {{ border: 1px solid {ACCENT}; }}

label {{ color: {FG}; }}
.label-muted {{ color: {FG_MUTED}; font-size: 12px; }}

textview {{ background-color: {SURFACE}; }}
textview text {{ background-color: {SURFACE}; color: #CBD5E1; }}

scrolledwindow, treeview {{ background-color: {SURFACE}; color: {FG}; }}
treeview header button {{
    background-color: {SURFACE_2};
    color: {FG_MUTED};
    border: none;
    border-bottom: 1px solid {BORDER};
    font-size: 11px;
    font-weight: 600;
    padding: 8px;
}}
treeview:selected {{ background-color: {SURFACE_2}; }}

separator {{ background-color: {BORDER}; min-height: 1px; }}

.preset-swatch {{
    border-radius: 6px;
    border: 1px solid {BORDER};
    background-color: {SURFACE};
    transition: border-color 150ms ease;
}}
.preset-swatch:hover {{ border-color: {FG_MUTED}; }}
.preset-selected {{ border: 2px solid {ACCENT}; }}
"""


def sh(cmd):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=6).stdout.strip()
    except Exception:
        return ''


def env_get(key):
    if not os.path.exists(ENV_FILE):
        return ''
    with open(ENV_FILE) as f:
        for line in f:
            if line.startswith(key + '='):
                return line.strip().split('=', 1)[1]
    return ''


def env_set(key, value):
    lines = []
    found = False
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            lines = f.readlines()
    for i, line in enumerate(lines):
        if line.startswith(key + '='):
            lines[i] = f'{key}={value}\n'
            found = True
            break
    if not found:
        lines.append(f'{key}={value}\n')
    with open(ENV_FILE, 'w') as f:
        f.writelines(lines)


def db_path():
    p = env_get('DB_PATH')
    return p if p else os.path.join(PROJ, 'server', 'pedidos.db')


def query(sql, params=()):
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
    h = h.lstrip('#')
    if len(h) != 6:
        return (0.2, 0.3, 0.1)
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


class Chart(Gtk.DrawingArea):
    """Grafico dibujado a mano con Cairo (barras o linea) -- cero dependencias
    externas de graficacion, suficiente para vistas de 7-14 dias."""
    def __init__(self, title, kind='bar', color=None):
        super().__init__()
        self.title = title
        self.kind = kind
        self.color = color or hex_to_rgb(ACCENT)
        self.data = []
        self.set_size_request(260, 180)
        self.connect('draw', self.on_draw)

    def set_data(self, data):
        self.data = data
        self.queue_draw()

    def on_draw(self, widget, cr):
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()
        surface_rgb = hex_to_rgb(SURFACE)
        border_rgb = hex_to_rgb(BORDER)
        muted_rgb = hex_to_rgb(FG_MUTED)

        cr.set_source_rgb(*surface_rgb)
        cr.paint()
        cr.set_source_rgb(*border_rgb)
        cr.set_line_width(1)
        cr.rectangle(0.5, 0.5, w - 1, h - 1)
        cr.stroke()

        cr.set_source_rgb(*muted_rgb)
        cr.select_font_face('Sans', 0, 0)
        cr.set_font_size(11)
        cr.move_to(14, 20)
        cr.show_text(self.title.upper())

        if not any(v for _, v in self.data):
            cr.set_source_rgba(*muted_rgb, 0.8)
            cr.set_font_size(11)
            cr.move_to(14, h / 2)
            cr.show_text('Sin datos todavia — apareceran con el primer pedido')
            return

        pad_left, pad_bottom, pad_top = 14, 26, 34
        chart_h = h - pad_bottom - pad_top
        chart_w = w - pad_left - 14
        maxval = max((v for _, v in self.data), default=1) or 1
        n = len(self.data) or 1
        bw = chart_w / n

        # Gridlines sutiles horizontales (referencia visual, no compiten con datos)
        for frac in (0.25, 0.5, 0.75, 1.0):
            gy = pad_top + chart_h * (1 - frac)
            cr.set_source_rgba(*border_rgb, 0.5)
            cr.set_line_width(1)
            cr.move_to(pad_left, gy)
            cr.line_to(pad_left + chart_w, gy)
            cr.stroke()

        if self.kind == 'bar':
            for i, (label, val) in enumerate(self.data):
                bh = (val / maxval) * chart_h if maxval else 0
                x = pad_left + i * bw + bw * 0.2
                y = pad_top + (chart_h - bh)
                cr.set_source_rgb(*self.color)
                cr.rectangle(x, y, bw * 0.6, bh)
                cr.fill()
                cr.set_source_rgb(*muted_rgb)
                cr.set_font_size(9)
                cr.move_to(x, h - pad_bottom + 13)
                cr.show_text(label)
        else:  # line
            pts = []
            for i, (label, val) in enumerate(self.data):
                x = pad_left + i * bw + bw / 2
                y = pad_top + (chart_h - (val / maxval) * chart_h if maxval else chart_h)
                pts.append((x, y, label))
            cr.set_source_rgb(*self.color)
            cr.set_line_width(2)
            for i, (x, y, _) in enumerate(pts):
                cr.line_to(x, y) if i else cr.move_to(x, y)
            cr.stroke()
            for x, y, label in pts:
                cr.arc(x, y, 2.5, 0, 2 * 3.14159)
                cr.fill()
                cr.set_source_rgb(*muted_rgb)
                cr.set_font_size(9)
                cr.move_to(x - 8, h - pad_bottom + 13)
                cr.show_text(label)
                cr.set_source_rgb(*self.color)


def stat_card(label, value_widget_holder, dot_holder=None):
    """Card estilo admin-console: etiqueta muted + valor grande. Si dot_holder
    se pasa (una lista), se agrega un indicador de estado circular editable
    via clase CSS (dot-active/dot-inactive/dot-failed) en vez de un emoji."""
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    box.get_style_context().add_class('stat-card')

    lbl_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
    lbl = Gtk.Label(label=label.upper(), xalign=0)
    lbl.get_style_context().add_class('stat-label')
    lbl_row.pack_start(lbl, True, True, 0)
    if dot_holder is not None:
        dot = Gtk.Box()
        dot.set_size_request(8, 8)
        dot.get_style_context().add_class('status-dot')
        dot.get_style_context().add_class('dot-inactive')
        lbl_row.pack_start(dot, False, False, 2)
        dot_holder.append(dot)
    box.pack_start(lbl_row, False, False, 0)

    val = Gtk.Label(label='—', xalign=0)
    val.get_style_context().add_class('stat-value')
    val.get_style_context().add_class('mono')
    box.pack_start(val, False, False, 0)
    value_widget_holder.append(val)
    return box


class DashboardWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title='Concentrados Monserrath — Panel del Servidor')
        self.set_default_size(920, 640)
        self.set_resizable(True)
        self.set_size_request(720, 480)  # minimo -- evita que las cards/graficos se aplasten y se vean corruptos

        screen = Gdk.Screen.get_default()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(vbox)

        header = Gtk.HeaderBar()
        header.set_title('CONCENTRADOS MONSERRATH')
        header.set_subtitle('Panel de administracion del servidor')
        header.set_show_close_button(True)
        refresh_btn = Gtk.Button(label='ACTUALIZAR')
        refresh_btn.connect('clicked', lambda *_: self.refresh_all())
        header.pack_end(refresh_btn)
        self.set_titlebar(header)

        notebook = Gtk.Notebook()
        vbox.pack_start(notebook, True, True, 0)

        notebook.append_page(self._scrollable(self.build_monitor_tab()), Gtk.Label(label='MONITOREO'))
        notebook.append_page(self._scrollable(self.build_sales_tab()), Gtk.Label(label='VENTAS'))
        notebook.append_page(self._scrollable(self.build_brand_tab()), Gtk.Label(label='MARCA'))
        notebook.append_page(self._scrollable(self.build_config_tab()), Gtk.Label(label='CONFIGURACION'))
        notebook.append_page(self.build_security_tab(), Gtk.Label(label='SEGURIDAD'))
        notebook.append_page(self.build_logs_tab(), Gtk.Label(label='LOGS'))

        self._pulse_on = True
        self.refresh_all()
        GLib.timeout_add_seconds(5, self._tick)
        GLib.timeout_add(700, self._pulse)

    def _tick(self):
        self.refresh_all()
        return True

    def _pulse(self):
        # Sutil respiracion de opacidad en el indicador de estado cuando el
        # servicio esta activo -- unica animacion del panel, discreta.
        self._pulse_on = not self._pulse_on
        if hasattr(self, 'dot_status') and getattr(self, '_status_class', '') == 'pulse-active':
            self.dot_status.set_opacity(1.0 if self._pulse_on else 0.5)
        elif hasattr(self, 'dot_status'):
            self.dot_status.set_opacity(1.0)
        return True

    def _scrollable(self, widget):
        """Envuelve una pestaña en scroll vertical -- si la ventana se achica,
        el contenido no se aplasta ni se superpone, simplemente aparece scroll."""
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(widget)
        return scroll

    # ── Tab: Monitoreo ────────────────────────────────────────
    def build_monitor_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_border_width(18)

        title = Gtk.Label(label='ESTADO EN VIVO', xalign=0)
        title.get_style_context().add_class('section-title')
        box.pack_start(title, False, False, 0)

        cards = Gtk.FlowBox()
        cards.set_selection_mode(Gtk.SelectionMode.NONE)
        cards.set_max_children_per_line(3)
        cards.set_row_spacing(10)
        cards.set_column_spacing(10)
        box.pack_start(cards, False, False, 0)

        holders = {}
        dots = {}
        specs = [
            ('status', 'Servicio Node', True), ('tunnel', 'Tunel Cloudflare', True),
            ('uptime', 'Activo desde', False), ('mem', 'Memoria', False),
            ('orders', 'Pedidos (hoy / total)', False), ('msgs', 'Mensajes (hoy / total)', False),
        ]
        for key, label, has_dot in specs:
            hold, dot_hold = [], ([] if has_dot else None)
            cards.add(stat_card(label, hold, dot_hold))
            holders[key] = hold[0]
            if has_dot:
                dots[key] = dot_hold[0]
        self.lbl_status, self.lbl_tunnel = holders['status'], holders['tunnel']
        self.lbl_uptime, self.lbl_mem = holders['uptime'], holders['mem']
        self.lbl_orders, self.lbl_msgs = holders['orders'], holders['msgs']
        self.dot_status, self.dot_tunnel = dots['status'], dots['tunnel']

        charts_title = Gtk.Label(label='ACTIVIDAD (ULTIMOS 7 DIAS)', xalign=0)
        charts_title.get_style_context().add_class('section-title')
        box.pack_start(charts_title, False, False, 0)

        charts = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.pack_start(charts, True, True, 0)
        self.chart_orders = Chart('Pedidos por dia', 'bar', hex_to_rgb(ACCENT))
        self.chart_msgs = Chart('Mensajes por dia', 'line', hex_to_rgb(INFO))
        charts.pack_start(self.chart_orders, True, True, 0)
        charts.pack_start(self.chart_msgs, True, True, 0)

        actions = Gtk.Box(spacing=8)
        box.pack_start(actions, False, False, 0)
        for label, cmd, css in [
            ('REINICIAR', f'systemctl restart {SERVICE}', 'btn-primary'),
            ('DETENER', f'systemctl stop {SERVICE}', 'btn-warn'),
            ('INICIAR', f'systemctl start {SERVICE}', 'btn-primary'),
        ]:
            btn = Gtk.Button(label=label)
            btn.get_style_context().add_class('action-btn')
            btn.get_style_context().add_class(css)
            btn.connect('clicked', lambda _w, c=cmd: self._run_and_refresh(c))
            actions.pack_start(btn, False, False, 0)

        return box

    def _run_and_refresh(self, cmd):
        sh(cmd)
        GLib.timeout_add(1500, lambda: (self.refresh_all(), False)[1])

    # ── Tab: Ventas ───────────────────────────────────────────
    def build_sales_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_border_width(18)

        title = Gtk.Label(label='RESUMEN DE VENTAS', xalign=0)
        title.get_style_context().add_class('section-title')
        box.pack_start(title, False, False, 0)

        cards = Gtk.FlowBox()
        cards.set_selection_mode(Gtk.SelectionMode.NONE)
        cards.set_max_children_per_line(4)
        cards.set_row_spacing(10)
        cards.set_column_spacing(10)
        box.pack_start(cards, False, False, 0)

        holders = {}
        for key, label in [
            ('sales_today', 'Ventas hoy'), ('avg_ticket', 'Ticket promedio'),
            ('cancelled', '% Cancelados'), ('delivered', 'Entregados (total)'),
        ]:
            hold = []
            cards.add(stat_card(label, hold))
            holders[key] = hold[0]
        self.lbl_sales_today = holders['sales_today']
        self.lbl_avg_ticket = holders['avg_ticket']
        self.lbl_cancelled = holders['cancelled']
        self.lbl_delivered = holders['delivered']

        chart_title = Gtk.Label(label='INGRESOS POR DIA (ULTIMOS 7)', xalign=0)
        chart_title.get_style_context().add_class('section-title')
        box.pack_start(chart_title, False, False, 0)
        self.chart_sales = Chart('Ingresos ($)', 'bar', hex_to_rgb(ACCENT))
        box.pack_start(self.chart_sales, False, False, 0)

        top_title = Gtk.Label(label='TOP PRODUCTOS VENDIDOS', xalign=0)
        top_title.get_style_context().add_class('section-title')
        box.pack_start(top_title, False, False, 0)

        self.top_products_store = Gtk.ListStore(str, str)
        tree = Gtk.TreeView(model=self.top_products_store)
        for i, colname in enumerate(['Producto', 'Unidades vendidas']):
            col = Gtk.TreeViewColumn(colname, Gtk.CellRendererText(), text=i)
            tree.append_column(col)
        scroll = Gtk.ScrolledWindow()
        scroll.set_size_request(-1, 140)
        scroll.add(tree)
        box.pack_start(scroll, True, True, 0)
        return box

    # ── Tab: Marca ────────────────────────────────────────────
    def build_brand_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_border_width(18)

        title = Gtk.Label(label='PERSONALIZACION DE MARCA', xalign=0)
        title.get_style_context().add_class('section-title')
        box.pack_start(title, False, False, 0)

        info = Gtk.Label(
            label='Cambia la paleta y el nombre que ven tus clientes en la app — se aplica al instante, sin reiniciar el servidor.',
            xalign=0, wrap=True)
        box.pack_start(info, False, False, 0)

        name_box = Gtk.Box(spacing=8)
        box.pack_start(name_box, False, False, 4)
        name_box.pack_start(Gtk.Label(label='Nombre de marca:'), False, False, 0)
        self.entry_brand_name = Gtk.Entry()
        self.entry_brand_name.set_width_chars(28)
        name_box.pack_start(self.entry_brand_name, False, False, 0)

        presets_title = Gtk.Label(label='PALETAS', xalign=0)
        presets_title.get_style_context().add_class('section-title')
        box.pack_start(presets_title, False, False, 0)

        self.preset_buttons = []
        presets_box = Gtk.FlowBox()
        presets_box.set_selection_mode(Gtk.SelectionMode.NONE)
        presets_box.set_max_children_per_line(6)
        box.pack_start(presets_box, False, False, 0)
        for name, primary, accent in PRESETS:
            btn = self._make_preset_swatch(name, primary, accent)
            presets_box.add(btn)

        custom_title = Gtk.Label(label='PERSONALIZADO (HEX)', xalign=0)
        custom_title.get_style_context().add_class('section-title')
        box.pack_start(custom_title, False, False, 0)
        custom_box = Gtk.Box(spacing=8)
        box.pack_start(custom_box, False, False, 0)
        custom_box.pack_start(Gtk.Label(label='Primario'), False, False, 0)
        self.entry_primary = Gtk.Entry()
        self.entry_primary.set_width_chars(10)
        custom_box.pack_start(self.entry_primary, False, False, 0)
        custom_box.pack_start(Gtk.Label(label='Acento'), False, False, 0)
        self.entry_accent = Gtk.Entry()
        self.entry_accent.set_width_chars(10)
        custom_box.pack_start(self.entry_accent, False, False, 0)

        preview_title = Gtk.Label(label='VISTA PREVIA', xalign=0)
        preview_title.get_style_context().add_class('section-title')
        box.pack_start(preview_title, False, False, 0)
        self.brand_preview = Gtk.DrawingArea()
        self.brand_preview.set_size_request(-1, 70)
        self.brand_preview.connect('draw', self._draw_brand_preview)
        box.pack_start(self.brand_preview, False, False, 0)

        logo_box = Gtk.Box(spacing=8)
        box.pack_start(logo_box, False, False, 4)
        logo_btn = Gtk.Button(label='CAMBIAR LOGO')
        logo_btn.get_style_context().add_class('action-btn')
        logo_btn.get_style_context().add_class('btn-flat')
        logo_btn.connect('clicked', self.on_pick_logo)
        logo_box.pack_start(logo_btn, False, False, 0)
        self.logo_status = Gtk.Label(label='')
        logo_box.pack_start(self.logo_status, False, False, 0)

        save_btn = Gtk.Button(label='GUARDAR MARCA')
        save_btn.get_style_context().add_class('action-btn')
        save_btn.get_style_context().add_class('btn-primary')
        save_btn.connect('clicked', self.on_save_brand)
        box.pack_start(save_btn, False, False, 8)

        self.entry_primary.connect('changed', lambda *_: self.brand_preview.queue_draw())
        self.entry_accent.connect('changed', lambda *_: self.brand_preview.queue_draw())
        return box

    def _make_preset_swatch(self, name, primary, accent):
        btn = Gtk.Button()
        btn.get_style_context().add_class('preset-swatch')
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_size_request(72, 60)
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
        box.pack_start(lbl, False, False, 0)
        btn.add(box)
        btn.connect('clicked', lambda *_: self._apply_preset(primary, accent))
        return btn

    def _apply_preset(self, primary, accent):
        self.entry_primary.set_text(primary)
        self.entry_accent.set_text(accent)

    def _draw_brand_preview(self, widget, cr):
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()
        primary = self.entry_primary.get_text() or PRIMARY_DEFAULT
        accent = self.entry_accent.get_text() or ACCENT_DEFAULT
        r, g, b = hex_to_rgb(primary)
        cr.set_source_rgb(r, g, b)
        cr.rectangle(0, 0, w, h)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.select_font_face('Sans', 0, 1)
        cr.set_font_size(14)
        cr.move_to(14, h / 2 - 6)
        cr.show_text(self.entry_brand_name.get_text() or 'Nombre de tu negocio')
        ra, ga, ba = hex_to_rgb(accent)
        cr.set_source_rgb(ra, ga, ba)
        cr.rectangle(w - 90, h / 2 - 4, 76, 24)
        cr.fill()
        cr.set_source_rgb(1, 1, 1)
        cr.set_font_size(11)
        cr.move_to(w - 82, h / 2 + 12)
        cr.show_text('Boton')

    def on_pick_logo(self, _btn):
        dialog = Gtk.FileChooserDialog(
            title='Elegi un logo', parent=self,
            action=Gtk.FileChooserAction.OPEN)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                            Gtk.STOCK_OPEN, Gtk.ResponseType.OK)
        filt = Gtk.FileFilter()
        filt.set_name('Imagenes')
        filt.add_mime_type('image/png')
        filt.add_mime_type('image/jpeg')
        dialog.add_filter(filt)
        if dialog.run() == Gtk.ResponseType.OK:
            src = dialog.get_filename()
            ext = 'png' if src.lower().endswith('png') else 'jpg'
            appdata = self._appdata_dir()
            if appdata:
                dest_dir = os.path.join(appdata, 'pedidos-bot', 'branding')
                os.makedirs(dest_dir, exist_ok=True)
                fname = f'logo_{int(datetime.datetime.now().timestamp())}.{ext}'
                dest = os.path.join(dest_dir, fname)
                sh(f'cp "{src}" "{dest}"')
                setting_set('theme_logo_url', fname)
                self.logo_status.set_text(f'Logo actualizado: {fname}')
            else:
                self.logo_status.set_text('No se encontro APPDATA del servicio')
        dialog.destroy()

    def _appdata_dir(self):
        env = sh(f"systemctl show {SERVICE} -p Environment --value")
        m = re.search(r'APPDATA=(\S+)', env)
        return m.group(1) if m else None

    def on_save_brand(self, _btn):
        primary = self.entry_primary.get_text().strip() or PRIMARY_DEFAULT
        accent = self.entry_accent.get_text().strip() or ACCENT_DEFAULT
        name = self.entry_brand_name.get_text().strip()
        setting_set('theme_primary', primary)
        setting_set('theme_accent', accent)
        if name:
            setting_set('theme_name', name)
        self.logo_status.set_text('Marca guardada — la app la toma en el proximo login.')

    # ── Tab: Configuracion ────────────────────────────────────
    def build_config_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_border_width(18)

        title = Gtk.Label(label='CONEXION Y ACCESO', xalign=0)
        title.get_style_context().add_class('section-title')
        box.pack_start(title, False, False, 0)

        grid = Gtk.Grid(column_spacing=12, row_spacing=10)
        box.pack_start(grid, False, False, 0)

        self.entry_port = self._config_field(grid, 0, 'Puerto', env_get('PORT') or '3000')
        self.entry_phone = self._config_field(grid, 1, 'Numero WhatsApp (BOT_PHONE)', env_get('BOT_PHONE'))
        self.entry_domain = self._config_field(grid, 2, 'Dominio propio (nginx+HTTPS)', env_get('SERVER_DOMAIN'))

        save_btn = Gtk.Button(label='GUARDAR Y REINICIAR SERVICIO')
        save_btn.get_style_context().add_class('action-btn')
        save_btn.get_style_context().add_class('btn-primary')
        save_btn.connect('clicked', self.on_save_config)
        box.pack_start(save_btn, False, False, 8)

        sec_title = Gtk.Label(label='ACCIONES SENSIBLES', xalign=0)
        sec_title.get_style_context().add_class('section-title')
        box.pack_start(sec_title, False, False, 8)

        row2 = Gtk.Box(spacing=8)
        box.pack_start(row2, False, False, 0)
        regen_btn = Gtk.Button(label='REGENERAR SECRETOS')
        regen_btn.get_style_context().add_class('action-btn')
        regen_btn.get_style_context().add_class('btn-warn')
        regen_btn.connect('clicked', self.on_regen_secrets)
        row2.pack_start(regen_btn, False, False, 0)

        relink_btn = Gtk.Button(label='RE-VINCULAR WHATSAPP')
        relink_btn.get_style_context().add_class('action-btn')
        relink_btn.get_style_context().add_class('btn-warn')
        relink_btn.connect('clicked', self.on_relink_whatsapp)
        row2.pack_start(relink_btn, False, False, 0)

        self.config_status = Gtk.Label(label='')
        box.pack_start(self.config_status, False, False, 8)
        return box

    def _config_field(self, grid, row, label_text, value):
        lbl = Gtk.Label(label=label_text, xalign=0)
        entry = Gtk.Entry()
        entry.set_text(value or '')
        entry.set_width_chars(30)
        grid.attach(lbl, 0, row, 1, 1)
        grid.attach(entry, 1, row, 1, 1)
        return entry

    def on_save_config(self, _btn):
        env_set('PORT', self.entry_port.get_text().strip() or '3000')
        env_set('BOT_PHONE', re.sub(r'\D', '', self.entry_phone.get_text()))
        env_set('SERVER_DOMAIN', self.entry_domain.get_text().strip())
        sh(f'systemctl restart {SERVICE}')
        self.config_status.set_text('Guardado. Servicio reiniciando…')
        GLib.timeout_add(1500, lambda: (self.refresh_all(), False)[1])

    def on_regen_secrets(self, _btn):
        env_set('API_KEY', secrets.token_hex(32))
        env_set('JWT_SECRET', secrets.token_hex(32))
        sh(f'systemctl restart {SERVICE}')
        self.config_status.set_text('Secretos regenerados — la app movil debera reloguearse.')

    def on_relink_whatsapp(self, _btn):
        dialog = Gtk.MessageDialog(
            transient_for=self, flags=0, message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text='Esto borra la sesion de WhatsApp actual y pedira un nuevo codigo de vinculacion. Continuar?')
        resp = dialog.run()
        dialog.destroy()
        if resp == Gtk.ResponseType.YES:
            appdata = self._appdata_dir()
            if appdata:
                sh(f'rm -rf "{appdata}/pedidos-bot/auth" && mkdir -p "{appdata}/pedidos-bot/auth"')
            sh(f'systemctl restart {SERVICE}')
            self.config_status.set_text('Sesion borrada. Revisa la pestaña Logs para el nuevo codigo.')

    # ── Tab: Seguridad ────────────────────────────────────────
    def build_security_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_border_width(18)
        title = Gtk.Label(label='AUDITORIA DE SEGURIDAD', xalign=0)
        title.get_style_context().add_class('section-title')
        box.pack_start(title, False, False, 0)
        self.security_view = Gtk.TextView(editable=False, cursor_visible=False)
        self.security_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.security_view.set_left_margin(8)
        self.security_view.set_top_margin(8)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.security_view)
        box.pack_start(scroll, True, True, 0)
        btn = Gtk.Button(label='EJECUTAR AUDITORIA')
        btn.get_style_context().add_class('action-btn')
        btn.get_style_context().add_class('btn-flat')
        btn.connect('clicked', lambda *_: self.refresh_security())
        box.pack_start(btn, False, False, 0)
        return box

    def refresh_security(self):
        lines = []
        user = sh(f"systemctl show {SERVICE} -p User --value")
        lines.append(f"Servicio corre como: {user or '?'} " + ("(OK, no-root)" if user and user != 'root' else "(RIESGO: root)"))
        try:
            perms = oct(os.stat(ENV_FILE).st_mode)[-3:] if os.path.exists(ENV_FILE) else '?'
        except Exception:
            perms = '?'
        lines.append(f"Permisos .env: {perms} (recomendado: 600)")
        lines.append(f"HOST bind: {env_get('HOST') or '(no seteado)'} (recomendado: 127.0.0.1)")
        fw = 'ufw' if sh('command -v ufw') else ('firewalld' if sh('command -v firewall-cmd') else 'iptables')
        lines.append(f"Firewall detectado: {fw}")
        f2b = sh('systemctl is-active fail2ban 2>/dev/null') or 'no instalado'
        lines.append(f"fail2ban: {f2b}")
        lines.append(f"Servicio Node: {sh(f'systemctl is-active {SERVICE} 2>/dev/null') or 'no instalado'}")
        lines.append(f"Tunel Cloudflare: {sh(f'systemctl is-active {TUNNEL_SERVICE} 2>/dev/null') or 'no instalado'}")
        buf = self.security_view.get_buffer()
        buf.set_text('\n'.join(f'• {l}' for l in lines))

    # ── Tab: Logs ─────────────────────────────────────────────
    def build_logs_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_border_width(18)
        title = Gtk.Label(label='LOGS DEL SERVIDOR (EN VIVO)', xalign=0)
        title.get_style_context().add_class('section-title')
        box.pack_start(title, False, False, 0)
        self.logs_view = Gtk.TextView(editable=False, cursor_visible=False)
        self.logs_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.logs_view.set_monospace(True)
        self.logs_view.set_left_margin(8)
        scroll = Gtk.ScrolledWindow()
        scroll.add(self.logs_view)
        box.pack_start(scroll, True, True, 0)
        return box

    def refresh_logs(self):
        p = os.path.join(LOG_DIR, 'server.log')
        content = sh(f'tail -c 8000 "{p}" 2>/dev/null') if os.path.exists(p) else '(sin logs todavia)'
        buf = self.logs_view.get_buffer()
        buf.set_text(content)
        mark = buf.create_mark(None, buf.get_end_iter(), False)
        self.logs_view.scroll_to_mark(mark, 0, False, 0, 0)

    # ── Refresco general ──────────────────────────────────────
    def _set_dot(self, dot, active, failed=False):
        ctx = dot.get_style_context()
        for cls in ('dot-active', 'dot-inactive', 'dot-failed'):
            ctx.remove_class(cls)
        ctx.add_class('dot-failed' if failed else ('dot-active' if active else 'dot-inactive'))

    def refresh_all(self):
        active = sh(f'systemctl is-active {SERVICE} 2>/dev/null') or 'inactivo'
        self._status_class = 'pulse-active' if active == 'active' else 'pulse-inactive'
        self.lbl_status.set_text(active.upper())
        self._set_dot(self.dot_status, active == 'active', failed=(active == 'failed'))

        tactive = sh(f'systemctl is-active {TUNNEL_SERVICE} 2>/dev/null') or 'no instalado'
        self.lbl_tunnel.set_text(tactive.upper())
        self._set_dot(self.dot_tunnel, tactive == 'active', failed=(tactive == 'failed'))

        since = sh(f"systemctl show {SERVICE} -p ActiveEnterTimestamp --value")
        self.lbl_uptime.set_text(since or '—')

        mem = sh(f"systemctl show {SERVICE} -p MemoryCurrent --value")
        try:
            self.lbl_mem.set_text(f'{int(mem) / 1024 / 1024:.1f} MB')
        except Exception:
            self.lbl_mem.set_text('—')

        orders_today = query("SELECT COUNT(*) FROM orders WHERE date(requested_at)=date('now')")
        orders_total = query("SELECT COUNT(*) FROM orders")
        self.lbl_orders.set_text(
            f"{orders_today[0][0] if orders_today else 0} / {orders_total[0][0] if orders_total else 0}")

        msgs_today = query("SELECT COUNT(*) FROM messages WHERE date(created_at)=date('now')")
        msgs_total = query("SELECT COUNT(*) FROM messages")
        self.lbl_msgs.set_text(
            f"{msgs_today[0][0] if msgs_today else 0} / {msgs_total[0][0] if msgs_total else 0}")

        self._refresh_chart(self.chart_orders, 'orders', 'requested_at')
        self._refresh_chart(self.chart_msgs, 'messages', 'created_at')
        self._refresh_sales()
        self.refresh_security()
        self.refresh_logs()
        self._load_brand()

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

    def _refresh_sales(self):
        sales_today = query("""
            SELECT COALESCE(SUM(oi.product_price*oi.quantity),0) FROM orders o
            JOIN order_items oi ON oi.order_id=o.id
            WHERE o.status IN ('entregado','delivered') AND date(o.delivered_at)=date('now')
        """)
        self.lbl_sales_today.set_text(f"${sales_today[0][0]:,.0f}" if sales_today else "$0")

        avg = query("""
            SELECT COALESCE(AVG(t),0) FROM (
              SELECT SUM(oi.product_price*oi.quantity) t FROM orders o
              JOIN order_items oi ON oi.order_id=o.id
              WHERE o.status IN ('entregado','delivered') GROUP BY o.id)
        """)
        self.lbl_avg_ticket.set_text(f"${avg[0][0]:,.0f}" if avg else "$0")

        counts = query("""
            SELECT COUNT(*) FILTER (WHERE status='cancelled'),
                   COUNT(*) FILTER (WHERE status IN ('entregado','delivered')),
                   COUNT(*) FROM orders
        """)
        if counts:
            cancelled, delivered, total = counts[0]
            pct = round((cancelled / total) * 100) if total else 0
            self.lbl_cancelled.set_text(f"{pct}%")
            self.lbl_delivered.set_text(str(delivered))

        rows = query("""
            SELECT date(o.delivered_at) d, SUM(oi.product_price*oi.quantity) t
            FROM orders o JOIN order_items oi ON oi.order_id=o.id
            WHERE o.status IN ('entregado','delivered') AND o.delivered_at >= date('now','-6 days')
            GROUP BY d ORDER BY d
        """)
        by_date = {r[0]: r[1] for r in rows}
        data = []
        for i in range(6, -1, -1):
            d = (datetime.date.today() - datetime.timedelta(days=i))
            data.append((d.strftime('%d/%m'), int(by_date.get(d.isoformat(), 0) or 0)))
        self.chart_sales.set_data(data)

        top = query("""
            SELECT oi.product_name, SUM(oi.quantity) q FROM order_items oi
            JOIN orders o ON o.id=oi.order_id
            WHERE o.status IN ('entregado','delivered')
            GROUP BY oi.product_name ORDER BY q DESC LIMIT 10
        """)
        self.top_products_store.clear()
        for name, qty in top:
            self.top_products_store.append([name, str(qty)])

    def _load_brand(self):
        if self.entry_primary.get_text():
            return  # no pisar lo que el usuario esta editando
        self.entry_primary.set_text(setting_get('theme_primary', PRIMARY_DEFAULT))
        self.entry_accent.set_text(setting_get('theme_accent', ACCENT_DEFAULT))
        self.entry_brand_name.set_text(setting_get('theme_name', 'Concentrados Monserrath'))


def main():
    win = DashboardWindow()
    win.connect('destroy', Gtk.main_quit)
    win.show_all()
    Gtk.main()


if __name__ == '__main__':
    main()
