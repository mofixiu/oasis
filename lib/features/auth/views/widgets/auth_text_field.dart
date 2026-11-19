import 'package:flutter/material.dart';
import '../../../../core/app_variant.dart';
import '../../../../core/theme/app_theme.dart';

class AuthTextField extends StatefulWidget {
  final String label;
  final String hintText;
  final IconData prefixIcon;
  final bool isPassword;
  final Widget? suffixIcon;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.prefixIcon,
    this.isPassword = false,
    this.suffixIcon,
    this.controller,
    this.keyboardType,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  // Password fields start obscured; the built-in eye toggle flips this.
  late bool _obscureText = widget.isPassword;

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = AppTheme.profileTextColor(context);
    final mutedTextColor = AppTheme.mutedTextColor(context);

    // v2: no label above the field, as in the brand mockups. The label is
    // still what a screen reader announces, and the hint says the same.
    final field = TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      keyboardType: widget.keyboardType,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppTheme.primaryTextColor(context),
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: mutedTextColor, fontSize: 15),
        prefixIcon: Icon(
          widget.prefixIcon,
          color: AppTheme.secondaryTextColor(context),
          size: 20,
        ),
        suffixIcon: widget.isPassword
            ? IconButton(
                tooltip: _obscureText ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: mutedTextColor,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureText = !_obscureText),
              )
            : widget.suffixIcon,
        filled: true,
        fillColor: AppTheme.inputFillColor(context),
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.actionColor, width: 1.5),
        ),
      ),
    );

    if (isOasisV2) {
      return Semantics(label: widget.label, textField: true, child: field);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: TextStyle(
            color: primaryTextColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}
