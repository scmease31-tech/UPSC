import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// UPSC Daily Edge — Premium Glassmorphic Theme System
/// Inspired by: Pastel gradient backgrounds, frosted glass cards,
///              teal/mint accents, rounded modern UI elements.
/// ──────────────────────────────────────────────────────────────────────────────
class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════════════════════════════════════
  // CORE BRAND COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color primaryColor    = Color(0xFF00BFA6);
  static const Color primaryLight    = Color(0xFF5DF2D6);
  static const Color primaryDark     = Color(0xFF00897B);
  static const Color primarySurface  = Color(0xFFE0F7F4);

  static const Color accentViolet    = Color(0xFF7C4DFF);
  static const Color accentLavender  = Color(0xFFB388FF);
  static const Color accentPurple    = Color(0xFF9C27B0);
  static const Color accentColor     = Color(0xFFB388FF);
  static const Color accentTeal      = Color(0xFF00BFA6);
  static const Color accentRose      = Color(0xFFFF4081);

  static const Color successGreen    = Color(0xFF00C853);
  static const Color errorRed        = Color(0xFFFF1744);
  static const Color warningOrange   = Color(0xFFFFAB00);
  static const Color mintGreen       = Color(0xFF00C853);
  static const Color warmYellow      = Color(0xFFFBBF24);
  static const Color warmGold        = Color(0xFFFCD34D);

  // ═══════════════════════════════════════════════════════════════════════════
  // PASTEL BACKGROUND PALETTE (from gradient background image)
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color bgGradientTop       = Color(0xFFEFF9F0);
  static const Color bgGradientMid       = Color(0xFFD6F0F7);
  static const Color bgGradientBottom    = Color(0xFFE8D5F5);
  static const Color bgGradientDeep      = Color(0xFFF5C6E0);

  // ═══════════════════════════════════════════════════════════════════════════
  // CARD / SURFACE COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color glassBg            = Color(0xCCFFFFFF);
  static const Color glassStroke        = Color(0x33FFFFFF);

  static const Color cardBg             = Color(0xFFFFFFFE);
  static const Color scaffoldBg         = Color(0xFFF4FAFB);
  static const Color surfaceVariant     = Color(0xFFF5F3FF);

  // ═══════════════════════════════════════════════════════════════════════════
  // PASTEL CARD TINTS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color pastelMint         = Color(0xFFD1FAE5);
  static const Color pastelBlue         = Color(0xFFDBEAFE);
  static const Color pastelLavender     = Color(0xFFEDE9FE);
  static const Color pastelPink         = Color(0xFFFCE7F3);
  static const Color pastelYellow       = Color(0xFFFEF3C7);

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color textPrimary       = Color(0xFF1A1D26);
  static const Color textSecondary     = Color(0xFF5A6178);
  static const Color textTertiary      = Color(0xFF9CA3AF);
  static const Color dividerColor      = Color(0xFFE5E7EB);

  // ═══════════════════════════════════════════════════════════════════════════
  // DARK MODE COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color darkScaffoldBg        = Color(0xFF0D1117);
  static const Color darkCardBg            = Color(0xFF161B22);
  static const Color darkSurface           = Color(0xFF1C2333);
  static const Color darkTextPrimary       = Color(0xFFF0F3F6);
  static const Color darkTextSecondary     = Color(0xFF8B949E);
  static const Color darkTextTertiary      = Color(0xFF6E7681);
  static const Color darkDividerColor      = Color(0xFF21262D);
  static const Color darkSurfaceVariant    = Color(0xFF1C2333);

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENT PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  static const LinearGradient screenGradient = LinearGradient(
    colors: [bgGradientTop, bgGradientMid, bgGradientBottom, bgGradientDeep],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  static const LinearGradient screenGradientDark = LinearGradient(
    colors: [Color(0xFF0D1117), Color(0xFF111827), Color(0xFF1A1040)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00BFA6), Color(0xFF00E5CC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFFB388FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00C853), Color(0xFF69F0AE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [Color(0xFFA78BFA), Color(0xFFDDD6FE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFB388FF), Color(0xFFE1BEE7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADOWS
  // ═══════════════════════════════════════════════════════════════════════════

  static List<BoxShadow> get softShadow => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2)),
  ];

  static List<BoxShadow> get cardShadow => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 4)),
    BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 1)),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 30, offset: const Offset(0, 8)),
  ];

  static List<BoxShadow> get glowShadow => [
    BoxShadow(color: primaryColor.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get darkCardShadow => [
    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> get neuShadow => cardShadow;
  static List<BoxShadow> get darkNeuShadow => darkCardShadow;
  static List<BoxShadow> get neuInset => softShadow;

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION DURATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Duration durationFast   = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationSlow   = Duration(milliseconds: 500);
  static const Duration durationPage   = Duration(milliseconds: 600);

  static const Curve curveDefault    = Curves.easeOutCubic;
  static const Curve curveSpring     = Curves.elasticOut;
  static const Curve curveDecelerate = Curves.decelerate;

  // ═══════════════════════════════════════════════════════════════════════════
  // SPACING SCALE (4pt grid)
  // ═══════════════════════════════════════════════════════════════════════════

  static const double space4   = 4;
  static const double space8   = 8;
  static const double space12  = 12;
  static const double space16  = 16;
  static const double space20  = 20;
  static const double space24  = 24;
  static const double space32  = 32;

  // ═══════════════════════════════════════════════════════════════════════════
  // RADII
  // ═══════════════════════════════════════════════════════════════════════════

  static const double radiusSm    = 10;
  static const double radiusMd    = 14;
  static const double radiusLg    = 22;
  static const double radiusXl    = 28;
  static const double radiusRound = 100;

  // ═══════════════════════════════════════════════════════════════════════════
  // DECORATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static LinearGradient scaffoldGradient(BuildContext context) {
    return isDark(context) ? screenGradientDark : screenGradient;
  }

  static BoxDecoration glassCard(BuildContext context, {
    double radius = 22, Color? glowColor, bool intense = false,
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: intense ? 0.10 : 0.06)
          : Colors.white.withValues(alpha: intense ? 0.92 : 0.78),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.6),
        width: 1.2,
      ),
      boxShadow: dark ? darkCardShadow : cardShadow,
    );
  }

  static BoxDecoration cleanCard(BuildContext context, {
    double radius = 18, Color? borderColor,
  }) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? darkCardBg : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? (dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
        width: 1,
      ),
      boxShadow: dark ? darkCardShadow : cardShadow,
    );
  }

  static BoxDecoration filledButton({Color? color, double radius = 14}) {
    final c = color ?? primaryColor;
    return BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
    );
  }

  static BoxDecoration gradientButton({List<Color>? colors, double radius = 14, bool glow = true}) {
    final btnColors = colors ?? [primaryColor, primaryLight];
    return BoxDecoration(
      gradient: LinearGradient(colors: btnColors, begin: Alignment.centerLeft, end: Alignment.centerRight),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: glow ? [BoxShadow(color: btnColors[0].withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
    );
  }

  /// Skeleton shimmer decoration for loading placeholders.
  static BoxDecoration shimmerBox(BuildContext context, {double radius = 12}) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(radius),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADAPTIVE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color scaffold(BuildContext context) => isDark(context) ? darkScaffoldBg : scaffoldBg;
  static Color card(BuildContext context) => isDark(context) ? darkCardBg : cardBg;
  static Color surface(BuildContext context) => isDark(context) ? darkSurface : surfaceVariant;
  static Color textP(BuildContext context) => isDark(context) ? darkTextPrimary : textPrimary;
  static Color textS(BuildContext context) => isDark(context) ? darkTextSecondary : textSecondary;
  static Color textT(BuildContext context) => isDark(context) ? darkTextTertiary : textTertiary;
  static Color divider(BuildContext context) => isDark(context) ? darkDividerColor : dividerColor;
  static Color surfaceV(BuildContext context) => isDark(context) ? darkSurfaceVariant : surfaceVariant;
  static List<BoxShadow> cardSh(BuildContext context) => isDark(context) ? darkCardShadow : cardShadow;
  static List<BoxShadow> neuSh(BuildContext context) => isDark(context) ? darkCardShadow : cardShadow;

  // ═══════════════════════════════════════════════════════════════════════════
  // LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor, brightness: Brightness.light,
        primary: primaryColor, secondary: accentViolet,
        surface: cardBg, surfaceContainerHighest: surfaceVariant,
      ),
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, foregroundColor: textPrimary,
        elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.4),
        iconTheme: const IconThemeData(color: textPrimary, size: 22),
      ),
      textTheme: _buildTextTheme(Brightness.light),
      cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme(Brightness.light),
      chipTheme: _chipTheme(Brightness.light),
      inputDecorationTheme: _inputTheme(Brightness.light),
      dividerTheme: DividerThemeData(color: dividerColor.withValues(alpha: 0.5), thickness: 1, space: 1),
      dialogTheme: DialogThemeData(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)), titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary)),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd))),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: Colors.transparent, selectedItemColor: primaryColor, unselectedItemColor: textTertiary, type: BottomNavigationBarType.fixed, elevation: 0),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(true),
        thickness: WidgetStatePropertyAll(4),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(primaryColor.withValues(alpha: 0.3)),
        trackColor: WidgetStatePropertyAll(Colors.transparent),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        minThumbLength: 36,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DARK THEME
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor, brightness: Brightness.dark,
        primary: primaryColor, secondary: accentLavender,
        surface: darkCardBg, surfaceContainerHighest: darkSurfaceVariant,
      ),
      scaffoldBackgroundColor: darkScaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, foregroundColor: darkTextPrimary,
        elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: darkTextPrimary, letterSpacing: -0.4),
        iconTheme: const IconThemeData(color: Color(0xFFF0F3F6), size: 22),
      ),
      textTheme: _buildTextTheme(Brightness.dark),
      cardTheme: CardThemeData(color: darkCardBg, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)), margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme(Brightness.dark),
      chipTheme: _chipTheme(Brightness.dark),
      inputDecorationTheme: _inputTheme(Brightness.dark),
      dividerTheme: DividerThemeData(color: darkDividerColor.withValues(alpha: 0.5), thickness: 1, space: 1),
      dialogTheme: DialogThemeData(backgroundColor: darkCardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)), titleTextStyle: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: darkTextPrimary)),
      snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd))),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(backgroundColor: Colors.transparent, selectedItemColor: primaryColor, unselectedItemColor: darkTextTertiary, type: BottomNavigationBarType.fixed, elevation: 0),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStatePropertyAll(true),
        thickness: WidgetStatePropertyAll(4),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(primaryColor.withValues(alpha: 0.35)),
        trackColor: WidgetStatePropertyAll(Colors.transparent),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        minThumbLength: 36,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TYPOGRAPHY
  // ═══════════════════════════════════════════════════════════════════════════

  static TextTheme _buildTextTheme(Brightness brightness) {
    final tp = brightness == Brightness.dark ? darkTextPrimary : textPrimary;
    final ts = brightness == Brightness.dark ? darkTextSecondary : textSecondary;
    return TextTheme(
      headlineLarge: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, color: tp, letterSpacing: -0.5, height: 1.2),
      headlineMedium: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: tp, letterSpacing: -0.3, height: 1.3),
      titleLarge: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: tp, letterSpacing: -0.2),
      titleMedium: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: tp),
      bodyLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: tp, height: 1.6),
      bodyMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: ts, height: 1.5),
      bodySmall: GoogleFonts.inter(fontSize: 12, color: ts),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: primaryColor),
      labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: ts),
    );
  }

  static ElevatedButtonThemeData get _elevatedButtonTheme => ElevatedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(primaryColor),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      elevation: WidgetStateProperty.all(0),
      padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd))),
      textStyle: WidgetStateProperty.all(GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
    ),
  );

  static OutlinedButtonThemeData _outlinedButtonTheme(Brightness b) {
    final fg = b == Brightness.dark ? primaryLight : primaryColor;
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: fg, side: BorderSide(color: fg.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
        textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ChipThemeData _chipTheme(Brightness b) {
    final bgColor = b == Brightness.dark ? darkSurfaceVariant : pastelMint;
    final labelColor = b == Brightness.dark ? darkTextSecondary : textSecondary;
    return ChipThemeData(
      backgroundColor: bgColor, selectedColor: primaryColor.withValues(alpha: 0.15),
      labelStyle: GoogleFonts.inter(fontSize: 13, color: labelColor, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    );
  }

  static InputDecorationTheme _inputTheme(Brightness b) {
    final fillColor = b == Brightness.dark ? darkSurfaceVariant : Colors.white.withValues(alpha: 0.7);
    final hintColor = b == Brightness.dark ? darkTextTertiary : textTertiary;
    return InputDecorationTheme(
      filled: true, fillColor: fillColor,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: BorderSide(color: b == Brightness.dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd), borderSide: const BorderSide(color: primaryColor, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      hintStyle: GoogleFonts.inter(fontSize: 14, color: hintColor),
    );
  }
}
