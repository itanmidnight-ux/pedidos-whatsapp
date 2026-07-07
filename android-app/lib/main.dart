import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
      themeMode: ThemeMode.system,
      // Las pantallas se diseñaron para ancho de telefono/tablet chica. En
      // navegador de escritorio (o cualquier viewport ancho) sin esto el
      // contenido se estira a lo ancho de la ventana y todo -- logos, texto,
      // filas -- se ve distorsionado. Se limita el ancho de contenido y se
      // centra, con un fondo detras, como cualquier app de chat en web.
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final mq = MediaQuery.of(context);
        final clampedTextScaler = mq.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.2,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clampedTextScaler),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const maxContentWidth = 560.0;
              if (constraints.maxWidth <= maxContentWidth) return child;
              return ColoredBox(
                color: const Color(0xFFEDEAE2),
                child: Center(
                  child: SizedBox(
                    width: maxContentWidth,
                    height: constraints.maxHeight,
                    child: Material(
                      elevation: 6,
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
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
