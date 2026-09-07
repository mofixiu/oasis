import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The one search bar Marketplace, Stays and Fix all use.
///
/// Every one of those screens searches the same way: a free-text area name
/// the backend matches against a listing's name, address, city and state, so
/// they share a control rather than each growing their own. Keeping it in one
/// place is also what keeps the debounce honest: typing "Lekki" is six
/// keystrokes, and six list requests for one word is the mistake this widget
/// exists to prevent.
///
/// The [controller] belongs to the screen, not to this widget, because every
/// screen using it has some *other* control that clears the search: a "see
/// all" button, an empty state, switching to a nearby search. Owning the text
/// internally would leave a stale word sitting in the box after one of those,
/// filtering nothing and explaining nothing.
///
/// This widget deliberately does not dedupe: it reports what was typed and
/// lets the controller decide whether that is a change worth a request. The
/// controllers already do, and two places tracking "what did we last search
/// for" is how they drift apart.
class LandaSearchField extends StatefulWidget {
  final TextEditingController controller;

  final String hintText;

  /// Called with the trimmed query once typing settles, and immediately on
  /// clear or submit. Empty string means "no search".
  final ValueChanged<String> onChanged;

  /// How long typing has to settle before [onChanged] fires.
  final Duration debounce;

  /// Sits to the right of the field, inside the same row. Stays' "Near me"
  /// button lives here.
  final Widget? trailing;

  const LandaSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 450),
    this.trailing,
  });

  @override
  State<LandaSearchField> createState() => _LandaSearchFieldState();
}

class _LandaSearchFieldState extends State<LandaSearchField> {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Repaints the clear button when the text changes from anywhere: typing,
    // or the screen clearing the field out from under us.
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(LandaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    // Clearing is not typing: the user wants the unfiltered list back now,
    // not in half a second.
    if (raw.trim().isEmpty) {
      widget.onChanged('');
      return;
    }
    _debounce = Timer(widget.debounce, () => widget.onChanged(raw.trim()));
  }

  void _clear() {
    _debounce?.cancel();
    widget.controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      onSubmitted: (value) {
        // Hitting Go should not wait out a timer that is about to fire with
        // the same text.
        _debounce?.cancel();
        widget.onChanged(value.trim());
      },
      textCapitalization: TextCapitalization.words,
      style: AppTheme.bodyText(
        context,
        color: AppTheme.primaryTextColor(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        hintStyle: AppTheme.bodyText(
          context,
          color: AppTheme.mutedTextColor(context),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: AppTheme.mutedTextColor(context),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.mutedTextColor(context),
                ),
                onPressed: _clear,
                tooltip: 'Clear search',
              ),
        filled: true,
        fillColor: AppTheme.inputFillColor(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppTheme.cornerMd,
          borderSide: BorderSide(color: AppTheme.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppTheme.cornerMd,
          borderSide: BorderSide(color: AppTheme.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppTheme.cornerMd,
          borderSide: const BorderSide(color: AppTheme.actionColor, width: 1.4),
        ),
      ),
    );

    if (widget.trailing == null) return field;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: field),
        const SizedBox(width: 10),
        widget.trailing!,
      ],
    );
  }
}
