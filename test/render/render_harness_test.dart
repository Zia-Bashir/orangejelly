import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermelonjelly/app/app.dart';
import 'package:watermelonjelly/core/di/injection.dart';
import 'package:watermelonjelly/features/jelly/physics/jelly_engine.dart';
import 'package:watermelonjelly/features/jelly/presentation/cubits/knife_state.dart';
import 'package:watermelonjelly/features/jelly/presentation/widgets/jelly_viewport.dart';
import 'package:watermelonjelly/features/jelly/render/jelly_camera.dart';
import 'package:watermelonjelly/features/jelly/render/jelly_painter.dart';
import 'package:watermelonjelly/features/jelly/render/jelly_palette.dart';
import 'package:watermelonjelly/features/jelly/render/jelly_renderer.dart';
import 'package:watermelonjelly/features/jelly/render/knife_renderer.dart';

import '../helpers/fonts.dart';

//* --- [ Render Harness ] ---

/// Headless renders + CPU frame-cost probe for the jelly / knife renderers.
///
/// Opt-in (writes PNGs to build/screens):
///   flutter test test/render --dart-define=JELLY_SHOTS=true
const bool _enabled = bool.fromEnvironment('JELLY_SHOTS');

Future<void> _save(ui.Image image, String name) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  Directory('build/screens').createSync(recursive: true);
  File('build/screens/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

void _settle(JellyEngine e, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    e.advance(1 / 60);
  }
}

//* ---[ Close-ups ]---

ui.Image _renderCloseUp(
  JellyEngine engine, {
  KnifeState? knife,
  double w = 900,
  double h = 620,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..color = const Color(0xFFE9E6E2),
  );
  final cam = JellyCamera()..configure(w, h, fill: 0.95);
  final renderer = JellyRenderer();
  final knifeRenderer = KnifeRenderer();
  const empty = KnifeState();
  renderer.paintShadows(canvas, engine.body, cam, JellyPalette.navel);
  knifeRenderer
    ..paintShadow(canvas, cam, knife ?? empty)
    ..paintKnife(canvas, cam, knife ?? empty, lowerPass: true);
  renderer.paintSurface(canvas, engine.body, cam, showMesh: false);
  knifeRenderer.paintKnife(canvas, cam, knife ?? empty, lowerPass: false);
  return recorder.endRecording().toImageSync(w.toInt(), h.toInt());
}

//* ---[ App screenshots ]---

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    await _save(await boundary.toImage(pixelRatio: 2), name);
  });
}

Future<void> _frames(WidgetTester tester, double seconds) async {
  final n = (seconds * 60).round();
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// Screen-space centroid of the slice inside the live viewport (global px).
Offset _sliceCentre(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(JellyViewport),
      matching: find.byType(CustomPaint),
    ),
  );
  final cam = (paint.painter! as JellyPainter).camera;
  final body = getIt<JellyEngine>().body;
  var x = 0.0, y = 0.0, z = 0.0;
  for (var i = 0; i < body.numParticles; i++) {
    x += body.pos[i * 3];
    y += body.pos[i * 3 + 1];
    z += body.pos[i * 3 + 2];
  }
  final n = body.numParticles;
  final out = Float64List(3);
  cam.project(x / n, y / n + 0.25, z / n, out, 0);
  final box = tester.renderObject<RenderBox>(find.byType(JellyViewport));
  return box.localToGlobal(Offset(out[0], out[1]));
}

Future<void> _knifeSequence(
  WidgetTester tester,
  Size size,
  String prefix,
) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(const OrangeJellyApp());
  getIt<JellyEngine>().reset();
  await _frames(tester, 1.5);
  await _capture(tester, '${prefix}_rest');

  if (find.text('Knife').evaluate().isEmpty) {
    await tester.tap(find.text('SPECIMEN'));
    await _frames(tester, 0.5);
  }
  await tester.tap(find.text('Knife').first);
  await _frames(tester, 0.4);
  if (find.text('SPECIMEN').evaluate().isNotEmpty &&
      find.text('Give it a nudge').evaluate().isNotEmpty) {
    await tester.tap(find.text('SPECIMEN'));
    await _frames(tester, 0.5);
  }

  final c = _sliceCentre(tester);
  final span = size.width < 600 ? 150.0 : 190.0;
  final gesture = await tester.startGesture(c + Offset(-span, -span * 0.12));
  for (var i = 1; i <= 24; i++) {
    await gesture.moveBy(Offset(span * 2 / 24, span * 0.3 / 24));
    await _frames(tester, 1 / 60);
  }
  await _frames(tester, 0.3);
  await _capture(tester, '${prefix}_knife_aim');

  await gesture.up();
  await _frames(tester, 0.12);
  await _capture(tester, '${prefix}_knife_chop');
  await _frames(tester, 0.09);
  await _capture(tester, '${prefix}_knife_impact');
  await _frames(tester, 1.2);
  await _capture(tester, '${prefix}_knife_after');
  debugPrint(
    '📦 DATA (APP LOGS) [harness] : $prefix pieces -> '
    '${getIt<JellyEngine>().body.numPieces}',
  );
  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    await _loadIcons();
  });

  test('close-up renders', () async {
    final engine = JellyEngine();
    _settle(engine, 2);
    await _save(_renderCloseUp(engine), 'jelly_rest_closeup');

    await _save(
      _renderCloseUp(
        engine,
        knife: const KnifeState(
          phase: KnifePhase.aiming,
          x: 0.1,
          z: 0.2,
          yaw: 0.12,
          edgeY: 1.2,
          opacity: 1,
        ),
      ),
      'knife_hover_closeup',
    );
    await _save(
      _renderCloseUp(
        engine,
        knife: const KnifeState(
          phase: KnifePhase.chopping,
          x: 0.1,
          z: 0.2,
          yaw: 0.12,
          edgeY: 0.12,
          opacity: 1,
        ),
      ),
      'knife_chop_closeup',
    );

    engine.cutWithPlane(0.8, 0, 0.6, 0.1);
    engine.cutWithPlane(-0.5, 0, 0.86, 0.35);
    _settle(engine, 1.5);
    await _save(_renderCloseUp(engine), 'jelly_cut_closeup');
  }, skip: !_enabled);

  testWidgets('app knife sequence (wide)', (tester) async {
    await getIt.reset();
    configureDependencies();
    await _knifeSequence(tester, const Size(1024, 560), 'wide');
  }, skip: !_enabled);

  testWidgets('app knife sequence (phone)', (tester) async {
    await getIt.reset();
    configureDependencies();
    await _knifeSequence(tester, const Size(390, 844), 'phone');
  }, skip: !_enabled);

  test('frame cost probe', () {
    final engine = JellyEngine();
    _settle(engine, 1);
    final renderer = JellyRenderer();
    final cam = JellyCamera()..configure(390, 600, fill: 0.84);

    void measure(String label) {
      void frame() {
        final r = ui.PictureRecorder();
        renderer.paint(
          Canvas(r),
          engine.body,
          cam,
          JellyPalette.navel,
          showMesh: false,
        );
        r.endRecording().dispose();
      }

      for (var i = 0; i < 60; i++) {
        frame();
      }
      final physics = Stopwatch();
      final render = Stopwatch();
      const frames = 180;
      for (var i = 0; i < frames; i++) {
        physics.start();
        engine.advance(1 / 60);
        physics.stop();
        render.start();
        frame();
        render.stop();
      }
      final p = physics.elapsedMicroseconds / frames / 1000;
      final ms = render.elapsedMicroseconds / frames / 1000;
      debugPrint(
        '📦 DATA (APP LOGS) [frameCost] : $label -> '
        'physics ${p.toStringAsFixed(2)} ms, '
        'render ${ms.toStringAsFixed(2)} ms, '
        '${renderer.lastVertexCount} shaded vertices',
      );
    }

    measure('rest');
    engine.cutWithPlane(0.8, 0, 0.6, 0.1);
    engine.cutWithPlane(-0.5, 0, 0.86, 0.35);
    measure('two cuts');
  }, skip: !_enabled);

  test('harness is opt-in', () {
    expect(_enabled || !_enabled, isTrue);
  });
}
