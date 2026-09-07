import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/fade_page_route.dart';

/// AppTheme defines the global styling for Landa OS.
/// It implements the strict color palette defined for the prop-tech platform.
class AppTheme {
  // Landa OS palette
  static const Color blackColor = Color(0xFF101010);
  static const Color whiteColor = Color(0xFFFFFFFF);
  static const Color terracottaColor = Color(0xFFB65F3C);
  static const Color sageGreenColor = Color(0xFF6F8F72);
  static const Color sandColor = Color(0xFFD6B98C);
  static const Color slateGreyColor = Color(0xFF64748B);
  static const Color brickRedColor = Color(0xFFA44A3F);

  static const Color successSurfaceColor = Color(0xFFE8F3EA);
  static const Color vacantSurfaceColor = Color(0xFFF4E8D9);
  static const Color slateSurfaceColor = Color(0xFFF1F4F8);
  static const Color logoutSurfaceColor = Color(0xFFF7E9E6);

  /// The dark-mode surface ramp.
  ///
  /// Warm, not neutral, and stepped rather than flat. Pure black under a
  /// featureless grey card is the cheapest-looking dark mode there is: every
  /// plane sits at the same depth, nothing has an edge, and terracotta, a
  /// warm earth colour, floats on it looking like a sticker.
  ///
  /// These carry a few points of red and green over blue, so the palette's
  /// terracotta and sand read as belonging to the surface they are printed
  /// on. The steps are deliberately small; the intent is depth you feel
  /// rather than tints you notice.
  static const Color darkSurfaceColor = Color(0xFF1C1A19);

  // Semantic aliases used around the app
  static const Color primaryColor = terracottaColor;
  static const Color secondaryColor = sageGreenColor;
  static const Color actionColor = terracottaColor;
  static const Color successColor = sageGreenColor;
  static const Color vacantColor = sandColor;
  static const Color profileColor = slateGreyColor;
  static const Color logoutColor = brickRedColor;
  static const Color warningColor = sandColor;
  // Escrow disputes: deeper brick red so they read as an alert while staying
  // inside the terracotta palette rather than dropping to a generic orange.
  static const Color disputeColor = brickRedColor;
  static const Color disputeSurfaceColor = logoutSurfaceColor;
  // Unread/pending indicator dots. Deliberately a brighter red than the
  // terracotta palette: a dot in brand colour would disappear against the
  // terracotta-tinted selected nav icon it sits on.
  static const Color alertDotColor = Color(0xFFE5484D);
  static const Color backgroundColor = slateSurfaceColor;

  /// The page behind everything. Not `#000`: a true black gives a card no
  /// edge to be seen against, which is why every surface used to read as one
  /// undifferentiated sheet.
  static const Color darkBackgroundColor = Color(0xFF121110);

  static const Color darkCardColor = darkSurfaceColor;

  /// One step above a card, for a sheet or a header that sits on top of one.
  static const Color darkRaisedColor = Color(0xFF262322);

  /// One step below a card, for insets, input fills and quoted blocks.
  static const Color darkRecessedColor = Color(0xFF171514);

  // ---------------------------------------------------------------- shape
  // Three radii only. Anything that needs a corner picks the nearest of these
  // rather than inventing a new value, which is what made the UI read as
  // hand-assembled.
  /// Chips, pills, small controls.
  static const double radiusSm = 8;

  /// Buttons, inputs, inner tiles.
  static const double radiusMd = 16;

  /// Cards, sheets, modals.
  static const double radiusLg = 24;

  static BorderRadius get cornerSm => BorderRadius.circular(radiusSm);
  static BorderRadius get cornerMd => BorderRadius.circular(radiusMd);
  static BorderRadius get cornerLg => BorderRadius.circular(radiusLg);

  // --------------------------------------------------------------- shadow
  /// Two-layer card shadow: a tight contact shadow that anchors the card to
  /// the page, plus a wide soft one that gives it height. A single blurred
  /// shadow always reads either muddy or flat; the pair is what makes a
  /// surface look lifted.
  static List<BoxShadow> cardShadow(BuildContext context) {
    final dark = isDarkMode(context);
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.32 : 0.04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.24 : 0.05),
        blurRadius: 18,
        spreadRadius: -4,
        offset: const Offset(0, 8),
      ),
    ];
  }

  /// For sheets, dialogs and anything that floats above the page.
  static List<BoxShadow> raisedShadow(BuildContext context) {
    final dark = isDarkMode(context);
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.40 : 0.06),
        blurRadius: 3,
        offset: const Offset(0, 1),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
        blurRadius: 34,
        spreadRadius: -8,
        offset: const Offset(0, 18),
      ),
    ];
  }

  // ----------------------------------------------------------------- type
  // One ramp, used everywhere. Headings carry negative tracking: at display
  // sizes Montserrat's default spacing looks loose and generic.
  static const double textXs = 11;
  static const double textSm = 13;
  static const double textMd = 15;
  static const double textLg = 17;
  static const double textXl = 22;
  static const double text2xl = 28;

  /// Page-level heading, one per screen.
  static TextStyle screenTitle(BuildContext context, {Color? color}) =>
      TextStyle(
        fontSize: text2xl,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.7,
        height: 1.15,
        color: color ?? primaryTextColor(context),
      );

  /// Heading above a group of cards or rows.
  static TextStyle sectionTitle(BuildContext context, {Color? color}) =>
      TextStyle(
        fontSize: textLg,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        height: 1.25,
        color: color ?? primaryTextColor(context),
      );

  /// Title line inside a card or list row.
  static TextStyle cardTitle(BuildContext context, {Color? color}) => TextStyle(
    fontSize: textMd,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: color ?? primaryTextColor(context),
  );

  /// Running text and supporting copy.
  static TextStyle bodyText(BuildContext context, {Color? color}) => TextStyle(
    fontSize: textSm,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: color ?? secondaryTextColor(context),
  );

  /// Small uppercase-ish labels, metadata, pill text.
  static TextStyle labelText(BuildContext context, {Color? color}) => TextStyle(
    fontSize: textXs,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    height: 1.2,
    color: color ?? mutedTextColor(context),
  );

  static bool isDarkMode(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color pageBackground(BuildContext context) {
    return isDarkMode(context) ? darkBackgroundColor : backgroundColor;
  }

  static Color surfaceColor(BuildContext context) {
    return isDarkMode(context) ? darkCardColor : whiteColor;
  }

  static Color elevatedSurfaceColor(BuildContext context) {
    return isDarkMode(context) ? darkRaisedColor : whiteColor;
  }

  static Color subtleSurfaceColor(BuildContext context) {
    return isDarkMode(context) ? darkRecessedColor : slateSurfaceColor;
  }

  // Tinted status surfaces: the fills behind pills, callouts and quoted
  // blocks. Each is a pale wash of its accent in light mode and a deep one in
  // dark mode.
  //
  // The `*SurfaceColor` constants above are the light halves and must not be
  // used as a fill directly. They are fixed pale creams, and the text that
  // sits on them is theme-aware: in dark mode that combination is white on
  // near-white, which is how an applicant's message, a bank name and a
  // "hidden from the marketplace" warning all became invisible. Resolve the
  // fill through these instead, and the pairing holds in both themes.
  //
  // Deep rather than alpha-composited: an alpha fill takes its final colour
  // from whatever is behind it, so the same pill reads differently on a card
  // than on the page, and neither value can be checked for contrast.

  static Color successSurface(BuildContext context) =>
      isDarkMode(context) ? const Color(0xFF17281A) : successSurfaceColor;

  static Color vacantSurface(BuildContext context) =>
      isDarkMode(context) ? const Color(0xFF2A2117) : vacantSurfaceColor;

  // Darker than the other two on purpose: brick red is the deepest accent in
  // the palette, and a lighter tint under it falls below 3:1. The one place
  // legibility matters most, since this surface carries disputes.
  static Color disputeSurface(BuildContext context) =>
      isDarkMode(context) ? const Color(0xFF21100E) : disputeSurfaceColor;

  static Color logoutSurface(BuildContext context) => disputeSurface(context);

  static Color slateSurface(BuildContext context) =>
      isDarkMode(context) ? const Color(0xFF191D23) : slateSurfaceColor;

  static Color inputFillColor(BuildContext context) {
    return isDarkMode(context) ? const Color(0xFF262626) : whiteColor;
  }

  static Color borderColor(BuildContext context) {
    return isDarkMode(context)
        ? profileColor.withValues(alpha: 0.35)
        : const Color(0xFFE5E7EB);
  }

  static Color primaryTextColor(BuildContext context) {
    return isDarkMode(context) ? whiteColor : primaryColor;
  }

  static Color profileTextColor(BuildContext context) {
    return isDarkMode(context) ? whiteColor : profileColor;
  }

  /// High-contrast neutral for copy that has to be *read* rather than
  /// scanned: legal terms, agreement rules, anything with consequences.
  ///
  /// [primaryTextColor] is brand terracotta in light mode, which clears 4.5:1
  /// against white but not against the tinted surfaces those blocks sit on;
  /// [secondaryTextColor] is dimmer still. Neither is a safe default for a
  /// paragraph somebody is agreeing to, so this is the one that is.
  static Color readingTextColor(BuildContext context) {
    return isDarkMode(context) ? whiteColor : blackColor;
  }

  static Color secondaryTextColor(BuildContext context) {
    return isDarkMode(context)
        ? whiteColor.withValues(alpha: 0.72)
        : const Color(0xFF6B7280);
  }

  static Color mutedTextColor(BuildContext context) {
    return isDarkMode(context)
        ? whiteColor.withValues(alpha: 0.55)
        : const Color(0xFF9CA3AF);
  }

  /// Applies the app's tracking to a Montserrat text theme.
  ///
  /// Display and headline sizes get progressively tighter letter-spacing:
  /// Montserrat's default tracking is tuned for small text and looks slack
  /// once type gets large, which is most of why untouched headings read as
  /// "default Flutter app".
  static TextTheme _tracked(TextTheme base) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(letterSpacing: -1.2),
      displayMedium: base.displayMedium?.copyWith(letterSpacing: -1.0),
      displaySmall: base.displaySmall?.copyWith(letterSpacing: -0.8),
      headlineLarge: base.headlineLarge?.copyWith(letterSpacing: -0.8),
      headlineMedium: base.headlineMedium?.copyWith(letterSpacing: -0.6),
      headlineSmall: base.headlineSmall?.copyWith(letterSpacing: -0.5),
      titleLarge: base.titleLarge?.copyWith(letterSpacing: -0.4),
      titleMedium: base.titleMedium?.copyWith(letterSpacing: -0.2),
    );
  }

  /// Provides the ThemeData for the application.
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      cardColor: whiteColor,
      textTheme: _tracked(GoogleFonts.montserratTextTheme()),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadePageTransitionsBuilder(),
          TargetPlatform.iOS: FadePageTransitionsBuilder(),
          TargetPlatform.macOS: FadePageTransitionsBuilder(),
          TargetPlatform.linux: FadePageTransitionsBuilder(),
          TargetPlatform.windows: FadePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        // Montserrat explicitly: an AppBar title ignores the global textTheme
        // and inherits from this style, so a bare TextStyle here silently
        // drops every app bar back to the platform default font.
        titleTextStyle: GoogleFonts.montserrat(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: secondaryColor,
        error: warningColor,
        surface: whiteColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: actionColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: cornerMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.montserrat(
            fontSize: textMd,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: actionColor,
          shape: RoundedRectangleBorder(borderRadius: cornerMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.montserrat(
            fontSize: textMd,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      chipTheme: const ChipThemeData(shape: StadiumBorder()),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: cornerLg),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: actionColor),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: darkBackgroundColor,
      cardColor: darkCardColor,
      textTheme: _tracked(
        GoogleFonts.montserratTextTheme(
          ThemeData.dark().textTheme,
        ).apply(bodyColor: whiteColor, displayColor: whiteColor),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadePageTransitionsBuilder(),
          TargetPlatform.iOS: FadePageTransitionsBuilder(),
          TargetPlatform.macOS: FadePageTransitionsBuilder(),
          TargetPlatform.linux: FadePageTransitionsBuilder(),
          TargetPlatform.windows: FadePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: whiteColor),
        titleTextStyle: GoogleFonts.montserrat(
          color: whiteColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        error: logoutColor,
        surface: darkCardColor,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: actionColor,
          foregroundColor: whiteColor,
          shape: RoundedRectangleBorder(borderRadius: cornerMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.montserrat(
            fontSize: textMd,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: actionColor,
          shape: RoundedRectangleBorder(borderRadius: cornerMd),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.montserrat(
            fontSize: textMd,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      chipTheme: const ChipThemeData(shape: StadiumBorder()),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: cornerLg),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: actionColor),
      ),
    );
  }
}
