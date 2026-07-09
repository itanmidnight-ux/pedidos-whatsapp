import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/stat_tile.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

const Map<String, String> _statusLabels = {
  'pending': 'Pendiente', 'claimed': 'Reclamado', 'en_camino': 'En camino',
  'entregado': 'Entregado', 'delivered': 'Entregado', 'cancelled': 'Cancelado',
};
const Map<String, Color> _statusColors = {
  'pending':   Color(0xFFB5651D),
  'claimed':   Color(0xFF3B5A73),
  'en_camino': Color(0xFF2D5016),
  'entregado': Color(0xFF2E7D32),
  'delivered': Color(0xFF2E7D32),
  'cancelled': Color(0xFFB3261E),
};

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

// Separador de miles (es-CO usa punto: 306.000) -- antes los numeros
// grandes se mostraban pegados ("306000"), dificiles de leer de un vistazo.
String _fmtN(dynamic n) => NumberFormat.decimalPattern('es_CO').format(n is num ? n : num.tryParse('$n') ?? 0);

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _products;
  Map<String, dynamic>? _employees;
  Map<String, dynamic>? _customers;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getAnalyticsSummary(),
        ApiService.getAnalyticsProducts(),
        ApiService.getAnalyticsEmployees(),
        ApiService.getAnalyticsCustomers(),
      ]);
      if (mounted) {
        setState(() {
          _summary = results[0];
          _products = results[1];
          _employees = results[2];
          _customers = results[3];
        });
      }
    } catch (_) {
      // Pantalla se queda con los datos previos (o vacíos) si falla la carga
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analíticas'),
        // Material 3 sin esto usa colorScheme.primary para el tab seleccionado
        // -- el mismo verde del fondo del AppBar, texto invisible sobre su
        // propio fondo. Un TabBar dentro de un AppBar de color necesita sus
        // colores explícitos en blanco, M3 no lo asume solo.
        bottom: TabBar(controller: _tabController, isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Resumen'), Tab(text: 'Productos'), Tab(text: 'Empleados'), Tab(text: 'Clientes'),
          ]),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: TabBarView(controller: _tabController, children: [
              _buildSummaryTab(),
              _buildProductsTab(),
              _buildEmployeesTab(),
              _buildCustomersTab(),
            ]),
          ),
    );
  }

  Widget _buildSummaryTab() {
    final s = _summary;
    if (s == null) return const EmptyState(icon: Icons.bar_chart_rounded, title: 'Sin datos todavía');
    final statusBreakdown = (s['status_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final dailySales = (s['daily_sales'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return ListView(padding: const EdgeInsets.all(16), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          StatTile(label: 'Ventas hoy', value: '\$${_fmtN(s['sales_today'])}', icon: Icons.attach_money_rounded),
          StatTile(label: 'Ticket promedio', value: '\$${_fmtN(s['avg_ticket'])}', icon: Icons.receipt_long_rounded),
          StatTile(label: 'Cancelados', value: '${s['cancelled_pct']}%', icon: Icons.cancel_outlined),
          StatTile(label: 'Entregados (total)', value: _fmtN(s['delivered_total']), icon: Icons.local_shipping_outlined),
        ],
      ),
      const SizedBox(height: 20),
      Text('Ingresos por día — últimos 7 días', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      AppCard(child: SizedBox(height: 200, child: _DailySalesChart(data: dailySales))),
      const SizedBox(height: 20),
      Text('Distribución de pedidos', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      AppCard(child: SizedBox(height: 220, child: _StatusDonutChart(data: statusBreakdown))),
    ]);
  }

  Widget _buildProductsTab() {
    final p = _products;
    if (p == null) return const EmptyState(icon: Icons.inventory_2_rounded, title: 'Sin datos todavía');
    final top = (p['top_products'] as List? ?? []).cast<Map<String, dynamic>>();
    final low = (p['low_stock'] as List? ?? []).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (low.isNotEmpty) ...[
        Text('Stock bajo', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...low.map((prod) => AppCard(child: Row(children: [
          Expanded(child: Text(prod['name'] as String)),
          Text('${prod['stock']} unid.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]))),
        const SizedBox(height: 20),
      ],
      Text('Más vendidos', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (top.isEmpty) const EmptyState(icon: Icons.inventory_2_rounded, title: 'Sin ventas registradas'),
      ...top.map((prod) => AppCard(child: Row(children: [
        Expanded(child: Text(prod['name'] as String)),
        Text('${_fmtN(prod['total_qty'])} vendidos'),
      ]))),
    ]);
  }

  String _timeAgo(String? iso) {
    if (iso == null) return 'nunca';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '-';
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1)   return 'ahora mismo';
    if (diff.inMinutes < 60)  return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24)    return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  Widget _buildEmployeesTab() {
    final e = _employees;
    if (e == null) return const EmptyState(icon: Icons.engineering_rounded, title: 'Sin datos todavía');
    final list = (e['employees'] as List? ?? []).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const EmptyState(icon: Icons.engineering_rounded, title: 'Sin trabajadores registrados');
    final notLoggedInToday = list.where((emp) => emp['logged_in_today'] != 1).length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (notLoggedInToday > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '$notLoggedInToday ${notLoggedInToday == 1 ? "persona no ha" : "personas no han"} iniciado sesión hoy',
              style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        ),
      ...list.map((emp) {
        final isActive = emp['is_active_now'] == 1;
        final loggedToday = emp['logged_in_today'] == 1;
        return GestureDetector(
          onTap: () => _showEmployeeDetail(emp),
          child: AppCard(child: Row(children: [
            Container(
              width: 10, height: 10,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.green : (loggedToday ? Colors.orange : Colors.grey.shade400),
              ),
            ),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(emp['display_name'] as String? ?? emp['username'] as String,
                style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                isActive ? 'En sesión · entró ${_timeAgo(emp['last_login_at'] as String?)}'
                  : !loggedToday ? 'No ha iniciado sesión hoy'
                  : 'Salió ${_timeAgo(emp['last_logout_at'] as String?)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isActive ? Colors.green.shade700 : Colors.grey.shade600),
              ),
            ])),
            Text('${_fmtN(emp['delivered_count'])} entregas'),
            const SizedBox(width: 12),
            Text('${emp['avg_minutes'] ?? '-'} min prom.'),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ])),
        );
      }),
    ]);
  }

  Future<void> _showEmployeeDetail(Map<String, dynamic> emp) async {
    Map<String, dynamic>? detail;
    try { detail = await ApiService.getEmployeeDetail(emp['id'] as int); } catch (_) {}
    if (!mounted) return;
    final sessions = (detail?['sessions'] as List? ?? []).cast<Map<String, dynamic>>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emp['display_name'] as String? ?? emp['username'] as String,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('@${emp['username']} · ${emp['role']}', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: StatTile(label: 'Entregas', value: _fmtN(emp['delivered_count']), icon: Icons.local_shipping_outlined)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Tiempo prom.', value: '${emp['avg_minutes'] ?? '-'} min', icon: Icons.timer_outlined)),
            ]),
            const SizedBox(height: 16),
            const Text('Historial de sesiones', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: sessions.isEmpty
                ? const Center(child: Text('Sin sesiones registradas', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: sessions.length,
                    itemBuilder: (_, i) {
                      final s = sessions[i];
                      final open = s['logged_out_at'] == null;
                      return ListTile(
                        dense: true,
                        leading: Icon(open ? Icons.login_rounded : Icons.logout_rounded,
                          color: open ? Colors.green : Colors.grey),
                        title: Text('Entrada: ${s['logged_in_at']}'),
                        subtitle: Text(open ? 'Sigue en sesión' : 'Salida: ${s['logged_out_at']}'),
                      );
                    },
                  ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildCustomersTab() {
    final c = _customers;
    if (c == null) return const EmptyState(icon: Icons.people_outline_rounded, title: 'Sin datos todavía');
    final top = (c['top_customers'] as List? ?? []).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.8,
        children: [
          StatTile(label: 'Clientes nuevos (30d)', value: _fmtN(c['new_customers']), icon: Icons.person_add_outlined),
          StatTile(label: 'Recurrentes', value: _fmtN(c['returning_customers']), icon: Icons.repeat_rounded),
        ],
      ),
      const SizedBox(height: 20),
      Text('Top clientes', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (top.isEmpty) const EmptyState(icon: Icons.people_outline_rounded, title: 'Sin pedidos entregados aún'),
      ...top.map((cust) => AppCard(child: Row(children: [
        Expanded(child: Text(cust['name'] as String? ?? cust['phone'] as String)),
        Text('${_fmtN(cust['order_count'])} pedidos'),
      ]))),
    ]);
  }
}

/// Barras de ingresos por día (últimos 7 días).
class _DailySalesChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _DailySalesChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((d) => (d['total'] as num? ?? 0) == 0)) {
      return const Center(child: Text('Sin ingresos esta semana', style: TextStyle(color: Colors.grey)));
    }
    final primary = Theme.of(context).colorScheme.primary;
    final maxVal = data.map((d) => (d['total'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b);
    return BarChart(BarChartData(
      maxY: maxVal * 1.2,
      barTouchData: BarTouchData(enabled: true),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 28,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= data.length) return const SizedBox.shrink();
            final d = DateTime.tryParse(data[i]['date'] as String? ?? '');
            return Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(d != null ? DateFormat('E', 'es').format(d) : '',
                style: const TextStyle(fontSize: 11, color: Colors.black87)));
          },
        )),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      barGroups: List.generate(data.length, (i) {
        final total = (data[i]['total'] as num? ?? 0).toDouble();
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: total, color: primary, width: 20,
            borderRadius: BorderRadius.circular(4)),
        ]);
      }),
    ));
  }
}

/// Dona de distribución de pedidos por estado.
class _StatusDonutChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _StatusDonutChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.where((d) => (d['count'] as num? ?? 0) > 0).toList();
    if (entries.isEmpty) {
      return const Center(child: Text('Sin pedidos todavía', style: TextStyle(color: Colors.grey)));
    }
    final total = entries.fold<int>(0, (sum, e) => sum + (e['count'] as num).toInt());
    return Row(children: [
      Expanded(
        flex: 3,
        child: PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 40,
          sections: entries.map((e) {
            final status = e['status'] as String;
            final count  = (e['count'] as num).toInt();
            final pct    = (count / total * 100).round();
            return PieChartSectionData(
              value: count.toDouble(),
              color: _statusColors[status] ?? Colors.grey,
              title: '$pct%',
              radius: 55,
              titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
            );
          }).toList(),
        )),
      ),
      Expanded(
        flex: 2,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
          children: entries.map((e) {
            final status = e['status'] as String;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(width: 10, height: 10,
                  decoration: BoxDecoration(color: _statusColors[status] ?? Colors.grey, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(_statusLabels[status] ?? status,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  overflow: TextOverflow.ellipsis)),
                Text('${e['count']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}
