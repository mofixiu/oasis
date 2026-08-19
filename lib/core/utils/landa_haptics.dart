import 'package:flutter/services.dart';

/// Centralised haptic vocabulary.
///
/// Physical feedback is most of what separates an app that feels built from
/// one that feels rendered, but only if it is used consistently: the same
/// class of action must always produce the same tap. Screens call these
/// semantic helpers rather than [HapticFeedback] directly so the mapping
/// stays in one place.
class LandaHaptics {
  const LandaHaptics._();

  /// Ordinary taps: buttons, cards, list rows, tab changes.
  static void tap() => HapticFeedback.lightImpact();

  /// Committing something: submit, pay, apply, approve.
  static void commit() => HapticFeedback.mediumImpact();

  /// Moving between options: filter chips, segmented controls, toggles.
  static void select() => HapticFeedback.selectionClick();

  /// An action completed successfully.
  static void success() => HapticFeedback.mediumImpact();

  /// A destructive or rejected outcome. Heavy reads as "that mattered".
  static void warning() => HapticFeedback.heavyImpact();
}
