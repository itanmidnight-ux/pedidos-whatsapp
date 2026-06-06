import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'providers/app_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/client_home_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0xFF1E6B2E),
    statusBarIconBrightness: Brightness.light,
  ));
  await ApiService.init();

  // OneSignal push notifications
  const oneSignalAppId = String.fromEnvironment('ONESIGNAL_APP_ID', defaultValue: '');
  if (oneSignalAppId.isNotEmpty) {
    OneSignal.initialize(oneSignalAppId);
    await OneSignal.Notifications.requestPermission(true);
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppProvider(),
      child: const PedidosApp(),
    ),
  );
}

class PedidosApp extends StatelessWidget {
  const PedidosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Concentrados Monserrath',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E6B2E),
          brightness: Brightness.light,
        ).copyWith(
          primary:    const Color(0xFF1E6B2E),
          secondary:  const Color(0xFFD4800A),
          surface:    const Color(0xFFF5F5F0),
          onPrimary:  Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F0),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E6B2E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFC8E6C9),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1E6B2E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
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
