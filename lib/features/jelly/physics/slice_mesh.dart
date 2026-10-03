import 'dart:math' as math;
import 'dart:typed_data';

//* --- [ Slice Geometry ] ---

/// Dimensions of the watermelon wedge in simulation units (1 unit = 3.5 cm).
///
/// Material (rest) coordinates use a slice-local frame: the apex sits at the
/// origin, the wedge bisector points along +X, Y is up and the arc (rind) lies
/// at distance [radius] from the apex.
abstract final class SliceGeometry {
  static const double radius = 2.38;
  static const double angle = 60 * math.pi / 180;
  static const double thickness = 0.5;
  static const double bevel = 0.07;
  static const int rows = 10;
  static const int layers = 3;

  /// Fraction of [radius] where the red flesh gives way to the cream rind.
  static const double fleshEnd = 0.885;

  /// Fraction of [radius] where the cream rind gives way to the green skin.
  static const double creamEnd = 0.95;

  /// World yaw of the wedge bisector (rind faces the viewer, tip points back
  /// and to the right like the reference specimen).
  static const double worldYaw = 2.2;

  /// Height the slice is spawned above the ground so it settles with a wobble.
  static const double dropHeight = 0.18;
}

//* --- [ Tet Mesh ] ---

/// Immutable tetrahedral mesh: rest (material) positions, initial world
/// positions and 4 particle indices per tetrahedron.
class TetMesh {
  const TetMesh({
    required this.restPositions,
    required this.worldPositions,
    required this.tets,
  });

  final Float64List restPositions;
  final Float64List worldPositions;
  final Int32List tets;

  int get numParticles => restPositions.length ~/ 3;
  int get numTets => tets.length ~/ 4;
}

//* --- [ Slice Mesh Builder ] ---

/// Builds the wedge as a triangulated circular sector extruded into prisms,
/// each prism split into 3 tetrahedra with a globally consistent diagonal rule
/// (so neighbouring prisms share conforming faces).
abstract final class SliceMeshBuilder {
  static TetMesh build() {
    const nr = SliceGeometry.rows;
    const ny = SliceGeometry.layers;
    const perLayer = (nr + 1) * (nr + 2) ~/ 2;
    const numParticles = perLayer * (ny + 1);
    const halfAngle = SliceGeometry.angle / 2;

    final rest = Float64List(numParticles * 3);

    //* ---[ Particles ]---

    for (var k = 0; k <= ny; k++) {
      final y = SliceGeometry.thickness * k / ny;
      final isCapLayer = k == 0 || k == ny;
      for (var i = 0; i <= nr; i++) {
        final r = _rowRadius(i);
        for (var j = 0; j <= i; j++) {
          final phi = i == 0 ? 0.0 : -halfAngle + SliceGeometry.angle * j / i;
          var x = r * math.cos(phi);
          var z = r * math.sin(phi);
          if (isCapLayer) {
            var ix = 0.0;
            var iz = 0.0;
            if (i == 0) {
              ix += 2;
            } else {
              if (i == nr) {
                ix -= math.cos(phi);
                iz -= math.sin(phi);
              }
              if (j == 0) {
                ix += math.sin(halfAngle);
                iz += math.cos(halfAngle);
              }
              if (j == i) {
                ix += math.sin(halfAngle);
                iz -= math.cos(halfAngle);
              }
            }
            x += ix * SliceGeometry.bevel;
            z += iz * SliceGeometry.bevel;
          }
          final id = k * perLayer + _index2d(i, j);
          rest[id * 3] = x;
          rest[id * 3 + 1] = y;
          rest[id * 3 + 2] = z;
        }
      }
    }

    //* ---[ Tetrahedra ]---

    final tris = <int>[];
    for (var i = 0; i < nr; i++) {
      for (var j = 0; j <= i; j++) {
        tris
          ..add(_index2d(i, j))
          ..add(_index2d(i + 1, j))
          ..add(_index2d(i + 1, j + 1));
      }
      for (var j = 0; j < i; j++) {
        tris
          ..add(_index2d(i, j))
          ..add(_index2d(i + 1, j + 1))
          ..add(_index2d(i, j + 1));
      }
    }

    final numTris = tris.length ~/ 3;
    final tets = Int32List(numTris * ny * 3 * 4);
    var t = 0;
    for (var k = 0; k < ny; k++) {
      final lo = k * perLayer;
      final hi = (k + 1) * perLayer;
      for (var f = 0; f < numTris; f++) {
        final sorted = [tris[f * 3], tris[f * 3 + 1], tris[f * 3 + 2]]..sort();
        final a = sorted[0];
        final b = sorted[1];
        final c = sorted[2];
        final split = [
          [a + lo, b + lo, c + lo, a + hi],
          [b + lo, c + lo, a + hi, b + hi],
          [c + lo, a + hi, b + hi, c + hi],
        ];
        for (final tet in split) {
          tets[t * 4] = tet[0];
          tets[t * 4 + 1] = tet[1];
          tets[t * 4 + 2] = tet[2];
          tets[t * 4 + 3] = tet[3];
          if (_signedVolume(rest, tets, t) < 0) {
            tets[t * 4 + 2] = tet[3];
            tets[t * 4 + 3] = tet[2];
          }
          t++;
        }
      }
    }

    return TetMesh(
      restPositions: rest,
      worldPositions: _toWorld(rest),
      tets: tets,
    );
  }

  //* ---[ Helpers ]---

  static int _index2d(int i, int j) => i * (i + 1) ~/ 2 + j;

  static double _rowRadius(int i) {
    const nr = SliceGeometry.rows;
    const fleshRadius = 0.84 * SliceGeometry.radius;
    if (i <= nr - 2) return fleshRadius * i / (nr - 2);
    if (i == nr - 1) return 0.92 * SliceGeometry.radius;
    return SliceGeometry.radius;
  }

  static double _signedVolume(Float64List p, Int32List tets, int t) {
    final i0 = tets[t * 4] * 3;
    final i1 = tets[t * 4 + 1] * 3;
    final i2 = tets[t * 4 + 2] * 3;
    final i3 = tets[t * 4 + 3] * 3;
    final ax = p[i1] - p[i0], ay = p[i1 + 1] - p[i0 + 1];
    final az = p[i1 + 2] - p[i0 + 2];
    final bx = p[i2] - p[i0], by = p[i2 + 1] - p[i0 + 1];
    final bz = p[i2 + 2] - p[i0 + 2];
    final cx = p[i3] - p[i0], cy = p[i3 + 1] - p[i0 + 1];
    final cz = p[i3 + 2] - p[i0 + 2];
    return ((ay * bz - az * by) * cx +
            (az * bx - ax * bz) * cy +
            (ax * by - ay * bx) * cz) /
        6;
  }

  /// Rotates the slice-local mesh by [SliceGeometry.worldYaw] and centres its
  /// footprint on the world origin, slightly above the ground.
  static Float64List _toWorld(Float64List rest) {
    final n = rest.length ~/ 3;
    final out = Float64List(rest.length);
    final c = math.cos(SliceGeometry.worldYaw);
    final s = math.sin(SliceGeometry.worldYaw);
    var cx = 0.0;
    var cz = 0.0;
    for (var i = 0; i < n; i++) {
      final x = rest[i * 3];
      final z = rest[i * 3 + 2];
      out[i * 3] = c * x - s * z;
      out[i * 3 + 1] = rest[i * 3 + 1] + SliceGeometry.dropHeight;
      out[i * 3 + 2] = s * x + c * z;
      cx += out[i * 3];
      cz += out[i * 3 + 2];
    }
    cx /= n;
    cz /= n;
    for (var i = 0; i < n; i++) {
      out[i * 3] -= cx;
      out[i * 3 + 2] -= cz;
    }
    return out;
  }
}
