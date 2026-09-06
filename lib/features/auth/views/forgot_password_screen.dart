import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_toast.dart';
import '../controllers/auth_controller.dart';
import 'reset_password_screen.dart';
import 'widgets/auth_text_field.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/landa_busy.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      LandaToast.error(context, 'Enter the email address for your account.');
      return;
    }
    final success = await context.read<AuthController>().requestPasswordReset(
      email,
    );
    if (!mounted) return;
    if (success) {
      setState(() => _sent = true);
      LandaToast.success(
        context,
        'If an account exists, a reset link is on its way.',
      );
    } else {
      LandaToast.error(
        context,
        context.read<AuthController>().errorMessage ??
            'Could not request a password reset.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondaryTextColor = AppTheme.secondaryTextColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.borderColor(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _sent
                          ? Icons.mark_email_read_outlined
                          : Icons.lock_reset_outlined,
                      size: 44,
                      color: AppTheme.actionColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _sent ? 'Check your inbox' : 'Forgot your password?',
                      textAlign: TextAlign.center,
                      style: AppTheme.screenTitle(
                        context,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _sent
                          ? 'We sent password-reset instructions to ${_emailController.text.trim()}. Check spam too.'
                          : 'Enter your account email and we’ll send a secure password-reset link.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryTextColor,
                        height: 1.4,
                      ),
                    ),
                    if (!_sent) ...[
                      const SizedBox(height: 28),
                      AuthTextField(
                        controller: _emailController,
                        label: 'EMAIL ADDRESS',
                        hintText: 'user@example.com',
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 24),
                      Consumer<AuthController>(
                        builder: (context, auth, _) => SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _sendResetLink,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.actionColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: auth.isLoading
                                ? const LandaBusyDots(
                                    color: Colors.white,
                                    size: 7,
                                  )
                                : const Text(
                                    'Send reset link',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                    if (_sent) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          FadePageRoute(page: const ResetPasswordScreen()),
                        ),
                        child: const Text('I have a reset token'),
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
