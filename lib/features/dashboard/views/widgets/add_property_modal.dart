import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/nigeria_locations.dart';
import '../../../../core/widgets/oasis_place_picker.dart';
import '../../../../core/widgets/oasis_pressable.dart';
import '../../../../core/widgets/oasis_sheet.dart';
import '../../../../core/widgets/oasis_toast.dart';
import '../../../properties/controllers/landlord_controller.dart';
import '../../../properties/views/widgets/add_units_modal.dart';
import '../../../properties/models/property_model.dart';
import '../../../properties/services/geocoding_service.dart';
import '../../../properties/views/widgets/property_location_picker.dart';
import '../../../shortlets/views/create_shortlet_sheet.dart';
import 'move_in_tenants_modal.dart';

/// Whether the ownership walkthrough may be an existing video file rather
/// than one recorded on the spot.
///
/// **Temporary, and on for simulator testing.** The walkthrough is an
/// anti-fraud control: recording live is what ties whoever is claiming the
/// property to standing in front of it, and a file chosen from storage proves
/// only that somebody once had a video. An iOS simulator has no camera, so
/// with this off the add-property flow cannot be completed there at all.
///
/// Set to `false` before shipping. It is one line here and nothing else: the
/// record path is untouched and stays the default action on the tile.
const bool kAllowUploadedWalkthrough = true;

/// Adds a property, then continues straight into its units, then asks who
/// already lives in them.
///
/// One function rather than three call sites each chaining it themselves.
/// A property created here has no units yet, and the units sheet is also where
/// a landlord names the artisans they trust on them, so ending the property
/// form and dropping the landlord back on the dashboard left both undone, with
/// nothing on screen saying so. That is the bug this exists to prevent
/// recurring the next time somewhere new opens the property form.
///
/// The third step exists because most landlords arriving here are not opening
/// an empty building: they are moving one they already run onto Oasis, with
/// tenants in it and rent already collected. Left out, their first act would
/// be to list occupied flats as vacant, and the only way to correct it would
/// be to invite their own tenants to apply for the homes they live in.
///
/// Both steps after the property are normal dismissible sheets: a landlord who
/// would rather do it later closes them, and reaches them again from My
/// properties.
///
/// ## Why this holds a navigator rather than the caller's context
///
/// This is the longest-lived piece of UI in the app: five sheets, each one
/// awaited, with file uploads between them. It routinely outlives the screen
/// that started it, and it used to present every one of those sheets from the
/// dashboard's own `BuildContext`.
///
/// The dashboard does not reliably survive the flow. `MainScaffold` swaps its
/// entire body for the verification screen the moment the profile stops
/// reading VERIFIED, and every request this flow makes can come back
/// `403 VERIFICATION_REQUIRED`, which `ApiClient.onVerificationRequired`
/// routes straight into that swap. The dashboard element goes with it, and
/// the *next* `showModalBottomSheet` in the chain is handed a context whose
/// element is no longer in the tree. It dies inside the framework's own
/// ancestor lookup, before any of this code runs:
///
/// ```text
/// Null check operator used on a null value
/// #0  Element.widget            (framework.dart)
/// #1  debugCheckHasMediaQuery   (debug.dart)
/// #2  showModalBottomSheet      (bottom_sheet.dart)
/// #3  openAddPropertyFlow
/// ```
///
/// The same cause surfaces as *"Looking up a deactivated widget's ancestor is
/// unsafe"* when the element has only been deactivated and not yet unmounted.
/// Either way it lands at the last step, after the landlord has uploaded a
/// walkthrough and five photos.
///
/// Guarding on `context.mounted` does not help, that is what the code used
/// to do. It is false only once the element is fully unmounted, and the
/// window between deactivation and that point is where the assertion lives;
/// worse, the check passes at the top of an `await` and the swap happens
/// during it.
///
/// A [NavigatorState] is not in that subtree. It outlives every screen inside
/// it, which is exactly the lifetime this flow needs, so it is captured once,
/// here, and every sheet below is presented from it. Pinned by
/// `add_property_flow_test.dart`.
Future<void> openAddPropertyFlow(BuildContext context) async {
  final navigator = Navigator.of(context);

  // Asked before anything is typed, because it decides what is asked for.
  // A short-let host is not put through a deed they do not need, and a
  // landlord letting by the year is not asked for a nightly price.
  final purpose = await _askPropertyPurpose(navigator);
  if (purpose == null || !navigator.mounted) return;

  final property = await showModalBottomSheet<PropertyModel>(
    context: navigator.context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Sized inside the builder rather than through `constraints`, so the
    // measurement is taken against the sheet's own context. Measuring the
    // caller's would both re-introduce the dependency this flow exists to
    // avoid and quietly make the *dashboard* rebuild every time the keyboard
    // moves.
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints.tightFor(
        height: MediaQuery.sizeOf(sheetContext).height * 0.8,
      ),
      child: AddPropertyModal(purpose: purpose),
    ),
  );
  if (property == null || !navigator.mounted) return;

  final added = await AddUnitsModal.open(
    navigator.context,
    property,
    purpose: purpose,
  );
  // Nothing to list or move anyone into, so nothing left to ask about.
  if (added == null || added.units.isEmpty || !navigator.mounted) return;

  if (purpose.isShortLet) {
    // The third step for a short let is the listing itself: nightly price,
    // house rules, how many guests, which dates. Without it the host leaves
    // this flow with units nobody can book, and nothing on screen says so.
    await _listCreatedUnitsForShortStays(navigator, property, added);
    return;
  }

  final hasTenants = await _askAboutExistingTenants(
    navigator,
    added.units.length,
  );
  if (hasTenants != true || !navigator.mounted) return;
  await MoveInTenantsModal.open(navigator.context, property);
}

/// Yearly rent or short lets: the first question in the flow.
///
/// A sheet rather than a toggle inside the form: the answer changes which
/// fields exist, and a control that rewrites the form under the landlord's
/// hands halfway through filling it in is worse than one clear question up
/// front. Returns null when they backed out.
Future<PropertyPurpose?> _askPropertyPurpose(NavigatorState navigator) =>
    showModalBottomSheet<PropertyPurpose>(
      context: navigator.context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => OasisSheet(
        icon: Icons.help_outline_rounded,
        title: 'What are you listing this for?',
        subtitle:
            'The two work differently, and Oasis asks for different things '
            'for each. You can add another property for the other kind any '
            'time.',
        children: [
          for (final purpose in PropertyPurpose.values) ...[
            _PurposeTile(
              purpose: purpose,
              onTap: () => Navigator.pop(sheetContext, purpose),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );

/// Walks the host through listing each unit they just created for nightly
/// stays.
///
/// One sheet per unit, in order, and each one is skippable: a host who adds
/// six flats and lists two of them tonight has done nothing wrong, and the
/// rest are still reachable from Short lets. The nightly price they typed on
/// the unit is carried in, so the number is asked for once.
Future<void> _listCreatedUnitsForShortStays(
  NavigatorState navigator,
  PropertyModel property,
  AddUnitsResult added,
) async {
  for (final unit in added.units) {
    if (!navigator.mounted) return;
    final listed = await openCreateShortLetSheet(
      navigator.context,
      initialProperty: property,
      initialUnit: unit,
      initialNightlyPrice: added.nightlyPrices[unit.id],
    );
    // Backing out of one unit's listing ends the run rather than asking about
    // the next five. The host has said what they came to say.
    if (!listed) return;
  }
}

/// Asks whether anybody already lives in the units just created.
///
/// A question rather than a fourth form pushed at everyone: a landlord listing
/// a newly built block would have to dismiss a tenant sheet they never wanted,
/// and one with a full building would otherwise never learn the step exists.
Future<bool?> _askAboutExistingTenants(
  NavigatorState navigator,
  int unitCount,
) => showModalBottomSheet<bool>(
  context: navigator.context,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => OasisSheet(
    icon: Icons.groups_2_outlined,
    title: 'Anyone living here already?',
    subtitle:
        'You added $unitCount unit${unitCount == 1 ? '' : 's'}. If tenants are '
        'already in ${unitCount == 1 ? 'it' : 'some of them'}, record them now '
        'so their agreements start from the day they really moved in.',
    footer: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OasisSheetButton(
          label: 'Yes, add my tenants',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => Navigator.pop(sheetContext, true),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(sheetContext, false),
          child: Text(
            'No, these are all vacant',
            style: AppTheme.bodyText(
              sheetContext,
              color: AppTheme.secondaryTextColor(sheetContext),
            ),
          ),
        ),
      ],
    ),
    children: const [],
  ),
);

class AddPropertyModal extends StatefulWidget {
  /// What the landlord said they are listing for. Decides whether proof of
  /// ownership is asked for, and what the sheet says it is collecting.
  final PropertyPurpose purpose;

  const AddPropertyModal({
    super.key,
    this.purpose = PropertyPurpose.yearlyRent,
  });

  @override
  State<AddPropertyModal> createState() => _AddPropertyModalState();
}

class _AddPropertyModalState extends State<AddPropertyModal> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  /// Both blank on purpose.
  ///
  /// The city box used to arrive prefilled with 'Lagos', which is not a city
  /// anybody writes on a Nigerian address: they write Ikeja, Lekki, Yaba. The
  /// state box kept 'Lagos' longer, on the argument that most early landlords
  /// are there — and testers in Abuja had to clear it before they could type
  /// their own, on a form where a prefilled box reads as answered. A default
  /// that is right for some people and silently wrong for the rest is worse
  /// than an empty box, because the empty box gets filled in.
  ///
  /// Both are filled *automatically* now, from whatever the pin resolves to,
  /// which is the answer testers actually wanted.
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();

  /// Whether the pin has filled a box in for the landlord.
  ///
  /// Tracked so the map can keep correcting its own guesses — dragging the
  /// pin from Yaba to Ikeja should move the city with it — while never
  /// touching a value the landlord typed themselves. Typing into a field
  /// clears its flag and the map stops writing to it.
  bool _cityFromPin = false;
  bool _stateFromPin = false;
  bool _addressFromPin = false;

  /// Set for a moment after the pin fills something in, so the form can say
  /// which boxes it just wrote to. A form that silently rearranges itself
  /// while you are looking at the map is unnerving.
  bool _showAutofillNote = false;

  final _picker = ImagePicker();
  final List<File> _photos = [];
  File? _verificationVideo;
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
        OasisToast.error(context, 'Unable to select photos: $error');
      }
    }
  }

  /// The walkthrough step. Records live, or, while
  /// [kAllowUploadedWalkthrough] is on: offers an existing file instead.
  Future<void> _addVerificationVideo() async {
    if (!kAllowUploadedWalkthrough) {
      await _recordVerificationVideo();
      return;
    }

    final recordLive = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => OasisSheet(
        icon: Icons.videocam_outlined,
        title: 'Add your walkthrough',
        subtitle:
            'Recording on the spot is what verification is checking for. '
            'Choosing a file is for testing on a simulator, which has no '
            'camera.',
        children: [
          OasisSheetChipButton(
            icon: Icons.fiber_manual_record_rounded,
            label: 'Record now',
            onTap: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: 10),
          OasisSheetChipButton(
            icon: Icons.folder_open_outlined,
            label: 'Choose a video file',
            onTap: () => Navigator.pop(sheetContext, false),
          ),
        ],
      ),
    );
    if (recordLive == null || !mounted) return;

    if (recordLive) {
      await _recordVerificationVideo();
      return;
    }
    final file = await _pickVideoFile();
    if (file != null && mounted) {
      setState(() => _verificationVideo = file);
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
        OasisToast.error(context, 'Unable to record video: $error');
      }
    }
  }

  /// Picks a video off the device, size-checked. Null when the landlord backed
  /// out or the file was refused: the caller decides what it was for.
  Future<File?> _pickVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: PropertyMediaLimits.videoExtensions,
      );
      final path = result?.files.single.path;
      if (path == null || !mounted) return null;

      final file = File(path);
      if (await file.length() > PropertyMediaLimits.maxVideoBytes) {
        if (mounted) {
          OasisToast.error(
            context,
            'Video must not exceed 50MB. Choose a shorter clip.',
          );
        }
        return null;
      }
      return file;
    } catch (error) {
      if (mounted) {
        OasisToast.error(context, 'Unable to select video: $error');
      }
      return null;
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
        OasisToast.error(context, 'Unable to select deed: $error');
      }
    }
  }

  /// Whether enough photos are attached for the listing to be accepted.
  bool get _hasEnoughPhotos => _photos.length >= PropertyMediaLimits.minPhotos;

  /// Whether this property is being added for nightly stays.
  bool get _isShortLet => widget.purpose.isShortLet;

  /// Whether proof of ownership is part of this submission.
  ///
  /// Only for a yearly let. A deed underwrites a tenancy: a document that
  /// binds somebody to a home for a year, where a forged claim costs a family
  /// their savings. A guest booking three nights signs nothing, pays into
  /// escrow and leaves, and the live walkthrough already ties the host to the
  /// building. Asking a short-let host for a land title is asking for
  /// paperwork most of them do not have for a risk their booking does not
  /// carry.
  bool get _needsDeed => !_isShortLet;

  /// Whether the ownership evidence for this property is complete.
  bool get _hasOwnershipEvidence =>
      _verificationVideo != null && (!_needsDeed || _deed != null);

  /// Writes whatever the pin resolved to into the boxes that are still the
  /// app's to write.
  ///
  /// The rule is one sentence: **the landlord always wins**. A field is
  /// filled when it is empty, or when the last thing in it also came from the
  /// pin — so nudging the pin down the street keeps the city in step — and is
  /// left completely alone once they have typed in it themselves. Getting
  /// this wrong in the other direction is the worse bug: a form that
  /// overwrites a carefully typed address every time the map settles is one
  /// nobody can complete.
  void _applyResolvedAddress(GeocodeAddress address) {
    if (!mounted) return;
    var changed = false;

    void fill(
      TextEditingController controller,
      String? value,
      bool fromPin,
      void Function(bool) mark,
    ) {
      final incoming = value?.trim() ?? '';
      if (incoming.isEmpty) return;
      final current = controller.text.trim();
      if (current.isNotEmpty && !fromPin) return;
      if (current == incoming) return;
      controller.text = incoming;
      mark(true);
      changed = true;
    }

    fill(
      _addressCtrl,
      address.addressLine,
      _addressFromPin,
      (v) => _addressFromPin = v,
    );
    fill(_cityCtrl, address.city, _cityFromPin, (v) => _cityFromPin = v);
    fill(_stateCtrl, address.state, _stateFromPin, (v) => _stateFromPin = v);

    if (changed) setState(() => _showAutofillNote = true);
  }

  /// Opens the state list, then clears a city that no longer belongs to it.
  ///
  /// Changing state with "Lekki" left in the city box is how a Rivers
  /// property ends up advertised in a Lagos suburb, so the stale city goes
  /// rather than being carried across.
  Future<void> _pickState() async {
    final picked = await openStatePicker(context, selected: _stateCtrl.text);
    if (picked == null || !mounted) return;
    final cityStillValid =
        _cityCtrl.text.trim().isEmpty ||
        NigeriaLocations.canonicalCity(state: picked, city: _cityCtrl.text) !=
            null;
    setState(() {
      _stateCtrl.text = picked;
      _stateFromPin = false;
      if (!cityStillValid) {
        _cityCtrl.clear();
        _cityFromPin = false;
      }
    });
  }

  Future<void> _pickCity() async {
    final picked = await openCityPicker(
      context,
      state: _stateCtrl.text,
      selected: _cityCtrl.text,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _cityCtrl.text = picked;
      _cityFromPin = false;
    });
  }

  /// The street line the landlord has typed, for the pin map's lookup.
  ///
  /// City and state reach the picker as their own fields now. Joining them
  /// in here as well would send Nominatim "Kolapo Ishola, Ibadan, Oyo,
  /// Ibadan, Oyo", and the progressive lookup adds them back at the level
  /// that needs them.
  String _streetQuery() => _addressCtrl.text.trim();

  /// The one thing still standing between this form and a submission, or null
  /// when it is ready.
  ///
  /// Read by the footer as well as by [_submitProperty], which is the point:
  /// this form asks for a pin, five files and a video, and telling somebody
  /// which field is wrong only *after* they have pressed the button, at the
  /// end of the longest form in the app, is the least useful moment to say
  /// it. The blocker is now on screen the whole way down.
  String? get _problem {
    if (_nameCtrl.text.trim().isEmpty) return 'Give the property a name.';
    if (_addressCtrl.text.trim().isEmpty) return 'Enter the street address.';
    // Both are required by `POST /properties/`. Checked here because the
    // alternative is uploading five files and a video to be told no: the
    // request that used to fail on this carried the whole evidence bundle.
    if (_cityCtrl.text.trim().isEmpty) return 'Enter the city.';
    if (_stateCtrl.text.trim().isEmpty) return 'Enter the state.';
    if (_pin == null) return 'Drop a pin on the property location.';
    if (_photos.length < PropertyMediaLimits.minPhotos) {
      final need = PropertyMediaLimits.minPhotos - _photos.length;
      return _photos.isEmpty
          ? 'Add at least ${PropertyMediaLimits.minPhotos} photos of the '
                'property.'
          : '$need more ${need == 1 ? 'photo' : 'photos'} of the property.';
    }
    if (_verificationVideo == null) {
      return 'Record the live walkthrough. It is what verifies the property.';
    }
    if (_needsDeed && _deed == null) {
      return 'Attach the deed or proof of ownership.';
    }
    return null;
  }

  Future<void> _submitProperty() async {
    final problem = _problem;
    if (problem != null) {
      OasisToast.error(context, problem);
      return;
    }
    final name = _nameCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final state = _stateCtrl.text.trim();
    setState(() => _isSubmitting = true);
    final property = await context.read<LandlordController>().createProperty(
      name: name,
      address: address,
      city: city,
      state: state,
      latitude: _pin!.latitude,
      longitude: _pin!.longitude,
      photos: _photos,
      verificationVideo: _verificationVideo!,
      // Null for a short let, and the service leaves the part out entirely.
      deedFile: _deed,
    );
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    if (property == null) {
      OasisToast.error(
        context,
        context.read<LandlordController>().errorMessage ??
            'Could not submit property.',
      );
      return;
    }
    // Handed back so the caller can carry straight on into the units sheet.
    Navigator.pop(context, property);
    OasisToast.success(context, '${property.name} submitted for verification.');
  }

  @override
  Widget build(BuildContext context) {
    return OasisSheet(
      icon: Icons.add_location_alt_rounded,
      title: _isShortLet ? 'Add a place for stays' : 'Add verified property',
      subtitle: _isShortLet
          ? 'Pin the place and record a live walkthrough. You add the units '
                'next, with photos and a tour video for each, then set your '
                'nightly price and house rules.'
          : 'Pin the property, record a live walkthrough and attach proof of '
                'ownership. You add the units next, with a tour video for '
                'each.',
      accent: AppTheme.primaryColor,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Named above the button rather than behind a tap on it, and
          // updated as they type: the same pattern the units sheet already
          // uses. A disabled button that will not say why is what this form
          // used to do.
          if (_problem case final problem? when !_isSubmitting) ...[
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
                    problem,
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
          OasisSheetButton(
            label: 'Submit property for review',
            icon: Icons.verified_outlined,
            color: AppTheme.primaryColor,
            isLoading: _isSubmitting,
            onPressed: _problem == null ? _submitProperty : null,
          ),
        ],
      ),
      children: [
        const OasisFieldLabel('Property details'),
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          // Rebuilds the footer's blocker line as they type, so it tracks
          // what is actually filled in rather than what was filled in last
          // time something else changed.
          onChanged: (_) => setState(() {}),
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Property name',
            prefixIcon: Icons.home_work_outlined,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressCtrl,
          textCapitalization: TextCapitalization.words,
          // Typing here hands the field back to the landlord: the pin stops
          // writing to it from this point on.
          onChanged: (_) => setState(() => _addressFromPin = false),
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Street address',
            prefixIcon: Icons.signpost_outlined,
          ),
        ),
        const SizedBox(height: 12),
        // Pickers rather than text boxes. Both feed the marketplace's own
        // city/state filter, which matches strings: a landlord who writes
        // "lagos state" and a tenant who writes "Lagos" are searching two
        // different places, and one list on both sides is what stops that.
        Row(
          children: [
            Expanded(
              child: OasisPickerField(
                value: _stateCtrl.text,
                hint: 'State',
                prefixIcon: Icons.map_outlined,
                onTap: _pickState,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OasisPickerField(
                value: _cityCtrl.text,
                hint: 'City / area',
                prefixIcon: Icons.location_city_rounded,
                onTap: _pickCity,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        PropertyLocationPicker(
          // The map follows the town the landlord picked above. Without
          // these it opened on Lagos whatever they chose, and an estate
          // Nominatim has never heard of left them stranded there.
          city: _cityCtrl.text,
          state: _stateCtrl.text,
          onChanged: (pin) => setState(() => _pin = pin),
          addressResolver: _streetQuery,
          onAddressResolved: _applyResolvedAddress,
        ),
        // Said out loud, and only once something was actually written: the
        // three boxes above are off screen by the time the pin settles, and a
        // landlord who scrolls back to find them already filled in should
        // know why rather than wonder what else the app decided for them.
        if (_showAutofillNote) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: AppTheme.successColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Address, city and state filled in from the pin. Scroll up '
                  'to change any of them.',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.successColor,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),

        OasisFieldLabel(
          'Property photos',
          trailing: _OptionalTag(
            label: _hasEnoughPhotos ? '${_photos.length} added' : 'Required',
            highlight: _hasEnoughPhotos,
            required: !_hasEnoughPhotos,
          ),
        ),
        // A listing with nothing to look at is not a listing: the backend
        // rejects it, and a property with no photos is hidden from the
        // marketplace. Say so here rather than letting the landlord fill in
        // the whole sheet and collect a 422 at the end.
        if (!_hasEnoughPhotos) ...[
          const SizedBox(height: 6),
          Text(
            _photos.isEmpty
                ? 'Add at least ${PropertyMediaLimits.minPhotos} photos. '
                      'Listings without them are not shown to tenants.'
                : 'One more photo needed.',
            style: AppTheme.labelText(
              context,
              color: AppTheme.secondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 10),
        ],
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
                    child: OasisPressable(
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
              child: OasisSheetChipButton(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                onTap: () => _pickPhotos(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OasisSheetChipButton(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () => _pickPhotos(ImageSource.gallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        OasisFieldLabel(
          'Live ownership check',
          trailing: _OptionalTag(
            label: _hasOwnershipEvidence ? 'Complete' : 'Required',
            highlight: _hasOwnershipEvidence,
            required: !_hasOwnershipEvidence,
          ),
        ),
        _EvidenceTile(
          icon: Icons.videocam_outlined,
          title: _verificationVideo == null
              ? (kAllowUploadedWalkthrough
                    ? 'Add live walkthrough'
                    : 'Record live walkthrough')
              : 'Live walkthrough added',
          subtitle: _verificationVideo == null
              ? 'Up to 60 seconds showing the exterior and your presence.'
              : _verificationVideo!.path.split('/').last,
          action: _verificationVideo == null
              ? (kAllowUploadedWalkthrough ? 'Add' : 'Record')
              : 'Redo',
          onTap: _addVerificationVideo,
          complete: _verificationVideo != null,
        ),
        // Proof of ownership, for a yearly let only. Said out loud in the
        // short-let case rather than silently dropped: a host who has read
        // about the deed elsewhere, or who is adding their second property,
        // would otherwise be looking for a step that is deliberately not
        // there.
        if (_needsDeed) ...[
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
        ] else ...[
          const SizedBox(height: 8),
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
                  'No deed needed for short stays. The live walkthrough is '
                  'the check. Guests book by the night and sign nothing.',
                  style: AppTheme.labelText(
                    context,
                    color: AppTheme.secondaryTextColor(context),
                  ),
                ),
              ),
            ],
          ),
        ],
        // No "tour videos come next" panel here any more. It was a note
        // explaining that the property-tour video had moved onto each unit —
        // useful to a landlord who remembered the old form, and dead weight
        // to everybody else, sitting directly above a footer that already
        // says what the next step is. The sheet's own subtitle carries the
        // same fact in one line.
      ],
    );
  }
}

/// One answer to the opening question, as a full-width tile.
///
/// Tiles rather than a segmented control because each option needs a line of
/// explanation: a landlord who has only ever let by the year does not know
/// what Oasis means by a short let, and picking the wrong one costs them the
/// whole form.
class _PurposeTile extends StatelessWidget {
  final PropertyPurpose purpose;
  final VoidCallback onTap;

  const _PurposeTile({required this.purpose, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = purpose.isShortLet
        ? AppTheme.vacantColor
        : AppTheme.actionColor;
    return OasisPressable(
      onTap: onTap,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.subtleSurfaceColor(context),
          borderRadius: AppTheme.cornerMd,
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: AppTheme.cornerSm,
              ),
              child: Icon(
                purpose.isShortLet
                    ? Icons.holiday_village_outlined
                    : Icons.calendar_month_outlined,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(purpose.label, style: AppTheme.cardTitle(context)),
                  const SizedBox(height: 3),
                  Text(
                    purpose.blurb,
                    style: AppTheme.bodyText(
                      context,
                      color: AppTheme.secondaryTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 20, color: accent),
          ],
        ),
      ),
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
    return OasisPressable(
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
