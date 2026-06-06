class Order {
  final int? id;
  final String productName;
  final double? productPrice;
  final String deliveryAddress;
  final bool isFiado;
  String status;
  final String waMessage;
  String? comment;
  final String requestedAt;
  final String? deliveredAt;
  final String? customerName;
  final String? customerPhone;
  final int? claimedBy;
  final String? claimedByName;
  final String? claimedByUsername;
  final String? cancelReason;
  final List<Map<String, dynamic>> items;
  bool pendingSync;

  Order({
    this.id,
    required this.productName,
    this.productPrice,
    required this.deliveryAddress,
    required this.isFiado,
    required this.status,
    required this.waMessage,
    this.comment,
    required this.requestedAt,
    this.deliveredAt,
    this.customerName,
    this.customerPhone,
    this.claimedBy,
    this.claimedByName,
    this.claimedByUsername,
    this.cancelReason,
    this.items = const [],
    this.pendingSync = false,
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id:              j['id'],
    productName:     j['product_name'] ?? '',
    productPrice:    (j['product_price'] as num?)?.toDouble(),
    deliveryAddress: j['delivery_address'] ?? '',
    isFiado:         j['is_fiado'] == 1 || j['is_fiado'] == true,
    status:          j['status'] ?? 'pending',
    waMessage:       j['wa_message'] ?? '',
    comment:         j['comment'],
    requestedAt:     j['requested_at'] ?? '',
    deliveredAt:     j['delivered_at'],
    customerName:    j['customer_name'],
    customerPhone:   j['phone'],
    claimedBy:           j['claimed_by'],
    claimedByName:       j['claimed_by_display'] ?? j['claimed_by_name'],
    claimedByUsername:   j['claimed_by_name'],
    cancelReason:        j['cancel_reason'],
    items:           (j['items'] as List?)?.cast<Map<String, dynamic>>() ?? [],
  );

  bool get isActive  => ['pending', 'claimed', 'en_camino'].contains(status);
  bool get isClaimed => claimedBy != null;
  String get statusLabel {
    switch (status) {
      case 'pending':   return 'Pendiente';
      case 'claimed':   return 'Reclamado por ${claimedByName ?? '?'}';
      case 'en_camino': return 'En camino • ${claimedByName ?? '?'}';
      case 'entregado':
      case 'delivered': return 'Entregado';
      case 'cancelled': return 'Cancelado';
      default:          return status;
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'product_name': productName, 'product_price': productPrice,
    'delivery_address': deliveryAddress, 'is_fiado': isFiado ? 1 : 0,
    'status': status, 'wa_message': waMessage, 'comment': comment,
    'requested_at': requestedAt, 'delivered_at': deliveredAt,
    'customer_name': customerName, 'customer_phone': customerPhone,
    'claimed_by': claimedBy, 'claimed_by_name': claimedByName,
    'cancel_reason': cancelReason,
    'pending_sync': pendingSync ? 1 : 0,
  };
}
