import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../theme/breakpoints.dart';
import '../widgets/order_card.dart';
import '../widgets/company_header.dart';
import '../widgets/empty_state.dart';
import 'products_screen.dart';
import 'messages_screen.dart';
import 'users_screen.dart';
import 'admin_analytics_screen.dart';
import 'admin_estados_screen.dart';
import 'admin_settings_screen.dart';
import 'inventario_screen.dart';
import 'worker_estados_screen.dart';

// Filter chips
const _allStatuses = ['pending', 'claimed', 'en_camino'];
final _statusLabels = {'pending': 'Pendientes', 'claimed': 'Reclamados', 'en_camino': 'En camino'};

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  int _tab = 0;
  Set<String> _filter = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<AppProvider>();
      p.refreshAll();
      p.startAutoRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<AppProvider>().stopAutoRefresh();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final p = context.read<AppProvider>();
    if (state == AppLifecycleState.resumed) {
      p.refreshAll();
      p.startAutoRefresh();
    } else if (state == AppLifecycleState.paused) {
      p.stopAutoRefresh();
    }
  }

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
    final scheme = Theme.of(context).colorScheme;
    final bottomTitles = provider.isAdmin
        ? const ['Pedidos Activos', 'Productos', 'Mensajes']
        : const ['Pedidos Activos', 'Mensajes'];
    final safeTab = _tab < bottomTitles.length ? _tab : 0;

    final isWide = MediaQuery.of(context).size.width >= kDesktopBreakpoint;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: CompanyHeader(
        pageTitle: bottomTitles[safeTab],
        actions: [
          if (!provider.isOnline)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Sin conexión',
                child: Icon(Icons.wifi_off, color: scheme.secondary, size: 20),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () => provider.refreshAll(),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          DrawerHeader(
            decoration: BoxDecoration(color: scheme.primary),
            child: const Align(alignment: Alignment.bottomLeft,
              child: Text('Menú', style: TextStyle(color: Colors.white, fontSize: 20))),
          ),
          if (provider.isAdmin) ...[
            const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('NEGOCIO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1))),
            ListTile(leading: const Icon(Icons.bar_chart_rounded), title: const Text('Analíticas'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAnalyticsScreen())); }),
            ListTile(leading: const Icon(Icons.bar_chart_rounded), title: const Text('Inventario'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const InventarioScreen())); }),
            ListTile(leading: const Icon(Icons.auto_stories_rounded), title: const Text('Estados'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminEstadosScreen())); }),
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('SISTEMA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1))),
            ListTile(leading: const Icon(Icons.group_rounded), title: const Text('Usuarios'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen())); }),
            ListTile(leading: const Icon(Icons.settings_rounded), title: const Text('Configuración'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Configuración')),
                body: const AdminSettingsScreen()))); }),
          ] else
            ListTile(leading: const Icon(Icons.auto_stories_rounded), title: const Text('Estados'),
              onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkerEstadosScreen())); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.logout_rounded), title: const Text('Cerrar sesión'),
            onTap: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                title: const Text('Cerrar sesión'), content: const Text('¿Deseas cerrar sesión?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
                ]));
              if (confirm == true && context.mounted) context.read<AppProvider>().logout();
            }),
        ]),
      ),
      body: _buildBody(context, provider, scheme, safeTab, isWide),
      bottomNavigationBar: isWide ? null : _buildBottomNav(provider, scheme, safeTab),
    );
  }

  Widget _buildBody(BuildContext context, AppProvider provider, ColorScheme scheme, int safeTab, bool isWide) {
    final content = IndexedStack(index: safeTab, children: [
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
                  selectedColor: scheme.primary.withValues(alpha: 0.16),
                  checkmarkColor: scheme.primary,
                ),
              )).toList(),
            ),
          ),
          Expanded(child: RefreshIndicator(
            onRefresh: provider.refreshOrders,
            color: scheme.primary,
            child: () {
              if (provider.loading) return Center(child: CircularProgressIndicator(color: scheme.primary));
              final sorted = _sortedOrders(provider.orders);
              if (sorted.isEmpty) return ListView(children: [
                const SizedBox(height: 100),
                const EmptyState(
                  icon: Icons.inventory_2_rounded,
                  title: 'No hay pedidos activos',
                  subtitle: 'Desliza para actualizar',
                ),
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
      ]);

    if (!isWide) return content;

    // Desktop/TV: rail lateral en vez de nav inferior -- una barra de 72px
    // pegada abajo del todo se ve fuera de lugar en una pantalla grande.
    return Row(children: [
      NavigationRail(
        selectedIndex: safeTab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        labelType: NavigationRailLabelType.all,
        backgroundColor: Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        destinations: _navDestinations(provider, scheme)
            .map((d) => NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label)))
            .toList(),
      ),
      const VerticalDivider(width: 1),
      Expanded(child: content),
    ]);
  }

  Widget _buildBottomNav(AppProvider provider, ColorScheme scheme, int safeTab) {
    return NavigationBar(
      selectedIndex: safeTab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      backgroundColor: Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      destinations: _navDestinations(provider, scheme)
          .map((d) => NavigationDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: d.label))
          .toList(),
    );
  }

  List<_NavItem> _navDestinations(AppProvider provider, ColorScheme scheme) => [
        _NavItem(
          icon: Badge(
            isLabelVisible: provider.orders.isNotEmpty,
            label: Text('${provider.orders.length}'),
            backgroundColor: scheme.secondary,
            child: const Icon(Icons.dashboard_rounded)),
          selectedIcon: Icon(Icons.dashboard_rounded, color: scheme.primary),
          label: 'Pedidos'),
        if (provider.isAdmin)
          _NavItem(
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded, color: scheme.primary),
            label: 'Productos'),
        _NavItem(
          icon: Badge(
            isLabelVisible: provider.flaggedCount > 0,
            label: Text('${provider.flaggedCount}'),
            backgroundColor: Colors.red,
            child: const Icon(Icons.chat_bubble_outline_rounded)),
          selectedIcon: Badge(
            isLabelVisible: provider.flaggedCount > 0,
            label: Text('${provider.flaggedCount}'),
            backgroundColor: Colors.red,
            child: Icon(Icons.chat_bubble_rounded, color: scheme.primary)),
          label: 'Mensajes'),
      ];
}

class _NavItem {
  final Widget icon;
  final Widget selectedIcon;
  final String label;
  const _NavItem({required this.icon, required this.selectedIcon, required this.label});
}
