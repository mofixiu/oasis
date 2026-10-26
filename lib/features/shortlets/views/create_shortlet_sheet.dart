import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/app_variant.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/nigeria_locations.dart';
import '../../../core/utils/oasis_currency.dart';
import '../../../core/widgets/oasis_place_picker.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../../../core/widgets/v2_ui.dart';
import '../../properties/controllers/landlord_controller.dart';
import '../../properties/models/property_model.dart';
import '../../properties/services/geocoding_service.dart';
import '../../properties/views/widgets/property_location_picker.dart';
import '../../properties/views/widgets/unit_media_sheet.dart';
import '../controllers/shortlet_controller.dart';
import '../models/shortlet_models.dart';
import '../../../core/utils/oasis_input_formatters.dart';

/// Lists a unit for nightly stays, or edits the listing it already has.
///
/// Returns true when something was saved. One sheet for both jobs, and which
/// one it is comes down to whether [existing] was passed: a create `POST`s to
/// the collection, an edit `PATCH`es the listing's own path.
///
/// The two used to be the same request: the backend keyed a listing to its
/// unit and treated a second `POST` as an edit, which was fine when the host
/// meant to edit and silently replaced a live price and calendar when they
/// did not. It now refuses that with `409 LISTING_EXISTS` and hands back the
/// id of the listing that already exists. The client-side duplicate check
/// below stays as the first line, it is faster and it can explain itself,
/// but the backend is now the one that decides.
Future<bool> openCreateShortLetSheet(
  BuildContext context, {
  ShortLetListing? existing,

  /// Pre-selects the unit being listed, for the add-property flow that walks
  /// a host straight from creating a place into listing it. The pickers are
  /// still shown, so a host who opened this from Short lets picks as before.
  PropertyModel? initialProperty,
  UnitModel? initialUnit,

  /// The nightly price the host already typed on the unit, carried through
  /// so the same number is not asked for twice.
  String? initialNightlyPrice,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Keeps the sheet below the status bar when the keyboard lifts the
    // height cap below; without it the title runs into the clock.
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Capped at 70% rather than left to grow with the form. This is the
    // longest sheet in the app, and unconstrained it reaches the top of the
    // screen, where its title collides with the clock and there is no visible
    // way back to what is behind it.
    //
    // The cap lifts while the keyboard is up. The pinned footer pads itself by
    // the keyboard inset so the button stays reachable, and holding the sheet
    // to 70% of the screen at the same time leaves nowhere for that padding to
    // go: on a small phone the whole thing overflows. Read inside the builder
    // rather than passed as `constraints`, so it tracks the keyboard instead
    // of being fixed at the moment the sheet opened.
    builder: (sheetContext) {
      final screenHeight = MediaQuery.sizeOf(sheetContext).height;
      final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: keyboard > 0 ? screenHeight : screenHeight * 0.7,
        ),
        child: _CreateShortLetSheet(
          existing: existing,
          initialProperty: initialProperty,
          initialUnit: initialUnit,
          initialNightlyPrice: initialNightlyPrice,
        ),
      );
    },
  );
  return saved ?? false;
}

class _CreateShortLetSheet extends StatefulWidget {
  final ShortLetListing? existing;
  final PropertyModel? initialProperty;
  final UnitModel? initialUnit;
  final String? initialNightlyPrice;

  const _CreateShortLetSheet({
    this.existing,
    this.initialProperty,
    this.initialUnit,
    this.initialNightlyPrice,
  });

  @override
  State<_CreateShortLetSheet> createState() => _CreateShortLetSheetState();
}

class _CreateShortLetSheetState extends State<_CreateShortLetSheet> {
  final _priceController = TextEditingController();

  /// The refundable deposit. Blank means none, which is why it is a text
  /// field rather than a switch plus an amount: a host who wants no deposit
  /// should not have to touch anything.
  final _cautionController = TextEditingController();

  /// The host's write-up of the place: the one field on this form written
  /// *to* a guest rather than about the unit.
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

  /// v2 only: the place is not one of the host's units yet, so the property
  /// and unit are made in the same request as the listing
  /// (`POST /host/listings/`). A new host has nothing to pick from, and the
  /// v1 add-property flow that used to come first is not part of v2.
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

  bool get _isEditing => widget.existing != null;

  /// Whether this sheet can make a new place at all: v2, adding rather than
  /// editing, and not handed a unit by the v1 add-property flow.
  bool get _canAddNewPlace =>
      isOasisV2 && !_isEditing && widget.initialUnit == null;

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
      final from = DateTime.tryParse(existing.availableFrom ?? '');
      final to = DateTime.tryParse(existing.availableTo ?? '');
      if (from != null && to != null && to.isAfter(from)) {
        _window = DateTimeRange(start: from, end: to);
      }
    }
    // The unit picker needs the landlord's properties; a sheet opened straight
    // from the dashboard may be the first thing to want them.
    //
    // The existing listings are fetched for the same reason, and one more:
    // they are how this sheet knows a unit is already let by the night. A
    // host whose listings have not loaded would otherwise be allowed to pick
    // a unit that already has one and silently overwrite it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final landlord = context.read<LandlordController>();
      if (landlord.properties.isEmpty) landlord.loadLandlordProperties();
      final shortLets = context.read<ShortLetController>();
      if (!shortLets.hasLoaded(ShortLetController.kListingsKey)) {
        shortLets.loadLandlordListings();
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

  /// Digits only: the API takes a decimal string and the landlord types naira.
  String get _rawPrice =>
      _priceController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasPrice => _rawPrice.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  /// The deposit as digits, and whether one was actually asked for. A field
  /// left blank, or filled with zeroes, both mean "no deposit".
  String get _rawCaution =>
      _cautionController.text.replaceAll(RegExp(r'[^0-9]'), '');

  bool get _hasCaution => _rawCaution.replaceAll(RegExp(r'^0+'), '').isNotEmpty;

  /// Long enough for a host to describe a flat properly, short enough that
  /// the listing screen stays a page rather than an essay. The backend
  /// enforces the same ceiling: see `backend_change_spec_v11.md` §2.
  static const int _maxDescriptionLength = 1000;

  bool get _hasDescription => _descriptionController.text.trim().isNotEmpty;

  /// The unit this listing is for. When editing, it is fixed: moving a
  /// listing between units would silently create a second one.
  String? get _unitId => _isEditing ? widget.existing!.unitId : _unit?.id;

  /// The listing this unit already has, when the host has picked one that is
  /// let by the night. Null while editing: editing *is* that listing.
  ShortLetListing? get _duplicateListing {
    if (_isEditing || _newPlace) return null;
    final unitId = _unit?.id;
    if (unitId == null) return null;
    return context.read<ShortLetController>().listingForUnit(unitId);
  }

  /// What a minimum-length stay would cost a guest, deposit included.
  ///
  /// Written out for the host because the deposit changes the number the
  /// guest sees at checkout, and a host who has never seen that number is the
  /// one who is surprised by a cancelled booking.
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

  Future<void> _save() async {
    if (_newPlace) return _saveNewPlace();
    final unitId = _unitId;
    if (unitId == null || unitId.isEmpty) {
      OasisToast.error(context, 'Pick the unit you want to let by the night.');
      return;
    }
    if (!_hasPrice) {
      OasisToast.error(context, 'Set a nightly price.');
      return;
    }

    final controller = context.read<ShortLetController>();

    // The duplicate check. `POST` with a unit that already has a listing
    // edits that listing rather than refusing, so a host adding the same
    // flat twice would not get two listings: they would get their live
    // price, rules and calendar quietly replaced by whatever is in this
    // form. Refused here, with the way to the real thing.
    if (!_isEditing) {
      final duplicate = controller.listingForUnit(unitId);
      if (duplicate != null) {
        OasisToast.error(
          context,
          '${duplicate.title} is already listed for short stays. Open that '
          'listing from Short lets to change its price or dates.',
        );
        return;
      }
    }

    final listing = await controller.saveListing(
      unitId: unitId,
      // Null when adding, which is what makes this a create. Supplied when
      // editing, which sends it to the listing's own path: the backend no
      // longer accepts an edit as a second POST.
      listingId: widget.existing?.id,
      nightlyPrice: '$_rawPrice.00',
      minimumNights: _minimumNights,
      maximumGuests: _maximumGuests,
      // Always sent, so clearing the field actually removes a deposit the
      // host set last time rather than silently leaving it in place.
      cautionFee: _hasCaution ? '$_rawCaution.00' : '0.00',
      cancellationPolicy: _cancellationPolicy,
      availableFrom: _window == null ? null : shortLetIsoDate(_window!.start),
      availableTo: _window == null ? null : shortLetIsoDate(_window!.end),
      // Blocked dates are managed from the listing itself once it exists;
      // sending an empty list here would wipe any the host already set.
      blockedDates: widget.existing?.blockedDates ?? const [],
      description: _descriptionController.text.trim(),
      houseRules: _rulesController.text.trim(),
      checkInNotes: _checkInController.text.trim(),
      isActive: _isActive,
    );
    if (!mounted) return;

    if (listing == null) {
      // The backend refused the create because the unit is already listed,
      // and told us which listing. The host wanted this unit let by the
      // night and it is, so the useful answer is that listing, not an
      // error. This is the race the client-side check above cannot cover:
      // a unit listed on another device since the last fetch.
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

    Navigator.pop(context, true);
    if (controller.windowWasWidened) {
      // The host asked for no window and the backend would not take one, so
      // the app set the widest it could. Say so: a listing that comes back
      // reading "Bookable until 2031" when they chose "any dates" would
      // otherwise look like the app ignoring them.
      OasisToast.success(
        context,
        'Listed. This server needs a booking window, so yours runs for the '
        'next 5 years. You can narrow it any time.',
      );
    } else {
      OasisToast.success(
        context,
        _isEditing
            ? 'Listing updated.'
            : isOasisV2
            ? 'Your place is listed.'
            : 'Your place is listed for short stays.',
      );
    }
  }

  /// The first thing a new place is still missing, or null when it is ready.
  /// Checked in the order the fields appear, so the toast points at the
  /// highest one left to fill in.
  String? get _newPlaceProblem {
    if (_placeNameController.text.trim().isEmpty) {
      return 'Give your place a name.';
    }
    if (_addressController.text.trim().isEmpty) {
      return 'Add the street address.';
    }
    if (_state.isEmpty) return 'Pick the state.';
    if (_city.isEmpty) return 'Pick the city or area.';
    if (_pin == null) return 'Drop a pin on the map so guests can find it.';
    if (!_hasPrice) return 'Set a nightly price.';
    return null;
  }

  /// Creates the property, unit and listing together, then offers to add
  /// photos straight away: the new place has none, and a listing without
  /// them is one guests scroll past.
  Future<void> _saveNewPlace() async {
    if (_newPlaceProblem case final problem?) {
      OasisToast.error(context, problem);
      return;
    }
    final pin = _pin!;
    final unitNumber = _unitNumberController.text.trim();
    final controller = context.read<ShortLetController>();
    final landlord = context.read<LandlordController>();
    final navigator = Navigator.of(context);

    final result = await controller.createHostListing(
      propertyName: _placeNameController.text.trim(),
      address: _addressController.text.trim(),
      city: _city,
      state: _state,
      latitude: pin.latitude,
      longitude: pin.longitude,
      // Optional for the host: a whole house has no flat number, and the
      // backend needs one, so it gets the plainest possible.
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
      description: _descriptionController.text.trim(),
      houseRules: _rulesController.text.trim(),
      checkInNotes: _checkInController.text.trim(),
    );
    if (!mounted) return;
    if (result == null) {
      OasisToast.error(
        context,
        controller.errorMessage ??
            'Could not list your place. Try again in a moment.',
      );
      return;
    }

    navigator.pop(true);
    // So the place shows under the host's properties, and the next listing
    // can be added to it, without waiting for the next refresh.
    unawaited(landlord.loadLandlordProperties());
    if (result.unitId.isEmpty) {
      OasisToast.success(
        navigator.context,
        'Your place is listed. Add photos to it from My places.',
      );
      return;
    }
    // Guests can see the place as soon as it exists, photos or not
    // (backend, 2026-10-23), so this comes straight away.
    OasisToast.success(
      navigator.context,
      'Your place is live. Add a few photos so guests can see it.',
    );
    await openUnitMediaSheet(
      navigator.context,
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
    );
    // The photos belong to the unit; the listing card reads them from there.
    await controller.loadLandlordListings();
  }

  /// Opens the state list, and clears a city that no longer belongs to it.
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

  /// Where the place is and what it is: the fields `POST /host/listings/`
  /// needs on top of the listing's own.
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
    Text(
      'Guests see this as the title of your listing.',
      style: AppTheme.labelText(
        context,
        color: AppTheme.secondaryTextColor(context),
      ),
    ),
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
    const SizedBox(height: 18),
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
  ];

  /// Closes this sheet and reopens it on the listing that already exists.
  ///
  /// The listing is refetched rather than guessed at: the local set is what
  /// missed the duplicate in the first place, so trusting it here would be
  /// trusting the thing that was already wrong.
  Future<void> _openExistingInstead(String listingId) async {
    // Captured before anything is awaited: this sheet is about to be popped
    // and its context goes with it.
    final navigator = Navigator.of(context);
    final controller = context.read<ShortLetController>();

    await controller.loadLandlordListings();
    if (!navigator.mounted) return;

    final existing = controller.listings
        .where((listing) => listing.id == listingId)
        .firstOrNull;
    navigator.pop(existing != null);
    if (existing == null) {
      // It exists server-side but did not come back in the list. Nothing to
      // open, so say what happened rather than silently doing nothing.
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ShortLetController>();
    final landlord = context.watch<LandlordController>();
    final units = _property == null
        ? const <UnitModel>[]
        : landlord.propertyUnits[_property!.id] ?? const <UnitModel>[];

    return OasisSheet(
      icon: Icons.holiday_village_outlined,
      title: isOasisV2
          ? (_isEditing ? 'Edit shortlet' : 'List a place')
          : (_isEditing ? 'Edit short let' : 'List for short stays'),
      subtitle: _isEditing
          ? widget.existing!.title
          : _newPlace
          ? 'Tell guests where it is and what it costs. You approve every '
                'booking before anyone pays.'
          : 'Offer a unit by the night. You approve every booking before '
                'anyone pays.',
      footer: OasisSheetButton(
        label: _isEditing ? 'Save changes' : 'List this place',
        icon: Icons.check_rounded,
        isLoading: controller.isSubmitting,
        onPressed: controller.isSubmitting || _duplicateListing != null
            ? null
            : _save,
      ),
      children: [
        // Only offered once there is something to pick: a new host goes
        // straight to the new-place fields.
        if (_canAddNewPlace && landlord.properties.isNotEmpty) ...[
          V2SegmentChips(
            labels: const ['A new place', 'One of my units'],
            selected: _newPlace ? 0 : 1,
            onSelected: (index) => setState(() => _newPlace = index == 0),
          ),
          const SizedBox(height: 18),
        ],
        if (_newPlace) ..._newPlaceFields(context),
        // The unit is fixed when editing, because the backend keys a listing
        // to its unit and changing it here would make a second listing.
        if (!_isEditing && !_newPlace) ...[
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
                  // Shown and disabled rather than filtered out. A host
                  // looking for flat A1 and not finding it would assume the
                  // app had lost it; seeing it greyed out as "already
                  // listed" tells them where it went.
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
          // The pre-selected case, which the dropdown cannot refuse: a unit
          // handed in by the add-property flow, or one listed on another
          // device since this list was fetched.
          if (_duplicateListing case final duplicate?) ...[
            const SizedBox(height: 8),
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
                    '${duplicate.title} is already let by the night. Edit '
                    'that listing from Short lets instead of adding a second '
                    'one.',
                    style: AppTheme.labelText(
                      context,
                      color: AppTheme.warningColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
        ],

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

        // The deposit. Optional for the host and compulsory for the guest
        // once set, which is why it is stated in both directions here: a
        // host needs to know they are adding to the bill, not asking a
        // favour.
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 15,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _hasCaution
                    ? 'Guests pay this on top of the nightly total and see it '
                          'as a separate line. Only this deposit is held and '
                          'returned after checkout unless you report damage.'
                    : 'Ask for a refundable deposit if you want cover for '
                          'damage. Most hosts leave this empty.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        OasisFieldLabel(
          'Cancellation policy',
          trailing: const _OptionalPill(label: 'Optional'),
        ),
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
        Text(
          '${_cancellationPolicy.defaultSummary} Oasis shows guests the '
          'terms before they request dates.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: _Stepper(
                label: 'Minimum nights',
                value: _minimumNights,
                min: 1,
                max: 30,
                onChanged: (value) => setState(() => _minimumNights = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Stepper(
                label: 'Sleeps up to',
                value: _maximumGuests,
                min: 1,
                max: 20,
                onChanged: (value) => setState(() => _maximumGuests = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        OasisFieldLabel(
          'Available between',
          trailing: _OptionalPill(
            label: _window == null ? 'Any dates' : 'Set',
            highlight: _window != null,
          ),
        ),
        InkWell(
          onTap: _pickWindow,
          borderRadius: AppTheme.cornerMd,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.subtleSurfaceColor(context),
              borderRadius: AppTheme.cornerMd,
              border: Border.all(color: AppTheme.borderColor(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 19,
                  color: AppTheme.mutedTextColor(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _window == null
                        ? 'Taking bookings any time'
                        : '${DateFormat('d MMM yyyy').format(_window!.start)} – '
                              '${DateFormat('d MMM yyyy').format(_window!.end)}',
                    style: _window == null
                        ? AppTheme.bodyText(
                            context,
                            color: AppTheme.mutedTextColor(context),
                          )
                        : AppTheme.cardTitle(context),
                  ),
                ),
                if (_window != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _window = null),
                    color: AppTheme.mutedTextColor(context),
                    tooltip: 'Take bookings any time',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _window == null
              ? 'Leave this alone and guests can ask for any dates. Set it if '
                    'the place is only free for part of the year.'
              : 'Guests can only ask for dates inside this window.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 18),

        // Placed before the rules and the arrival notes because it is the
        // only one of the three a guest reads while deciding. A stay with no
        // description gets browsed past, which is why the hint is a worked
        // example rather than "Description".
        OasisFieldLabel(
          'About this place',
          trailing: _OptionalPill(
            label: _hasDescription ? 'Added' : 'Recommended',
            highlight: _hasDescription,
          ),
        ),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          maxLength: _maxDescriptionLength,
          textCapitalization: TextCapitalization.sentences,
          style: AppTheme.bodyText(context),
          onChanged: (_) => setState(() {}),
          decoration: oasisInputDecoration(
            context,
            hint:
                'A quiet two-bedroom flat five minutes from the airport. '
                'Fast wifi, 24-hour power, parking in the compound.',
          ),
        ),
        Text(
          'Guests see this at the top of your listing. Say what the place is '
          'like and what is nearby.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
        const SizedBox(height: 18),

        const OasisFieldLabel('House rules'),
        TextField(
          controller: _rulesController,
          maxLines: 3,
          style: AppTheme.bodyText(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'No parties. Quiet after 10pm.',
          ),
        ),
        const SizedBox(height: 18),

        const OasisFieldLabel('Check-in notes'),
        TextField(
          controller: _checkInController,
          maxLines: 2,
          style: AppTheme.bodyText(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Gate code and key box details.',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppTheme.mutedTextColor(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Only shared with a guest once they have paid.',
                style: AppTheme.labelText(
                  context,
                  color: AppTheme.secondaryTextColor(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

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

        if (_hasPrice) ...[
          const SizedBox(height: 8),
          Text(
            _quoteLine,
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
        ],
      ],
    );
  }
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
///
/// A local copy rather than a shared widget, because the one in the
/// add-property sheet also carries a "required" state this sheet has no use
/// for: every field here is either set or genuinely fine left alone.
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
