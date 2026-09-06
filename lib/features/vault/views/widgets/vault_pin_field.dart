import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/landa_haptics.dart';
import '../../../../core/widgets/landa_pressable.dart';

/// Four boxes for a vault PIN.
///
/// A real [TextField] does the work and is kept invisible behind the boxes,
/// so the platform keyboard, paste, and accessibility all behave normally
/// while the boxes stay the thing on screen. Digits are never rendered,
/// because a PIN typed in a bank hall is read over a shoulder. Only whether
/// each position is filled.
class VaultPinField extends StatefulWidget {
  final ValueChanged<String> onChanged;

  /// Fired when the fourth digit lands, so a caller can submit without making
  /// the user reach for a button they were always going to press.
  final ValueChanged<String>? onCompleted;

  final bool autofocus;
  final bool enabled;

  /// Tints the boxes red after a rejected PIN, so the retry does not look
  /// identical to the first attempt.
  final bool hasError;

  const VaultPinField({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.autofocus = true,
    this.enabled = true,
    this.hasError = false,
  });

  @override
  State<VaultPinField> createState() => VaultPinFieldState();
}

class VaultPinFieldState extends State<VaultPinField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  static const int _length = 4;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleChanged(String value) {
    setState(() {});
    widget.onChanged(value);
    if (value.length == _length) {
      LandaHaptics.tap();
      widget.onCompleted?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filled = _controller.text.length;

    return Stack(
      children: [
        // The boxes are what the user sees and taps; the field beneath them is
        // sized to match so the tap target is the whole row.
        LandaPressable(
          onTap: widget.enabled ? _focusNode.requestFocus : null,
          pressedScale: 1,
          child: Row(
            children: [
              for (var index = 0; index < _length; index++) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(
                  child: _PinBox(
                    isFilled: index < filled,
                    isNext: index == filled && _focusNode.hasFocus,
                    hasError: widget.hasError,
                    enabled: widget.enabled,
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              // obscureText as well as hidden rendering: it keeps the PIN out
              // of the keyboard's own suggestion and autofill history.
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              showCursor: false,
              maxLength: _length,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(_length),
              ],
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
              onChanged: _handleChanged,
              onTap: () => setState(() {}),
            ),
          ),
        ),
      ],
    );
  }
}

class _PinBox extends StatelessWidget {
  final bool isFilled;
  final bool isNext;
  final bool hasError;
  final bool enabled;

  const _PinBox({
    required this.isFilled,
    required this.isNext,
    required this.hasError,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final accent = hasError ? AppTheme.disputeColor : AppTheme.actionColor;
    final border = hasError
        ? accent
        : isNext || isFilled
        ? accent.withValues(alpha: isNext ? 1 : 0.45)
        : AppTheme.borderColor(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 60,
      decoration: BoxDecoration(
        color: AppTheme.subtleSurfaceColor(context),
        borderRadius: AppTheme.cornerMd,
        border: Border.all(color: border, width: isNext || hasError ? 1.6 : 1),
      ),
      child: Center(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          scale: isFilled ? 1 : 0,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? accent : AppTheme.mutedTextColor(context),
            ),
          ),
        ),
      ),
    );
  }
}
