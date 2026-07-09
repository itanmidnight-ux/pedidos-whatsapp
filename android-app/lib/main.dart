import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'providers/app_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/client_home_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF1A3009),
    statusBarIconBrightness: Brightness.light,
  ));
  // DateFormat(pattern, 'es') en varias pantallas (fecha de entrega,
  // mensajes, analiticas) lanzaba LocaleDataException en runtime porque
  // los datos del locale nunca se inicializaban -- en release eso se veia
  // como una pantalla completamente gris (el ErrorWidget por defecto).
  await initializeDateFormatting('es', null);
  await ApiService.init();
  await NotificationService.init();
  await NotificationService.requestPermission();

  const oneSignalAppId = String.fromEnvironment('ONESIGNAL_APP_ID', defaultValue: '');
  if (oneSignalAppId.isNotEmpty) {
    OneSignal.initialize(oneSignalAppId);
    await OneSignal.Notifications.requestPermission(true);
  }

  final themeProvider = ThemeProvider();
  if (ApiService.isConfigured) await themeProvider.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const PedidosApp(),
    ),
  );
}

class PedidosApp extends StatelessWidget {
  const PedidosApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: themeProvider.brandName,
      debugShowCheckedModeBanner: false,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      // ThemeMode.system se ve roto en cualquier SO/navegador con preferencia
      // oscura (ej. Kali por defecto): darkTheme nunca tuvo el mismo trabajo
      // de diseño que lightTheme (ver app_theme.dart) y termina en un
      // Material 3 dark sin ajustar -- superficie casi negra, look "app
      // rota". Fijo a claro hasta que exista un modo oscuro diseñado de
      // verdad, no el default sin tocar.
      themeMode: ThemeMode.light,
      // Sin caja de ancho fijo global: cada pantalla ancha (dashboard,
      // chat, login) ya resuelve su propio límite de contenido donde hace
      // falta (NavigationRail, ConstrainedBox de formulario, etc). Forzar
      // aquí un SizedBox centrado dejaba franjas vacías a los costados en
      // monitores de PC en vez de usar la pantalla completa.
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final clampedTextScaler = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.2,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clampedTextScaler),
          child: child,
        );
      },
      home: Consumer<AppProvider>(
        builder: (_, provider, __) {
          if (!provider.isLoggedIn) return const LoginScreen();
          if (provider.currentRole == 'client') return const ClientHomeScreen();
          return const DashboardScreen();
        },
      ),
    );
  }
}
