import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../physics/soft_body.dart';
import 'jelly_camera.dart';
import 'jelly_material.dart';
import 'jelly_palette.dart';

//* --- [ Jelly Renderer ] ---

/// Software 3D pipeline on top of `Canvas.drawVertices`:
///
/// * smooth per-particle normals from boundary faces,
/// * back-face culling + painter's-algorithm depth sort,
/// * each boundary triangle subdivided ([subdivisions]²) so the procedural
///   material (seeds, stripes, rind bands) has enough colour resolution,
/// * per-vertex wrapped Lambert + Blinn-Phong + rim light for a glossy,
///   slightly translucent gummy look,
/// * light-projected blurred ground shadows per piece.
///
/// All buffers are reused between frames and only grow after cuts.
class JellyRenderer {
  JellyRenderer() {
    _buildSubdivisionTables();
  }

  static const int subdivisions = 5;
  static const int _subVerts = (subdivisions + 1) * (subdivisions + 2) ~/ 2;
  static const int _subTris = subdivisions * subdivisions;
  static const int _maxVertsPerDraw = 65000;

  /// Face-index slots packed under the depth in each sort key.
  static const double _faceSlots = 4194304;

  //* ---[ Lights ]---

  static const double _lx = -0.38, _ly = 0.84, _lz = 0.39;
  static const double _fx = 0.72, _fy = 0.38, _fz = -0.58;

  /// Shadow-casting direction (art-directed: falls down-right like the
  /// reference, independent of the key light used for shading).
  static const double _sx = -0.34, _sy = 0.88, _sz = -0.33;

  //* ---[ Subdivision tables ]---

  final Float32List _wb = Float32List(_subVerts);
  final Float32List _wc = Float32List(_subVerts);
  final Uint16List _localTris = Uint16List(_subTris * 3);

  //* ---[ Caches ]---

  int _topologyVersion = -1;
  JellyPalette? _palette;
  JellyMaterial? _material;
  Float32List _faceColors = Float32List(0);

  Float64List _normals = Float64List(0);
  Float64List _screen = Float64List(0);
  Float64List _shadowScreen = Float64List(0);
  Float64List _sortKeys = Float64List(0);

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
  final List<int> _order = <int>[];

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
        _wb[idx(u, v)] = u / n;
        _wc[idx(u, v)] = v / n;
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

  void paint(
    Canvas canvas,
    SoftBody body,
    JellyCamera cam,
    JellyPalette palette, {
    required bool showMesh,
  }) {
    _ensureBuffers(body);
    _refreshMaterial(body, palette);
    _computeNormals(body);
    _projectParticles(body, cam);
    _paintShadows(canvas, body, cam, palette);
    final visible = _sortVisibleFaces(body, cam);
    _paintSurface(canvas, body, cam, visible);
    if (showMesh) _paintMesh(canvas, body, visible);
  }

  //* ---[ Buffers ]---

  void _ensureBuffers(SoftBody b) {
    if (_normals.length < b.capacity * 3) {
      _normals = Float64List(b.capacity * 3);
      _screen = Float64List(b.capacity * 3);
      _shadowScreen = Float64List(b.capacity * 3);
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
    if (_faceColors.length < b.numFaces * _subVerts * 3) {
      _faceColors = Float32List(b.numFaces * _subVerts * 3 * 2);
    }
    final rest = b.rest, faces = b.faces;
    for (var f = 0; f < b.numFaces; f++) {
      final a = faces[f * 3] * 3;
      final bb = faces[f * 3 + 1] * 3;
      final c = faces[f * 3 + 2] * 3;
      for (var k = 0; k < _subVerts; k++) {
        final wb = _wb[k], wc = _wc[k], wa = 1 - wb - wc;
        material.evaluate(
          rest[a] * wa + rest[bb] * wb + rest[c] * wc,
          rest[a + 1] * wa + rest[bb + 1] * wb + rest[c + 1] * wc,
          rest[a + 2] * wa + rest[bb + 2] * wb + rest[c + 2] * wc,
          _faceColors,
          (f * _subVerts + k) * 3,
        );
      }
    }
  }

  //* ---[ Normals + projection ]---

  void _computeNormals(SoftBody b) {
    final nrm = _normals, pos = b.pos, faces = b.faces;
    nrm.fillRange(0, b.numParticles * 3, 0);
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
      nrm[a] += nx;
      nrm[a + 1] += ny;
      nrm[a + 2] += nz;
      nrm[bb] += nx;
      nrm[bb + 1] += ny;
      nrm[bb + 2] += nz;
      nrm[c] += nx;
      nrm[c + 1] += ny;
      nrm[c + 2] += nz;
    }
    for (var i = 0; i < b.numParticles * 3; i += 3) {
      final l = math.sqrt(
        nrm[i] * nrm[i] + nrm[i + 1] * nrm[i + 1] + nrm[i + 2] * nrm[i + 2],
      );
      if (l > 1e-12) {
        nrm[i] /= l;
        nrm[i + 1] /= l;
        nrm[i + 2] /= l;
      }
    }
  }

  void _projectParticles(SoftBody b, JellyCamera cam) {
    final pos = b.pos;
    const kx = _sx / _sy, kz = _sz / _sy;
    for (var i = 0; i < b.numParticles; i++) {
      final o = i * 3;
      cam.project(pos[o], pos[o + 1], pos[o + 2], _screen, o);
      final y = pos[o + 1];
      cam.project(pos[o] - kx * y, 0, pos[o + 2] - kz * y, _shadowScreen, o);
    }
  }

  //* ---[ Visibility + depth sort ]---

  int _sortVisibleFaces(SoftBody b, JellyCamera cam) {
    final pos = b.pos, faces = b.faces, scr = _screen;
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
      if (nx * vx + ny * vy + nz * vz <= 0) continue;
      final depth = scr[a + 2] + scr[bb + 2] + scr[c + 2];
      _sortKeys[count++] = (depth * 2000).floorToDouble() * _faceSlots + f;
    }
    Float64List.sublistView(_sortKeys, 0, count).sort();
    return count;
  }

  //* --- [ Surface ] ---

  void _paintSurface(Canvas canvas, SoftBody b, JellyCamera cam, int count) {
    final pos = b.pos, faces = b.faces, scr = _screen, nrm = _normals;
    final colors = _faceColors;
    final ex = cam.eyeX, ey = cam.eyeY, ez = cam.eyeZ;
    var vCount = 0;
    var iCount = 0;

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
      final base = vCount;
      final colorBase = f * _subVerts * 3;

      for (var k = 0; k < _subVerts; k++) {
        final wb = _wb[k], wc = _wc[k], wa = 1 - wb - wc;
        _positions[vCount * 2] = scr[a] * wa + scr[bb] * wb + scr[c] * wc;
        _positions[vCount * 2 + 1] =
            scr[a + 1] * wa + scr[bb + 1] * wb + scr[c + 1] * wc;

        var nx = nrm[a] * wa + nrm[bb] * wb + nrm[c] * wc;
        var ny = nrm[a + 1] * wa + nrm[bb + 1] * wb + nrm[c + 1] * wc;
        var nz = nrm[a + 2] * wa + nrm[bb + 2] * wb + nrm[c + 2] * wc;
        final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (nl > 1e-9) {
          nx /= nl;
          ny /= nl;
          nz /= nl;
        }
        var vx = ex - (pos[a] * wa + pos[bb] * wb + pos[c] * wc);
        var vy = ey - (pos[a + 1] * wa + pos[bb + 1] * wb + pos[c + 1] * wc);
        var vz = ez - (pos[a + 2] * wa + pos[bb + 2] * wb + pos[c + 2] * wc);
        final vl = math.sqrt(vx * vx + vy * vy + vz * vz);
        vx /= vl;
        vy /= vl;
        vz /= vl;

        final ci = colorBase + k * 3;
        _colors[vCount] = _shade(
          colors[ci],
          colors[ci + 1],
          colors[ci + 2],
          nx,
          ny,
          nz,
          vx,
          vy,
          vz,
        );
        vCount++;
      }
      for (var t = 0; t < _subTris * 3; t++) {
        _indices[iCount++] = base + _localTris[t];
      }
    }
    _flush(canvas, vCount, iCount);
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

  /// Wrapped Lambert + fill + Blinn-Phong specular + rim, packed to ARGB.
  static int _shade(
    double r,
    double g,
    double b,
    double nx,
    double ny,
    double nz,
    double vx,
    double vy,
    double vz,
  ) {
    final ndl = nx * _lx + ny * _ly + nz * _lz;
    final wrap = math.max(0.0, (ndl + 0.35) / 1.35);
    final fill = math.max(0.0, nx * _fx + ny * _fy + nz * _fz) * 0.16;
    final ndv = math.max(0.0, nx * vx + ny * vy + nz * vz);

    var hx = _lx + vx, hy = _ly + vy, hz = _lz + vz;
    final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hl;
    hy /= hl;
    hz /= hl;
    final ndh = math.max(0.0, nx * hx + ny * hy + nz * hz);
    final h2 = ndh * ndh, h4 = h2 * h2, h8 = h4 * h4, h16 = h8 * h8;
    final h32 = h16 * h16;
    final spec = h32 * h32 * 0.95 + h8 * h4 * 0.10;

    final edge = 1 - ndv;
    final rim = edge * edge * edge * 0.30;
    final light = 0.36 + 0.68 * wrap + fill;
    // Subsurface tint: saturated body colour bleeds into the shadowed side.
    final sss = (1 - wrap) * 0.10;

    final outR = r * light + r * r * sss + rim * (0.55 * r + 0.45) + spec;
    final outG = g * light + g * g * sss + rim * (0.55 * g + 0.45) + spec;
    final outB = b * light + b * b * sss + rim * (0.55 * b + 0.45) + spec;
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
    final n = b.numParticles;
    final piece = b.particlePiece;
    final scr = _shadowScreen;
    _order
      ..clear()
      ..addAll(Iterable<int>.generate(n));
    _order.sort((i, j) {
      final pi = piece[i] - piece[j];
      if (pi != 0) return pi;
      final dx = scr[i * 3] - scr[j * 3];
      if (dx != 0) return dx < 0 ? -1 : 1;
      final dy = scr[i * 3 + 1] - scr[j * 3 + 1];
      return dy < 0 ? -1 : (dy > 0 ? 1 : 0);
    });

    final ppu = cam.pixelsPerUnit;
    var start = 0;
    while (start < n) {
      final p = piece[_order[start]];
      var end = start;
      var minY = double.infinity;
      while (end < n && piece[_order[end]] == p) {
        minY = math.min(minY, b.pos[_order[end] * 3 + 1]);
        end++;
      }
      final hull = _hull(start, end);
      if (hull != null) {
        final lift = 1 / (1 + minY * 1.6);
        _shadowPaint
          ..color = palette.shadowTint.withValues(alpha: 0.20 * lift)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ppu * 0.30);
        canvas.drawPath(hull, _shadowPaint);
        _shadowPaint
          ..color = const Color(0xFF2A1A16).withValues(alpha: 0.38 * lift)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            ppu * (0.08 + minY * 0.25),
          );
        canvas.drawPath(hull, _shadowPaint);
      }
      start = end;
    }
  }

  /// Monotone-chain convex hull of `_order[start, end)` in shadow space.
  Path? _hull(int start, int end) {
    final count = end - start;
    if (count < 3) return null;
    final scr = _shadowScreen;
    final stack = List<int>.filled(count * 2 + 1, 0);
    var k = 0;
    double cross(int o, int a, int b) =>
        (scr[a * 3] - scr[o * 3]) * (scr[b * 3 + 1] - scr[o * 3 + 1]) -
        (scr[a * 3 + 1] - scr[o * 3 + 1]) * (scr[b * 3] - scr[o * 3]);
    for (var i = start; i < end; i++) {
      final p = _order[i];
      while (k >= 2 && cross(stack[k - 2], stack[k - 1], p) <= 0) {
        k--;
      }
      stack[k++] = p;
    }
    final lower = k + 1;
    for (var i = end - 2; i >= start; i--) {
      final p = _order[i];
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
