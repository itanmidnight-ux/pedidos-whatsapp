import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/order.dart';
import '../models/product.dart';
import '../models/estado.dart';

/// Caché offline para uso en teléfono (sqflite). sqflite no tiene
/// implementación en Flutter Web -- sin el guard `kIsWeb`, cualquier llamada
/// aquí lanza una excepción no manejada la primera vez que algo intenta
/// cachear (por ejemplo dentro del catch de AppProvider.refreshOrders, que
/// usa esto como fallback offline), dejando `loading` trabado en true para
/// siempre: la app entera se queda con el spinner de carga infinito en el
/// navegador. En web esta caché simplemente no aplica (no hay modo offline).
class LocalDB {
  static Database? _db;

  static Future<Database> get _database async {
    if (kIsWeb) throw UnsupportedError('LocalDB no está disponible en Flutter Web');
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    return openDatabase(
      p.join(await getDatabasesPath(), 'monserrath_v2.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cached_products (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            aliases TEXT DEFAULT '[]',
            price REAL NOT NULL,
            available INTEGER DEFAULT 1,
            favorite INTEGER DEFAULT 0,
            no_fiado INTEGER DEFAULT 0,
            images TEXT DEFAULT '[]',
            cached_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_estados (
            id INTEGER PRIMARY KEY,
            admin_username TEXT NOT NULL,
            filename TEXT NOT NULL,
            media_type TEXT NOT NULL DEFAULT 'image',
            caption TEXT,
            created_at TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            heart_count INTEGER DEFAULT 0,
            has_hearted INTEGER DEFAULT 0,
            comment_count INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_orders (
            id INTEGER PRIMARY KEY,
            data_json TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_sync (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action TEXT NOT NULL,
            order_id INTEGER,
            data_json TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE app_state (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ── Products ──────────────────────────────────────────────
  static Future<void> cacheProducts(List<Product> products) async {
    if (kIsWeb) return;
    final db = await _database;
    final batch = db.batch();
    batch.delete('cached_products');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in products) {
      batch.insert('cached_products', {
        'id':        p.id,
        'name':      p.name,
        'aliases':   jsonEncode(p.aliases),
        'price':     p.price,
        'available': p.available ? 1 : 0,
        'favorite':  p.favorite  ? 1 : 0,
        'no_fiado':  p.noFiado   ? 1 : 0,
        'images':    jsonEncode(p.images),
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Product>> getCachedProducts() async {
    if (kIsWeb) return [];
    final db = await _database;
    final rows = await db.query('cached_products', orderBy: 'favorite DESC, name ASC');
    return rows.map((r) => Product(
      id:        r['id']    as int?,
      name:      r['name']  as String,
      aliases:   List<String>.from(jsonDecode(r['aliases'] as String? ?? '[]')),
      price:     (r['price'] as num).toDouble(),
      available: (r['available'] as int) == 1,
      favorite:  (r['favorite']  as int) == 1,
      noFiado:   (r['no_fiado']  as int) == 1,
      images:    List<String>.from(jsonDecode(r['images'] as String? ?? '[]')),
    )).toList();
  }

  // ── Estados ───────────────────────────────────────────────
  static Future<void> cacheEstados(List<Estado> estados) async {
    if (kIsWeb) return;
    final db = await _database;
    final batch = db.batch();
    batch.delete('cached_estados');
    for (final e in estados) {
      batch.insert('cached_estados', {
        'id':            e.id,
        'admin_username': e.adminUsername,
        'filename':      e.filename,
        'media_type':    e.mediaType,
        'caption':       e.caption,
        'created_at':    e.createdAt.toIso8601String(),
        'expires_at':    e.expiresAt.toIso8601String(),
        'heart_count':   e.heartCount,
        'has_hearted':   e.hasHearted ? 1 : 0,
        'comment_count': e.commentCount,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Estado>> getCachedEstados() async {
    if (kIsWeb) return [];
    final db = await _database;
    final rows = await db.query('cached_estados', orderBy: 'created_at DESC');
    final now = DateTime.now();
    return rows
      .map((r) {
        final expires = DateTime.parse(r['expires_at'] as String);
        if (expires.isBefore(now)) return null;
        return Estado(
          id:           r['id']            as int,
          adminUsername: r['admin_username'] as String,
          filename:     r['filename']       as String,
          mediaType:    r['media_type']     as String,
          caption:      r['caption']        as String?,
          createdAt:    DateTime.parse(r['created_at'] as String),
          expiresAt:    expires,
          heartCount:   (r['heart_count']   as int?) ?? 0,
          hasHearted:   ((r['has_hearted']  as int?) ?? 0) == 1,
          commentCount: (r['comment_count'] as int?) ?? 0,
        );
      })
      .where((e) => e != null)
      .cast<Estado>()
      .toList();
  }

  // ── App state (notification tracking) ────────────────────
  static Future<int> getLastEstadoId() async {
    if (kIsWeb) return 0;
    final db  = await _database;
    final row = await db.query('app_state', where: 'key=?', whereArgs: ['last_estado_id']);
    return int.tryParse(row.firstOrNull?['value'] as String? ?? '0') ?? 0;
  }

  static Future<void> setLastEstadoId(int id) async {
    if (kIsWeb) return;
    final db = await _database;
    await db.insert('app_state', {'key': 'last_estado_id', 'value': id.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<int> getLastProductId() async {
    if (kIsWeb) return 0;
    final db  = await _database;
    final row = await db.query('app_state', where: 'key=?', whereArgs: ['last_product_id']);
    return int.tryParse(row.firstOrNull?['value'] as String? ?? '0') ?? 0;
  }

  static Future<void> setLastProductId(int id) async {
    if (kIsWeb) return;
    final db = await _database;
    await db.insert('app_state', {'key': 'last_product_id', 'value': id.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Ultimo status conocido por pedido (id -> status), para detectar cambios
  /// de estado del cliente (en_camino/entregado/cancelled) y notificar.
  static Future<Map<String, String>> getOrderStatuses() async {
    if (kIsWeb) return {};
    final db  = await _database;
    final row = await db.query('app_state', where: 'key=?', whereArgs: ['order_statuses']);
    final raw = row.firstOrNull?['value'] as String?;
    if (raw == null) return {};
    try { return Map<String, String>.from(jsonDecode(raw) as Map); } catch (_) { return {}; }
  }

  static Future<void> setOrderStatuses(Map<String, String> statuses) async {
    if (kIsWeb) return;
    final db = await _database;
    await db.insert('app_state', {'key': 'order_statuses', 'value': jsonEncode(statuses)},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Orders cache ──────────────────────────────────────────
  static Future<void> saveOrders(List<Order> orders) async {
    if (kIsWeb) return;
    final db  = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    batch.delete('cached_orders');
    for (final o in orders) {
      batch.insert('cached_orders', {
        'id':        o.id,
        'data_json': jsonEncode(o.toMap()),
        'cached_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Order>> getOrders() async {
    if (kIsWeb) return [];
    final db   = await _database;
    final rows = await db.query('cached_orders', orderBy: 'id DESC');
    const active = {'pending', 'claimed', 'en_camino'};
    return rows
      .map((r) => Order.fromJson(jsonDecode(r['data_json'] as String)))
      .where((o) => active.contains(o.status))
      .toList();
  }

  // ── Pending sync ──────────────────────────────────────────
  static Future<void> _addSync(String action, int id, {Map<String, dynamic>? data}) async {
    final db = await _database;
    await db.insert('pending_sync', {
      'action':    action,
      'order_id':  id,
      'data_json': data != null ? jsonEncode(data) : null,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingSync() async {
    if (kIsWeb) return [];
    final db   = await _database;
    final rows = await db.query('pending_sync', orderBy: 'id ASC');
    return rows.map((r) => {
      'action': r['action'],
      'id':     r['order_id'],
      if (r['data_json'] != null) ...(jsonDecode(r['data_json'] as String) as Map<String, dynamic>),
    }).toList();
  }

  static Future<void> clearPendingSync() async {
    if (kIsWeb) return;
    final db = await _database;
    await db.delete('pending_sync');
  }

  static Future<void> _updateOrder(int id, void Function(Order o) fn) async {
    final db  = await _database;
    final rows = await db.query('cached_orders', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final order = Order.fromJson(jsonDecode(rows.first['data_json'] as String));
    fn(order);
    await db.update('cached_orders', {
      'data_json': jsonEncode(order.toMap()),
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id=?', whereArgs: [id]);
  }

  static Future<void> markDelivered(int id) async {
    if (kIsWeb) return;
    await _updateOrder(id, (o) => o.status = 'entregado');
    await _addSync('deliver', id);
  }

  static Future<void> updateComment(int id, String comment) async {
    if (kIsWeb) return;
    await _updateOrder(id, (o) => o.comment = comment);
    await _addSync('comment', id, data: {'comment': comment});
  }

  static Future<void> claimOrder(int id) async {
    if (kIsWeb) return;
    await _updateOrder(id, (o) => o.status = 'claimed');
    await _addSync('claim', id);
  }

  static Future<void> unclaimOrder(int id) async {
    if (kIsWeb) return;
    await _updateOrder(id, (o) => o.status = 'pending');
    await _addSync('unclaim', id);
  }

  static Future<void> markEnCamino(int id) async {
    if (kIsWeb) return;
    await _updateOrder(id, (o) => o.status = 'en_camino');
    await _addSync('en_camino', id);
  }

  static Future<void> cancelOrder(int id, String reason) async {
    if (kIsWeb) return;
    await _updateOrder(id, (o) => o.status = 'cancelled');
    await _addSync('cancel', id, data: {'reason': reason});
  }
}
