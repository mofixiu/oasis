import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/oasis_entrance.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/main_scaffold.dart';
import '../controllers/auth_controller.dart';
import '../models/user_model.dart';
import '../../../core/widgets/oasis_busy.dart';
import '../../../core/app_variant.dart';

class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  final _ninController = TextEditingController();
  final _givenNamesController = TextEditingController();
  final _lastNameController = TextEditingController();
  File? _selfieFile;
  final ImagePicker _picker = ImagePicker();
  Timer? _verificationPoller;
  bool _isPolling = false;
  bool _pollRequestInFlight = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = context
          .read<AuthController>()
          .currentUser
          ?.verificationStatus;
      if (status == VerificationStatus.pending) {
        _startPolling();
      }
    });
  }

  @override
  void dispose() {
    _verificationPoller?.cancel();
    _ninController.dispose();
    _givenNamesController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _pickSelfie(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selfieFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      OasisToast.error(context, 'Error picking image: $e');
    }
  }

  Future<void> _submitVerification() async {
    final nin = _ninController.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(nin)) {
      OasisToast.error(context, 'NIN must contain exactly 11 digits.');
      return;
    }

    if (_selfieFile == null) {
      OasisToast.error(
        context,
        'Please select or capture a selfie for verification.',
      );
      return;
    }

    if (await _selfieFile!.length() > 5 * 1024 * 1024) {
      if (mounted) {
        OasisToast.error(context, 'Selfie image must not exceed 5MB.');
      }
      return;
    }

    if (!mounted) return;
    await _attemptVerification(nin);
  }

  /// Runs the actual verify call and handles every outcome, including the
  /// consent gate: if the backend says consent is required, this shows the
  /// consent sheet, records acceptance, then retries itself with the same
  /// [nin] and the currently-selected selfie/name fields.
  Future<void> _attemptVerification(String nin) async {
    final auth = context.read<AuthController>();
    final status = await auth.verifyIdentity(
      selfie: _selfieFile!,
      nin: nin,
      givenNames: _givenNamesController.text.trim().isEmpty
          ? null
          : _givenNamesController.text.trim(),
      lastName: _lastNameController.text.trim().isEmpty
          ? null
          : _lastNameController.text.trim(),
    );

    if (!mounted) return;

    if (status == VerificationStatus.verified) {
      _continueToProduct();
    } else if (status == VerificationStatus.pending) {
      OasisToast.success(
        context,
        'Verification request received. We’ll unlock your account once it is verified.',
      );
      _startPolling();
    } else if (status == VerificationStatus.failed) {
      OasisToast.error(
        context,
        'Verification could not be completed. Please review your details and try again.',
      );
    } else if (auth.consentRequired) {
      final agreed = await _showConsentSheet();
      if (!mounted || !agreed) return;

      final accepted = await auth.acceptVerificationConsent();
      if (!mounted) return;

      if (accepted) {
        await _attemptVerification(nin);
      } else if (auth.errorMessage != null) {
        OasisToast.error(context, auth.errorMessage!);
      }
    } else if (auth.errorMessage != null) {
      OasisToast.error(context, auth.errorMessage!);
    }
  }

  Future<bool> _showConsentSheet() async {
    final agreed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _VerificationConsentSheet(),
    );
    return agreed ?? false;
  }

  void _startPolling() {
    if (_isPolling || _hasNavigated) return;
    setState(() => _isPolling = true);

    Future<void> poll() async {
      if (!mounted || _pollRequestInFlight || _hasNavigated) return;
      _pollRequestInFlight = true;
      final status = await context
          .read<AuthController>()
          .checkVerificationStatus();
      _pollRequestInFlight = false;

      if (!mounted || _hasNavigated) return;
      if (status == VerificationStatus.verified) {
        _continueToProduct();
      } else if (status == VerificationStatus.failed) {
        _verificationPoller?.cancel();
        setState(() => _isPolling = false);
        OasisToast.error(
          context,
          'Verification could not be completed. Please submit a new request.',
        );
      }
    }

    poll();
    _verificationPoller = Timer.periodic(
      const Duration(seconds: 3),
      (_) => poll(),
    );
  }

  void _continueToProduct() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _verificationPoller?.cancel();
    OasisToast.success(context, 'Identity verified successfully.');
    Navigator.pushAndRemoveUntil(
      context,
      FadePageRoute(page: const MainScaffold()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authController = context.watch<AuthController>();
    final user = authController.currentUser;
    final isAlreadyVerified =
        user?.verificationStatus == VerificationStatus.verified;
    final isPending = user?.verificationStatus == VerificationStatus.pending;

    final accent = isAlreadyVerified
        ? AppTheme.successColor
        : AppTheme.actionColor;

    return Scaffold(
      backgroundColor: AppTheme.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppTheme.pageBackground(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppTheme.primaryTextColor(context)),
        title: Text(
          'Identity Verification',
          style: AppTheme.cardTitle(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OasisEntrance(
                    index: 0,
                    child: _VerificationHeader(
                      accent: accent,
                      isVerified: isAlreadyVerified,
                      isPending: isPending,
                    ),
                  ),

                  // Polling state. Uses the sand/vacant pair rather than raw
                  // amber so "waiting" reads as part of the palette instead of
                  // a stock Material warning.
                  if (isPending) ...[
                    const SizedBox(height: 20),
                    OasisEntrance(
                      index: 1,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.vacantSurface(context),
                          borderRadius: AppTheme.cornerMd,
                          border: Border.all(
                            color: AppTheme.vacantColor.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          children: [
                            const OasisBusyDots(color: AppTheme.primaryColor),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Checking your verification. This screen '
                                'continues automatically once it completes.',
                                style: AppTheme.bodyText(
                                  context,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  OasisEntrance(
                    index: 2,
                    child: _StepCard(
                      step: '1',
                      title: 'National ID',
                      subtitle: 'Your 11-digit National Identification Number.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _VerificationField(
                            controller: _ninController,
                            hint: '12345678901',
                            icon: Icons.badge_outlined,
                            keyboardType: TextInputType.number,
                            maxLength: 11,
                          ),
                          const SizedBox(height: 4),
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              childrenPadding: const EdgeInsets.only(bottom: 4),
                              expandedCrossAxisAlignment:
                                  CrossAxisAlignment.start,
                              title: Text(
                                'Full name (optional)',
                                style: AppTheme.bodyText(context),
                              ),
                              subtitle: Text(
                                "Only needed if this doesn't match your saved profile.",
                                style: AppTheme.labelText(
                                  context,
                                ).copyWith(letterSpacing: 0, fontSize: 11.5),
                              ),
                              children: [
                                _VerificationField(
                                  controller: _givenNamesController,
                                  hint: 'Given names',
                                  icon: Icons.person_outline,
                                ),
                                const SizedBox(height: 12),
                                _VerificationField(
                                  controller: _lastNameController,
                                  hint: 'Last name',
                                  icon: Icons.person_outline,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  OasisEntrance(
                    index: 3,
                    child: _StepCard(
                      step: '2',
                      title: 'Verification selfie',
                      subtitle: 'A clear photo of your face, under 5MB.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_selfieFile != null)
                            ClipRRect(
                              borderRadius: AppTheme.cornerMd,
                              child: Image.file(
                                _selfieFile!,
                                height: 190,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 34),
                              decoration: BoxDecoration(
                                color: AppTheme.subtleSurfaceColor(context),
                                borderRadius: AppTheme.cornerMd,
                                border: Border.all(
                                  color: AppTheme.borderColor(context),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.face_retouching_natural,
                                    size: 42,
                                    color: AppTheme.mutedTextColor(context),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'No selfie selected yet',
                                    style: AppTheme.bodyText(
                                      context,
                                      color: AppTheme.mutedTextColor(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OasisButton(
                                  label: 'Camera',
                                  icon: Icons.camera_alt_outlined,
                                  outlined: true,
                                  onPressed: () =>
                                      _pickSelfie(ImageSource.camera),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OasisButton(
                                  label: 'Gallery',
                                  icon: Icons.photo_library_outlined,
                                  outlined: true,
                                  onPressed: () =>
                                      _pickSelfie(ImageSource.gallery),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
                  OasisEntrance(
                    index: 4,
                    child: Consumer<AuthController>(
                      builder: (context, auth, _) => OasisButton(
                        label: isPending
                            ? 'Verification pending'
                            : isAlreadyVerified
                            ? 'Identity verified'
                            : 'Submit identity verification',
                        icon: isAlreadyVerified
                            ? Icons.verified_rounded
                            : Icons.shield_outlined,
                        isBusy: auth.isLoading,
                        color: accent,
                        onPressed:
                            auth.isLoading || _isPolling || isAlreadyVerified
                            ? null
                            : _submitVerification,
                      ),
                    ),
                  ),

                  if (isAlreadyVerified) ...[
                    const SizedBox(height: 12),
                    OasisEntrance(
                      index: 5,
                      child: OasisButton(
                        label: 'Continue to dashboard',
                        outlined: true,
                        color: AppTheme.profileColor,
                        onPressed: () => Navigator.pushAndRemoveUntil(
                          context,
                          FadePageRoute(page: const MainScaffold()),
                          (route) => false,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Text(
                    'Your NIN is never stored in full. We keep only a secure '
                    'fingerprint of it and a reference to this check.',
                    textAlign: TextAlign.center,
                    style: AppTheme.labelText(
                      context,
                    ).copyWith(letterSpacing: 0, fontSize: 11.5, height: 1.5),
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

/// Hero block: state-coloured badge, title and supporting line.
class _VerificationHeader extends StatelessWidget {
  final Color accent;
  final bool isVerified;
  final bool isPending;

  const _VerificationHeader({
    required this.accent,
    required this.isVerified,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 72,
        width: 72,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isVerified ? Icons.verified_user_rounded : Icons.lock_person_outlined,
          color: accent,
          size: 32,
        ),
      ),
      SizedBox(height: 16),
      Text(
        isVerified
            ? 'Your identity is verified'
            : isPending
            ? 'Verification in progress'
            : 'Verify your identity',
        textAlign: TextAlign.center,
        style: AppTheme.screenTitle(context),
      ),
      const SizedBox(height: 8),
      Text(
        isVerified
            ? 'You have full access to Oasis.'
            : isPending
            ? 'This usually takes a moment.'
            : isOasisV2
            ? 'A one-time check that keeps guests and hosts safe.'
            : 'A one-time check that unlocks properties, agreements and rent payments.',
        textAlign: TextAlign.center,
        style: AppTheme.bodyText(
          context,
          color: AppTheme.secondaryTextColor(context),
        ),
      ),
    ],
  );
}

/// Numbered step container, so the two inputs read as a sequence rather than
/// a stack of unrelated boxes.
class _StepCard extends StatelessWidget {
  final String step;
  final String title;
  final String subtitle;
  final Widget child;

  const _StepCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: AppTheme.cornerLg,
      border: Border.all(color: AppTheme.borderColor(context)),
      boxShadow: AppTheme.cardShadow(context),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 26,
              width: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.vacantSurface(context),
                shape: BoxShape.circle,
              ),
              child: Text(
                step,
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.primaryColor,
                ).copyWith(fontSize: 12, letterSpacing: 0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.cardTitle(context)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTheme.labelText(
                      context,
                    ).copyWith(letterSpacing: 0, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

/// Field styled to match the rest of the app's inputs.
class _VerificationField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final int? maxLength;

  const _VerificationField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    maxLength: maxLength,
    style: AppTheme.bodyText(
      context,
      color: AppTheme.primaryTextColor(context),
    ),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.bodyText(
        context,
        color: AppTheme.mutedTextColor(context),
      ),
      prefixIcon: Icon(icon, size: 19, color: AppTheme.mutedTextColor(context)),
      counterText: '',
      filled: true,
      fillColor: AppTheme.inputFillColor(context),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTheme.cornerSm,
        borderSide: BorderSide(color: AppTheme.borderColor(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTheme.cornerSm,
        borderSide: const BorderSide(color: AppTheme.actionColor, width: 1.5),
      ),
    ),
  );
}

/// One-time gate before the first `POST /verify/`: the backend rejects
/// verification with `403 CONSENT_REQUIRED` until this has been accepted.
class _VerificationConsentSheet extends StatelessWidget {
  const _VerificationConsentSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 24,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.vacantSurface(context),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.privacy_tip_outlined,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Verification & Privacy Consent',
                  style: AppTheme.sectionTitle(
                    context,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Before we verify your identity, you need to agree to how we handle your data:',
            style: AppTheme.bodyText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ).copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          const _ConsentPoint(
            text:
                'Your selfie and National Identification Number (NIN) are sent to our identity verification provider to confirm you are who you say you are.',
          ),
          const _ConsentPoint(
            text:
                'We never store your raw NIN, only a tokenized fingerprint of it, plus a reference to the verification attempt.',
          ),
          const _ConsentPoint(
            text:
                'This data is used solely to unlock Oasis product features and is not shared for any other purpose.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.actionColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'I Agree & Continue',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  final String text;

  const _ConsentPoint({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(
            Icons.check_circle,
            size: 16,
            color: AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ).copyWith(height: 1.4),
          ),
        ),
      ],
    ),
  );
}
