import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:watermelonjelly/features/jelly/physics/jelly_engine.dart';
import 'package:watermelonjelly/features/jelly/physics/slice_mesh.dart';
import 'package:watermelonjelly/features/jelly/physics/soft_body.dart';
import 'package:watermelonjelly/features/jelly/render/jelly_camera.dart';

void _settle(JellyEngine e, {double seconds = 3}) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    e.advance(1 / 60);
  }
}

/// Every boundary edge must be shared by exactly two boundary faces.
bool _surfaceIsClosed(SoftBody b) {
  final counts = <int, int>{};
  final n = b.numParticles;
  for (var f = 0; f < b.numFaces; f++) {
    for (var k = 0; k < 3; k++) {
      final a = b.faces[f * 3 + k];
      final c = b.faces[f * 3 + (k + 1) % 3];
      final key = a < c ? a * n + c : c * n + a;
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  return counts.values.every((c) => c == 2);
}

void main() {
  //* --- [ Mesh ] ---

  group('SliceMeshBuilder', () {
    test('builds a single positively oriented, closed tet mesh', () {
      final body = SoftBody.fromMesh(SliceMeshBuilder.build());
      expect(body.numParticles, greaterThan(100));
      expect(body.numTets, greaterThan(300));
      expect(body.numPieces, 1);
      for (var t = 0; t < body.numTets; t++) {
        expect(body.tetRestVolume[t], greaterThan(0));
      }
      expect(_surfaceIsClosed(body), isTrue);
    });

    test('rest mass is about 78 g at 1.3 g/cm³', () {
      final stats = JellyEngine().computeStats();
      expect(stats.massGrams, inInclusiveRange(74, 82));
    });
  });

  //* --- [ Solver ] ---

  group('XPBD solver', () {
    test('volume stays ~100% of rest once settled', () {
      final e = JellyEngine();
      _settle(e);
      final s = e.computeStats();
      expect(s.volumePercent, inInclusiveRange(98.5, 101.0));
      expect(s.kineticMicroJoules, lessThan(1));
    });

    test('nothing sinks below the ground', () {
      final e = JellyEngine()..nudge();
      _settle(e, seconds: 2);
      for (var i = 0; i < e.body.numParticles; i++) {
        expect(e.body.pos[i * 3 + 1], greaterThanOrEqualTo(-1e-9));
      }
    });

    test('nudge injects kinetic energy that damps back out', () {
      final e = JellyEngine();
      _settle(e, seconds: 1);
      e.nudge();
      e.advance(1 / 60);
      expect(e.computeStats().kineticMicroJoules, greaterThan(10));
      _settle(e, seconds: 4);
      expect(e.computeStats().kineticMicroJoules, lessThan(1));
    });

    test('stays stable at both firmness extremes', () {
      for (final f in [0.0, 1.0]) {
        final e = JellyEngine()
          ..firmness = f
          ..damping = 0;
        e.nudge();
        _settle(e, seconds: 2);
        final s = e.computeStats();
        expect(s.volumePercent.isFinite, isTrue);
        expect(s.volumePercent, inInclusiveRange(95, 105));
      }
    });
  });

  //* --- [ Cutting ] ---

  group('Knife', () {
    test('a plane through the middle makes two pieces', () {
      final e = JellyEngine();
      _settle(e, seconds: 1);
      final volumeBefore = e.body.totalRestVolume;
      final result = e.cutWithPlane(0.8, 0, 0.6, 0.0);
      expect(result.didCut, isTrue);
      expect(e.computeStats().pieces, 2);
      expect(_surfaceIsClosed(e.body), isTrue);
      expect(e.body.totalRestVolume, closeTo(volumeBefore, volumeBefore * .02));
      _settle(e, seconds: 2);
      expect(e.computeStats().volumePercent, inInclusiveRange(98, 101.5));
    });

    test('two crossing cuts increase the piece count further', () {
      final e = JellyEngine();
      e.cutWithPlane(1, 0, 0, 0.0);
      e.cutWithPlane(0, 0, 1, 0.0);
      expect(e.computeStats().pieces, greaterThanOrEqualTo(3));
    });

    test('a plane that misses the jelly does nothing', () {
      final e = JellyEngine();
      final result = e.cutWithPlane(1, 0, 0, 50);
      expect(result.didCut, isFalse);
      expect(e.computeStats().pieces, 1);
    });

    test('a screen swipe across the projected slice cuts it', () {
      final e = JellyEngine();
      final cam = JellyCamera()..configure(400, 600);
      final c = _screenCentroid(e, cam);
      final result = e.cut(cam, c.$1, c.$2 - 250, c.$1 + 20, c.$2 + 250);
      expect(result.didCut, isTrue);
      expect(e.computeStats().pieces, 2);
    });

    test('reset restores the original single piece', () {
      final e = JellyEngine();
      final particles = e.body.numParticles;
      e.cutWithPlane(1, 0, 0, 0.0);
      expect(e.computeStats().pieces, greaterThan(1));
      e.reset();
      final s = e.computeStats();
      expect(s.pieces, 1);
      expect(s.particles, particles);
    });
  });

  //* --- [ Hand ] ---

  group('Hand', () {
    test('grabbing and dragging upward lifts the slice', () {
      final e = JellyEngine();
      _settle(e, seconds: 1);
      final cam = JellyCamera()..configure(400, 600);
      final c = _screenCentroid(e, cam);
      expect(e.beginGrab(cam, c.$1, c.$2), isTrue);
      for (var i = 1; i <= 30; i++) {
        e.moveGrab(cam, c.$1, c.$2 - i * 4);
        e.advance(1 / 60);
      }
      final top = _maxY(e);
      expect(top, greaterThan(SliceGeometry.thickness + 0.3));
      e.endGrab();
      expect(e.isGrabbing, isFalse);
      for (var i = 0; i < e.body.numParticles; i++) {
        expect(e.body.invMass[i], greaterThan(0));
      }
    });

    test('tapping empty space grabs nothing', () {
      final e = JellyEngine();
      final cam = JellyCamera()..configure(400, 600);
      expect(e.beginGrab(cam, 2, 2), isFalse);
      expect(e.isGrabbing, isFalse);
    });

    test('twisting rotates the grabbed cluster', () {
      final e = JellyEngine();
      _settle(e, seconds: 1);
      final cam = JellyCamera()..configure(400, 600);
      final c = _screenCentroid(e, cam);
      expect(e.beginGrab(cam, c.$1, c.$2), isTrue);
      final before = List<double>.generate(
        e.body.numParticles * 3,
        (i) => e.body.pos[i],
      );
      e.twistGrab(math.pi / 3);
      _settle(e, seconds: 0.5);
      var moved = 0.0;
      for (var i = 0; i < before.length; i++) {
        moved = math.max(moved, (e.body.pos[i] - before[i]).abs());
      }
      expect(moved, greaterThan(0.1));
      e.endGrab();
    });
  });
}

(double, double) _screenCentroid(JellyEngine e, JellyCamera cam) {
  var x = 0.0, y = 0.0, z = 0.0;
  final n = e.body.numParticles;
  for (var i = 0; i < n; i++) {
    x += e.body.pos[i * 3];
    y += e.body.pos[i * 3 + 1];
    z += e.body.pos[i * 3 + 2];
  }
  final buf = Float64List(3);
  cam.project(x / n, y / n + 0.25, z / n, buf, 0);
  return (buf[0], buf[1]);
}

double _maxY(JellyEngine e) {
  var m = 0.0;
  for (var i = 0; i < e.body.numParticles; i++) {
    m = math.max(m, e.body.pos[i * 3 + 1]);
  }
  return m;
}
