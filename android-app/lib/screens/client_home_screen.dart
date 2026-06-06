import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/estado.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import 'client_products_screen.dart';
import 'client_cart_screen.dart';
import 'client_estados_viewer.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  static const _green = Color(0xFF1E6B2E);
  int _tab = 0;
  List<Estado> _estados = [];

  @override
  void initState() {
    super.initState();
    _loadEstados();
  }

  Future<void> _loadEstados() async {
    try {
      final list = await ApiService.getEstados();
      if (mounted) setState(() => _estados = list);
    } catch (_) {}
  }

  void _openEstados() {
    if (_estados.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ClientEstadosViewer(estados: _estados)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        backgroundColor: _green,
        title: Row(children: [
          const Text('Concentrados', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(width: 4),
          const Text('Monserrath', style: TextStyle(color: Colors.white70, fontSize: 17)),
        ]),
        actions: [
          if (_estados.isNotEmpty)
            Stack(children: [
              IconButton(
                icon: const Icon(Icons.auto_stories_rounded, color: Colors.white),
                tooltip: 'Estados',
                onPressed: _openEstados,
              ),
              Positioned(right: 8, top: 8,
                child: Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.orange, shape: BoxShape.circle),
                )),
            ]),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final ok = await showDialog<bool>(
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
              if (ok == true && context.mounted) {
                context.read<AppProvider>().logout();
              }
            },
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: const [
        ClientProductsScreen(),
      ]),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              backgroundColor: _green,
              onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ClientCartScreen())),
              child: const Icon(Icons.shopping_cart_rounded, color: Colors.white),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFC8E6C9),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.storefront_outlined),
            selectedIcon: const Icon(Icons.storefront_rounded, color: _green),
            label: 'Productos'),
        ],
      ),
    );
  }
}
