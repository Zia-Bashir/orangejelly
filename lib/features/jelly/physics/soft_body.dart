import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'slice_mesh.dart';

//* --- [ Soft Body ] ---

/// Flat-buffer tetrahedral soft body.
///
/// Particle buffers are sized to [capacity] and only grow when a cut needs to
/// duplicate particles, so stepping never allocates. Topology (edges, surface
/// faces, pieces) is rebuilt only after construction or a cut.
class SoftBody {
  SoftBody.fromMesh(TetMesh mesh, {this.density = 1.0})
    : capacity = mesh.numParticles * 3,
      numParticles = mesh.numParticles {
    _allocateParticles(capacity);
    rest.setRange(0, mesh.restPositions.length, mesh.restPositions);
    pos.setRange(0, mesh.worldPositions.length, mesh.worldPositions);
    prev.setRange(0, mesh.worldPositions.length, mesh.worldPositions);
    tets = Int32List.fromList(mesh.tets);
    numTets = mesh.numTets;
    rebuildTopology();
    originalRestVolume = totalRestVolume;
  }

  final double density;

  int capacity;
  int numParticles;

  //* ---[ Particle buffers ]---

  late Float64List pos;
  late Float64List prev;
  late Float64List vel;
  late Float64List rest;
  late Float64List mass;
  late Float64List invMass;
  late Int32List particlePiece;
  late Uint8List isSurface;

  //* ---[ Topology ]---

  late Int32List tets;
  int numTets = 0;
  Float64List tetRestVolume = Float64List(0);
  Int32List tetPiece = Int32List(0);

  Int32List edges = Int32List(0);
  Float64List edgeRestLength = Float64List(0);
  int numEdges = 0;

  /// Outward-wound boundary triangles (3 particle ids each).
  Int32List faces = Int32List(0);
  int numFaces = 0;

  int numPieces = 0;
  double totalRestVolume = 0;
  double originalRestVolume = 0;

  /// Incremented on every topology rebuild so renderers can refresh caches.
  int topologyVersion = 0;

  /// Outward faces of a positively oriented tet, as local vertex triples.
  static const List<List<int>> tetFaces = [
    [0, 2, 1],
    [0, 1, 3],
    [0, 3, 2],
    [1, 2, 3],
  ];

  //* --- [ Capacity ] ---

  void _allocateParticles(int cap) {
    pos = Float64List(cap * 3);
    prev = Float64List(cap * 3);
    vel = Float64List(cap * 3);
    rest = Float64List(cap * 3);
    mass = Float64List(cap);
    invMass = Float64List(cap);
    particlePiece = Int32List(cap);
    isSurface = Uint8List(cap);
  }

  void ensureCapacity(int needed) {
    if (needed <= capacity) return;
    var cap = capacity;
    while (cap < needed) {
      cap *= 2;
    }
    final oPos = pos, oPrev = prev, oVel = vel, oRest = rest;
    final oMass = mass, oInv = invMass, oPiece = particlePiece;
    final oSurf = isSurface;
    _allocateParticles(cap);
    pos.setRange(0, numParticles * 3, oPos);
    prev.setRange(0, numParticles * 3, oPrev);
    vel.setRange(0, numParticles * 3, oVel);
    rest.setRange(0, numParticles * 3, oRest);
    mass.setRange(0, numParticles, oMass);
    invMass.setRange(0, numParticles, oInv);
    particlePiece.setRange(0, numParticles, oPiece);
    isSurface.setRange(0, numParticles, oSurf);
    capacity = cap;
  }

  /// Creates a copy of particle [p] (same state + material coordinate).
  int duplicateParticle(int p) {
    ensureCapacity(numParticles + 1);
    final q = numParticles++;
    for (var k = 0; k < 3; k++) {
      pos[q * 3 + k] = pos[p * 3 + k];
      prev[q * 3 + k] = prev[p * 3 + k];
      vel[q * 3 + k] = vel[p * 3 + k];
      rest[q * 3 + k] = rest[p * 3 + k];
    }
    mass[q] = mass[p];
    invMass[q] = invMass[p];
    return q;
  }

  //* --- [ Geometry ] ---

  static double signedVolume(Float64List p, int i0, int i1, int i2, int i3) {
    final a = i0 * 3, b = i1 * 3, c = i2 * 3, d = i3 * 3;
    final ax = p[b] - p[a], ay = p[b + 1] - p[a + 1], az = p[b + 2] - p[a + 2];
    final bx = p[c] - p[a], by = p[c + 1] - p[a + 1], bz = p[c + 2] - p[a + 2];
    final cx = p[d] - p[a], cy = p[d + 1] - p[a + 1], cz = p[d + 2] - p[a + 2];
    return ((ay * bz - az * by) * cx +
            (az * bx - ax * bz) * cy +
            (ax * by - ay * bx) * cz) /
        6;
  }

  double tetVolume(int t) => signedVolume(
    pos,
    tets[t * 4],
    tets[t * 4 + 1],
    tets[t * 4 + 2],
    tets[t * 4 + 3],
  );

  double currentVolume() {
    var v = 0.0;
    for (var t = 0; t < numTets; t++) {
      v += tetVolume(t);
    }
    return v;
  }

  //* --- [ Topology Rebuild ] ---

  /// Recomputes rest volumes, masses, edges, boundary faces and pieces from
  /// the current tet list and material coordinates.
  void rebuildTopology() {
    final n = numParticles;

    //* ---[ Rest volumes + masses ]---

    tetRestVolume = Float64List(numTets);
    mass.fillRange(0, n, 0);
    totalRestVolume = 0;
    for (var t = 0; t < numTets; t++) {
      var v = signedVolume(
        rest,
        tets[t * 4],
        tets[t * 4 + 1],
        tets[t * 4 + 2],
        tets[t * 4 + 3],
      );
      if (v < 0) {
        final tmp = tets[t * 4 + 2];
        tets[t * 4 + 2] = tets[t * 4 + 3];
        tets[t * 4 + 3] = tmp;
        v = -v;
      }
      tetRestVolume[t] = v;
      totalRestVolume += v;
      final share = v * density / 4;
      for (var k = 0; k < 4; k++) {
        mass[tets[t * 4 + k]] += share;
      }
    }
    for (var i = 0; i < n; i++) {
      invMass[i] = mass[i] > 0 ? 1 / mass[i] : 0;
    }

    //* ---[ Edges ]---

    final edgeKeys = HashSet<int>();
    final edgeList = <int>[];
    const pairs = [
      [0, 1],
      [0, 2],
      [0, 3],
      [1, 2],
      [1, 3],
      [2, 3],
    ];
    for (var t = 0; t < numTets; t++) {
      for (final pr in pairs) {
        var a = tets[t * 4 + pr[0]];
        var b = tets[t * 4 + pr[1]];
        if (a > b) {
          final tmp = a;
          a = b;
          b = tmp;
        }
        if (edgeKeys.add(a * n + b)) {
          edgeList
            ..add(a)
            ..add(b);
        }
      }
    }
    edges = Int32List.fromList(edgeList);
    numEdges = edgeList.length ~/ 2;
    edgeRestLength = Float64List(numEdges);
    for (var e = 0; e < numEdges; e++) {
      final a = edges[e * 2] * 3;
      final b = edges[e * 2 + 1] * 3;
      final dx = rest[a] - rest[b];
      final dy = rest[a + 1] - rest[b + 1];
      final dz = rest[a + 2] - rest[b + 2];
      edgeRestLength[e] = _sqrt(dx * dx + dy * dy + dz * dz);
    }

    //* ---[ Boundary faces ]---

    final faceOwner = HashMap<int, int>();
    for (var t = 0; t < numTets; t++) {
      for (var f = 0; f < 4; f++) {
        final key = faceKey(t, f);
        final existing = faceOwner[key];
        faceOwner[key] = existing == null ? t * 4 + f : -1;
      }
    }
    final faceList = <int>[];
    isSurface.fillRange(0, n, 0);
    for (final owner in faceOwner.values) {
      if (owner < 0) continue;
      final t = owner ~/ 4;
      final local = tetFaces[owner % 4];
      for (final l in local) {
        final id = tets[t * 4 + l];
        faceList.add(id);
        isSurface[id] = 1;
      }
    }
    faces = Int32List.fromList(faceList);
    numFaces = faceList.length ~/ 3;

    //* ---[ Pieces (connected components) ]---

    final parent = Int32List(n);
    for (var i = 0; i < n; i++) {
      parent[i] = i;
    }
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    for (var t = 0; t < numTets; t++) {
      final r0 = find(tets[t * 4]);
      for (var k = 1; k < 4; k++) {
        final rk = find(tets[t * 4 + k]);
        if (rk != r0) parent[rk] = r0;
      }
    }
    final label = Int32List(n)..fillRange(0, n, -1);
    numPieces = 0;
    for (var i = 0; i < n; i++) {
      final r = find(i);
      if (label[r] < 0) label[r] = numPieces++;
      particlePiece[i] = label[r];
    }
    tetPiece = Int32List(numTets);
    for (var t = 0; t < numTets; t++) {
      tetPiece[t] = particlePiece[tets[t * 4]];
    }

    topologyVersion++;
  }

  /// Order-independent key for local face [f] of tet [t].
  int faceKey(int t, int f) => faceKeyOf(tets, t, f, numParticles);

  static int faceKeyOf(Int32List tets, int t, int f, int n) {
    final local = tetFaces[f];
    var a = tets[t * 4 + local[0]];
    var b = tets[t * 4 + local[1]];
    var c = tets[t * 4 + local[2]];
    int tmp;
    if (a > b) {
      tmp = a;
      a = b;
      b = tmp;
    }
    if (b > c) {
      tmp = b;
      b = c;
      c = tmp;
    }
    if (a > b) {
      tmp = a;
      a = b;
      b = tmp;
    }
    return (a * n + b) * n + c;
  }

  static double _sqrt(double v) => v <= 0 ? 0 : math.sqrt(v);
}
