import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../../core/widgets/landa_sheet.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../../properties/controllers/landlord_controller.dart';
import '../../../properties/models/property_model.dart';
import '../../../properties/views/widgets/property_location_picker.dart';

class AddPropertyModal extends StatefulWidget {
  const AddPropertyModal({super.key});

  @override
  State<AddPropertyModal> createState() => _AddPropertyModalState();
}

class _AddPropertyModalState extends State<AddPropertyModal> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController(text: 'Lagos');
  final _stateCtrl = TextEditingController(text: 'Lagos');
  final _picker = ImagePicker();
  final List<File> _photos = [];
  File? _verificationVideo;

  /// Optional public property tour, separate from the private
  /// [_verificationVideo] used for ownership review.
  File? _listingVideo;
  File? _deed;
  LatLng? _pin;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked.isNotEmpty && mounted) {
          setState(
            () => _photos.addAll(picked.map((image) => File(image.path))),
          );
        }
      } else {
        final picked = await _picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (picked != null && mounted) {
          setState(() => _photos.add(File(picked.path)));
        }
      }
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to select photos: $error');
      }
    }
  }

  Future<void> _recordVerificationVideo() async {
    try {
      final video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 60),
      );
      if (video != null && mounted) {
        setState(() => _verificationVideo = File(video.path));
      }
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to record video: $error');
      }
    }
  }

  Future<void> _pickListingVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: PropertyMediaLimits.videoExtensions,
      );
      final path = result?.files.single.path;
      if (path == null || !mounted) return;

      final file = File(path);
      if (await file.length() > PropertyMediaLimits.maxVideoBytes) {
        if (mounted) {
          LandaToast.error(
            context,
            'Tour video must not exceed 50MB. Choose a shorter clip.',
          );
        }
        return;
      }
      if (mounted) setState(() => _listingVideo = file);
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to select video: $error');
      }
    }
  }

  Future<void> _pickDeed() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (result?.files.single.path != null && mounted) {
        setState(() => _deed = File(result!.files.single.path!));
      }
    } catch (error) {
      if (mounted) {
        LandaToast.error(context, 'Unable to select deed: $error');
      }
    }
  }

  Future<void> _submitProperty() async {
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    if (name.isEmpty || address.isEmpty) {
      LandaToast.error(context, 'Enter the property name and street address.');
      return;
    }
    if (_pin == null) {
      LandaToast.error(context, 'Drop a pin on the property location.');
      return;
    }
    if (_verificationVideo == null || _deed == null) {
      LandaToast.error(
        context,
        'A live verification video and deed are required.',
      );
      return;
    }
    setState(() => _isSubmitting = true);
    final property = await context.read<LandlordController>().createProperty(
      name: name,
      address: address,
      city: _cityCtrl.text.trim(),
      state: _stateCtrl.text.trim(),
      latitude: _pin!.latitude,
      longitude: _pin!.longitude,
      photos: _photos,
      verificationVideo: _verificationVideo!,
      deedFile: _deed!,
      listingVideo: _listingVideo,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (property == null) {
      LandaToast.error(
        context,
        context.read<LandlordController>().errorMessage ??
            'Could not submit property.',
      );
      return;
    }
    Navigator.pop(context);
    LandaToast.success(context, '${property.name} submitted for verification.');
  }

  @override
  Widget build(BuildContext context) {
    return LandaSheet(
      icon: Icons.add_location_alt_rounded,
      title: 'Add verified property',
      subtitle:
          'Pin the property, record a live walkthrough and attach proof of ownership.',
      accent: AppTheme.primaryColor,
      footer: LandaSheetButton(
        label: 'Submit property for review',
        icon: Icons.verified_outlined,
        color: AppTheme.primaryColor,
        isLoading: _isSubmitting,
        onPressed: _submitProperty,
      ),
      children: [
        const LandaFieldLabel('Property details'),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          style: AppTheme.cardTitle(context),
          decoration: landaInputDecoration(
            context,
            hint: 'Property name',
            prefixIcon: Icons.home_work_outlined,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          textCapitalization: TextCapitalization.words,
          style: AppTheme.cardTitle(context),
          decoration: landaInputDecoration(
            context,
            hint: 'Street address',
            prefixIcon: Icons.signpost_outlined,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _cityCtrl,
                textCapitalization: TextCapitalization.words,
                style: AppTheme.cardTitle(context),
                decoration: landaInputDecoration(context, hint: 'City'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _stateCtrl,
                textCapitalization: TextCapitalization.words,
                style: AppTheme.cardTitle(context),
                decoration: landaInputDecoration(context, hint: 'State'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        PropertyLocationPicker(onChanged: (pin) => _pin = pin),
        const SizedBox(height: 24),

        LandaFieldLabel(
          'Property photos',
          trailing: _OptionalTag(
            label: _photos.isEmpty ? 'Optional' : '${_photos.length} added',
            highlight: _photos.isNotEmpty,
          ),
        ),
        if (_photos.isNotEmpty) ...[
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: AppTheme.cornerMd,
                    child: Image.file(
                      _photos[index],
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: LandaPressable(
                      onTap: () => setState(() => _photos.removeAt(index)),
                      pressedScale: 0.88,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: LandaSheetChipButton(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                onTap: () => _pickPhotos(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LandaSheetChipButton(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () => _pickPhotos(ImageSource.gallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        LandaFieldLabel(
          'Live ownership check',
          trailing: _OptionalTag(
            label: (_verificationVideo != null && _deed != null)
                ? 'Complete'
                : 'Required',
            highlight: _verificationVideo != null && _deed != null,
            required: !(_verificationVideo != null && _deed != null),
          ),
        ),
        _EvidenceTile(
          icon: Icons.videocam_outlined,
          title: _verificationVideo == null
              ? 'Record live walkthrough'
              : 'Live walkthrough recorded',
          subtitle: _verificationVideo == null
              ? 'Record up to 60 seconds showing the exterior and your presence.'
              : _verificationVideo!.path.split('/').last,
          action: _verificationVideo == null ? 'Record' : 'Redo',
          onTap: _recordVerificationVideo,
          complete: _verificationVideo != null,
        ),
        const SizedBox(height: 10),
        _EvidenceTile(
          icon: Icons.description_outlined,
          title: _deed == null
              ? 'Attach deed or proof of ownership'
              : 'Proof of ownership attached',
          subtitle: _deed == null
              ? 'PDF, JPG or PNG. This is reviewed with the live video.'
              : _deed!.path.split('/').last,
          action: _deed == null ? 'Attach' : 'Replace',
          onTap: _pickDeed,
          complete: _deed != null,
        ),
        const SizedBox(height: 24),

        // Public-facing tour, distinct from the private ownership check
        // above. Optional, and can also be added later from the property
        // screen.
        LandaFieldLabel(
          'Property tour video',
          trailing: _OptionalTag(
            label: _listingVideo == null ? 'Optional' : 'Added',
            highlight: _listingVideo != null,
          ),
        ),
        _EvidenceTile(
          icon: Icons.movie_outlined,
          title: _listingVideo == null
              ? 'Add a tour video for your listing'
              : 'Tour video attached',
          subtitle: _listingVideo == null
              ? 'MP4 or MOV up to 50MB. Shown to tenants browsing the marketplace.'
              : _listingVideo!.path.split('/').last,
          action: _listingVideo == null ? 'Attach' : 'Replace',
          onTap: _pickListingVideo,
          complete: _listingVideo != null,
        ),
      ],
    );
  }
}

/// Small status pill beside a section label: whether the section is optional,
/// still required, or already satisfied.
class _OptionalTag extends StatelessWidget {
  final String label;
  final bool highlight;
  final bool required;

  const _OptionalTag({
    required this.label,
    this.highlight = false,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? AppTheme.successColor
        : required
        ? AppTheme.actionColor
        : AppTheme.mutedTextColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppTheme.cornerSm,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.labelText(
          context,
          color: color,
        ).copyWith(fontSize: 10, letterSpacing: 0.6),
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;
  final bool complete;

  const _EvidenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    required this.complete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = complete ? AppTheme.successColor : AppTheme.actionColor;
    return LandaPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: complete
              ? accent.withValues(alpha: 0.08)
              : AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(
            color: complete
                ? accent.withValues(alpha: 0.3)
                : AppTheme.borderColor(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: AppTheme.cornerSm,
              ),
              child: Icon(
                complete ? Icons.check_rounded : icon,
                size: 19,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.cardTitle(
                      context,
                    ).copyWith(fontSize: AppTheme.textSm),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyText(
                      context,
                      color: AppTheme.mutedTextColor(context),
                    ).copyWith(fontSize: AppTheme.textXs, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              action.toUpperCase(),
              style: AppTheme.labelText(
                context,
                color: accent,
              ).copyWith(fontSize: 10, letterSpacing: 0.6),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}
