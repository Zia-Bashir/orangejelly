import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watermelonjelly/app/app.dart';
import 'package:watermelonjelly/core/di/injection.dart';
import 'package:watermelonjelly/features/jelly/presentation/widgets/mobile_controls_sheet.dart';

import 'helpers/fonts.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MelonJellyApp());
  await tester.pump(const Duration(milliseconds: 32));
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
    expect(find.textContaining('Swipe across the jelly'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
