import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../render/jelly_camera.dart';
import 'jelly_cutter.dart';
import 'slice_mesh.dart';
import 'soft_body.dart';
import 'xpbd_solver.dart';

//* --- [ Jelly Stats ] ---

class JellyStats extends Equatable {
  const JellyStats({
    required this.massGrams,
    required this.volumePercent,
    required this.kineticMicroJoules,
    required this.pieces,
    required this.particles,
    required this.tetrahedra,
  });

  final double massGrams;
  final double volumePercent;
  final double kineticMicroJoules;
  final int pieces;
  final int particles;
  final int tetrahedra;

  @override
  List<Object?> get props => [
    massGrams,
    volumePercent,
    kineticMicroJoules,
    pieces,
    particles,
    tetrahedra,
  ];
}

//* --- [ Jelly Engine ] ---

/// Owns the soft body and drives the XPBD solver. Plain Dart service (no UI
/// state): Cubits forward settings here and the viewport ticker calls
/// [advance] every frame.
@lazySingleton
class JellyEngine {
  JellyEngine() {
    _buildFreshBody();
    firmness = 0.40;
    damping = 0.45;
    debugPrint(
      '✅ (APP LOGS) [JellyEngine] : created -> '
      '${body.numParticles} particles, ${body.numTets} tets',
    );
  }

  /// 1 simulation unit = 3.5 cm.
  static const double unitCm = 3.5;

  /// Gummy density in g/cm³.
  static const double gummyDensity = 1.3;

  /// Target substep length (seconds of sim time).
  static const double maxSubstep = 1 / 600;

  static final TetMesh _mesh = SliceMeshBuilder.build();

  final XpbdSolver _solver = XpbdSolver();
  final XpbdParams params = XpbdParams();
  final math.Random _random = math.Random(9);

  late SoftBody body;

  //* --- [ Settings ] ---

  double _firmness = 0.40;
  double _damping = 0.45;

  double get firmness => _firmness;

  /// 0 = trembling … 1 = set. Maps log-linearly onto edge compliance.
  set firmness(double value) {
    _firmness = value.clamp(0.0, 1.0);
    params.edgeCompliance = math.pow(10, -0.8 - 1.6 * _firmness).toDouble();
  }

  double get damping => _damping;

  /// 0 = lively … 1 = syrupy. Maps exponentially onto internal damping rate.
  set damping(double value) {
    _damping = value.clamp(0.0, 1.0);
    params.internalDamping = 0.4 * math.pow(40, _damping).toDouble();
  }

  //* --- [ Lifecycle ] ---

  void _buildFreshBody() {
    body = SoftBody.fromMesh(_mesh);
  }

  /// Restores the single, uncut specimen.
  void reset() {
    endGrab();
    _buildFreshBody();
    debugPrint('✅ (APP LOGS) [JellyEngine] : reset -> pieces 1');
  }

  //* --- [ Stepping ] ---

  /// Advances the simulation by [dt] seconds of sim time.
  void advance(double dt) {
    if (dt <= 0) return;
    final clamped = math.min(dt, 1 / 30);
    final n = (clamped / maxSubstep).ceil().clamp(2, 24);
    final h = clamped / n;
    for (var s = 0; s < n; s++) {
      _solver.integrate(body, params, h);
      if (_grabCount > 0) _applyGrab((s + 1) / n);
      _solver.solveConstraints(body, params, h);
      _solver.updateVelocities(body, params, h);
    }
    if (_grabCount > 0) {
      _fromX = _toX;
      _fromY = _toY;
      _fromZ = _toZ;
      _fromAngle = _toAngle;
    }
  }

  //* --- [ Hand Tool: Grab + Twist ] ---

  Int32List _grabIds = Int32List(0);
  Float64List _grabOffsets = Float64List(0);
  int _grabCount = 0;
  double _fromX = 0, _fromY = 0, _fromZ = 0;
  double _toX = 0, _toY = 0, _toZ = 0;
  double _fromAngle = 0, _toAngle = 0;
  double _axisX = 0, _axisY = 0, _axisZ = 1;
  double _planeX = 0, _planeY = 0, _planeZ = 0;
  final Float64List _ray = Float64List(3);
  final Float64List _proj = Float64List(3);

  bool get isGrabbing => _grabCount > 0;

  /// Radius (sim units) of the particle cluster pinned under a finger.
  static const double grabRadius = 0.34;

  /// Starts a grab under screen point (sx, sy). Returns false on a miss.
  bool beginGrab(JellyCamera cam, double sx, double sy) {
    endGrab();
    final hit = _pick(cam, sx, sy);
    if (hit == null) return false;
    final (hx, hy, hz, piece) = hit;

    final ids = <int>[];
    final r2 = grabRadius * grabRadius;
    var nearest = -1;
    var nearestD2 = double.infinity;
    for (var i = 0; i < body.numParticles; i++) {
      if (body.particlePiece[i] != piece) continue;
      final dx = body.pos[i * 3] - hx;
      final dy = body.pos[i * 3 + 1] - hy;
      final dz = body.pos[i * 3 + 2] - hz;
      final d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < r2) ids.add(i);
      if (d2 < nearestD2) {
        nearestD2 = d2;
        nearest = i;
      }
    }
    if (ids.isEmpty && nearest >= 0) ids.add(nearest);
    if (ids.isEmpty) return false;

    _grabCount = ids.length;
    _grabIds = Int32List.fromList(ids);
    _grabOffsets = Float64List(_grabCount * 3);
    for (var k = 0; k < _grabCount; k++) {
      final i = _grabIds[k];
      _grabOffsets[k * 3] = body.pos[i * 3] - hx;
      _grabOffsets[k * 3 + 1] = body.pos[i * 3 + 1] - hy;
      _grabOffsets[k * 3 + 2] = body.pos[i * 3 + 2] - hz;
      body.invMass[i] = 0;
    }
    _fromX = _toX = _planeX = hx;
    _fromY = _toY = _planeY = hy;
    _fromZ = _toZ = _planeZ = hz;
    _fromAngle = _toAngle = 0;
    _axisX = cam.fx;
    _axisY = cam.fy;
    _axisZ = cam.fz;
    debugPrint(
      '✅ (APP LOGS) [grab] : begin -> piece $piece, $_grabCount particles',
    );
    return true;
  }

  /// Drags the grabbed cluster to follow the finger on a camera-facing plane.
  void moveGrab(JellyCamera cam, double sx, double sy) {
    if (_grabCount == 0) return;
    cam.rayDirection(sx, sy, _ray);
    final denom = _ray[0] * _axisX + _ray[1] * _axisY + _ray[2] * _axisZ;
    if (denom.abs() < 1e-6) return;
    final t =
        ((_planeX - cam.eyeX) * _axisX +
            (_planeY - cam.eyeY) * _axisY +
            (_planeZ - cam.eyeZ) * _axisZ) /
        denom;
    if (t <= 0) return;
    _toX = cam.eyeX + _ray[0] * t;
    _toY = (cam.eyeY + _ray[1] * t).clamp(0.0, params.ceiling);
    _toZ = cam.eyeZ + _ray[2] * t;
  }

  /// Twists the grabbed cluster around the view axis through the grab point.
  void twistGrab(double radians) {
    if (_grabCount == 0) return;
    _toAngle += radians;
  }

  void endGrab() {
    if (_grabCount == 0) return;
    for (var k = 0; k < _grabCount; k++) {
      final i = _grabIds[k];
      if (i < body.numParticles && body.mass[i] > 0) {
        body.invMass[i] = 1 / body.mass[i];
      }
    }
    _grabCount = 0;
    debugPrint('✅ (APP LOGS) [grab] : end');
  }

  void _applyGrab(double alpha) {
    final cx = _fromX + (_toX - _fromX) * alpha;
    final cy = _fromY + (_toY - _fromY) * alpha;
    final cz = _fromZ + (_toZ - _fromZ) * alpha;
    final angle = _fromAngle + (_toAngle - _fromAngle) * alpha;
    final c = math.cos(angle), s = math.sin(angle);
    final kx = _axisX, ky = _axisY, kz = _axisZ;
    final pos = body.pos;
    for (var g = 0; g < _grabCount; g++) {
      final ox = _grabOffsets[g * 3];
      final oy = _grabOffsets[g * 3 + 1];
      final oz = _grabOffsets[g * 3 + 2];
      final dot = kx * ox + ky * oy + kz * oz;
      final rx = ox * c + (ky * oz - kz * oy) * s + kx * dot * (1 - c);
      final ry = oy * c + (kz * ox - kx * oz) * s + ky * dot * (1 - c);
      final rz = oz * c + (kx * oy - ky * ox) * s + kz * dot * (1 - c);
      final i = _grabIds[g] * 3;
      pos[i] = cx + rx;
      pos[i + 1] = math.max(0, cy + ry);
      pos[i + 2] = cz + rz;
    }
  }

  //* ---[ Picking ]---

  /// Ray-casts the surface triangles; falls back to the nearest surface
  /// particle within a finger-sized radius. Returns hit point + piece.
  (double, double, double, int)? _pick(JellyCamera cam, double sx, double sy) {
    cam.rayDirection(sx, sy, _ray);
    final ox = cam.eyeX, oy = cam.eyeY, oz = cam.eyeZ;
    final dx = _ray[0], dy = _ray[1], dz = _ray[2];
    final pos = body.pos, faces = body.faces;
    var bestT = double.infinity;
    var bestFace = -1;
    for (var f = 0; f < body.numFaces; f++) {
      final a = faces[f * 3] * 3;
      final b = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      final e1x = pos[b] - pos[a], e1y = pos[b + 1] - pos[a + 1];
      final e1z = pos[b + 2] - pos[a + 2];
      final e2x = pos[c] - pos[a], e2y = pos[c + 1] - pos[a + 1];
      final e2z = pos[c + 2] - pos[a + 2];
      final px = dy * e2z - dz * e2y;
      final py = dz * e2x - dx * e2z;
      final pz = dx * e2y - dy * e2x;
      final det = e1x * px + e1y * py + e1z * pz;
      if (det.abs() < 1e-12) continue;
      final inv = 1 / det;
      final tx = ox - pos[a], ty = oy - pos[a + 1], tz = oz - pos[a + 2];
      final u = (tx * px + ty * py + tz * pz) * inv;
      if (u < 0 || u > 1) continue;
      final qx = ty * e1z - tz * e1y;
      final qy = tz * e1x - tx * e1z;
      final qz = tx * e1y - ty * e1x;
      final v = (dx * qx + dy * qy + dz * qz) * inv;
      if (v < 0 || u + v > 1) continue;
      final t = (e2x * qx + e2y * qy + e2z * qz) * inv;
      if (t > 0 && t < bestT) {
        bestT = t;
        bestFace = f;
      }
    }
    if (bestFace >= 0) {
      return (
        ox + dx * bestT,
        oy + dy * bestT,
        oz + dz * bestT,
        body.particlePiece[faces[bestFace * 3]],
      );
    }

    const radiusPx = 36.0;
    var best = -1;
    var bestScore = double.infinity;
    for (var i = 0; i < body.numParticles; i++) {
      if (body.isSurface[i] == 0) continue;
      cam.project(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2], _proj, 0);
      final ddx = _proj[0] - sx, ddy = _proj[1] - sy;
      final d = math.sqrt(ddx * ddx + ddy * ddy);
      if (d > radiusPx) continue;
      final score = d + _proj[2] * 4;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (best < 0) return null;
    return (
      pos[best * 3],
      pos[best * 3 + 1],
      pos[best * 3 + 2],
      body.particlePiece[best],
    );
  }

  //* --- [ Knife Tool ] ---

  final Float64List _rayB = Float64List(3);

  /// Slices along the screen segment (ax, ay) → (bx, by). The cut plane holds
  /// the camera eye and both screen rays; only geometry under the swipe is cut.
  CutResult cut(JellyCamera cam, double ax, double ay, double bx, double by) {
    final sdx = bx - ax, sdy = by - ay;
    final len2 = sdx * sdx + sdy * sdy;
    if (len2 < 24 * 24) return CutResult.none;
    endGrab();

    cam.rayDirection(ax, ay, _ray);
    cam.rayDirection(bx, by, _rayB);
    var nx = _ray[1] * _rayB[2] - _ray[2] * _rayB[1];
    var ny = _ray[2] * _rayB[0] - _ray[0] * _rayB[2];
    var nz = _ray[0] * _rayB[1] - _ray[1] * _rayB[0];
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nl < 1e-9) return CutResult.none;
    nx /= nl;
    ny /= nl;
    nz /= nl;
    final d = nx * cam.eyeX + ny * cam.eyeY + nz * cam.eyeZ;

    bool inRange(double x, double y, double z) {
      cam.project(x, y, z, _proj, 0);
      final t = ((_proj[0] - ax) * sdx + (_proj[1] - ay) * sdy) / len2;
      return t >= -0.03 && t <= 1.03;
    }

    final result = JellyCutter.cut(
      body,
      nx: nx,
      ny: ny,
      nz: nz,
      d: d,
      inRange: inRange,
    );
    debugPrint(
      '✅ (APP LOGS) [cut] : pieces -> '
      '${result.piecesBefore} → ${body.numPieces} '
      '(split ${result.splitParticles})',
    );
    return result;
  }

  /// Chops straight down along the world ground line (ax, az) → (bx, bz),
  /// like a knife blade: a vertical cut plane, limited to the segment (plus
  /// a small margin) so only geometry under the blade is cut.
  CutResult sliceAlong(double ax, double az, double bx, double bz) {
    final dx = bx - ax, dz = bz - az;
    final len = math.sqrt(dx * dx + dz * dz);
    if (len < 0.05) return CutResult.none;
    endGrab();
    final ux = dx / len, uz = dz / len;
    final nx = -uz, nz = ux;
    final d = nx * ax + nz * az;
    const margin = 0.1;
    final result = JellyCutter.cut(
      body,
      nx: nx,
      ny: 0,
      nz: nz,
      d: d,
      inRange: (x, _, z) {
        final t = (x - ax) * ux + (z - az) * uz;
        return t >= -margin && t <= len + margin;
      },
      separation: 0.05,
      separationSpeed: 1.1,
    );
    debugPrint(
      '✅ (APP LOGS) [sliceAlong] : pieces -> '
      '${result.piecesBefore} → ${body.numPieces} '
      '(split ${result.splitParticles})',
    );
    return result;
  }

  /// Cuts with an explicit world plane `n · x = d` (used by tests/tools).
  CutResult cutWithPlane(double nx, double ny, double nz, double d) {
    endGrab();
    return JellyCutter.cut(
      body,
      nx: nx,
      ny: ny,
      nz: nz,
      d: d,
      inRange: (_, _, _) => true,
    );
  }

  //* --- [ Nudge ] ---

  /// Pops every piece upward with a slightly off-centre impulse so it lands
  /// unevenly and wobbles.
  void nudge() {
    final n = body.numParticles;
    if (n == 0) return;
    final pick = _random.nextInt(n);
    final px = body.pos[pick * 3], pz = body.pos[pick * 3 + 2];
    final sideX = (_random.nextDouble() - 0.5) * 1.2;
    final sideZ = (_random.nextDouble() - 0.5) * 1.2;
    for (var i = 0; i < n; i++) {
      if (body.invMass[i] == 0) continue;
      final dx = body.pos[i * 3] - px, dz = body.pos[i * 3 + 2] - pz;
      final falloff = math.exp(-(dx * dx + dz * dz) / 0.8);
      body.vel[i * 3] += sideX * falloff;
      body.vel[i * 3 + 1] += 3.4 * (0.55 + 0.9 * falloff);
      body.vel[i * 3 + 2] += sideZ * falloff;
    }
    debugPrint('✅ (APP LOGS) [nudge] : impulse at particle -> $pick');
  }

  //* --- [ Stats ] ---

  JellyStats computeStats() {
    const cm3PerUnit = unitCm * unitCm * unitCm;
    const kgPerSimMass = cm3PerUnit * gummyDensity / 1000;
    const metresPerUnit = unitCm / 100;
    var ke = 0.0;
    for (var i = 0; i < body.numParticles; i++) {
      final vx = body.vel[i * 3], vy = body.vel[i * 3 + 1];
      final vz = body.vel[i * 3 + 2];
      ke += 0.5 * body.mass[i] * (vx * vx + vy * vy + vz * vz);
    }
    final joules = ke * kgPerSimMass * metresPerUnit * metresPerUnit;
    return JellyStats(
      massGrams: body.totalRestVolume * cm3PerUnit * gummyDensity,
      volumePercent: body.currentVolume() / body.totalRestVolume * 100,
      kineticMicroJoules: joules * 1e6,
      pieces: body.numPieces,
      particles: body.numParticles,
      tetrahedra: body.numTets,
    );
  }
}
