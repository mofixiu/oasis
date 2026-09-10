import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_pressable.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../controllers/fix_controller.dart';
import '../models/fix_models.dart';

/// Lets an artisan edit the profile tenants browse: their trade, where they
/// work, how long they have been at it, and a line about themselves.
///
/// Returns true when something was saved.
Future<bool> openArtisanProfileSheet(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ArtisanProfileSheet(),
  );
  return saved ?? false;
}

class _ArtisanProfileSheet extends StatefulWidget {
  const _ArtisanProfileSheet();

  @override
  State<_ArtisanProfileSheet> createState() => _ArtisanProfileSheetState();
}

class _ArtisanProfileSheetState extends State<_ArtisanProfileSheet> {
  late final FixController _controller = context.read<FixController>();

  late final TextEditingController _location;
  late final TextEditingController _bio;
  late final TextEditingController _experience;
  late String _category;

  @override
  void initState() {
    super.initState();
    final profile = _controller.myProfile;
    _location = TextEditingController(text: profile?.location ?? '');
    _bio = TextEditingController(text: profile?.bio ?? '');
    _experience = TextEditingController(
      text: (profile?.yearsOfExperience ?? 0) > 0
          ? '${profile!.yearsOfExperience}'
          : '',
    );
    _category = profile?.category.isNotEmpty == true
        ? profile!.category
        : (_controller.categories.isEmpty
              ? ArtisanCategory.defaults.first.value
              : _controller.categories.first.value);
  }

  @override
  void dispose() {
    _location.dispose();
    _bio.dispose();
    _experience.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final location = _location.text.trim();
    if (location.isEmpty) {
      OasisToast.error(context, 'Tell tenants where you work.');
      return;
    }

    final typed = _experience.text.trim();
    final experience = typed.isEmpty ? 0 : int.tryParse(typed);
    if (experience == null || experience < 0) {
      OasisToast.error(context, 'Years of experience must be a whole number.');
      return;
    }

    final saved = await _controller.updateMyArtisanProfile(
      category: _category,
      location: location,
      bio: _bio.text,
      yearsOfExperience: experience,
    );
    if (!mounted) return;

    if (!saved) {
      OasisToast.error(
        context,
        _controller.errorMessage ??
            'Could not save that. Try again in a moment.',
      );
      return;
    }
    Navigator.pop(context, true);
    OasisToast.success(context, 'Profile updated.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<FixController>();
    final categories = controller.categories.isEmpty
        ? ArtisanCategory.defaults
        : controller.categories;

    return OasisSheet(
      icon: Icons.tune_rounded,
      title: 'Your trade',
      subtitle: 'What tenants see when they are choosing an artisan.',
      footer: OasisSheetButton(
        label: 'Save',
        icon: Icons.check_rounded,
        isLoading: controller.isSubmitting,
        onPressed: controller.isSubmitting ? null : _save,
      ),
      children: [
        const OasisFieldLabel('Trade'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in categories)
              _CategoryChip(
                label: category.label,
                selected: category.value == _category,
                onTap: () => setState(() => _category = category.value),
              ),
          ],
        ),
        const SizedBox(height: 24),

        const OasisFieldLabel('Where you work'),
        TextField(
          controller: _location,
          textCapitalization: TextCapitalization.words,
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Lekki Phase 1',
            prefixIcon: Icons.place_outlined,
          ),
        ),
        const SizedBox(height: 20),

        const OasisFieldLabel('Years of experience'),
        TextField(
          controller: _experience,
          keyboardType: TextInputType.number,
          style: AppTheme.cardTitle(context),
          decoration: oasisInputDecoration(
            context,
            hint: '5',
            prefixIcon: Icons.workspace_premium_outlined,
          ),
        ),
        const SizedBox(height: 20),

        const OasisFieldLabel('About you'),
        TextField(
          controller: _bio,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          style: AppTheme.bodyText(
            context,
            color: AppTheme.readingTextColor(context),
          ),
          decoration: oasisInputDecoration(
            context,
            hint: 'Reliable plumber for home repairs.',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'A tenant reads this before letting you into their home, so a line '
          'about what you do and how long you have done it goes a long way.',
          style: AppTheme.labelText(
            context,
            color: AppTheme.secondaryTextColor(context),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OasisPressable(
    onTap: onTap,
    pressedScale: 0.96,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.actionColor.withValues(alpha: 0.12)
            : AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerSm,
        border: Border.all(
          color: selected
              ? AppTheme.actionColor
              : AppTheme.borderColor(context),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.cardTitle(
          context,
          color: selected
              ? AppTheme.actionColor
              : AppTheme.secondaryTextColor(context),
        ).copyWith(fontSize: AppTheme.textSm),
      ),
    ),
  );
}
