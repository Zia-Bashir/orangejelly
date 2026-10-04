import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orangejelly/features/jelly/physics/jelly_engine.dart';
import 'package:orangejelly/features/jelly/presentation/cubits/jelly_controls_cubit.dart';
import 'package:orangejelly/features/jelly/presentation/cubits/jelly_controls_state.dart';
import 'package:orangejelly/features/jelly/presentation/cubits/jelly_stats_cubit.dart';
import 'package:orangejelly/features/jelly/render/jelly_palette.dart';

void main() {
  late JellyEngine engine;

  setUp(() => engine = JellyEngine());

  //* --- [ Controls Cubit ] ---

  group('JellyControlsCubit', () {
    test('starts with the reference defaults', () {
      final cubit = JellyControlsCubit(engine);
      expect(cubit.state.tool, JellyTool.hand);
      expect(cubit.state.variety, JellyVariety.navel);
      expect(cubit.state.firmness, 0.40);
      expect(cubit.state.damping, 0.45);
      expect(cubit.state.paused, isFalse);
      expect(engine.firmness, 0.40);
      expect(engine.damping, 0.45);
    });

    blocTest<JellyControlsCubit, JellyControlsState>(
      'selects tool and variety',
      build: () => JellyControlsCubit(engine),
      act: (c) => c
        ..selectTool(JellyTool.knife)
        ..selectTool(JellyTool.knife)
        ..selectVariety(JellyVariety.blood),
      expect: () => [
        const JellyControlsState(tool: JellyTool.knife),
        const JellyControlsState(
          tool: JellyTool.knife,
          variety: JellyVariety.blood,
        ),
      ],
    );

    blocTest<JellyControlsCubit, JellyControlsState>(
      'sliders clamp and forward to the engine',
      build: () => JellyControlsCubit(engine),
      act: (c) => c
        ..setFirmness(1.4)
        ..setDamping(-1),
      verify: (c) {
        expect(c.state.firmness, 1.0);
        expect(c.state.damping, 0.0);
        expect(engine.firmness, 1.0);
        expect(engine.damping, 0.0);
      },
    );

    blocTest<JellyControlsCubit, JellyControlsState>(
      'toggles flags',
      build: () => JellyControlsCubit(engine),
      act: (c) => c
        ..toggleQuarterSpeed()
        ..toggleShowMesh()
        ..togglePaused()
        ..togglePanel()
        ..toggleInside(),
      verify: (c) {
        final s = c.state;
        expect(s.quarterSpeed, isTrue);
        expect(s.timeScale, JellyControlsState.playback * 0.25);
        expect(s.showMesh, isTrue);
        expect(s.paused, isTrue);
        expect(s.panelExpanded, isTrue);
        expect(s.insideExpanded, isTrue);
      },
    );

    test('reset restores a single piece after a cut', () {
      final cubit = JellyControlsCubit(engine);
      engine.cutWithPlane(1, 0, 0, 0);
      expect(engine.body.numPieces, greaterThan(1));
      cubit.reset();
      expect(engine.body.numPieces, 1);
    });
  });

  //* --- [ Stats Cubit ] ---

  group('JellyStatsCubit', () {
    test('initial readout reflects one resting piece', () {
      final cubit = JellyStatsCubit(engine);
      expect(cubit.state.pieces, 1);
      expect(cubit.state.massGrams, inInclusiveRange(74, 82));
    });

    test('refresh reports new pieces after a cut', () {
      final cubit = JellyStatsCubit(engine);
      engine.cutWithPlane(1, 0, 0, 0);
      cubit.refresh();
      expect(cubit.state.pieces, 2);
    });

    blocTest<JellyStatsCubit, JellyStats>(
      'refresh without change emits nothing',
      build: () => JellyStatsCubit(engine),
      act: (c) => c
        ..refresh()
        ..refresh(),
      expect: () => <JellyStats>[],
    );
  });
}
