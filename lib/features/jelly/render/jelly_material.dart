import 'dart:math' as math;
import 'dart:typed_data';

import '../physics/slice_mesh.dart';
import 'jelly_palette.dart';

//* --- [ Jelly Material ] ---

/// Procedural watermelon colouring evaluated in material (rest) space, so
/// outer skin, cream rind, flesh, seeds and freshly cut faces all colour
/// themselves consistently wherever the jelly is sliced.
///
/// Each sample is 4 floats: linear-ish RGB (0..1) plus a translucency weight
/// the renderer turns into subsurface glow (high where the flesh is thin).
class JellyMaterial {
  JellyMaterial(this.palette) : _seeds = _buildSeeds();

  final JellyPalette palette;
  final Float64List _seeds;

  /// Floats written per sample by [evaluate]: r, g, b, translucency, and the
  /// material-space x / z slope of the top-surface pillow dome.
  static const int stride = 6;

  //* ---[ Top-surface shape (render only) ]---

  /// Slope of the rounded edge where the top meets the outline (≈ 42°),
  /// easing to flat over [_edgeBand] sim units.
  static const double _edgeSlope = 0.9;
  static const double _edgeBand = 0.26;

  /// Broad pillow dome over the whole top.
  static const double _domeHeight = 0.06;
  static const double _domeReach = 1.0;

  static const double _seedAlong = 0.105;
  static const double _seedAcross = 0.060;
  static const double _seedVertical = 0.34;

  //* ---[ Seed layout ]---

  /// Seeds sit in arcs across the flesh (x, y, z, cos φ, sin φ per seed).
  static Float64List _buildSeeds() {
    const rows = [(0.36, 3), (0.50, 4), (0.63, 5), (0.75, 6)];
    final rnd = math.Random(9);
    final out = <double>[];
    const r = SliceGeometry.radius;
    const half = SliceGeometry.angle / 2;
    for (final (frac, count) in rows) {
      for (var k = 0; k < count; k++) {
        final t = (k + 0.5) / count;
        final phi =
            -half * 0.76 + half * 1.52 * t + (rnd.nextDouble() - .5) * .08;
        final rad = r * frac + (rnd.nextDouble() - 0.5) * 0.1;
        final y = SliceGeometry.thickness * (0.62 + rnd.nextDouble() * 0.16);
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

  /// Seed layout: x, y, z, cos φ, sin φ per seed (material space).
  Float64List get seeds => _seeds;

  /// Seed half-length / half-width in material units (for decals).
  static const double seedLength = _seedAlong;
  static const double seedWidth = _seedAcross;

  /// Writes RGB + translucency for material point (x, y, z) into [out] at [o].
  ///
  /// With [topSurface] true only the darker pocket around each seed is
  /// painted (the renderer draws crisp seed decals there instead) and the
  /// top-surface slope (rounded edge + pillow dome) is written; otherwise
  /// the slope is zero.
  void evaluate(
    double x,
    double y,
    double z,
    Float32List out,
    int o, {
    bool topSurface = false,
  }) {
    if (topSurface) {
      _topSlope(x, z, out, o + 4);
    } else {
      out[o + 4] = 0;
      out[o + 5] = 0;
    }
    final seedBodies = !topSurface;
    const radius = SliceGeometry.radius;
    const thick = SliceGeometry.thickness;
    final rxz = math.sqrt(x * x + z * z);
    final r = rxz / radius;
    final phi = math.atan2(z, x);
    final p = palette;

    //* ---[ Distance to the flesh boundaries ]---

    final dTop = math.max(0.0, thick - y);
    final dBottom = math.max(0.0, y);
    final dSide = math.max(
      0.0,
      rxz * math.sin(SliceGeometry.angle / 2 - phi.abs()),
    );
    final dRind = math.max(0.0, (SliceGeometry.fleshEnd - r) * radius);
    var d1 = dTop, d2 = dBottom;
    if (d2 < d1) {
      final t = d1;
      d1 = d2;
      d2 = t;
    }
    for (final d in [dSide, dRind]) {
      if (d < d1) {
        d2 = d1;
        d1 = d;
      } else if (d < d2) {
        d2 = d;
      }
    }

    //* ---[ Flesh: deep core, lighter translucent skin ]---

    final radial = _smooth(0.25, SliceGeometry.fleshEnd, r);
    final core = _smooth(0.0, 0.2, d1);
    final lightness = (0.34 * radial + 0.16 * (1 - core)).clamp(0.0, 1.0);
    var cr = _lerp(p.fleshDeep.r, p.fleshLight.r, lightness);
    var cg = _lerp(p.fleshDeep.g, p.fleshLight.g, lightness);
    var cb = _lerp(p.fleshDeep.b, p.fleshLight.b, lightness);

    // Thin where two boundaries meet (edges, the tip, along the rind).
    var glow = math.exp(-(d1 + d2) / 0.32) * 0.85 + (1 - core) * 0.25;

    //* ---[ Seeds ]---

    final (seed, halo) = _seedStrength(x, y, z);
    if (halo > 0) {
      cr = _lerp(cr, p.fleshDeep.r * 0.82, halo * 0.55);
      cg = _lerp(cg, p.fleshDeep.g * 0.82, halo * 0.55);
      cb = _lerp(cb, p.fleshDeep.b * 0.82, halo * 0.55);
    }
    if (seed > 0 && seedBodies) {
      cr = _lerp(cr, p.seed.r, seed);
      cg = _lerp(cg, p.seed.g, seed);
      cb = _lerp(cb, p.seed.b, seed);
      glow *= 1 - seed;
    }

    //* ---[ Cream rind (soft blush → cream → pale green) ]---

    final blush = _smooth(
      SliceGeometry.fleshEnd - 0.07,
      SliceGeometry.fleshEnd,
      r,
    );
    if (blush > 0) {
      final pr = _lerp(p.fleshLight.r, p.cream.r, 0.55);
      final pg = _lerp(p.fleshLight.g, p.cream.g, 0.55);
      final pb = _lerp(p.fleshLight.b, p.cream.b, 0.55);
      final t = blush * 0.6;
      cr = _lerp(cr, pr, t);
      cg = _lerp(cg, pg, t);
      cb = _lerp(cb, pb, t);
    }
    final creamT = _smooth(
      SliceGeometry.fleshEnd - 0.02,
      SliceGeometry.fleshEnd + 0.025,
      r,
    );
    if (creamT > 0) {
      final greenish =
          _smooth(
            SliceGeometry.fleshEnd + 0.02,
            SliceGeometry.creamEnd + 0.01,
            r,
          ) *
          0.55;
      final rr = _lerp(p.cream.r, p.skinLight.r, greenish);
      final gg = _lerp(p.cream.g, p.skinLight.g, greenish);
      final bb = _lerp(p.cream.b, p.skinLight.b, greenish);
      cr = _lerp(cr, rr, creamT);
      cg = _lerp(cg, gg, creamT);
      cb = _lerp(cb, bb, creamT);
      glow *= 1 - creamT * 0.7;
    }

    //* ---[ Striped green skin ]---

    final skinT = _smooth(
      SliceGeometry.creamEnd - 0.012,
      SliceGeometry.creamEnd + 0.02,
      r,
    );
    if (skinT > 0) {
      final s = phi * radius;
      final yn = y / thick;
      final warp =
          0.06 * math.sin(yn * 6.0 + s * 4.1) +
          0.025 * math.sin(yn * 13.0 - s * 9.3);
      final v = s * 11.5 + warp * 11 + 0.8 * math.sin(s * 2.6 + 1.7);
      final widthMod = 0.22 * math.sin(s * 4.7 + 0.8);
      final dark = _smooth(-0.35 + widthMod, 0.15 + widthMod, math.sin(v));
      final speckle = (_hash(x * 3.1, y * 2.7, z * 3.3) - 0.5) * 0.05;
      final rr = _lerp(p.skinLight.r, p.skinDark.r, dark * 0.92) + speckle;
      final gg = _lerp(p.skinLight.g, p.skinDark.g, dark * 0.92) + speckle;
      final bb = _lerp(p.skinLight.b, p.skinDark.b, dark * 0.92) + speckle;
      cr = _lerp(cr, rr, skinT);
      cg = _lerp(cg, gg, skinT);
      cb = _lerp(cb, bb, skinT);
      glow *= 1 - skinT;
    }

    //* ---[ Fine grain ]---

    final grain = (_hash(x, y, z) - 0.5) * 0.015;
    out[o] = (cr + grain).clamp(0.0, 1.0);
    out[o + 1] = (cg + grain).clamp(0.0, 1.0);
    out[o + 2] = (cb + grain).clamp(0.0, 1.0);
    out[o + 3] = glow.clamp(0.0, 1.0);
  }

  /// (seed body, surrounding pocket) strengths — soft teardrops that read as
  /// embedded a little below the surface rather than painted on.
  (double, double) _seedStrength(double x, double y, double z) {
    final seeds = _seeds;
    var best = 0.0;
    var halo = 0.0;
    for (var i = 0; i < seeds.length; i += 5) {
      final dx = x - seeds[i];
      final dz = z - seeds[i + 2];
      if (dx * dx + dz * dz > 0.06) continue;
      final along = dx * seeds[i + 3] + dz * seeds[i + 4];
      final across = -dx * seeds[i + 4] + dz * seeds[i + 3];
      final dy = (y - seeds[i + 1]) / _seedVertical;
      // Teardrop: narrower toward the apex (negative along).
      final width = _seedAcross * (along < 0 ? 0.62 + 0.6 * along.abs() : 1.0);
      final a = along / _seedAlong, c = across / width;
      final d = math.sqrt(a * a + c * c + dy * dy);
      final s = 1 - _smooth(0.1, 1.2, d);
      if (s > best) best = s;
      final h = 1 - _smooth(0.8, 2.0, d);
      if (h > halo) halo = h;
    }
    return (math.min(1.0, best * 1.15) * 0.88, halo);
  }

  /// Material-space slope (∂h/∂x, ∂h/∂z) of the top surface's height field:
  /// a rounded edge along the outline plus a broad dome and a faint ripple
  /// so reflections break up like a wet surface. Analytic in material space,
  /// so highlights stay smooth regardless of the triangulation.
  static void _topSlope(double x, double z, Float32List out, int o) {
    const e = 0.005;
    final d = math.max(0.0, _outlineDistance(x, z));
    final gx =
        (_outlineDistance(x + e, z) - _outlineDistance(x - e, z)) / (2 * e);
    final gz =
        (_outlineDistance(x, z + e) - _outlineDistance(x, z - e)) / (2 * e);
    final u = math.max(0.0, 1 - d / _edgeBand);
    final edge = _edgeSlope * u * u;

    // Smooth Gaussian pillow over the wedge body (no medial-axis crease).
    const cx = SliceGeometry.radius * 0.6;
    const sx = 0.95 * _domeReach, sz = 0.55 * _domeReach;
    final ddx = x - cx;
    final bump = _domeHeight * math.exp(-(ddx * ddx / sx + z * z / sz));
    final domeX = -bump * 2 * ddx / sx;
    final domeZ = -bump * 2 * z / sz;

    out[o] = edge * gx + domeX + 0.024 * math.cos(x * 4.3 + z * 2.1);
    out[o + 1] = edge * gz + domeZ + 0.02 * math.cos(z * 3.7 - x * 1.3);
  }

  /// Signed distance from (x, z) to the top face's outline (straight sides +
  /// arc), measured from the bevelled cap edge (negative outside it).
  static double _outlineDistance(double x, double z) {
    final rxz = math.sqrt(x * x + z * z);
    final phi = math.atan2(z, x);
    final dSide = rxz * math.sin(SliceGeometry.angle / 2 - phi.abs());
    final dArc = SliceGeometry.radius - rxz;
    return math.min(dSide, dArc) - SliceGeometry.bevel;
  }

  /// True when material point (x, z) sits on the uncut top outline, where
  /// [evaluate]'s analytic edge slope replaces mesh-averaged normals.
  static bool onTopOutline(double x, double z) => _outlineDistance(x, z) < 0.03;

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
