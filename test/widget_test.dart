import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermelonjelly/app/app.dart';
import 'package:watermelonjelly/core/di/injection.dart';
import 'package:watermelonjelly/features/jelly/physics/jelly_engine.dart';
import 'package:watermelonjelly/features/jelly/presentation/widgets/jelly_viewport.dart';
import 'package:watermelonjelly/features/jelly/presentation/widgets/mobile_controls_sheet.dart';
import 'package:watermelonjelly/features/jelly/render/jelly_painter.dart';

import 'helpers/fonts.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MelonJellyApp());
  await tester.pump(const Duration(milliseconds: 32));
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// Global screen position of the slice centre in the live viewport.
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

void main() {
  setUpAll(loadAppFonts);

  setUp(() async {
    await getIt.reset();
    configureDependencies();
  });

  testWidgets('portrait phone uses the bottom controls sheet', (tester) async {
    await _pumpAt(tester, const Size(390, 844));
    expect(find.text('Melon'), findsOneWidget);
    expect(find.byType(MobileControlsSheet), findsOneWidget);
    expect(find.text('THE SPECIMEN'), findsNothing);

    await tester.tap(find.text('SPECIMEN'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Give it a nudge'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('landscape uses the side panel like the reference', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1024, 600));
    expect(find.text('THE SPECIMEN'), findsOneWidget);
    expect(find.byType(MobileControlsSheet), findsNothing);
    expect(find.text('PIECES'), findsOneWidget);

    await tester.tap(find.text('Knife'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.textContaining(
        'Draw a line across the slice — the knife lines up over it and cuts '
        'when you let go. Cut the pieces again, as small as you like.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('knife: dragging previews only, letting go chops the slice', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1024, 600));
    await _frames(tester, 60);
    await tester.tap(find.text('Knife'));
    await _frames(tester, 10);
    final engine = getIt<JellyEngine>();
    expect(engine.body.numPieces, 1);

    final c = _sliceCentre(tester);
    final gesture = await tester.startGesture(c + const Offset(-190, -20));
    for (var i = 0; i < 24; i++) {
      await gesture.moveBy(const Offset(380 / 24, 1.5));
      await _frames(tester, 1);
    }
    await _frames(tester, 30);
    expect(engine.body.numPieces, 1, reason: 'no cut while still dragging');

    await gesture.up();
    await _frames(tester, 90);
    expect(engine.body.numPieces, 2, reason: 'release chops through');
    expect(find.text('2'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
