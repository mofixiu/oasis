import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../fix/models/fix_models.dart';
import '../controllers/auth_controller.dart';
import '../models/user_model.dart';
import 'widgets/auth_text_field.dart';
import 'sign_in_screen.dart';
import 'identity_verification_screen.dart';
import '../../../core/widgets/oasis_busy.dart';
import '../../../core/app_variant.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  // Artisan-only. An artisan account carries a trade, where it works and how
  // long it has been at it, that is the whole of what a tenant sees before
  // deciding whether to let someone into their home.
  final _locationController = TextEditingController();
  final _bioController = TextEditingController();
  final _experienceController = TextEditingController();

  // v2 is a guest-first app, so it opens on Guest.
  UserRole _selectedRole = isOasisV2 ? UserRole.tenant : UserRole.owner;

  /// The roles the selector offers. Artisans are reached from the line at the
  /// foot of the page rather than from a third tab: see the selector.
  static const List<UserRole> _rentingRoles = isOasisV2
      ? [UserRole.tenant, UserRole.owner]
      : [UserRole.owner, UserRole.tenant];

  /// The trade, for an artisan. Seeded from [ArtisanCategory.defaults]: the
  /// live category list needs a verified token, and there is no token yet on
  /// this screen.
  String _category = ArtisanCategory.defaults.first.value;

  bool _isSubmitting = false;

  bool get _isArtisan => _selectedRole == UserRole.artisan;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _locationController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    // Closed first: the next screen replaces this one, and a keyboard left
    // up for a field that no longer exists has no way to be dismissed.
    FocusManager.instance.primaryFocus?.unfocus();
    if (_isSubmitting) return;

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || phone.isEmpty || password.isEmpty) {
      OasisToast.error(context, 'Please fill in all fields.');
      return;
    }

    // Checked here rather than left to the backend: an artisan with no
    // location is invisible to the tenants nearest them, which looks like the
    // app not working rather than a field they skipped.
    final location = _locationController.text.trim();
    if (_isArtisan && location.isEmpty) {
      OasisToast.error(context, 'Tell tenants where you work.');
      return;
    }

    final experience = int.tryParse(_experienceController.text.trim());
    if (_isArtisan &&
        _experienceController.text.trim().isNotEmpty &&
        (experience == null || experience < 0)) {
      OasisToast.error(context, 'Years of experience must be a whole number.');
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
      category: _isArtisan ? _category : null,
      location: _isArtisan ? location : null,
      bio: _isArtisan ? _bioController.text.trim() : null,
      yearsOfExperience: _isArtisan ? (experience ?? 0) : null,
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    if (success) {
      // Names the next step rather than declaring the job done. An account
      // exists, but nothing in the app works until identity verification
      // clears, and for an artisan in particular, "created successfully"
      // read as "you are live and can be hired", which is not true yet.
      OasisToast.success(
        context,
        _isArtisan
            ? 'Account created. Verify your identity to start taking jobs.'
            : 'Account created. One more step: verify your identity.',
      );
      Navigator.pushAndRemoveUntil(
        context,
        FadePageRoute(page: const IdentityVerificationScreen()),
        (route) => false,
      );
    } else if (auth.errorMessage != null) {
      OasisToast.error(context, auth.errorMessage!);
    }
  }

  /// One line under the role selector saying what the chosen account is for.
  String get _roleBlurb {
    switch (_selectedRole) {
      case UserRole.owner:
        return isOasisV2
            ? 'List your shortlets and welcome guests.'
            : 'List properties, sign tenancies and collect rent.';
      case UserRole.tenant:
        return isOasisV2
            ? 'Book shortlets for every plan and pay securely.'
            : 'Find a home, sign your tenancy and pay rent securely.';
      case UserRole.artisan:
        return 'Take repair jobs from verified tenants and get paid through '
            'the app.';
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
                      AppTheme.isDarkMode(context)
                          ? 'assets/images/oasis_wordmark_dark.png'
                          : 'assets/images/oasis_wordmark.png',
                      height: 44,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Create an account',
                      style: AppTheme.screenTitle(
                        context,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isOasisV2
                          ? 'Book and host shortlets with Oasis.'
                          : 'Secure access to Oasis real estate platform.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryTextColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Role selector, and only the two roles this app is
                    // about. An artisan is a different kind of account:
                    // they hold no unit and sign no tenancy, and giving it
                    // a third of the selector implied one visitor in three
                    // was here to register a trade, which squeezed the two
                    // that matter and put a stranger's option in front of
                    // every tenant. Artisans get the quiet line at the foot
                    // of the page instead.
                    if (!_isArtisan) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurfaceColor(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            for (final role in _rentingRoles)
                              Expanded(
                                child: _RoleOption(
                                  label: role.displayName,
                                  selected: _selectedRole == role,
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(
                                          () => _selectedRole = role,
                                        ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ] else
                      // Where the selector was, so an artisan can see what
                      // they are signing up for and get back out of it.
                      _ArtisanModeBanner(
                        onLeave: _isSubmitting
                            ? null
                            : () => setState(
                                () => _selectedRole = UserRole.owner,
                              ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      _roleBlurb,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryTextColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

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
                            color: Colors.black.withValues(alpha: 0.04),
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

                          // Trade details. Only an artisan has them, and they
                          // are collected up front because a profile with no
                          // trade cannot be listed to anybody.
                          if (_isArtisan) ...[
                            const SizedBox(height: 24),
                            Divider(color: borderColor, height: 1),
                            const SizedBox(height: 20),
                            Text(
                              'YOUR TRADE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.9,
                                color: secondaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _CategoryPicker(
                              value: _category,
                              enabled: !_isSubmitting,
                              onChanged: (value) =>
                                  setState(() => _category = value),
                            ),
                            const SizedBox(height: 20),
                            AuthTextField(
                              controller: _locationController,
                              label: 'WHERE YOU WORK',
                              hintText: 'Lekki Phase 1',
                              prefixIcon: Icons.place_outlined,
                              keyboardType: TextInputType.streetAddress,
                            ),
                            const SizedBox(height: 20),
                            AuthTextField(
                              controller: _experienceController,
                              label: 'YEARS OF EXPERIENCE',
                              hintText: '5',
                              prefixIcon: Icons.workspace_premium_outlined,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 20),
                            AuthTextField(
                              controller: _bioController,
                              label: 'ABOUT YOU (OPTIONAL)',
                              hintText: 'Reliable plumber for home repairs.',
                              prefixIcon: Icons.notes_outlined,
                              keyboardType: TextInputType.text,
                            ),
                          ],

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
                                            OasisBusyDots(color: Colors.white),
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
                    const SizedBox(height: 24),

                    // The way to an artisan account: small, at the bottom,
                    // and out of the way of the two roles this app is for.
                    // It switches the same form rather than pushing another
                    // screen: everything above it is still what an artisan
                    // fills in, plus their trade.
                    // Artisans belong to v1's Fix, which is switched off.
                    if (!isOasisV2 && !_isArtisan)
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => setState(
                                () => _selectedRole = UserRole.artisan,
                              ),
                        style: TextButton.styleFrom(
                          foregroundColor: secondaryTextColor,
                        ),
                        child: const Text(
                          'Are you an artisan? Register your trade',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
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

/// Stands in for the role selector once the artisan line at the foot of the
/// page has been tapped.
///
/// Its job is the way back. Switching the form to a trade account changes
/// which fields are asked for, and without something saying so a tenant who
/// tapped the line out of curiosity would be left filling in a plumber's
/// profile with no visible way out of it.
class _ArtisanModeBanner extends StatelessWidget {
  final VoidCallback? onLeave;

  const _ArtisanModeBanner({required this.onLeave});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
    decoration: BoxDecoration(
      color: AppTheme.actionColor.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.actionColor.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.handyman_outlined,
          size: 19,
          color: AppTheme.actionColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Registering as an artisan',
            style: AppTheme.cardTitle(context, color: AppTheme.actionColor),
          ),
        ),
        TextButton(
          onPressed: onLeave,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.secondaryTextColor(context),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
          ),
          child: const Text(
            'Not an artisan',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// One slot in the role selector.
class _RoleOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _RoleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected ? AppTheme.actionColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.secondaryTextColor(context),
        ),
      ),
    ),
  );
}

/// The trade an artisan works in, as a wrap of chips.
///
/// Chips rather than a dropdown: there are four of them, they are the single
/// most important thing about the account, and a dropdown would hide three of
/// the four behind a tap.
class _CategoryPicker extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _CategoryPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final category in ArtisanCategory.defaults)
        GestureDetector(
          onTap: enabled ? () => onChanged(category.value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: category.value == value
                  ? AppTheme.actionColor.withValues(alpha: 0.12)
                  : AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerSm,
              border: Border.all(
                color: category.value == value
                    ? AppTheme.actionColor
                    : AppTheme.borderColor(context),
                width: category.value == value ? 1.4 : 1,
              ),
            ),
            child: Text(
              category.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: category.value == value
                    ? AppTheme.actionColor
                    : AppTheme.secondaryTextColor(context),
              ),
            ),
          ),
        ),
    ],
  );
}
