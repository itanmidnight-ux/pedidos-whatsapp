import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/stat_tile.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});
  @override State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

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
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: const [
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
    if (s == null) return const EmptyState(emoji: '📊', title: 'Sin datos todavía');
    return ListView(padding: const EdgeInsets.all(16), children: [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          StatTile(label: 'Ventas hoy', value: '\$${s['sales_today']}', icon: Icons.attach_money_rounded),
          StatTile(label: 'Ticket promedio', value: '\$${s['avg_ticket']}', icon: Icons.receipt_long_rounded),
          StatTile(label: 'Cancelados', value: '${s['cancelled_pct']}%', icon: Icons.cancel_outlined),
          StatTile(label: 'Entregados (total)', value: '${s['delivered_total']}', icon: Icons.local_shipping_outlined),
        ],
      ),
    ]);
  }

  Widget _buildProductsTab() {
    final p = _products;
    if (p == null) return const EmptyState(emoji: '📦', title: 'Sin datos todavía');
    final top = (p['top_products'] as List).cast<Map<String, dynamic>>();
    final low = (p['low_stock'] as List).cast<Map<String, dynamic>>();
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
      if (top.isEmpty) const EmptyState(emoji: '📦', title: 'Sin ventas registradas'),
      ...top.map((prod) => AppCard(child: Row(children: [
        Expanded(child: Text(prod['name'] as String)),
        Text('${prod['total_qty']} vendidos'),
      ]))),
    ]);
  }

  Widget _buildEmployeesTab() {
    final e = _employees;
    if (e == null) return const EmptyState(emoji: '👷', title: 'Sin datos todavía');
    final list = (e['employees'] as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return const EmptyState(emoji: '👷', title: 'Sin entregas registradas');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final emp = list[i];
        return AppCard(child: Row(children: [
          Expanded(child: Text(emp['display_name'] as String? ?? emp['username'] as String)),
          Text('${emp['delivered_count']} entregas'),
          const SizedBox(width: 12),
          Text('${emp['avg_minutes'] ?? '-'} min prom.'),
        ]));
      },
    );
  }

  Widget _buildCustomersTab() {
    final c = _customers;
    if (c == null) return const EmptyState(emoji: '👥', title: 'Sin datos todavía');
    final top = (c['top_customers'] as List).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.8,
        children: [
          StatTile(label: 'Clientes nuevos (30d)', value: '${c['new_customers']}', icon: Icons.person_add_outlined),
          StatTile(label: 'Recurrentes', value: '${c['returning_customers']}', icon: Icons.repeat_rounded),
        ],
      ),
      const SizedBox(height: 20),
      Text('Top clientes', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      if (top.isEmpty) const EmptyState(emoji: '👥', title: 'Sin pedidos entregados aún'),
      ...top.map((cust) => AppCard(child: Row(children: [
        Expanded(child: Text(cust['name'] as String? ?? cust['phone'] as String)),
        Text('${cust['order_count']} pedidos'),
      ]))),
    ]);
  }
}
