import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/oasis_sheet.dart';
import '../../../core/widgets/oasis_toast.dart';
import '../controllers/auth_controller.dart';

/// Resetting a forgotten password, start to finish, in one bottom sheet.
///
/// This used to be two full screens pushed over sign-in: one to ask for the
/// email, another to paste the token and choose a new password, each a
/// centred card on an otherwise empty page with its own app bar and its own
/// "Back" button. Three taps of chrome around two short forms. It is a
/// detour from signing in, not a place, and a sheet is what a detour looks
/// like: sign-in stays behind it, and dismissing lands you back where you
/// were rather than on whatever the navigator had underneath.
///
/// The three steps are stages of one sheet rather than three sheets, because
/// they share the email: the confirmation names the address the link went to,
/// and stepping back to correct a typo has to keep what was typed. Chaining
/// sheets would mean carrying that between routes, and each hop is another
/// chance to hand a dead `BuildContext` to `showModalBottomSheet` — the crash
/// documented at length on `openAddPropertyFlow`.
Future<void> openPasswordResetSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Not dismissible by a tap outside once a new password is being typed:
      // see `_PasswordResetSheetState.build`. The sheet itself decides.
      builder: (_) => const _PasswordResetSheet(),
    );

/// Which of the three questions the sheet is currently asking.
enum _Stage {
  /// "What is your email?"
  requestLink,

  /// "We have sent it." The only stage with nothing to fill in.
  linkSent,

  /// "Paste the token and choose a new password."
  setPassword,
}

class _PasswordResetSheet extends StatefulWidget {
  const _PasswordResetSheet();

  @override
  State<_PasswordResetSheet> createState() => _PasswordResetSheetState();
}

class _PasswordResetSheetState extends State<_PasswordResetSheet> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Stage _stage = _Stage.requestLink;

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String get _email => _emailController.text.trim();

  Future<void> _sendResetLink() async {
    if (_email.isEmpty || !_email.contains('@')) {
      OasisToast.error(context, 'Enter the email address for your account.');
      return;
    }
    final auth = context.read<AuthController>();
    final success = await auth.requestPasswordReset(_email);
    if (!mounted) return;

    if (!success) {
      OasisToast.error(
        context,
        auth.errorMessage ?? 'Could not request a password reset.',
      );
      return;
    }
    setState(() => _stage = _Stage.linkSent);
  }

  Future<void> _setNewPassword() async {
    final token = _tokenController.text.trim();
    final password = _passwordController.text;

    if (token.isEmpty) {
      OasisToast.error(context, 'Paste the reset token from your email.');
      return;
    }
    if (password.length < 8) {
      OasisToast.error(context, 'New password must be at least 8 characters.');
      return;
    }
    if (password != _confirmController.text) {
      OasisToast.error(context, 'Passwords do not match.');
      return;
    }

    // Captured before the await: this sheet pops itself on success, and the
    // toast that follows has to be shown against something still in the tree.
    final navigator = Navigator.of(context);
    final auth = context.read<AuthController>();
    final success = await auth.confirmPasswordReset(
      token: token,
      newPassword: password,
    );
    if (!navigator.mounted) return;

    if (!success) {
      OasisToast.error(
        navigator.context,
        auth.errorMessage ??
            'Could not reset password. The token may be invalid or expired.',
      );
      return;
    }
    navigator.pop();
    OasisToast.success(
      navigator.context,
      'Password reset. Sign in with your new password.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    // Grows with the keyboard rather than being fixed when the sheet opened:
    // the last stage is three fields and a button, which does not fit in 70%
    // of a small phone once the keyboard is up.
    final height = MediaQuery.sizeOf(context).height;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: keyboard > 0 ? height * 0.94 : height * 0.72,
      ),
      child: switch (_stage) {
        _Stage.requestLink => _requestLink(auth),
        _Stage.linkSent => _linkSent(),
        _Stage.setPassword => _setPassword(auth),
      },
    );
  }

  // ------------------------------------------------------------- stage one

  Widget _requestLink(AuthController auth) => OasisSheet(
    icon: Icons.lock_reset_outlined,
    title: 'Forgot your password?',
    subtitle:
        'Enter your account email and we will send a secure reset link to '
        'it.',
    footer: OasisSheetButton(
      label: 'Send reset link',
      icon: Icons.send_rounded,
      isLoading: auth.isLoading,
      onPressed: auth.isLoading ? null : _sendResetLink,
    ),
    children: [
      const OasisFieldLabel('Email address'),
      TextField(
        controller: _emailController,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _sendResetLink(),
        style: AppTheme.cardTitle(context),
        decoration: oasisInputDecoration(
          context,
          hint: 'user@example.com',
          prefixIcon: Icons.email_outlined,
        ),
      ),
      const SizedBox(height: 12),
      // Offered up front as well as after sending: somebody arriving here
      // with the email already open on another device should not have to
      // send themselves a second link to reach the form that uses the first.
      _StageLink(
        label: 'I already have a reset token',
        onTap: () => setState(() => _stage = _Stage.setPassword),
      ),
    ],
  );

  // ------------------------------------------------------------- stage two

  Widget _linkSent() => OasisSheet(
    icon: Icons.mark_email_read_outlined,
    title: 'Check your inbox',
    subtitle:
        'If an account exists for $_email, the reset instructions are on '
        'their way. Check spam too.',
    accent: AppTheme.successColor,
    footer: OasisSheetButton(
      label: 'I have the token',
      icon: Icons.vpn_key_outlined,
      onPressed: () => setState(() => _stage = _Stage.setPassword),
    ),
    children: [
      _StageLink(
        label: 'Send it to a different address',
        // Back to the first stage with the email still in the field, so a
        // typo is one character to fix rather than a whole address to retype.
        onTap: () => setState(() => _stage = _Stage.requestLink),
      ),
    ],
  );

  // ----------------------------------------------------------- stage three

  Widget _setPassword(AuthController auth) => OasisSheet(
    icon: Icons.password_outlined,
    title: 'Set a new password',
    subtitle: 'Paste the token from your email and choose a new password.',
    footer: OasisSheetButton(
      label: 'Reset password',
      icon: Icons.check_rounded,
      isLoading: auth.isLoading,
      onPressed: auth.isLoading ? null : _setNewPassword,
    ),
    children: [
      const OasisFieldLabel('Reset token'),
      TextField(
        controller: _tokenController,
        autofocus: true,
        style: AppTheme.cardTitle(context),
        decoration: oasisInputDecoration(
          context,
          hint: 'Paste the token from your email',
          prefixIcon: Icons.vpn_key_outlined,
        ),
      ),
      const SizedBox(height: 14),
      const OasisFieldLabel('New password'),
      TextField(
        controller: _passwordController,
        obscureText: true,
        style: AppTheme.cardTitle(context),
        decoration: oasisInputDecoration(
          context,
          hint: 'At least 8 characters',
          prefixIcon: Icons.lock_outline,
        ),
      ),
      const SizedBox(height: 14),
      const OasisFieldLabel('Confirm new password'),
      TextField(
        controller: _confirmController,
        obscureText: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _setNewPassword(),
        style: AppTheme.cardTitle(context),
        decoration: oasisInputDecoration(
          context,
          hint: 'Re-enter your new password',
          prefixIcon: Icons.lock_outline,
        ),
      ),
      const SizedBox(height: 12),
      // Only offered when there is a link to go back to. Somebody who jumped
      // straight here from stage one has no "sent" screen behind them.
      if (_email.isNotEmpty)
        _StageLink(
          label: 'Send the link again',
          onTap: () => setState(() => _stage = _Stage.requestLink),
        ),
    ],
  );
}

/// A quiet inline link between stages. A `TextButton` rather than a second
/// filled button: there is one action per stage and this is never it.
class _StageLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StageLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: AppTheme.labelText(context, color: AppTheme.actionColor),
      ),
    ),
  );
}
