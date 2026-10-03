import 'dart:ui';

//* --- [ Jelly Variety ] ---

enum JellyVariety {
  crimson('Crimson'),
  golden('Golden'),
  rose('Rosé');

  const JellyVariety(this.label);

  final String label;

  JellyPalette get palette => switch (this) {
    JellyVariety.crimson => JellyPalette.crimson,
    JellyVariety.golden => JellyPalette.golden,
    JellyVariety.rose => JellyPalette.rose,
  };
}

//* --- [ Jelly Palette ] ---

/// Material colours of one watermelon variety.
class JellyPalette {
  const JellyPalette({
    required this.fleshDeep,
    required this.fleshLight,
    required this.cream,
    required this.skinDark,
    required this.skinLight,
    required this.seed,
    required this.shadowTint,
  });

  final Color fleshDeep;
  final Color fleshLight;
  final Color cream;
  final Color skinDark;
  final Color skinLight;
  final Color seed;
  final Color shadowTint;

  static const crimson = JellyPalette(
    fleshDeep: Color(0xFFD81E2C),
    fleshLight: Color(0xFFF2545A),
    cream: Color(0xFFE9E4B6),
    skinDark: Color(0xFF173F1A),
    skinLight: Color(0xFF4F8A3C),
    seed: Color(0xFF2B0F0C),
    shadowTint: Color(0xFF7A1E22),
  );

  static const golden = JellyPalette(
    fleshDeep: Color(0xFFE59A1C),
    fleshLight: Color(0xFFF6C454),
    cream: Color(0xFFF2EFD0),
    skinDark: Color(0xFF1C4519),
    skinLight: Color(0xFF5A9440),
    seed: Color(0xFF2E1A0A),
    shadowTint: Color(0xFF8A5A12),
  );

  static const rose = JellyPalette(
    fleshDeep: Color(0xFFE5627A),
    fleshLight: Color(0xFFF59AA6),
    cream: Color(0xFFF3EFD6),
    skinDark: Color(0xFF2E5A2A),
    skinLight: Color(0xFF79A85E),
    seed: Color(0xFF3A1518),
    shadowTint: Color(0xFF8A3A48),
  );
}
