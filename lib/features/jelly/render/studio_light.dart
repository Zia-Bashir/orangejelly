import 'dart:math' as math;

//* --- [ Studio Light ] ---

/// Shared studio lighting rig (world space, Y up, camera on +Z):
///
/// * a key light from the upper left for diffuse shading,
/// * a large soft overhead softbox behind the specimen — broad sheen on flat
///   tops,
/// * a long thin strip light above the camera — sharp streaks wherever a
///   rounded edge sweeps its reflection across it,
/// * a white sky / warm floor gradient for Fresnel reflections.
abstract final class StudioLight {
  //* ---[ Key light ]---

  static const double lx = -0.42, ly = 0.80, lz = 0.43;

  //* ---[ Softbox ]---

  static const double boxX = 0.0, boxY = 0.66, boxZ = -0.751;

  /// Softbox frame (right / up axes perpendicular to the box direction).
  static final double _bul = math.sqrt(boxZ * boxZ + boxX * boxX);
  static final double buX = -boxZ / _bul, buY = 0, buZ = boxX / _bul;
  static final double bvX = boxY * buZ - boxZ * buY;
  static final double bvY = boxZ * buX - boxX * buZ;
  static final double bvZ = boxX * buY - boxY * buX;

  //* ---[ Strip ]---

  /// Strip runs along world X; its plane holds X and (0, sin θ, cos θ).
  static const double _stripTheta = 1.02;
  static final double stripNy = math.cos(_stripTheta);
  static final double stripNz = -math.sin(_stripTheta);
  static final double stripDy = math.sin(_stripTheta);
  static final double stripDz = math.cos(_stripTheta);

  //* --- [ Reflection ] ---

  /// Radiance reflected along unit direction (rx, ry, rz), scaled by the
  /// Fresnel term [f] (0..1). Returns a grey value (≥ 0, may exceed 1).
  static double reflect(double rx, double ry, double rz, double f) {
    var spec = 0.0;

    //* ---[ Softbox ]---

    final c = rx * boxX + ry * boxY + rz * boxZ;
    if (c > 0.25) {
      final a = (rx * buX + ry * buY + rz * buZ) / c;
      final b = (rx * bvX + ry * bvY + rz * bvZ) / c;
      // Brighter toward one end, like a window: uneven, wet-looking sheen.
      final ramp = 0.55 + 0.45 * _smoothstep(-0.2, 0.15, a);
      final soft = _rect(a, 0.22, 0.20) * _rect(b, 0.16, 0.14) * ramp;
      final core = _rect(a - 0.05, 0.07, 0.06) * _rect(b + 0.01, 0.06, 0.05);
      spec += (soft * 0.8 + core * 0.6) * (0.55 + 0.45 * f);
    }

    //* ---[ Strip ]---

    final along = ry * stripDy + rz * stripDz;
    if (along > 0) {
      final off = (ry * stripNy + rz * stripNz) / 0.05;
      final fall = 1 - _smoothstep(0.45, 0.95, rx.abs());
      spec += math.exp(-off * off) * fall * 0.95 * (0.7 + 0.3 * f);
    }

    //* ---[ Sky / floor ]---

    final sky = ry > 0 ? 0.35 + 0.65 * ry : 0.22 + 0.1 * ry;
    return spec + f * sky * 0.85;
  }

  /// Schlick Fresnel with a gummy-ish base reflectance.
  static double fresnel(double ndv) {
    final m = 1 - ndv;
    final m2 = m * m;
    return 0.04 + 0.96 * m2 * m2 * m;
  }

  static double _rect(double x, double half, double soft) =>
      1 - _smoothstep(half - soft, half, x.abs());

  static double _smoothstep(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
