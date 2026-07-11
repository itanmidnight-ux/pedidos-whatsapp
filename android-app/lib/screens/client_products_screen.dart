import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';
import '../widgets/empty_state.dart';
import 'client_product_detail.dart';

class ClientProductsScreen extends StatefulWidget {
  const ClientProductsScreen({super.key});
  @override State<ClientProductsScreen> createState() => _ClientProductsScreenState();
}

class _ClientProductsScreenState extends State<ClientProductsScreen>
    with SingleTickerProviderStateMixin {
  List<Product> _all      = [];
  List<Product> _filtered = [];
  String        _category = 'Todos';
  bool          _loading  = true;
  bool          _offline  = false;
  final _searchCtrl = TextEditingController();
  List<String>  _categories = ['Todos'];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    // Cache local primero: pinta al instante sin spinner si ya hay datos --
    // antes cada apertura del catalogo mostraba "cargando" aunque los
    // productos casi nunca cambian entre visitas.
    final cached = await LocalDB.getCachedProducts();
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _all = cached.where((p) => p.available).toList();
        _buildCategories();
        _filter();
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = true);
    }

    List<Product> list;
    bool offline = false;
    try {
      list = await ApiService.getProducts();
      await LocalDB.cacheProducts(list);
    } catch (_) {
      if (cached.isNotEmpty) return; // ya se ve el cache, nada nuevo que aplicar
      list = await LocalDB.getCachedProducts();
      offline = true;
    }
    if (mounted) setState(() {
      _all      = list.where((p) => p.available).toList();
      _offline  = offline;
      _buildCategories();
      _filter();
      _loading  = false;
    });
  }

  void _buildCategories() {
    final cats = <String>{'Todos'};
    if (_all.any((p) => p.favorite)) cats.add('Destacados');
    for (final p in _all) {
      final cat = _detectCategory(p.name);
      if (cat != null) cats.add(cat);
    }
    _categories = cats.toList();
  }

  String? _detectCategory(String name) {
    final n = name.toLowerCase();
    if (n.contains('concentrado') || n.contains('purina') || n.contains('alimento')) return 'Concentrados';
    if (n.contains('bulto') || n.contains('arroba'))   return 'Bultos';
    if (n.contains('pollo') || n.contains('gallina'))  return 'Aves';
    if (n.contains('cerdo') || n.contains('porcino'))  return 'Cerdos';
    if (n.contains('bovino') || n.contains('novill') || n.contains('ganado')) return 'Bovinos';
    if (n.contains('perro') || n.contains('gato') || n.contains('mascota')) return 'Mascotas';
    if (n.contains('vitamina') || n.contains('suplemento')) return 'Suplementos';
    return null;
  }

  String _productDescription(Product p) {
    final n = p.name.toLowerCase();
    if (n.contains('concentrado') || n.contains('alimento')) {
      return 'Alimento balanceado de alta calidad con nutrientes esenciales para el óptimo desarrollo y salud de sus animales.';
    }
    if (n.contains('bulto')) {
      return 'Presentación económica en bulto. Ideal para grandes productores. Excelente relación calidad-precio.';
    }
    if (n.contains('pollo') || n.contains('gallina')) {
      return 'Formulado especialmente para aves de corral. Promueve crecimiento sano y producción eficiente.';
    }
    if (n.contains('cerdo')) {
      return 'Nutrición balanceada para porcinos en todas las etapas de crecimiento. Alta digestibilidad.';
    }
    if (n.contains('bovino') || n.contains('ganado')) {
      return 'Suplemento nutricional premium para bovinos. Optimiza la producción de leche y carne.';
    }
    if (n.contains('perro') || n.contains('mascota')) {
      return 'Alimento premium para su mascota. Ingredientes naturales seleccionados para su bienestar.';
    }
    if (n.contains('vitamina') || n.contains('suplemento')) {
      return 'Suplemento vitamínico esencial. Fortalece el sistema inmune y mejora el rendimiento productivo.';
    }
    return 'Producto de alta calidad, seleccionado para satisfacer las necesidades de sus animales con los mejores estándares nutricionales.';
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = _all.where((p) {
        final matchCat = _category == 'Todos'
          ? true
          : _category == 'Destacados'
            ? p.favorite
            : _detectCategory(p.name) == _category;
        final matchQ = q.isEmpty
          || p.name.toLowerCase().contains(q)
          || p.aliases.any((a) => a.toLowerCase().contains(q));
        return matchCat && matchQ;
      }).toList();
    });
  }

  void _setCategory(String c) {
    setState(() => _category = c);
    _filter();
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.of(context).size;
    final cols   = size.width > 600 ? 3 : 2;
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      // Search bar
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Buscar producto...',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: scheme.primary, size: 22),
            suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, color: Colors.grey.shade400),
                  onPressed: () { _searchCtrl.clear(); _filter(); })
              : null,
            filled: true,
            fillColor: const Color(0xFFF5F5F5),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: scheme.primary, width: 1.5)),
          ),
        ),
      ),
      // Category chips
      if (_categories.length > 1)
        Container(
          color: Colors.white,
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final sel = _category == cat;
              return GestureDetector(
                onTap: () => _setCategory(cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel ? scheme.primary : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? scheme.primary : Colors.grey.shade300, width: 1),
                  ),
                  child: Text(cat,
                    style: TextStyle(
                      color: sel ? Colors.white : Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    )),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 1),

      // Products grid
      Expanded(child: _loading
        ? Center(child: CircularProgressIndicator(color: scheme.primary))
        : _filtered.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _load,
              color: scheme.primary,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Featured banner
                  if (_all.any((p) => p.favorite) && _category == 'Todos' && _searchCtrl.text.isEmpty)
                    SliverToBoxAdapter(child: _featuredSection()),
                  // Grid
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12,
                      MediaQuery.of(context).padding.bottom + 80),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => _ProductCard(
                          product:     _filtered[i],
                          description: _productDescription(_filtered[i]),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ClientProductDetail(
                                product:     _filtered[i],
                                description: _productDescription(_filtered[i]),
                              )));
                          },
                        ),
                        childCount: _filtered.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.68,
                      ),
                    ),
                  ),
                ],
              ),
            )),
    ]);
  }

  Widget _featuredSection() {
    final featured = _all.where((p) => p.favorite).take(5).toList();
    if (featured.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.star_rounded, color: scheme.secondary, size: 18),
          const SizedBox(width: 6),
          Text('Más Solicitados',
            style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 15,
              color: Color.lerp(scheme.primary, Colors.black, 0.5))),
        ]),
      ),
      SizedBox(
        height: 160,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: featured.length,
          itemBuilder: (_, i) {
            final p = featured[i];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => ClientProductDetail(
                  product: p, description: _productDescription(p)))),
              child: Container(
                width: 130,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: SizedBox(
                      height: 90, width: double.infinity,
                      child: p.images.isNotEmpty
                        ? Hero(
                            tag: 'product-image-${p.id}',
                            child: CachedNetworkImage(
                              imageUrl: ApiService.productImageUrl(p.images.first),
                              httpHeaders: ApiService.imageHeaders,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => _ImgPlaceholder()))
                        : _ImgPlaceholder(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 3),
                      Text('\$${_fmt(p.price)}',
                        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      const Divider(height: 12, indent: 16, endIndent: 16),
    ]);
  }

  Widget _emptyState() => EmptyState(
    icon: Icons.inventory_2_rounded,
    title: _searchCtrl.text.isNotEmpty
      ? 'Sin resultados para "${_searchCtrl.text}"'
      : _offline ? 'Sin datos guardados — conecta a internet'
      : 'Sin productos disponibles',
    action: _offline
      ? FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Reintentar'),
        )
      : null,
  );

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(0);
}

class _ProductCard extends StatelessWidget {
  final Product  product;
  final String   description;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.description, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image section
          Expanded(child: Stack(fit: StackFit.expand, children: [
            product.images.isNotEmpty
              ? Hero(
                  tag: 'product-image-${product.id}',
                  child: CachedNetworkImage(
                    imageUrl: ApiService.productImageUrl(product.images.first),
                    httpHeaders: ApiService.imageHeaders,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _ImgPlaceholder(shimmer: true),
                    errorWidget: (_, __, ___) => _ImgPlaceholder()))
              : _ImgPlaceholder(),
            // Gradient overlay bottom
            Positioned(bottom: 0, left: 0, right: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent]),
                ),
              )),
            // Badges
            Positioned(top: 8, left: 8, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.favorite)
                  _Badge(label: 'Destacado', color: scheme.secondary),
                if (!product.noFiado)
                  const _Badge(label: 'Fiado', color: Color(0xFF1565C0)),
              ],
            )),
          ])),
          // Info section
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.3)),
              const SizedBox(height: 3),
              Text(description,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, height: 1.3)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: Text('\$${_fmt(product.price)}',
                  style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 16))),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 14),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(0);
}

class _Badge extends StatelessWidget {
  final String label;
  final Color  color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 3),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
  );
}

class _ImgPlaceholder extends StatelessWidget {
  final bool shimmer;
  const _ImgPlaceholder({this.shimmer = false});
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      color: primary.withValues(alpha: 0.1),
      child: Center(child: Icon(Icons.pets_rounded, color: primary, size: 40)),
    );
  }
}
