import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/agreements/controllers/agreement_controller.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/auth/services/api_auth_service.dart';
import 'features/auth/views/splash_screen.dart';
import 'features/notifications/controllers/notification_controller.dart';
import 'features/payments/controllers/payment_controller.dart';
import 'features/properties/controllers/landlord_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final apiAuthService = ApiAuthService();
  final themeController = ThemeController();
  await themeController.loadThemeMode();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final authController = AuthController(
              authService: apiAuthService,
            )..checkAuthStatus();
            // Any gated endpoint can return a live 403 verification-required
            // response even if the cached local status is stale VERIFIED;
            // route that signal back to AuthController so the UI reacts.
            ApiClient.onVerificationRequired =
                authController.handleVerificationRequiredSignal;
            return authController;
          },
        ),
        ChangeNotifierProvider(create: (_) => themeController),
        ChangeNotifierProvider(create: (_) => LandlordController()),
        ChangeNotifierProvider(create: (_) => AgreementController()),
        ChangeNotifierProvider(create: (_) => PaymentController()),
        ChangeNotifierProvider(create: (_) => NotificationController()),
      ],
      child: const LandaApp(),
    ),
  );
}

/// The root widget of Landa OS.
class LandaApp extends StatefulWidget {
  const LandaApp({super.key});

  @override
  State<LandaApp> createState() => _LandaAppState();
}

class _LandaAppState extends State<LandaApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<ThemeController>().loadThemeMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController?>();

    return MaterialApp(
      title: 'Landa OS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeController?.themeMode ?? ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
