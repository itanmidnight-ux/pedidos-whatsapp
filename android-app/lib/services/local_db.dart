import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';

class LocalDB {
  static const _ordersKey     = 'cached_orders';
  static const _pendingSyncKey = 'pending_sync';

  static final _activeStatuses = {'pending', 'claimed', 'en_camino'};

  static Future<void> saveOrders(List<Order> orders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_ordersKey, orders.map((o) => jsonEncode(o.toMap())).toList());
  }

  static Future<List<Order>> getOrders() async {
    final all = await _getAllOrders();
    return all.where((o) => _activeStatuses.contains(o.status)).toList();
  }

  static Future<List<Order>> _getAllOrders() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_ordersKey) ?? [])
        .map((s) => Order.fromJson(jsonDecode(s)))
        .toList();
  }

  static Future<void> _updateOrder(int id, void Function(Order o) update) async {
    final orders = await _getAllOrders();
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx >= 0) { update(orders[idx]); await saveOrders(orders); }
  }

  static Future<void> _addPendingSync(Map<String, dynamic> action) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_pendingSyncKey) ?? [];
    list.add(jsonEncode(action));
    await prefs.setStringList(_pendingSyncKey, list);
  }

  // ── Actions ───────────────────────────────────────────────
  static Future<void> markDelivered(int id) async {
    await _updateOrder(id, (o) { o.status = 'entregado'; o.pendingSync = true; });
    await _addPendingSync({'action': 'deliver', 'id': id});
  }

  static Future<void> updateComment(int id, String comment) async {
    await _updateOrder(id, (o) { o.comment = comment; o.pendingSync = true; });
    await _addPendingSync({'action': 'comment', 'id': id, 'comment': comment});
  }

  static Future<void> claimOrder(int id) async {
    await _updateOrder(id, (o) { o.status = 'claimed'; o.pendingSync = true; });
    await _addPendingSync({'action': 'claim', 'id': id});
  }

  static Future<void> unclaimOrder(int id) async {
    await _updateOrder(id, (o) { o.status = 'pending'; o.pendingSync = true; });
    await _addPendingSync({'action': 'unclaim', 'id': id});
  }

  static Future<void> markEnCamino(int id) async {
    await _updateOrder(id, (o) { o.status = 'en_camino'; o.pendingSync = true; });
    await _addPendingSync({'action': 'en_camino', 'id': id});
  }

  static Future<void> cancelOrder(int id, String reason) async {
    await _updateOrder(id, (o) { o.status = 'cancelled'; o.pendingSync = true; });
    await _addPendingSync({'action': 'cancel', 'id': id, 'reason': reason});
  }

  static Future<List<Map<String, dynamic>>> getPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingSyncKey) ?? [])
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> clearPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingSyncKey);
  }
}
