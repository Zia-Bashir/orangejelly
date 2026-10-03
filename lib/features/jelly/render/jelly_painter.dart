import 'package:flutter/rendering.dart';

import '../physics/jelly_engine.dart';
import '../presentation/cubits/knife_cubit.dart';
import 'jelly_camera.dart';
import 'jelly_palette.dart';
import 'jelly_renderer.dart';
import 'knife_renderer.dart';

//* --- [ Jelly Painter ] ---

/// Paints one frame: ground shadows (jelly + knife), the part of the blade
/// below the jelly top, the jelly surface, the rest of the knife, and the
/// drawn guide line. Knife pose is read from [knife]'s current state.
class JellyPainter extends CustomPainter {
  JellyPainter({
    required this.engine,
    required this.camera,
    required this.renderer,
    required this.knifeRenderer,
    required this.knife,
    required this.palette,
    required this.showMesh,
    required this.fill,
    required this.focusInsets,
    required super.repaint,
  });

  final JellyEngine engine;
  final JellyCamera camera;
  final JellyRenderer renderer;
  final KnifeRenderer knifeRenderer;
  final KnifeCubit knife;
  final JellyPalette palette;
  final bool showMesh;
  final double fill;

  /// Insets (logical px) of the region the specimen is centred and fitted in.
  final EdgeInsets focusInsets;

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
    final k = knife.state;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    renderer.paintShadows(canvas, engine.body, camera, palette);
    knifeRenderer
      ..paintShadow(canvas, camera, k)
      ..paintKnife(canvas, camera, k, lowerPass: true);
    renderer.paintSurface(canvas, engine.body, camera, showMesh: showMesh);
    knifeRenderer
      ..paintKnife(canvas, camera, k, lowerPass: false)
      ..paintGuide(canvas, k);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant JellyPainter old) =>
      !identical(old.palette, palette) ||
      old.showMesh != showMesh ||
      old.fill != fill ||
      old.focusInsets != focusInsets ||
      !identical(old.knife, knife) ||
      !identical(old.engine, engine);
}
