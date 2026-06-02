import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../screens/chat_screen.dart';

class OrderDetailModal extends StatelessWidget {
  final Order order;
  final ValueChanged<String> onComment;
  final VoidCallback onDeliver;

  const OrderDetailModal({
    super.key, required this.order,
    required this.onComment, required this.onDeliver,
  });

  Widget _row(IconData icon, String label, String value, {Color? color}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color ?? const Color(0xFF2D5016)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(
              fontSize: 11, color: Colors.grey)),
            Text(value, style: TextStyle(
              fontSize: 14, color: color ?? Colors.black87)),
          ])),
      ]),
    );

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(order.requestedAt)?.toLocal();
    final dateStr = date != null
      ? DateFormat('dd/MM/yyyy HH:mm').format(date) : 'N/A';

    return DraggableScrollableSheet(
      initialChildSize: 0.8, minChildSize: 0.5,
      maxChildSize: 0.95, expand: false,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
          ),
          // Header del modal
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(children: [
              const Text('Detalle del Pedido',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: Color(0xFF1A1A1A))),
              const Spacer(),
              if (order.isFiado) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12)),
                child: const Text('FIADO',
                  style: TextStyle(color: Color(0xFFD4800A),
                    fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: ListView(controller: ctrl, padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              _row(Icons.person_outline, 'Cliente',
                order.customerName ?? order.customerPhone ?? 'N/A'),
              _row(Icons.inventory_2_outlined, 'Producto', order.productName),
              if (order.productPrice != null)
                _row(Icons.attach_money, 'Precio',
                  '\$${NumberFormat('#,###', 'es_CO').format(order.productPrice)}',
                  color: const Color(0xFF2D5016)),
              _row(Icons.location_on_outlined, 'Dirección',
                order.deliveryAddress),
              _row(Icons.access_time, 'Solicitado', dateStr),
              if (order.isFiado)
                _row(Icons.warning_amber_rounded, 'Pago',
                  'FIADO — pago pendiente',
                  color: const Color(0xFFD4800A)),
              const Divider(height: 24),
              // Mensaje WA
              const Text('Mensaje original WhatsApp',
                style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 13, color: Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCF8C6),
                  borderRadius: BorderRadius.circular(14)),
                child: Text(order.waMessage,
                  style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
              if (order.comment != null) ...[
                const SizedBox(height: 16),
                const Text('Comentario',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 6),
                Text(order.comment!,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              // BOTÓN ENTREGADO
              FilledButton.icon(
                onPressed: () { onDeliver(); Navigator.pop(context); },
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Marcar como ENTREGADO'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2D5016),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              // BOTÓN ENVIAR MENSAJE
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final phone = order.customerPhone ?? '';
                  if (phone.isEmpty) return;
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      phone: phone,
                      name: order.customerName ?? phone,
                    ),
                  ));
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: Color(0xFF2D5016)),
                label: const Text('Enviar mensaje al cliente',
                  style: TextStyle(color: Color(0xFF2D5016))),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  side: const BorderSide(color: Color(0xFF2D5016)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ]),
      ),
    );
  }
}
