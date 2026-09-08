import 'package:flutter/material.dart';

/// Typography entry points backed by the fonts bundled in `assets/fonts/`.
///
/// These are drop-in replacements for the `GoogleFonts.inter` /
/// `GoogleFonts.plusJakartaSans` calls the app used to make. `google_fonts`
/// fetches typefaces over the network on first launch, so text rendered in
/// fallback Roboto and then visibly swapped once the download landed — and an
/// offline first run never got the right typeface at all, in an app that is
/// otherwise offline-first.
///
/// Both bundled files are *variable* fonts, so one file spans every weight.
/// Flutter does not vary the weight of a variable font from
/// [TextStyle.fontWeight] alone, so the `wght` axis is driven explicitly via
/// [FontVariation]. [TextStyle.fontWeight] is still set so that metrics and any
/// fallback font behave correctly.
class AppFonts {
  const AppFonts._();

  static const String interFamily = 'Inter';
  static const String jakartaFamily = 'PlusJakartaSans';

  static TextStyle _style({
    required String family,
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
    List<Shadow>? shadows,
  }) {
    final weight = fontWeight ?? textStyle?.fontWeight ?? FontWeight.w400;
    final base = TextStyle(
      fontFamily: family,
      fontWeight: weight,
      fontVariations: <FontVariation>[
        FontVariation('wght', weight.value.toDouble()),
      ],
      color: color,
      backgroundColor: backgroundColor,
      fontSize: fontSize,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      wordSpacing: wordSpacing,
      height: height,
      decoration: decoration,
      decorationColor: decorationColor,
      decorationStyle: decorationStyle,
      decorationThickness: decorationThickness,
      shadows: shadows,
    );
    // Mirrors GoogleFonts' behaviour: an explicitly passed textStyle is the
    // base, and the arguments above win over it.
    return textStyle == null ? base : textStyle.merge(base);
  }

  /// Body/UI face. Replaces `GoogleFonts.inter(...)`.
  static TextStyle inter({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
    List<Shadow>? shadows,
  }) =>
      _style(
        family: interFamily,
        textStyle: textStyle,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        height: height,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: decorationThickness,
        shadows: shadows,
      );

  /// Display/heading face. Replaces `GoogleFonts.plusJakartaSans(...)`.
  static TextStyle plusJakartaSans({
    TextStyle? textStyle,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    TextDecoration? decoration,
    Color? decorationColor,
    TextDecorationStyle? decorationStyle,
    double? decorationThickness,
    List<Shadow>? shadows,
  }) =>
      _style(
        family: jakartaFamily,
        textStyle: textStyle,
        color: color,
        backgroundColor: backgroundColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
        height: height,
        decoration: decoration,
        decorationColor: decorationColor,
        decorationStyle: decorationStyle,
        decorationThickness: decorationThickness,
        shadows: shadows,
      );
}
