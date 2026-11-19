import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/main_scaffold.dart';
import '../controllers/auth_controller.dart';
import '../models/user_model.dart';
import 'identity_verification_screen.dart';
import 'password_reset_sheet.dart';
import 'widgets/auth_pill_button.dart';
import 'widgets/auth_text_field.dart';
import 'sign_up_screen.dart';
import '../../../core/app_variant.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    // Closed first: the next screen replaces this one, and a keyboard left
    // up for a field that no longer exists has no way to be dismissed.
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      OasisToast.error(context, 'Please enter your email and password.');
      return;
    }

    final auth = context.read<AuthController>();
    final success = await auth.login(email, password);

    if (!mounted) return;

    if (success) {
      final user = auth.currentUser;
      final targetPage =
          (user?.verificationStatus != VerificationStatus.verified)
          ? const IdentityVerificationScreen()
          : const MainScaffold();

      OasisToast.success(
        context,
        'Welcome back, ${user?.email.split("@").first ?? "User"}!',
      );

      Navigator.pushAndRemoveUntil(
        context,
        FadePageRoute(page: targetPage),
        (route) => false,
      );
    } else if (auth.errorMessage != null) {
      OasisToast.error(context, auth.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      AppTheme.isDarkMode(context)
                          ? 'assets/images/oasis_wordmark_dark.png'
                          : 'assets/images/oasis_wordmark.png',
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Welcome back',
                    style: AppTheme.screenTitle(context).copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isOasisV2
                        ? 'Sign in to book and manage your shortlets.'
                        : 'Secure access to your property portfolio.',
                    style: AppTheme.bodyText(context).copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  AuthTextField(
                    controller: _emailController,
                    label: 'Email address',
                    hintText: 'Email address',
                    prefixIcon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hintText: 'Password',
                    prefixIcon: Icons.lock_outline_rounded,
                    isPassword: true,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      // A sheet over sign-in, not a page pushed on top of
                      // it: resetting a password is a detour, and dismissing
                      // it should put you back on the form you were filling.
                      onPressed: () => openPasswordResetSheet(context),
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: AppTheme.linkColor(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<AuthController>(
                    builder: (context, auth, _) => AuthPillButton(
                      label: 'Sign in',
                      isLoading: auth.isLoading,
                      onPressed: _handleLogin,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AuthSwitchLink(
                    prompt: isOasisV2
                        ? 'New to Oasis?'
                        : "Don't have an account?",
                    action: 'Create an account',
                    onTap: () => Navigator.pushReplacement(
                      context,
                      FadePageRoute(page: const SignUpScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
