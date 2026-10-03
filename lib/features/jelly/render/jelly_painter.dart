import 'package:flutter/rendering.dart';

import '../physics/jelly_engine.dart';
import 'jelly_camera.dart';
import 'jelly_palette.dart';
import 'jelly_renderer.dart';

//* --- [ Knife Trail ] ---

/// Screen-space swipe of the knife, faded out by the viewport ticker.
class KnifeTrail {
  final List<Offset> points = <Offset>[];
  double opacity = 0;
  bool active = false;

  void begin(Offset p) {
    points
      ..clear()
      ..add(p);
    opacity = 1;
    active = true;
  }

  void extend(Offset p) {
    if (!active) return;
    if (points.isNotEmpty && (points.last - p).distanceSquared < 4) return;
    points.add(p);
    if (points.length > 256) points.removeAt(1);
  }

  void release() => active = false;

  void fade(double dt) {
    if (active || opacity <= 0) return;
    opacity = (opacity - dt * 2.8).clamp(0.0, 1.0);
    if (opacity == 0) points.clear();
  }
}

//* --- [ Jelly Painter ] ---

class JellyPainter extends CustomPainter {
  JellyPainter({
    required this.engine,
    required this.camera,
    required this.renderer,
    required this.palette,
    required this.showMesh,
    required this.trail,
    required this.fill,
    required this.focusInsets,
    required super.repaint,
  });

  final JellyEngine engine;
  final JellyCamera camera;
  final JellyRenderer renderer;
  final JellyPalette palette;
  final bool showMesh;
  final KnifeTrail trail;
  final double fill;

  /// Insets (logical px) of the region the specimen is centred and fitted in.
  final EdgeInsets focusInsets;

  static final Paint _trailPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    camera.configure(
      size.width,
      size.height,
      fill: fill,
      insetLeft: focusInsets.left,
      insetTop: focusInsets.top,
      insetRight: focusInsets.right,
      insetBottom: focusInsets.bottom,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    renderer.paint(canvas, engine.body, camera, palette, showMesh: showMesh);
    _paintTrail(canvas);
    canvas.restore();
  }

  void _paintTrail(Canvas canvas) {
    if (trail.points.length < 2 || trail.opacity <= 0) return;
    final path = Path()..moveTo(trail.points.first.dx, trail.points.first.dy);
    for (var i = 1; i < trail.points.length; i++) {
      path.lineTo(trail.points[i].dx, trail.points[i].dy);
    }
    _trailPaint
      ..strokeWidth = 5
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55 * trail.opacity);
    canvas.drawPath(path, _trailPaint);
    _trailPaint
      ..strokeWidth = 1.4
      ..color = const Color(0xFF161513).withValues(alpha: 0.85 * trail.opacity);
    canvas.drawPath(path, _trailPaint);
  }

  @override
  bool shouldRepaint(covariant JellyPainter old) =>
      !identical(old.palette, palette) ||
      old.showMesh != showMesh ||
      old.fill != fill ||
      old.focusInsets != focusInsets ||
      !identical(old.engine, engine);
}
