import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/session/realtime_hub.dart';
import 'core/session/session_scope.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/landa_error_guard.dart';
import 'core/utils/landa_navigator.dart';
import 'core/utils/landa_refresh.dart';
import 'features/agreements/controllers/agreement_controller.dart';
import 'features/auth/controllers/auth_controller.dart';
import 'features/auth/services/api_auth_service.dart';
import 'features/auth/views/splash_screen.dart';
import 'features/fix/controllers/fix_controller.dart';
import 'features/marketplace/controllers/marketplace_controller.dart';
import 'features/messaging/controllers/messaging_controller.dart';
import 'features/notifications/controllers/notification_controller.dart';
import 'features/payments/controllers/payment_controller.dart';
import 'features/payouts/controllers/payout_controller.dart';
import 'features/properties/controllers/landlord_controller.dart';
import 'features/reviews/controllers/review_controller.dart';
import 'features/shortlets/controllers/shortlet_controller.dart';
import 'features/vault/controllers/vault_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before anything else, so a failure during startup is caught too. Errors
  // are logged under one tag and a widget that throws leaves a small card
  // behind instead of taking the screen down with it.
  LandaErrorGuard.install();

  final apiAuthService = ApiAuthService();
  final themeController = ThemeController();
  await themeController.loadThemeMode();

  // These providers live for the whole process, so each one caches data
  // belonging to the signed-in user. They are built here (rather than inline
  // below) so they can be registered with SessionScope and wiped on sign-out.
  final landlordController = LandlordController();
  final agreementController = AgreementController();
  final paymentController = PaymentController();
  final notificationController = NotificationController();
  final marketplaceController = MarketplaceController();
  final payoutController = PayoutController();
  final vaultController = VaultController();
  final messagingController = MessagingController();
  final shortLetController = ShortLetController();
  final fixController = FixController();
  final reviewController = ReviewController();

  SessionScope.register([
    landlordController,
    agreementController,
    paymentController,
    notificationController,
    marketplaceController,
    payoutController,
    vaultController,
    messagingController,
    shortLetController,
    fixController,
    reviewController,
  ]);

  // Everything live in the app (a message landing, a notification being
  // raised) comes down one WebSocket, and this is what turns its frames into
  // controller state and on-screen popups. Built here rather than lazily,
  // because it has to be listening before the first event can arrive.
  final realtimeHub = RealtimeHub(
    messaging: messagingController,
    notifications: notificationController,
  )..start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) {
            final authController = AuthController(authService: apiAuthService)
              ..checkAuthStatus();
            // The socket authenticates with the session's own token, so it
            // can only be up while there is one. Driven by a listener rather
            // than from inside AuthController: which live features exist is a
            // composition-root concern, not something auth should know.
            authController.addListener(
              () => realtimeHub.handleAuthChanged(
                isAuthenticated: authController.isAuthenticated,
              ),
            );
            // Lets the hub re-read the profile when a VERIFICATION_SUCCEEDED
            // notification lands, so the app stops showing the verification
            // screen the moment the backend clears the user.
            realtimeHub.attachAuth(authController);
            // Any gated endpoint can return a live 403 verification-required
            // response even if the cached local status is stale VERIFIED;
            // route that signal back to AuthController so the UI reacts.
            ApiClient.onVerificationRequired =
                authController.handleVerificationRequiredSignal;
            // An expired refresh token ends the session from inside the
            // network layer. Without this the app kept rendering a signed-in
            // shell over an account that no longer had credentials, and every
            // request failed with the backend's raw JWT error.
            ApiClient.onSessionExpired = authController.handleSessionExpired;
            return authController;
          },
        ),
        ChangeNotifierProvider(create: (_) => themeController),
        ChangeNotifierProvider.value(value: landlordController),
        ChangeNotifierProvider.value(value: agreementController),
        ChangeNotifierProvider.value(value: paymentController),
        ChangeNotifierProvider.value(value: notificationController),
        ChangeNotifierProvider.value(value: marketplaceController),
        ChangeNotifierProvider.value(value: payoutController),
        ChangeNotifierProvider.value(value: vaultController),
        ChangeNotifierProvider.value(value: messagingController),
        ChangeNotifierProvider.value(value: shortLetController),
        ChangeNotifierProvider.value(value: fixController),
        ChangeNotifierProvider.value(value: reviewController),
        Provider<RealtimeHub>.value(value: realtimeHub),
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
    if (!mounted) return;
    // The socket follows the app in and out of the foreground. The OS freezes
    // it on suspension anyway, and one held across that wakes up believing it
    // is connected while delivering nothing.
    //
    // Nullable, like the theme controller below: a widget test can pump this
    // shell without the composition root's providers, and a lifecycle change
    // must not be the thing that fails it.
    context.read<RealtimeHub?>()?.handleAppLifecycle(state);
    if (state == AppLifecycleState.resumed) {
      context.read<ThemeController?>()?.loadThemeMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController?>();

    return MaterialApp(
      title: 'Landa OS',
      debugShowCheckedModeBanner: false,
      // One scroll feel on both platforms. Flutter's default gives iOS a
      // rubber-band and Android a clamped stop with a colour-bleed glow at
      // the edge: the same list behaving two different ways, and the glow in
      // particular reads as an artefact of somebody else's design system
      // sitting on top of this one.
      scrollBehavior: const _LandaScrollBehavior(),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeController?.themeMode ?? ThemeMode.system,
      // Lets every screen using AutoRefreshMixin know when it is back on top
      // after a pushed route pops: the moment its data is most likely stale.
      navigatorObservers: [landaRouteObserver],
      // Lets things that happen *to* the user, such as a message arriving over
      // the socket, find an Overlay to pop up in and a route to push when the
      // popup is tapped. See [landaNavigatorKey] for why this is the only
      // sanctioned use of a global navigator.
      navigatorKey: landaNavigatorKey,
      home: const SplashScreen(),
    );
  }
}

/// The app's scroll feel: rubber-band overscroll, no edge glow, and a drag
/// that starts from a touch or a trackpad alike.
class _LandaScrollBehavior extends MaterialScrollBehavior {
  const _LandaScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  /// Mouse and trackpad included, so the same lists are usable on a desktop
  /// build without a separate behaviour for it.
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
