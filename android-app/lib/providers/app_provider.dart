import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/order.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/local_db.dart';

class AppProvider extends ChangeNotifier {
  bool isLoggedIn    = ApiService.isConfigured;
  bool isOnline      = true;
  bool get isAdmin   => ApiService.isAdmin;
  String get currentRole => ApiService.currentRole;
  List<Order>                   orders   = [];
  List<Product>                 products = [];
  List<Map<String, dynamic>>    users    = [];
  int  flaggedCount = 0;
  bool loading      = false;

  Future<bool> _checkOnline() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.serverUrl}/health'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<void> logout() async {
    await ApiService.logout();
    isLoggedIn = false;
    orders = []; products = []; users = [];
    notifyListeners();
  }

  Future<void> login(String username, String pin) async {
    final result = await ApiService.login(username, pin);
    await ApiService.saveConfig(
      result['token']!, result['username']!,
      role: result['role'] ?? 'worker',
      displayName: result['display_name'] ?? result['username']!,
    );
    isLoggedIn = true; isOnline = true;
    notifyListeners();
    await refreshAll();
  }

  Future<void> refreshAll() async {
    isOnline = await _checkOnline();
    await Future.wait([refreshOrders(), refreshProducts(), refreshFlagged()]);
    if (isAdmin && isOnline) await refreshUsers();
  }

  Future<void> refreshFlagged() async {
    try {
      if (isOnline) { flaggedCount = (await ApiService.getFlaggedMessages()).length; notifyListeners(); }
    } catch (_) {}
  }

  Future<void> refreshOrders() async {
    loading = true; notifyListeners();
    try {
      if (isOnline) {
        final fresh = await ApiService.getOrders();
        await LocalDB.saveOrders(fresh);
        orders = fresh;
      } else { orders = await LocalDB.getOrders(); }
    } catch (_) { orders = await LocalDB.getOrders(); }
    loading = false; notifyListeners();
  }

  Future<void> refreshProducts() async {
    try { if (isOnline) { products = await ApiService.getProducts(); notifyListeners(); } }
    catch (_) {}
  }

  Future<void> refreshUsers() async {
    try { users = await ApiService.getUsers(); notifyListeners(); }
    catch (_) {}
  }

  // ── Order lifecycle ───────────────────────────────────────
  Future<void> claimOrder(int id) async {
    if (isOnline) {
      final updated = await ApiService.claimOrder(id);
      _updateOrderInList(updated);
    } else { await LocalDB.claimOrder(id); }
    notifyListeners();
  }

  Future<void> unclaimOrder(int id) async {
    if (isOnline) {
      final updated = await ApiService.unclaimOrder(id);
      _updateOrderInList(updated);
    } else { await LocalDB.unclaimOrder(id); }
    notifyListeners();
  }

  Future<void> markEnCamino(int id) async {
    if (isOnline) {
      final updated = await ApiService.markEnCamino(id);
      _updateOrderInList(updated);
    } else { await LocalDB.markEnCamino(id); }
    notifyListeners();
  }

  Future<void> cancelOrder(int id, String reason) async {
    if (isOnline) { await ApiService.cancelOrder(id, reason); }
    else { await LocalDB.cancelOrder(id, reason); }
    orders.removeWhere((o) => o.id == id); notifyListeners();
  }

  Future<void> deliverOrder(int id) async {
    if (isOnline) { await ApiService.deliverOrder(id); }
    else { await LocalDB.markDelivered(id); }
    orders.removeWhere((o) => o.id == id); notifyListeners();
  }

  Future<void> addComment(int id, String comment) async {
    if (isOnline) { await ApiService.addComment(id, comment); }
    else { await LocalDB.updateComment(id, comment); }
    final idx = orders.indexWhere((o) => o.id == id);
    if (idx >= 0) { orders[idx].comment = comment; notifyListeners(); }
  }

  void _updateOrderInList(Order updated) {
    final idx = orders.indexWhere((o) => o.id == updated.id);
    if (idx >= 0) orders[idx] = updated; else orders.insert(0, updated);
  }

  // ── Products ──────────────────────────────────────────────
  Future<Product> createProduct(Product p) async {
    final product = await ApiService.createProduct(p);
    products.add(product); notifyListeners();
    return product;
  }

  Future<void> updateProduct(int id, Map<String, dynamic> data) async {
    final updated = await ApiService.updateProduct(id, data);
    final idx = products.indexWhere((p) => p.id == id);
    if (idx >= 0) { products[idx] = updated; notifyListeners(); }
  }

  Future<void> deleteProduct(int id) async {
    await ApiService.deleteProduct(id);
    products.removeWhere((p) => p.id == id); notifyListeners();
  }

  // ── Users (admin) ─────────────────────────────────────────
  Future<void> createUser(String username, String password, String displayName, {String role = 'worker', String? address}) async {
    final user = await ApiService.createUser(username, password, displayName, role: role, address: address);
    users.add(user); notifyListeners();
  }

  Future<void> updateUser(int id, Map<String, dynamic> data) async {
    final updated = await ApiService.updateUser(id, data);
    final idx = users.indexWhere((u) => u['id'] == id);
    if (idx >= 0) { users[idx] = updated; notifyListeners(); }
  }

  // ── Sync ──────────────────────────────────────────────────
  Future<void> syncPendingActions() async {
    if (!isOnline) return;
    for (final a in await LocalDB.getPendingSync()) {
      try {
        final id = a['id'] as int;
        switch (a['action']) {
          case 'deliver':  await ApiService.deliverOrder(id); break;
          case 'comment':  await ApiService.addComment(id, a['comment']); break;
          case 'claim':    await ApiService.claimOrder(id); break;
          case 'unclaim':  await ApiService.unclaimOrder(id); break;
          case 'en_camino': await ApiService.markEnCamino(id); break;
          case 'cancel':   await ApiService.cancelOrder(id, a['reason'] ?? ''); break;
        }
      } catch (_) {}
    }
    await LocalDB.clearPendingSync();
    await refreshAll();
  }
}
