import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/app_variant.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nigeria_locations.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/utils/oasis_input_formatters.dart';
import '../../../core/widgets/oasis_place_picker.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../../properties/models/property_model.dart';
import '../../properties/services/geocoding_service.dart';
import '../../properties/views/widgets/property_location_picker.dart';
import '../../properties/views/widgets/unit_media_sheet.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_details.dart';
import '../models/shortlet_models.dart';

/// Lists a unit for nightly stays, or edits the listing it already has.
///
/// A full-screen flow, one group of questions per step, rather than the
/// single long sheet it used to be. The sheet asked a dozen questions in one
/// scroll, ended at a photo manager with no way forward, and left the host
/// guessing what was still missing. Steps say what they want and refuse to
/// move on until they have it.
///
/// Returns true when something was saved. A create `POST`s to the
/// collection, an edit `PATCH`es the listing's own path. The backend refuses
/// a second create for the same unit with `409 LISTING_EXISTS`; the client
/// check below stays as the first line because it is faster and can explain
/// itself.
Future<bool> openCreateShortLetSheet(
  BuildContext context, {
  ShortLetListing? existing,

  /// Pre-selects the unit being listed, for the add-property flow that walks
  /// a host straight from creating a place into listing it.
  PropertyModel? initialProperty,
  UnitModel? initialUnit,

  /// The nightly price the host already typed on the unit, carried through
  /// so the same number is not asked for twice.
  String? initialNightlyPrice,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ListPlaceFlow(
        existing: existing,
        initialProperty: initialProperty,
        initialUnit: initialUnit,
        initialNightlyPrice: initialNightlyPrice,
      ),
    ),
  );
  return saved ?? false;
}

enum _Step { place, space, bestFor, describe, media, pricing, rules, review }

extension on _Step {
  String get title => switch (this) {
    _Step.place => 'Where is your place?',
    _Step.space => 'Tell us about the space',
    _Step.bestFor => 'What is it best for?',
    _Step.describe => 'Describe your place',
    _Step.media => 'Photos and a tour video',
    _Step.pricing => 'Price and booking',
    _Step.rules => 'House rules and arrival',
    _Step.review => 'Review and publish',
  };

  String get subtitle => switch (this) {
    _Step.place => 'Guests only see the exact address once they have paid.',
    _Step.space => 'What it is, how many it sleeps and what it comes with.',
    _Step.bestFor =>
      'Pick every occasion it suits. Guests browse by these, so a birthday '
          'planner finds your place.',
    _Step.describe => 'The first thing guests read on your listing.',
    _Step.media =>
      'At least 3 photos and a short walkthrough video. Listings with a '
          'tour get booked with more confidence.',
    _Step.pricing => 'You approve every booking before anyone pays.',
    _Step.rules => 'Set expectations so there are no surprises at check-in.',
    _Step.review => 'Check everything before guests can see it.',
  };
}

class _ListPlaceFlow extends StatefulWidget {
  final ShortLetListing? existing;
  final PropertyModel? initialProperty;
  final UnitModel? initialUnit;
  final String? initialNightlyPrice;

  const _ListPlaceFlow({
    this.existing,
    this.initialProperty,
    this.initialUnit,
    this.initialNightlyPrice,
  });

  @override
  State<_ListPlaceFlow> createState() => _ListPlaceFlowState();
}

class _ListPlaceFlowState extends State<_ListPlaceFlow> {
  final _priceController = TextEditingController();

  /// The refundable deposit. Blank means none, which is why it is a text
  /// field rather than a switch plus an amount.
  final _cautionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _rulesController = TextEditingController();
  final _checkInController = TextEditingController();

  PropertyModel? _property;
  UnitModel? _unit;
  int _minimumNights = 1;
  int _maximumGuests = 2;
  ShortLetCancellationPolicy _cancellationPolicy =
      ShortLetCancellationPolicy.flexible;
  DateTimeRange? _window;
  bool _isActive = true;
  ShortLetDetails _details = const ShortLetDetails();

  /// v2 only: the place is not one of the host's units yet, so the property
  /// and unit are made in the same request as the listing
  /// (`POST /host/listings/`).
  bool _newPlace = false;
  final _placeNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _unitNumberController = TextEditingController();
  String _state = '';
  String _city = '';
  LatLng? _pin;
  int _bedrooms = 1;
  int _bathrooms = 1;

  /// Which of the address boxes the pin filled in, so dropping the pin
  /// again updates them, but never overwrites what the host typed.
  bool _addressFromPin = false;
  bool _cityFromPin = false;
  bool _stateFromPin = false;

  /// Media picked for a listing that does not exist yet. Uploaded to the
  /// unit as soon as the create succeeds. An edit manages the unit's media
  /// directly instead, because the unit is already there.
  final List<File> _photos = [];
  File? _video;
  final _imagePicker = ImagePicker();

  /// What publishing is doing right now, shown over the review step. Null
  /// when idle.
  String? _publishing;

  int _stepIndex = 0;

  bool get _isEditing => widget.existing != null;

  bool get _canAddNewPlace =>
      isOasisV2 && !_isEditing && widget.initialUnit == null;

  /// Editing skips the place step: a listing is keyed to its unit, and
  /// moving it would make a second listing.
  List<_Step> get _steps => [
    if (!_isEditing) _Step.place,
    _Step.space,
    _Step.bestFor,
    _Step.describe,
    _Step.media,
    _Step.pricing,
    _Step.rules,
    _Step.review,
  ];

  _Step get _step => _steps[_stepIndex];

  static const int _minPhotos = 3;
  static const int _minDescriptionLength = 30;

  /// The backend enforces the same ceiling: `backend_change_spec_v11.md` §2.
  static const int _maxDescriptionLength = 1000;

  @override
  void initState() {
    super.initState();
    _property = widget.initialProperty;
    _unit = widget.initialUnit;
    _newPlace = _canAddNewPlace;
    final seededPrice = widget.initialNightlyPrice;
    if (seededPrice != null) {
      _priceController.text = OasisThousandsFormatter.groupAmount(seededPrice);
    }
    final existing = widget.existing;
    if (existing != null) {
      _priceController.text = OasisThousandsFormatter.groupAmount(
        existing.nightlyPrice,
      );
      if (existing.hasCautionFee) {
        _cautionController.text = OasisThousandsFormatter.groupAmount(
          existing.cautionFee,
        );
      }
      _descriptionController.text = existing.description;
      _rulesController.text = existing.houseRules;
      _checkInController.text = existing.checkInNotes;
      _minimumNights = existing.minimumNights;
      _maximumGuests = existing.maximumGuests;
      _cancellationPolicy = existing.cancellationPolicy;
      _isActive = existing.isActive;
      _details = existing.details;
      final from = DateTime.tryParse(existing.availableFrom ?? '');
      final to = DateTime.tryParse(existing.availableTo ?? '');
      if (from != null && to != null && to.isAfter(from)) {
        _window = DateTimeRange(start: from, end: to);
      }
    }
    // The unit picker needs the landlord's properties, and the existing
    // listings are how this flow knows a unit is already let by the night.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final landlord = context.read<LandlordController>();
      if (landlord.properties.isEmpty) landlord.loadLandlordProperties();
      final shortLets = context.read<ShortLetController>();
      if (!shortLets.hasLoaded(ShortLetController.kListingsKey)) {
        shortLets.loadLandlordListings();
      }
      if (existing != null && existing.unitId.isNotEmpty) {
        landlord.loadUnitMedia(existing.unitId);
      }
    });
  }

  @override
  void dispose() {
    _priceController.dispose();
    _cautionController.dispose();
    _descriptionController.dispose();
    _rulesController.dispose();
    _checkInController.dispose();
    _placeNameController.dispose();
    _addressController.dispose();
    _unitNumberController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- derived

  /// Digits only: the API takes a decimal string and the host types naira.
  String get _rawPrice =>
      _priceController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasPrice => _rawPrice.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  String get _rawCaution =>
      _cautionController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasCaution => _rawCaution.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  String get _description => _descriptionController.text.trim();

  String? get _unitId => _isEditing ? widget.existing!.unitId : _unit?.id;

  /// The listing this unit already has, when the host has picked one that is
  /// let by the night. Null while editing: editing *is* that listing.
  ShortLetListing? get _duplicateListing {
    if (_isEditing || _newPlace) return null;
    final unitId = _unit?.id;
    if (unitId == null) return null;
    return context.read<ShortLetController>().listingForUnit(unitId);
  }

  /// The edited unit's photo count and tour video, from the media manager
  /// when it has loaded and from the listing until then.
  int get _existingPhotoCount {
    final unitId = widget.existing?.unitId ?? '';
    final loaded = context.read<LandlordController>().unitPhotos[unitId];
    return loaded?.length ?? widget.existing?.photoUrls.length ?? 0;
  }

  bool get _existingHasVideo {
    final unitId = widget.existing?.unitId ?? '';
    final url =
        context.read<LandlordController>().unitVideoUrlFor(unitId) ??
        widget.existing?.videoUrl;
    return url != null && url.isNotEmpty;
  }

  /// What a minimum-length stay would cost a guest, deposit included.
  String get _quoteLine {
    final nights = int.parse(_rawPrice) * _minimumNights;
    final stay = OasisCurrency.format('$nights.00');
    if (!_hasCaution) {
      return 'A $_minimumNights-night stay would come to $stay before fees.';
    }
    final deposit = OasisCurrency.format('$_rawCaution.00');
    final total = OasisCurrency.format('${nights + int.parse(_rawCaution)}.00');
    return 'A $_minimumNights-night stay would come to $stay, plus a '
        '$deposit refundable deposit. $total to pay before fees.';
  }

  /// The first thing [step] is still missing, or null when it is complete.
  String? _problemWith(_Step step) {
    switch (step) {
      case _Step.place:
        if (_newPlace) {
          if (_placeNameController.text.trim().isEmpty) {
            return 'Give your place a name.';
          }
          if (_addressController.text.trim().isEmpty) {
            return 'Add the street address.';
          }
          if (_state.isEmpty) return 'Pick the state.';
          if (_city.isEmpty) return 'Pick the city or area.';
          if (_pin == null) {
            return 'Drop a pin on the map so guests can find it.';
          }
          return null;
        }
        if (_unitId == null || _unitId!.isEmpty) {
          return 'Pick the unit you want to let by the night.';
        }
        if (_duplicateListing case final duplicate?) {
          return '${duplicate.title} is already listed. Edit that listing '
              'instead.';
        }
        return null;
      case _Step.space:
        if (_details.placeType == null) return 'Pick the type of place.';
        if (_details.amenities.isEmpty) {
          return 'Pick at least one thing the place has.';
        }
        return null;
      case _Step.bestFor:
        if (_details.bestFor.isEmpty) {
          return 'Pick at least one occasion your place suits.';
        }
        return null;
      case _Step.describe:
        if (_description.length < _minDescriptionLength) {
          return 'Write at least $_minDescriptionLength characters so guests '
              'know what to expect.';
        }
        return null;
      case _Step.media:
        if (_isEditing) {
          if (_existingPhotoCount < _minPhotos) {
            return 'Add at least $_minPhotos photos.';
          }
          if (!_existingHasVideo) return 'Add a tour video of the place.';
          return null;
        }
        if (_photos.length < _minPhotos) {
          return 'Add at least $_minPhotos photos.';
        }
        if (_video == null) return 'Add a tour video of the place.';
        return null;
      case _Step.pricing:
        if (!_hasPrice) return 'Set a nightly price.';
        return null;
      case _Step.rules:
      case _Step.review:
        return null;
    }
  }

  // -------------------------------------------------------- navigation

  void _next() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_problemWith(_step) case final problem?) {
      OasisToast.error(context, problem);
      return;
    }
    if (_step == _Step.review) {
      _publish();
      return;
    }
    setState(() => _stepIndex++);
  }

  void _back() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_stepIndex == 0) {
      _confirmLeave();
      return;
    }
    setState(() => _stepIndex--);
  }

  void _jumpTo(_Step step) {
    final index = _steps.indexOf(step);
    if (index != -1) setState(() => _stepIndex = index);
  }

  /// Asked before throwing a half-filled listing away. A host who has typed
  /// an address and picked photos should not lose them to a stray tap.
  Future<void> _confirmLeave() async {
    if (_publishing != null) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_isEditing ? 'Discard changes?' : 'Leave without listing?'),
        content: Text(
          _isEditing
              ? 'Your changes to this listing will not be saved.'
              : 'What you have filled in so far will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _isEditing ? 'Discard' : 'Leave',
              style: AppTheme.cardTitle(
                dialogContext,
                color: AppTheme.disputeColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context, false);
  }

  // ----------------------------------------------------------- pickers

  Future<void> _pickWindow() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      initialDateRange: _window,
      helpText: 'When can guests book?',
      saveText: 'Done',
    );
    if (picked != null) setState(() => _window = picked);
  }

  Future<void> _pickTime({required bool checkIn}) async {
    final current = checkIn ? _details.checkInTime : _details.checkOutTime;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 12,
        minute: int.tryParse(parts.last) ?? 0,
      ),
      helpText: checkIn ? 'Check-in from' : 'Check-out by',
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      _details = checkIn
          ? _details.copyWith(checkInTime: value)
          : _details.copyWith(checkOutTime: value);
    });
  }

  String _formatTime(String value) {
    final parts = value.split(':');
    final time = DateTime(
      2000,
      1,
      1,
      int.tryParse(parts.first) ?? 0,
      int.tryParse(parts.last) ?? 0,
    );
    return DateFormat('h:mm a').format(time);
  }

  Future<void> _pickState() async {
    final picked = await openStatePicker(context, selected: _state);
    if (picked == null || !mounted) return;
    final cityStillValid =
        _city.isEmpty ||
        NigeriaLocations.canonicalCity(state: picked, city: _city) != null;
    setState(() {
      _state = picked;
      _stateFromPin = false;
      if (!cityStillValid) {
        _city = '';
        _cityFromPin = false;
      }
    });
  }

  Future<void> _pickCity() async {
    final picked = await openCityPicker(
      context,
      state: _state,
      selected: _city,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _city = picked;
      _cityFromPin = false;
    });
  }

  /// Fills the address boxes from where the pin landed, leaving anything the
  /// host typed themselves alone.
  void _applyResolvedAddress(GeocodeAddress address) {
    if (!mounted) return;
    setState(() {
      final street = address.addressLine?.trim() ?? '';
      if (street.isNotEmpty &&
          (_addressController.text.trim().isEmpty || _addressFromPin)) {
        _addressController.text = street;
        _addressFromPin = true;
      }
      final city = address.city?.trim() ?? '';
      if (city.isNotEmpty && (_city.isEmpty || _cityFromPin)) {
        _city = city;
        _cityFromPin = true;
      }
      final state = address.state?.trim() ?? '';
      if (state.isNotEmpty && (_state.isEmpty || _stateFromPin)) {
        _state = state;
        _stateFromPin = true;
      }
    });
  }

  Future<void> _addPhotos() async {
    final remaining = PropertyMediaLimits.maxUnitPhotos - _photos.length;
    if (remaining <= 0) {
      OasisToast.error(
        context,
        'You can add up to ${PropertyMediaLimits.maxUnitPhotos} photos.',
      );
      return;
    }
    final picked = await _imagePicker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty || !mounted) return;
    final accepted = <File>[];
    for (final image in picked.take(remaining)) {
      final file = File(image.path);
      if (await file.length() > PropertyMediaLimits.maxPhotoBytes) {
        if (!mounted) return;
        OasisToast.error(
          context,
          '"${image.name}" is larger than 5MB, so it was left out.',
        );
        continue;
      }
      accepted.add(file);
    }
    if (!mounted) return;
    if (picked.length > remaining) {
      OasisToast.info(
        context,
        'Only the first $remaining were added. The limit is '
        '${PropertyMediaLimits.maxUnitPhotos}.',
      );
    }
    setState(() => _photos.addAll(accepted));
  }

  Future<void> _pickVideo() async {
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
        'That video is larger than 50MB. Trim it or choose a shorter one.',
      );
      return;
    }
    if (!mounted) return;
    setState(() => _video = file);
  }

  /// The edited unit's media, managed in place: the unit already exists, so
  /// uploads go straight to it.
  Future<void> _manageExistingMedia() async {
    final existing = widget.existing!;
    await openUnitMediaSheet(
      context,
      unit: UnitModel(
        id: existing.unitId,
        unitNumber: existing.unitNumber,
        bedrooms: existing.bedrooms,
        bathrooms: existing.bathrooms,
        rentAmount: '0.00',
        isOccupied: false,
        createdAt: '',
      ),
    );
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ saving

  Future<void> _publish() async {
    if (_isEditing) return _saveEdit();
    // Every step is checked again, in order: the review step can be reached
    // and then a value changed, and the first problem is the one to fix.
    for (final step in _steps) {
      if (_problemWith(step) case final problem?) {
        _jumpTo(step);
        OasisToast.error(context, problem);
        return;
      }
    }
    if (_newPlace) return _publishNewPlace();
    return _publishExistingUnit();
  }

  Future<void> _saveEdit() async {
    final controller = context.read<ShortLetController>();
    setState(() => _publishing = 'Saving your changes…');
    final listing = await controller.saveListing(
      unitId: _unitId!,
      listingId: widget.existing!.id,
      nightlyPrice: '$_rawPrice.00',
      minimumNights: _minimumNights,
      maximumGuests: _maximumGuests,
      cautionFee: _hasCaution ? '$_rawCaution.00' : '0.00',
      cancellationPolicy: _cancellationPolicy,
      availableFrom: _window == null ? null : shortLetIsoDate(_window!.start),
      availableTo: _window == null ? null : shortLetIsoDate(_window!.end),
      // Blocked dates are managed from the listing itself; an empty list
      // here would wipe any the host already set.
      blockedDates: widget.existing!.blockedDates,
      description: _description,
      houseRules: _rulesController.text.trim(),
      checkInNotes: _checkInController.text.trim(),
      isActive: _isActive,
      details: _details,
    );
    if (!mounted) return;
    setState(() => _publishing = null);
    if (listing == null) {
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not save that listing. Try again in a moment.',
      );
      return;
    }
    Navigator.pop(context, true);
    OasisToast.success(context, 'Listing updated.');
  }

  Future<void> _publishExistingUnit() async {
    final controller = context.read<ShortLetController>();
    final unitId = _unitId!;
    setState(() => _publishing = 'Creating your listing…');
    final listing = await controller.saveListing(
      unitId: unitId,
      nightlyPrice: '$_rawPrice.00',
      minimumNights: _minimumNights,
      maximumGuests: _maximumGuests,
      cautionFee: _hasCaution ? '$_rawCaution.00' : '0.00',
      cancellationPolicy: _cancellationPolicy,
      availableFrom: _window == null ? null : shortLetIsoDate(_window!.start),
      availableTo: _window == null ? null : shortLetIsoDate(_window!.end),
      description: _description,
      houseRules: _rulesController.text.trim(),
      checkInNotes: _checkInController.text.trim(),
      isActive: _isActive,
      details: _details,
    );
    if (!mounted) return;
    if (listing == null) {
      setState(() => _publishing = null);
      // The backend refused because the unit is already listed, and said
      // which listing: open that instead of showing an error.
      final existingId = controller.existingListingId;
      if (existingId != null) {
        await _openExistingInstead(existingId);
        return;
      }
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not save that listing. Try again in a moment.',
      );
      return;
    }
    await _uploadMediaAndFinish(
      unit: _unit!,
      propertyId: _property?.id,
      widened: controller.windowWasWidened,
    );
  }

  Future<void> _publishNewPlace() async {
    final pin = _pin!;
    final unitNumber = _unitNumberController.text.trim();
    final controller = context.read<ShortLetController>();
    setState(() => _publishing = 'Creating your listing…');
    final result = await controller.createHostListing(
      propertyName: _placeNameController.text.trim(),
      address: _addressController.text.trim(),
      city: _city,
      state: _state,
      latitude: pin.latitude,
      longitude: pin.longitude,
      // A whole house has no flat number, and the backend needs one.
      unitNumber: unitNumber.isEmpty ? '1' : unitNumber,
      bedrooms: _bedrooms,
      bathrooms: _bathrooms,
      nightlyPrice: '$_rawPrice.00',
      minimumNights: _minimumNights,
      maximumGuests: _maximumGuests,
      cautionFee: _hasCaution ? '$_rawCaution.00' : '0.00',
      cancellationPolicy: _cancellationPolicy,
      availableFrom: _window == null ? null : shortLetIsoDate(_window!.start),
      availableTo: _window == null ? null : shortLetIsoDate(_window!.end),
      description: _description,
      houseRules: _rulesController.text.trim(),
      checkInNotes: _checkInController.text.trim(),
      details: _details,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() => _publishing = null);
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not list your place. Try again in a moment.',
      );
      return;
    }
    // So the place shows under the host's properties without waiting for
    // the next refresh.
    unawaited(context.read<LandlordController>().loadLandlordProperties());
    await _uploadMediaAndFinish(
      unit: UnitModel(
        id: result.unitId,
        unitNumber: result.unitNumber,
        bedrooms: result.bedrooms,
        bathrooms: result.bathrooms,
        rentAmount: '0.00',
        isOccupied: false,
        createdAt: '',
      ),
      propertyId: result.propertyId.isEmpty ? null : result.propertyId,
      widened: false,
    );
  }

  /// Uploads the picked photos and video to the new listing's unit.
  ///
  /// The listing already exists by now, so a failed upload is not a failed
  /// listing: the host lands in the media manager to retry instead of being
  /// told the whole thing went wrong.
  Future<void> _uploadMediaAndFinish({
    required UnitModel unit,
    required String? propertyId,
    required bool widened,
  }) async {
    final landlord = context.read<LandlordController>();
    final shortLets = context.read<ShortLetController>();
    final navigator = Navigator.of(context);

    var mediaOk = unit.id.isNotEmpty;
    if (mediaOk) {
      setState(() => _publishing = 'Uploading ${_photos.length} photos…');
      mediaOk = await landlord.uploadUnitPhotos(
        unitId: unit.id,
        photos: List.of(_photos),
        propertyId: propertyId,
      );
    }
    if (mediaOk && mounted) {
      setState(() => _publishing = 'Uploading your tour video…');
      mediaOk = await landlord.uploadUnitVideo(
        unitId: unit.id,
        video: _video!,
        propertyId: propertyId,
      );
    }
    await shortLets.loadLandlordListings();
    if (!navigator.mounted) return;

    navigator.pop(true);
    if (mediaOk) {
      OasisToast.success(
        navigator.context,
        widened
            ? 'Your place is live. This server needs a booking window, so '
                  'yours runs for the next 5 years. You can narrow it any time.'
            : 'Your place is live.',
      );
      return;
    }
    OasisToast.error(
      navigator.context,
      'Your place is listed, but some media did not upload. Add it here.',
    );
    if (unit.id.isEmpty) return;
    await openUnitMediaSheet(
      navigator.context,
      unit: unit,
      propertyId: propertyId,
    );
    await shortLets.loadLandlordListings();
  }

  /// Closes this flow and reopens it on the listing that already exists.
  Future<void> _openExistingInstead(String listingId) async {
    final navigator = Navigator.of(context);
    final controller = context.read<ShortLetController>();

    await controller.loadLandlordListings();
    if (!navigator.mounted) return;

    final existing = controller.listings
        .where((listing) => listing.id == listingId)
        .firstOrNull;
    navigator.pop(existing != null);
    if (existing == null) {
      OasisToast.error(
        navigator.context,
        'That unit is already listed for short stays. Open it from Short '
        'lets to change it.',
      );
      return;
    }
    OasisToast.info(
      navigator.context,
      '${existing.title} is already listed. Opening it to edit instead.',
    );
    await openCreateShortLetSheet(navigator.context, existing: existing);
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    // Watched so the media step's counts update as the manager loads.
    context.watch<LandlordController>();
    context.watch<ShortLetController>();
    final isLast = _step == _Step.review;
    final progress = (_stepIndex + 1) / _steps.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppTheme.pageBackground(context),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    V2CircleButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      onTap: _confirmLeave,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isEditing
                            ? 'Edit ${widget.existing!.title}'
                            : 'List a place',
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.cardTitle(context),
                      ),
                    ),
                    Text(
                      'Step ${_stepIndex + 1} of ${_steps.length}',
                      style: AppTheme.labelText(
                        context,
                        color: AppTheme.secondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: const Duration(milliseconds: 250),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 4,
                      color: AppTheme.actionColor,
                      backgroundColor: AppTheme.subtleSurfaceColor(context),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: ListView(
                        key: ValueKey(_step),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          Text(
                            _step.title,
                            style: V2PageHeader.titleStyle(context),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _step.subtitle,
                            style: AppTheme.bodyText(
                              context,
                            ).copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          ..._stepFields(context),
                        ],
                      ),
                    ),
                    if (_publishing != null)
                      Positioned.fill(child: _PublishingOverlay(_publishing!)),
                  ],
                ),
              ),
              _BottomBar(
                showBack: _stepIndex > 0,
                nextLabel: isLast
                    ? (_isEditing ? 'Save changes' : 'Publish listing')
                    : 'Next',
                isBusy: _publishing != null,
                onBack: _back,
                onNext: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _stepFields(BuildContext context) => switch (_step) {
    _Step.place => _placeFields(context),
    _Step.space => _spaceFields(context),
    _Step.bestFor => _bestForFields(context),
    _Step.describe => _describeFields(context),
    _Step.media => _mediaFields(context),
    _Step.pricing => _pricingFields(context),
    _Step.rules => _rulesFields(context),
    _Step.review => _reviewFields(context),
  };

  // ------------------------------------------------------------ steps

  List<Widget> _placeFields(BuildContext context) {
    final landlord = context.read<LandlordController>();
    return [
      // Only offered once there is something to pick: a new host goes
      // straight to the new-place fields.
      if (_canAddNewPlace && landlord.properties.isNotEmpty) ...[
        V2SegmentChips(
          labels: const ['A new place', 'One of my units'],
          selected: _newPlace ? 0 : 1,
          onSelected: (index) => setState(() => _newPlace = index == 0),
        ),
        const SizedBox(height: 22),
      ],
      if (_newPlace)
        ..._newPlaceFields(context)
      else
        ..._existingUnitFields(context),
    ];
  }

  List<Widget> _newPlaceFields(BuildContext context) => [
    const OasisFieldLabel('Place name'),
    TextField(
      controller: _placeNameController,
      textCapitalization: TextCapitalization.words,
      onChanged: (_) => setState(() {}),
      style: AppTheme.cardTitle(context),
      decoration: oasisInputDecoration(
        context,
        hint: 'e.g. The Lekki Loft',
        prefixIcon: Icons.home_work_outlined,
      ),
    ),
    const SizedBox(height: 6),
    _Hint('Guests see this as the title of your listing.'),
    const SizedBox(height: 18),
    const OasisFieldLabel('Address'),
    TextField(
      controller: _addressController,
      textCapitalization: TextCapitalization.words,
      // Typing hands the box back to the host: the pin stops writing to it.
      onChanged: (_) => setState(() => _addressFromPin = false),
      style: AppTheme.cardTitle(context),
      decoration: oasisInputDecoration(
        context,
        hint: 'Street address',
        prefixIcon: Icons.signpost_outlined,
      ),
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: OasisPickerField(
            value: _state,
            hint: 'State',
            prefixIcon: Icons.map_outlined,
            onTap: _pickState,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OasisPickerField(
            value: _city,
            hint: 'City / area',
            prefixIcon: Icons.location_city_rounded,
            onTap: _pickCity,
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    PropertyLocationPicker(
      city: _city,
      state: _state,
      onChanged: (pin) => setState(() => _pin = pin),
      addressResolver: () => _addressController.text.trim(),
      onAddressResolved: _applyResolvedAddress,
    ),
    const SizedBox(height: 18),
    OasisFieldLabel(
      'Flat or unit',
      trailing: const _OptionalPill(label: 'Optional'),
    ),
    TextField(
      controller: _unitNumberController,
      textCapitalization: TextCapitalization.characters,
      style: AppTheme.cardTitle(context),
      decoration: oasisInputDecoration(
        context,
        hint: 'e.g. 3B. Leave empty for a whole house',
        prefixIcon: Icons.meeting_room_outlined,
      ),
    ),
  ];

  List<Widget> _existingUnitFields(BuildContext context) {
    final landlord = context.read<LandlordController>();
    final controller = context.read<ShortLetController>();
    final units = _property == null
        ? const <UnitModel>[]
        : landlord.propertyUnits[_property!.id] ?? const <UnitModel>[];
    return [
      const OasisFieldLabel('Property'),
      DropdownButtonFormField<PropertyModel>(
        initialValue: _property,
        isExpanded: true,
        borderRadius: AppTheme.cornerMd,
        decoration: oasisInputDecoration(
          context,
          prefixIcon: Icons.apartment_outlined,
        ),
        hint: Text('Choose a property', style: AppTheme.bodyText(context)),
        items: [
          for (final property in landlord.properties)
            DropdownMenuItem(
              value: property,
              child: Text(property.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (property) => setState(() {
          _property = property;
          _unit = null;
        }),
      ),
      const SizedBox(height: 18),
      const OasisFieldLabel('Unit'),
      DropdownButtonFormField<UnitModel>(
        initialValue: _unit,
        isExpanded: true,
        borderRadius: AppTheme.cornerMd,
        decoration: oasisInputDecoration(
          context,
          prefixIcon: Icons.meeting_room_outlined,
        ),
        hint: Text(
          _property == null ? 'Pick a property first' : 'Choose a unit',
          style: AppTheme.bodyText(context),
        ),
        items: [
          for (final unit in units)
            DropdownMenuItem(
              value: unit,
              // Shown and disabled rather than filtered out, so a host
              // looking for flat A1 sees where it went.
              enabled: controller.listingForUnit(unit.id) == null,
              child: Text(
                controller.listingForUnit(unit.id) == null
                    ? 'Unit ${unit.unitNumber}'
                    : 'Unit ${unit.unitNumber} · already listed',
                style: controller.listingForUnit(unit.id) == null
                    ? null
                    : AppTheme.bodyText(
                        context,
                        color: AppTheme.mutedTextColor(context),
                      ),
              ),
            ),
        ],
        onChanged: (unit) => setState(() => _unit = unit),
      ),
      if (_duplicateListing case final duplicate?) ...[
        const SizedBox(height: 8),
        _Notice(
          icon: Icons.info_outline_rounded,
          color: AppTheme.warningColor,
          text:
              '${duplicate.title} is already let by the night. Edit that '
              'listing from Short lets instead of adding a second one.',
        ),
      ],
    ];
  }

  List<Widget> _spaceFields(BuildContext context) => [
    const OasisFieldLabel('Type of place'),
    _ChoiceWrap(
      children: [
        for (final type in ShortLetPlaceType.values)
          _ChoiceChip(
            label: type.label,
            icon: type.icon,
            selected: _details.placeType == type,
            onTap: () =>
                setState(() => _details = _details.copyWith(placeType: type)),
          ),
      ],
    ),
    const SizedBox(height: 22),
    // Bedrooms and bathrooms belong to the unit. A new place sets them here;
    // an existing unit already has them.
    if (_newPlace && !_isEditing) ...[
      Row(
        children: [
          Expanded(
            child: _Stepper(
              label: 'Bedrooms',
              value: _bedrooms,
              min: 1,
              max: 12,
              onChanged: (value) => setState(() => _bedrooms = value),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Stepper(
              label: 'Bathrooms',
              value: _bathrooms,
              min: 1,
              max: 12,
              onChanged: (value) => setState(() => _bathrooms = value),
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
    ],
    _Stepper(
      label: 'Sleeps up to',
      value: _maximumGuests,
      min: 1,
      max: 20,
      onChanged: (value) => setState(() => _maximumGuests = value),
    ),
    const SizedBox(height: 22),
    OasisFieldLabel(
      'What the place has',
      trailing: _OptionalPill(
        label: '${_details.amenities.length} picked',
        highlight: _details.amenities.isNotEmpty,
      ),
    ),
    _ChoiceWrap(
      children: [
        for (final amenity in ShortLetAmenity.values)
          _ChoiceChip(
            label: amenity.label,
            icon: amenity.icon,
            selected: _details.amenities.contains(amenity),
            onTap: () => setState(() {
              final next = {..._details.amenities};
              if (!next.remove(amenity)) next.add(amenity);
              _details = _details.copyWith(amenities: next);
            }),
          ),
      ],
    ),
  ];

  List<Widget> _bestForFields(BuildContext context) => [
    _ChoiceWrap(
      children: [
        for (final occasion in ShortLetOccasion.values)
          _ChoiceChip(
            label: occasion.label,
            icon: occasion.icon,
            selected: _details.bestFor.contains(occasion),
            onTap: () => setState(() {
              final next = {..._details.bestFor};
              if (!next.remove(occasion)) next.add(occasion);
              // Parties and allowing parties are the same promise. Picking
              // one without the other would tell guests two different things.
              _details = _details.copyWith(
                bestFor: next,
                partiesAllowed: occasion == ShortLetOccasion.party
                    ? next.contains(occasion)
                    : null,
              );
            }),
          ),
      ],
    ),
    const SizedBox(height: 14),
    _Hint(
      'Choosing Parties also marks parties as allowed in your house rules. '
      'You can change that on the rules step.',
    ),
  ];

  List<Widget> _describeFields(BuildContext context) => [
    OasisFieldLabel(
      'About this place',
      trailing: _OptionalPill(
        label: '${_description.length}/$_minDescriptionLength min',
        highlight: _description.length >= _minDescriptionLength,
      ),
    ),
    TextField(
      controller: _descriptionController,
      maxLines: 8,
      minLines: 6,
      maxLength: _maxDescriptionLength,
      textCapitalization: TextCapitalization.sentences,
      style: AppTheme.bodyText(context),
      onChanged: (_) => setState(() {}),
      decoration: oasisInputDecoration(
        context,
        hint:
            'A quiet two-bedroom flat five minutes from the airport. Fast '
            'wifi, 24-hour power, parking in the compound.',
      ),
    ),
    _Hint(
      'Say what the place is like, who it suits and what is nearby: '
      'restaurants, beaches, the airport.',
    ),
  ];

  List<Widget> _mediaFields(BuildContext context) {
    if (_isEditing) {
      final photos = _existingPhotoCount;
      final hasVideo = _existingHasVideo;
      return [
        _MediaStatusRow(
          icon: Icons.photo_library_outlined,
          label: 'Photos',
          value: '$photos added',
          done: photos >= _minPhotos,
        ),
        const SizedBox(height: 10),
        _MediaStatusRow(
          icon: Icons.videocam_outlined,
          label: 'Tour video',
          value: hasVideo ? 'Added' : 'Missing',
          done: hasVideo,
        ),
        const SizedBox(height: 18),
        OasisSheetButton(
          label: 'Manage photos and video',
          icon: Icons.perm_media_outlined,
          onPressed: _manageExistingMedia,
        ),
      ];
    }
    return [
      OasisFieldLabel(
        'Photos',
        trailing: _OptionalPill(
          label: '${_photos.length}/$_minPhotos min',
          highlight: _photos.length >= _minPhotos,
        ),
      ),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var i = 0; i < _photos.length; i++)
            _PhotoTile(
              file: _photos[i],
              isCover: i == 0,
              onRemove: () => setState(() => _photos.removeAt(i)),
            ),
          if (_photos.length < PropertyMediaLimits.maxUnitPhotos)
            _AddTile(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Add photos',
              onTap: _addPhotos,
            ),
        ],
      ),
      const SizedBox(height: 6),
      _Hint(
        'The first photo is your cover. Up to '
        '${PropertyMediaLimits.maxUnitPhotos}, 5MB each.',
      ),
      const SizedBox(height: 22),
      OasisFieldLabel(
        'Tour video',
        trailing: _OptionalPill(
          label: _video == null ? 'Required' : 'Added',
          highlight: _video != null,
        ),
      ),
      if (_video == null)
        SizedBox(
          height: 110,
          child: _AddTile(
            icon: Icons.video_call_outlined,
            label: 'Add a walkthrough video',
            onTap: _pickVideo,
          ),
        )
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.subtleSurfaceColor(context),
            borderRadius: AppTheme.cornerMd,
            border: Border.all(color: AppTheme.borderColor(context)),
          ),
          child: Row(
            children: [
              const Icon(Icons.videocam_rounded, color: AppTheme.successColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _video!.path.split(Platform.pathSeparator).last,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.cardTitle(context),
                ),
              ),
              TextButton(onPressed: _pickVideo, child: const Text('Change')),
            ],
          ),
        ),
      const SizedBox(height: 6),
      _Hint('MP4 or MOV, up to 50MB. Walk through each room in one take.'),
    ];
  }

  List<Widget> _pricingFields(BuildContext context) => [
    const OasisFieldLabel('Price per night'),
    TextField(
      controller: _priceController,
      keyboardType: TextInputType.number,
      inputFormatters: const [OasisThousandsFormatter()],
      style: AppTheme.cardTitle(context),
      onChanged: (_) => setState(() {}),
      decoration: oasisInputDecoration(
        context,
        hint: '50000',
        prefixIcon: Icons.payments_outlined,
        suffix: Padding(
          padding: const EdgeInsets.only(right: 16, left: 8),
          child: Text('₦ / night', style: AppTheme.labelText(context)),
        ),
      ),
    ),
    const SizedBox(height: 18),
    OasisFieldLabel(
      'Caution fee',
      trailing: _OptionalPill(
        label: _hasCaution ? 'Refundable' : 'Optional',
        highlight: _hasCaution,
      ),
    ),
    TextField(
      controller: _cautionController,
      keyboardType: TextInputType.number,
      inputFormatters: const [OasisThousandsFormatter()],
      style: AppTheme.cardTitle(context),
      onChanged: (_) => setState(() {}),
      decoration: oasisInputDecoration(
        context,
        hint: 'Leave empty for no deposit',
        prefixIcon: Icons.shield_outlined,
        suffix: Padding(
          padding: const EdgeInsets.only(right: 16, left: 8),
          child: Text('₦', style: AppTheme.labelText(context)),
        ),
      ),
    ),
    const SizedBox(height: 6),
    _Hint(
      _hasCaution
          ? 'Guests pay this on top of the nightly total. It is held and '
                'returned after checkout unless you report damage.'
          : 'Ask for a refundable deposit if you want cover for damage.',
    ),
    const SizedBox(height: 18),
    _Stepper(
      label: 'Minimum nights',
      value: _minimumNights,
      min: 1,
      max: 30,
      onChanged: (value) => setState(() => _minimumNights = value),
    ),
    const SizedBox(height: 18),
    const OasisFieldLabel('Cancellation policy'),
    DropdownButtonFormField<ShortLetCancellationPolicy>(
      initialValue: _cancellationPolicy,
      isExpanded: true,
      borderRadius: AppTheme.cornerMd,
      decoration: oasisInputDecoration(
        context,
        prefixIcon: Icons.policy_outlined,
      ),
      items: [
        for (final policy in ShortLetCancellationPolicy.values)
          DropdownMenuItem(value: policy, child: Text(policy.label)),
      ],
      onChanged: (policy) {
        if (policy != null) setState(() => _cancellationPolicy = policy);
      },
    ),
    const SizedBox(height: 6),
    _Hint(
      '${_cancellationPolicy.defaultSummary} Guests see the terms before they '
      'request dates.',
    ),
    const SizedBox(height: 18),
    OasisFieldLabel(
      'Available between',
      trailing: _OptionalPill(
        label: _window == null ? 'Any dates' : 'Set',
        highlight: _window != null,
      ),
    ),
    _TapField(
      icon: Icons.event_available_outlined,
      value: _window == null
          ? null
          : '${DateFormat('d MMM yyyy').format(_window!.start)} – '
                '${DateFormat('d MMM yyyy').format(_window!.end)}',
      placeholder: 'Taking bookings any time',
      onTap: _pickWindow,
      onClear: _window == null ? null : () => setState(() => _window = null),
    ),
    if (_hasPrice) ...[
      const SizedBox(height: 18),
      _Notice(
        icon: Icons.calculate_outlined,
        color: AppTheme.secondaryTextColor(context),
        text: _quoteLine,
      ),
    ],
  ];

  List<Widget> _rulesFields(BuildContext context) => [
    Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OasisFieldLabel('Check-in from'),
              _TapField(
                icon: Icons.login_rounded,
                value: _formatTime(_details.checkInTime),
                onTap: () => _pickTime(checkIn: true),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const OasisFieldLabel('Check-out by'),
              _TapField(
                icon: Icons.logout_rounded,
                value: _formatTime(_details.checkOutTime),
                onTap: () => _pickTime(checkIn: false),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 18),
    _RuleSwitch(
      icon: Icons.smoke_free_rounded,
      label: 'Smoking allowed',
      value: _details.smokingAllowed,
      onChanged: (value) =>
          setState(() => _details = _details.copyWith(smokingAllowed: value)),
    ),
    _RuleSwitch(
      icon: Icons.pets_rounded,
      label: 'Pets allowed',
      value: _details.petsAllowed,
      onChanged: (value) =>
          setState(() => _details = _details.copyWith(petsAllowed: value)),
    ),
    _RuleSwitch(
      icon: Icons.celebration_outlined,
      label: 'Parties and events allowed',
      value: _details.partiesAllowed,
      onChanged: (value) => setState(() {
        final bestFor = {..._details.bestFor};
        if (!value) bestFor.remove(ShortLetOccasion.party);
        _details = _details.copyWith(partiesAllowed: value, bestFor: bestFor);
      }),
    ),
    const SizedBox(height: 18),
    OasisFieldLabel(
      'Other house rules',
      trailing: const _OptionalPill(label: 'Optional'),
    ),
    TextField(
      controller: _rulesController,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      style: AppTheme.bodyText(context),
      decoration: oasisInputDecoration(
        context,
        hint: 'Quiet after 10pm. No shoes on the rug.',
      ),
    ),
    const SizedBox(height: 18),
    OasisFieldLabel(
      'Check-in notes',
      trailing: const _OptionalPill(label: 'Optional'),
    ),
    TextField(
      controller: _checkInController,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      style: AppTheme.bodyText(context),
      decoration: oasisInputDecoration(
        context,
        hint: 'Gate code, key box, who to call on arrival.',
      ),
    ),
    const SizedBox(height: 6),
    _Notice(
      icon: Icons.lock_outline_rounded,
      color: AppTheme.mutedTextColor(context),
      text: 'Only shared with a guest once they have paid.',
    ),
    if (_isEditing) ...[
      const SizedBox(height: 10),
      SwitchListTile.adaptive(
        value: _isActive,
        onChanged: (value) => setState(() => _isActive = value),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppTheme.actionColor,
        title: Text('Taking bookings', style: AppTheme.cardTitle(context)),
        subtitle: Text(
          _isActive
              ? 'Guests can find and request this place.'
              : 'Hidden from guests. Existing bookings are unaffected.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ),
    ],
  ];

  List<Widget> _reviewFields(BuildContext context) {
    final placeLine = _isEditing
        ? widget.existing!.title
        : _newPlace
        ? [
            _placeNameController.text.trim(),
            [_city, _state].where((part) => part.isNotEmpty).join(', '),
          ].where((part) => part.isNotEmpty).join(' · ')
        : [
            _property?.name,
            if (_unit != null) 'Unit ${_unit!.unitNumber}',
          ].whereType<String>().join(' · ');
    final photos = _isEditing ? _existingPhotoCount : _photos.length;
    final hasVideo = _isEditing ? _existingHasVideo : _video != null;
    final rules = [
      _details.smokingAllowed ? 'Smoking OK' : 'No smoking',
      _details.petsAllowed ? 'Pets OK' : 'No pets',
      _details.partiesAllowed ? 'Parties OK' : 'No parties',
    ].join(' · ');

    return [
      if (!_isEditing)
        _ReviewRow(
          label: 'Place',
          value: placeLine,
          onEdit: () => _jumpTo(_Step.place),
        ),
      _ReviewRow(
        label: 'Space',
        value: [
          _details.placeType?.label ?? 'Type not set',
          'Sleeps $_maximumGuests',
          '${_details.amenities.length} amenities',
        ].join(' · '),
        onEdit: () => _jumpTo(_Step.space),
      ),
      _ReviewRow(
        label: 'Best for',
        value: _details.bestFor.map((o) => o.label).join(', '),
        onEdit: () => _jumpTo(_Step.bestFor),
      ),
      _ReviewRow(
        label: 'Description',
        value: _description,
        onEdit: () => _jumpTo(_Step.describe),
      ),
      _ReviewRow(
        label: 'Media',
        value:
            '$photos photos · ${hasVideo ? 'tour video added' : 'no tour video'}',
        onEdit: () => _jumpTo(_Step.media),
      ),
      _ReviewRow(
        label: 'Price',
        value: _hasPrice
            ? '${OasisCurrency.format('$_rawPrice.00')} a night · '
                  '$_minimumNights-night minimum · ${_cancellationPolicy.label}'
            : 'Not set',
        onEdit: () => _jumpTo(_Step.pricing),
      ),
      _ReviewRow(
        label: 'Rules',
        value:
            'In from ${_formatTime(_details.checkInTime)}, out by '
            '${_formatTime(_details.checkOutTime)} · $rules',
        onEdit: () => _jumpTo(_Step.rules),
      ),
      const SizedBox(height: 12),
      _Notice(
        icon: Icons.verified_user_outlined,
        color: AppTheme.secondaryTextColor(context),
        text: _isEditing
            ? 'Changes show to guests as soon as you save.'
            : 'Your place goes live once the photos and video upload. You '
                  'approve every booking before anyone pays.',
      ),
    ];
  }
}

// ------------------------------------------------------------ widgets

class _BottomBar extends StatelessWidget {
  final bool showBack;
  final String nextLabel;
  final bool isBusy;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _BottomBar({
    required this.showBack,
    required this.nextLabel,
    required this.isBusy,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppTheme.pageBackground(context),
      border: Border(top: BorderSide(color: AppTheme.borderColor(context))),
    ),
    padding: EdgeInsets.fromLTRB(
      20,
      12,
      20,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Row(
      children: [
        if (showBack) ...[
          TextButton(
            onPressed: isBusy ? null : onBack,
            child: Text(
              'Back',
              style: AppTheme.cardTitle(
                context,
                color: AppTheme.primaryTextColor(context),
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: OasisSheetButton(
            label: nextLabel,
            icon: nextLabel == 'Next'
                ? Icons.arrow_forward_rounded
                : Icons.check_rounded,
            isLoading: isBusy,
            onPressed: isBusy ? null : onNext,
          ),
        ),
      ],
    ),
  );
}

class _PublishingOverlay extends StatelessWidget {
  final String message;

  const _PublishingOverlay(this.message);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTheme.pageBackground(context).withValues(alpha: 0.92),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppTheme.actionColor),
          const SizedBox(height: 18),
          Text(message, style: AppTheme.cardTitle(context)),
          const SizedBox(height: 6),
          Text(
            'Keep the app open until this finishes.',
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ChoiceWrap extends StatelessWidget {
  final List<Widget> children;

  const _ChoiceWrap({required this.children});

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 8, runSpacing: 8, children: children);
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Colors.white
        : AppTheme.primaryTextColor(context);
    return Semantics(
      button: true,
      selected: selected,
      child: OasisPressable(
        onTap: onTap,
        pressedScale: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.terracottaColor
                : AppTheme.surfaceColor(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? AppTheme.terracottaColor
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTheme.bodyText(
                  context,
                  color: foreground,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final File file;
  final bool isCover;
  final VoidCallback onRemove;

  const _PhotoTile({
    required this.file,
    required this.isCover,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: AppTheme.cornerMd,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image.file(file, fit: BoxFit.cover, cacheWidth: 400),
        if (isCover)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Cover',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AddTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.actionColor, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTheme.labelText(context, color: AppTheme.actionColor),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MediaStatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool done;

  const _MediaStatusRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.done,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.surfaceColor(context),
      borderRadius: AppTheme.cornerMd,
      border: Border.all(color: AppTheme.borderColor(context)),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppTheme.primaryTextColor(context)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: AppTheme.cardTitle(context))),
        Text(
          value,
          style: AppTheme.labelText(
            context,
            color: done ? AppTheme.successColor : AppTheme.warningColor,
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          done ? Icons.check_circle_rounded : Icons.error_outline_rounded,
          size: 18,
          color: done ? AppTheme.successColor : AppTheme.warningColor,
        ),
      ],
    ),
  );
}

class _TapField extends StatelessWidget {
  final IconData icon;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _TapField({
    required this.icon,
    required this.value,
    required this.onTap,
    this.placeholder = '',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppTheme.cornerMd,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppTheme.mutedTextColor(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value ?? placeholder,
              style: value == null
                  ? AppTheme.bodyText(
                      context,
                      color: AppTheme.mutedTextColor(context),
                    )
                  : AppTheme.cardTitle(context),
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.mutedTextColor(context),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RuleSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RuleSwitch({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 21, color: AppTheme.primaryTextColor(context)),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: AppTheme.cardTitle(context))),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppTheme.terracottaColor,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onEdit;

  const _ReviewRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.borderColor(context))),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTheme.labelText(context).copyWith(letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              Text(
                value.isEmpty ? 'Not set' : value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodyText(
                  context,
                  color: AppTheme.primaryTextColor(context),
                ),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onEdit, child: const Text('Edit')),
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  final String text;

  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.labelText(
      context,
      color: AppTheme.secondaryTextColor(context),
    ),
  );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: AppTheme.labelText(context, color: color)),
      ),
    ],
  );
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OasisFieldLabel(label),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded, size: 18),
              color: AppTheme.actionColor,
              disabledColor: AppTheme.mutedTextColor(context),
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: AppTheme.cardTitle(context),
              ),
            ),
            IconButton(
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              color: AppTheme.actionColor,
              disabledColor: AppTheme.mutedTextColor(context),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Status pill beside a field label: optional, set, or satisfied.
class _OptionalPill extends StatelessWidget {
  final String label;
  final bool highlight;

  const _OptionalPill({required this.label, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? AppTheme.successColor
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
