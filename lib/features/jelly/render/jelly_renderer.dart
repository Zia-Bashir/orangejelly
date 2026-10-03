import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../physics/slice_mesh.dart';
import '../physics/soft_body.dart';
import 'jelly_camera.dart';
import 'jelly_material.dart';
import 'jelly_palette.dart';
import 'studio_light.dart';

//* --- [ Jelly Renderer ] ---

/// Software 3D pipeline on top of `Canvas.drawVertices`:
///
/// * smooth per-particle normals from the physics boundary faces,
/// * back-face culling + painter's-algorithm depth sort,
/// * every boundary triangle is re-tessellated ([subdivisions]²) as a curved
///   PN triangle (cubic Bézier patch from corner positions + normals), so the
///   coarse tet surface renders as a smooth, pillowy gummy with rounded edges
///   while the physics particle count stays unchanged,
/// * per-vertex studio shading: wrapped diffuse, subsurface glow on thin
///   flesh, Fresnel-weighted softbox / strip-light / sky reflections,
/// * per-piece ground shadows: wide ambient occlusion, light-cast shadow and
///   a tight dark contact line.
///
/// All buffers are reused between frames and only grow after cuts.
class JellyRenderer {
  JellyRenderer() {
    _buildSubdivisionTables();
  }

  static const int subdivisions = 8;
  static const int _subVerts = (subdivisions + 1) * (subdivisions + 2) ~/ 2;
  static const int _subTris = subdivisions * subdivisions;
  static const int _maxVertsPerDraw = 65000;
  static const int _stride = JellyMaterial.stride;

  /// Face-index slots packed under the depth in each sort key.
  static const double _faceSlots = 4194304;

  /// Shadow-casting direction (art-directed: falls down-right like the
  /// reference, independent of the key light used for shading).
  static const double shadowX = -0.34, shadowY = 0.88, shadowZ = -0.33;

  //* ---[ Subdivision tables ]---

  final Float32List _wb = Float32List(_subVerts);
  final Float32List _wc = Float32List(_subVerts);

  /// Cubic Bernstein weights per sub-vertex (10 per vertex, PN order).
  final Float64List _bern = Float64List(_subVerts * 10);
  final Uint16List _localTris = Uint16List(_subTris * 3);

  //* ---[ Caches ]---

  int _topologyVersion = -1;
  JellyPalette? _palette;
  JellyMaterial? _material;
  Float32List _albedo = Float32List(0);

  /// Per face: 1 when it lies on the material top surface.
  Uint8List _faceTop = Uint8List(0);

  /// Per top face: rest x̂ and ẑ in the face edge basis (αx, βx, αz, βz).
  Float32List _faceJ = Float32List(0);

  //* ---[ Seed decals ]---

  Int32List _lastTopDraw = Int32List(0);
  Int32List _seedFace = Int32List(0);
  Float64List _seedBary = Float64List(0);
  Float64List _seedDir = Float64List(0);
  final Float64List _proj = Float64List(3);
  final Paint _seedPaint = Paint()..blendMode = BlendMode.multiply;

  Float64List _normals = Float64List(0);

  /// Normals averaged over top faces only (no rim rounding baked in).
  Float64List _topNormals = Float64List(0);

  /// Per particle: 1 on the uncut top outline (analytic rounded edge).
  Uint8List _onOutline = Uint8List(0);
  Float64List _screen = Float64List(0);
  Float64List _castScreen = Float64List(0);
  Float64List _footScreen = Float64List(0);
  Float64List _sortKeys = Float64List(0);
  final Float64List _patch = Float64List(30);

  final Float32List _positions = Float32List(_maxVertsPerDraw * 2);
  final Int32List _colors = Int32List(_maxVertsPerDraw);
  final Uint16List _indices = Uint16List(
    (_maxVertsPerDraw ~/ _subVerts) * _subTris * 3,
  );
  Float32List _lines = Float32List(0);

  final Paint _vertexPaint = Paint();
  final Paint _meshPaint = Paint()
    ..color = const Color(0x5C1A1714)
    ..strokeWidth = 0.6
    ..strokeCap = StrokeCap.round;
  final Paint _shadowPaint = Paint();
  final List<int> _ids = <int>[];
  Int32List _hullStack = Int32List(0);

  /// Shaded sub-vertices emitted by the last [paint] (for perf probes).
  int lastVertexCount = 0;

  void _buildSubdivisionTables() {
    const n = subdivisions;
    int idx(int u, int v) {
      var i = 0;
      for (var uu = 0; uu < u; uu++) {
        i += n + 1 - uu;
      }
      return i + v;
    }

    for (var u = 0; u <= n; u++) {
      for (var v = 0; v <= n - u; v++) {
        final k = idx(u, v);
        final b = u / n, c = v / n, a = 1 - b - c;
        _wb[k] = b;
        _wc[k] = c;
        final o = k * 10;
        _bern[o] = a * a * a;
        _bern[o + 1] = b * b * b;
        _bern[o + 2] = c * c * c;
        _bern[o + 3] = 3 * a * a * b;
        _bern[o + 4] = 3 * a * b * b;
        _bern[o + 5] = 3 * a * a * c;
        _bern[o + 6] = 3 * b * b * c;
        _bern[o + 7] = 3 * a * c * c;
        _bern[o + 8] = 3 * b * c * c;
        _bern[o + 9] = 6 * a * b * c;
      }
    }
    var t = 0;
    for (var u = 0; u < n; u++) {
      for (var v = 0; v < n - u; v++) {
        _localTris[t++] = idx(u, v);
        _localTris[t++] = idx(u + 1, v);
        _localTris[t++] = idx(u, v + 1);
        if (v < n - 1 - u) {
          _localTris[t++] = idx(u + 1, v);
          _localTris[t++] = idx(u + 1, v + 1);
          _localTris[t++] = idx(u, v + 1);
        }
      }
    }
  }

  //* --- [ Paint ] ---

  /// Ground shadows + surface in one go (no knife interleaving).
  void paint(
    Canvas canvas,
    SoftBody body,
    JellyCamera cam,
    JellyPalette palette, {
    required bool showMesh,
  }) {
    paintShadows(canvas, body, cam, palette);
    paintSurface(canvas, body, cam, showMesh: showMesh);
  }

  /// Prepares per-frame buffers and paints the ground shadows. Must run
  /// before [paintSurface] each frame.
  void paintShadows(
    Canvas canvas,
    SoftBody body,
    JellyCamera cam,
    JellyPalette palette,
  ) {
    _ensureBuffers(body);
    _refreshMaterial(body, palette);
    _computeNormals(body);
    _projectParticles(body, cam);
    _paintShadows(canvas, body, cam, palette);
  }

  /// Paints the jelly surface (and optional mesh overlay).
  void paintSurface(
    Canvas canvas,
    SoftBody body,
    JellyCamera cam, {
    required bool showMesh,
  }) {
    final visible = _sortVisibleFaces(body, cam);
    _planSeedSlots(body, visible);
    _paintSurface(canvas, body, cam, visible);
    if (showMesh) _paintMesh(canvas, body, visible);
  }

  //* ---[ Buffers ]---

  void _ensureBuffers(SoftBody b) {
    if (_normals.length < b.capacity * 3) {
      _normals = Float64List(b.capacity * 3);
      _topNormals = Float64List(b.capacity * 3);
      _onOutline = Uint8List(b.capacity);
      _topologyVersion = -1;
      _screen = Float64List(b.capacity * 3);
      _castScreen = Float64List(b.capacity * 3);
      _footScreen = Float64List(b.capacity * 3);
    }
    if (_sortKeys.length < b.numFaces) {
      _sortKeys = Float64List(b.numFaces * 2);
      _lines = Float32List(b.numFaces * 2 * 12);
    }
  }

  void _refreshMaterial(SoftBody b, JellyPalette palette) {
    if (_topologyVersion == b.topologyVersion && identical(_palette, palette)) {
      return;
    }
    _topologyVersion = b.topologyVersion;
    if (!identical(_palette, palette)) {
      _palette = palette;
      _material = JellyMaterial(palette);
    }
    final material = _material!;
    if (_albedo.length < b.numFaces * _subVerts * _stride) {
      _albedo = Float32List(b.numFaces * _subVerts * _stride * 2);
    }
    if (_faceTop.length < b.numFaces) {
      _faceTop = Uint8List(b.numFaces * 2);
      _faceJ = Float32List(b.numFaces * 2 * 4);
    }
    final rest = b.rest, faces = b.faces;
    for (var i = 0; i < b.numParticles; i++) {
      final o = i * 3;
      _onOutline[i] =
          rest[o + 1] > SliceGeometry.thickness - 0.02 &&
              JellyMaterial.onTopOutline(rest[o], rest[o + 2])
          ? 1
          : 0;
    }
    for (var f = 0; f < b.numFaces; f++) {
      final a = faces[f * 3] * 3;
      final bb = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      final top = _isTopFace(rest, a, bb, c);
      _faceTop[f] = top ? 1 : 0;
      if (top) {
        // Rest x̂ / ẑ expressed in the face's edge basis (α e1 + β e2).
        final e1x = rest[bb] - rest[a], e1z = rest[bb + 2] - rest[a + 2];
        final e2x = rest[c] - rest[a], e2z = rest[c + 2] - rest[a + 2];
        final det = e1x * e2z - e2x * e1z;
        final inv = det.abs() < 1e-12 ? 0.0 : 1 / det;
        _faceJ[f * 4] = e2z * inv;
        _faceJ[f * 4 + 1] = -e1z * inv;
        _faceJ[f * 4 + 2] = -e2x * inv;
        _faceJ[f * 4 + 3] = e1x * inv;
      }
      for (var k = 0; k < _subVerts; k++) {
        final wb = _wb[k], wc = _wc[k], wa = 1 - wb - wc;
        material.evaluate(
          rest[a] * wa + rest[bb] * wb + rest[c] * wc,
          rest[a + 1] * wa + rest[bb + 1] * wb + rest[c + 1] * wc,
          rest[a + 2] * wa + rest[bb + 2] * wb + rest[c + 2] * wc,
          _albedo,
          (f * _subVerts + k) * _stride,
          topSurface: top,
        );
      }
    }
    _embedSeeds(b, material);
  }

  static bool _isTopFace(Float64List rest, int a, int b, int c) {
    const top = SliceGeometry.thickness - 0.02;
    return rest[a + 1] > top && rest[b + 1] > top && rest[c + 1] > top;
  }

  //* ---[ Seed embedding ]---

  /// Finds, for every seed, the top-surface triangle above it (in material
  /// x/z) and its barycentric weights, so decals ride the deforming surface.
  void _embedSeeds(SoftBody b, JellyMaterial material) {
    final seeds = material.seeds;
    final count = seeds.length ~/ 5;
    if (_seedFace.length != count) {
      _seedFace = Int32List(count);
      _seedBary = Float64List(count * 3);
      _seedDir = Float64List(count * 4);
    }
    _seedFace.fillRange(0, count, -1);
    final rest = b.rest, faces = b.faces;
    for (var f = 0; f < b.numFaces; f++) {
      final a = faces[f * 3] * 3;
      final bb = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      if (!_isTopFace(rest, a, bb, c)) continue;
      final e1x = rest[bb] - rest[a], e1z = rest[bb + 2] - rest[a + 2];
      final e2x = rest[c] - rest[a], e2z = rest[c + 2] - rest[a + 2];
      final det = e1x * e2z - e2x * e1z;
      if (det.abs() < 1e-12) continue;
      for (var s = 0; s < count; s++) {
        if (_seedFace[s] >= 0) continue;
        final px = seeds[s * 5] - rest[a], pz = seeds[s * 5 + 2] - rest[a + 2];
        final wb = (px * e2z - e2x * pz) / det;
        final wc = (e1x * pz - px * e1z) / det;
        if (wb < -1e-6 || wc < -1e-6 || wb + wc > 1 + 1e-6) continue;
        _seedFace[s] = f;
        _seedBary[s * 3] = 1 - wb - wc;
        _seedBary[s * 3 + 1] = wb;
        _seedBary[s * 3 + 2] = wc;
        // Seed axes expressed in the face's edge basis (α e1 + β e2).
        for (var k = 0; k < 2; k++) {
          final dx = k == 0 ? seeds[s * 5 + 3] : -seeds[s * 5 + 4];
          final dz = k == 0 ? seeds[s * 5 + 4] : seeds[s * 5 + 3];
          _seedDir[s * 4 + k * 2] = (dx * e2z - e2x * dz) / det;
          _seedDir[s * 4 + k * 2 + 1] = (e1x * dz - dx * e1z) / det;
        }
      }
    }
  }

  //* ---[ Normals + projection ]---

  void _computeNormals(SoftBody b) {
    final nrm = _normals, top = _topNormals, pos = b.pos, faces = b.faces;
    nrm.fillRange(0, b.numParticles * 3, 0);
    top.fillRange(0, b.numParticles * 3, 0);
    for (var f = 0; f < b.numFaces; f++) {
      final a = faces[f * 3] * 3;
      final bb = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      final e1x = pos[bb] - pos[a], e1y = pos[bb + 1] - pos[a + 1];
      final e1z = pos[bb + 2] - pos[a + 2];
      final e2x = pos[c] - pos[a], e2y = pos[c + 1] - pos[a + 1];
      final e2z = pos[c + 2] - pos[a + 2];
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      final out = _faceTop[f] == 1 ? 2 : 1;
      for (var pass = 0; pass < out; pass++) {
        final n = pass == 0 ? nrm : top;
        n[a] += nx;
        n[a + 1] += ny;
        n[a + 2] += nz;
        n[bb] += nx;
        n[bb + 1] += ny;
        n[bb + 2] += nz;
        n[c] += nx;
        n[c + 1] += ny;
        n[c + 2] += nz;
      }
    }
    _normalize(nrm, b.numParticles);
    _normalize(top, b.numParticles);
  }

  static void _normalize(Float64List n, int count) {
    for (var i = 0; i < count * 3; i += 3) {
      final l = math.sqrt(
        n[i] * n[i] + n[i + 1] * n[i + 1] + n[i + 2] * n[i + 2],
      );
      if (l > 1e-12) {
        n[i] /= l;
        n[i + 1] /= l;
        n[i + 2] /= l;
      }
    }
  }

  void _projectParticles(SoftBody b, JellyCamera cam) {
    final pos = b.pos;
    const kx = shadowX / shadowY, kz = shadowZ / shadowY;
    for (var i = 0; i < b.numParticles; i++) {
      final o = i * 3;
      final x = pos[o], y = pos[o + 1], z = pos[o + 2];
      cam.project(x, y, z, _screen, o);
      cam.project(x - kx * y, 0, z - kz * y, _castScreen, o);
      cam.project(x, 0, z, _footScreen, o);
    }
  }

  //* ---[ Visibility + depth sort ]---

  int _sortVisibleFaces(SoftBody b, JellyCamera cam) {
    final pos = b.pos, faces = b.faces, scr = _screen, nrm = _normals;
    var count = 0;
    for (var f = 0; f < b.numFaces; f++) {
      final ia = faces[f * 3], ib = faces[f * 3 + 1], ic = faces[f * 3 + 2];
      final a = ia * 3, bb = ib * 3, c = ic * 3;
      final e1x = pos[bb] - pos[a], e1y = pos[bb + 1] - pos[a + 1];
      final e1z = pos[bb + 2] - pos[a + 2];
      final e2x = pos[c] - pos[a], e2y = pos[c + 1] - pos[a + 1];
      final e2z = pos[c + 2] - pos[a + 2];
      final nx = e1y * e2z - e1z * e2y;
      final ny = e1z * e2x - e1x * e2z;
      final nz = e1x * e2y - e1y * e2x;
      final vx = cam.eyeX - pos[a], vy = cam.eyeY - pos[a + 1];
      final vz = cam.eyeZ - pos[a + 2];
      // Curved patches bulge past their flat face: keep faces whose
      // smoothed corner normals still see the eye (silhouette rounding).
      if (nx * vx + ny * vy + nz * vz <= 0 &&
          !_cornerSees(cam, pos, nrm, a) &&
          !_cornerSees(cam, pos, nrm, bb) &&
          !_cornerSees(cam, pos, nrm, c)) {
        continue;
      }
      final depth = scr[a + 2] + scr[bb + 2] + scr[c + 2];
      _sortKeys[count++] = (depth * 2000).floorToDouble() * _faceSlots + f;
    }
    Float64List.sublistView(_sortKeys, 0, count).sort();
    return count;
  }

  static bool _cornerSees(
    JellyCamera cam,
    Float64List pos,
    Float64List nrm,
    int o,
  ) =>
      nrm[o] * (cam.eyeX - pos[o]) +
          nrm[o + 1] * (cam.eyeY - pos[o + 1]) +
          nrm[o + 2] * (cam.eyeZ - pos[o + 2]) >
      0;

  //* --- [ Surface ] ---

  void _paintSurface(Canvas canvas, SoftBody b, JellyCamera cam, int count) {
    final pos = b.pos, faces = b.faces, nrm = _normals;
    final albedo = _albedo, bern = _bern, patch = _patch;
    final ex = cam.eyeX, ey = cam.eyeY, ez = cam.eyeZ;
    final cfx = cam.fx, cfy = cam.fy, cfz = cam.fz;
    final crx = cam.rx, cry = cam.ry, crz = cam.rz;
    final cux = cam.ux, cuy = cam.uy, cuz = cam.uz;
    final focal = cam.pixelsPerUnit * cam.distance;
    final ccx = cam.centerX, ccy = cam.centerY;
    var vCount = 0;
    var iCount = 0;
    var total = 0;

    for (var s = count - 1; s >= 0; s--) {
      if (vCount + _subVerts > _maxVertsPerDraw) {
        _flush(canvas, vCount, iCount);
        vCount = 0;
        iCount = 0;
      }
      final f = (_sortKeys[s] % _faceSlots).toInt();
      final a = faces[f * 3] * 3;
      final bb = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      _buildPatch(pos, nrm, a, bb, c, patch);
      final base = vCount;
      final colorBase = f * _subVerts * _stride;

      // World directions of rest x̂ / ẑ on this face (for the pillow dome).
      var jxx = 0.0, jxy = 0.0, jxz = 0.0, jzx = 0.0, jzy = 0.0, jzz = 0.0;
      final top = _faceTop[f] == 1;
      if (top) {
        final e1x = pos[bb] - pos[a], e1y = pos[bb + 1] - pos[a + 1];
        final e1z = pos[bb + 2] - pos[a + 2];
        final e2x = pos[c] - pos[a], e2y = pos[c + 1] - pos[a + 1];
        final e2z = pos[c + 2] - pos[a + 2];
        final ax = _faceJ[f * 4], bx = _faceJ[f * 4 + 1];
        final az = _faceJ[f * 4 + 2], bz = _faceJ[f * 4 + 3];
        jxx = ax * e1x + bx * e2x;
        jxy = ax * e1y + bx * e2y;
        jxz = ax * e1z + bx * e2z;
        jzx = az * e1x + bz * e2x;
        jzy = az * e1y + bz * e2y;
        jzz = az * e1z + bz * e2z;
      }

      // Shading normals per corner. On the uncut top outline the analytic
      // edge slope supplies the rounding, so start from top-only normals
      // (mesh-averaged rim normals would zig-zag across the triangulation).
      final na = top && _onOutline[a ~/ 3] == 1 ? _topNormals : nrm;
      final nb = top && _onOutline[bb ~/ 3] == 1 ? _topNormals : nrm;
      final nc = top && _onOutline[c ~/ 3] == 1 ? _topNormals : nrm;
      final n1x = na[a], n1y = na[a + 1], n1z = na[a + 2];
      final n2x = nb[bb], n2y = nb[bb + 1], n2z = nb[bb + 2];
      final n3x = nc[c], n3y = nc[c + 1], n3z = nc[c + 2];

      for (var k = 0; k < _subVerts; k++) {
        final wb = _wb[k], wc = _wc[k], wa = 1 - wb - wc;
        final o = k * 10;

        //* ---[ Curved position ]---

        var px = 0.0, py = 0.0, pz = 0.0;
        for (var q = 0; q < 10; q++) {
          final w = bern[o + q];
          px += patch[q * 3] * w;
          py += patch[q * 3 + 1] * w;
          pz += patch[q * 3 + 2] * w;
        }

        //* ---[ Projection ]---

        final dx = px - ex, dy = py - ey, dz = pz - ez;
        final depth = math.max(1e-3, dx * cfx + dy * cfy + dz * cfz);
        final kk = focal / depth;
        _positions[vCount * 2] = ccx + (dx * crx + dy * cry + dz * crz) * kk;
        _positions[vCount * 2 + 1] =
            ccy - (dx * cux + dy * cuy + dz * cuz) * kk;

        //* ---[ Shading ]---

        var nx = n1x * wa + n2x * wb + n3x * wc;
        var ny = n1y * wa + n2y * wb + n3y * wc;
        var nz = n1z * wa + n2z * wb + n3z * wc;
        final ci = colorBase + k * _stride;
        if (top) {
          final gx = albedo[ci + 4], gz = albedo[ci + 5];
          nx -= gx * jxx + gz * jzx;
          ny -= gx * jxy + gz * jzy;
          nz -= gx * jxz + gz * jzz;
        }
        final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (nl > 1e-9) {
          nx /= nl;
          ny /= nl;
          nz /= nl;
        }
        final vl = math.sqrt(dx * dx + dy * dy + dz * dz);
        _colors[vCount] = _shade(
          albedo[ci],
          albedo[ci + 1],
          albedo[ci + 2],
          albedo[ci + 3],
          nx,
          ny,
          nz,
          -dx / vl,
          -dy / vl,
          -dz / vl,
        );
        vCount++;
      }
      for (var t = 0; t < _subTris * 3; t++) {
        _indices[iCount++] = base + _localTris[t];
      }
      total += _subVerts;
      final piece = b.particlePiece[faces[f * 3]];
      if (piece < _lastTopDraw.length && _lastTopDraw[piece] == s) {
        _flush(canvas, vCount, iCount);
        vCount = 0;
        iCount = 0;
        _paintSeeds(canvas, b, cam, piece);
      }
    }
    _flush(canvas, vCount, iCount);
    lastVertexCount = total;
  }

  /// Records, per piece, the sort slot of its last-drawn top face: seed
  /// decals go right after it, above every top face but under anything
  /// drawn later (closer rims, pieces in front).
  void _planSeedSlots(SoftBody b, int count) {
    if (_lastTopDraw.length < b.numPieces) {
      _lastTopDraw = Int32List(b.numPieces * 2);
    }
    _lastTopDraw.fillRange(0, _lastTopDraw.length, -1);
    final rest = b.rest, faces = b.faces;
    for (var s = count - 1; s >= 0; s--) {
      final f = (_sortKeys[s] % _faceSlots).toInt();
      final a = faces[f * 3] * 3;
      if (!_isTopFace(rest, a, faces[f * 3 + 1] * 3, faces[f * 3 + 2] * 3)) {
        continue;
      }
      _lastTopDraw[b.particlePiece[faces[f * 3]]] = s;
    }
  }

  /// Soft teardrop decals for the seeds embedded under [piece]'s top,
  /// multiplied into the shaded surface so the gloss above them survives.
  void _paintSeeds(Canvas canvas, SoftBody body, JellyCamera cam, int piece) {
    final pos = body.pos, patch = _patch, faces = body.faces;
    final seedColor = _palette!.seed;
    final tint = Color.from(
      alpha: 1,
      red: seedColor.r * 0.8 + 0.12,
      green: seedColor.g * 0.8 + 0.05,
      blue: seedColor.b * 0.8 + 0.05,
    );
    for (var s = 0; s < _seedFace.length; s++) {
      final f = _seedFace[s];
      if (f < 0 || body.particlePiece[faces[f * 3]] != piece) continue;
      final a = faces[f * 3] * 3;
      final b = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      _buildPatch(pos, _normals, a, b, c, patch);
      final wa = _seedBary[s * 3], wb = _seedBary[s * 3 + 1];
      final wc = _seedBary[s * 3 + 2];

      //* ---[ Centre on the curved patch ]---

      final bw = [
        wa * wa * wa,
        wb * wb * wb,
        wc * wc * wc,
        3 * wa * wa * wb,
        3 * wa * wb * wb,
        3 * wa * wa * wc,
        3 * wb * wb * wc,
        3 * wa * wc * wc,
        3 * wb * wc * wc,
        6 * wa * wb * wc,
      ];
      var cx = 0.0, cy = 0.0, cz = 0.0;
      for (var q = 0; q < 10; q++) {
        cx += patch[q * 3] * bw[q];
        cy += patch[q * 3 + 1] * bw[q];
        cz += patch[q * 3 + 2] * bw[q];
      }

      //* ---[ Deformed seed axes ]---

      final e1x = pos[b] - pos[a], e1y = pos[b + 1] - pos[a + 1];
      final e1z = pos[b + 2] - pos[a + 2];
      final e2x = pos[c] - pos[a], e2y = pos[c + 1] - pos[a + 1];
      final e2z = pos[c + 2] - pos[a + 2];
      const len = JellyMaterial.seedLength * 0.85;
      const wid = JellyMaterial.seedWidth * 0.85;
      final al = _seedDir[s * 4] * len, be = _seedDir[s * 4 + 1] * len;
      final ac = _seedDir[s * 4 + 2] * wid, bc = _seedDir[s * 4 + 3] * wid;

      cam.project(cx, cy, cz, _proj, 0);
      final sx = _proj[0], sy = _proj[1];
      cam.project(
        cx + e1x * al + e2x * be,
        cy + e1y * al + e2y * be,
        cz + e1z * al + e2z * be,
        _proj,
        0,
      );
      final ux = _proj[0] - sx, uy = _proj[1] - sy;
      cam.project(
        cx + e1x * ac + e2x * bc,
        cy + e1y * ac + e2y * bc,
        cz + e1z * ac + e2z * bc,
        _proj,
        0,
      );
      final vx = _proj[0] - sx, vy = _proj[1] - sy;

      //* ---[ Teardrop ]---

      final path = Path();
      const steps = 18;
      for (var i = 0; i <= steps; i++) {
        final th = 2 * math.pi * i / steps;
        final u = math.cos(th);
        final v = math.sin(th) * (0.3 + 0.7 * math.sqrt((1 + u) / 2));
        final px = sx + u * ux + v * vx, py = sy + u * uy + v * vy;
        i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
      }
      path.close();
      final minor = math.sqrt(vx * vx + vy * vy);
      _seedPaint
        ..color = tint.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.8 + minor * 0.9);
      canvas.drawPath(path, _seedPaint);
      _seedPaint
        ..color = tint
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 + minor * 0.3);
      canvas.drawPath(path, _seedPaint);
    }
  }

  /// PN-triangle control net (10 points × xyz) for corners a, b, c.
  static void _buildPatch(
    Float64List p,
    Float64List n,
    int a,
    int b,
    int c,
    Float64List out,
  ) {
    for (var d = 0; d < 3; d++) {
      out[d] = p[a + d];
      out[3 + d] = p[b + d];
      out[6 + d] = p[c + d];
    }
    // Edge control points: (2Pi + Pj − ((Pj − Pi)·Ni) Ni) / 3.
    void edge(int slot, int i, int j) {
      final w =
          (p[j] - p[i]) * n[i] +
          (p[j + 1] - p[i + 1]) * n[i + 1] +
          (p[j + 2] - p[i + 2]) * n[i + 2];
      for (var d = 0; d < 3; d++) {
        out[slot * 3 + d] = (2 * p[i + d] + p[j + d] - w * n[i + d]) / 3;
      }
    }

    edge(3, a, b); // b210
    edge(4, b, a); // b120
    edge(5, a, c); // b201
    edge(6, b, c); // b021
    edge(7, c, a); // b102
    edge(8, c, b); // b012
    for (var d = 0; d < 3; d++) {
      var e = 0.0;
      for (var q = 3; q < 9; q++) {
        e += out[q * 3 + d];
      }
      e /= 6;
      final v = (p[a + d] + p[b + d] + p[c + d]) / 3;
      out[27 + d] = e + (e - v) / 2; // b111
    }
  }

  void _flush(Canvas canvas, int vCount, int iCount) {
    if (iCount == 0) return;
    final vertices = Vertices.raw(
      VertexMode.triangles,
      Float32List.sublistView(_positions, 0, vCount * 2),
      colors: Int32List.sublistView(_colors, 0, vCount),
      indices: Uint16List.sublistView(_indices, 0, iCount),
    );
    canvas.drawVertices(vertices, BlendMode.dst, _vertexPaint);
    vertices.dispose();
  }

  /// Studio shading for one gummy surface sample, packed to ARGB.
  static int _shade(
    double r,
    double g,
    double b,
    double glow,
    double nx,
    double ny,
    double nz,
    double vx,
    double vy,
    double vz,
  ) {
    const lx = StudioLight.lx, ly = StudioLight.ly, lz = StudioLight.lz;
    final ndl = nx * lx + ny * ly + nz * lz;
    final wrap = math.max(0.0, (ndl + 0.45) / 1.45);
    final ndv = math.max(0.0, nx * vx + ny * vy + nz * vz);

    //* ---[ Diffuse + subsurface ]---

    final light = 0.34 + 0.62 * wrap + 0.08 * (ny * 0.5 + 0.5);
    // Light scattered inside the gummy: saturated bleed into the shade side.
    final sss = (1 - wrap) * 0.22;
    // Thin, translucent flesh glows lighter / pinker, most at grazing view.
    final edge = 1 - ndv;
    final glowAmt = glow * (0.10 + 0.40 * edge * edge) * (0.6 + 0.4 * wrap);

    //* ---[ Reflections ]---

    final f = StudioLight.fresnel(ndv);
    final d2 = 2 * ndv;
    final spec = StudioLight.reflect(
      d2 * nx - vx,
      d2 * ny - vy,
      d2 * nz - vz,
      f,
    );

    final outR = r * light + r * r * sss + (r * 0.5 + 0.5) * glowAmt + spec;
    final outG = g * light + g * g * sss + (g * 0.5 + 0.42) * glowAmt + spec;
    final outB = b * light + b * b * sss + (b * 0.5 + 0.45) * glowAmt + spec;
    return 0xFF000000 | (_to8(outR) << 16) | (_to8(outG) << 8) | _to8(outB);
  }

  static int _to8(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).toInt());

  //* --- [ Shadows ] ---

  void _paintShadows(
    Canvas canvas,
    SoftBody b,
    JellyCamera cam,
    JellyPalette palette,
  ) {
    final ppu = cam.pixelsPerUnit;
    final pos = b.pos;
    for (var piece = 0; piece < b.numPieces; piece++) {
      _ids.clear();
      var minY = double.infinity;
      for (var i = 0; i < b.numParticles; i++) {
        if (b.particlePiece[i] != piece) continue;
        _ids.add(i);
        minY = math.min(minY, pos[i * 3 + 1]);
      }
      if (_ids.length < 3) continue;
      final lift = 1 / (1 + math.max(0.0, minY) * 2.2);

      //* ---[ Wide ambient occlusion ]---

      final foot = _hull(_ids, _footScreen);
      if (foot != null) {
        _shadowPaint
          ..color = const Color(0xFF3A2C26).withValues(alpha: 0.16 * lift)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ppu * 0.42);
        canvas.drawPath(foot, _shadowPaint);
      }

      //* ---[ Light-cast shadow ]---

      final cast = _hull(_ids, _castScreen);
      if (cast != null) {
        _shadowPaint
          ..color = palette.shadowTint.withValues(alpha: 0.20 * lift)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ppu * 0.26);
        canvas.drawPath(cast, _shadowPaint);
        _shadowPaint
          ..color = const Color(0xFF2A1A16).withValues(alpha: 0.22 * lift)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            ppu * (0.12 + math.max(0.0, minY) * 0.3),
          );
        canvas.drawPath(cast, _shadowPaint);
      }

      //* ---[ Contact line ]---

      if (foot != null && minY < 0.08) {
        _shadowPaint
          ..color = const Color(
            0xFF1E1410,
          ).withValues(alpha: 0.55 * (1 - minY / 0.08))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ppu * 0.035);
        canvas.drawPath(foot, _shadowPaint);
      }
    }
  }

  /// Monotone-chain convex hull of particle [ids] in screen buffer [scr].
  Path? _hull(List<int> ids, Float64List scr) {
    final count = ids.length;
    if (count < 3) return null;
    ids.sort((i, j) {
      final dx = scr[i * 3] - scr[j * 3];
      if (dx != 0) return dx < 0 ? -1 : 1;
      final dy = scr[i * 3 + 1] - scr[j * 3 + 1];
      return dy < 0 ? -1 : (dy > 0 ? 1 : 0);
    });
    if (_hullStack.length < count * 2 + 1) {
      _hullStack = Int32List(count * 4 + 2);
    }
    final stack = _hullStack;
    var k = 0;
    double cross(int o, int a, int b) =>
        (scr[a * 3] - scr[o * 3]) * (scr[b * 3 + 1] - scr[o * 3 + 1]) -
        (scr[a * 3 + 1] - scr[o * 3 + 1]) * (scr[b * 3] - scr[o * 3]);
    for (var i = 0; i < count; i++) {
      final p = ids[i];
      while (k >= 2 && cross(stack[k - 2], stack[k - 1], p) <= 0) {
        k--;
      }
      stack[k++] = p;
    }
    final lower = k + 1;
    for (var i = count - 2; i >= 0; i--) {
      final p = ids[i];
      while (k >= lower && cross(stack[k - 2], stack[k - 1], p) <= 0) {
        k--;
      }
      stack[k++] = p;
    }
    if (k < 4) return null;
    final path = Path()..moveTo(scr[stack[0] * 3], scr[stack[0] * 3 + 1]);
    for (var i = 1; i < k - 1; i++) {
      path.lineTo(scr[stack[i] * 3], scr[stack[i] * 3 + 1]);
    }
    return path..close();
  }

  //* --- [ Mesh Overlay ] ---

  void _paintMesh(Canvas canvas, SoftBody b, int count) {
    final faces = b.faces, scr = _screen;
    var o = 0;
    for (var s = 0; s < count; s++) {
      final f = (_sortKeys[s] % _faceSlots).toInt();
      final a = faces[f * 3] * 3;
      final bb = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      o = _line(o, scr, a, bb);
      o = _line(o, scr, bb, c);
      o = _line(o, scr, c, a);
    }
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(_lines, 0, o),
      _meshPaint,
    );
  }

  int _line(int o, Float64List scr, int p, int q) {
    _lines[o] = scr[p];
    _lines[o + 1] = scr[p + 1];
    _lines[o + 2] = scr[q];
    _lines[o + 3] = scr[q + 1];
    return o + 4;
  }
}
