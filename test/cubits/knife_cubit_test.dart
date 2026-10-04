import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orangejelly/features/jelly/physics/jelly_engine.dart';
import 'package:orangejelly/features/jelly/presentation/cubits/knife_cubit.dart';
import 'package:orangejelly/features/jelly/presentation/cubits/knife_state.dart';
import 'package:orangejelly/features/jelly/render/jelly_camera.dart';

Offset _sliceCentre(JellyEngine e, JellyCamera cam) {
  var x = 0.0, y = 0.0, z = 0.0;
  final n = e.body.numParticles;
  for (var i = 0; i < n; i++) {
    x += e.body.pos[i * 3];
    y += e.body.pos[i * 3 + 1];
    z += e.body.pos[i * 3 + 2];
  }
  final out = Float64List(3);
  cam.project(x / n, y / n + 0.25, z / n, out, 0);
  return Offset(out[0], out[1]);
}

/// Advances engine + knife together like the viewport frame loop.
int _run(JellyEngine e, KnifeCubit k, double seconds) {
  var cuts = 0;
  for (var i = 0; i < (seconds * 60).round(); i++) {
    e.advance(1 / 60);
    if (k.tick(1 / 60)?.didCut ?? false) cuts++;
  }
  return cuts;
}

void main() {
  late JellyEngine engine;
  late JellyCamera cam;
  late KnifeCubit knife;
  late Offset centre;

  setUp(() {
    engine = JellyEngine();
    for (var i = 0; i < 60; i++) {
      engine.advance(1 / 60);
    }
    cam = JellyCamera()..configure(400, 600);
    centre = _sliceCentre(engine, cam);
    knife = KnifeCubit(engine);
  });

  tearDown(() => knife.close());

  /// Drags from left of the slice to right of it, ticking frames as it goes.
  int dragAcross() {
    var cuts = 0;
    expect(knife.beginAim(cam, centre + const Offset(-170, -12)), isTrue);
    for (var i = 1; i <= 30; i++) {
      knife.updateAim(cam, centre + Offset(-170 + i * 340 / 30, -12 + i * 0.8));
      cuts += _run(engine, knife, 1 / 60);
    }
    cuts += _run(engine, knife, 0.5);
    return cuts;
  }

  //* --- [ Aiming ] ---

  test('dragging only previews: the knife hovers, nothing is cut', () {
    final cuts = dragAcross();
    expect(cuts, 0);
    expect(engine.body.numPieces, 1);
    final s = knife.state;
    expect(s.phase, KnifePhase.aiming);
    expect(s.knifeVisible, isTrue);
    expect(s.guideVisible, isTrue);
    expect(s.edgeY, greaterThan(KnifeCubit.impactY + 0.5));
    expect((s.guideEnd! - s.guideStart!).distance, greaterThan(300));
  });

  //* --- [ Chop ] ---

  test('releasing chops down, cuts once on impact, then lifts away', () {
    dragAcross();
    expect(knife.release(cam), isTrue);
    expect(knife.state.phase, KnifePhase.chopping);
    expect(engine.body.numPieces, 1);

    var cuts = 0;
    var minEdge = double.infinity;
    var sawLift = false;
    for (var i = 0; i < 120 && knife.state.phase != KnifePhase.idle; i++) {
      engine.advance(1 / 60);
      if (knife.tick(1 / 60)?.didCut ?? false) cuts++;
      minEdge = knife.state.edgeY < minEdge ? knife.state.edgeY : minEdge;
      if (knife.state.phase == KnifePhase.lifting) sawLift = true;
    }
    expect(cuts, 1);
    expect(engine.body.numPieces, 2);
    expect(minEdge, lessThanOrEqualTo(KnifeCubit.impactY));
    expect(sawLift, isTrue);
    expect(knife.state, const KnifeState());
  });

  test('pieces can be cut again with a second chop', () {
    dragAcross();
    knife.release(cam);
    _run(engine, knife, 1.5);
    expect(engine.body.numPieces, 2);

    expect(knife.beginAim(cam, centre + const Offset(10, -200)), isTrue);
    for (var i = 1; i <= 20; i++) {
      knife.updateAim(cam, centre + Offset(10 + i * 0.5, -200 + i * 20));
      _run(engine, knife, 1 / 60);
    }
    knife.release(cam);
    _run(engine, knife, 1.5);
    expect(engine.body.numPieces, greaterThanOrEqualTo(3));
  });

  //* --- [ Edge cases ] ---

  test('a tap or tiny drag puts the knife away without cutting', () {
    knife.beginAim(cam, centre);
    knife.updateAim(cam, centre + const Offset(6, 3));
    _run(engine, knife, 0.1);
    expect(knife.release(cam), isFalse);
    expect(knife.state.phase, KnifePhase.lifting);
    expect(_run(engine, knife, 1), 0);
    expect(engine.body.numPieces, 1);
    expect(knife.state.phase, KnifePhase.idle);
  });

  test('a new aim is ignored mid-chop', () {
    dragAcross();
    knife.release(cam);
    _run(engine, knife, 0.05);
    expect(knife.state.phase, KnifePhase.chopping);
    expect(knife.beginAim(cam, centre), isFalse);
  });

  test('cancel removes the knife and line immediately', () {
    knife.beginAim(cam, centre);
    knife.updateAim(cam, centre + const Offset(100, 0));
    knife.cancel();
    expect(knife.state, const KnifeState());
    expect(knife.release(cam), isFalse);
    expect(engine.body.numPieces, 1);
  });

  test('a line that misses the slice chops but cuts nothing', () {
    knife.beginAim(cam, const Offset(10, 20));
    for (var i = 1; i <= 10; i++) {
      knife.updateAim(cam, Offset(10 + i * 15.0, 20));
    }
    expect(knife.release(cam), isTrue);
    expect(_run(engine, knife, 1.5), 0);
    expect(engine.body.numPieces, 1);
    expect(knife.state.phase, KnifePhase.idle);
  });
}
