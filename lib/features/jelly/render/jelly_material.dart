import 'dart:math' as math;
import 'dart:typed_data';

import '../physics/slice_mesh.dart';
import 'jelly_palette.dart';

//* --- [ Jelly Material ] ---

/// Procedural watermelon colouring evaluated in material (rest) space, so
/// outer skin, cream rind, flesh, seeds and freshly cut faces all colour
/// themselves consistently wherever the jelly is sliced.
class JellyMaterial {
  JellyMaterial(this.palette) : _seeds = _buildSeeds();

  final JellyPalette palette;
  final Float64List _seeds;

  static const double _seedAlong = 0.085;
  static const double _seedAcross = 0.048;
  static const double _seedVertical = 0.24;

  //* ---[ Seed layout ]---

  /// Seeds sit in arcs across the flesh (x, y, z, cos φ, sin φ per seed).
  static Float64List _buildSeeds() {
    const rows = [(0.34, 3), (0.48, 4), (0.61, 5), (0.73, 6)];
    final rnd = math.Random(9);
    final out = <double>[];
    const r = SliceGeometry.radius;
    const half = SliceGeometry.angle / 2;
    for (final (frac, count) in rows) {
      for (var k = 0; k < count; k++) {
        final t = (k + 0.5) / count;
        final phi =
            -half * 0.78 + half * 1.56 * t + (rnd.nextDouble() - .5) * .06;
        final rad = r * frac + (rnd.nextDouble() - 0.5) * 0.08;
        final y = SliceGeometry.thickness * (0.55 + rnd.nextDouble() * 0.2);
        out.addAll([
          rad * math.cos(phi),
          y,
          rad * math.sin(phi),
          math.cos(phi),
          math.sin(phi),
        ]);
      }
    }
    return Float64List.fromList(out);
  }

  //* --- [ Evaluate ] ---

  /// Writes linear RGB (0..1) for material point (x, y, z) into [out] at [o].
  void evaluate(double x, double y, double z, Float32List out, int o) {
    const radius = SliceGeometry.radius;
    final r = math.sqrt(x * x + z * z) / radius;
    final phi = math.atan2(z, x);
    final p = palette;

    double cr, cg, cb;

    //* ---[ Flesh gradient ]---

    final fleshT = _smooth(0.45, SliceGeometry.fleshEnd, r);
    cr = _lerp(p.fleshDeep.r, p.fleshLight.r, fleshT);
    cg = _lerp(p.fleshDeep.g, p.fleshLight.g, fleshT);
    cb = _lerp(p.fleshDeep.b, p.fleshLight.b, fleshT);

    //* ---[ Seeds ]---

    final s = _seedStrength(x, y, z);
    if (s > 0) {
      cr = _lerp(cr, p.seed.r, s);
      cg = _lerp(cg, p.seed.g, s);
      cb = _lerp(cb, p.seed.b, s);
    }

    //* ---[ Cream rind ]---

    final creamT = _smooth(
      SliceGeometry.fleshEnd - 0.012,
      SliceGeometry.fleshEnd + 0.012,
      r,
    );
    if (creamT > 0) {
      final greenish = _smooth(0.89, SliceGeometry.creamEnd, r) * 0.35;
      final rr = _lerp(p.cream.r, p.skinLight.r, greenish);
      final gg = _lerp(p.cream.g, p.skinLight.g, greenish);
      final bb = _lerp(p.cream.b, p.skinLight.b, greenish);
      cr = _lerp(cr, rr, creamT);
      cg = _lerp(cg, gg, creamT);
      cb = _lerp(cb, bb, creamT);
    }

    //* ---[ Striped green skin ]---

    final skinT = _smooth(
      SliceGeometry.creamEnd - 0.01,
      SliceGeometry.creamEnd + 0.012,
      r,
    );
    if (skinT > 0) {
      final wave = math.sin(phi * 44 + 1.6 * math.sin(y * 10 + phi * 13));
      final stripe = _smooth(0.15, 0.75, wave);
      final rr = _lerp(p.skinDark.r, p.skinLight.r, stripe * 0.75);
      final gg = _lerp(p.skinDark.g, p.skinLight.g, stripe * 0.75);
      final bb = _lerp(p.skinDark.b, p.skinLight.b, stripe * 0.75);
      cr = _lerp(cr, rr, skinT);
      cg = _lerp(cg, gg, skinT);
      cb = _lerp(cb, bb, skinT);
    }

    //* ---[ Fine grain ]---

    final grain = (_hash(x, y, z) - 0.5) * 0.05;
    out[o] = (cr + grain).clamp(0.0, 1.0);
    out[o + 1] = (cg + grain).clamp(0.0, 1.0);
    out[o + 2] = (cb + grain).clamp(0.0, 1.0);
  }

  double _seedStrength(double x, double y, double z) {
    final seeds = _seeds;
    var best = 0.0;
    for (var i = 0; i < seeds.length; i += 5) {
      final dx = x - seeds[i];
      final dz = z - seeds[i + 2];
      final along = dx * seeds[i + 3] + dz * seeds[i + 4];
      final across = -dx * seeds[i + 4] + dz * seeds[i + 3];
      final dy = (y - seeds[i + 1]) / _seedVertical;
      // Teardrop: narrower toward the apex (negative along).
      final width = _seedAcross * (along < 0 ? 0.7 : 1.0);
      final a = along / _seedAlong, c = across / width;
      final d = math.sqrt(a * a + c * c + dy * dy);
      final s = 1 - _smooth(0.55, 1.05, d);
      if (s > best) best = s;
    }
    return best * 0.92;
  }

  //* ---[ Helpers ]---

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _smooth(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static double _hash(double x, double y, double z) {
    final v = math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453;
    return v - v.floorToDouble();
  }
}
