import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'local_db.dart';

/// Rastreo de ubicación de trabajadores/admin -- SOLO esos roles, nunca
/// clientes. El permiso se pide de forma explícita y con una pantalla de
/// consentimiento previa (requisito real de Google Play para ubicación en
/// segundo plano, además de ser lo correcto). Sigue funcionando con la app
/// cerrada vía el foreground service que expone geolocator en Android.
class LocationTrackerService {
  static StreamSubscription<Position>? _sub;
  static const _consentKey = 'location_consent_given';

  static bool get _eligibleRole =>
      !kIsWeb && ['worker', 'admin'].contains(ApiService.currentRole);

  static Future<bool> hasGivenConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<void> setConsentGiven() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, true);
  }

  /// Pide los permisos de ubicación (uso normal, luego segundo plano) y
  /// arranca el reporte periódico. No hace nada si el rol no es staff --
  /// nunca se activa para clientes, sin importar qué llame a este método.
  static Future<void> start() async {
    if (!_eligibleRole) return;
    if (_sub != null) return; // ya está corriendo

    if (!await Geolocator.isLocationServiceEnabled()) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) return;

    // Segundo plano (Android 10+): pedirlo aparte, tras el de uso normal --
    // es el flujo que exige el propio sistema operativo.
    if (perm != LocationPermission.always) {
      perm = await Geolocator.requestPermission();
    }

    _sub = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Concentrados Monserrath',
          notificationText: 'Compartiendo tu ubicación por seguridad mientras trabajas',
          enableWakeLock: true,
        ),
      ),
    ).listen((pos) => _reportOrQueue(pos), onError: (_) {});
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Reporta la posición actual; si falla (sin señal, servidor caído un
  /// momento) la guarda en la cola local en vez de perderla. Luego intenta
  /// vaciar la cola completa -- así un bache de conectividad no deja un
  /// hueco real en el recorrido del empleado.
  static Future<void> _reportOrQueue(Position pos) async {
    try {
      await ApiService.reportLocation(pos.latitude, pos.longitude, pos.accuracy);
    } catch (_) {
      await LocalDB.queueLocation(pos.latitude, pos.longitude, pos.accuracy);
    }
    await _flushQueue();
  }

  static Future<void> _flushQueue() async {
    await LocalDB.pruneOldQueuedLocations();
    final pending = await LocalDB.getQueuedLocations();
    for (final row in pending) {
      try {
        await ApiService.reportLocation(
          (row['lat'] as num).toDouble(),
          (row['lng'] as num).toDouble(),
          row['accuracy'] == null ? null : (row['accuracy'] as num).toDouble(),
        );
        await LocalDB.removeQueuedLocation(row['id'] as int);
      } catch (_) {
        break; // sigue sin red -- se reintenta el resto en el próximo ciclo
      }
    }
  }
}
