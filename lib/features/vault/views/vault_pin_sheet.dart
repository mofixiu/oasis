import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../controllers/vault_controller.dart';
import '../models/vault_models.dart';
import 'widgets/vault_pin_field.dart';
import '../../../core/widgets/oasis_busy.dart';

/// Asks for the vault PIN before money leaves the vault, and returns it.
///
/// Returns null when the user backed out, could not get in, or has no PIN and
/// declined to create one, so a caller can treat null as "do not spend" with
/// no further checks.
///
/// The PIN is handed back rather than kept anywhere: it goes straight into the
/// one request that needs it and is never stored, cached, or logged. Holding
/// it on a controller "for the next action" would quietly turn a per-action
/// confirmation into a session-long one.
///
/// The sheet resolves all three states itself: no PIN yet, locked out, ready
/// to enter, rather than bouncing the user between sheets to find out which
/// one they are in.
Future<String?> promptVaultPin(
  BuildContext context, {
  required String title,
  required String subtitle,
  String actionLabel = 'Confirm',
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _VaultPinSheet(
    title: title,
    subtitle: subtitle,
    actionLabel: actionLabel,
  ),
);

/// Opens the PIN from settings, to create one or change the existing one.
///
/// Returns true when the PIN was saved. Shares the create form with
/// [promptVaultPin] so the rules a user learns in one place hold in the other.
Future<bool> openVaultPinManager(BuildContext context) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _VaultPinManagerSheet(),
  );
  return saved ?? false;
}

/// What the prompt is currently asking for.
enum _PromptStage { loading, unavailable, create, locked, enter }

class _VaultPinSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String actionLabel;

  const _VaultPinSheet({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
  });

  @override
  State<_VaultPinSheet> createState() => _VaultPinSheetState();
}

class _VaultPinSheetState extends State<_VaultPinSheet> {
  final _passwordController = TextEditingController();

  String _pin = '';
  String _newPin = '';
  String _confirmPin = '';
  bool _obscurePassword = true;

  /// True until the first PIN status read settles. Kept locally rather than
  /// read from the controller so the sheet shows its own first-load state
  /// without inheriting a spinner from whatever the vault screen is doing.
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPin());
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkPin() async {
    // Always re-read. A lock lifts on a timer and a PIN may have been created
    // on another device, so a status cached earlier in the session can send
    // the user to the wrong form.
    await context.read<VaultController>().loadPinStatus();
    if (mounted) setState(() => _checking = false);
  }

  _PromptStage _stage(VaultController controller) {
    if (_checking) return _PromptStage.loading;
    final status = controller.pinStatus;
    // Status unknown means the check itself failed: offering a PIN entry that
    // cannot be judged would waste one of five attempts on a network fault.
    if (status == null) return _PromptStage.unavailable;
    if (!status.isSet) return _PromptStage.create;
    if (status.isLocked) return _PromptStage.locked;
    return _PromptStage.enter;
  }

  void _submitExisting() {
    if (!isValidVaultPin(_pin)) return;
    Navigator.pop(context, _pin);
  }

  Future<void> _createAndContinue() async {
    final controller = context.read<VaultController>();

    if (_passwordController.text.isEmpty) {
      OasisToast.error(context, 'Enter your account password.');
      return;
    }
    if (!isValidVaultPin(_newPin)) {
      OasisToast.error(context, 'Your PIN must be 4 digits.');
      return;
    }
    if (_newPin != _confirmPin) {
      OasisToast.error(context, 'Those two PINs do not match.');
      return;
    }

    final created = await controller.createPin(
      password: _passwordController.text,
      pin: _newPin,
    );
    if (!mounted) return;

    if (!created) {
      OasisToast.error(
        context,
        controller.errorMessage ?? 'Could not save that PIN. Try again.',
      );
      return;
    }

    // They typed it a moment ago and confirmed it. Asking for it again here
    // would be ceremony, not security.
    Navigator.pop(context, _newPin);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final status = controller.pinStatus;
    final stage = _stage(controller);

    return OasisSheet(
      icon: stage == _PromptStage.locked
          ? Icons.lock_clock_outlined
          : Icons.lock_outline_rounded,
      title: stage == _PromptStage.create
          ? 'Create your vault PIN'
          : widget.title,
      subtitle: switch (stage) {
        _PromptStage.create =>
          'Before money can leave your vault, set a 4-digit PIN. You will '
              'enter it every time.',
        _PromptStage.locked => 'PIN entry is paused for now.',
        _PromptStage.unavailable =>
          'We could not check your vault PIN just now.',
        _ => widget.subtitle,
      },
      accent: stage == _PromptStage.locked
          ? AppTheme.disputeColor
          : AppTheme.actionColor,
      footer: switch (stage) {
        _PromptStage.loading => null,
        _PromptStage.unavailable => OasisSheetButton(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: () {
            setState(() => _checking = true);
            _checkPin();
          },
        ),
        _PromptStage.locked => OasisSheetButton(
          label: 'Close',
          onPressed: () => Navigator.pop(context),
          color: AppTheme.disputeColor,
        ),
        _PromptStage.create => OasisSheetButton(
          label: 'Create PIN and continue',
          icon: Icons.lock_outline_rounded,
          isLoading: controller.isSavingPin,
          onPressed: controller.isSavingPin ? null : _createAndContinue,
        ),
        _PromptStage.enter => OasisSheetButton(
          label: widget.actionLabel,
          icon: Icons.check_rounded,
          onPressed: isValidVaultPin(_pin) ? _submitExisting : null,
        ),
      },
      children: switch (stage) {
        _PromptStage.loading => const [_CheckingPin()],
        _PromptStage.unavailable => const [
          VaultPinNotice(
            icon: Icons.wifi_off_rounded,
            message:
                'Your PIN could not be checked, so nothing has been sent. '
                'Try again in a moment.',
          ),
        ],
        _PromptStage.locked => [
          VaultPinNotice(
            icon: Icons.lock_clock_outlined,
            tone: AppTheme.disputeColor,
            message:
                status?.lockMessage ??
                'Too many wrong PINs. Try again in a few minutes.',
          ),
          const SizedBox(height: 10),
          const VaultPinNotice(
            icon: Icons.shield_outlined,
            message:
                'Your money is untouched. The pause only stops the PIN being '
                'guessed.',
          ),
        ],
        _PromptStage.create => _createFields(controller),
        _PromptStage.enter => _enterFields(status),
      },
    );
  }

  List<Widget> _enterFields(VaultPinStatus? status) => [
    const OasisFieldLabel('Vault PIN'),
    VaultPinField(
      onChanged: (value) => setState(() => _pin = value),
      onCompleted: (_) => _submitExisting(),
    ),
    const SizedBox(height: 16),
    // Only warn when the count is genuinely low. "5 tries left" on a first
    // attempt reads as an accusation.
    if (status != null && status.isRunningOutOfAttempts)
      VaultPinNotice(
        icon: Icons.warning_amber_rounded,
        tone: AppTheme.warningColor,
        message:
            '${status.attemptsRemaining} '
            '${status.attemptsRemaining == 1 ? 'try' : 'tries'} left before '
            'your vault locks for 15 minutes.',
      )
    else
      const VaultPinNotice(
        icon: Icons.shield_outlined,
        message:
            'Your PIN is asked for every time money leaves your vault, even '
            'on this phone.',
      ),
  ];

  List<Widget> _createFields(VaultController controller) => [
    const OasisFieldLabel('Account password'),
    TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      enableSuggestions: false,
      autocorrect: false,
      style: AppTheme.bodyText(context),
      decoration: oasisInputDecoration(
        context,
        hint: 'Your Oasis password',
        prefixIcon: Icons.key_outlined,
        suffix: IconButton(
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 19,
            color: AppTheme.mutedTextColor(context),
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
    ),
    const SizedBox(height: 20),

    const OasisFieldLabel('Choose a 4-digit PIN'),
    VaultPinField(
      autofocus: false,
      onChanged: (value) => setState(() => _newPin = value),
    ),
    const SizedBox(height: 20),

    const OasisFieldLabel('Enter it again'),
    VaultPinField(
      autofocus: false,
      hasError: _confirmPin.length == 4 && _confirmPin != _newPin,
      onChanged: (value) => setState(() => _confirmPin = value),
    ),
    const SizedBox(height: 16),

    const VaultPinNotice(
      icon: Icons.shield_outlined,
      message:
          'Pick something you will remember. There is no way to reset a '
          'forgotten vault PIN yet. You would need support to help.',
    ),
  ];
}

/// Creates or changes the PIN from settings.
///
/// Separate from the prompt because the intent is different: nothing is
/// waiting on it, so it ends in a saved PIN rather than a spend.
class _VaultPinManagerSheet extends StatefulWidget {
  const _VaultPinManagerSheet();

  @override
  State<_VaultPinManagerSheet> createState() => _VaultPinManagerSheetState();
}

class _VaultPinManagerSheetState extends State<_VaultPinManagerSheet> {
  final _passwordController = TextEditingController();

  String _currentPin = '';
  String _newPin = '';
  String _confirmPin = '';
  bool _obscurePassword = true;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<VaultController>().loadPinStatus();
      if (mounted) setState(() => _checking = false);
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save({required bool isChange}) async {
    final controller = context.read<VaultController>();

    if (_passwordController.text.isEmpty) {
      OasisToast.error(context, 'Enter your account password.');
      return;
    }
    if (isChange && !isValidVaultPin(_currentPin)) {
      OasisToast.error(context, 'Enter your current 4-digit PIN.');
      return;
    }
    if (!isValidVaultPin(_newPin)) {
      OasisToast.error(context, 'Your new PIN must be 4 digits.');
      return;
    }
    if (_newPin != _confirmPin) {
      OasisToast.error(context, 'Those two PINs do not match.');
      return;
    }

    final saved = isChange
        ? await controller.changePin(
            password: _passwordController.text,
            currentPin: _currentPin,
            newPin: _newPin,
          )
        : await controller.createPin(
            password: _passwordController.text,
            pin: _newPin,
          );
    if (!mounted) return;

    if (!saved) {
      OasisToast.error(
        context,
        controller.errorMessage ?? 'Could not save that PIN. Try again.',
      );
      return;
    }

    Navigator.pop(context, true);
    OasisToast.success(
      context,
      isChange ? 'Vault PIN changed.' : 'Vault PIN created.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final status = controller.pinStatus;
    final isChange = status?.isSet ?? false;
    final isLocked = status?.isLocked ?? false;

    if (_checking) {
      return const OasisSheet(
        icon: Icons.lock_outline_rounded,
        title: 'Vault PIN',
        subtitle: 'Checking your vault PIN.',
        children: [_CheckingPin()],
      );
    }

    return OasisSheet(
      icon: Icons.lock_outline_rounded,
      title: isChange ? 'Change vault PIN' : 'Create vault PIN',
      subtitle: isChange
          ? 'You will need your password and the PIN you use now.'
          : 'A 4-digit PIN guards every withdrawal and vault payment.',
      footer: OasisSheetButton(
        label: isChange ? 'Change PIN' : 'Create PIN',
        icon: Icons.lock_outline_rounded,
        isLoading: controller.isSavingPin,
        // A locked vault refuses the current PIN too, so changing it now would
        // spend an attempt for nothing.
        onPressed: controller.isSavingPin || (isChange && isLocked)
            ? null
            : () => _save(isChange: isChange),
      ),
      children: [
        if (isChange && isLocked) ...[
          VaultPinNotice(
            icon: Icons.lock_clock_outlined,
            tone: AppTheme.disputeColor,
            message:
                status?.lockMessage ??
                'Too many wrong PINs. Try again in a few minutes.',
          ),
          const SizedBox(height: 20),
        ],

        const OasisFieldLabel('Account password'),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          enableSuggestions: false,
          autocorrect: false,
          enabled: !(isChange && isLocked),
          style: AppTheme.bodyText(context),
          decoration: oasisInputDecoration(
            context,
            hint: 'Your Oasis password',
            prefixIcon: Icons.key_outlined,
            suffix: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 19,
                color: AppTheme.mutedTextColor(context),
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        const SizedBox(height: 20),

        if (isChange) ...[
          const OasisFieldLabel('Current PIN'),
          VaultPinField(
            autofocus: false,
            enabled: !isLocked,
            onChanged: (value) => setState(() => _currentPin = value),
          ),
          const SizedBox(height: 20),
        ],

        OasisFieldLabel(isChange ? 'New PIN' : 'Choose a 4-digit PIN'),
        VaultPinField(
          autofocus: false,
          enabled: !(isChange && isLocked),
          onChanged: (value) => setState(() => _newPin = value),
        ),
        const SizedBox(height: 20),

        const OasisFieldLabel('Enter it again'),
        VaultPinField(
          autofocus: false,
          enabled: !(isChange && isLocked),
          hasError: _confirmPin.length == 4 && _confirmPin != _newPin,
          onChanged: (value) => setState(() => _confirmPin = value),
        ),
        const SizedBox(height: 16),

        if (isChange && status != null && status.isRunningOutOfAttempts)
          VaultPinNotice(
            icon: Icons.warning_amber_rounded,
            tone: AppTheme.warningColor,
            message:
                '${status.attemptsRemaining} '
                '${status.attemptsRemaining == 1 ? 'try' : 'tries'} left '
                'before your vault locks for 15 minutes.',
          )
        else
          const VaultPinNotice(
            icon: Icons.shield_outlined,
            message:
                'Pick something you will remember. There is no way to reset a '
                'forgotten vault PIN yet. You would need support to help.',
          ),
      ],
    );
  }
}

class _CheckingPin extends StatelessWidget {
  const _CheckingPin();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: OasisBusyDots(color: AppTheme.mutedTextColor(context)),
    ),
  );
}

/// A quiet line of explanation under a PIN field.
class VaultPinNotice extends StatelessWidget {
  final IconData icon;
  final String message;

  /// Tint for the icon. Defaults to the muted body colour: anything louder
  /// should be reserved for a warning that is actually about to cost the user
  /// something.
  final Color? tone;

  const VaultPinNotice({
    super.key,
    required this.icon,
    required this.message,
    this.tone,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 15, color: tone ?? AppTheme.mutedTextColor(context)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: AppTheme.labelText(
            context,
            color: tone ?? AppTheme.secondaryTextColor(context),
          ),
        ),
      ),
    ],
  );
}
