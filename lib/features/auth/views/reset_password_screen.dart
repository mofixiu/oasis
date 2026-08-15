import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/landa_toast.dart';
import '../controllers/auth_controller.dart';
import 'widgets/auth_text_field.dart';

/// Lets a user paste the single-use token from the password-reset email
/// (or the deep-link token, once linking is wired up) and set a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _tokenController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = _tokenController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (token.isEmpty) {
      LandaToast.error(context, 'Enter the reset token from your email.');
      return;
    }
    if (newPassword.length < 8) {
      LandaToast.error(
        context,
        'New password must be at least 8 characters.',
      );
      return;
    }
    if (newPassword != confirmPassword) {
      LandaToast.error(context, 'Passwords do not match.');
      return;
    }

    final success = await context.read<AuthController>().confirmPasswordReset(
      token: token,
      newPassword: newPassword,
    );
    if (!mounted) return;

    if (success) {
      LandaToast.success(
        context,
        'Password reset. Sign in with your new password.',
      );
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      LandaToast.error(
        context,
        context.read<AuthController>().errorMessage ??
            'Could not reset password. The token may be invalid or expired.',
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
                    const Icon(
                      Icons.password_outlined,
                      size: 44,
                      color: AppTheme.actionColor,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Set a new password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Paste the reset token from your email and choose a new password.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryTextColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    AuthTextField(
                      controller: _tokenController,
                      label: 'RESET TOKEN',
                      hintText: 'Paste the token from your email',
                      prefixIcon: Icons.vpn_key_outlined,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _newPasswordController,
                      label: 'NEW PASSWORD',
                      hintText: 'At least 8 characters',
                      prefixIcon: Icons.lock_outline,
                      isPassword: true,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _confirmPasswordController,
                      label: 'CONFIRM NEW PASSWORD',
                      hintText: 'Re-enter your new password',
                      prefixIcon: Icons.lock_outline,
                      isPassword: true,
                    ),
                    const SizedBox(height: 24),
                    Consumer<AuthController>(
                      builder: (context, auth, _) => SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: auth.isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.actionColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Reset password',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back'),
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
