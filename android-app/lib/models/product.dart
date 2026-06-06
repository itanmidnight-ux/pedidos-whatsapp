class Product {
  final int? id;
  final String name;
  final List<String> aliases;
  final double price;
  final bool available;
  final bool favorite;
  final bool noFiado;
  final List<String> images;

  Product({
    this.id, required this.name, required this.aliases,
    required this.price, this.available = true,
    this.favorite = false, this.noFiado = false,
    this.images = const [],
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'], name: j['name'],
    aliases: (j['aliases'] is List) ? List<String>.from(j['aliases']) : [],
    price: (j['price'] as num).toDouble(),
    available: j['available'] == 1 || j['available'] == true,
    favorite: j['favorite'] == 1 || j['favorite'] == true,
    noFiado: j['no_fiado'] == 1 || j['no_fiado'] == true,
    images: (j['images'] is List) ? List<String>.from(j['images']) : [],
  );

  Map<String, dynamic> toJson() => {
    'name': name, 'price': price, 'aliases': aliases,
    'available': available ? 1 : 0,
    'favorite': favorite ? 1 : 0,
    'no_fiado': noFiado ? 1 : 0,
  };
}
