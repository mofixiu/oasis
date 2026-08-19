import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_video_player.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';

/// Landlord-facing manager for a property's listing photos and tour video.
///
/// The first photo becomes the marketplace cover image, so it is badged as
/// such — landlords need to know which one tenants will actually see.
class PropertyMediaManager extends StatefulWidget {
  final PropertyModel property;

  const PropertyMediaManager({super.key, required this.property});

  @override
  State<PropertyMediaManager> createState() => _PropertyMediaManagerState();
}

class _PropertyMediaManagerState extends State<PropertyMediaManager> {
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<LandlordController>().loadPropertyMedia(
        widget.property.id,
      ),
    );
  }

  Future<void> _addPhotos(int currentCount) async {
    final remaining = PropertyMediaLimits.maxPhotos - currentCount;
    if (remaining <= 0) {
      LandaToast.error(
        context,
        'This property already has the maximum of ${PropertyMediaLimits.maxPhotos} photos.',
      );
      return;
    }

    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty || !mounted) return;

    if (picked.length > remaining) {
      LandaToast.error(
        context,
        'You can add $remaining more ${remaining == 1 ? 'photo' : 'photos'}. Select fewer and try again.',
      );
      return;
    }

    // Enforce the documented 5MB-per-photo cap here rather than spending an
    // upload round-trip to be rejected.
    final files = <File>[];
    for (final image in picked) {
      final file = File(image.path);
      if (await file.length() > PropertyMediaLimits.maxPhotoBytes) {
        if (!mounted) return;
        LandaToast.error(
          context,
          '"${image.name}" is larger than 5MB. Please choose a smaller image.',
        );
        return;
      }
      files.add(file);
    }

    if (!mounted) return;
    final controller = context.read<LandlordController>();
    final success = await controller.uploadPropertyPhotos(
      propertyId: widget.property.id,
      photos: files,
    );
    if (!mounted) return;
    if (success) {
      LandaToast.success(
        context,
        files.length == 1 ? 'Photo added.' : '${files.length} photos added.',
      );
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  Future<void> _deletePhoto(PropertyPhoto photo, bool isCover) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove this photo?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        content: Text(
          isCover
              ? 'This is the cover photo tenants see first. The next photo will become the new cover.'
              : 'This photo will no longer appear on your listing.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.disputeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Remove',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<LandlordController>();
    final success = await controller.deletePropertyPhoto(
      propertyId: widget.property.id,
      photoId: photo.id,
    );
    if (!mounted) return;
    if (success) {
      LandaToast.success(context, 'Photo removed.');
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  Future<void> _uploadVideo({required bool replacing}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: PropertyMediaLimits.videoExtensions,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;

    final file = File(path);
    if (await file.length() > PropertyMediaLimits.maxVideoBytes) {
      if (!mounted) return;
      LandaToast.error(
        context,
        'Video is larger than 50MB. Please choose a shorter or more compressed clip.',
      );
      return;
    }

    if (!mounted) return;
    final controller = context.read<LandlordController>();
    final success = await controller.uploadPropertyVideo(
      propertyId: widget.property.id,
      video: file,
    );
    if (!mounted) return;
    if (success) {
      LandaToast.success(
        context,
        replacing ? 'Tour video replaced.' : 'Tour video uploaded.',
      );
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  Future<void> _deleteVideo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove tour video?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        content: const Text(
          'Tenants browsing the marketplace will no longer see a video tour for this property.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.disputeColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Remove',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<LandlordController>();
    final success = await controller.deletePropertyVideo(widget.property.id);
    if (!mounted) return;
    if (success) {
      LandaToast.success(context, 'Tour video removed.');
    } else if (controller.errorMessage != null) {
      LandaToast.error(context, controller.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LandlordController>();
    final photos = controller.propertyPhotos[widget.property.id] ?? const [];
    final videoUrl = controller.videoUrlFor(widget.property.id);
    final busy = controller.isMediaBusy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'LISTING PHOTOS',
          trailing: '${photos.length}/${PropertyMediaLimits.maxPhotos}',
          action: photos.length < PropertyMediaLimits.maxPhotos
              ? TextButton.icon(
                  onPressed: busy ? null : () => _addPhotos(photos.length),
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.actionColor,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 8),
        if (photos.isEmpty)
          _EmptyMediaCard(
            icon: Icons.photo_library_outlined,
            message:
                'No listing photos yet. The first photo you add becomes the cover tenants see in the marketplace.',
            actionLabel: 'Add photos',
            onAction: busy ? null : () => _addPhotos(0),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: photos.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) => _PhotoTile(
              photo: photos[index],
              isCover: index == 0,
              enabled: !busy,
              onDelete: () => _deletePhoto(photos[index], index == 0),
            ),
          ),

        const SizedBox(height: 24),
        const _SectionHeader(title: 'PROPERTY TOUR VIDEO'),
        const SizedBox(height: 8),
        if (videoUrl == null)
          _EmptyMediaCard(
            icon: Icons.videocam_outlined,
            message:
                'Add an optional walkthrough video (MP4 or MOV, up to 50MB) to help your listing stand out.',
            actionLabel: 'Upload video',
            onAction: busy ? null : () => _uploadVideo(replacing: false),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Column(
              children: [
                // Play inline so the landlord sees exactly what tenants will.
                LandaVideoPlayer(
                  url: videoUrl,
                  thumbnailUrl: widget.property.displayImageUrl,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => _uploadVideo(replacing: true),
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Replace video'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.secondaryTextColor(context),
                          side: BorderSide(
                            color: AppTheme.borderColor(context),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: busy ? null : _deleteVideo,
                      icon: const Icon(Icons.delete_outline),
                      color: AppTheme.disputeColor,
                      tooltip: 'Remove video',
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (busy) ...[
          const SizedBox(height: 12),
          const Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? action;

  const _SectionHeader({required this.title, this.trailing, this.action});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: Colors.grey,
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: 8),
        Text(
          trailing!,
          style: TextStyle(
            fontSize: 11,
            color: AppTheme.mutedTextColor(context),
          ),
        ),
      ],
      const Spacer(),
      if (action != null) action!,
    ],
  );
}

class _PhotoTile extends StatelessWidget {
  final PropertyPhoto photo;
  final bool isCover;
  final bool enabled;
  final VoidCallback onDelete;

  const _PhotoTile({
    required this.photo,
    required this.isCover,
    required this.enabled,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            photo.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppTheme.primaryColor.withValues(alpha: .08),
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppTheme.primaryColor,
              ),
            ),
          ),
          if (isCover)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.actionColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'COVER',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: enabled ? onDelete : null,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMediaCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  const _EmptyMediaCard({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Column(
      children: [
        Icon(icon, size: 34, color: AppTheme.mutedTextColor(context)),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: onAction,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.actionColor,
            side: const BorderSide(color: AppTheme.actionColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}
