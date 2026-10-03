import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../physics/slice_mesh.dart';
import '../presentation/cubits/knife_state.dart';
import 'jelly_camera.dart';
import 'jelly_renderer.dart';
import 'studio_light.dart';

//* --- [ Knife Renderer ] ---

/// Draws the knife tool as projected 3D geometry: a brushed-steel cleaver
/// blade (bevel band, shoulder highlight, spine), steel bolster and a dark
/// riveted handle, plus its ground shadow and the drawn guide line.
///
/// Local knife frame: u along the blade (heel → tip), v up from the cutting
/// edge, w across the blade. The blade is split at the jelly-top height so
/// the part below can be painted *before* the jelly surface (the jelly then
/// hides it, so the blade looks like it sinks in) and the rest after.
class KnifeRenderer {
  KnifeRenderer() : _outline = _buildOutline();

  //* ---[ Dimensions (sim units) ]---

  static const double bladeLength = 2.7;
  static const double bladeHeight = 0.95;
  static const double spineHalf = 0.022;
  static const double bevelHeight = 0.17;
  static const double bolsterLength = 0.11;
  static const double handleLength = 1.2;
  static const double _heel = -bladeLength / 2;
  static const double _tip = bladeLength / 2;
  static const double _handleV = bladeHeight - 0.2;
  static const int _ring = 16;

  /// Jelly-top height used to split the blade into below / above passes.
  static const double clipY = SliceGeometry.thickness;

  /// Blade outline in (u, v), counter-clockwise.
  final List<Offset> _outline;

  //* ---[ Per-frame pose ]---

  late JellyCamera _cam;
  double _cx = 0, _cz = 0, _ux = 1, _uz = 0, _wx = 0, _wz = 1, _edgeY = 0;
  double _yaw = 0;

  /// Which blade face (+w / −w) looks at the camera.
  double _side = 1;
  final Float64List _p = Float64List(3);

  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Paint _shadow = Paint();
  final Paint _layer = Paint();

  //* --- [ Outline ] ---

  static List<Offset> _buildOutline() {
    const h = bladeHeight;
    final pts = <Offset>[
      const Offset(_heel, h),
      const Offset(_heel, 0.07),
      const Offset(_heel + 0.03, 0.015),
      const Offset(_heel + 0.08, 0),
    ];
    // Straight edge, then a rounded belly sweeping up to the tip.
    const bellyStart = _tip - 0.55;
    pts.add(const Offset(bellyStart, 0));
    const c = Offset(_tip - 0.02, 0.0);
    const end = Offset(_tip, h * 0.42);
    for (var i = 1; i <= 10; i++) {
      final t = i / 10;
      final a = Offset(bellyStart, 0) * ((1 - t) * (1 - t));
      pts.add(a + c * (2 * t * (1 - t)) + end * (t * t));
    }
    pts
      ..add(const Offset(_tip - 0.03, h - 0.09))
      ..add(const Offset(_tip - 0.07, h - 0.02))
      ..add(const Offset(_tip - 0.13, h));
    return pts;
  }

  //* --- [ Pose ] ---

  void _setPose(JellyCamera cam, KnifeState s) {
    _cam = cam;
    _cx = s.x;
    _cz = s.z;
    _yaw = s.yaw;
    _ux = math.cos(s.yaw);
    _uz = math.sin(s.yaw);
    _wx = -_uz;
    _wz = _ux;
    _edgeY = s.edgeY;
    final ex = cam.eyeX - _cx, ez = cam.eyeZ - _cz;
    _side = ex * _wx + ez * _wz >= 0 ? 1 : -1;
  }

  Offset _project(double u, double v, double w) {
    _cam.project(
      _cx + u * _ux + w * _wx,
      _edgeY + v,
      _cz + u * _uz + w * _wz,
      _p,
      0,
    );
    return Offset(_p[0], _p[1]);
  }

  double _depth(double u, double v, double w) {
    _cam.project(
      _cx + u * _ux + w * _wx,
      _edgeY + v,
      _cz + u * _uz + w * _wz,
      _p,
      0,
    );
    return _p[2];
  }

  /// Blade face offset: thick at the spine, tapering to the edge.
  double _faceW(double v) => _side * spineHalf * (v / bladeHeight);

  //* --- [ Shadow ] ---

  /// Ground shadow of blade + handle (paint with the jelly shadows).
  void paintShadow(Canvas canvas, JellyCamera cam, KnifeState s) {
    if (!s.knifeVisible) return;
    _setPose(cam, s);
    const kx = JellyRenderer.shadowX / JellyRenderer.shadowY;
    const kz = JellyRenderer.shadowZ / JellyRenderer.shadowY;
    Offset ground(double u, double v) {
      final x = _cx + u * _ux, z = _cz + u * _uz, y = _edgeY + v;
      cam.project(x - kx * y, 0, z - kz * y, _p, 0);
      return Offset(_p[0], _p[1]);
    }

    final path = Path()
      ..addPolygon([for (final o in _outline) ground(o.dx, o.dy)], true);
    const hf = _heel - bolsterLength, hb = hf - handleLength;
    path.addPolygon([
      ground(_heel, _handleV + 0.15),
      ground(hb, _handleV + 0.16),
      ground(hb, _handleV - 0.16),
      ground(_heel, _handleV - 0.15),
    ], true);
    final lift = 1 / (1 + s.edgeY * 0.9);
    _shadow
      ..color = const Color(
        0xFF231A16,
      ).withValues(alpha: 0.26 * lift * s.opacity)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        cam.pixelsPerUnit * (0.03 + s.edgeY * 0.1),
      );
    canvas.drawPath(path, _shadow);
  }

  //* --- [ Knife ] ---

  /// Paints the knife. With [lowerPass] only the blade below the jelly top
  /// is drawn (call before the jelly surface); otherwise everything above.
  void paintKnife(
    Canvas canvas,
    JellyCamera cam,
    KnifeState s, {
    required bool lowerPass,
  }) {
    if (!s.knifeVisible) return;
    _setPose(cam, s);
    final split = clipY - _edgeY;
    if (lowerPass && split <= 0) return;

    final faded = s.opacity < 0.999;
    if (faded) {
      _layer.color = Color.fromRGBO(0, 0, 0, s.opacity);
      canvas.saveLayer(null, _layer);
    }

    if (lowerPass) {
      _paintBlade(canvas, 0, split, spine: false);
    } else {
      final lo = math.max(0.0, split);
      final bladeDepth = _depth(0, bladeHeight / 2, 0);
      final handleDepth = _depth(_heel - handleLength / 2, _handleV, 0);
      if (handleDepth > bladeDepth) {
        _paintHandle(canvas);
        _paintBolster(canvas);
        _paintBlade(canvas, lo, bladeHeight, spine: true);
      } else {
        _paintBlade(canvas, lo, bladeHeight, spine: true);
        _paintBolster(canvas);
        _paintHandle(canvas);
      }
    }

    if (faded) canvas.restore();
  }

  //* ---[ Blade ]---

  void _paintBlade(
    Canvas canvas,
    double vMin,
    double vMax, {
    required bool spine,
  }) {
    if (vMax - vMin < 1e-4) return;
    final whole = _clipBand(_outline, vMin, vMax);
    if (whole.length < 3) return;
    final bladePath = _facePath(whole);

    //* ---[ Steel lighting for the flat face + bevel ]---

    final k = _steelLight(_side * _wx, 0, _side * _wz);
    final kb = _steelLight(_side * _wx * 0.93, -0.36, _side * _wz * 0.93);

    //* ---[ Main face: brushed vertical gradient ]---

    final main = _clipBand(_outline, math.max(vMin, bevelHeight), vMax);
    if (main.length >= 3) {
      final path = _facePath(main);
      final top = _project(0, bladeHeight, _faceW(bladeHeight));
      final low = _project(0, bevelHeight, _faceW(bevelHeight));
      _fill
        ..shader = Gradient.linear(
          top,
          low,
          [_steel(0.86, k), _steel(0.74, k), _steel(0.56, k), _steel(0.48, k)],
          const [0, 0.35, 0.8, 1],
        )
        ..color = const Color(0xFFFFFFFF);
      canvas.drawPath(path, _fill);
      _fill.shader = null;

      canvas.save();
      canvas.clipPath(path);
      _paintBrushing(canvas, k);
      _paintSheen(canvas);
      canvas.restore();
    }

    //* ---[ Bevel band + cutting edge ]---

    final bevel = _clipBand(_outline, vMin, math.min(vMax, bevelHeight));
    if (bevel.length >= 3) {
      final path = _facePath(bevel);
      final shoulder = _project(0, bevelHeight, _faceW(bevelHeight));
      final edge = _project(0, 0, 0);
      _fill
        ..shader = Gradient.linear(
          shoulder,
          edge,
          [_steel(0.95, kb), _steel(0.70, kb), _steel(0.88, kb)],
          const [0, 0.55, 1],
        )
        ..color = const Color(0xFFFFFFFF);
      canvas.drawPath(path, _fill);
      _fill.shader = null;
    }

    canvas.save();
    canvas.clipPath(bladePath);
    if (bevelHeight > vMin && bevelHeight < vMax) {
      _stroke
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        _project(_heel, bevelHeight, _faceW(bevelHeight)),
        _project(_tip, bevelHeight, _faceW(bevelHeight)),
        _stroke,
      );
    }
    if (vMin <= 0.001) {
      _stroke
        ..color = const Color(0xFFF7F9FA).withValues(alpha: 0.9)
        ..strokeWidth = 1.0;
      final edgePath = Path();
      var started = false;
      for (final o in _outline) {
        if (o.dy > 0.06 && o.dx < _tip - 0.6) continue;
        if (o.dy > bladeHeight * 0.45) continue;
        final q = _project(o.dx, o.dy, 0);
        started ? edgePath.lineTo(q.dx, q.dy) : edgePath.moveTo(q.dx, q.dy);
        started = true;
      }
      canvas.drawPath(edgePath, _stroke);
    }
    canvas.restore();

    //* ---[ Spine ]---

    if (spine && vMax >= bladeHeight - 1e-6) {
      const uEnd = _tip - 0.13;
      final spinePath = Path()
        ..addPolygon([
          _project(_heel, bladeHeight, spineHalf),
          _project(uEnd, bladeHeight, spineHalf),
          _project(uEnd, bladeHeight, -spineHalf),
          _project(_heel, bladeHeight, -spineHalf),
        ], true);
      _fill.color = _steel(0.97, _steelLight(0, 1, 0));
      canvas.drawPath(spinePath, _fill);
    }

    //* ---[ Silhouette ]---

    _stroke
      ..color = const Color(0xFF2B2F33).withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    canvas.drawPath(bladePath, _stroke);
  }

  /// Fine horizontal brushing lines across the blade face.
  void _paintBrushing(Canvas canvas, double k) {
    _stroke.strokeWidth = 0.7;
    final rnd = math.Random(7);
    for (var i = 0; i < 34; i++) {
      final v = bevelHeight + rnd.nextDouble() * (bladeHeight - bevelHeight);
      final light = i.isEven;
      _stroke.color = light
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.05 + 0.06 * k)
          : const Color(0xFF30353A).withValues(alpha: 0.06);
      final u0 = _heel + rnd.nextDouble() * 0.6;
      final u1 = _tip - rnd.nextDouble() * 0.6;
      canvas.drawLine(
        _project(u0, v, _faceW(v)),
        _project(u1, v, _faceW(v)),
        _stroke,
      );
    }
  }

  /// Anisotropic streak along the blade that slides with its orientation.
  void _paintSheen(Canvas canvas) {
    final centre = 0.5 + 0.32 * math.sin(_yaw * 1.3 + 0.6);
    final a = _project(_heel, bladeHeight * 0.6, _faceW(bladeHeight * 0.6));
    final b = _project(_tip, bladeHeight * 0.6, _faceW(bladeHeight * 0.6));
    final lo = (centre - 0.16).clamp(0.0, 1.0);
    final hi = (centre + 0.16).clamp(0.0, 1.0);
    _fill
      ..shader = Gradient.linear(
        a,
        b,
        const [Color(0x00FFFFFF), Color(0x59FFFFFF), Color(0x00FFFFFF)],
        [lo, centre.clamp(lo, hi), hi],
      )
      ..color = const Color(0xFFFFFFFF);
    canvas.drawPaint(_fill);
    _fill.shader = null;
  }

  //* ---[ Handle ]---

  void _paintHandle(Canvas canvas) {
    const hf = _heel - bolsterLength, hb = hf - handleLength;
    _paintPrism(
      canvas,
      uFront: hf,
      uBack: hb,
      halfH: 0.155,
      halfW: 0.088,
      backScale: 1.1,
      base: const (0.15, 0.115, 0.10),
      gloss: 0.32,
    );
    for (final du in [0.2, 0.58, 0.96]) {
      _paintRivet(canvas, hf - du, 0.088 * (1 + 0.1 * du / handleLength));
    }
  }

  void _paintBolster(Canvas canvas) {
    _paintPrism(
      canvas,
      uFront: _heel,
      uBack: _heel - bolsterLength,
      halfH: 0.15,
      halfW: 0.06,
      backScale: 1.0,
      base: const (0.74, 0.76, 0.78),
      gloss: 0.7,
    );
  }

  /// Rounded-rectangle (superellipse) prism along u, flat-shaded per facet.
  void _paintPrism(
    Canvas canvas, {
    required double uFront,
    required double uBack,
    required double halfH,
    required double halfW,
    required double backScale,
    required (double, double, double) base,
    required double gloss,
  }) {
    final ring = <(double, double)>[];
    for (var i = 0; i < _ring; i++) {
      final t = 2 * math.pi * i / _ring;
      final c = math.cos(t), s = math.sin(t);
      ring.add((
        halfW * c.sign * math.pow(c.abs(), 0.55).toDouble(),
        halfH * s.sign * math.pow(s.abs(), 0.55).toDouble(),
      ));
    }
    final ex = _cam.eyeX, ey = _cam.eyeY, ez = _cam.eyeZ;

    for (var i = 0; i < _ring; i++) {
      final (w0, v0) = ring[i];
      final (w1, v1) = ring[(i + 1) % _ring];
      // Outward facet normal in (w, v), then to world.
      var nw = v1 - v0, nv = -(w1 - w0);
      final nl = math.sqrt(nw * nw + nv * nv);
      nw /= nl;
      nv /= nl;
      final nx = nw * _wx, ny = nv, nz = nw * _wz;
      final um = (uFront + uBack) / 2;
      final px = _cx + um * _ux + (w0 + w1) / 2 * _wx;
      final py = _edgeY + _handleV + (v0 + v1) / 2;
      final pz = _cz + um * _uz + (w0 + w1) / 2 * _wz;
      if (nx * (ex - px) + ny * (ey - py) + nz * (ez - pz) <= 0) continue;
      final path = Path()
        ..addPolygon([
          _project(uFront, _handleV + v0, w0),
          _project(uFront, _handleV + v1, w1),
          _project(uBack, _handleV + v1 * backScale, w1 * backScale),
          _project(uBack, _handleV + v0 * backScale, w0 * backScale),
        ], true);
      _fill.color = _shadeSolid(base, gloss, nx, ny, nz, px, py, pz);
      canvas.drawPath(path, _fill);
    }

    //* ---[ End caps ]---

    for (final (u, sign, scale) in [
      (uBack, -1.0, backScale),
      (uFront, 1.0, 1.0),
    ]) {
      final nx = _ux * sign, nz = _uz * sign;
      final px = _cx + u * _ux, py = _edgeY + _handleV, pz = _cz + u * _uz;
      if (nx * (ex - px) + nz * (ez - pz) <= 0) continue;
      final path = Path()
        ..addPolygon([
          for (final (w, v) in ring)
            _project(u, _handleV + v * scale, w * scale),
        ], true);
      _fill.color = _shadeSolid(base, gloss, nx, 0, nz, px, py, pz);
      canvas.drawPath(path, _fill);
    }
  }

  void _paintRivet(Canvas canvas, double u, double w) {
    const r = 0.042;
    final ww = _side * w;
    final c = _project(u, _handleV, ww);
    final a = _project(u + r, _handleV, ww) - c;
    final b = _project(u, _handleV + r, ww) - c;
    Path ellipse(double scale) {
      final path = Path();
      for (var i = 0; i <= 14; i++) {
        final t = 2 * math.pi * i / 14;
        final q = c + a * (math.cos(t) * scale) + b * (math.sin(t) * scale);
        i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
      }
      return path..close();
    }

    _fill.color = const Color(0xFF2E3236);
    canvas.drawPath(ellipse(1.15), _fill);
    final radius = math.max(1.0, math.max(a.distance, b.distance));
    _fill
      ..shader = Gradient.radial(
        c - b * 0.35 - a * 0.25,
        radius * 1.4,
        const [Color(0xFFF4F6F7), Color(0xFFA9B0B6), Color(0xFF5E656B)],
        const [0, 0.5, 1],
      )
      ..color = const Color(0xFFFFFFFF);
    canvas.drawPath(ellipse(1.0), _fill);
    _fill.shader = null;
  }

  //* --- [ Lighting ] ---

  /// Brightness multiplier for a steel facet with world normal n.
  double _steelLight(double nx, double ny, double nz) {
    final l = math.sqrt(nx * nx + ny * ny + nz * nz);
    nx /= l;
    ny /= l;
    nz /= l;
    var vx = _cam.eyeX - _cx, vy = _cam.eyeY - (_edgeY + bladeHeight / 2);
    var vz = _cam.eyeZ - _cz;
    final vl = math.sqrt(vx * vx + vy * vy + vz * vz);
    vx /= vl;
    vy /= vl;
    vz /= vl;
    final ndv = (nx * vx + ny * vy + nz * vz).abs();
    final d2 = 2 * ndv;
    final env = StudioLight.reflect(
      d2 * nx - vx,
      d2 * ny - vy,
      d2 * nz - vz,
      StudioLight.fresnel(ndv),
    );
    final diffuse = math.max(
      0.0,
      nx * StudioLight.lx + ny * StudioLight.ly + nz * StudioLight.lz,
    );
    return (0.8 + 0.22 * diffuse + 0.45 * math.min(1.0, env)).clamp(0.6, 1.3);
  }

  static Color _steel(double grey, double k) {
    final g = (grey * k).clamp(0.0, 1.0);
    // Slightly cool steel tint.
    return Color.from(
      alpha: 1,
      red: (g * 0.97).clamp(0.0, 1.0),
      green: (g * 0.99).clamp(0.0, 1.0),
      blue: g,
    );
  }

  Color _shadeSolid(
    (double, double, double) base,
    double gloss,
    double nx,
    double ny,
    double nz,
    double px,
    double py,
    double pz,
  ) {
    var vx = _cam.eyeX - px, vy = _cam.eyeY - py, vz = _cam.eyeZ - pz;
    final vl = math.sqrt(vx * vx + vy * vy + vz * vz);
    vx /= vl;
    vy /= vl;
    vz /= vl;
    final ndl = nx * StudioLight.lx + ny * StudioLight.ly + nz * StudioLight.lz;
    final wrap = math.max(0.0, (ndl + 0.3) / 1.3);
    final ndv = math.max(0.0, nx * vx + ny * vy + nz * vz);
    final d2 = 2 * ndv;
    final spec =
        StudioLight.reflect(
          d2 * nx - vx,
          d2 * ny - vy,
          d2 * nz - vz,
          StudioLight.fresnel(ndv),
        ) *
        gloss;
    final light = 0.35 + 0.75 * wrap;
    return Color.from(
      alpha: 1,
      red: (base.$1 * light + spec).clamp(0.0, 1.0),
      green: (base.$2 * light + spec).clamp(0.0, 1.0),
      blue: (base.$3 * light + spec).clamp(0.0, 1.0),
    );
  }

  //* --- [ Guide Line ] ---

  /// Dashed preview of the drawn cut line with start / end markers.
  void paintGuide(Canvas canvas, KnifeState s) {
    if (!s.guideVisible) return;
    final a = s.guideStart!, b = s.guideEnd!;
    final o = s.guideOpacity;
    final d = b - a;
    final len = d.distance;

    if (len > 2) {
      _stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 6
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5 * o);
      canvas.drawLine(a, b, _stroke);
      _stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF161513).withValues(alpha: 0.85 * o);
      final dir = d / len;
      const dash = 7.0, gap = 5.0;
      for (var t = 0.0; t < len; t += dash + gap) {
        canvas.drawLine(
          a + dir * t,
          a + dir * math.min(len, t + dash),
          _stroke,
        );
      }
      _stroke.strokeCap = StrokeCap.butt;
    }

    _fill.color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * o);
    canvas.drawCircle(a, 5, _fill);
    _stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFF161513).withValues(alpha: 0.9 * o);
    canvas.drawCircle(a, 3.6, _stroke);
    if (len > 2) {
      canvas.drawCircle(b, 5, _fill);
      _fill.color = const Color(0xFF161513).withValues(alpha: 0.9 * o);
      canvas.drawCircle(b, 3.2, _fill);
    }
  }

  //* --- [ Geometry Helpers ] ---

  Path _facePath(List<Offset> uv) => Path()
    ..addPolygon([
      for (final q in uv) _project(q.dx, q.dy, _faceW(q.dy)),
    ], true);

  /// Sutherland–Hodgman clip of polygon [poly] (u, v) to lo ≤ v ≤ hi.
  static List<Offset> _clipBand(List<Offset> poly, double lo, double hi) {
    List<Offset> clip(List<Offset> input, double c, bool keepAbove) {
      final out = <Offset>[];
      if (input.isEmpty) return out;
      bool inside(Offset p) => keepAbove ? p.dy >= c : p.dy <= c;
      var prev = input.last;
      for (final cur in input) {
        final ci = inside(cur), pi = inside(prev);
        if (ci != pi) {
          final t = (c - prev.dy) / (cur.dy - prev.dy);
          out.add(Offset(prev.dx + (cur.dx - prev.dx) * t, c));
        }
        if (ci) out.add(cur);
        prev = cur;
      }
      return out;
    }

    return clip(clip(poly, lo, true), hi, false);
  }
}
