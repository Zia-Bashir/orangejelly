import 'dart:math' as math;
import 'dart:typed_data';

import 'soft_body.dart';

//* --- [ Solver Parameters ] ---

class XpbdParams {
  /// Edge (distance) compliance — inverse stiffness. Lower = firmer.
  double edgeCompliance = 2e-3;

  /// Tetrahedral volume compliance. Zero keeps volume (near) incompressible.
  double volumeCompliance = 0;

  /// Gravity along -Y in sim units / s². Raised so drops and bounces
  /// read lively instead of floaty (1 unit = 3.5 cm).
  double gravity = 90;

  /// Per-second rate at which non-rigid (internal) motion is damped.
  double internalDamping = 3;

  /// Per-second rate of uniform air drag.
  double airDrag = 0.15;

  /// Fraction of tangential motion removed on ground contact per substep.
  double groundFriction = 0.35;

  /// Radius of the invisible circular wall around the stage.
  double stageRadius = 3.4;

  /// Ceiling for grabbed or flung particles.
  double ceiling = 6;

  /// Minimum particle distance between different pieces.
  double pieceContactDistance = 0.07;

  double maxSpeed = 30;
}

//* --- [ XPBD Solver ] ---

/// Extended position-based dynamics (XPBD) on tetrahedra, after Macklin et
/// al. 2016 and Müller's "10 minute physics" soft-body formulation. One
/// constraint iteration per substep; stiffness comes from many small substeps.
class XpbdSolver {
  static const List<List<int>> _volIdOrder = [
    [1, 3, 2],
    [0, 2, 3],
    [0, 3, 1],
    [0, 1, 2],
  ];

  final Float64List _grads = Float64List(12);

  //* ---[ Piece scratch (damping) ]---

  Float64List _pieceAcc = Float64List(0);

  //* ---[ Spatial hash (piece contacts) ]---

  Int32List _cellStart = Int32List(0);
  Int32List _cellEntries = Int32List(0);

  //* --- [ Integration ] ---

  void integrate(SoftBody b, XpbdParams p, double h) {
    final n = b.numParticles;
    final pos = b.pos, prev = b.prev, vel = b.vel, w = b.invMass;
    final g = p.gravity * h;
    for (var i = 0; i < n; i++) {
      final o = i * 3;
      prev[o] = pos[o];
      prev[o + 1] = pos[o + 1];
      prev[o + 2] = pos[o + 2];
      if (w[i] == 0) continue;
      vel[o + 1] -= g;
      pos[o] += vel[o] * h;
      pos[o + 1] += vel[o + 1] * h;
      pos[o + 2] += vel[o + 2] * h;
    }
  }

  //* --- [ Constraints ] ---

  void solveConstraints(SoftBody b, XpbdParams p, double h) {
    _solveEdges(b, p.edgeCompliance / (h * h));
    _solveVolumes(b, p.volumeCompliance / (h * h));
    if (b.numPieces > 1) _solvePieceContacts(b, p.pieceContactDistance);
    _solveBounds(b, p);
  }

  void _solveEdges(SoftBody b, double alpha) {
    final pos = b.pos, w = b.invMass, edges = b.edges;
    final restLen = b.edgeRestLength;
    for (var e = 0; e < b.numEdges; e++) {
      final i0 = edges[e * 2], i1 = edges[e * 2 + 1];
      final w0 = w[i0], w1 = w[i1];
      final wSum = w0 + w1;
      if (wSum == 0) continue;
      final a = i0 * 3, c = i1 * 3;
      var dx = pos[a] - pos[c];
      var dy = pos[a + 1] - pos[c + 1];
      var dz = pos[a + 2] - pos[c + 2];
      final len = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (len < 1e-12) continue;
      dx /= len;
      dy /= len;
      dz /= len;
      final s = -(len - restLen[e]) / (wSum + alpha);
      pos[a] += dx * s * w0;
      pos[a + 1] += dy * s * w0;
      pos[a + 2] += dz * s * w0;
      pos[c] -= dx * s * w1;
      pos[c + 1] -= dy * s * w1;
      pos[c + 2] -= dz * s * w1;
    }
  }

  void _solveVolumes(SoftBody b, double alpha) {
    final pos = b.pos, w = b.invMass, tets = b.tets;
    final restVol = b.tetRestVolume;
    final g = _grads;
    for (var t = 0; t < b.numTets; t++) {
      var wSum = 0.0;
      for (var j = 0; j < 4; j++) {
        final order = _volIdOrder[j];
        final o0 = tets[t * 4 + order[0]] * 3;
        final o1 = tets[t * 4 + order[1]] * 3;
        final o2 = tets[t * 4 + order[2]] * 3;
        final ax = pos[o1] - pos[o0];
        final ay = pos[o1 + 1] - pos[o0 + 1];
        final az = pos[o1 + 2] - pos[o0 + 2];
        final bx = pos[o2] - pos[o0];
        final by = pos[o2 + 1] - pos[o0 + 1];
        final bz = pos[o2 + 2] - pos[o0 + 2];
        final gx = (ay * bz - az * by) / 6;
        final gy = (az * bx - ax * bz) / 6;
        final gz = (ax * by - ay * bx) / 6;
        g[j * 3] = gx;
        g[j * 3 + 1] = gy;
        g[j * 3 + 2] = gz;
        wSum += w[tets[t * 4 + j]] * (gx * gx + gy * gy + gz * gz);
      }
      if (wSum == 0) continue;
      final c = b.tetVolume(t) - restVol[t];
      final s = -c / (wSum + alpha);
      for (var j = 0; j < 4; j++) {
        final id = tets[t * 4 + j];
        final k = s * w[id];
        pos[id * 3] += g[j * 3] * k;
        pos[id * 3 + 1] += g[j * 3 + 1] * k;
        pos[id * 3 + 2] += g[j * 3 + 2] * k;
      }
    }
  }

  void _solveBounds(SoftBody b, XpbdParams p) {
    final pos = b.pos, prev = b.prev, w = b.invMass;
    final keep = 1 - p.groundFriction;
    final r2 = p.stageRadius * p.stageRadius;
    for (var i = 0; i < b.numParticles; i++) {
      if (w[i] == 0) continue;
      final o = i * 3;
      if (pos[o + 1] < 0) {
        pos[o + 1] = 0;
        pos[o] = prev[o] + (pos[o] - prev[o]) * keep;
        pos[o + 2] = prev[o + 2] + (pos[o + 2] - prev[o + 2]) * keep;
      } else if (pos[o + 1] > p.ceiling) {
        pos[o + 1] = p.ceiling;
      }
      final x = pos[o], z = pos[o + 2];
      final d2 = x * x + z * z;
      if (d2 > r2) {
        final k = p.stageRadius / math.sqrt(d2);
        pos[o] = x * k;
        pos[o + 2] = z * k;
      }
    }
  }

  //* --- [ Piece Contacts ] ---

  /// Pushes apart particles of *different* pieces closer than [minDist],
  /// using a hashed uniform grid rebuilt every call (O(n)).
  void _solvePieceContacts(SoftBody b, double minDist) {
    final n = b.numParticles;
    final tableSize = 2 * n + 1;
    if (_cellStart.length < tableSize + 1) {
      _cellStart = Int32List(tableSize * 2 + 1);
    }
    if (_cellEntries.length < n) _cellEntries = Int32List(b.capacity);
    final start = _cellStart, entries = _cellEntries, pos = b.pos;
    final inv = 1 / minDist;
    start.fillRange(0, tableSize + 1, 0);
    for (var i = 0; i < n; i++) {
      final h = _hash(
        (pos[i * 3] * inv).floor(),
        (pos[i * 3 + 1] * inv).floor(),
        (pos[i * 3 + 2] * inv).floor(),
        tableSize,
      );
      start[h]++;
    }
    var acc = 0;
    for (var c = 0; c < tableSize; c++) {
      acc += start[c];
      start[c] = acc;
    }
    start[tableSize] = acc;
    for (var i = 0; i < n; i++) {
      final h = _hash(
        (pos[i * 3] * inv).floor(),
        (pos[i * 3 + 1] * inv).floor(),
        (pos[i * 3 + 2] * inv).floor(),
        tableSize,
      );
      start[h]--;
      entries[start[h]] = i;
    }

    final w = b.invMass, piece = b.particlePiece;
    final min2 = minDist * minDist;
    for (var i = 0; i < n; i++) {
      final wi = w[i];
      final xi = (pos[i * 3] * inv).floor();
      final yi = (pos[i * 3 + 1] * inv).floor();
      final zi = (pos[i * 3 + 2] * inv).floor();
      for (var gx = xi - 1; gx <= xi + 1; gx++) {
        for (var gy = yi - 1; gy <= yi + 1; gy++) {
          for (var gz = zi - 1; gz <= zi + 1; gz++) {
            final h = _hash(gx, gy, gz, tableSize);
            for (var k = start[h]; k < start[h + 1]; k++) {
              final j = entries[k];
              if (j <= i || piece[j] == piece[i]) continue;
              final wSum = wi + w[j];
              if (wSum == 0) continue;
              final dx = pos[i * 3] - pos[j * 3];
              final dy = pos[i * 3 + 1] - pos[j * 3 + 1];
              final dz = pos[i * 3 + 2] - pos[j * 3 + 2];
              final d2 = dx * dx + dy * dy + dz * dz;
              if (d2 >= min2 || d2 < 1e-16) continue;
              final d = math.sqrt(d2);
              final corr = 0.5 * (minDist - d) / (d * wSum);
              final ci = corr * wi, cj = corr * w[j];
              pos[i * 3] += dx * ci;
              pos[i * 3 + 1] += dy * ci;
              pos[i * 3 + 2] += dz * ci;
              pos[j * 3] -= dx * cj;
              pos[j * 3 + 1] -= dy * cj;
              pos[j * 3 + 2] -= dz * cj;
            }
          }
        }
      }
    }
  }

  static int _hash(int x, int y, int z, int size) =>
      ((x * 92837111) ^ (y * 689287499) ^ (z * 283923481)).abs() % size;

  //* --- [ Velocity Update + Damping ] ---

  void updateVelocities(SoftBody b, XpbdParams p, double h) {
    final n = b.numParticles;
    final pos = b.pos, prev = b.prev, vel = b.vel;
    final inv = 1 / h;
    final maxV2 = p.maxSpeed * p.maxSpeed;
    final drag = math.exp(-p.airDrag * h);
    for (var i = 0; i < n * 3; i += 3) {
      var vx = (pos[i] - prev[i]) * inv * drag;
      var vy = (pos[i + 1] - prev[i + 1]) * inv * drag;
      var vz = (pos[i + 2] - prev[i + 2]) * inv * drag;
      final v2 = vx * vx + vy * vy + vz * vz;
      if (v2 > maxV2) {
        final k = p.maxSpeed / math.sqrt(v2);
        vx *= k;
        vy *= k;
        vz *= k;
      }
      vel[i] = vx;
      vel[i + 1] = vy;
      vel[i + 2] = vz;
    }
    final k = 1 - math.exp(-p.internalDamping * h);
    if (k > 0) _dampInternalMotion(b, k);
  }

  /// Damps velocity deviation from each piece's rigid motion (linear +
  /// angular), so wobble settles without slowing falls or spins
  /// (Müller et al. 2007, "Position Based Dynamics", §3.5).
  void _dampInternalMotion(SoftBody b, double k) {
    const stride = 16;
    final np = b.numPieces;
    if (_pieceAcc.length < np * stride) _pieceAcc = Float64List(np * stride);
    final acc = _pieceAcc..fillRange(0, np * stride, 0);
    final n = b.numParticles;
    final pos = b.pos, vel = b.vel, m = b.mass, piece = b.particlePiece;

    //* ---[ Mass, centre, momentum ]---

    for (var i = 0; i < n; i++) {
      final o = piece[i] * stride, mi = m[i];
      acc[o] += mi;
      acc[o + 1] += pos[i * 3] * mi;
      acc[o + 2] += pos[i * 3 + 1] * mi;
      acc[o + 3] += pos[i * 3 + 2] * mi;
      acc[o + 4] += vel[i * 3] * mi;
      acc[o + 5] += vel[i * 3 + 1] * mi;
      acc[o + 6] += vel[i * 3 + 2] * mi;
    }
    for (var q = 0; q < np; q++) {
      final o = q * stride, mq = acc[o];
      if (mq <= 0) continue;
      for (var c = 1; c <= 6; c++) {
        acc[o + c] /= mq;
      }
    }

    //* ---[ Angular momentum + inertia ]---

    for (var i = 0; i < n; i++) {
      final o = piece[i] * stride, mi = m[i];
      final rx = pos[i * 3] - acc[o + 1];
      final ry = pos[i * 3 + 1] - acc[o + 2];
      final rz = pos[i * 3 + 2] - acc[o + 3];
      final vx = vel[i * 3], vy = vel[i * 3 + 1], vz = vel[i * 3 + 2];
      acc[o + 7] += mi * (ry * vz - rz * vy);
      acc[o + 8] += mi * (rz * vx - rx * vz);
      acc[o + 9] += mi * (rx * vy - ry * vx);
      acc[o + 10] += mi * (ry * ry + rz * rz);
      acc[o + 11] += mi * (rx * rx + rz * rz);
      acc[o + 12] += mi * (rx * rx + ry * ry);
      acc[o + 13] -= mi * rx * ry;
      acc[o + 14] -= mi * rx * rz;
      acc[o + 15] -= mi * ry * rz;
    }

    //* ---[ ω = I⁻¹ L (stored back into slots 7..9) ]---

    for (var q = 0; q < np; q++) {
      final o = q * stride;
      final a = acc[o + 10], e = acc[o + 11], i9 = acc[o + 12];
      final bb = acc[o + 13], c = acc[o + 14], f = acc[o + 15];
      final c00 = e * i9 - f * f;
      final c01 = c * f - bb * i9;
      final c02 = bb * f - c * e;
      final det = a * c00 + bb * c01 + c * c02;
      final lx = acc[o + 7], ly = acc[o + 8], lz = acc[o + 9];
      if (det.abs() < 1e-14) {
        acc[o + 7] = 0;
        acc[o + 8] = 0;
        acc[o + 9] = 0;
        continue;
      }
      final c11 = a * i9 - c * c;
      final c12 = bb * c - a * f;
      final c22 = a * e - bb * bb;
      final invDet = 1 / det;
      acc[o + 7] = (c00 * lx + c01 * ly + c02 * lz) * invDet;
      acc[o + 8] = (c01 * lx + c11 * ly + c12 * lz) * invDet;
      acc[o + 9] = (c02 * lx + c12 * ly + c22 * lz) * invDet;
    }

    //* ---[ Blend towards rigid velocity ]---

    final w = b.invMass;
    for (var i = 0; i < n; i++) {
      if (w[i] == 0) continue;
      final o = piece[i] * stride;
      final rx = pos[i * 3] - acc[o + 1];
      final ry = pos[i * 3 + 1] - acc[o + 2];
      final rz = pos[i * 3 + 2] - acc[o + 3];
      final wx = acc[o + 7], wy = acc[o + 8], wz = acc[o + 9];
      final tx = acc[o + 4] + (wy * rz - wz * ry);
      final ty = acc[o + 5] + (wz * rx - wx * rz);
      final tz = acc[o + 6] + (wx * ry - wy * rx);
      vel[i * 3] += (tx - vel[i * 3]) * k;
      vel[i * 3 + 1] += (ty - vel[i * 3 + 1]) * k;
      vel[i * 3 + 2] += (tz - vel[i * 3 + 2]) * k;
    }
  }
}
