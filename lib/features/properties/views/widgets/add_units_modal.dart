import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/oasis_currency.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_sheet.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../fix/controllers/fix_controller.dart';
import '../../../fix/models/fix_models.dart';
import '../../../fix/views/unit_recommendations_sheet.dart';
import '../../controllers/landlord_controller.dart';
import '../../models/property_model.dart';
import '../../../../core/utils/oasis_input_formatters.dart';

/// What the units sheet hands back.
///
/// More than the units themselves, because the short-let flow continues
/// straight into a listing per unit and the price is already known: the host
/// typed it here, per night. Carrying it forward is the difference between
/// being asked once and being asked twice for the same number.
class AddUnitsResult {
  final List<UnitModel> units;

  /// Nightly price by unit id, for units whose rent was quoted per night.
  /// Empty for a yearly-rent property, where no such number was asked for.
  final Map<String, String> nightlyPrices;

  const AddUnitsResult({required this.units, this.nightlyPrices = const {}});
}

class AddUnitsModal extends StatefulWidget {
  final PropertyModel property;

  /// What the property is being let for. Decides which rent intervals are
  /// offered and how the sheet describes what happens next.
  final PropertyPurpose purpose;

  const AddUnitsModal({
    super.key,
    required this.property,
    this.purpose = PropertyPurpose.yearlyRent,
  });

  /// Opens the units sheet for [property], resolving to the units created.
  ///
  /// Shared so the two ways in (adding a property, and adding units to one
  /// that already exists) present it identically.
  ///
  /// Null when the landlord closed it without saving. The add-property flow
  /// uses that to decide whether asking about existing tenants makes any
  /// sense: there is nobody to move into a property with no units.
  static Future<AddUnitsResult?> open(
    BuildContext context,
    PropertyModel property, {
    PropertyPurpose purpose = PropertyPurpose.yearlyRent,
  }) => showModalBottomSheet<AddUnitsResult>(
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
        height: MediaQuery.sizeOf(sheetContext).height * 0.9,
      ),
      child: AddUnitsModal(property: property, purpose: purpose),
    ),
  );

  @override
  State<AddUnitsModal> createState() => _AddUnitsModalState();
}

class _AddUnitsModalState extends State<AddUnitsModal> {
  /// The rows on screen. Seeded in [initState] rather than inline, because
  /// the first row's rent interval depends on what the property is for.
  final List<_UnitDraft> _drafts = [];

  final _picker = ImagePicker();

  bool _isSubmitting = false;

  /// What the sheet is doing while it works, e.g. "Uploading Unit A1's
  /// video". Media upload runs unit by unit after the batch lands, and on a
  /// Nigerian connection a 50MB clip is not a spinner's worth of waiting:
  /// silence here reads as the app having hung.
  String? _progressLabel;

  /// Optional artisans to recommend, applied to every unit added here.
  ///
  /// Property-wide rather than per unit because that is how a landlord
  /// actually works: one plumber covers the whole block, not flat A1 alone.
  /// The backend keys recommendations on the unit, so these are posted once
  /// per created unit after the batch lands: there is no unit id to attach
  /// them to before then.
  final Map<String, ArtisanProfile> _recommended = {};
  final Map<String, String> _recommendedLabels = {};

  @override
  void initState() {
    super.initState();
    _drafts.add(_UnitDraft('A1', interval: _defaultInterval));
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  /// The interval a fresh row starts on: nightly for a short let, yearly for
  /// a tenancy. Whichever the landlord is most likely to be thinking in.
  RentInterval get _defaultInterval =>
      RentInterval.forPurpose(widget.purpose).first;

  void _addRow() => setState(
    () => _drafts.add(
      _UnitDraft('A${_drafts.length + 1}', interval: _defaultInterval),
    ),
  );

  Future<void> _addRecommendation() async {
    final picked = await pickRecommendedArtisan(
      context,
      taken: _recommended.keys.toSet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _recommended[picked.category.value] = picked.artisan;
      _recommendedLabels[picked.category.value] = picked.category.label;
    });
  }

  // ------------------------------------------------------------------ media

  Future<void> _addPhotos(_UnitDraft draft) async {
    final remaining = PropertyMediaLimits.maxUnitPhotos - draft.photos.length;
    if (remaining <= 0) {
      OasisToast.error(
        context,
        'That unit already has the maximum of '
        '${PropertyMediaLimits.maxUnitPhotos} photos.',
      );
      return;
    }

    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked.isEmpty || !mounted) return;

      if (picked.length > remaining) {
        OasisToast.error(
          context,
          'You can add $remaining more '
          '${remaining == 1 ? 'photo' : 'photos'} to that unit.',
        );
        return;
      }

      // The documented 5MB cap is enforced here rather than after a failed
      // upload: on a slow connection the round-trip to be told no can take
      // longer than picking the file did.
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
      setState(() => draft.photos.addAll(files));
    } catch (error) {
      if (mounted) OasisToast.error(context, 'Unable to select photos.');
    }
  }

  Future<void> _addTourVideo(_UnitDraft draft) async {
    try {
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
      setState(() => draft.tourVideo = file);
    } catch (error) {
      if (mounted) OasisToast.error(context, 'Unable to select that video.');
    }
  }

  // ----------------------------------------------------------------- saving

  /// What is stopping the batch from being saved, or null when it is ready.
  ///
  /// Returned as a sentence rather than a bool so the footer can say which
  /// unit is short of what. A landlord adding eight flats should not have to
  /// scroll looking for the one the app is unhappy about.
  String? get _problem {
    for (final (index, draft) in _drafts.indexed) {
      final name = draft.unitNumber.text.trim();
      final label = name.isEmpty ? 'Unit ${index + 1}' : 'Unit $name';
      if (name.isEmpty) return 'Give $label a number.';
      if (draft.annualRent == null) {
        return 'Enter a valid price for $label.';
      }
      // Photos of the flat itself, and required rather than encouraged. A
      // listing whose only pictures are of the building tells a tenant
      // nothing about the room they would live in, and every unit that went
      // up without them had to be chased for them afterwards: by which
      // point it had already been passed over by everyone browsing.
      if (draft.photos.length < PropertyMediaLimits.minUnitPhotos) {
        final need = PropertyMediaLimits.minUnitPhotos - draft.photos.length;
        return draft.photos.isEmpty
            ? 'Add at least ${PropertyMediaLimits.minUnitPhotos} photos of '
                  '$label. Every unit needs its own.'
            : '$need more ${need == 1 ? 'photo' : 'photos'} needed for '
                  '$label.';
      }
      // The other hard media rule. A walkthrough is what lets a tenant apply
      // for somewhere they have not stood in, which is the whole promise of
      // renting through the app rather than through an agent at the gate.
      if (draft.tourVideo == null) {
        return 'Add a tour video for $label. Every unit needs one.';
      }
    }
    final numbers = _drafts
        .map((draft) => draft.unitNumber.text.trim().toLowerCase())
        .toList();
    if (numbers.toSet().length != numbers.length) {
      return 'Each unit number must be unique.';
    }
    return null;
  }

  /// Uploads the photos and video collected for each created unit.
  ///
  /// Runs after the batch, because media is keyed on a unit id that does not
  /// exist until then. Failures are counted, not thrown: the units are real
  /// and saved by this point, and losing them over a video that can be
  /// re-attached from the unit itself would be the worse outcome.
  Future<int> _uploadMedia(List<UnitModel> created) async {
    final controller = context.read<LandlordController>();
    var failures = 0;

    for (final unit in created) {
      final draft = _draftFor(unit);
      if (draft == null) continue;

      if (draft.photos.isNotEmpty) {
        if (mounted) {
          setState(
            () => _progressLabel = 'Uploading Unit ${unit.unitNumber} photos…',
          );
        }
        final ok = await controller.uploadUnitPhotos(
          unitId: unit.id,
          photos: draft.photos,
          propertyId: widget.property.id,
        );
        if (!ok) failures++;
      }

      final video = draft.tourVideo;
      if (video != null) {
        if (mounted) {
          setState(
            () => _progressLabel =
                'Uploading Unit ${unit.unitNumber} tour video…',
          );
        }
        final ok = await controller.uploadUnitVideo(
          unitId: unit.id,
          video: video,
          propertyId: widget.property.id,
        );
        if (!ok) failures++;
      }
    }
    return failures;
  }

  /// Nightly price per created unit, for the rows quoted by the night.
  ///
  /// Feeds the short-let listing step that follows, so the host is asked for
  /// their nightly rate once rather than once per screen.
  Map<String, String> _nightlyPricesFor(List<UnitModel> created) {
    final prices = <String, String>{};
    for (final unit in created) {
      final price = _draftFor(unit)?.nightlyPrice;
      if (price != null) prices[unit.id] = price;
    }
    return prices;
  }

  /// Matches a created unit back to the row it came from.
  ///
  /// By unit number rather than list position: the backend is free to return
  /// the batch in its own order, and attaching one flat's walkthrough to
  /// another is the kind of mistake nobody would spot until a tenant did.
  _UnitDraft? _draftFor(UnitModel unit) {
    final target = unit.unitNumber.trim().toLowerCase();
    for (final draft in _drafts) {
      if (draft.unitNumber.text.trim().toLowerCase() == target) return draft;
    }
    return null;
  }

  /// Saves the chosen recommendations against every unit just created.
  ///
  /// Failures here are reported but never turn the whole flow into an error:
  /// the units exist, which was the point of the sheet, and a recommendation
  /// is something the landlord can set again from the unit itself.
  Future<int> _applyRecommendations(List<UnitModel> units) async {
    if (_recommended.isEmpty) return 0;
    final controller = context.read<FixController>();

    var failures = 0;
    for (final unit in units) {
      for (final entry in _recommended.entries) {
        final saved = await controller.recommendArtisan(
          unitId: unit.id,
          category: entry.key,
          artisanId: entry.value.id,
        );
        if (!saved) failures++;
      }
    }
    return failures;
  }

  Future<void> _submit() async {
    final problem = _problem;
    if (problem != null) {
      OasisToast.error(context, problem);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _progressLabel = 'Saving units…';
    });

    final created = await context.read<LandlordController>().createUnitsBatch(
      propertyId: widget.property.id,
      units: _drafts
          .map(
            (draft) => {
              'unit_number': draft.unitNumber.text.trim(),
              'bedrooms': int.tryParse(draft.bedrooms.text.trim()) ?? 1,
              'bathrooms': int.tryParse(draft.bathrooms.text.trim()) ?? 1,
              // Always a year's rent, whatever the landlord typed it as.
              // The API stores one figure and the whole app reads it as
              // annual; converting here is what lets the sheet ask the
              // question in the period they actually think in.
              'rent_amount': draft.annualRent,
            },
          )
          .toList(),
    );
    if (!mounted) return;

    if (created == null) {
      setState(() {
        _isSubmitting = false;
        _progressLabel = null;
      });
      OasisToast.error(
        context,
        context.read<LandlordController>().errorMessage ??
            'Could not add units.',
      );
      return;
    }

    final mediaFailures = await _uploadMedia(created);
    if (!mounted) return;
    final recommendationFailures = await _applyRecommendations(created);
    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _progressLabel = null;
    });

    Navigator.pop(
      context,
      AddUnitsResult(units: created, nightlyPrices: _nightlyPricesFor(created)),
    );
    OasisToast.success(
      context,
      '${created.length} unit${created.length == 1 ? '' : 's'} added to '
      '${widget.property.name}.',
    );
    // Said separately, because the two failures have different fixes: media
    // is re-attached from the unit, a recommendation is re-picked.
    if (mediaFailures > 0) {
      OasisToast.error(
        context,
        'Some photos or videos did not upload. Open the unit to add them '
        'again. The units themselves are saved.',
      );
    } else if (recommendationFailures > 0) {
      OasisToast.error(
        context,
        'Some recommended artisans could not be saved. You can set them on '
        'each unit.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _problem == null;

    return OasisSheet(
      icon: Icons.meeting_room_outlined,
      title: widget.purpose.isShortLet ? 'Add the places' : 'Add units',
      subtitle: widget.purpose.isShortLet
          ? '${widget.property.name}. Every unit needs its own photos and '
                'tour video. A guest books one flat, not the building. You '
                'set the nightly price and house rules next.'
          : '${widget.property.name}. Every unit needs its own photos and '
                'tour video. A tenant applies for one flat, not the '
                'building.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The specific blocker, above the button rather than behind a tap
          // on it. A disabled button that will not say why is the thing this
          // sheet used to do.
          if (!ready && !_isSubmitting) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: AppTheme.warningColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _problem!,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.warningColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (_progressLabel != null) ...[
            Text(
              _progressLabel!,
              textAlign: TextAlign.center,
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
            const SizedBox(height: 10),
          ],
          OasisSheetButton(
            label:
                'Save ${_drafts.length} unit${_drafts.length == 1 ? '' : 's'}',
            icon: Icons.check_rounded,
            isLoading: _isSubmitting,
            onPressed: _isSubmitting || !ready ? null : _submit,
          ),
        ],
      ),
      children: [
        for (final (index, draft) in _drafts.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _UnitDraftCard(
              draft: draft,
              index: index,
              purpose: widget.purpose,
              enabled: !_isSubmitting,
              canRemove: _drafts.length > 1,
              onRemove: () => setState(() {
                final removed = _drafts.removeAt(index);
                removed.dispose();
              }),
              onAddPhotos: () => _addPhotos(draft),
              onRemovePhoto: (photoIndex) =>
                  setState(() => draft.photos.removeAt(photoIndex)),
              onAddVideo: () => _addTourVideo(draft),
              onChanged: () => setState(() {}),
            ),
          ),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isSubmitting ? null : _addRow,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add another unit'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.actionColor),
          ),
        ),
        const SizedBox(height: 8),

        _RecommendedArtisansSection(
          chosen: _recommended,
          labels: _recommendedLabels,
          onAdd: _isSubmitting ? null : _addRecommendation,
          onRemove: (category) => setState(() => _recommended.remove(category)),
        ),
      ],
    );
  }
}

/// One row's worth of state, including the media collected for it.
class _UnitDraft {
  final TextEditingController unitNumber;
  final bedrooms = TextEditingController(text: '1');
  final bathrooms = TextEditingController(text: '1');
  final rent = TextEditingController();

  /// What period [rent] is quoted for. The API only stores a year's rent, so
  /// this is what the typed figure is multiplied by on the way out: see
  /// [annualRent].
  RentInterval interval;

  /// Photos of this flat. Held on the device until the unit exists, because
  /// the upload endpoint is keyed on a unit id there is no way to know yet.
  final List<File> photos = [];

  /// The walkthrough. Required before the batch can be saved.
  File? tourVideo;

  _UnitDraft(String number, {this.interval = RentInterval.perYear})
    : unitNumber = TextEditingController(text: number);

  /// The typed figure as a year's rent, or null when it is not a number.
  ///
  /// This is the only rent that ever reaches the backend. A landlord who
  /// quotes ₦250,000 a month is storing ₦3,000,000 a year, and the sheet says
  /// so under the field rather than converting behind their back.
  String? get annualRent =>
      OasisCurrency.scale(rent.text.trim(), interval.periodsPerYear);

  /// The nightly price, for a host who quoted one. Null for every other
  /// interval: deriving a nightly rate from a yearly rent would be inventing
  /// a number the host never agreed to.
  String? get nightlyPrice => interval == RentInterval.perNight
      ? OasisCurrency.scale(rent.text.trim(), 1)
      : null;

  void dispose() {
    unitNumber.dispose();
    bedrooms.dispose();
    bathrooms.dispose();
    rent.dispose();
  }
}

class _UnitDraftCard extends StatelessWidget {
  final _UnitDraft draft;
  final int index;

  /// Decides which rent intervals this row offers.
  final PropertyPurpose purpose;

  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onAddPhotos;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onAddVideo;

  /// Rebuilds the sheet as the landlord types, so the footer's blocker line
  /// tracks what they have actually filled in.
  final VoidCallback onChanged;

  const _UnitDraftCard({
    required this.draft,
    required this.index,
    required this.purpose,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
    required this.onAddPhotos,
    required this.onRemovePhoto,
    required this.onAddVideo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasVideo = draft.tourVideo != null;
    final annualRent = draft.annualRent;
    final hasEnoughPhotos =
        draft.photos.length >= PropertyMediaLimits.minUnitPhotos;
    final label = draft.unitNumber.text.trim().isEmpty
        ? 'UNIT ${index + 1}'
        : 'UNIT ${draft.unitNumber.text.trim().toUpperCase()}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
              ),
              const Spacer(),
              if (canRemove)
                OasisPressable(
                  onTap: enabled ? onRemove : null,
                  pressedScale: 0.88,
                  child: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 20,
                    color: AppTheme.disputeColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: draft.unitNumber,
                  enabled: enabled,
                  onChanged: (_) => onChanged(),
                  style: AppTheme.cardTitle(context),
                  decoration: oasisInputDecoration(context, hint: 'Number'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.bedrooms,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  style: AppTheme.cardTitle(context),
                  decoration: oasisInputDecoration(context, hint: 'Beds'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.bathrooms,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  style: AppTheme.cardTitle(context),
                  decoration: oasisInputDecoration(context, hint: 'Baths'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: draft.rent,
                  enabled: enabled,
                  // Grouped as it is typed. This is the field that decides
                  // what a flat costs for a year, on a form where a landlord
                  // fills in six of them in a row, and an extra zero in an
                  // ungrouped seven-digit number is invisible.
                  keyboardType: TextInputType.number,
                  inputFormatters: const [OasisThousandsFormatter()],
                  onChanged: (_) => onChanged(),
                  style: AppTheme.cardTitle(context),
                  decoration: oasisInputDecoration(
                    context,
                    hint: 'Price (₦)',
                    prefixIcon: Icons.payments_outlined,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The period the figure is quoted for. Beside the amount rather
              // than under it, because the two are one answer: a rent read
              // without its interval is off by a factor of twelve.
              Expanded(
                flex: 4,
                child: _IntervalPicker(
                  value: draft.interval,
                  options: RentInterval.forPurpose(purpose),
                  enabled: enabled,
                  onChanged: (interval) {
                    draft.interval = interval;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          // Says what will actually be stored. Oasis keeps one rent per unit
          // , a year's, and a landlord who typed a monthly figure is owed
          // the multiplication in front of them rather than a surprise on
          // the listing.
          if (annualRent != null && draft.interval != RentInterval.perYear) ...[
            const SizedBox(height: 6),
            Text(
              'Saved as ${OasisCurrency.perYear(annualRent)}'
              '${draft.interval == RentInterval.perNight ? ' if let every night' : ''}.',
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Photos of this flat, and required. They were optional, and
          // optional meant most units went up with pictures of a gate and
          // nothing of the rooms, which is the one thing somebody deciding
          // where to live is actually looking for.
          Row(
            children: [
              Expanded(
                child: Text(
                  'PHOTOS OF THIS UNIT',
                  style: AppTheme.labelText(
                    context,
                  ).copyWith(letterSpacing: 0.9),
                ),
              ),
              Text(
                hasEnoughPhotos ? '${draft.photos.length} ADDED' : 'REQUIRED',
                style: AppTheme.labelText(
                  context,
                  color: hasEnoughPhotos
                      ? AppTheme.successColor
                      : AppTheme.actionColor,
                ).copyWith(fontSize: 10, letterSpacing: 0.6),
              ),
            ],
          ),
          if (!hasEnoughPhotos) ...[
            const SizedBox(height: 4),
            Text(
              draft.photos.isEmpty
                  ? 'At least ${PropertyMediaLimits.minUnitPhotos} photos of '
                        'this flat, enough to tell a studio from a '
                        'two-bedroom.'
                  : 'One more photo needed.',
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (draft.photos.isNotEmpty) ...[
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: draft.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, photoIndex) => Stack(
                  children: [
                    ClipRRect(
                      borderRadius: AppTheme.cornerSm,
                      child: Image.file(
                        draft.photos[photoIndex],
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: OasisPressable(
                        onTap: enabled ? () => onRemovePhoto(photoIndex) : null,
                        pressedScale: 0.88,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          OasisSheetChipButton(
            icon: Icons.add_photo_alternate_outlined,
            label: draft.photos.isEmpty ? 'Add photos' : 'Add more photos',
            onTap: enabled ? onAddPhotos : () {},
          ),
          const SizedBox(height: 14),

          _TourVideoTile(
            file: draft.tourVideo,
            enabled: enabled,
            onTap: onAddVideo,
          ),
          if (!hasVideo) ...[
            const SizedBox(height: 6),
            Text(
              'MP4 or MOV up to 50MB. Walk through the flat once. This is '
              'what a tenant watches before applying.',
              style: AppTheme.labelText(
                context,
                color: AppTheme.secondaryTextColor(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which period a unit's price is quoted for.
///
/// A dropdown rather than chips: there are only two or three options, but
/// they sit beside the amount on a row that already carries a text field, and
/// three chips there would either wrap or squeeze the number they belong to.
class _IntervalPicker extends StatelessWidget {
  final RentInterval value;
  final List<RentInterval> options;
  final bool enabled;
  final ValueChanged<RentInterval> onChanged;

  const _IntervalPicker({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<RentInterval>(
    initialValue: options.contains(value) ? value : options.first,
    isExpanded: true,
    borderRadius: AppTheme.cornerMd,
    style: AppTheme.cardTitle(context),
    decoration: oasisInputDecoration(context),
    items: [
      for (final option in options)
        DropdownMenuItem(
          value: option,
          child: Text(option.suffix, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: enabled
        ? (interval) {
            if (interval != null) onChanged(interval);
          }
        : null,
  );
}

/// The required walkthrough for one unit, in the two states it has.
class _TourVideoTile extends StatelessWidget {
  final File? file;
  final bool enabled;
  final VoidCallback onTap;

  const _TourVideoTile({
    required this.file,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final attached = file != null;
    // Terracotta while it is outstanding rather than red: it is a step not
    // yet done, not a mistake the landlord has made.
    final accent = attached ? AppTheme.successColor : AppTheme.actionColor;

    return OasisPressable(
      onTap: enabled ? onTap : null,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: AppTheme.cornerSm,
              ),
              child: Icon(
                attached ? Icons.check_rounded : Icons.movie_outlined,
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
                    attached ? 'Tour video attached' : 'Add tour video',
                    style: AppTheme.cardTitle(
                      context,
                    ).copyWith(fontSize: AppTheme.textSm),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attached
                        ? file!.path.split('/').last
                        : 'Required for every unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              attached ? 'REPLACE' : 'ATTACH',
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

/// The optional "who do you trust here" step in the add-units flow.
///
/// Optional on purpose: a landlord adding units at midnight should not be made
/// to pick a plumber before they can save. What it buys is a tenant who, when
/// something breaks, sees a name their landlord already vouched for instead of
/// guessing from a list of strangers.
class _RecommendedArtisansSection extends StatelessWidget {
  final Map<String, ArtisanProfile> chosen;
  final Map<String, String> labels;
  final VoidCallback? onAdd;
  final ValueChanged<String> onRemove;

  const _RecommendedArtisansSection({
    required this.chosen,
    required this.labels,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.subtleSurfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'RECOMMENDED ARTISANS',
                style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
              ),
            ),
            Text(
              chosen.isEmpty ? 'OPTIONAL' : '${chosen.length} ADDED',
              style: AppTheme.labelText(
                context,
                color: chosen.isEmpty
                    ? AppTheme.mutedTextColor(context)
                    : AppTheme.successColor,
              ).copyWith(fontSize: 10, letterSpacing: 0.6),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Artisans already on Oasis. Your tenants see them marked as '
          'recommended by you, on every unit added here.',
          style: AppTheme.bodyText(context),
        ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in chosen.entries)
                _ChosenChip(
                  label:
                      '${labels[entry.key] ?? ArtisanCategory.prettify(entry.key)}'
                      ' · ${entry.value.displayName}',
                  onRemove: () => onRemove(entry.key),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        OasisPressable(
          onTap: onAdd,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.actionColor.withValues(alpha: 0.07),
              borderRadius: AppTheme.cornerMd,
              border: Border.all(
                color: AppTheme.actionColor.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_search_outlined,
                  size: 17,
                  color: AppTheme.actionColor,
                ),
                const SizedBox(width: 8),
                Text(
                  chosen.isEmpty
                      ? 'Add a recommended artisan'
                      : 'Add another trade',
                  style: AppTheme.cardTitle(
                    context,
                    color: AppTheme.actionColor,
                  ).copyWith(fontSize: AppTheme.textSm),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChosenChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ChosenChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
    decoration: BoxDecoration(
      color: AppTheme.successSurface(context),
      borderRadius: AppTheme.cornerSm,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTheme.labelText(
            context,
            color: AppTheme.readingTextColor(context),
          ).copyWith(fontSize: AppTheme.textSm, letterSpacing: 0),
        ),
        const SizedBox(width: 6),
        OasisPressable(
          onTap: onRemove,
          pressedScale: 0.88,
          child: Icon(
            Icons.close_rounded,
            size: 15,
            color: AppTheme.disputeColor,
          ),
        ),
      ],
    ),
  );
}
