import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/landa_network_image.dart';
import '../../../../core/widgets/landa_toast.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';
import '../../../../core/widgets/landa_busy.dart';
import '../../../../core/widgets/landa_shimmer.dart';

/// Landlord-facing manager for a property's listing photos.
///
/// The first photo becomes the marketplace cover image, so it is badged as
/// such: landlords need to know which one tenants will actually see.
///
/// Photos here are of the *building*: the gate, the compound, the street. The
/// tour video that used to sit alongside them now belongs to each unit, since
/// a tenant applies for one flat and a single video of a block told them
/// nothing about it. What remains of it here is a count of which units still
/// need one.
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
        title: Text(
          'Remove this photo?',
          style: AppTheme.sectionTitle(context, color: AppTheme.primaryColor),
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LandlordController>();
    final photos = controller.propertyPhotos[widget.property.id] ?? const [];
    final units =
        controller.propertyUnits[widget.property.id] ?? const <UnitModel>[];
    final missingVideos = units.where((unit) => unit.needsTourVideo).length;
    final busy = controller.isMediaBusy;

    // Has this property's media come back yet? Not the same question as
    // "is a request in flight": the fetch is scheduled post-frame, so on the
    // very first frame nothing is loading *and* nothing has been loaded, and
    // an empty photo list at that moment means "not asked", not "none".
    //
    // Reading it as "none" is what made the page announce "No listing photos
    // yet" to a landlord with four of them, and then swap to the grid a
    // moment later, which reads as the app having lost their photos and
    // found them again.
    final hasLoadedMedia = controller.hasLoaded(
      LandlordController.propertyMediaKey(widget.property.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'LISTING PHOTOS',
          // The count is a claim about what is on the listing, so it stays
          // blank until there is one to make.
          trailing: hasLoadedMedia
              ? '${photos.length}/${PropertyMediaLimits.maxPhotos}'
              : null,
          action:
              hasLoadedMedia && photos.length < PropertyMediaLimits.maxPhotos
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
        if (!hasLoadedMedia)
          // Shaped like the grid that is coming, so the arrival reads as the
          // photos resolving rather than the page changing its mind.
          const _PhotoGridSkeleton()
        else if (photos.isEmpty)
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
        // The walkthrough moved onto each unit. What is left here is the
        // scoreboard: a landlord who never opens an individual unit still
        // needs to know that three of their flats have nothing for a tenant
        // to watch, because that is why those flats are not being applied
        // for.
        const _SectionHeader(title: 'UNIT TOUR VIDEOS'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: missingVideos > 0
                ? AppTheme.actionColor.withValues(alpha: 0.07)
                : AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: missingVideos > 0
                  ? AppTheme.actionColor.withValues(alpha: 0.3)
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                missingVideos > 0
                    ? Icons.videocam_off_outlined
                    : Icons.videocam_outlined,
                size: 20,
                color: missingVideos > 0
                    ? AppTheme.actionColor
                    : AppTheme.successColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  units.isEmpty
                      ? 'Each unit gets its own walkthrough. Add units below '
                            'and attach one to each.'
                      : missingVideos > 0
                      ? '$missingVideos of ${units.length} '
                            '${units.length == 1 ? 'unit has' : 'units have'} '
                            'no tour video. Open the unit below to add one, '
                            'tenants rarely apply for a flat they cannot see '
                            'inside.'
                      : 'Every unit has a tour video.',
                  style: AppTheme.bodyText(context),
                ),
              ),
            ],
          ),
        ),
        if (busy) ...[
          const SizedBox(height: 12),
          const LandaBusyLine(label: 'Uploading'),
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
          LandaNetworkImage(
            url: photo.imageUrl,
            placeholderIcon: Icons.image_outlined,
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

/// Placeholder for the photo grid while a property's media is being read.
///
/// Three tiles, the same size and spacing as the real ones: enough to say
/// "photos are coming" without claiming a count the app does not yet know.
class _PhotoGridSkeleton extends StatelessWidget {
  const _PhotoGridSkeleton();

  @override
  Widget build(BuildContext context) => LandaShimmer(
    child: GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: const [
        ShimmerBox(height: 100),
        ShimmerBox(height: 100),
        ShimmerBox(height: 100),
      ],
    ),
  );
}
