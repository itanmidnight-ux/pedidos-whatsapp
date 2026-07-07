import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/empty_state.dart';

class InventarioScreen extends StatefulWidget {
  const InventarioScreen({super.key});
  @override State<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends State<InventarioScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _productTotals = [];
  List<Map<String, dynamic>> _dailyDeliveries = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await ApiService.getInventoryStats();
      setState(() {
        _productTotals   = List<Map<String, dynamic>>.from(data['product_totals'] ?? []);
        _dailyDeliveries = List<Map<String, dynamic>>.from(data['daily_deliveries'] ?? []);
        _summary         = Map<String, dynamic>.from(data['summary'] ?? {});
        _loading         = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      color: scheme.primary,
      child: _loading
        ? Center(child: CircularProgressIndicator(color: scheme.primary))
        : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(children: [
      const SizedBox(height: 100),
      Center(child: Column(children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
          style: FilledButton.styleFrom(backgroundColor: scheme.primary),
        ),
      ])),
    ]);
  }

  Widget _buildContent() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildSummaryCards(),
      const SizedBox(height: 20),
      _buildBarChart(),
      const SizedBox(height: 20),
      _buildProductList(),
      const SizedBox(height: 40),
    ],
  );

  Widget _buildSummaryCards() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Resumen del día', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: scheme.primary)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _statCard('Pendientes', '${_summary['pending'] ?? 0}', Icons.hourglass_top_rounded, scheme.secondary)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('En camino', '${_summary['en_camino'] ?? 0}', Icons.directions_bike_rounded, scheme.primary)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _statCard('Reclamados', '${_summary['claimed'] ?? 0}', Icons.person_pin_circle_rounded, Colors.blue)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Entregados hoy', '${_summary['delivered_today'] ?? 0}', Icons.check_circle_rounded, Colors.teal)),
      ]),
    ],
  );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) => Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ]),
    ),
  );

  Widget _buildBarChart() {
    // Build last 7 days labels + counts
    final now = DateTime.now();
    const dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

    final dayMap = <String, int>{};
    for (var d in _dailyDeliveries) {
      dayMap[d['day'] as String] = (d['count'] as int?) ?? 0;
    }

    final bars = List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final count = dayMap[key] ?? 0;
      final label = dayNames[(date.weekday - 1) % 7];
      final isToday = i == 6;
      return (label: label, count: count, isToday: isToday);
    });

    final maxCount = bars.map((b) => b.count).reduce((a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pedidos entregados (últimos 7 días)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: scheme.primary)),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: bars.map((b) {
                final barH = maxCount == 0 ? 0.0 : (b.count / maxCount) * 100.0;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (b.count > 0)
                          Text('${b.count}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: b.isToday ? scheme.secondary : scheme.primary)),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          height: barH.clamp(4, 100),
                          decoration: BoxDecoration(
                            color: b.isToday ? scheme.secondary : scheme.primary,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(b.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: b.isToday ? FontWeight.bold : FontWeight.normal,
                            color: b.isToday ? scheme.secondary : Colors.grey.shade700)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (maxCount == 0) ...[
            const SizedBox(height: 8),
            Center(child: Text('Sin entregas esta semana',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12))),
          ],
        ]),
      ),
    );
  }

  Widget _buildProductList() {
    final scheme = Theme.of(context).colorScheme;
    if (_productTotals.isEmpty) {
      return const EmptyState(icon: Icons.inventory_2_rounded, title: 'No hay pedidos activos');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(children: [
            Icon(Icons.inventory_2_rounded, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text('Productos requeridos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: scheme.primary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Text('${_productTotals.length} productos',
                style: TextStyle(fontSize: 11, color: scheme.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const Divider(height: 1),
        ..._productTotals.asMap().entries.map((e) {
          final item = e.value;
          final isLast = e.key == _productTotals.length - 1;
          final total = (item['total'] as num?)?.toInt() ?? 0;
          final maxTotal = (_productTotals.first['total'] as num?)?.toInt() ?? 1;
          final ratio = total / maxTotal;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(item['name'] as String? ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.secondary.withValues(alpha: 0.4))),
                    child: Text(
                      NumberFormat('#,###', 'es_CO').format(total),
                      style: TextStyle(fontWeight: FontWeight.bold, color: scheme.secondary, fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 4,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ratio > 0.7 ? Colors.red.shade400 : ratio > 0.4 ? scheme.secondary : scheme.primary),
                  ),
                ),
              ]),
            ),
            if (!isLast) const Divider(height: 1, indent: 16, endIndent: 16),
          ]);
        }),
        const SizedBox(height: 8),
      ]),
    );
  }
}
