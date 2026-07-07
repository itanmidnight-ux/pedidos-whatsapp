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

CSS = """
window { background-color: #14170f; }
headerbar {
    background-image: linear-gradient(to right, #2D5016, #1A3009);
    color: #ffffff;
    border: none;
}
headerbar label { color: #ffffff; }
headerbar .title { font-weight: 800; letter-spacing: 0.5px; }
headerbar .subtitle { color: #D4800A; }
headerbar button {
    background: rgba(255,255,255,0.08);
    border: 1px solid rgba(255,255,255,0.18);
    border-radius: 8px;
    color: #ffffff;
    transition: background 200ms ease;
}
headerbar button:hover { background: rgba(255,255,255,0.22); }

notebook > header { background-color: #1c2116; border: none; }
notebook > header > tabs > tab {
    padding: 8px 14px;
    color: #b9c2ad;
    transition: color 200ms ease, background 200ms ease;
    border-radius: 8px 8px 0 0;
}
notebook > header > tabs > tab:checked {
    background-color: #2D5016;
    color: #ffffff;
}
notebook > header > tabs > tab:hover { background-color: rgba(212,128,10,0.15); }

.stat-card {
    background-color: #1c2116;
    border-radius: 12px;
    border: 1px solid rgba(212,128,10,0.25);
    padding: 12px;
    transition: border 200ms ease, background 200ms ease;
}
.stat-card:hover { border: 1px solid rgba(212,128,10,0.6); background-color: #202614; }
.stat-label { color: #9aa693; font-size: 11px; letter-spacing: 0.3px; }
.stat-value { color: #ffffff; font-size: 20px; font-weight: 800; }
.stat-icon { font-size: 22px; }

.section-title {
    color: #D4800A;
    font-weight: 800;
    font-size: 13px;
    letter-spacing: 0.5px;
}

.pulse-active { color: #6fd97f; font-size: 16px; }
.pulse-inactive { color: #666; font-size: 16px; }
.pulse-failed { color: #e5766a; font-size: 16px; }

button.action-btn {
    border-radius: 10px;
    padding: 8px 16px;
    font-weight: 700;
    transition: all 200ms ease;
}
button.action-btn:hover { border-color: rgba(255,255,255,0.4); }
.btn-primary { background-color: #2D5016; color: white; border: none; }
.btn-primary:hover { background-color: #3a6620; }
.btn-warn { background-color: #B5651D; color: white; border: none; }
.btn-warn:hover { background-color: #cc7526; }
.btn-danger { background-color: #B3261E; color: white; border: none; }
.btn-danger:hover { background-color: #cc3a30; }
.btn-flat { background-color: #1c2116; color: #e6e6e6; border: 1px solid rgba(255,255,255,0.12); }
.btn-flat:hover { background-color: #2a3020; }

entry {
    background-color: #1c2116;
    color: #ffffff;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.15);
    padding: 6px 10px;
}
entry:focus { border: 1px solid #D4800A; }

label { color: #d8ddd0; }
textview, textview text { background-color: #0f120c; color: #cfd6c4; }

.preset-swatch {
    border-radius: 10px;
    border: 2px solid rgba(255,255,255,0.15);
    transition: border 200ms ease;
}
.preset-swatch:hover { border: 2px solid #ffffff; }
.preset-selected { border: 3px solid #ffffff; }
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
        self.color = color or (0.831, 0.502, 0.039)
        self.data = []
        self.set_size_request(260, 170)
        self.connect('draw', self.on_draw)

    def set_data(self, data):
        self.data = data
        self.queue_draw()

    def on_draw(self, widget, cr):
        w = widget.get_allocated_width()
        h = widget.get_allocated_height()
        cr.set_source_rgb(0.11, 0.13, 0.086)
        cr.paint()

        cr.set_source_rgb(0.831, 0.502, 0.039)
        cr.select_font_face('Sans', 0, 1)
        cr.set_font_size(12)
        cr.move_to(10, 18)
        cr.show_text(self.title)

        if not any(v for _, v in self.data):
            cr.set_source_rgba(0.7, 0.75, 0.68, 0.6)
            cr.set_font_size(11)
            cr.move_to(10, h / 2)
            cr.show_text('Sin datos todavia — apareceran con el primer pedido')
            return

        pad_left, pad_bottom, pad_top = 12, 24, 30
        chart_h = h - pad_bottom - pad_top
        chart_w = w - pad_left - 12
        maxval = max((v for _, v in self.data), default=1) or 1
        n = len(self.data) or 1
        bw = chart_w / n

        if self.kind == 'bar':
            for i, (label, val) in enumerate(self.data):
                bh = (val / maxval) * chart_h if maxval else 0
                x = pad_left + i * bw + bw * 0.15
                y = pad_top + (chart_h - bh)
                cr.set_source_rgb(*self.color)
                cr.rectangle(x, y, bw * 0.7, bh)
                cr.fill()
                cr.set_source_rgba(0.85, 0.88, 0.8, 0.9)
                cr.set_font_size(8)
                cr.move_to(x, h - pad_bottom + 11)
                cr.show_text(label)
        else:  # line
            pts = []
            for i, (label, val) in enumerate(self.data):
                x = pad_left + i * bw + bw / 2
                y = pad_top + (chart_h - (val / maxval) * chart_h if maxval else chart_h)
                pts.append((x, y, label))
            cr.set_source_rgb(*self.color)
            cr.set_line_width(2.2)
            for i, (x, y, _) in enumerate(pts):
                cr.line_to(x, y) if i else cr.move_to(x, y)
            cr.stroke()
            for x, y, label in pts:
                cr.arc(x, y, 3, 0, 2 * 3.14159)
                cr.fill()
                cr.set_source_rgba(0.85, 0.88, 0.8, 0.9)
                cr.set_font_size(8)
                cr.move_to(x - 8, h - pad_bottom + 11)
                cr.show_text(label)
                cr.set_source_rgb(*self.color)


def stat_card(icon, label, value_widget_holder):
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    box.get_style_context().add_class('stat-card')
    icon_lbl = Gtk.Label(label=icon)
    icon_lbl.get_style_context().add_class('stat-icon')
    box.pack_start(icon_lbl, False, False, 0)
    inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    lbl = Gtk.Label(label=label, xalign=0)
    lbl.get_style_context().add_class('stat-label')
    val = Gtk.Label(label='—', xalign=0)
    val.get_style_context().add_class('stat-value')
    inner.pack_start(lbl, False, False, 0)
    inner.pack_start(val, False, False, 0)
    box.pack_start(inner, True, True, 0)
    value_widget_holder.append(val)
    return box


class DashboardWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title='Concentrados Monserrath — Panel del Servidor')
        self.set_default_size(920, 640)

        screen = Gdk.Screen.get_default()
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode())
        Gtk.StyleContext.add_provider_for_screen(
            screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(vbox)

        header = Gtk.HeaderBar()
        header.set_title('🌾 Concentrados Monserrath')
        header.set_subtitle('Panel del servidor — monitoreo en vivo')
        header.set_show_close_button(True)
        refresh_btn = Gtk.Button(label='⟳ Actualizar')
        refresh_btn.connect('clicked', lambda *_: self.refresh_all())
        header.pack_end(refresh_btn)
        self.set_titlebar(header)

        notebook = Gtk.Notebook()
        vbox.pack_start(notebook, True, True, 0)

        notebook.append_page(self.build_monitor_tab(), Gtk.Label(label='📊  Monitoreo'))
        notebook.append_page(self.build_sales_tab(), Gtk.Label(label='💰  Ventas'))
        notebook.append_page(self.build_brand_tab(), Gtk.Label(label='🎨  Marca'))
        notebook.append_page(self.build_config_tab(), Gtk.Label(label='⚙️  Configuracion'))
        notebook.append_page(self.build_security_tab(), Gtk.Label(label='🛡️  Seguridad'))
        notebook.append_page(self.build_logs_tab(), Gtk.Label(label='📜  Logs'))

        self._pulse_on = True
        self.refresh_all()
        GLib.timeout_add_seconds(5, self._tick)
        GLib.timeout_add(700, self._pulse)

    def _tick(self):
        self.refresh_all()
        return True

    def _pulse(self):
        self._pulse_on = not self._pulse_on
        if hasattr(self, 'status_dot'):
            ctx = self.status_dot.get_style_context()
            cls = getattr(self, '_status_class', 'pulse-inactive')
            if cls == 'pulse-active':
                self.status_dot.set_opacity(1.0 if self._pulse_on else 0.45)
        return True

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
        specs = [
            ('status', '🖥️', 'Servicio Node'), ('tunnel', '☁️', 'Tunel Cloudflare'),
            ('uptime', '⏱️', 'Activo desde'), ('mem', '🧠', 'Memoria'),
            ('orders', '📦', 'Pedidos (hoy / total)'), ('msgs', '💬', 'Mensajes (hoy / total)'),
        ]
        for key, icon, label in specs:
            hold = []
            cards.add(stat_card(icon, label, hold))
            holders[key] = hold[0]
        self.lbl_status, self.lbl_tunnel = holders['status'], holders['tunnel']
        self.lbl_uptime, self.lbl_mem = holders['uptime'], holders['mem']
        self.lbl_orders, self.lbl_msgs = holders['orders'], holders['msgs']

        charts_title = Gtk.Label(label='ACTIVIDAD (ULTIMOS 7 DIAS)', xalign=0)
        charts_title.get_style_context().add_class('section-title')
        box.pack_start(charts_title, False, False, 0)

        charts = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        box.pack_start(charts, True, True, 0)
        self.chart_orders = Chart('Pedidos por dia', 'bar', (0.831, 0.502, 0.039))
        self.chart_msgs = Chart('Mensajes por dia', 'line', (0.44, 0.72, 0.85))
        charts.pack_start(self.chart_orders, True, True, 0)
        charts.pack_start(self.chart_msgs, True, True, 0)

        actions = Gtk.Box(spacing=8)
        box.pack_start(actions, False, False, 0)
        for label, cmd, css in [
            ('🔄 Reiniciar', f'systemctl restart {SERVICE}', 'btn-primary'),
            ('⏸ Detener', f'systemctl stop {SERVICE}', 'btn-warn'),
            ('▶ Iniciar', f'systemctl start {SERVICE}', 'btn-primary'),
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
        for key, icon, label in [
            ('sales_today', '💵', 'Ventas hoy'), ('avg_ticket', '🧾', 'Ticket promedio'),
            ('cancelled', '❌', '% Cancelados'), ('delivered', '🚚', 'Entregados (total)'),
        ]:
            hold = []
            cards.add(stat_card(icon, label, hold))
            holders[key] = hold[0]
        self.lbl_sales_today = holders['sales_today']
        self.lbl_avg_ticket = holders['avg_ticket']
        self.lbl_cancelled = holders['cancelled']
        self.lbl_delivered = holders['delivered']

        chart_title = Gtk.Label(label='INGRESOS POR DIA (ULTIMOS 7)', xalign=0)
        chart_title.get_style_context().add_class('section-title')
        box.pack_start(chart_title, False, False, 0)
        self.chart_sales = Chart('Ingresos ($)', 'bar', (0.42, 0.75, 0.4))
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
        logo_btn = Gtk.Button(label='🖼️ Cambiar logo…')
        logo_btn.get_style_context().add_class('action-btn')
        logo_btn.get_style_context().add_class('btn-flat')
        logo_btn.connect('clicked', self.on_pick_logo)
        logo_box.pack_start(logo_btn, False, False, 0)
        self.logo_status = Gtk.Label(label='')
        logo_box.pack_start(self.logo_status, False, False, 0)

        save_btn = Gtk.Button(label='💾 Guardar marca')
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

        save_btn = Gtk.Button(label='💾 Guardar y reiniciar servicio')
        save_btn.get_style_context().add_class('action-btn')
        save_btn.get_style_context().add_class('btn-primary')
        save_btn.connect('clicked', self.on_save_config)
        box.pack_start(save_btn, False, False, 8)

        sec_title = Gtk.Label(label='ACCIONES SENSIBLES', xalign=0)
        sec_title.get_style_context().add_class('section-title')
        box.pack_start(sec_title, False, False, 8)

        row2 = Gtk.Box(spacing=8)
        box.pack_start(row2, False, False, 0)
        regen_btn = Gtk.Button(label='🔑 Regenerar secretos')
        regen_btn.get_style_context().add_class('action-btn')
        regen_btn.get_style_context().add_class('btn-warn')
        regen_btn.connect('clicked', self.on_regen_secrets)
        row2.pack_start(regen_btn, False, False, 0)

        relink_btn = Gtk.Button(label='📱 Re-vincular WhatsApp')
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
        btn = Gtk.Button(label='🔍 Ejecutar auditoria ahora')
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
    def refresh_all(self):
        active = sh(f'systemctl is-active {SERVICE} 2>/dev/null') or 'inactivo'
        icon = '🟢' if active == 'active' else ('🔴' if active == 'failed' else '⚪')
        self._status_class = 'pulse-active' if active == 'active' else 'pulse-inactive'
        self.lbl_status.set_text(f'{icon} {active}')

        tactive = sh(f'systemctl is-active {TUNNEL_SERVICE} 2>/dev/null') or 'no instalado'
        ticon = '🟢' if tactive == 'active' else '⚪'
        self.lbl_tunnel.set_text(f'{ticon} {tactive}')

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
