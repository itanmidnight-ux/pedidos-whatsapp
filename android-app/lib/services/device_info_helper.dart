import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:device_info_plus/device_info_plus.dart';

/// Identifica el dispositivo desde el que se inicia sesión -- control de
/// seguridad para saber en qué equipos entra cada trabajador. Evita
/// dart:io (Platform.isAndroid) porque este archivo tambien se compila
/// para Flutter Web, donde dart:io no existe.
class DeviceInfoHelper {
  static Future<String> describe() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return '${info.browserName.name} (web)';
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await plugin.androidInfo;
        return '${info.brand} ${info.model} (Android ${info.version.release})';
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await plugin.iosInfo;
        return '${info.name} (iOS ${info.systemVersion})';
      }
    } catch (_) {}
    return 'Dispositivo desconocido';
  }
}
