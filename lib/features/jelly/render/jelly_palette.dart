import 'dart:ui';

//* --- [ Jelly Variety ] ---

enum JellyVariety {
  navel('Navel'),
  blood('Blood'),
  cara('Cara Cara');

  const JellyVariety(this.label);

  final String label;

  JellyPalette get palette => switch (this) {
    JellyVariety.navel => JellyPalette.navel,
    JellyVariety.blood => JellyPalette.blood,
    JellyVariety.cara => JellyPalette.cara,
  };
}

//* --- [ Jelly Palette ] ---

/// Material colours of one orange variety: flesh, white pith, peel, pips.
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

  /// White pith between flesh and peel.
  final Color cream;
  final Color skinDark;
  final Color skinLight;
  final Color seed;
  final Color shadowTint;

  /// Classic bright navel: juicy orange flesh, white pith, dimpled peel.
  static const navel = JellyPalette(
    fleshDeep: Color(0xFFE25A08),
    fleshLight: Color(0xFFFFB15A),
    cream: Color(0xFFF6F1E4),
    skinDark: Color(0xFFC24E0C),
    skinLight: Color(0xFFF3922A),
    seed: Color(0xFFF4E6C4),
    shadowTint: Color(0xFFC45A18),
  );

  /// Blood orange: burgundy flesh, russet peel.
  static const blood = JellyPalette(
    fleshDeep: Color(0xFF8C1828),
    fleshLight: Color(0xFFE25A48),
    cream: Color(0xFFF4EBDC),
    skinDark: Color(0xFF6A2416),
    skinLight: Color(0xFFE07838),
    seed: Color(0xFFF0DCC4),
    shadowTint: Color(0xFF6A1820),
  );

  /// Cara Cara: salmon-pink flesh, warm orange peel.
  static const cara = JellyPalette(
    fleshDeep: Color(0xFFE87858),
    fleshLight: Color(0xFFFFC6A4),
    cream: Color(0xFFF7F2E6),
    skinDark: Color(0xFFD06018),
    skinLight: Color(0xFFF4A24A),
    seed: Color(0xFFF6E8D0),
    shadowTint: Color(0xFFC06040),
  );
}
