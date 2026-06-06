class CartItem {
  final int? id;
  final int productId;
  final String productName;
  final double price;
  int quantity;
  String? deliveryDate;

  CartItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.deliveryDate,
  });

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
    id:           j['id'],
    productId:    j['product_id'],
    productName:  j['product_name'] ?? '',
    price:        (j['price'] as num).toDouble(),
    quantity:     j['quantity'] ?? 1,
    deliveryDate: j['delivery_date'],
  );

  double get subtotal => price * quantity;
}
