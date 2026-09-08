import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/app_fonts.dart';

/// The bundled typefaces are *variable* fonts, so the `wght` axis has to be
/// driven explicitly through [FontVariation] — Flutter will not vary a variable
/// font's weight from [TextStyle.fontWeight] alone. That failure mode is silent:
/// every heading would quietly render at regular weight and still look like
/// valid text. These tests pin the wiring down.
double? _wght(TextStyle style) {
  final variations = style.fontVariations;
  if (variations == null) return null;
  for (final variation in variations) {
    if (variation.axis == 'wght') return variation.value;
  }
  return null;
}

void main() {
  group('AppFonts families', () {
    test('inter resolves to the bundled Inter family', () {
      expect(AppFonts.inter().fontFamily, 'Inter');
    });

    test('plusJakartaSans resolves to the bundled family', () {
      expect(AppFonts.plusJakartaSans().fontFamily, 'PlusJakartaSans');
    });

    test('family names match the pubspec font declarations', () {
      expect(AppFonts.interFamily, 'Inter');
      expect(AppFonts.jakartaFamily, 'PlusJakartaSans');
    });
  });

  group('variable weight axis', () {
    test('drives the wght axis from fontWeight', () {
      for (final weight in <FontWeight>[
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
        FontWeight.w900,
      ]) {
        final style = AppFonts.inter(fontWeight: weight);
        expect(style.fontWeight, weight);
        expect(_wght(style), weight.value.toDouble(),
            reason: 'wght axis must track fontWeight for $weight');
      }
    });

    test('defaults to regular when no weight is given', () {
      expect(_wght(AppFonts.inter()), 400.0);
      expect(AppFonts.inter().fontWeight, FontWeight.w400);
    });

    test('applies to the heading face too', () {
      final style = AppFonts.plusJakartaSans(fontWeight: FontWeight.w800);
      expect(_wght(style), 800.0);
    });
  });

  group('passthrough arguments', () {
    test('carries the styling the call sites actually use', () {
      final style = AppFonts.inter(
        fontSize: 13,
        color: const Color(0xFF123456),
        height: 1.5,
        letterSpacing: -0.3,
        fontStyle: FontStyle.italic,
      );
      expect(style.fontSize, 13);
      expect(style.color, const Color(0xFF123456));
      expect(style.height, 1.5);
      expect(style.letterSpacing, -0.3);
      expect(style.fontStyle, FontStyle.italic);
    });

    test('explicit arguments win over a supplied textStyle', () {
      final style = AppFonts.inter(
        textStyle: const TextStyle(fontSize: 99, color: Color(0xFF000000)),
        fontSize: 12,
      );
      expect(style.fontSize, 12);
      expect(style.fontFamily, 'Inter');
    });

    test('inherits weight from a supplied textStyle when none is passed', () {
      final style = AppFonts.inter(
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      );
      expect(style.fontWeight, FontWeight.w700);
      expect(_wght(style), 700.0);
    });
  });
}
