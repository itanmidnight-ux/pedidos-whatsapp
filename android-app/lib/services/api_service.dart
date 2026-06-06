import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/message.dart';
import '../models/estado.dart';
import '../models/cart_item.dart';

class ApiService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _defaultUrl = 'https://francoise-subhumid-maire.ngrok-free.dev';
  static String _serverUrl  = _defaultUrl;
  static String _token      = '';
  static String _username   = '';
  static String _role       = '';
  static String _displayName = '';

  static Future<void> init() async {
    final prefs  = await SharedPreferences.getInstance();
    _serverUrl   = prefs.getString('server_url') ?? _defaultUrl;
    _token       = await _secureStorage.read(key: 'jwt_token')    ?? '';
    _username    = await _secureStorage.read(key: 'username')     ?? '';
    _role        = await _secureStorage.read(key: 'role')         ?? '';
    _displayName = await _secureStorage.read(key: 'display_name') ?? '';
  }

  static Future<void> saveConfig(String token, String username, {String role = 'worker', String displayName = ''}) async {
    await _secureStorage.write(key: 'jwt_token',    value: token);
    await _secureStorage.write(key: 'username',     value: username);
    await _secureStorage.write(key: 'role',         value: role);
    await _secureStorage.write(key: 'display_name', value: displayName);
    _token = token; _username = username; _role = role; _displayName = displayName;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    _serverUrl = url;
  }

  static Future<void> logout() async {
    await _secureStorage.deleteAll();
    _token = ''; _username = ''; _role = ''; _displayName = '';
  }

  static bool   get isConfigured => _token.isNotEmpty;
  static String get serverUrl    => _serverUrl;
  static String get currentUser  => _username;
  static String get currentRole  => _role;
  static String get displayName  => _displayName;
  static bool   get isAdmin      => _role == 'admin';

  static Map<String, String> get _headers => {
    'Authorization':              'Bearer $_token',
    'Content-Type':               'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  static Map<String, String> get _headersNoContent => {
    'Authorization':              'Bearer $_token',
    'ngrok-skip-browser-warning': 'true',
  };

  // ── Auth ────────────────────────────────────────────────
  static Future<Map<String, String>> login(String username, String pin) async {
    final res = await http.post(
      Uri.parse('$_serverUrl/api/auth/token'),
      headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
      body: jsonEncode({'username': username.toLowerCase().trim(), 'pin': pin}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'token':        body['token'] as String,
        'username':     body['username'] as String,
        'role':         body['role'] as String? ?? 'worker',
        'display_name': body['display_name'] as String? ?? body['username'] as String,
      };
    }
    throw Exception(jsonDecode(res.body)['error'] ?? 'Credenciales incorrectas');
  }

  // ── Orders ──────────────────────────────────────────────
  static Future<List<Order>> getOrders() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/orders'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Order.fromJson(j)).toList();
    throw Exception('Error pedidos: ${res.statusCode}');
  }

  static Future<Order> claimOrder(int id) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/orders/$id/claim'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error reclamando pedido');
  }

  static Future<Order> unclaimOrder(int id) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/orders/$id/unclaim'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error liberando pedido');
  }

  static Future<Order> markEnCamino(int id) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/orders/$id/en_camino'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error actualizando estado');
  }

  static Future<Order> cancelOrder(int id, String reason) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/orders/$id/cancel'), headers: _headers, body: jsonEncode({'reason': reason})).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error cancelando pedido');
  }

  static Future<void> deliverOrder(int id) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/orders/$id/deliver'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error entregando pedido');
  }

  static Future<void> addComment(int id, String comment) async {
    await http.put(Uri.parse('$_serverUrl/api/orders/$id/comment'), headers: _headers, body: jsonEncode({'comment': comment})).timeout(const Duration(seconds: 10));
  }

  // ── Products ─────────────────────────────────────────────
  static Future<List<Product>> getProducts() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/products'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Product.fromJson(j)).toList();
    throw Exception('Error productos');
  }

  static Future<Product> createProduct(Product p) async {
    final res = await http.post(Uri.parse('$_serverUrl/api/products'), headers: _headers, body: jsonEncode(p.toJson())).timeout(const Duration(seconds: 10));
    return Product.fromJson(jsonDecode(res.body));
  }

  static Future<Product> updateProduct(int id, Map<String, dynamic> data) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/products/$id'), headers: _headers, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
    return Product.fromJson(jsonDecode(res.body));
  }

  static Future<void> deleteProduct(int id) async {
    await http.delete(Uri.parse('$_serverUrl/api/products/$id'), headers: _headers).timeout(const Duration(seconds: 10));
  }

  // ── Users (admin) ────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getUsers() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/users'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(res.body)['users']);
    throw Exception('Error usuarios: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> createUser(String username, String pin, String displayName, {String role = 'worker'}) async {
    final res = await http.post(Uri.parse('$_serverUrl/api/users'), headers: _headers,
      body: jsonEncode({'username': username, 'pin': pin, 'display_name': displayName, 'role': role})).timeout(const Duration(seconds: 10));
    if (res.statusCode == 201) return jsonDecode(res.body)['user'];
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error creando usuario');
  }

  static Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> data) async {
    final res = await http.put(Uri.parse('$_serverUrl/api/users/$id'), headers: _headers, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body)['user'];
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error actualizando usuario');
  }

  // ── Messages ─────────────────────────────────────────────
  static Future<List<Conversation>> getConversations({bool archived = false}) async {
    final url = '$_serverUrl/api/messages${archived ? '?archived=true' : ''}';
    final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Conversation.fromJson(j)).toList();
    throw Exception('Error conversaciones');
  }

  static Future<List<Message>> getFlaggedMessages() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/messages/flagged'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Message.fromJson(j)).toList();
    throw Exception('Error alertas');
  }

  static Future<List<Message>> getMessages(String phone) async {
    final res = await http.get(Uri.parse('$_serverUrl/api/messages/${Uri.encodeComponent(phone)}'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Message.fromJson(j)).toList();
    throw Exception('Error mensajes');
  }

  static Future<void> sendWhatsAppMessage(String phone, String content) async {
    final res = await http.post(Uri.parse('$_serverUrl/api/messages/send'), headers: _headers,
      body: jsonEncode({'phone': phone, 'content': content})).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error enviando mensaje');
  }

  static Future<void> markConversationRead(String phone) async {
    await http.put(Uri.parse('$_serverUrl/api/messages/${Uri.encodeComponent(phone)}/read'),
      headers: _headers).timeout(const Duration(seconds: 5));
  }

  static Future<void> deleteConversation(String phone) async {
    final res = await http.delete(
      Uri.parse('$_serverUrl/api/messages/conversation/${Uri.encodeComponent(phone)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error borrando conversación');
  }

  static Future<void> archiveConversation(String phone, {required bool archived}) async {
    final res = await http.put(
      Uri.parse('$_serverUrl/api/messages/conversation/${Uri.encodeComponent(phone)}/archive'),
      headers: _headers,
      body: jsonEncode({'archived': archived}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error archivando conversación');
  }

  static Future<void> sendMediaMessage(String phone, String filePath, String mediaType) async {
    final uri     = Uri.parse('$_serverUrl/api/messages/send-media');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    request.fields['phone']      = phone;
    request.fields['media_type'] = mediaType;
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    if (streamed.statusCode != 200) throw Exception('Error enviando media');
  }

  static Future<Uint8List?> downloadMedia(String filename) async {
    try {
      final res = await http.get(
        Uri.parse('$_serverUrl/api/messages/media/${Uri.encodeComponent(filename)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return res.bodyBytes;
      return null;
    } catch (_) { return null; }
  }

  static Future<void> flagMessage(int id, {bool flagged = false, String? reason}) async {
    await http.put(Uri.parse('$_serverUrl/api/messages/$id/flag'), headers: _headers,
      body: jsonEncode({'flagged': flagged, 'flag_reason': reason})).timeout(const Duration(seconds: 10));
  }

  // ── Users: delete ────────────────────────────────────────
  static Future<void> deleteUser(int id) async {
    final res = await http.delete(Uri.parse('$_serverUrl/api/users/$id'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error eliminando usuario');
  }

  // ── Product images ───────────────────────────────────────
  static Future<String> uploadProductImage(int productId, String filePath) async {
    final uri     = Uri.parse('$_serverUrl/api/products/$productId/images');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    request.files.add(await http.MultipartFile.fromPath('image', filePath));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) throw Exception('Error subiendo imagen');
    return jsonDecode(body)['filename'] as String;
  }

  static Future<void> deleteProductImage(int productId, String filename) async {
    final res = await http.delete(
      Uri.parse('$_serverUrl/api/products/$productId/images/${Uri.encodeComponent(filename)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error eliminando imagen');
  }

  static String productImageUrl(String filename) =>
    '$_serverUrl/api/products/images/${Uri.encodeComponent(filename)}';

  // ── Estados ──────────────────────────────────────────────
  static Future<List<Estado>> getEstados() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/estados'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['estados'] as List).map((j) => Estado.fromJson(j)).toList();
    }
    throw Exception('Error cargando estados');
  }

  static Future<Estado> createEstado(String filePath, {String? caption}) async {
    final uri     = Uri.parse('$_serverUrl/api/estados');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    if (caption != null) request.fields['caption'] = caption;
    request.files.add(await http.MultipartFile.fromPath('media', filePath));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) throw Exception('Error creando estado');
    return Estado.fromJson(jsonDecode(body)['estado']);
  }

  static Future<void> deleteEstado(int id) async {
    final res = await http.delete(Uri.parse('$_serverUrl/api/estados/$id'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error eliminando estado');
  }

  static String estadoMediaUrl(String filename) =>
    '$_serverUrl/api/estados/media/${Uri.encodeComponent(filename)}';

  // ── Cart ─────────────────────────────────────────────────
  static Future<List<CartItem>> getCart() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/cart'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['items'] as List).map((j) => CartItem.fromJson(j)).toList();
    }
    throw Exception('Error cargando carrito');
  }

  static Future<void> addToCart(int productId, int quantity, {String? deliveryDate}) async {
    final res = await http.post(
      Uri.parse('$_serverUrl/api/cart'),
      headers: _headers,
      body: jsonEncode({'product_id': productId, 'quantity': quantity, 'delivery_date': deliveryDate}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error agregando al carrito');
  }

  static Future<void> removeFromCart(int productId) async {
    final res = await http.delete(Uri.parse('$_serverUrl/api/cart/$productId'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error removiendo del carrito');
  }

  static Future<void> clearCart() async {
    await http.delete(Uri.parse('$_serverUrl/api/cart'), headers: _headers)
      .timeout(const Duration(seconds: 10));
  }

  static Future<Map<String, dynamic>> checkout({
    required String paymentMethod,
    String? nequiReference,
    String? deliveryDate,
  }) async {
    final res = await http.post(
      Uri.parse('$_serverUrl/api/cart/checkout'),
      headers: _headers,
      body: jsonEncode({
        'payment_method':   paymentMethod,
        'nequi_reference':  nequiReference,
        'delivery_date':    deliveryDate,
      }),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 201) return jsonDecode(res.body)['order'];
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error realizando pedido');
  }

  // ── Settings ─────────────────────────────────────────────
  static Future<Map<String, String>> getSettings() async {
    final res = await http.get(Uri.parse('$_serverUrl/api/settings'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body)['settings'] as Map<String, dynamic>;
      return body.map((k, v) => MapEntry(k, v.toString()));
    }
    throw Exception('Error cargando configuración');
  }

  static Future<void> updateSetting(String key, String value) async {
    final res = await http.put(
      Uri.parse('$_serverUrl/api/settings'),
      headers: _headers,
      body: jsonEncode({'key': key, 'value': value}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error actualizando configuración');
  }
}
