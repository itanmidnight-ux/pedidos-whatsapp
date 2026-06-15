import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/estado.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/local_db.dart';
import 'client_products_screen.dart';
import 'client_cart_screen.dart';
import 'client_estados_screen.dart';
import 'client_profile_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> with WidgetsBindingObserver {
  static const _green = Color(0xFF1E6B2E);
  static const _gold  = Color(0xFFD4800A);

  int  _tab       = 0;
  int  _newEstados = 0;
  bool _isOnline  = true;
  List<Estado> _estados = [];

  final _cartKey = GlobalKey<ClientCartScreenState>();
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initConnectivity();
    _loadEstados();
    NotificationService.startPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadEstados();
      NotificationService.startPolling();
    } else if (state == AppLifecycleState.paused) {
      NotificationService.stopPolling();
    }
  }

  void _initConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted) setState(() => _isOnline = online);
      if (online) _loadEstados();
    });
  }

  Future<void> _loadEstados() async {
    try {
      List<Estado> list;
      if (_isOnline) {
        list = await ApiService.getEstados();
        await LocalDB.cacheEstados(list);
      } else {
        list = await LocalDB.getCachedEstados();
      }
      if (mounted) setState(() {
        _estados = list;
        _newEstados = list.length;
      });
    } catch (_) {
      final cached = await LocalDB.getCachedEstados();
      if (mounted) setState(() => _estados = cached);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    NotificationService.stopPolling();
    super.dispose();
  }

  void _goToEstados() {
    setState(() { _tab = 2; _newEstados = 0; });
  }

  void _goToProfile() {
    setState(() => _tab = 3);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      body: Column(children: [
        // ── Status bar + Header ───────────────────────────
        _buildHeader(size),
        // ── Connectivity banner ───────────────────────────
        if (!_isOnline)
          Container(
            color: Colors.orange.shade700,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Row(children: [
              const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              const Expanded(child: Text('Sin conexión — mostrando datos guardados',
                style: TextStyle(color: Colors.white, fontSize: 12))),
            ]),
          ),
        // ── Content ───────────────────────────────────────
        Expanded(child: IndexedStack(index: _tab, children: [
          const ClientProductsScreen(),
          ClientCartScreen(key: _cartKey),
          ClientEstadosScreen(
            estados: _estados,
            onRefresh: _loadEstados,
          ),
          const ClientProfileScreen(),
        ])),
      ]),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader(Size size) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3009), Color(0xFF1E6B2E), Color(0xFF2D8040)],
        ),
      ),
      child: SafeArea(bottom: false, child: Column(children: [
        // AppBar row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            // Logo
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Center(child: Text('🌾', style: TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Concentrados', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1)),
                Text('Monserrath', style: TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, height: 1.1)),
              ],
            )),
            // Online/offline indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green.shade700 : Colors.orange.shade700,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(_isOnline ? 'En línea' : 'Sin conexión',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 8),
            // Logout
            GestureDetector(
              onTap: () => _confirmLogout(),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.white70, size: 18),
              ),
            ),
          ]),
        ),
        // Story circles (estados preview) — only show if not on estados tab
        if (_estados.isNotEmpty && _tab != 2)
          _buildEstadosPreview(),
        const SizedBox(height: 4),
      ])),
    );
  }

  Widget _buildEstadosPreview() {
    return GestureDetector(
      onTap: _goToEstados,
      child: Container(
        height: 88,
        margin: const EdgeInsets.only(bottom: 4),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _estados.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) {
              return _StoryCircle(
                label: 'Ver todo',
                isNew: _newEstados > 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFFD4800A), Color(0xFFFF9800)]),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 28),
                ),
                onTap: _goToEstados,
              );
            }
            final e = _estados[i - 1];
            return _StoryCircle(
              label: e.adminUsername,
              isNew: true,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF1E6B2E), Color(0xFF4CAF50)]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 24),
              ),
              onTap: _goToEstados,
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) {
        setState(() { _tab = i; });
        if (i == 1) _cartKey.currentState?.reload();
        if (i == 2) setState(() => _newEstados = 0);
      },

      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFC8E6C9),
      elevation: 8,
      shadowColor: Colors.black26,
      destinations: [
        const NavigationDestination(
          icon:         Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront_rounded, color: _green),
          label: 'Tienda',
        ),
        const NavigationDestination(
          icon:         Icon(Icons.shopping_cart_outlined),
          selectedIcon: Icon(Icons.shopping_cart_rounded, color: _green),
          label: 'Carrito',
        ),
        NavigationDestination(
          icon: Stack(clipBehavior: Clip.none, children: [
            const Icon(Icons.auto_stories_outlined),
            if (_newEstados > 0)
              Positioned(right: -4, top: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                  child: Text('$_newEstados',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                )),
          ]),
          selectedIcon: const Icon(Icons.auto_stories_rounded, color: _green),
          label: 'Estados',
        ),
        const NavigationDestination(
          icon:         Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: _green),
          label: 'Perfil',
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas salir de tu cuenta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok == true && mounted) {
      NotificationService.stopPolling();
      context.read<AppProvider>().logout();
    }
  }
}

class _StoryCircle extends StatelessWidget {
  final Widget child;
  final String label;
  final bool isNew;
  final VoidCallback onTap;
  const _StoryCircle({required this.child, required this.label, required this.isNew, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 56, height: 56,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isNew
              ? const LinearGradient(colors: [Color(0xFFD4800A), Color(0xFFFF9800)])
              : null,
            color: isNew ? null : Colors.white24,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1A3009),
              shape: BoxShape.circle,
            ),
            child: child,
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
      ]),
    ),
  );
}
