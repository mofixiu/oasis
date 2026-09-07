import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_pressable.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';
import '../../../../core/widgets/landa_busy.dart';

/// Shown on a landlord's own property card when the listing has no photos.
///
/// A property with no photos is hidden from the tenant marketplace, which is
/// invisible from the landlord's side: they would simply never hear from
/// anyone. This says what happened and fixes it in one tap, which is the only
/// thing that makes the rule fair to listings created before it existed.
class MissingPhotosPrompt extends StatefulWidget {
  final PropertyModel property;

  const MissingPhotosPrompt({super.key, required this.property});

  @override
  State<MissingPhotosPrompt> createState() => _MissingPhotosPromptState();
}

class _MissingPhotosPromptState extends State<MissingPhotosPrompt> {
  final _picker = ImagePicker();
  bool _isUploading = false;

  Future<void> _addPhotos() async {
    if (_isUploading) return;

    List<XFile> picked;
    try {
      picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 85);
    } catch (error) {
      if (mounted) LandaToast.error(context, 'Unable to select photos.');
      return;
    }
    if (picked.isEmpty || !mounted) return;

    setState(() => _isUploading = true);
    final controller = context.read<LandlordController>();
    final uploaded = await controller.uploadPropertyPhotos(
      propertyId: widget.property.id,
      photos: picked.map((image) => File(image.path)).toList(),
    );
    if (!mounted) return;
    setState(() => _isUploading = false);

    if (uploaded) {
      LandaToast.success(
        context,
        '${widget.property.name} is back in the marketplace.',
      );
    } else {
      LandaToast.error(
        context,
        controller.errorMessage ?? 'Could not upload those photos.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.vacantSurface(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.35)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.visibility_off_outlined,
          size: 17,
          color: AppTheme.warningColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hidden from the marketplace',
                style: AppTheme.cardTitle(context),
              ),
              const SizedBox(height: 2),
              Text(
                'Tenants only see listings with photos. Add a couple and this '
                'goes live again.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
              const SizedBox(height: 10),
              LandaPressable(
                onTap: _isUploading ? null : _addPhotos,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.actionColor,
                    borderRadius: AppTheme.cornerSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isUploading)
                        const LandaBusyDots(color: AppTheme.whiteColor, size: 4)
                      else
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 15,
                          color: AppTheme.whiteColor,
                        ),
                      const SizedBox(width: 7),
                      Text(
                        _isUploading ? 'Uploading…' : 'Add photos',
                        style: AppTheme.cardTitle(
                          context,
                          color: AppTheme.whiteColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
