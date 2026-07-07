import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/message.dart';
import '../models/estado.dart';
import '../models/cart_item.dart';

// Interceptor central: cualquier request que responda 401 dispara logout +
// aviso a la UI, sin depender de que cada método individual lo chequee.
class _AuthHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    if (res.statusCode == 401) {
      ApiService.logout();
      ApiService.onUnauthorized?.call();
    }
    return res;
  }
}

class ApiService {
  static final http.Client _client = _AuthHttpClient();

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _defaultUrl = 'https://tu-dominio.duckdns.org';

  // En web usa el mismo origen (funciona con DuckDNS HTTP y cloudflare HTTPS)
  static String get _autoUrl {
    if (kIsWeb) {
      final uri = Uri.base;
      return '${uri.scheme}://${uri.host}${uri.hasPort && uri.port != 80 && uri.port != 443 ? ":${uri.port}" : ""}';
    }
    return _defaultUrl;
  }

  static String _serverUrl   = _defaultUrl;
  static String _token       = '';
  static String _username    = '';
  static String _role        = '';
  static String _displayName = '';

  // Called by app-level provider when 401 is detected → forces re-login
  static Function()? onUnauthorized;

  static Future<void> init() async {
    final prefs  = await SharedPreferences.getInstance();
    // Web: siempre usar mismo origen (ignora prefs guardadas)
    _serverUrl   = kIsWeb ? _autoUrl : (prefs.getString('server_url') ?? _defaultUrl);
    _token       = await _secureStorage.read(key: 'jwt_token')    ?? '';
    _username    = await _secureStorage.read(key: 'username')     ?? '';
    _role        = await _secureStorage.read(key: 'role')         ?? '';
    _displayName = await _secureStorage.read(key: 'display_name') ?? '';

    // Validate stored token is not expired; silently refresh if possible
    if (_token.isNotEmpty && _isTokenExpired(_token)) {
      try {
        await _refreshToken();
      } catch (_) {
        await logout();
      }
    }
  }

  // Decode JWT exp claim without verifying signature (verification done server-side)
  static bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'] as int?;
      if (exp == null) return false;
      return DateTime.now().millisecondsSinceEpoch / 1000 > exp;
    } catch (_) { return false; }
  }

  static Future<void> _refreshToken() async {
    final res = await _client.post(
      Uri.parse('$_serverUrl/api/auth/refresh'),
      headers: {
        'Authorization':              'Bearer $_token',
        'Content-Type':               'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      await saveConfig(
        body['token'] as String,
        body['username'] as String,
        role:        body['role'] as String? ?? _role,
        displayName: body['display_name'] as String? ?? _displayName,
      );
    } else {
      throw Exception('refresh_failed');
    }
  }

  // Central HTTP response handler — detects 401 and triggers re-login
  static dynamic _handleResponse(http.Response res) {
    if (res.statusCode == 401) {
      logout();
      onUnauthorized?.call();
      throw Exception('session_expired');
    }
    return res;
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

  // Public getter for use in CachedNetworkImage httpHeaders
  static Map<String, String> get imageHeaders => {
    'Authorization':              'Bearer $_token',
    'ngrok-skip-browser-warning': 'true',
  };

  static MediaType _mimeOf(String path) {
    final ext = path.split('.').last.toLowerCase();
    const t = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'png': 'image/png',  'webp': 'image/webp',
      'gif': 'image/gif',  'mp4': 'video/mp4',
      'mov': 'video/quicktime', 'webm': 'video/webm',
      'ogg': 'audio/ogg',  'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',  'aac': 'audio/aac',
    };
    return MediaType.parse(t[ext] ?? 'image/jpeg');
  }

  // ── Auth ────────────────────────────────────────────────
  // Cuenta queda pendiente de aprobación del admin — el servidor ya no
  // devuelve token de sesión en el registro (active=0 hasta ser aprobada).
  static Future<String> register({
    required String username,
    required String password,
    required String displayName,
    required String email,
    required String address,
    String? nickname,
    String? bio,
  }) async {
    http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$_serverUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({
          'username':     username.toLowerCase().trim(),
          'password':     password,
          'display_name': displayName.trim(),
          'email':        email.trim(),
          'address':      address.trim(),
          if (nickname != null && nickname.isNotEmpty) 'nickname': nickname.trim(),
          if (bio      != null && bio.isNotEmpty)      'bio':      bio.trim(),
        }),
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw Exception('Servidor no responde. Verifica tu conexión.');
    } catch (_) {
      throw Exception('No se pudo conectar al servidor.');
    }
    if (res.statusCode == 201) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['message'] as String? ??
          'Cuenta creada. Un administrador debe aprobarla antes de que puedas iniciar sesión.';
    }
    final body = _tryDecodeBody(res.body);
    throw Exception(body['error'] as String? ?? 'Error al registrarse');
  }

  static Future<Map<String, String>> login(String username, String pin) async {
    http.Response res;
    try {
      res = await _client.post(
        Uri.parse('$_serverUrl/api/auth/token'),
        headers: {'Content-Type': 'application/json', 'ngrok-skip-browser-warning': 'true'},
        body: jsonEncode({'username': username.toLowerCase().trim(), 'password': pin}),
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw Exception('Servidor no responde. Verifica tu conexión.');
    } catch (e) {
      throw Exception('No se pudo conectar al servidor.');
    }

    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return {
        'token':        body['token'] as String,
        'username':     body['username'] as String,
        'role':         body['role'] as String? ?? 'worker',
        'display_name': body['display_name'] as String? ?? body['username'] as String,
      };
    }

    final body = _tryDecodeBody(res.body);
    if (res.statusCode == 429) {
      final secs = body['retry_in'] as int? ?? 900;
      final mins = (secs / 60).ceil();
      throw Exception('Demasiados intentos fallidos. Intenta en $mins minutos.');
    }
    final attLeft = body['attempts_left'] as int?;
    final msg     = body['error'] as String? ?? 'Credenciales incorrectas';
    throw Exception(attLeft != null && attLeft > 0
      ? '$msg ($attLeft intentos restantes)'
      : msg);
  }

  static Map<String, dynamic> _tryDecodeBody(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  // ── Orders ──────────────────────────────────────────────
  static Future<List<Order>> getOrders() async {
    final res = _handleResponse(
      await _client.get(Uri.parse('$_serverUrl/api/orders'), headers: _headers).timeout(const Duration(seconds: 10)));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Order.fromJson(j)).toList();
    throw Exception('Error pedidos: ${res.statusCode}');
  }

  static Future<Order> claimOrder(int id) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/orders/$id/claim'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error reclamando pedido');
  }

  static Future<Order> unclaimOrder(int id) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/orders/$id/unclaim'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error liberando pedido');
  }

  static Future<Order> markEnCamino(int id) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/orders/$id/en_camino'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error actualizando estado');
  }

  static Future<Order> cancelOrder(int id, String reason) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/orders/$id/cancel'), headers: _headers, body: jsonEncode({'reason': reason})).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Order.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error cancelando pedido');
  }

  static Future<void> deliverOrder(int id) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/orders/$id/deliver'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error entregando pedido');
  }

  static Future<void> addComment(int id, String comment) async {
    await _client.put(Uri.parse('$_serverUrl/api/orders/$id/comment'), headers: _headers, body: jsonEncode({'comment': comment})).timeout(const Duration(seconds: 10));
  }

  static Future<Map<String, dynamic>> getInventoryStats() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/orders/stats'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error stats: ${res.statusCode}');
  }

  // ── Products ─────────────────────────────────────────────
  static Future<List<Product>> getProducts() async {
    final res = _handleResponse(
      await _client.get(Uri.parse('$_serverUrl/api/products'), headers: _headers).timeout(const Duration(seconds: 10)));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Product.fromJson(j)).toList();
    throw Exception('Error productos');
  }

  static Future<Product> createProduct(Product p) async {
    final res = await _client.post(Uri.parse('$_serverUrl/api/products'), headers: _headers, body: jsonEncode(p.toJson())).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200 || res.statusCode == 201) return Product.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error creando producto: ${res.statusCode}');
  }

  static Future<Product> updateProduct(int id, Map<String, dynamic> data) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/products/$id'), headers: _headers, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return Product.fromJson(jsonDecode(res.body));
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error actualizando producto: ${res.statusCode}');
  }

  static Future<void> deleteProduct(int id) async {
    await _client.delete(Uri.parse('$_serverUrl/api/products/$id'), headers: _headers).timeout(const Duration(seconds: 10));
  }

  // ── Users (admin) ────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getUsers() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/users'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(res.body)['users']);
    throw Exception('Error usuarios: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> createUser(String username, String password, String displayName, {String role = 'worker', String? address}) async {
    final res = await _client.post(Uri.parse('$_serverUrl/api/users'), headers: _headers,
      body: jsonEncode({'username': username, 'password': password, 'display_name': displayName, 'role': role, if (address != null && address.isNotEmpty) 'address': address})).timeout(const Duration(seconds: 10));
    if (res.statusCode == 201) return jsonDecode(res.body)['user'];
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error creando usuario');
  }

  static Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> data) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/users/$id'), headers: _headers, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body)['user'];
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error actualizando usuario');
  }

  // ── Messages ─────────────────────────────────────────────
  static Future<List<Conversation>> getConversations({bool archived = false}) async {
    final url = '$_serverUrl/api/messages${archived ? '?archived=true' : ''}';
    final res = _handleResponse(
      await _client.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10)));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Conversation.fromJson(j)).toList();
    throw Exception('Error conversaciones');
  }

  static Future<List<Message>> getFlaggedMessages() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/messages/flagged'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Message.fromJson(j)).toList();
    throw Exception('Error alertas');
  }

  static Future<List<Message>> getMessages(String phone) async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/messages/${Uri.encodeComponent(phone)}'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return (jsonDecode(res.body) as List).map((j) => Message.fromJson(j)).toList();
    throw Exception('Error mensajes');
  }

  static Future<void> sendWhatsAppMessage(String phone, String content) async {
    final res = await _client.post(Uri.parse('$_serverUrl/api/messages/send'), headers: _headers,
      body: jsonEncode({'phone': phone, 'content': content})).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error enviando mensaje');
  }

  static Future<void> markConversationRead(String phone) async {
    await _client.put(Uri.parse('$_serverUrl/api/messages/${Uri.encodeComponent(phone)}/read'),
      headers: _headers).timeout(const Duration(seconds: 5));
  }

  static Future<void> deleteConversation(String phone) async {
    final res = await _client.delete(
      Uri.parse('$_serverUrl/api/messages/conversation/${Uri.encodeComponent(phone)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error borrando conversación');
  }

  static Future<void> archiveConversation(String phone, {required bool archived}) async {
    final res = await _client.put(
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
    request.files.add(await http.MultipartFile.fromPath('file', filePath,
      contentType: _mimeOf(filePath)));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
    if (streamed.statusCode != 200) throw Exception('Error enviando media');
  }

  static Future<Uint8List?> downloadMedia(String filename) async {
    try {
      final res = await _client.get(
        Uri.parse('$_serverUrl/api/messages/media/${Uri.encodeComponent(filename)}'),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) return res.bodyBytes;
      return null;
    } catch (_) { return null; }
  }

  static Future<void> flagMessage(int id, {bool flagged = false, String? reason}) async {
    await _client.put(Uri.parse('$_serverUrl/api/messages/$id/flag'), headers: _headers,
      body: jsonEncode({'flagged': flagged, 'flag_reason': reason})).timeout(const Duration(seconds: 10));
  }

  // ── Users: clients list + self-profile ───────────────────
  static Future<List<Map<String, dynamic>>> getClients() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/users/clients'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(res.body)['clients']);
    throw Exception('Error clientes: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/users/me'), headers: _headers,
      body: jsonEncode(data)).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body)['user'] as Map<String, dynamic>;
    throw Exception(jsonDecode(res.body)['error'] ?? 'Error actualizando perfil');
  }

  static Future<void> changePassword(String currentPw, String newPw) async {
    final res = await _client.put(Uri.parse('$_serverUrl/api/users/me/password'), headers: _headers,
      body: jsonEncode({'current_password': currentPw, 'new_password': newPw}))
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error cambiando contraseña');
  }

  static Future<String> uploadProfilePic(String? filePath, {Uint8List? bytes, String? mimeType}) async {
    final uri     = Uri.parse('$_serverUrl/api/users/me/profile-pic');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    if (bytes != null) {
      final mt  = MediaType.parse(mimeType ?? 'image/jpeg');
      final ext = mt.subtype == 'jpeg' ? 'jpg' : mt.subtype;
      request.files.add(http.MultipartFile.fromBytes('photo', bytes,
        filename: 'photo.$ext', contentType: mt));
    } else if (filePath != null) {
      request.files.add(await http.MultipartFile.fromPath('photo', filePath,
        contentType: _mimeOf(filePath)));
    } else {
      throw Exception('Se requiere filePath o bytes');
    }
    final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception(_tryParseError(body) ?? 'Error subiendo foto');
    return jsonDecode(body)['filename'] as String;
  }

  static Future<void> deleteProfilePic() async {
    final res = await _client.delete(Uri.parse('$_serverUrl/api/users/me/profile-pic'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error eliminando foto');
  }

  static String profilePicUrl(String filename) =>
    '$_serverUrl/api/users/profile-pic/${Uri.encodeComponent(filename)}';

  static Future<String> uploadLogo(String filePath) async {
    final uri = Uri.parse('$_serverUrl/api/settings/logo');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    request.files.add(await http.MultipartFile.fromPath('logo', filePath, contentType: _mimeOf(filePath)));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception(_tryParseError(body) ?? 'Error subiendo logo');
    return jsonDecode(body)['filename'] as String;
  }

  static String logoUrl(String filename) => '$_serverUrl/api/settings/logo/${Uri.encodeComponent(filename)}';

  // ── Users: delete ────────────────────────────────────────
  static Future<void> deleteUser(int id) async {
    final res = await _client.delete(Uri.parse('$_serverUrl/api/users/$id'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception(jsonDecode(res.body)['error'] ?? 'Error eliminando usuario');
  }

  // ── Product images ───────────────────────────────────────
  static Future<String> uploadProductImage(int productId, String filePath) async {
    final uri     = Uri.parse('$_serverUrl/api/products/$productId/images');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    request.files.add(await http.MultipartFile.fromPath('image', filePath,
      contentType: _mimeOf(filePath)));
    final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) {
      final err = _tryParseError(body);
      throw Exception(err ?? 'Error subiendo imagen (${streamed.statusCode})');
    }
    return jsonDecode(body)['filename'] as String;
  }

  static String? _tryParseError(String body) {
    try { return (jsonDecode(body) as Map)['error'] as String?; } catch (_) { return null; }
  }

  static Future<void> deleteProductImage(int productId, String filename) async {
    final res = await _client.delete(
      Uri.parse('$_serverUrl/api/products/$productId/images/${Uri.encodeComponent(filename)}'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error eliminando imagen');
  }

  static String productImageUrl(String filename) =>
    '$_serverUrl/api/products/images/${Uri.encodeComponent(filename)}';

  // ── Estados ──────────────────────────────────────────────
  static Future<List<Estado>> getEstados() async {
    final res = _handleResponse(
      await _client.get(Uri.parse('$_serverUrl/api/estados'), headers: _headers)
        .timeout(const Duration(seconds: 10)));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['estados'] as List).map((j) => Estado.fromJson(j)).toList();
    }
    throw Exception('Error cargando estados');
  }

  static Future<Estado> createEstado(
    String? filePath, {
    String? caption,
    Uint8List? bytes,
    String? mimeType,
    int? productId,
    String? productName,
  }) async {
    final uri     = Uri.parse('$_serverUrl/api/estados');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(_headersNoContent);
    if (caption     != null) request.fields['caption']      = caption;
    if (productId   != null) request.fields['product_id']   = productId.toString();
    if (productName != null) request.fields['product_name'] = productName;

    if (bytes != null) {
      final mt = MediaType.parse(mimeType ?? 'image/jpeg');
      final ext = mt.subtype == 'jpeg' ? 'jpg'
                : mt.subtype == 'quicktime' ? 'mov'
                : mt.subtype;
      request.files.add(http.MultipartFile.fromBytes('media', bytes,
        filename: 'media.$ext', contentType: mt));
    } else if (filePath != null) {
      request.files.add(await http.MultipartFile.fromPath('media', filePath,
        contentType: _mimeOf(filePath)));
    } else {
      throw Exception('Se requiere filePath o bytes');
    }

    final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 201) {
      final err = _tryParseError(body);
      throw Exception(err ?? 'Error creando estado (${streamed.statusCode})');
    }
    return Estado.fromJson(jsonDecode(body)['estado']);
  }

  static Future<void> deleteEstado(int id) async {
    final res = await _client.delete(Uri.parse('$_serverUrl/api/estados/$id'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error eliminando estado');
  }

  static String estadoMediaUrl(String filename) =>
    '$_serverUrl/api/estados/media/${Uri.encodeComponent(filename)}';

  static Future<Map<String, dynamic>> reactToEstado(int id) async {
    final res = await _client.post(Uri.parse('$_serverUrl/api/estados/$id/react'),
      headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error al reaccionar');
  }

  static Future<List<Map<String, dynamic>>> getEstadoComments(int id) async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/estados/$id/comments'),
      headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(res.body)['comments']);
    throw Exception('Error cargando comentarios');
  }

  static Future<List<Map<String, dynamic>>> getEstadoReactions(int id) async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/estados/$id/reactions'),
      headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(jsonDecode(res.body)['reactions']);
    throw Exception('Error cargando reacciones');
  }

  static Future<void> addEstadoComment(int id, String comment) async {
    final res = await _client.post(Uri.parse('$_serverUrl/api/estados/$id/comments'),
      headers: _headers,
      body: jsonEncode({'comment': comment})).timeout(const Duration(seconds: 10));
    if (res.statusCode != 201) throw Exception(jsonDecode(res.body)['error'] ?? 'Error agregando comentario');
  }

  // ── Cart ─────────────────────────────────────────────────
  static Future<List<CartItem>> getCart() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/cart'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (body['items'] as List).map((j) => CartItem.fromJson(j)).toList();
    }
    throw Exception('Error cargando carrito');
  }

  static Future<void> addToCart(int productId, int quantity, {String? deliveryDate}) async {
    final res = await _client.post(
      Uri.parse('$_serverUrl/api/cart'),
      headers: _headers,
      body: jsonEncode({'product_id': productId, 'quantity': quantity, 'delivery_date': deliveryDate}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error agregando al carrito');
  }

  static Future<void> removeFromCart(int productId) async {
    final res = await _client.delete(Uri.parse('$_serverUrl/api/cart/$productId'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error removiendo del carrito');
  }

  static Future<void> clearCart() async {
    await _client.delete(Uri.parse('$_serverUrl/api/cart'), headers: _headers)
      .timeout(const Duration(seconds: 10));
  }

  static Future<Map<String, dynamic>> checkout({
    required String paymentMethod,
    String? nequiReference,
    String? deliveryDate,
  }) async {
    final res = await _client.post(
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
    final res = await _client.get(Uri.parse('$_serverUrl/api/settings'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body)['settings'] as Map<String, dynamic>;
      return body.map((k, v) => MapEntry(k, v.toString()));
    }
    throw Exception('Error cargando configuración');
  }

  static Future<void> updateSetting(String key, String value) async {
    final res = await _client.put(
      Uri.parse('$_serverUrl/api/settings'),
      headers: _headers,
      body: jsonEncode({'key': key, 'value': value}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error actualizando configuración');
  }

  // ── Bot de WhatsApp: salud/estado ─────────────────────────────
  static Future<Map<String, dynamic>> getBotStatus() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/bot/status'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error consultando estado del bot');
  }

  static Future<void> restartBot() async {
    final res = await _client.post(Uri.parse('$_serverUrl/api/bot/restart'), headers: _headers)
      .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      final body = _tryDecodeBody(res.body);
      throw Exception(body['error'] as String? ?? 'Error reiniciando el bot');
    }
  }

  // ── Analíticas (admin) ────────────────────────────────────────
  static Future<Map<String, dynamic>> getAnalyticsSummary() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/analytics/summary'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error cargando resumen');
  }

  static Future<Map<String, dynamic>> getAnalyticsProducts() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/analytics/products'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error cargando productos');
  }

  static Future<Map<String, dynamic>> getAnalyticsEmployees() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/analytics/employees'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error cargando empleados');
  }

  static Future<Map<String, dynamic>> getAnalyticsCustomers() async {
    final res = await _client.get(Uri.parse('$_serverUrl/api/analytics/customers'), headers: _headers)
      .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    throw Exception('Error cargando clientes');
  }

  // ── Remember me: solo el usuario, nunca la contraseña ────────
  // La sesión ya persiste vía el JWT (ver init()); esto es solo para no
  // tener que retipear el usuario si el token expiró o cerró sesión.
  static Future<void> saveCredentials(String username) async {
    await _secureStorage.write(key: 'saved_username', value: username);
    await _secureStorage.delete(key: 'saved_password'); // limpia instalaciones previas
  }

  static Future<String> loadCredentials() async {
    return await _secureStorage.read(key: 'saved_username') ?? '';
  }

  static Future<void> clearCredentials() async {
    await _secureStorage.delete(key: 'saved_username');
    await _secureStorage.delete(key: 'saved_password');
  }

  // ── In-app chat message (order detection via bot) ─────────────
  static Future<String> sendAppMessage(String message) async {
    final res = await _client.post(
      Uri.parse('$_serverUrl/api/chat/message'),
      headers: _headers,
      body: jsonEncode({'message': message}),
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['reply'] as String? ?? 'Mensaje recibido';
    }
    throw Exception('Error enviando mensaje');
  }
}
