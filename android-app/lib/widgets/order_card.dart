import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart';
import 'order_detail_modal.dart';

class OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onDeliver;
  final ValueChanged<String> onComment;
  final VoidCallback? onClaim;
  final VoidCallback? onUnclaim;
  final VoidCallback? onEnCamino;
  final VoidCallback? onTake;
  final ValueChanged<String>? onCancel;

  const OrderCard({
    super.key,
    required this.order,
    required this.onDeliver,
    required this.onComment,
    this.onClaim,
    this.onUnclaim,
    this.onEnCamino,
    this.onTake,
    this.onCancel,
  });

  bool get _isOverdue {
    final d = DateTime.tryParse(order.requestedAt);
    return d != null && DateTime.now().difference(d).inDays >= 1;
  }

  String get _timeLabel {
    final d = DateTime.tryParse(order.requestedAt);
    return d == null ? '' : DateFormat('dd/MM h:mm a').format(d.toLocal());
  }

  void _callClient() async {
    final phone = order.customerPhone;
    if (phone == null) return;
    final uri = Uri.parse('tel:+$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  void _sendWhatsApp(BuildContext ctx) async {
    final phone = order.customerPhone;
    if (phone == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Cliente sin número de teléfono')));
      return;
    }
    final uri = Uri.parse('https://wa.me/$phone');
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showDetail(BuildContext ctx) => showModalBottomSheet(
    context: ctx, isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => OrderDetailModal(order: order, onComment: onComment, onDeliver: onDeliver),
  );

  void _showCancelDialog(BuildContext ctx) {
    final ctrl = TextEditingController();
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Cancelar pedido'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Motivo de cancelación...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Volver')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () { if (ctrl.text.trim().isNotEmpty) { onCancel?.call(ctrl.text.trim()); Navigator.pop(ctx); } },
          child: const Text('Cancelar pedido'),
        ),
      ],
    ));
  }

  void _showCommentDialog(BuildContext ctx) {
    final ctrl = TextEditingController(text: order.comment);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Comentario'),
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Escribe un comentario...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () { onComment(ctrl.text); Navigator.pop(ctx); }, child: const Text('Guardar')),
      ],
    ));
  }

  void _showMenu(BuildContext ctx) {
    final isClaimed = order.isClaimed;
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        // Customer name header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            order.customerName ?? order.customerPhone ?? 'Cliente',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(order.productName, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
        const Divider(height: 20),
        // Tomar pedido (claim + en_camino in one step)
        if (!isClaimed && onTake != null)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF2D5016),
              child: Icon(Icons.directions_bike, color: Colors.white, size: 18)),
            title: const Text('Tomar pedido', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Te asigna este pedido y lo pone en camino'),
            onTap: () { Navigator.pop(ctx); onTake?.call(); }),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFF1A6B2E),
            child: Icon(Icons.check_circle, color: Colors.white, size: 18)),
          title: const Text('Marcar entregado'),
          onTap: () { Navigator.pop(ctx); onDeliver(); }),
        if (order.customerPhone != null)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF25D366),
              child: Icon(Icons.chat, color: Colors.white, size: 18)),
            title: const Text('Enviar mensaje WhatsApp'),
            subtitle: Text(order.customerPhone!),
            onTap: () { Navigator.pop(ctx); _sendWhatsApp(ctx); }),
        if (order.customerPhone != null)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(Icons.phone, color: Colors.white, size: 18)),
            title: Text('Llamar a ${order.customerName ?? order.customerPhone}'),
            onTap: () { Navigator.pop(ctx); _callClient(); }),
        if (isClaimed && onUnclaim != null)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.orange,
              child: Icon(Icons.person_remove, color: Colors.white, size: 18)),
            title: const Text('Liberar pedido'),
            onTap: () { Navigator.pop(ctx); onUnclaim?.call(); }),
        if (isClaimed && onEnCamino != null && order.status != 'en_camino')
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF2D5016),
              child: Icon(Icons.directions_bike, color: Colors.white, size: 18)),
            title: const Text('Marcar en camino'),
            onTap: () { Navigator.pop(ctx); onEnCamino?.call(); }),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.grey,
            child: Icon(Icons.comment, color: Colors.white, size: 18)),
          title: const Text('Agregar comentario'),
          onTap: () { Navigator.pop(ctx); _showCommentDialog(ctx); }),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.blueGrey,
            child: Icon(Icons.info_outline, color: Colors.white, size: 18)),
          title: const Text('Ver detalle'),
          onTap: () { Navigator.pop(ctx); _showDetail(ctx); }),
        if (onCancel != null)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(Icons.cancel, color: Colors.white, size: 18)),
            title: const Text('Cancelar pedido', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(ctx); _showCancelDialog(ctx); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    final statusColor = switch (order.status) {
      'claimed'   => const Color(0xFFD4800A),
      'en_camino' => const Color(0xFF2D5016),
      _           => Colors.grey,
    };
    final showTakeButton = !order.isClaimed && onTake != null && order.status == 'pending';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Slidable(
        endActionPane: ActionPane(motion: const DrawerMotion(), children: [
          SlidableAction(
            onPressed: (_) => onDeliver(),
            backgroundColor: const Color(0xFF2D5016),
            foregroundColor: Colors.white,
            icon: Icons.check_circle_rounded,
            label: 'ENTREGADO',
            borderRadius: BorderRadius.circular(16),
          ),
        ]),
        startActionPane: order.isClaimed
          ? ActionPane(motion: const DrawerMotion(), children: [
              SlidableAction(
                onPressed: (_) => onUnclaim?.call(),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                icon: Icons.person_remove,
                label: 'LIBERAR',
                borderRadius: BorderRadius.circular(16),
              ),
            ])
          : ActionPane(motion: const DrawerMotion(), children: [
              SlidableAction(
                onPressed: (_) { if (onTake != null) onTake!(); else onClaim?.call(); },
                backgroundColor: const Color(0xFF2D5016),
                foregroundColor: Colors.white,
                icon: Icons.directions_bike,
                label: 'TOMAR',
                borderRadius: BorderRadius.circular(16),
              ),
            ]),
        child: GestureDetector(
          onTap: () => _showMenu(ctx),
          child: Card(
            elevation: order.isClaimed ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: order.isClaimed
                ? BorderSide(color: statusColor.withOpacity(0.5), width: 1.5)
                : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Header: nombre + badges
                Row(children: [
                  Expanded(child: Text(
                    order.customerName ?? order.customerPhone ?? 'Cliente',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                  if (order.isFiado) _badge('FIADO', Colors.orange),
                  if (order.isClaimed) ...[
                    const SizedBox(width: 4),
                    _badge(order.statusLabel, statusColor),
                  ],
                ]),
                const SizedBox(height: 6),
                // Producto
                Row(children: [
                  const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.green),
                  const SizedBox(width: 4),
                  Expanded(child: Text(order.productName, style: const TextStyle(fontSize: 14))),
                  if (order.productPrice != null)
                    Text('\$${NumberFormat('#,###', 'es_CO').format(order.productPrice)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2D5016))),
                ]),
                const SizedBox(height: 4),
                // Dirección
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(child: Text(order.deliveryAddress,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                ]),
                // Footer: hora + overdue + comentario + llamar
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.access_time, size: 14, color: _isOverdue ? Colors.red : Colors.grey),
                  const SizedBox(width: 4),
                  Text(_timeLabel, style: TextStyle(
                    fontSize: 12,
                    color: _isOverdue ? Colors.red : Colors.grey.shade600,
                    fontWeight: _isOverdue ? FontWeight.bold : FontWeight.normal)),
                  if (_isOverdue) ...[
                    const SizedBox(width: 6),
                    _badge('PENDIENTE', Colors.red),
                  ],
                  const Spacer(),
                  if (order.comment != null)
                    const Icon(Icons.comment, size: 14, color: Colors.grey),
                  if (order.customerPhone != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _sendWhatsApp(ctx),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.chat, size: 16, color: Color(0xFF25D366))),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _callClient,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(Icons.phone, size: 16, color: Colors.blue)),
                    ),
                  ],
                ]),
                // TOMAR PEDIDO button — visible for unclaimed orders
                if (showTakeButton) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2D5016),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.directions_bike, size: 16),
                      label: const Text('TOMAR PEDIDO', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      onPressed: onTake,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      border: Border.all(color: color.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(12)),
    child: Text(text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
  );
}
