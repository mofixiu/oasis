import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_network_image.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/user_model.dart';
import '../services/profile_service.dart';

/// Name, photo, phone, birthday and a short bio. Email and account type are
/// shown but not editable here.
class V2EditProfileScreen extends StatefulWidget {
  final ProfileService? service;

  const V2EditProfileScreen({super.key, this.service});

  @override
  State<V2EditProfileScreen> createState() => _V2EditProfileScreenState();
}

class _V2EditProfileScreenState extends State<V2EditProfileScreen> {
  static const _bioLimit = 150;

  late final ProfileService _service;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _bio;
  DateTime? _birthday;
  File? _pickedPhoto;
  bool _isSaving = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileService();
    final user = context.read<AuthController>().currentUser;
    _name = TextEditingController(text: user?.fullName ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _bio = TextEditingController(text: user?.bio ?? '');
    _birthday = DateTime.tryParse(user?.dateOfBirth ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// The backend has not shipped these fields until it says otherwise.
  String _failureMessage(Object error, String fallback) {
    if (error is ApiException) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        return 'Profile editing is not available yet.';
      }
      if (error.message.isNotEmpty) return error.message;
    }
    return fallback;
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    setState(() {
      _pickedPhoto = file;
      _isUploading = true;
    });
    try {
      await _service.uploadAvatar(file);
      if (!mounted) return;
      await context.read<AuthController>().refreshProfile();
      if (!mounted) return;
      OasisToast.success(context, 'Photo updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _pickedPhoto = null);
      OasisToast.error(
        context,
        _failureMessage(error, 'Could not upload that photo. Try again.'),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 16, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _save() async {
    final user = context.read<AuthController>().currentUser;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final bio = _bio.text.trim();
    final birthday = _birthday == null
        ? ''
        : DateFormat('yyyy-MM-dd').format(_birthday!);

    final nameLocked = _isNameLocked(user);
    if (!nameLocked && name.isEmpty) {
      OasisToast.error(context, 'Add your full name.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Only what changed, so a field the backend is stricter about is not
      // re-validated on every save.
      await _service.updateProfile(
        fullName: nameLocked || name == user?.fullName ? null : name,
        phone: phone == user?.phone ? null : phone,
        dateOfBirth: birthday == user?.dateOfBirth ? null : birthday,
        bio: bio == user?.bio ? null : bio,
      );
      if (!mounted) return;
      await context.read<AuthController>().refreshProfile();
      if (!mounted) return;
      OasisToast.success(context, 'Profile saved.');
      Navigator.maybePop(context);
    } catch (error) {
      if (!mounted) return;
      OasisToast.error(
        context,
        _failureMessage(error, 'Could not save your profile. Try again.'),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;
    final role = context.select<AuthController, UserRole>(
      (auth) => auth.currentRole,
    );
    final initial = (user?.preferredName ?? '?').characters.first;

    return V2StatusBar(
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.paddingOf(context).bottom + 28,
            ),
            children: [
              Row(
                children: [
                  V2CircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    size: 40,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Edit profile',
                      textAlign: TextAlign.center,
                      style: AppTheme.sectionTitle(context),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: _isSaving
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : TextButton(
                            onPressed: _save,
                            child: const Text(
                              'Save',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: OasisPressable(
                  onTap: _isUploading ? null : _pickPhoto,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 104,
                          height: 104,
                          child: _pickedPhoto != null
                              ? Image.file(_pickedPhoto!, fit: BoxFit.cover)
                              : (user?.avatarUrl.isNotEmpty ?? false)
                              ? OasisNetworkImage(
                                  url: user!.avatarUrl,
                                  placeholderIcon: Icons.person,
                                )
                              : Container(
                                  color: AppTheme.terracottaColor,
                                  alignment: Alignment.center,
                                  child: Text(
                                    initial,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      if (_isUploading)
                        const Positioned.fill(
                          child: ClipOval(
                            child: ColoredBox(
                              color: Colors.black38,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppTheme.blackColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.pageBackground(context),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_outlined,
                            size: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _isUploading ? null : _pickPhoto,
                  child: const Text('Change photo'),
                ),
              ),
              const SizedBox(height: 12),
              if (_isNameLocked(user))
                _FieldBox(
                  label: 'Full name',
                  helper:
                      'Your name comes from your ID check. Contact support '
                      'to change it.',
                  child: Text(
                    (user?.fullName ?? '').isEmpty ? 'Not set' : user!.fullName,
                    style: AppTheme.bodyText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ).copyWith(fontSize: 15),
                  ),
                )
              else
                _FieldBox(
                  label: 'Full name',
                  child: _input(_name, hint: 'Your name as on your ID'),
                ),
              _FieldBox(
                label: 'Email address',
                helper: 'Email can’t be changed here.',
                child: Text(
                  user?.email ?? '',
                  style: AppTheme.bodyText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ).copyWith(fontSize: 15),
                ),
              ),
              _FieldBox(
                label: 'Phone number',
                child: _input(
                  _phone,
                  hint: '+234 800 000 0000',
                  keyboard: TextInputType.phone,
                ),
              ),
              _FieldBox(
                label: 'Date of birth (optional)',
                onTap: _pickBirthday,
                trailing: Icon(
                  Icons.event_outlined,
                  color: AppTheme.secondaryTextColor(context),
                ),
                child: Text(
                  _birthday == null
                      ? 'Add your birthday'
                      : DateFormat('d MMMM yyyy').format(_birthday!),
                  style: AppTheme.bodyText(
                    context,
                    color: _birthday == null
                        ? AppTheme.mutedTextColor(context)
                        : AppTheme.primaryTextColor(context),
                  ).copyWith(fontSize: 15),
                ),
              ),
              _FieldBox(
                label: 'Bio (optional)',
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _bio,
                  builder: (context, value, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _input(
                        _bio,
                        hint: 'Tell hosts a bit about yourself…',
                        maxLines: 4,
                        maxLength: _bioLimit,
                      ),
                      Text(
                        '${value.text.characters.length}/$_bioLimit',
                        style: AppTheme.bodyText(
                          context,
                          color: AppTheme.mutedTextColor(context),
                        ).copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              // Read-only, like email: the role is fixed at sign-up. A
              // disabled Guest/Host toggle read as an invitation to switch.
              _FieldBox(
                label: 'Account type',
                child: Text(
                  role == UserRole.owner ? 'Host' : 'Guest',
                  style: AppTheme.bodyText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ).copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The backend refuses a name change from an ID-verified account (API
  /// guide 20), and using the app at all requires one, so for nearly
  /// everyone this is read-only.
  bool _isNameLocked(UserModel? user) =>
      user?.verificationStatus == VerificationStatus.verified;

  Widget _input(
    TextEditingController controller, {
    required String hint,
    TextInputType? keyboard,
    int maxLines = 1,
    int? maxLength,
  }) => TextField(
    controller: controller,
    keyboardType: keyboard,
    maxLines: maxLines,
    minLines: 1,
    maxLength: maxLength,
    textCapitalization: keyboard == null
        ? TextCapitalization.sentences
        : TextCapitalization.none,
    style: AppTheme.bodyText(
      context,
      color: AppTheme.primaryTextColor(context),
    ).copyWith(fontSize: 15),
    decoration: InputDecoration(
      isDense: true,
      counterText: '',
      border: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: AppTheme.bodyText(
        context,
        color: AppTheme.mutedTextColor(context),
      ).copyWith(fontSize: 15),
    ),
  );
}

/// A filled box with a small label over its value, as in the mockup.
class _FieldBox extends StatelessWidget {
  final String label;
  final Widget child;
  final String? helper;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _FieldBox({
    required this.label,
    required this.child,
    this.helper,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OasisPressable(
          onTap: onTap,
          pressedScale: onTap == null ? 1 : 0.99,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTheme.bodyText(
                          context,
                        ).copyWith(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      child,
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              helper!,
              style: AppTheme.bodyText(
                context,
                color: AppTheme.mutedTextColor(context),
              ).copyWith(fontSize: 11),
            ),
          ),
      ],
    ),
  );
}
