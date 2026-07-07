import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cart_item.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';

class ClientCartScreen extends StatefulWidget {
  const ClientCartScreen({super.key});
  @override State<ClientCartScreen> createState() => ClientCartScreenState();
}

class ClientCartScreenState extends State<ClientCartScreen> {
  List<CartItem> _items = [];
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void reload() { if (mounted) _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ApiService.getCart();
      if (mounted) setState(() => _items = items);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _remove(CartItem item) async {
    try {
      await ApiService.removeFromCart(item.productId);
      await _load();
    } catch (_) {}
  }

  double get _total => _items.fold(0, (s, i) => s + i.subtotal);

  Future<void> _checkout() async {
    if (_items.isEmpty) return;

    final method = await _pickPaymentMethod();
    if (method == null) return;

    if (method == 'nequi') {
      await _nequiFlow();
    } else {
      await _contraEntregaFlow();
    }
  }

  Future<String?> _pickPaymentMethod() async {
    Map<String, String>? settings;
    try { settings = await ApiService.getSettings(); } catch (_) {}
    final nequiPhone = settings?['nequi_phone'] ?? '';
    final nequiName  = settings?['nequi_name']  ?? 'Concentrados Monserrath';

    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Método de pago', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _PayOption(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Nequi',
            subtitle: 'Transferencia Nequi — $nequiPhone\n$nequiName',
            color: Colors.purple,
            onTap: () => Navigator.pop(_, 'nequi'),
          ),
          const SizedBox(height: 10),
          _PayOption(
            icon: Icons.local_shipping_rounded,
            title: 'Contra entrega',
            subtitle: 'Pago en efectivo al recibir',
            color: Colors.orange,
            onTap: () => Navigator.pop(_, 'contra_entrega'),
          ),
        ]),
      ),
    );
  }

  Future<void> _nequiFlow() async {
    Map<String, String>? settings;
    try { settings = await ApiService.getSettings(); } catch (_) {}
    final nequiPhone = settings?['nequi_phone'] ?? '';
    final nequiName  = settings?['nequi_name']  ?? 'Concentrados Monserrath';
    final totalStr   = '\$${_fmt(_total)}';

    final refCtrl = TextEditingController();
    final ref = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Pago Nequi'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Enviar $totalStr a:', style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(nequiName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(nequiPhone, style: const TextStyle(fontSize: 18, color: Colors.purple, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('Número de referencia Nequi:',
            style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: refCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Ej: 1234567890',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, null), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
            onPressed: () {
              if (refCtrl.text.trim().isEmpty) return;
              Navigator.pop(_, refCtrl.text.trim());
            },
            child: const Text('Confirmar pedido'),
          ),
        ],
      ),
    );
    if (ref == null) return;
    await _doCheckout(paymentMethod: 'nequi', nequiReference: ref);
  }

  Future<void> _contraEntregaFlow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contra entrega'),
        content: Text('Total a pagar: \$${_fmt(_total)}\n\nConfirmar pedido con pago en efectivo al recibir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Confirmar pedido'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _doCheckout(paymentMethod: 'contra_entrega');
  }

  Future<void> _doCheckout({required String paymentMethod, String? nequiReference}) async {
    setState(() => _checking = true);
    try {
      await ApiService.checkout(
        paymentMethod: paymentMethod,
        nequiReference: nequiReference,
        deliveryDate: _items.isNotEmpty ? _items.first.deliveryDate : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('¡Pedido realizado exitosamente!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _items = []);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _fmt(double v) => NumberFormat.currency(locale: 'es_CO', symbol: '', decimalDigits: 0).format(v);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: const Text('Mi carrito'),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: () async {
                await ApiService.clearCart();
                _load();
              },
              child: const Text('Vaciar', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.shopping_cart_outlined,
                  title: 'Tu carrito está vacío',
                  action: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Ver productos'),
                  ),
                )
              : Column(children: [
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AppCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('\$${_fmt(item.price)} c/u',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                              if (item.deliveryDate != null)
                                Text('Entrega: ${item.deliveryDate}',
                                  style: TextStyle(color: scheme.primary, fontSize: 12)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('\$${_fmt(item.subtotal)}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary, fontSize: 15)),
                              Text('x${item.quantity}',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                            ]),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () => _remove(item),
                            ),
                          ]),
                        ),
                      );
                    },
                  )),

                  // Total + checkout
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
                    ),
                    child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('\$${_fmt(_total)}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: scheme.primary)),
                      ]),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, height: 52,
                        child: AppButton(
                          label: _checking ? 'Procesando...' : 'Realizar pedido',
                          onPressed: _checking ? null : _checkout,
                          loading: _checking,
                          icon: Icons.payment_rounded,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ])),
                  ),
                ]),
    );
  }
}

class _PayOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _PayOption({required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey.shade400),
      ]),
    ),
  );
}
