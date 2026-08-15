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
  static const Color darkSurfaceColor = Color(0xFF1A1A1A);

  // Semantic aliases used around the app
  static const Color primaryColor = terracottaColor;
  static const Color secondaryColor = sageGreenColor;
  static const Color actionColor = terracottaColor;
  static const Color successColor = sageGreenColor;
  static const Color vacantColor = sandColor;
  static const Color profileColor = slateGreyColor;
  static const Color logoutColor = brickRedColor;
  static const Color warningColor = sandColor;
  static const Color backgroundColor = slateSurfaceColor;
  static const Color darkBackgroundColor = blackColor;
  static const Color darkCardColor = darkSurfaceColor;

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
    return isDarkMode(context) ? const Color(0xFF222222) : whiteColor;
  }

  static Color subtleSurfaceColor(BuildContext context) {
    return isDarkMode(context) ? const Color(0xFF181818) : slateSurfaceColor;
  }

  static Color inputFillColor(BuildContext context) {
    return isDarkMode(context) ? const Color(0xFF262626) : whiteColor;
  }

  static Color borderColor(BuildContext context) {
    return isDarkMode(context)
        ? profileColor.withOpacity(0.35)
        : const Color(0xFFE5E7EB);
  }

  static Color primaryTextColor(BuildContext context) {
    return isDarkMode(context) ? whiteColor : primaryColor;
  }

  static Color profileTextColor(BuildContext context) {
    return isDarkMode(context) ? whiteColor : profileColor;
  }

  static Color secondaryTextColor(BuildContext context) {
    return isDarkMode(context)
        ? whiteColor.withOpacity(0.72)
        : const Color(0xFF6B7280);
  }

  static Color mutedTextColor(BuildContext context) {
    return isDarkMode(context)
        ? whiteColor.withOpacity(0.55)
        : const Color(0xFF9CA3AF);
  }

  /// Provides the ThemeData for the application.
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      cardColor: whiteColor,
      textTheme: GoogleFonts.montserratTextTheme(),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadePageTransitionsBuilder(),
          TargetPlatform.iOS: FadePageTransitionsBuilder(),
          TargetPlatform.macOS: FadePageTransitionsBuilder(),
          TargetPlatform.linux: FadePageTransitionsBuilder(),
          TargetPlatform.windows: FadePageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      textTheme: GoogleFonts.montserratTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: whiteColor, displayColor: whiteColor),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadePageTransitionsBuilder(),
          TargetPlatform.iOS: FadePageTransitionsBuilder(),
          TargetPlatform.macOS: FadePageTransitionsBuilder(),
          TargetPlatform.linux: FadePageTransitionsBuilder(),
          TargetPlatform.windows: FadePageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: whiteColor),
        titleTextStyle: TextStyle(
          color: whiteColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: actionColor),
      ),
    );
  }
}
