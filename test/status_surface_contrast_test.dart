import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa_app/core/theme/app_theme.dart';

/// The tinted status surfaces: the fills behind pills, callouts and quoted
/// blocks.
///
/// They used to be fixed pale creams while the text on them was theme-aware,
/// so in dark mode an applicant's message, a resolved bank name and a
/// "hidden from the marketplace" warning were all white on near-white. These
/// assert the pairings hold in *both* themes, which is the part that was
/// never checked.
void main() {
  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      testWidgets('reading copy on every status surface clears 4.5:1', (
        tester,
      ) async {
        final context = await _context(tester, brightness);
        final reading = AppTheme.readingTextColor(context);

        for (final entry in _surfaces(context).entries) {
          expect(
            _contrast(reading, entry.value),
            greaterThanOrEqualTo(4.5),
            reason: 'reading text on ${entry.key}',
          );
        }
      });

      testWidgets('accent labels on their own surface clear 3:1', (
        tester,
      ) async {
        // 3:1 is the AA floor for the bold 12–13pt these are used at. It is
        // deliberately not 4.5: the brand terracotta cannot reach 4.5 against
        // any dark background, which is a palette decision rather than a
        // surface one.
        final context = await _context(tester, brightness);

        final pairs = {
          'success': (AppTheme.successColor, AppTheme.successSurface(context)),
          'dispute': (AppTheme.disputeColor, AppTheme.disputeSurface(context)),
          'vacant': (AppTheme.primaryColor, AppTheme.vacantSurface(context)),
          'slate': (AppTheme.profileColor, AppTheme.slateSurface(context)),
        };

        for (final entry in pairs.entries) {
          final (foreground, background) = entry.value;
          expect(
            _contrast(foreground, background),
            greaterThanOrEqualTo(3.0),
            reason: '${entry.key} accent on its surface',
          );
        }
      });

      testWidgets('every status surface is distinct from the card it sits on', (
        tester,
      ) async {
        // A tint the same colour as what is behind it is not a tint. The card
        // is the right comparison, not the page: every one of these appears
        // inside a card, a sheet or a toast. (Slate deliberately *is* the
        // light page colour, `backgroundColor` is defined as it, which is
        // exactly why the page is the wrong thing to measure against.)
        final context = await _context(tester, brightness);
        final card = AppTheme.surfaceColor(context);

        for (final entry in _surfaces(context).entries) {
          expect(
            entry.value,
            isNot(card),
            reason: '${entry.key} is indistinguishable from the card behind it',
          );
        }
      });
    });
  }
}

Map<String, Color> _surfaces(BuildContext context) => {
  'successSurface': AppTheme.successSurface(context),
  'vacantSurface': AppTheme.vacantSurface(context),
  'disputeSurface': AppTheme.disputeSurface(context),
  'logoutSurface': AppTheme.logoutSurface(context),
  'slateSurface': AppTheme.slateSurface(context),
  'subtleSurface': AppTheme.subtleSurfaceColor(context),
};

Future<BuildContext> _context(
  WidgetTester tester,
  Brightness brightness,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

double _contrast(Color a, Color b) {
  final lighter = math.max(_luminance(a), _luminance(b));
  final darker = math.min(_luminance(a), _luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
