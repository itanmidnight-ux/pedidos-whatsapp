import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import 'local_db.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Timer? _timer;
  static int _lastEstadoId  = 0;
  static int _lastProductId = 0;

  static const _channel = AndroidNotificationChannel(
    'monserrath_alerts',
    'Novedades Monserrath',
    description: 'Nuevos estados y productos disponibles',
    importance: Importance.high,
    enableVibration: true,
    playSound: true,
    showBadge: true,
  );

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  static Future<void> startPolling() async {
    _timer?.cancel();
    _lastEstadoId  = await LocalDB.getLastEstadoId();
    _lastProductId = await LocalDB.getLastProductId();
    // First check after 5s (let app fully load), then every 30s
    await Future.delayed(const Duration(seconds: 5));
    await _poll();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  static void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _poll() async {
    if (!ApiService.isConfigured) return;

    // Check new estados
    try {
      final estados = await ApiService.getEstados();
      if (estados.isNotEmpty) {
        final maxId = estados.map((e) => e.id).reduce((a, b) => a > b ? a : b);
        if (_lastEstadoId > 0 && maxId > _lastEstadoId) {
          final count = estados.where((e) => e.id > _lastEstadoId).length;
          await _notify(
            id: 1,
            title: count == 1 ? '¡Nuevo estado en Monserrath!' : '¡$count nuevos estados!',
            body: count == 1 ? 'Hay un nuevo contenido disponible — ¡míralo ahora!' : '$count nuevas publicaciones esperan por ti',
          );
        }
        if (maxId > _lastEstadoId) {
          _lastEstadoId = maxId;
          await LocalDB.setLastEstadoId(maxId);
        }
        await LocalDB.cacheEstados(estados);
      }
    } catch (_) {}

    // Check new products
    try {
      final products = await ApiService.getProducts();
      if (products.isNotEmpty) {
        final maxId = products.map((p) => p.id ?? 0).reduce((a, b) => a > b ? a : b);
        if (_lastProductId > 0 && maxId > _lastProductId) {
          final count = products.where((p) => (p.id ?? 0) > _lastProductId).length;
          await _notify(
            id: 2,
            title: count == 1 ? '¡Nuevo producto disponible!' : '¡$count nuevos productos!',
            body: count == 1 ? 'Un nuevo producto se agregó a nuestra tienda' : '$count nuevos productos esperan en la tienda',
          );
        }
        if (maxId > _lastProductId) {
          _lastProductId = maxId;
          await LocalDB.setLastProductId(maxId);
        }
        await LocalDB.cacheProducts(products);
      }
    } catch (_) {}
  }

  static Future<void> _notify({required int id, required String title, required String body}) async {
    HapticFeedback.vibrate();
    await _plugin.show(
      id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> notifyNewOrders(int count) async {
    await _notify(
      id: 3,
      title: count == 1 ? '¡Nuevo pedido recibido!' : '$count nuevos pedidos!',
      body: count == 1
        ? 'Tienes un pedido pendiente por atender'
        : '$count pedidos pendientes por atender',
    );
  }
}
