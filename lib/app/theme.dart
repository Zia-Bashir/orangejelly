import 'package:flutter/material.dart';

//* --- [ Colors ] ---

abstract final class JellyColors {
  static const background = Color(0xFFEAE7E2);
  static const panel = Color(0xFFEDEAE6);
  static const ink = Color(0xFF161513);
  static const inkSoft = Color(0xFF3A3733);
  static const muted = Color(0xFF8C8882);
  static const faint = Color(0xFFABA69F);
  static const line = Color(0xFFCDC9C2);
  static const lineStrong = Color(0xFFB9B4AC);
  static const live = Color(0xFF7FB38A);
  static const paused = Color(0xFFD7A54A);
}

//* --- [ Typography ] ---

abstract final class JellyText {
  static const _serif = 'InstrumentSerif';
  static const _mono = 'PlexMono';
  static const _sans = 'Inter';
  static const _fallback = ['Inter'];

  static TextStyle title(double size) => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _fallback,
    fontStyle: FontStyle.italic,
    fontSize: size,
    height: 0.92,
    letterSpacing: -size * 0.02,
    color: JellyColors.ink,
  );

  static const tagline = TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _fallback,
    fontSize: 15.5,
    height: 1.35,
    color: JellyColors.inkSoft,
  );

  static const serifItalic = TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _fallback,
    fontStyle: FontStyle.italic,
    fontSize: 14,
    height: 1.4,
    color: JellyColors.ink,
  );

  static const caption = TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _fallback,
    fontStyle: FontStyle.italic,
    fontSize: 11.5,
    color: JellyColors.muted,
  );

  static const label = TextStyle(
    fontFamily: _sans,
    fontSize: 9.5,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w500,
    fontVariations: [FontVariation('wght', 500)],
    color: JellyColors.inkSoft,
  );

  static const button = TextStyle(
    fontFamily: _sans,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontVariations: [FontVariation('wght', 420)],
    color: JellyColors.ink,
  );

  static const small = TextStyle(
    fontFamily: _sans,
    fontSize: 10,
    height: 1.45,
    fontVariations: [FontVariation('wght', 400)],
    color: JellyColors.faint,
  );

  static const mono = TextStyle(
    fontFamily: _mono,
    fontSize: 11,
    letterSpacing: 0.6,
    color: JellyColors.ink,
  );

  static const statValue = TextStyle(
    fontFamily: _mono,
    fontSize: 19,
    fontWeight: FontWeight.w500,
    color: JellyColors.ink,
  );

  static const statUnit = TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _fallback,
    fontStyle: FontStyle.italic,
    fontSize: 11,
    color: JellyColors.muted,
  );
}

//* --- [ Theme ] ---

ThemeData buildJellyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: JellyColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFE86A12),
      surface: JellyColors.background,
    ),
    fontFamily: 'Inter',
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    sliderTheme: const SliderThemeData(
      trackHeight: 1,
      activeTrackColor: JellyColors.inkSoft,
      inactiveTrackColor: JellyColors.lineStrong,
      thumbColor: JellyColors.background,
      overlayColor: Color(0x14161513),
      thumbShape: _RingThumbShape(),
      trackShape: RectangularSliderTrackShape(),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
  );
}

//* ---[ Slider thumb ]---

class _RingThumbShape extends SliderComponentShape {
  const _RingThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(12);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 5.5, Paint()..color = JellyColors.background);
    canvas.drawCircle(
      center,
      5.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = JellyColors.inkSoft,
    );
  }
}
