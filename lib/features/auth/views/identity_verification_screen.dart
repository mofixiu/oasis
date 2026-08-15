import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fade_page_route.dart';
import '../../../core/widgets/landa_toast.dart';
import '../../../core/widgets/main_scaffold.dart';
import '../controllers/auth_controller.dart';
import '../models/user_model.dart';

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
      LandaToast.error(context, 'Error picking image: $e');
    }
  }

  Future<void> _submitVerification() async {
    final nin = _ninController.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(nin)) {
      LandaToast.error(context, 'NIN must contain exactly 11 digits.');
      return;
    }

    if (_selfieFile == null) {
      LandaToast.error(
        context,
        'Please select or capture a selfie for verification.',
      );
      return;
    }

    if (await _selfieFile!.length() > 5 * 1024 * 1024) {
      if (mounted) {
        LandaToast.error(context, 'Selfie image must not exceed 5MB.');
      }
      return;
    }

    if (!mounted) return;
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
      LandaToast.success(
        context,
        'Verification request received. We’ll unlock your account once it is verified.',
      );
      _startPolling();
    } else if (status == VerificationStatus.failed) {
      LandaToast.error(
        context,
        'Verification could not be completed. Please review your details and try again.',
      );
    } else if (auth.errorMessage != null) {
      LandaToast.error(context, auth.errorMessage!);
    }
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
        LandaToast.error(
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
    LandaToast.success(context, 'Identity verified successfully.');
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

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        title: const Text(
          'Identity Verification',
          style: TextStyle(
            color: AppTheme.profileColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 24.0,
            ),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isAlreadyVerified
                            ? AppTheme.successColor
                            : AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_person_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isAlreadyVerified
                          ? 'Your Identity is Fully Verified'
                          : isPending
                          ? 'Verification Request Pending'
                          : 'Verify Your Identity',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isAlreadyVerified
                          ? 'You have earned the VERIFIED status badge.'
                          : isPending
                          ? 'We are checking your verification status. This screen will continue automatically once it is complete.'
                          : 'Upload a selfie and enter your 11-digit NIN to begin verification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),

                    if (isPending) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Request pending — checking for completion…',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Step 1: NIN Field
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '1. National ID (NIN)',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.profileColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ninController,
                                  keyboardType: TextInputType.number,
                                  maxLength: 11,
                                  decoration: InputDecoration(
                                    labelText: '11-DIGIT NIN',
                                    hintText: '12345678901',
                                    prefixIcon: const Icon(
                                      Icons.badge_outlined,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Optional: names for Smile ID sandbox test identities.
                          Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                20,
                                0,
                                20,
                                20,
                              ),
                              title: const Text(
                                'Full name (optional)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.profileColor,
                                ),
                              ),
                              subtitle: const Text(
                                'Only needed if this doesn\'t match your saved profile.',
                                style: TextStyle(fontSize: 12),
                              ),
                              children: [
                                TextField(
                                  controller: _givenNamesController,
                                  decoration: InputDecoration(
                                    labelText: 'GIVEN NAMES',
                                    hintText: 'Amina Fatou',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _lastNameController,
                                  decoration: InputDecoration(
                                    labelText: 'LAST NAME',
                                    hintText: 'Clearwater',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Step 2: Selfie Photo Picker
                          Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '2. Verification Selfie',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.profileColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_selfieFile != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      _selfieFile!,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                else
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 32,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.subtleSurfaceColor(
                                        context,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        style: BorderStyle.solid,
                                      ),
                                    ),
                                    child: const Column(
                                      children: [
                                        Icon(
                                          Icons.face_retouching_natural,
                                          size: 48,
                                          color: AppTheme.profileColor,
                                        ),
                                        SizedBox(height: 12),
                                        Text(
                                          'No selfie selected yet',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _pickSelfie(ImageSource.camera),
                                        icon: const Icon(
                                          Icons.camera_alt,
                                          size: 18,
                                        ),
                                        label: const Text('Camera'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _pickSelfie(ImageSource.gallery),
                                        icon: const Icon(
                                          Icons.photo_library,
                                          size: 18,
                                        ),
                                        label: const Text('Gallery'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: Consumer<AuthController>(
                        builder: (context, auth, _) {
                          return ElevatedButton.icon(
                            onPressed:
                                auth.isLoading ||
                                    _isPolling ||
                                    isAlreadyVerified
                                ? null
                                : _submitVerification,
                            icon: auth.isLoading
                                ? const SizedBox()
                                : const Icon(
                                    Icons.verified,
                                    color: Colors.white,
                                  ),
                            label: auth.isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    isPending
                                        ? 'Verification Pending'
                                        : isAlreadyVerified
                                        ? 'Identity Verified'
                                        : 'Submit Identity Verification',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.actionColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (isAlreadyVerified)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              FadePageRoute(page: const MainScaffold()),
                              (route) => false,
                            );
                          },
                          child: const Text('Continue to Dashboard'),
                        ),
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
