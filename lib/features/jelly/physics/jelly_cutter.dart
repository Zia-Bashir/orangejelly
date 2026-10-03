import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'soft_body.dart';

/// Returns true when a world-space point lies inside the swiped knife range.
typedef CutRangeTest = bool Function(double x, double y, double z);

//* --- [ Cut Result ] ---

class CutResult {
  const CutResult({
    required this.splitParticles,
    required this.piecesBefore,
    required this.piecesAfter,
  });

  static const none = CutResult(
    splitParticles: 0,
    piecesBefore: 0,
    piecesAfter: 0,
  );

  final int splitParticles;
  final int piecesBefore;
  final int piecesAfter;

  bool get didCut => splitParticles > 0;
}

//* --- [ Jelly Cutter ] ---

/// Cuts a [SoftBody] with the plane `n · x = d`.
///
/// 1. Vertices close to the plane are snapped onto it (world + material
///    space, via the local deformation gradient) so cut faces come out flat.
/// 2. Each tet is assigned a side by its centroid.
/// 3. Faces shared by tets on opposite sides (inside the swipe range) are cut.
/// 4. Each particle's incident tets are grouped by connectivity through
///    uncut faces; every extra group gets its own duplicated particle.
/// 5. Topology is rebuilt — pieces are the resulting connected components.
abstract final class JellyCutter {
  static CutResult cut(
    SoftBody body, {
    required double nx,
    required double ny,
    required double nz,
    required double d,
    required CutRangeTest inRange,
    double snapDistance = 0.13,
    double separation = 0.035,
    double separationSpeed = 0.5,
  }) {
    final piecesBefore = body.numPieces;
    final n0 = body.numParticles;
    final numTets = body.numTets;
    final incidence = _Incidence.build(body);

    _snapToPlane(body, incidence, nx, ny, nz, d, snapDistance, inRange);

    //* ---[ Tet sides ]---

    final pos = body.pos;
    final tets = body.tets;
    final side = Uint8List(numTets);
    for (var t = 0; t < numTets; t++) {
      var s = 0.0;
      for (var k = 0; k < 4; k++) {
        final o = tets[t * 4 + k] * 3;
        s += nx * pos[o] + ny * pos[o + 1] + nz * pos[o + 2];
      }
      side[t] = s / 4 - d >= 0 ? 1 : 0;
    }

    //* ---[ Face adjacency + cut faces ]---

    final neighbour = Int32List(numTets * 4)..fillRange(0, numTets * 4, -1);
    final firstSeen = HashMap<int, int>();
    for (var t = 0; t < numTets; t++) {
      for (var f = 0; f < 4; f++) {
        final key = SoftBody.faceKeyOf(tets, t, f, n0);
        final other = firstSeen.remove(key);
        if (other == null) {
          firstSeen[key] = t * 4 + f;
        } else {
          neighbour[t * 4 + f] = other ~/ 4;
          neighbour[other] = t;
        }
      }
    }

    final cutFace = Uint8List(numTets * 4);
    var anyCut = false;
    for (var t = 0; t < numTets; t++) {
      for (var f = 0; f < 4; f++) {
        final nb = neighbour[t * 4 + f];
        if (nb < 0 || side[nb] == side[t]) continue;
        final local = SoftBody.tetFaces[f];
        var cx = 0.0, cy = 0.0, cz = 0.0;
        for (final l in local) {
          final o = tets[t * 4 + l] * 3;
          cx += pos[o];
          cy += pos[o + 1];
          cz += pos[o + 2];
        }
        if (inRange(cx / 3, cy / 3, cz / 3)) {
          cutFace[t * 4 + f] = 1;
          anyCut = true;
        }
      }
    }
    if (!anyCut) return CutResult.none;

    //* ---[ Split particles along cut faces ]---

    final original = Int32List.fromList(tets.sublist(0, numTets * 4));
    final localIndex = Int32List(numTets)..fillRange(0, numTets, -1);
    final touched = <int>[];
    var split = 0;

    for (var p = 0; p < n0; p++) {
      final s0 = incidence.offsets[p], s1 = incidence.offsets[p + 1];
      final count = s1 - s0;
      if (count < 2) continue;

      var nearCut = false;
      for (var s = s0; s < s1 && !nearCut; s++) {
        final t = incidence.tets[s];
        for (var f = 0; f < 4; f++) {
          if (cutFace[t * 4 + f] == 1 && _faceHas(original, t, f, p)) {
            nearCut = true;
            break;
          }
        }
      }
      if (!nearCut) continue;

      final parent = List<int>.generate(count, (i) => i);
      int find(int x) {
        while (parent[x] != x) {
          parent[x] = parent[parent[x]];
          x = parent[x];
        }
        return x;
      }

      for (var s = s0; s < s1; s++) {
        localIndex[incidence.tets[s]] = s - s0;
      }
      for (var s = s0; s < s1; s++) {
        final t = incidence.tets[s];
        for (var f = 0; f < 4; f++) {
          if (cutFace[t * 4 + f] == 1 || !_faceHas(original, t, f, p)) {
            continue;
          }
          final nb = neighbour[t * 4 + f];
          if (nb < 0) continue;
          final li = localIndex[nb];
          if (li < 0) continue;
          final ra = find(s - s0), rb = find(li);
          if (ra != rb) parent[rb] = ra;
        }
      }

      final groupParticle = <int, int>{};
      for (var s = s0; s < s1; s++) {
        final root = find(s - s0);
        var id = groupParticle[root];
        if (id == null) {
          id = groupParticle.isEmpty ? p : body.duplicateParticle(p);
          groupParticle[root] = id;
          if (id != p) {
            split++;
            touched.add(id);
          }
        }
        if (id == p) continue;
        final t = incidence.tets[s];
        for (var k = 0; k < 4; k++) {
          if (original[t * 4 + k] == p) body.tets[t * 4 + k] = id;
        }
      }
      if (groupParticle.length > 1) touched.add(p);
      for (var s = s0; s < s1; s++) {
        localIndex[incidence.tets[s]] = -1;
      }
    }

    if (split == 0) return CutResult.none;

    body.rebuildTopology();

    //* ---[ Separate freshly cut pieces ]---

    if (body.numPieces > piecesBefore) {
      _separate(body, touched, nx, ny, nz, d, separation, separationSpeed);
    }

    return CutResult(
      splitParticles: split,
      piecesBefore: piecesBefore,
      piecesAfter: body.numPieces,
    );
  }

  //* --- [ Helpers ] ---

  static bool _faceHas(Int32List tets, int t, int f, int p) {
    final local = SoftBody.tetFaces[f];
    return tets[t * 4 + local[0]] == p ||
        tets[t * 4 + local[1]] == p ||
        tets[t * 4 + local[2]] == p;
  }

  //* ---[ Vertex snapping ]---

  static void _snapToPlane(
    SoftBody body,
    _Incidence inc,
    double nx,
    double ny,
    double nz,
    double d,
    double maxDist,
    CutRangeTest inRange,
  ) {
    final pos = body.pos, prev = body.prev, rest = body.rest;
    final tets = body.tets;
    final f = Float64List(9);
    final fi = Float64List(9);

    for (var p = 0; p < body.numParticles; p++) {
      final o = p * 3;
      final dist = nx * pos[o] + ny * pos[o + 1] + nz * pos[o + 2] - d;
      if (dist.abs() > maxDist || dist.abs() < 1e-6) continue;
      if (!inRange(pos[o], pos[o + 1], pos[o + 2])) continue;
      final s0 = inc.offsets[p], s1 = inc.offsets[p + 1];
      if (s1 == s0) continue;

      final dwx = -dist * nx, dwy = -dist * ny, dwz = -dist * nz;
      if (!_deformationGradient(body, inc.tets[s0], f) || !_invert3(f, fi)) {
        continue;
      }
      final drx = fi[0] * dwx + fi[1] * dwy + fi[2] * dwz;
      final dry = fi[3] * dwx + fi[4] * dwy + fi[5] * dwz;
      final drz = fi[6] * dwx + fi[7] * dwy + fi[8] * dwz;

      final oldW = [pos[o], pos[o + 1], pos[o + 2]];
      final oldR = [rest[o], rest[o + 1], rest[o + 2]];
      pos[o] += dwx;
      pos[o + 1] += dwy;
      pos[o + 2] += dwz;
      rest[o] += drx;
      rest[o + 1] += dry;
      rest[o + 2] += drz;

      var ok = true;
      for (var s = s0; s < s1 && ok; s++) {
        final t = inc.tets[s];
        final i0 = tets[t * 4], i1 = tets[t * 4 + 1];
        final i2 = tets[t * 4 + 2], i3 = tets[t * 4 + 3];
        final vr = SoftBody.signedVolume(rest, i0, i1, i2, i3);
        final vw = SoftBody.signedVolume(pos, i0, i1, i2, i3);
        final v0 = body.tetRestVolume[t];
        if (vr < 0.25 * v0 || vw < 0.15 * v0) ok = false;
      }
      if (!ok) {
        pos[o] = oldW[0];
        pos[o + 1] = oldW[1];
        pos[o + 2] = oldW[2];
        rest[o] = oldR[0];
        rest[o + 1] = oldR[1];
        rest[o + 2] = oldR[2];
        continue;
      }
      prev[o] += dwx;
      prev[o + 1] += dwy;
      prev[o + 2] += dwz;
    }
  }

  /// F = Ds · Dm⁻¹ for tet [t] (row-major into [out]).
  static bool _deformationGradient(SoftBody b, int t, Float64List out) {
    final ids = [b.tets[t * 4], b.tets[t * 4 + 1], b.tets[t * 4 + 2]];
    final i3 = b.tets[t * 4 + 3];
    final dm = Float64List(9);
    final ds = Float64List(9);
    for (var c = 0; c < 3; c++) {
      for (var r = 0; r < 3; r++) {
        dm[r * 3 + c] = b.rest[ids[c] * 3 + r] - b.rest[i3 * 3 + r];
        ds[r * 3 + c] = b.pos[ids[c] * 3 + r] - b.pos[i3 * 3 + r];
      }
    }
    final dmInv = Float64List(9);
    if (!_invert3(dm, dmInv)) return false;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        var v = 0.0;
        for (var k = 0; k < 3; k++) {
          v += ds[r * 3 + k] * dmInv[k * 3 + c];
        }
        out[r * 3 + c] = v;
      }
    }
    return true;
  }

  static bool _invert3(Float64List m, Float64List out) {
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final g = m[6], h = m[7], i = m[8];
    final c00 = e * i - f * h;
    final c01 = f * g - d * i;
    final c02 = d * h - e * g;
    final det = a * c00 + b * c01 + c * c02;
    if (det.abs() < 1e-12) return false;
    final inv = 1 / det;
    out[0] = c00 * inv;
    out[1] = (c * h - b * i) * inv;
    out[2] = (b * f - c * e) * inv;
    out[3] = c01 * inv;
    out[4] = (a * i - c * g) * inv;
    out[5] = (c * d - a * f) * inv;
    out[6] = c02 * inv;
    out[7] = (b * g - a * h) * inv;
    out[8] = (a * e - b * d) * inv;
    return true;
  }

  //* ---[ Separation impulse ]---

  static void _separate(
    SoftBody body,
    List<int> touched,
    double nx,
    double ny,
    double nz,
    double d,
    double offset,
    double speed,
  ) {
    final np = body.numPieces;
    final affected = Uint8List(np);
    for (final p in touched) {
      affected[body.particlePiece[p]] = 1;
    }
    final sum = Float64List(np);
    final count = Int32List(np);
    final pos = body.pos;
    for (var i = 0; i < body.numParticles; i++) {
      final q = body.particlePiece[i];
      sum[q] += nx * pos[i * 3] + ny * pos[i * 3 + 1] + nz * pos[i * 3 + 2];
      count[q]++;
    }
    for (var i = 0; i < body.numParticles; i++) {
      final q = body.particlePiece[i];
      if (affected[q] == 0 || count[q] == 0) continue;
      final sign = (sum[q] / count[q] - d) >= 0 ? 1.0 : -1.0;
      final o = i * 3;
      final kx = nx * sign, ky = ny * sign, kz = nz * sign;
      pos[o] += kx * offset;
      pos[o + 1] += math.max(0, ky * offset);
      pos[o + 2] += kz * offset;
      body.prev[o] = pos[o];
      body.prev[o + 1] = pos[o + 1];
      body.prev[o + 2] = pos[o + 2];
      body.vel[o] += kx * speed;
      body.vel[o + 1] += 0.4 * speed;
      body.vel[o + 2] += kz * speed;
    }
  }
}

//* --- [ Particle → Tet Incidence (CSR) ] ---

class _Incidence {
  _Incidence(this.offsets, this.tets);

  final Int32List offsets;
  final Int32List tets;

  static _Incidence build(SoftBody b) {
    final n = b.numParticles;
    final offsets = Int32List(n + 1);
    for (var k = 0; k < b.numTets * 4; k++) {
      offsets[b.tets[k] + 1]++;
    }
    for (var i = 0; i < n; i++) {
      offsets[i + 1] += offsets[i];
    }
    final fill = Int32List.fromList(offsets.sublist(0, n));
    final list = Int32List(b.numTets * 4);
    for (var t = 0; t < b.numTets; t++) {
      for (var k = 0; k < 4; k++) {
        final p = b.tets[t * 4 + k];
        list[fill[p]++] = t;
      }
    }
    return _Incidence(offsets, list);
  }
}
