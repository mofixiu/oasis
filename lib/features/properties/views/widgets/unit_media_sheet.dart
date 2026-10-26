import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/app_variant.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/oasis_network_image.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_sheet.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../../core/widgets/oasis_video_player.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';
import '../../../../core/widgets/oasis_busy.dart';

/// Manages one unit's photos and its tour video, after the unit exists.
///
/// The add-units sheet collects both up front, but three kinds of unit end up
/// here anyway: ones created before the walkthrough was required, ones whose
/// upload failed on a bad connection, and ones the landlord has since
/// redecorated. Without this the only way to fix any of them would be to
/// delete the flat and add it again.
Future<void> openUnitMediaSheet(
  BuildContext context, {
  required UnitModel unit,

  /// Refreshes that property's detail after a change. Null where there is
  /// none on screen to refresh, as on the v2 host's My places.
  String? propertyId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  // Measured against the sheet's own context, not the caller's. Reading
  // MediaQuery off the opening screen registers *that screen* as a
  // dependent, so it rebuilds every time the keyboard moves, and, worse,
  // it is an ancestor lookup on a context that may already be on its way
  // out of the tree by the time a long flow reaches this step.
  builder: (sheetContext) => ConstrainedBox(
    constraints: BoxConstraints.tightFor(
      height: MediaQuery.sizeOf(sheetContext).height * 0.85,
    ),
    child: _UnitMediaSheet(unit: unit, propertyId: propertyId),
  ),
);

class _UnitMediaSheet extends StatefulWidget {
  final UnitModel unit;
  final String? propertyId;

  const _UnitMediaSheet({required this.unit, this.propertyId});

  @override
  State<_UnitMediaSheet> createState() => _UnitMediaSheetState();
}

class _UnitMediaSheetState extends State<_UnitMediaSheet> {
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LandlordController>().loadUnitMedia(widget.unit.id);
    });
  }

  /// The video URL to render.
  ///
  /// The controller's copy wins when there is one, because it is what the
  /// last upload in this session returned; the unit's own field is what came
  /// with the property payload and may predate that upload.
  String? get _videoUrl =>
      context.watch<LandlordController>().unitVideoUrlFor(widget.unit.id) ??
      widget.unit.videoUrl;

  Future<void> _addPhotos(int currentCount) async {
    final remaining = PropertyMediaLimits.maxUnitPhotos - currentCount;
    if (remaining <= 0) {
      OasisToast.error(
        context,
        'This unit already has the maximum of '
        '${PropertyMediaLimits.maxUnitPhotos} photos.',
      );
      return;
    }

    final picked = await _picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty || !mounted) return;

    if (picked.length > remaining) {
      OasisToast.error(
        context,
        'You can add $remaining more ${remaining == 1 ? 'photo' : 'photos'}.',
      );
      return;
    }

    final files = <File>[];
    for (final image in picked) {
      final file = File(image.path);
      if (await file.length() > PropertyMediaLimits.maxPhotoBytes) {
        if (!mounted) return;
        OasisToast.error(
          context,
          '"${image.name}" is larger than 5MB. Choose a smaller image.',
        );
        return;
      }
      files.add(file);
    }
    if (!mounted) return;

    final controller = context.read<LandlordController>();
    final ok = await controller.uploadUnitPhotos(
      unitId: widget.unit.id,
      photos: files,
      propertyId: widget.propertyId,
    );
    if (!mounted) return;
    if (ok) {
      OasisToast.success(
        context,
        files.length == 1 ? 'Photo added.' : '${files.length} photos added.',
      );
    } else if (controller.errorMessage != null) {
      OasisToast.error(context, controller.errorMessage!);
    }
  }

  Future<void> _deletePhoto(PropertyPhoto photo) async {
    final controller = context.read<LandlordController>();
    final ok = await controller.deleteUnitPhoto(
      unitId: widget.unit.id,
      photoId: photo.id,
      propertyId: widget.propertyId,
    );
    if (!mounted) return;
    if (ok) {
      OasisToast.success(context, 'Photo removed.');
    } else if (controller.errorMessage != null) {
      OasisToast.error(context, controller.errorMessage!);
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
      OasisToast.error(
        context,
        'That video is larger than 50MB. Choose a shorter clip.',
      );
      return;
    }
    if (!mounted) return;

    final controller = context.read<LandlordController>();
    final ok = await controller.uploadUnitVideo(
      unitId: widget.unit.id,
      video: file,
      propertyId: widget.propertyId,
    );
    if (!mounted) return;
    if (ok) {
      OasisToast.success(
        context,
        replacing ? 'Tour video replaced.' : 'Tour video uploaded.',
      );
    } else if (controller.errorMessage != null) {
      OasisToast.error(context, controller.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LandlordController>();
    final photos =
        controller.unitPhotos[widget.unit.id] ?? const <PropertyPhoto>[];
    final videoUrl = _videoUrl;
    final busy = controller.isMediaBusy;

    // v2 hosts list shortlets for guests: photos are what a guest books on,
    // so they come first, and the walkthrough is an extra rather than a gap.
    final videoSection = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              'TOUR VIDEO',
              style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
            ),
          ),
          Text(
            videoUrl != null
                ? 'ADDED'
                : isOasisV2
                ? 'OPTIONAL'
                : 'MISSING',
            style: AppTheme.labelText(
              context,
              color: videoUrl != null
                  ? AppTheme.successColor
                  : isOasisV2
                  ? AppTheme.mutedTextColor(context)
                  : AppTheme.actionColor,
            ).copyWith(fontSize: 10, letterSpacing: 0.6),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (videoUrl == null)
        _EmptyMediaCard(
          icon: Icons.videocam_outlined,
          message: isOasisV2
              ? 'A short walkthrough helps guests picture the stay. Add one '
                    'whenever you like.'
              : 'This unit has no walkthrough. Tenants browsing the '
                    'marketplace see a still photo and nothing else, which is '
                    'the single biggest reason a listing gets skipped.',
          actionLabel: 'Upload tour video',
          onAction: busy ? null : () => _uploadVideo(replacing: false),
        )
      else
        Column(
          children: [
            OasisVideoPlayer(url: videoUrl),
            const SizedBox(height: 10),
            OasisSheetChipButton(
              icon: Icons.swap_horiz_rounded,
              label: 'Replace video',
              onTap: busy ? () {} : () => _uploadVideo(replacing: true),
            ),
          ],
        ),
    ];

    final photoSection = <Widget>[
      Row(
        children: [
          Expanded(
            child: Text(
              'PHOTOS',
              style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
            ),
          ),
          Text(
            '${photos.length}/${PropertyMediaLimits.maxUnitPhotos}',
            style: AppTheme.labelText(
              context,
              color: AppTheme.mutedTextColor(context),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (photos.isEmpty)
        _EmptyMediaCard(
          icon: Icons.photo_library_outlined,
          message: isOasisV2
              ? 'No photos yet. The first one is the cover guests see when '
                    'they browse.'
              : 'No photos of this unit yet. The first one becomes the image '
                    'tenants see in the marketplace.',
          actionLabel: 'Add photos',
          onAction: busy ? null : () => _addPhotos(0),
        )
      else ...[
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
            onDelete: () => _deletePhoto(photos[index]),
          ),
        ),
        const SizedBox(height: 10),
        if (photos.length < PropertyMediaLimits.maxUnitPhotos)
          OasisSheetChipButton(
            icon: Icons.add_photo_alternate_outlined,
            label: 'Add more photos',
            onTap: busy ? () {} : () => _addPhotos(photos.length),
          ),
      ],
    ];

    return OasisSheet(
      icon: Icons.perm_media_outlined,
      title: isOasisV2
          ? 'Photos of your place'
          : 'Unit ${widget.unit.unitNumber} media',
      subtitle: isOasisV2
          ? 'What guests see before they book. Add a photo of every room; '
                'the first is your cover.'
          : 'What a tenant sees before they apply. The tour video is the one '
                'that decides it. Nobody applies for a flat they cannot see '
                'inside.',
      children: [
        ...(isOasisV2 ? photoSection : videoSection),
        const SizedBox(height: 22),
        ...(isOasisV2 ? videoSection : photoSection),
        if (busy) ...[
          const SizedBox(height: 16),
          const OasisBusyLine(label: 'Uploading'),
        ],
      ],
    );
  }
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
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: AppTheme.cornerSm,
    child: Stack(
      fit: StackFit.expand,
      children: [
        OasisNetworkImage(
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
                borderRadius: AppTheme.cornerSm,
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
          child: OasisPressable(
            onTap: enabled ? onDelete : null,
            pressedScale: 0.88,
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
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Column(
      children: [
        Icon(icon, size: 32, color: AppTheme.mutedTextColor(context)),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTheme.bodyText(context),
        ),
        const SizedBox(height: 14),
        OasisSheetChipButton(
          icon: Icons.add_rounded,
          label: actionLabel,
          onTap: onAction ?? () {},
        ),
      ],
    ),
  );
}
