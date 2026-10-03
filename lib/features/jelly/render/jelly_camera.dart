import 'dart:math' as math;
import 'dart:typed_data';

//* --- [ Jelly Camera ] ---

/// Perspective camera orbiting the stage origin from slightly above, matching
/// the reference three-quarter view. Screen space is logical pixels, Y down.
class JellyCamera {
  JellyCamera({
    this.elevation = 0.70,
    this.azimuth = 0,
    this.distance = 10,
    this.targetY = 0.2,
  }) {
    _updateBasis();
  }

  final double elevation;
  final double azimuth;
  final double distance;
  final double targetY;

  //* ---[ Basis ]---

  double eyeX = 0, eyeY = 0, eyeZ = 0;
  double fx = 0, fy = 0, fz = 0;
  double rx = 0, ry = 0, rz = 0;
  double ux = 0, uy = 0, uz = 0;

  //* ---[ Viewport ]---

  double width = 1;
  double height = 1;
  double centerX = 0.5;
  double centerY = 0.5;

  /// Pixels per world unit at the target depth.
  double pixelsPerUnit = 100;

  void _updateBasis() {
    final ce = math.cos(elevation), se = math.sin(elevation);
    eyeX = distance * ce * math.sin(azimuth);
    eyeY = targetY + distance * se;
    eyeZ = distance * ce * math.cos(azimuth);
    final dx = -eyeX, dy = targetY - eyeY, dz = -eyeZ;
    final fl = math.sqrt(dx * dx + dy * dy + dz * dz);
    fx = dx / fl;
    fy = dy / fl;
    fz = dz / fl;
    // right = forward × worldUp(0,1,0)
    var cx = -fz, cz = fx;
    final cl = math.sqrt(cx * cx + cz * cz);
    cx /= cl;
    cz /= cl;
    rx = cx;
    ry = 0;
    rz = cz;
    // up = right × forward
    ux = ry * fz - rz * fy;
    uy = rz * fx - rx * fz;
    uz = rx * fy - ry * fx;
  }

  /// Fits the specimen (≈ [worldExtent] units wide) into the focus region
  /// (left, top, right, bottom insets in pixels) of a w × h viewport.
  void configure(
    double w,
    double h, {
    double insetLeft = 0,
    double insetTop = 0,
    double insetRight = 0,
    double insetBottom = 0,
    double worldExtent = 3.3,
    double fill = 0.72,
  }) {
    width = w;
    height = h;
    final fw = math.max(1.0, w - insetLeft - insetRight);
    final fh = math.max(1.0, h - insetTop - insetBottom);
    centerX = insetLeft + fw / 2;
    centerY = insetTop + fh / 2;
    pixelsPerUnit = math.min(fw * fill, fh * fill * 1.15) / worldExtent;
  }

  //* --- [ Projection ] ---

  /// Writes (screenX, screenY, depth) of the world point into [out] at [o].
  /// Returns false when the point is behind the camera.
  bool project(double x, double y, double z, Float64List out, int o) {
    final px = x - eyeX, py = y - eyeY, pz = z - eyeZ;
    final depth = px * fx + py * fy + pz * fz;
    if (depth < 1e-3) {
      out[o] = centerX;
      out[o + 1] = centerY;
      out[o + 2] = 1e-3;
      return false;
    }
    final k = pixelsPerUnit * distance / depth;
    out[o] = centerX + (px * rx + py * ry + pz * rz) * k;
    out[o + 1] = centerY - (px * ux + py * uy + pz * uz) * k;
    out[o + 2] = depth;
    return true;
  }

  /// Unit ray direction through a screen point, written into [out] (xyz).
  void rayDirection(double sx, double sy, Float64List out) {
    final s = pixelsPerUnit * distance;
    final a = (sx - centerX) / s;
    final b = -(sy - centerY) / s;
    var dx = fx + rx * a + ux * b;
    var dy = fy + ry * a + uy * b;
    var dz = fz + rz * a + uz * b;
    final l = math.sqrt(dx * dx + dy * dy + dz * dz);
    dx /= l;
    dy /= l;
    dz /= l;
    out[0] = dx;
    out[1] = dy;
    out[2] = dz;
  }
}
