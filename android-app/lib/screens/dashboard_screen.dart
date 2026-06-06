import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../widgets/order_card.dart';
import '../widgets/company_header.dart';
import 'products_screen.dart';
import 'messages_screen.dart';
import 'users_screen.dart';
import 'admin_estados_screen.dart';
import 'inventario_screen.dart';

// Filter chips
const _allStatuses = ['pending', 'claimed', 'en_camino'];
final _statusLabels = {'pending': 'Pendientes', 'claimed': 'Reclamados', 'en_camino': 'En camino'};

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;
  Set<String> _filter = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().refreshAll();
    });
  }

  static const _titlesWorker = ['Pedidos Activos', 'Mensajes'];
  static const _titlesAdmin  = ['Pedidos Activos', 'Productos', 'Mensajes', 'Usuarios', 'Estados', 'Inventario'];

  /// Filter + sort orders:
  /// - No filter: show pending + current user's claimed/en_camino (other workers' orders hidden)
  /// - Filter active: show only matching statuses
  /// - Always pin current user's orders to top, then oldest first
  List _sortedOrders(List orders) {
    final me = ApiService.currentUser;

    final filtered = _filter.isEmpty
      ? orders.where((o) => o.status == 'pending' || o.claimedByUsername == me).toList()
      : orders.where((o) => _filter.contains(o.status)).toList();

    // Backend returns ASC already; just pin mine to top
    final mine   = filtered.where((o) => o.claimedByUsername == me).toList();
    final others = filtered.where((o) => o.claimedByUsername != me).toList();
    return [...mine, ...others];
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final titles = provider.isAdmin ? _titlesAdmin : _titlesWorker;
    final safeTab = _tab < titles.length ? _tab : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      appBar: CompanyHeader(
        pageTitle: titles[safeTab],
        actions: [
          if (!provider.isOnline)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Sin conexión',
                child: Icon(Icons.wifi_off, color: Color(0xFFD4800A), size: 20),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => provider.refreshAll(),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Deseas cerrar sesión?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                    FilledButton(onPressed: () => Navigator.pop(context, true),
                      child: const Text('Salir')),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                context.read<AppProvider>().logout();
              }
            },
          ),
        ],
      ),
      body: IndexedStack(index: safeTab, children: [
        // PEDIDOS (all roles)
        Column(children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: _allStatuses.map((s) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_statusLabels[s] ?? s),
                  selected: _filter.contains(s),
                  onSelected: (v) => setState(() => v ? _filter.add(s) : _filter.remove(s)),
                  selectedColor: const Color(0xFFD4ECB8),
                  checkmarkColor: const Color(0xFF2D5016),
                ),
              )).toList(),
            ),
          ),
          Expanded(child: RefreshIndicator(
            onRefresh: provider.refreshOrders,
            color: const Color(0xFF2D5016),
            child: () {
              if (provider.loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF2D5016)));
              final sorted = _sortedOrders(provider.orders);
              if (sorted.isEmpty) return ListView(children: const [
                SizedBox(height: 100),
                Column(children: [
                  Text('📦', style: TextStyle(fontSize: 64)),
                  SizedBox(height: 12),
                  Text('No hay pedidos activos', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
                  SizedBox(height: 4),
                  Text('Desliza para actualizar', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ]);
              return ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 80),
                itemCount: sorted.length,
                itemBuilder: (ctx, i) {
                  final order = sorted[i];
                  return OrderCard(
                    key: ValueKey(order.id),
                    order: order,
                    onDeliver:  () => provider.deliverOrder(order.id!),
                    onComment:  (c) => provider.addComment(order.id!, c),
                    onClaim:    () => provider.claimOrder(order.id!),
                    onUnclaim:  () => provider.unclaimOrder(order.id!),
                    onEnCamino: () => provider.markEnCamino(order.id!),
                    onTake:     order.status == 'pending' && !order.isClaimed
                                  ? () => provider.takeOrder(order.id!)
                                  : null,
                    onCancel:   provider.isAdmin ? (r) => provider.cancelOrder(order.id!, r) : null,
                  );
                },
              );
            }(),
          )),
        ]),
        // PRODUCTOS (admin only)
        if (provider.isAdmin) const ProductsScreen(),
        // MENSAJES (all roles)
        const MessagesScreen(),
        // USUARIOS (admin only)
        if (provider.isAdmin) const UsersScreen(),
        // ESTADOS (admin only)
        if (provider.isAdmin) const AdminEstadosScreen(),
        // INVENTARIO (admin only)
        if (provider.isAdmin) const InventarioScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFC8E6C9),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: provider.orders.isNotEmpty,
              label: Text('${provider.orders.length}'),
              backgroundColor: const Color(0xFFD4800A),
              child: const Icon(Icons.dashboard_rounded)),
            selectedIcon: const Icon(Icons.dashboard_rounded, color: Color(0xFF1E6B2E)),
            label: 'Pedidos'),
          if (provider.isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2_rounded, color: Color(0xFF1E6B2E)),
              label: 'Productos'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: provider.flaggedCount > 0,
              label: Text('${provider.flaggedCount}'),
              backgroundColor: Colors.red,
              child: const Icon(Icons.chat_bubble_outline_rounded)),
            selectedIcon: Badge(
              isLabelVisible: provider.flaggedCount > 0,
              label: Text('${provider.flaggedCount}'),
              backgroundColor: Colors.red,
              child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF1E6B2E))),
            label: 'Mensajes'),
          if (provider.isAdmin)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: provider.users.isNotEmpty,
                label: Text('${provider.users.length}'),
                backgroundColor: const Color(0xFFD4800A),
                child: const Icon(Icons.group_outlined)),
              selectedIcon: const Icon(Icons.group_rounded, color: Color(0xFF1E6B2E)),
              label: 'Usuarios'),
          if (provider.isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories_rounded, color: Color(0xFF1E6B2E)),
              label: 'Estados'),
          if (provider.isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.bar_chart_rounded),
              selectedIcon: Icon(Icons.bar_chart_rounded, color: Color(0xFF1E6B2E)),
              label: 'Inventario'),
        ],
      ),
    );
  }
}
