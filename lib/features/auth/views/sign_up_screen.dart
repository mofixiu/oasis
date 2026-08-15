import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/landa_toast.dart';
import '../controllers/auth_controller.dart';
import '../models/user_model.dart';
import 'widgets/auth_text_field.dart';
import 'sign_in_screen.dart';
import 'identity_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _selectedRole = UserRole.owner;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    if (_isSubmitting) return;

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || phone.isEmpty || password.isEmpty) {
      LandaToast.error(context, 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final auth = context.read<AuthController>();
    final success = await auth.register(
      email: email,
      password: password,
      phone: phone,
      role: _selectedRole,
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      LandaToast.success(context, 'Account created successfully!');
      Navigator.pushAndRemoveUntil(
        context,
        FadePageRoute(page: const IdentityVerificationScreen()),
        (route) => false,
      );
    } else if (auth.errorMessage != null) {
      LandaToast.error(context, auth.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondaryTextColor = AppTheme.secondaryTextColor(context);
    final surfaceColor = AppTheme.surfaceColor(context);
    final borderColor = AppTheme.borderColor(context);

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/newlogonobackground.png',
                      height: 44,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Create an account',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Secure access to Landa OS real estate platform.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryTextColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Role Selector Toggle
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleSurfaceColor(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: _isSubmitting
                                  ? null
                                  : () => setState(
                                      () => _selectedRole = UserRole.owner,
                                    ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedRole == UserRole.owner
                                      ? AppTheme.actionColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Landlord / Owner',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedRole == UserRole.owner
                                        ? Colors.white
                                        : secondaryTextColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: _isSubmitting
                                  ? null
                                  : () => setState(
                                      () => _selectedRole = UserRole.tenant,
                                    ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedRole == UserRole.tenant
                                      ? AppTheme.actionColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Tenant',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedRole == UserRole.tenant
                                        ? Colors.white
                                        : secondaryTextColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Form Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AuthTextField(
                            controller: _emailController,
                            label: 'EMAIL ADDRESS',
                            hintText: 'user@example.com',
                            prefixIcon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 20),
                          AuthTextField(
                            controller: _phoneController,
                            label: 'PHONE NUMBER',
                            hintText: '+2348012345678',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 20),
                          AuthTextField(
                            controller: _passwordController,
                            label: 'SECURE PASSWORD',
                            hintText: '••••••••••••',
                            prefixIcon: Icons.lock_outline,
                            isPassword: true,
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: Consumer<AuthController>(
                              builder: (context, auth, _) {
                                final loading = _isSubmitting || auth.isLoading;
                                return ElevatedButton(
                                  onPressed: loading ? null : _handleRegister,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.actionColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: loading
                                      ? const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text(
                                              'Creating account...',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Create Account',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(Icons.arrow_forward, size: 20),
                                          ],
                                        ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account? ',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                        GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () {
                                  Navigator.pushReplacement(
                                    context,
                                    FadePageRoute(page: const SignInScreen()),
                                  );
                                },
                          child: const Text(
                            'Sign in here',
                            style: TextStyle(
                              color: AppTheme.actionColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
